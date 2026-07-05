//! syntax/lexer.zig — the native tokenizer core (docs/ZIG_NATIVE_PLAN.md Phase 1
//! step 2), replacing (eventually) `parser/lex.zig`'s `yylex`.
//!
//! Scope of this increment, deliberately: whitespace/comment skipping,
//! identifiers/keywords, typevars/`*`, and the fixed single- and multi-character
//! operator/punctuation set. Not yet implemented, on purpose (kept as
//! separately-staged, separately-verified work per the plan):
//!
//!   - Numerals, strings, chars, escapes, char classes (plan step 4) — these
//!     have their own subtle edge cases (hex floats, the 6-branch escape
//!     table, UTF-8-in-source decoding) that deserve dedicated tests rather
//!     than being folded in here unverified.
//!   - `%`-directive tokenization (deferred to `syntax/directives.zig`).
//!   - Backtick infix names (`` `f` ``) and the `$$`/`$*` internal `CONST` forms.
//!   - The offside/layout rule — NOT a token-stream transform (see the plan's
//!     Phase 1 step 3 correction): today's `lex.zig` couples the lexer to
//!     parser-driven margin state (`setlmargin`/`unsetlmargin`). This lexer
//!     produces a flat stream with no `.offside`/`.elseq` synthesis.
//!
//! Not yet wired into `parser_api.zig` — the legacy lexer remains the
//! production path until Phase 1 step 7.
//!
//! **Verified against `parser/lex.zig` (2026-07-06), not guessed:**
//!   - A lone `*` is the `.star` token (multiplication / type-application
//!     wildcard); a typevar requires **two or more** consecutive `*`s
//!     (`collectstars`/`lex_bridge.zig`'s `word.TYPEVAR => .int_val = star
//!     count`) — `**` is the *first* type variable, not `*`.
//!   - The plain-identifier reserved words are exactly: `abstype div if mod
//!     otherwise readvals show type where with` (`lex.zig`'s `identifier()`).
//!     `include export free bnf lex` are keywords only immediately after `%`
//!     (`directive()`) — out of scope here. `True`/`False` are ordinary
//!     `.cname` tokens in this lexer (they are just nullary constructors of
//!     `bool`; special-casing them as literals is a heap-representation
//!     detail of the legacy lexer, not a lexical-grammar fact).
//!
//! Tests: Lexer.next — one test per token family below.

const std = @import("std");
const tf = @import("../parser/token_filter.zig");
const Source = @import("source.zig").Source;

pub const Token = tf.Token;
pub const TokenId = tf.TokenId;
pub const Span = tf.Span;

/// A structured lex error recorded during scanning (mirrors
/// `parser/parser.zig`'s `Diagnostic` shape; kept as a separate type so
/// `syntax/` does not import the legacy `parser/parser.zig` tree it is
/// replacing).
pub const Diagnostic = struct {
    span: Span,
    message: []const u8,
};

const keywords = std.StaticStringMap(TokenId).initComptime(.{
    .{ "abstype", .kw_abstype },
    .{ "div", .kw_div },
    .{ "if", .kw_if },
    .{ "mod", .kw_mod },
    .{ "otherwise", .kw_otherwise },
    .{ "readvals", .kw_readvals },
    .{ "show", .kw_show },
    .{ "type", .kw_type },
    .{ "where", .kw_where },
    .{ "with", .kw_with },
});

/// Whether `ch` may continue an identifier (`parser/lex.zig`'s `okid`, minus
/// the internal `0x08` private-name marker — never present in real source).
fn isIdentCont(ch: u8) bool {
    return std.ascii.isAlphanumeric(ch) or ch == '_' or ch == '\'';
}

