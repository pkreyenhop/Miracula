//! syntax/directives.zig — scans `%`-directives into structured `Directive`
//! values (docs/ZIG_NATIVE_PLAN.md Phase 1 step 5, first half).
//!
//! `%` isn't a token in `syntax/lexer.zig` (deliberately deferred there):
//! legacy's `directive()` does its own specialised scanning after `%` — a
//! directive keyword (distinct from a plain identifier lookup), `"..."`/
//! `<...>` pathnames with different quoting rules than string literals (no
//! escape decoding — `okpath`'s raw-char rule), and a brace-delimited,
//! possibly multi-line binding/spec block for `%include`'s bindings and
//! `%free`'s signature. So this module scans directly over `Source` bytes,
//! not over `lexer.zig`'s token stream — it runs *before* tokenization of
//! the directive's own content (the bindings/spec block's `var = exp` /
//! `tform == type` grammar needs an expression/type parser that doesn't
//! fully exist in `syntax/` yet, so this step deliberately keeps it as raw
//! text — see the header note on scope).
//!
//! **Deliberately out of scope for this file** (recognized, not processed):
//! `%insert` (textual substitution — a `Source`-level concern, splicing
//! another file's bytes in place, not a token-level one), `%list`/`%nolist`
//! (REPL echo verbosity, irrelevant to a native batch compiler), `%bnf`/
//! `%lex`/`%begin` (the grammar-extension machinery, explicitly deferred to
//! last in the plan). All five come back as `.unsupported`.
//!
//! **Deliberately raw text, not deep-parsed:** `%include`'s binder block
//! (`{elem==num; zero=0; ...}`) and alias list, `%free`'s signature block,
//! and `%export`'s parts list. `semantics/modules.zig` (not yet built) will
//! parse these once it exists — see the plan's step-5 scoping note.
//! `%export`'s parts list is captured up to end-of-line; genuinely
//! multi-line export lists (not seen in the shipped `miralib` corpus) are a
//! known gap.
//!
//! Path resolution (`<...>` relative to miralib, `"..."` relative to the
//! including script's directory, `~` home-directory expansion) is also not
//! done here — `path`/`from_miralib` are captured verbatim; resolving them
//! needs interpreter context (`semantics/modules.zig` again).
//!
//! Not yet wired into `syntax/lexer.zig` or any parser — additive and
//! independently tested, same as `source.zig`/`lexer.zig`/`layout.zig` were
//! before their own integration.
//!
//! Tests: Scanner.scanDirective — one test per directive form, drawn from
//! docs/man/mira.man.ms §27's worked examples where possible.

const std = @import("std");
const Source = @import("source.zig").Source;
const tf = @import("../parser/token_filter.zig");
const Span = tf.Span;

/// Re-exported from `token_filter.zig`, not defined here: `parser/ast.zig`
/// needs the same type for its `.directive` AST node, and `parser/` can't
/// import `syntax/` (the reverse already holds — see `token_filter.zig`'s
/// own doc comment on `Directive`).
pub const Alias = tf.DirectiveAlias;
pub const Include = tf.DirectiveInclude;
pub const Directive = tf.Directive;

pub const Diagnostic = struct {
    span: Span,
    message: []const u8,
    /// See `syntax/lexer.zig`'s `Diagnostic` doc comment — same routing
    /// distinction (legacy's `syntax()` helper vs. an ad hoc `word.print`
    /// call site), mirrored here so `lexer.zig`'s `lexDirective` can copy
    /// these over without losing that information.
    stream: tf.DiagnosticStream = .stderr,
    add_prefix: bool = true,
};

const keywords = std.StaticStringMap(void).initComptime(.{
    .{"begin"}, .{"bnf"}, .{"export"}, .{"free"}, .{"include"}, .{"insert"}, .{"lex"}, .{"list"}, .{"nolist"},
});

fn isIdentCont(ch: u8) bool {
    return std.ascii.isAlphanumeric(ch) or ch == '_' or ch == '\'';
}

