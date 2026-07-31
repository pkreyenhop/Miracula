//! syntax/source.zig — a script reduced to Miranda-lexical bytes: literate
//! prose stripped, line-start offsets precomputed for `Span` reporting.
//!
//! Part of docs/GoReady.md Phase 1 (the native front end). Today's
//! `parser/lex.zig` interleaves literate-margin handling, line counting, and
//! token scanning into one online, heap-mutating pass (`getch`/`yylex`). This
//! module splits the *bytes* out first: prepare a `Source` once, then a pure
//! `(allocator, *const Source) -> {[]Token, Diagnostics}` lexer (Phase 1 step
//! 2) can scan it without touching the heap or re-deriving line numbers.
//! Not yet wired into `parser_api.zig` — the legacy lexer remains the
//! production path until Phase 1 step 7.
//!
//! Tests: Source.init — literate/plain detection and prose stripping,
//! Source.position — byte offset to 1-based (line, col)

const std = @import("std");
const tf = @import("token_filter.zig");

/// Re-exported so callers don't need to know `Span` lives in `token_filter.zig`.
pub const Span = tf.Span;

/// A prepared Miranda source buffer: literate prose blanked out (if the
/// script is literate), byte-identical in length and line count to the
/// original so `position()` never needs a literate-mode offset correction.
pub const Source = struct {
    /// Lexical bytes: for a literate script, every prose byte and the
    /// `>`-margin marker itself have been overwritten with `' '` in place —
    /// code lines are untouched, every `\n` is untouched. For a plain
    /// script, identical to the file/buffer as read. Owned by this `Source`.
    bytes: []u8,
    /// `bytes[line_starts[i]]` is the first byte of 1-based line `i + 1`.
    /// Always has at least one entry (`0`), even for an empty buffer.
    line_starts: []const u32,
    /// Whether literate stripping ran (detected by a leading `>` byte or by
    /// `loadFile`'s `.lit.m` filename convention — see `parser/lex.zig`'s
    /// `litname`).
    literate: bool,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *Source) void {
        self.allocator.free(self.bytes);
        self.allocator.free(self.line_starts);
        self.* = undefined;
    }

    /// Load `path` from disk and prepare it (literate detection consults
    /// both the leading-`>` rule and the `.lit.m` filename convention).
    pub fn loadFile(allocator: std.mem.Allocator, io: std.Io, path: []const u8) !Source {
        const file = try std.Io.Dir.cwd().openFile(io, path, .{});
        defer file.close(io);
        const len = try file.length(io);
        const raw = try allocator.alloc(u8, @intCast(len));
        errdefer allocator.free(raw);
        _ = try file.readPositionalAll(io, raw, 0);
        return init(allocator, raw, isLiterateName(path));
    }

    /// Prepare an in-memory buffer (`%insert`ed text, a REPL command line) as
    /// source. Only the leading-`>` literate rule applies — there is no
    /// filename to consult.
    pub fn fromBytes(allocator: std.mem.Allocator, raw: []const u8) !Source {
        const owned = try allocator.dupe(u8, raw);
        return init(allocator, owned, false);
    }

    /// Recursively resolve `%insert "path"` directives by splicing the
    /// target file's bytes in place of the whole directive line — legacy's
    /// `lex.zig` switches the character stream to another file mid-`yylex`
    /// for `%insert` (a real, C-preprocessor-`#include`-style substitution,
    /// not a token); this is the batch-model equivalent: splice once, up
    /// front, before tokenizing at all, rather than mid-scan (matches this
    /// file's header framing of `%insert`'ed text as "an in-memory buffer",
    /// prepared before `Source.init` runs). Call this on the raw bytes
    /// *before* `init`/`fromBytes`/literate detection, since splicing
    /// changes the byte layout those depend on.
    ///
    /// `base_dir` is the directory `"..."`-form paths resolve relative to
    /// (the including file's own directory — nested inserts resolve
    /// relative to *their own* file, not the original). `<...>`-form
    /// (miralib-relative) paths are not resolved here — not exercised by
    /// the shipped corpus, a known gap matching `%include`'s own
    /// unresolved path-resolution TODO (needs interpreter context this
    /// preprocessing step doesn't have access to).
    ///
    /// **Known limitation:** legacy attributes diagnostics inside an
    /// inserted file to *that file's own* line numbers (a stack of
    /// per-file line counters, restored when the insert ends), and
    /// continues the *outer* file's line count correctly afterward. This
    /// function's straight byte-concatenation does neither — line numbers
    /// after an insert are simply the running total across the spliced
    /// buffer. Not observed to matter for the shipped corpus (no golden
    /// case has a diagnostic after an `%insert`), but a real gap if one
    /// ever does.
    pub fn resolveInserts(gpa: std.mem.Allocator, raw: []const u8, base_dir: []const u8, io: std.Io, depth: u8) ![]u8 {
        if (depth > 12) return error.InsertNestingTooDeep; // matches lex.zig's `insertdepth < 12` check
        var out: std.ArrayList(u8) = .empty;
        errdefer out.deinit(gpa);
        var i: usize = 0;
        while (i < raw.len) {
            if (raw[i] == '%' and matchesInsertKeyword(raw, i + 1)) {
                if (try spliceOneInsert(gpa, raw, i, base_dir, io, depth, &out)) |next_i| {
                    i = next_i;
                    continue;
                }
            }
            try out.append(gpa, raw[i]);
            i += 1;
        }
        return out.toOwnedSlice(gpa);
    }

    fn matchesInsertKeyword(raw: []const u8, start: usize) bool {
        const kw = "insert";
        if (start + kw.len > raw.len) return false;
        if (!std.mem.eql(u8, raw[start .. start + kw.len], kw)) return false;
        // The keyword must end here (not e.g. "insertx") -- next byte (if
        // any) must not continue an identifier.
        const after = start + kw.len;
        if (after < raw.len) {
            const c = raw[after];
            if (std.ascii.isAlphanumeric(c) or c == '_' or c == '\'') return false;
        }
        return true;
    }

    /// Attempt to splice one `%insert "path"` directive starting at `raw[at]`
    /// (`raw[at] == '%'`) into `out`. Returns the byte index in `raw` to
    /// resume scanning from on success, or `null` if this isn't a
    /// well-formed `%insert "..."` (caller falls back to copying `'%'`
    /// through unchanged, matching `directives.zig`'s "unknown directive"
    /// tolerance elsewhere).
    // Explicit (not inferred) error set: spliceOneInsert and resolveInserts
    // call each other, and Zig can't infer an error set across a
    // recursive/mutual-recursion cycle.
    fn spliceOneInsert(gpa: std.mem.Allocator, raw: []const u8, at: usize, base_dir: []const u8, io: std.Io, depth: u8, out: *std.ArrayList(u8)) anyerror!?usize {
        var p = at + 1 + "insert".len;
        while (p < raw.len and (raw[p] == ' ' or raw[p] == '\t')) p += 1;
        if (p >= raw.len or raw[p] != '"') return null;
        const path_start = p + 1;
        var q = path_start;
        while (q < raw.len and raw[q] != '"' and raw[q] != '\n') q += 1;
        if (q >= raw.len or raw[q] != '"') return null;
        const path = raw[path_start..q];
        var end = q + 1;
        if (end < raw.len and raw[end] == '\n') end += 1;

        const full_path = try std.fs.path.join(gpa, &.{ base_dir, path });
        defer gpa.free(full_path);
        const file = try std.Io.Dir.cwd().openFile(io, full_path, .{});
        defer file.close(io);
        const len = try file.length(io);
        const inserted_raw = try gpa.alloc(u8, @intCast(len));
        defer gpa.free(inserted_raw);
        _ = try file.readPositionalAll(io, inserted_raw, 0);

        const inserted_dir = std.fs.path.dirname(full_path) orelse ".";
        const resolved = try resolveInserts(gpa, inserted_raw, inserted_dir, io, depth + 1);
        defer gpa.free(resolved);
        try out.appendSlice(gpa, resolved);
        return end;
    }

    /// Whether `path` names a literate script by convention
    /// (`parser/lex.zig`'s `litname`: filename ends in `.lit.m`). Public so
    /// callers that already have a file's bytes in hand (e.g. read via the
    /// legacy `Stream` stream rather than a fresh disk read — see
    /// `parser_api.zig`'s native-pipeline entry points) can compute
    /// `name_says_literate` themselves before calling `init` directly.
    pub fn isLiterateName(path: []const u8) bool {
        return std.mem.endsWith(u8, path, ".lit.m");
    }

    /// Take ownership of `raw` and prepare it as a `Source`. `name_says_literate`
    /// is the filename-convention half of literate detection (`loadFile`
    /// passes it through; `fromBytes` has no filename, so passes `false`).
    ///
    /// NOTE: this does not enforce the legacy lexer's separate `chblank` rule
    /// (a literate script's code blocks must be followed by a blank prose
    /// line) — that is a diagnostic, not a byte-stripping concern, and is
    /// deferred to the Phase 1 lexer that consumes this `Source`.
    ///
    /// NOTE: this does not validate UTF-8 — Miranda source is a byte stream
    /// (see `word.isLatin1Char`), and today only `-Dstrict`/Debug builds
    /// reject invalid UTF-8 (`parser_api.zig`'s `validateUtf8File`). Baking
    /// validation in here would silently change behaviour for non-strict
    /// Latin-1 scripts; callers that want it should validate before calling.
    pub fn init(allocator: std.mem.Allocator, raw: []u8, name_says_literate: bool) !Source {
        const literate = name_says_literate or (raw.len > 0 and raw[0] == '>');
        if (literate) blankProse(raw);
        const line_starts = try computeLineStarts(allocator, raw);
        return .{ .bytes = raw, .line_starts = line_starts, .literate = literate, .allocator = allocator };
    }

    /// Overwrite every prose byte, and the leading `>` marker of every code
    /// line, with `' '` — in place, preserving every `\n` and therefore every
    /// original byte offset / column / line number exactly.
    fn blankProse(raw: []u8) void {
        var i: usize = 0;
        while (i < raw.len) {
            if (raw[i] == '>') {
                raw[i] = ' ';
                while (i < raw.len and raw[i] != '\n') i += 1;
            } else {
                while (i < raw.len and raw[i] != '\n') {
                    raw[i] = ' ';
                    i += 1;
                }
            }
            if (i < raw.len and raw[i] == '\n') i += 1;
        }
    }

    fn computeLineStarts(allocator: std.mem.Allocator, bytes: []const u8) ![]const u32 {
        var list: std.ArrayList(u32) = .empty;
        errdefer list.deinit(allocator);
        try list.append(allocator, 0);
        for (bytes, 0..) |b, idx| {
            if (b == '\n') try list.append(allocator, @intCast(idx + 1));
        }
        return list.toOwnedSlice(allocator);
    }

    /// The 1-based (line, col) of byte offset `pos` (must be `<= bytes.len`).
    ///
    /// Tabs expand to the next multiple-of-8 column (`parser/lex.zig`'s
    /// `getch`: `col = (col/8 + 1)*8`, computed here relative to column 1
    /// instead of `getch`'s current left-verge (`lverge`) — this module has
    /// no layout/margin state to consult (that's `syntax/layout.zig`'s job,
    /// which runs *after* tokenizing, on the token stream, not the bytes).
    /// Verified against `miralib/prelude`'s real (tab-indented) `cutoff`
    /// function: since the offside rule only ever compares two columns
    /// computed the *same* way, lines sharing an identical tab/space prefix
    /// still align correctly under this simpler, lverge-0 assumption; it
    /// would only disagree with `lverge`-relative expansion for a prefix
    /// that mixes tabs and spaces differently across two lines meant to
    /// align at a *non-zero* lverge — not seen in the shipped corpus, but
    /// flagged here in case it surfaces later.
    pub fn position(self: *const Source, pos: usize) Span {
        var lo: usize = 0;
        var hi: usize = self.line_starts.len;
        while (lo + 1 < hi) {
            const mid = lo + (hi - lo) / 2;
            if (self.line_starts[mid] <= pos) lo = mid else hi = mid;
        }
        const line_start = self.line_starts[lo];
        var col: usize = 1;
        var i = line_start;
        while (i < pos) : (i += 1) {
            if (self.bytes[i] == '\t') {
                col = (col - 1) / 8 * 8 + 9;
            } else {
                col += 1;
            }
        }
        return .{ .line = @intCast(lo + 1), .col = @intCast(col) };
    }
};