/// The native tokenizer core. Pulls bytes from a `Source`; produces one
/// `Token` per call to `next()`, ending with an unbounded run of `.eof`.
pub const Lexer = struct {
    source: *const Source,
    pos: usize = 0,
    gpa: std.mem.Allocator,
    diagnostics: std.ArrayList(Diagnostic) = .empty,

    pub fn init(gpa: std.mem.Allocator, source: *const Source) Lexer {
        return .{ .source = source, .gpa = gpa };
    }

    pub fn deinit(self: *Lexer) void {
        for (self.diagnostics.items) |d| self.gpa.free(d.message);
        self.diagnostics.deinit(self.gpa);
        self.* = undefined;
    }

    fn peekByte(self: *const Lexer) ?u8 {
        return if (self.pos < self.source.bytes.len) self.source.bytes[self.pos] else null;
    }

    fn peekByteAt(self: *const Lexer, offset: usize) ?u8 {
        const p = self.pos + offset;
        return if (p < self.source.bytes.len) self.source.bytes[p] else null;
    }

    fn spanAt(self: *const Lexer, pos: usize) Span {
        return self.source.position(pos);
    }

    /// Skip whitespace and comments (`||` to end of line; `#!` shebang, but
    /// only as the very first two bytes of the file — matches `lex.zig`'s
    /// `layout()`).
    fn skipTrivia(self: *Lexer) void {
        while (true) {
            const ch = self.peekByte() orelse return;
            if (ch == ' ' or ch == '\t' or ch == '\n' or ch == '\r') {
                self.pos += 1;
                continue;
            }
            if (ch == '|' and self.peekByteAt(1) == '|') {
                while (self.peekByte()) |c| {
                    if (c == '\n') break;
                    self.pos += 1;
                }
                continue;
            }
            if (self.pos == 0 and ch == '#' and self.peekByteAt(1) == '!') {
                while (self.peekByte()) |c| {
                    if (c == '\n') break;
                    self.pos += 1;
                }
                continue;
            }
            return;
        }
    }

    fn record(self: *Lexer, span: Span, comptime fmt: []const u8, args: anytype) void {
        const msg = std.fmt.allocPrint(self.gpa, fmt, args) catch return;
        self.diagnostics.append(self.gpa, .{ .span = span, .message = msg }) catch {};
    }

    /// Two-char lookahead: if the next byte is `expected`, consume it and
    /// return `then`; otherwise leave `pos` alone and return `null`.
    fn tryFollow(self: *Lexer, expected: u8, then: TokenId) ?TokenId {
        if (self.peekByte() == expected) {
            self.pos += 1;
            return then;
        }
        return null;
    }

    /// Scan and return the next token; an exhausted `Source` yields an
    /// unbounded run of `.eof`.
    pub fn next(self: *Lexer) Token {
        self.skipTrivia();
        const start = self.pos;
        const span = self.spanAt(start);
        const ch = self.peekByte() orelse return .{ .id = .eof, .span = span };

        if (std.ascii.isAlphabetic(ch)) return self.lexIdentifier(start, span);
        if (ch == '*') return self.lexStarOrTypevar(start, span);

        self.pos += 1;
        return switch (ch) {
            '-' => .{ .id = self.tryFollow('>', .arrow) orelse self.tryFollow('-', .minus_minus) orelse .minus, .span = span },
            '<' => .{ .id = self.tryFollow('-', .left_arrow) orelse self.tryFollow('=', .le) orelse .lt, .span = span },
            '>' => .{ .id = self.tryFollow('=', .ge) orelse .gt, .span = span },
            '~' => .{ .id = self.tryFollow('=', .ne) orelse .tilde, .span = span },
            '=' => .{ .id = self.tryFollow('=', .eq_eq) orelse .eq, .span = span },
            '+' => .{ .id = self.tryFollow('+', .plus_plus) orelse .plus, .span = span },
            '.' => .{ .id = self.tryFollow('.', .dot_dot) orelse .dot, .span = span },
            '\\' => .{ .id = self.tryFollow('/', .vel) orelse .error_tok, .span = span },
            ':' => blk: {
                if (self.tryFollow(':', .coloncolon) != null) {
                    break :blk .{ .id = self.tryFollow('=', .colon2eq) orelse .coloncolon, .span = span };
                }
                break :blk .{ .id = .cons, .span = span };
            },
            '^' => .{ .id = .caret, .span = span },
            '!' => .{ .id = .bang, .span = span },
            '#' => .{ .id = .hash, .span = span },
            '&' => .{ .id = .amp, .span = span },
            '|' => .{ .id = .pipe, .span = span },
            '(' => .{ .id = .lparen, .span = span },
            ')' => .{ .id = .rparen, .span = span },
            '[' => .{ .id = .lbracket, .span = span },
            ']' => .{ .id = .rbracket, .span = span },
            '{' => .{ .id = .lbrace, .span = span },
            '}' => .{ .id = .rbrace, .span = span },
            ',' => .{ .id = .comma, .span = span },
            ';' => .{ .id = .semicolon, .span = span },
            '?' => .{ .id = .question, .span = span },
            else => blk: {
                self.record(span, "unexpected character '{c}' (0x{x:0>2})", .{ ch, ch });
                break :blk .{ .id = .error_tok, .span = span };
            },
        };
    }

    fn lexIdentifier(self: *Lexer, start: usize, span: Span) Token {
        self.pos += 1; // first char already checked alphabetic
        while (self.peekByte()) |c| {
            if (!isIdentCont(c)) break;
            self.pos += 1;
        }
        const text = self.source.bytes[start..self.pos];
        if (keywords.get(text)) |kw| return .{ .id = kw, .span = span };
        const id: TokenId = if (std.ascii.isUpper(text[0])) .cname else .name;
        return .{ .id = id, .span = span, .text = text };
    }

    /// A lone `*` is `.star`; two or more consecutive `*`s are `.typevar`
    /// (`int_val` = the star count — matches `lex_bridge.zig`'s encoding, so
    /// `**` is type variable 2, `***` is type variable 3, and so on).
    fn lexStarOrTypevar(self: *Lexer, start: usize, span: Span) Token {
        self.pos += 1;
        var count: i64 = 1;
        while (self.peekByte() == '*') {
            self.pos += 1;
            count += 1;
        }
        _ = start;
        if (count == 1) return .{ .id = .star, .span = span };
        return .{ .id = .typevar, .span = span, .int_val = count };
    }
};