/// Scans one `%`-directive's content, starting immediately after the `%`.
pub const Scanner = struct {
    source: *const Source,
    pos: usize,
    gpa: std.mem.Allocator,
    diagnostics: std.ArrayList(Diagnostic) = .empty,

    pub fn init(gpa: std.mem.Allocator, source: *const Source, pos_after_percent: usize) Scanner {
        return .{ .source = source, .pos = pos_after_percent, .gpa = gpa };
    }

    pub fn deinit(self: *Scanner) void {
        for (self.diagnostics.items) |d| self.gpa.free(d.message);
        self.diagnostics.deinit(self.gpa);
        self.* = undefined;
    }

    fn record(self: *Scanner, span: Span, comptime fmt: []const u8, args: anytype) void {
        const msg = std.fmt.allocPrint(self.gpa, fmt, args) catch return;
        self.diagnostics.append(self.gpa, .{ .span = span, .message = msg }) catch {};
    }

    /// Like `record`, but matches legacy's ad hoc `word.print(...)` call
    /// sites: stdout, `message` printed exactly as given (see
    /// `syntax/lexer.zig`'s `recordStdout`).
    fn recordStdout(self: *Scanner, span: Span, comptime fmt: []const u8, args: anytype) void {
        const msg = std.fmt.allocPrint(self.gpa, fmt, args) catch return;
        self.diagnostics.append(self.gpa, .{ .span = span, .message = msg, .stream = .stdout, .add_prefix = false }) catch {};
    }

    fn peekByte(self: *const Scanner) ?u8 {
        return if (self.pos < self.source.bytes.len) self.source.bytes[self.pos] else null;
    }

    fn peekByteAt(self: *const Scanner, offset: usize) ?u8 {
        const p = self.pos + offset;
        return if (p < self.source.bytes.len) self.source.bytes[p] else null;
    }

    fn skipHorizontalWhitespace(self: *Scanner) void {
        while (self.peekByte()) |c| {
            if (c != ' ' and c != '\t') break;
            self.pos += 1;
        }
    }

    /// Scan the directive keyword (`include`, `export`, …), assuming
    /// `self.pos` is right after the `%` (no whitespace between them, per
    /// real Miranda convention and `lex.zig`'s `directive()`, which calls
    /// `kollect` immediately with no leading `layout()`).
    fn scanKeyword(self: *Scanner) []const u8 {
        const start = self.pos;
        while (self.peekByte()) |c| {
            if (!isIdentCont(c)) break;
            self.pos += 1;
        }
        return self.source.bytes[start..self.pos];
    }

    /// `"..."` or `<...>`, per `lex.zig`'s `pathname()`: raw characters (no
    /// escape decoding), terminated by the matching quote/bracket or a
    /// newline (an error either way — a pathname cannot span lines).
    fn scanPathname(self: *Scanner, span: Span) ?struct { path: []const u8, from_miralib: bool } {
        self.skipHorizontalWhitespace();
        const opener = self.peekByte() orelse return null;
        const from_miralib = opener == '<';
        if (opener != '"' and opener != '<') return null;
        self.pos += 1;
        const start = self.pos;
        const closer: u8 = if (from_miralib) '>' else '"';
        while (self.peekByte()) |c| {
            if (c == closer or c == '\n') break;
            self.pos += 1;
        }
        if (self.peekByte() != closer) {
            self.record(span, "unterminated pathname after directive", .{});
            return null;
        }
        const path = self.source.bytes[start..self.pos];
        self.pos += 1; // the closer
        return .{ .path = path, .from_miralib = from_miralib };
    }

    /// A `{...}` block: brace-depth-tracked, so a brace inside a nested
    /// expression doesn't end it early. Returns the raw text between the
    /// outer braces (braces excluded), or `null` if `{` isn't next.
    fn scanBraceBlock(self: *Scanner, span: Span) ?[]const u8 {
        self.skipWhitespaceAndNewlines();
        if (self.peekByte() != '{') return null;
        self.pos += 1;
        const start = self.pos;
        var depth: usize = 1;
        while (self.peekByte()) |c| {
            if (c == '{') depth += 1;
            if (c == '}') {
                depth -= 1;
                if (depth == 0) break;
            }
            self.pos += 1;
        }
        if (depth != 0) {
            self.record(span, "unterminated '{{...}}' block after directive", .{});
            return self.source.bytes[start..self.pos];
        }
        const text = self.source.bytes[start..self.pos];
        self.pos += 1; // the closing '}'
        return text;
    }

    fn skipWhitespaceAndNewlines(self: *Scanner) void {
        while (self.peekByte()) |c| {
            if (c != ' ' and c != '\t' and c != '\n' and c != '\r') break;
            self.pos += 1;
        }
    }

    /// The rest of the current line, trimmed of trailing whitespace and the
    /// newline itself.
    fn scanToEndOfLine(self: *Scanner) []const u8 {
        const start = self.pos;
        while (self.peekByte()) |c| {
            if (c == '\n') break;
            self.pos += 1;
        }
        return std.mem.trimEnd(u8, self.source.bytes[start..self.pos], " \t\r");
    }

    /// `alias alias*` following an `%include`'s pathname/bindings:
    /// `new/old`, `IDENTIFIER/IDENTIFIER`, or `-identifier`, space
    /// separated, ending at end-of-line. Caller frees the returned slice.
    fn scanAliases(self: *Scanner) ![]Alias {
        var out: std.ArrayList(Alias) = .empty;
        errdefer out.deinit(self.gpa);
        while (true) {
            self.skipHorizontalWhitespace();
            const c = self.peekByte() orelse break;
            if (c == '\n') break;
            if (c == '-') {
                self.pos += 1;
                const name = self.scanIdentLike();
                if (name.len == 0) break;
                try out.append(self.gpa, .{ .suppress = name });
                continue;
            }
            const first = self.scanIdentLike();
            if (first.len == 0) break;
            if (self.peekByte() != '/') break;
            self.pos += 1;
            const second = self.scanIdentLike();
            try out.append(self.gpa, .{ .rename = .{ .new = first, .old = second } });
        }
        return out.toOwnedSlice(self.gpa);
    }

    fn scanIdentLike(self: *Scanner) []const u8 {
        const start = self.pos;
        while (self.peekByte()) |c| {
            if (!isIdentCont(c)) break;
            self.pos += 1;
        }
        return self.source.bytes[start..self.pos];
    }

    /// Scan one directive. `self.pos` must be positioned right after the
    /// `%` on entry; on return it is positioned just past everything this
    /// directive consumed.
    pub fn scanDirective(self: *Scanner) !Directive {
        const span = self.source.position(self.pos);
        const keyword = self.scanKeyword();

        if (!keywords.has(keyword)) {
            const rest = self.scanToEndOfLine();
            self.recordStdout(span, "syntax error: unknown directive \"%{s}\"", .{keyword});
            return .{ .unknown = .{ .text = rest, .span = span } };
        }

        if (std.mem.eql(u8, keyword, "include")) {
            const parsed = self.scanPathname(span) orelse {
                self.record(span, "bad pathname after %include", .{});
                return .{ .unknown = .{ .text = self.scanToEndOfLine(), .span = span } };
            };
            const bindings = self.scanBraceBlock(span) orelse &.{};
            const aliases = try self.scanAliases();
            return .{ .include = .{
                .path = parsed.path,
                .from_miralib = parsed.from_miralib,
                .bindings_text = bindings,
                .aliases = aliases,
                .span = span,
            } };
        }

        if (std.mem.eql(u8, keyword, "export")) {
            self.skipHorizontalWhitespace();
            return .{ .export_list = .{ .parts_text = self.scanToEndOfLine(), .span = span } };
        }

        if (std.mem.eql(u8, keyword, "free")) {
            const spec = self.scanBraceBlock(span) orelse blk: {
                self.record(span, "%free must be followed by '{{ signature }}'", .{});
                break :blk &.{};
            };
            return .{ .free = .{ .spec_text = spec, .span = span } };
        }

        // insert / list / nolist / bnf / lex / begin
        return .{ .unsupported = .{ .keyword = keyword, .span = span } };
    }
};