test "Source.init: plain script passes bytes through unchanged" {
    const gpa = std.testing.allocator;
    const raw = try gpa.dupe(u8, "square x = x * x\ncube x = x * x * x\n");
    var src = try Source.init(gpa, raw, false);
    defer src.deinit();
    try std.testing.expect(!src.literate);
    try std.testing.expectEqualStrings("square x = x * x\ncube x = x * x * x\n", src.bytes);
}

test "Source.init: leading '>' triggers literate stripping, code lines survive" {
    const gpa = std.testing.allocator;
    const raw = try gpa.dupe(u8,
        \\> square x = x * x
        \\> cube x  = x * x * x
        \\
        \\Prose paragraph, discarded.
        \\
    );
    var src = try Source.init(gpa, raw, false);
    defer src.deinit();
    try std.testing.expect(src.literate);
    // Every line is the same length as before (prose/margin bytes -> spaces).
    var orig_it = std.mem.splitScalar(u8, "> square x = x * x\n> cube x  = x * x * x\n\nProse paragraph, discarded.\n", '\n');
    var strip_it = std.mem.splitScalar(u8, src.bytes, '\n');
    while (orig_it.next()) |ol| {
        const sl = strip_it.next().?;
        try std.testing.expectEqual(ol.len, sl.len);
    }
    // The code lines' content (after the blanked '>' marker) is untouched.
    try std.testing.expect(std.mem.indexOf(u8, src.bytes, " square x = x * x") != null);
    try std.testing.expect(std.mem.indexOf(u8, src.bytes, " cube x  = x * x * x") != null);
    // The prose line is now all blanks.
    try std.testing.expect(std.mem.indexOf(u8, src.bytes, "Prose") == null);
}