/// Tokenize all of `source`, returning an owned slice ending in `.eof`
/// (caller frees with `gpa.free`). Diagnostics recorded during the scan are
/// left in `lexer.diagnostics` if the caller passes one in, else discarded —
/// most callers will want `tokenizeCollect` below instead.
pub fn tokenize(gpa: std.mem.Allocator, source: *const Source) ![]Token {
    var lexer = Lexer.init(gpa, source);
    defer lexer.deinit();
    var out: std.ArrayList(Token) = .empty;
    errdefer out.deinit(gpa);
    while (true) {
        const tok = lexer.next();
        try out.append(gpa, tok);
        if (tok.id == .eof) break;
    }
    return out.toOwnedSlice(gpa);
}

fn testSource(gpa: std.mem.Allocator, text: []const u8) !Source {
    return Source.fromBytes(gpa, text);
}

test "Lexer.next: skips whitespace, || comments, and a leading #! shebang" {
    const gpa = std.testing.allocator;
    var src = try testSource(gpa, "#!/usr/bin/mira\n  || a comment\n\t+\n");
    defer src.deinit();
    var lex = Lexer.init(gpa, &src);
    defer lex.deinit();
    const tok = lex.next();
    try std.testing.expectEqual(TokenId.plus, tok.id);
    try std.testing.expectEqual(@as(u32, 3), tok.span.line);
}

test "Lexer.next: identifiers classify by initial case and keywords win" {
    const gpa = std.testing.allocator;
    var src = try testSource(gpa, "foo Bar where x'2 _tail");
    defer src.deinit();
    var lex = Lexer.init(gpa, &src);
    defer lex.deinit();
    var tok = lex.next();
    try std.testing.expectEqual(TokenId.name, tok.id);
    try std.testing.expectEqualStrings("foo", tok.text);
    tok = lex.next();
    try std.testing.expectEqual(TokenId.cname, tok.id);
    try std.testing.expectEqualStrings("Bar", tok.text);
    tok = lex.next();
    try std.testing.expectEqual(TokenId.kw_where, tok.id);
    tok = lex.next();
    try std.testing.expectEqual(TokenId.name, tok.id);
    try std.testing.expectEqualStrings("x'2", tok.text);
    // A leading '_' is not an identifier start in this lexer (out of scope
    // legacy underline trick) -- falls through to error_tok, then the rest
    // scans as a plain name.
    tok = lex.next();
    try std.testing.expectEqual(TokenId.error_tok, tok.id);
    tok = lex.next();
    try std.testing.expectEqual(TokenId.name, tok.id);
    try std.testing.expectEqualStrings("tail", tok.text);
}

test "Lexer.next: all ten plain-position keywords resolve" {
    const gpa = std.testing.allocator;
    var src = try testSource(gpa, "abstype div if mod otherwise readvals show type where with");
    defer src.deinit();
    var lex = Lexer.init(gpa, &src);
    defer lex.deinit();
    const expected = [_]TokenId{ .kw_abstype, .kw_div, .kw_if, .kw_mod, .kw_otherwise, .kw_readvals, .kw_show, .kw_type, .kw_where, .kw_with };
    for (expected) |id| {
        try std.testing.expectEqual(id, lex.next().id);
    }
}