fn scanOne(gpa: std.mem.Allocator, source: *const Source, percent_pos: usize) !Directive {
    var scanner = Scanner.init(gpa, source, percent_pos + 1);
    defer scanner.deinit();
    return scanner.scanDirective();
}

test "Scanner: %include \"mylib\" (basic form, no bindings, no aliases)" {
    const gpa = std.testing.allocator;
    var src = try Source.fromBytes(gpa, "%include \"mylib\"\n");
    defer src.deinit();
    const d = try scanOne(gpa, &src, 0);
    defer gpa.free(d.include.aliases);
    try std.testing.expect(d == .include);
    try std.testing.expectEqualStrings("mylib", d.include.path);
    try std.testing.expect(!d.include.from_miralib);
    try std.testing.expectEqualStrings("", d.include.bindings_text);
    try std.testing.expectEqual(@as(usize, 0), d.include.aliases.len);
}

test "Scanner: %include <ex/matrix> (miralib-relative form)" {
    const gpa = std.testing.allocator;
    var src = try Source.fromBytes(gpa, "%include <ex/matrix>\n");
    defer src.deinit();
    const d = try scanOne(gpa, &src, 0);
    defer gpa.free(d.include.aliases);
    try std.testing.expect(d == .include);
    try std.testing.expectEqualStrings("ex/matrix", d.include.path);
    try std.testing.expect(d.include.from_miralib);
}