test "Source.init: .lit.m filename convention triggers literate mode without a leading '>'" {
    const gpa = std.testing.allocator;
    const raw = try gpa.dupe(u8, "Prose first, no leading '>'.\n\n> code_line = 1\n");
    var src = try Source.init(gpa, raw, true);
    defer src.deinit();
    try std.testing.expect(src.literate);
    try std.testing.expect(std.mem.indexOf(u8, src.bytes, "Prose") == null);
    try std.testing.expect(std.mem.indexOf(u8, src.bytes, " code_line = 1") != null);
}

test "Source.position: 1-based (line, col) for a multi-line buffer" {
    const gpa = std.testing.allocator;
    const raw = try gpa.dupe(u8, "abc\nde\nfghi\n");
    var src = try Source.init(gpa, raw, false);
    defer src.deinit();
    try std.testing.expectEqual(Span{ .line = 1, .col = 1 }, src.position(0));
    try std.testing.expectEqual(Span{ .line = 1, .col = 4 }, src.position(3)); // the '\n' itself
    try std.testing.expectEqual(Span{ .line = 2, .col = 1 }, src.position(4)); // 'd'
    try std.testing.expectEqual(Span{ .line = 3, .col = 3 }, src.position(9)); // 'h'
}

test "Source.position: a tab expands to the next multiple-of-8 column" {
    const gpa = std.testing.allocator;
    // "\t" (col 1->9), "a\t" (col 2->9), "ab\t" (col 3->9), "\t\t" (col 1->9->17).
    const raw = try gpa.dupe(u8, "\tx\na\tx\nab\tx\n\t\tx\n");
    var src = try Source.init(gpa, raw, false);
    defer src.deinit();
    try std.testing.expectEqual(@as(u32, 9), src.position(1).col); // 'x' after "\t"
    try std.testing.expectEqual(@as(u32, 9), src.position(5).col); // 'x' after "a\t"
    try std.testing.expectEqual(@as(u32, 9), src.position(10).col); // 'x' after "ab\t"
    try std.testing.expectEqual(@as(u32, 17), src.position(14).col); // 'x' after "\t\t"
}

test "Source.position: empty buffer has one line, position 0" {
    const gpa = std.testing.allocator;
    const raw = try gpa.alloc(u8, 0);
    var src = try Source.init(gpa, raw, false);
    defer src.deinit();
    try std.testing.expectEqual(Span{ .line = 1, .col = 1 }, src.position(0));
}

test "Source.fromBytes: dupes the input, caller's buffer stays untouched" {
    const gpa = std.testing.allocator;
    var input = "1 + 2\n".*;
    var src = try Source.fromBytes(gpa, &input);
    defer src.deinit();
    try std.testing.expectEqualStrings("1 + 2\n", &input);
    try std.testing.expectEqualStrings("1 + 2\n", src.bytes);
}