test "Lexer.next: True/False are ordinary cname tokens, not literals" {
    const gpa = std.testing.allocator;
    var src = try testSource(gpa, "True False");
    defer src.deinit();
    var lex = Lexer.init(gpa, &src);
    defer lex.deinit();
    var tok = lex.next();
    try std.testing.expectEqual(TokenId.cname, tok.id);
    try std.testing.expectEqualStrings("True", tok.text);
    tok = lex.next();
    try std.testing.expectEqual(TokenId.cname, tok.id);
    try std.testing.expectEqualStrings("False", tok.text);
}

test "Lexer.next: a lone '*' is .star; '**'/'***' are .typevar with the star count" {
    const gpa = std.testing.allocator;
    var src = try testSource(gpa, "* ** *** ****");
    defer src.deinit();
    var lex = Lexer.init(gpa, &src);
    defer lex.deinit();
    var tok = lex.next();
    try std.testing.expectEqual(TokenId.star, tok.id);
    tok = lex.next();
    try std.testing.expectEqual(TokenId.typevar, tok.id);
    try std.testing.expectEqual(@as(i64, 2), tok.int_val);
    tok = lex.next();
    try std.testing.expectEqual(TokenId.typevar, tok.id);
    try std.testing.expectEqual(@as(i64, 3), tok.int_val);
    tok = lex.next();
    try std.testing.expectEqual(TokenId.typevar, tok.id);
    try std.testing.expectEqual(@as(i64, 4), tok.int_val);
}

test "Lexer.next: multi-character operators" {
    const gpa = std.testing.allocator;
    var src = try testSource(gpa, "-> -- <- <= >= ~= == ++ .. \\/ :: ::=");
    defer src.deinit();
    var lex = Lexer.init(gpa, &src);
    defer lex.deinit();
    const expected = [_]TokenId{ .arrow, .minus_minus, .left_arrow, .le, .ge, .ne, .eq_eq, .plus_plus, .dot_dot, .vel, .coloncolon, .colon2eq };
    for (expected) |id| {
        try std.testing.expectEqual(id, lex.next().id);
    }
}

test "Lexer.next: single-character operators fall through when lookahead fails" {
    const gpa = std.testing.allocator;
    var src = try testSource(gpa, "- < > ~ = + . : ^ ! # & | ( ) [ ] { } , ; ?");
    defer src.deinit();
    var lex = Lexer.init(gpa, &src);
    defer lex.deinit();
    const expected = [_]TokenId{ .minus, .lt, .gt, .tilde, .eq, .plus, .dot, .cons, .caret, .bang, .hash, .amp, .pipe, .lparen, .rparen, .lbracket, .rbracket, .lbrace, .rbrace, .comma, .semicolon, .question };
    for (expected) |id| {
        try std.testing.expectEqual(id, lex.next().id);
    }
}

test "Lexer.next: unrecognised byte is .error_tok and is recorded as a diagnostic" {
    const gpa = std.testing.allocator;
    var src = try testSource(gpa, "@");
    defer src.deinit();
    var lex = Lexer.init(gpa, &src);
    defer lex.deinit();
    const tok = lex.next();
    try std.testing.expectEqual(TokenId.error_tok, tok.id);
    try std.testing.expectEqual(@as(usize, 1), lex.diagnostics.items.len);
}

test "Lexer.next: an exhausted Source yields .eof forever" {
    const gpa = std.testing.allocator;
    var src = try testSource(gpa, "x");
    defer src.deinit();
    var lex = Lexer.init(gpa, &src);
    defer lex.deinit();
    _ = lex.next(); // 'x'
    try std.testing.expectEqual(TokenId.eof, lex.next().id);
    try std.testing.expectEqual(TokenId.eof, lex.next().id);
}

test "tokenize: collects a full stream ending in .eof" {
    const gpa = std.testing.allocator;
    var src = try testSource(gpa, "square x = x * x");
    defer src.deinit();
    const toks = try tokenize(gpa, &src);
    defer gpa.free(toks);
    try std.testing.expectEqual(TokenId.eof, toks[toks.len - 1].id);
    try std.testing.expectEqual(TokenId.name, toks[0].id);
    try std.testing.expectEqualStrings("square", toks[0].text);
    try std.testing.expectEqual(TokenId.star, toks[4].id);
}