test "Scanner: %include with a parametrised-script binder block" {
    const gpa = std.testing.allocator;
    var src = try Source.fromBytes(gpa, "%include \"matrices\" {elem==num; zero=0; mult=*; add=+; }\n");
    defer src.deinit();
    const d = try scanOne(gpa, &src, 0);
    defer gpa.free(d.include.aliases);
    try std.testing.expect(d == .include);
    try std.testing.expectEqualStrings("matrices", d.include.path);
    try std.testing.expectEqualStrings("elem==num; zero=0; mult=*; add=+; ", d.include.bindings_text);
    try std.testing.expectEqual(@as(usize, 0), d.include.aliases.len);
}

test "Scanner: %include with an alias list (rename and suppress)" {
    const gpa = std.testing.allocator;
    var src = try Source.fromBytes(gpa, "%include \"mike\" -g mike_f/f\n");
    defer src.deinit();
    const d = try scanOne(gpa, &src, 0);
    defer gpa.free(d.include.aliases);
    try std.testing.expect(d == .include);
    try std.testing.expectEqualStrings("mike", d.include.path);
    try std.testing.expectEqual(@as(usize, 2), d.include.aliases.len);
    try std.testing.expect(d.include.aliases[0] == .suppress);
    try std.testing.expectEqualStrings("g", d.include.aliases[0].suppress);
    try std.testing.expect(d.include.aliases[1] == .rename);
    try std.testing.expectEqualStrings("mike_f", d.include.aliases[1].rename.new);
    try std.testing.expectEqualStrings("f", d.include.aliases[1].rename.old);
}

test "Scanner: %export + -flooby (parts list captured to end of line)" {
    const gpa = std.testing.allocator;
    var src = try Source.fromBytes(gpa, "%export + -flooby\n");
    defer src.deinit();
    const d = try scanOne(gpa, &src, 0);
    try std.testing.expect(d == .export_list);
    try std.testing.expectEqualStrings("+ -flooby", d.export_list.parts_text);
}

test "Scanner: %free { signature } (spec captured, braces excluded)" {
    const gpa = std.testing.allocator;
    var src = try Source.fromBytes(gpa,
        \\%free { elem :: type
        \\        zero :: elem
        \\      }
        \\
    );
    defer src.deinit();
    const d = try scanOne(gpa, &src, 0);
    try std.testing.expect(d == .free);
    try std.testing.expect(std.mem.indexOf(u8, d.free.spec_text, "elem :: type") != null);
    try std.testing.expect(std.mem.indexOf(u8, d.free.spec_text, "zero :: elem") != null);
}

test "Scanner: %insert/%list/%nolist/%bnf/%lex are recognized as unsupported" {
    const gpa = std.testing.allocator;
    const cases = [_][]const u8{ "%insert \"x\"\n", "%list\n", "%nolist\n", "%bnf\n", "%lex\n" };
    const expected_keywords = [_][]const u8{ "insert", "list", "nolist", "bnf", "lex" };
    for (cases, expected_keywords) |case, expected| {
        var src = try Source.fromBytes(gpa, case);
        defer src.deinit();
        const d = try scanOne(gpa, &src, 0);
        try std.testing.expect(d == .unsupported);
        try std.testing.expectEqualStrings(expected, d.unsupported.keyword);
    }
}

test "Scanner: an unrecognized directive name is .unknown, matching lex.zig's error" {
    const gpa = std.testing.allocator;
    var src = try Source.fromBytes(gpa, "%bogus foo bar\n");
    defer src.deinit();
    var scanner = Scanner.init(gpa, &src, 1);
    defer scanner.deinit();
    const d = try scanner.scanDirective();
    try std.testing.expect(d == .unknown);
    try std.testing.expectEqualStrings("bogus", extractKeywordText(&src));
    try std.testing.expectEqual(@as(usize, 1), scanner.diagnostics.items.len);
}

fn extractKeywordText(src: *const Source) []const u8 {
    // "%bogus foo bar\n" -- keyword starts right after '%'.
    return src.bytes[1..6];
}
