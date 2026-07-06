//! syntax/lexer.zig — the native tokenizer core (docs/ZIG_NATIVE_PLAN.md Phase 1
//! step 2), replacing (eventually) `parser/lex.zig`'s `yylex`.
//!
//! Scope of this increment: whitespace/comment skipping, identifiers/keywords,
//! typevars/`*`, the fixed operator/punctuation set, numerals (decimal/hex/
//! octal integers, decimal floats), and string/char literals with the full
//! escape table. Not yet implemented, on purpose (kept as separately-staged,
//! separately-verified work per the plan):
//!
//!   - Hex-float numerals (`0x1.8p3`) — `error_tok` with a diagnostic, not a
//!     silent mis-scan; char classes (`` `[...]` ``, `%bnf`/`%lex`-only).
//!   - Backtick infix names (`` `f` ``) and the `$$`/`$*` internal `CONST` forms.
//!   - The offside/layout rule — NOT a token-stream transform (see the plan's
//!     Phase 1 step 3 correction): today's `lex.zig` couples the lexer to
//!     parser-driven margin state (`setlmargin`/`unsetlmargin`). This lexer
//!     produces a flat stream with no `.offside`/`.elseq` synthesis.
//!
//! **Deliberate behaviour difference from the legacy lexer:** string/char
//! literals here always decode non-ASCII source bytes as UTF-8 and always
//! re-encode escapes/codepoints as UTF-8 in `.const_str`/`.const_char`.
//! Legacy gates UTF-8 decoding behind the runtime `-utf8`/`-noutf8` flag
//! (Latin-1 otherwise) — an ambient flag this Source-driven lexer has no
//! access to by design. Reconciling this (or deciding modernizing to
//! always-UTF-8 is the right call) is Phase 1 step 7's problem, not this
//! file's; flagged here so it isn't forgotten. Hex/octal integer digits are
//! converted to a plain decimal digit string during lexing (`digitsToDecimal`)
//! so `.const_int.text` never carries a source radix prefix, unlike the
//! legacy bridge's raw dictionary-buffer capture (which does).
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
//! Not yet wired into `parser_api.zig` — the legacy lexer remains the
//! production path until Phase 1 step 7.
//!
//! **`%`-directive tokenization** (landed 2026-07-06): a `%` dispatches to
//! `syntax/directives.zig`'s `Scanner`, which consumes the *whole* directive
//! (keyword, pathname, brace block, alias list, or unsupported/unknown
//! fallback) as one unit — its grammar doesn't decompose into this lexer's
//! ordinary token set (see that file's header). The result is a single
//! `.directive` token whose `int_val` indexes `Lexer.directives`, a
//! side-list of parsed `Directive` values (`tokenize`'s plain `[]Token`
//! silently discards these; `tokenizeWithDirectives` returns both). Scanning
//! resumes immediately after whatever the directive consumed — normal
//! tokens follow on the same or a later line exactly as the source has them.
//! Not yet consumed by `parser.zig` (a separate step: the AST shape and real
//! `%include`/`%export`/`%free` semantics are step 5's harder half, not this
//! file's).
//!
//! **Token text ownership** (a wrinkle worth settling before step 7, not
//! solved here): `.name`/`.cname`/decimal `.const_int`/`.const_float`'s
//! `.text` are borrowed slices into the `Source`'s bytes — safe as long as
//! the `Source` outlives the token, nothing to free. Hex/octal `.const_int`
//! (`digitsToDecimal`'s output) and `.const_str` (`lexStringConst`'s decoded
//! buffer) are freshly `gpa`-allocated — the caller owns and must free them.
//! A `.directive` token's payload lives in `Lexer.directives`/
//! `TokenizeResult.directives`, not in the token itself.
//!
//! Tests: Lexer.next — one test per token family below.

const std = @import("std");
const tf = @import("../parser/token_filter.zig");
const Source = @import("source.zig").Source;
const directives_mod = @import("directives.zig");

pub const Token = tf.Token;
pub const TokenId = tf.TokenId;
pub const Span = tf.Span;
pub const Directive = directives_mod.Directive;

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
    /// One entry per `.directive` token produced so far, in order — a
    /// `.directive` token's `int_val` is its index into this list. Owned by
    /// the `Lexer` until moved out (see `tokenize`'s `TokenizeResult`);
    /// `deinit` frees whatever wasn't moved out.
    directives: std.ArrayList(Directive) = .empty,

    pub fn init(gpa: std.mem.Allocator, source: *const Source) Lexer {
        return .{ .source = source, .gpa = gpa };
    }

    pub fn deinit(self: *Lexer) void {
        for (self.diagnostics.items) |d| self.gpa.free(d.message);
        self.diagnostics.deinit(self.gpa);
        for (self.directives.items) |d| d.deinit(self.gpa);
        self.directives.deinit(self.gpa);
        self.* = undefined;
    }

    fn peekByte(self: *const Lexer) ?u8 {
        return if (self.pos < self.source.bytes.len) self.source.bytes[self.pos] else null;
    }

    fn peekByteAt(self: *const Lexer, offset: usize) ?u8 {
        const p = self.pos + offset;
        return if (p < self.source.bytes.len) self.source.bytes[p] else null;
    }

    fn digitFollows(self: *const Lexer, offset: usize) bool {
        return if (self.peekByteAt(offset)) |c| std.ascii.isDigit(c) else false;
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
        if (std.ascii.isDigit(ch) or (ch == '.' and self.digitFollows(1))) return self.lexNumeral(start, span);
        if (ch == '\'') return self.lexCharConst(span);
        if (ch == '"') return self.lexStringConst(span);
        if (ch == '%') return self.lexDirective(span);

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

    /// Scan a numeral: `0x`/`0o` integer, or decimal integer/float (verified
    /// against `lex.zig`'s `numeral`/`hexnumeral`/`octnumeral`).
    fn lexNumeral(self: *Lexer, start: usize, span: Span) Token {
        if (self.peekByte() == '0' and (self.peekByteAt(1) == 'x' or self.peekByteAt(1) == 'X')) {
            return self.lexRadixInt(span, 16);
        }
        if (self.peekByte() == '0' and (self.peekByteAt(1) == 'o' or self.peekByteAt(1) == 'O')) {
            return self.lexRadixInt(span, 8);
        }
        return self.lexDecimal(start, span);
    }

    fn isRadixDigit(c: u8, base: u8) bool {
        _ = std.fmt.charToDigit(c, base) catch return false;
        return true;
    }

    /// `0x`/`0o` integer literal. Digits are converted to decimal text on the
    /// spot (`digitsToDecimal`) — see the file header for why. Hex-float
    /// (`0x1.8p3`) is deliberately unsupported: `error_tok`, not a silent
    /// truncated-integer mis-scan.
    fn lexRadixInt(self: *Lexer, span: Span, base: u8) Token {
        self.pos += 2; // the "0x"/"0o" (or upper-case) prefix
        const digits_start = self.pos;
        while (self.peekByte()) |c| {
            if (!isRadixDigit(c, base)) break;
            self.pos += 1;
        }
        if (self.pos == digits_start) {
            self.record(span, "malformed base-{d} number: no digits after the prefix", .{base});
            return .{ .id = .error_tok, .span = span };
        }
        if (base == 16 and (self.peekByte() == '.' or self.peekByte() == 'p' or self.peekByte() == 'P')) {
            self.record(span, "hex-float literals are not yet supported by the native lexer", .{});
            return .{ .id = .error_tok, .span = span };
        }
        const digits = self.source.bytes[digits_start..self.pos];
        const decimal = digitsToDecimal(self.gpa, digits, base) catch {
            self.record(span, "out of memory converting numeral", .{});
            return .{ .id = .error_tok, .span = span };
        };
        return .{ .id = .const_int, .span = span, .text = decimal };
    }

    /// Decimal integer or float. A float has a `.` (followed by a digit) and/
    /// or an `e`/`E` exponent; the exponent's `+`/`-` sign and significant-
    /// digit-count-over-3 range check match `lex.zig`'s `numeral` exactly.
    fn lexDecimal(self: *Lexer, start: usize, span: Span) Token {
        while (self.peekByte()) |c| {
            if (!std.ascii.isDigit(c)) break;
            self.pos += 1;
        }
        var is_float = false;
        if (self.peekByte() == '.' and self.digitFollows(1)) {
            is_float = true;
            self.pos += 1;
            while (self.peekByte()) |c| {
                if (!std.ascii.isDigit(c)) break;
                self.pos += 1;
            }
        }
        if (self.peekByte() == 'e' or self.peekByte() == 'E') {
            is_float = true;
            self.pos += 1;
            if (self.peekByte() == '+' or self.peekByte() == '-') self.pos += 1;
            const exp_start = self.pos;
            while (self.peekByte()) |c| {
                if (!std.ascii.isDigit(c)) break;
                self.pos += 1;
            }
            if (self.pos == exp_start) {
                self.record(span, "badly formed floating point number", .{});
                return .{ .id = .error_tok, .span = span };
            }
            var sig = self.source.bytes[exp_start..self.pos];
            while (sig.len > 1 and sig[0] == '0') sig = sig[1..];
            if (sig.len > 3) {
                self.record(span, "floating point number out of range", .{});
                return .{ .id = .error_tok, .span = span };
            }
        }
        const text = self.source.bytes[start..self.pos];
        if (!is_float) return .{ .id = .const_int, .span = span, .text = text };
        if (text.len > 60) {
            self.record(span, "illegal floating point constant (too many digits)", .{});
            return .{ .id = .error_tok, .span = span };
        }
        const value = std.fmt.parseFloat(f64, text) catch {
            self.record(span, "malformed floating point number '{s}'", .{text});
            return .{ .id = .error_tok, .span = span };
        };
        return .{ .id = .const_float, .span = span, .float_val = value };
    }

    /// One decoded logical character from a string/char literal, or `.elided`
    /// (the `\&` no-op escape — legal only inside a string), or an error.
    const Escape = union(enum) {
        char: u21,
        elided,
        err: []const u8,
    };

    /// Decode one character at `self.pos`: a raw byte (UTF-8-decoded if its
    /// top bit is set — see the file header on the UTF-8-always choice), or a
    /// backslash escape. Verified digit-for-digit against `lex.zig`'s
    /// `getlitch`: `\a\b\f\n\r\t\v`, `\x`/`\X` hex (4/6 digits), up to 3
    /// decimal digits, `\'\"\\\``, `\&` (elides), `\<newline>` (line
    /// continuation, recurses for the next real character). An unescaped
    /// literal newline is always an error.
    fn decodeEscape(self: *Lexer) Escape {
        const ch = self.peekByte() orelse return .{ .err = "unexpected end of input in a literal" };
        if (ch == '\n') return .{ .err = "non-escaped newline encountered inside a literal" };
        if (ch != '\\') {
            if (ch < 0x80) {
                self.pos += 1;
                return .{ .char = ch };
            }
            const len = std.unicode.utf8ByteSequenceLength(ch) catch {
                self.pos += 1;
                return .{ .err = "invalid UTF-8 in source" };
            };
            if (self.pos + len > self.source.bytes.len) {
                self.pos += 1;
                return .{ .err = "invalid UTF-8 in source (truncated sequence)" };
            }
            const seq = self.source.bytes[self.pos .. self.pos + len];
            const cp = std.unicode.utf8Decode(seq) catch {
                self.pos += 1;
                return .{ .err = "invalid UTF-8 in source" };
            };
            self.pos += len;
            return .{ .char = cp };
        }
        self.pos += 1; // consume '\'
        const esc = self.peekByte() orelse return .{ .err = "unterminated escape sequence" };
        self.pos += 1;
        switch (esc) {
            '\n' => return self.decodeEscape(), // line continuation
            'a' => return .{ .char = 0x07 },
            'b' => return .{ .char = 0x08 },
            'f' => return .{ .char = 0x0c },
            'n' => return .{ .char = '\n' },
            'r' => return .{ .char = '\r' },
            't' => return .{ .char = '\t' },
            'v' => return .{ .char = 0x0b },
            'x', 'X' => {
                const max_digits: usize = if (esc == 'x') 4 else 6;
                var value: u32 = 0;
                var count: usize = 0;
                while (count < max_digits) : (count += 1) {
                    const c = self.peekByte() orelse break;
                    const d = std.fmt.charToDigit(c, 16) catch break;
                    value = value * 16 + d;
                    self.pos += 1;
                }
                if (count == 0) return .{ .err = "\\x with no hex digits" };
                if (value > 0x10ffff) return .{ .err = "hexadecimal escape out of range" };
                return .{ .char = @intCast(value) };
            },
            '\'', '"', '\\', '`' => return .{ .char = esc },
            '&' => return .elided,
            '0'...'9' => {
                var value: u32 = esc - '0';
                var count: usize = 1;
                while (count < 3) : (count += 1) {
                    const c = self.peekByte() orelse break;
                    if (!std.ascii.isDigit(c)) break;
                    value = value * 10 + (c - '0');
                    self.pos += 1;
                }
                return .{ .char = @intCast(value) };
            },
            else => return .{ .err = "unrecognised escape character" },
        }
    }

    fn lexCharConst(self: *Lexer, span: Span) Token {
        self.pos += 1; // opening '\''
        switch (self.decodeEscape()) {
            .err => |msg| {
                self.record(span, "{s}", .{msg});
                return .{ .id = .error_tok, .span = span };
            },
            .elided => {
                self.record(span, "'\\&' does not denote a character", .{});
                return .{ .id = .error_tok, .span = span };
            },
            .char => |cp| {
                if (self.peekByte() != '\'') {
                    self.record(span, "malformed character constant (expected closing ')", .{});
                    return .{ .id = .error_tok, .span = span };
                }
                self.pos += 1; // closing '\''
                return .{ .id = .const_char, .span = span, .char_val = cp };
            },
        }
    }

    fn lexStringConst(self: *Lexer, span: Span) Token {
        self.pos += 1; // opening '"'
        var out: std.ArrayList(u8) = .empty;
        errdefer out.deinit(self.gpa);
        while (true) {
            const c = self.peekByte() orelse {
                self.record(span, "script ends inside unclosed string quotes", .{});
                out.deinit(self.gpa);
                return .{ .id = .error_tok, .span = span };
            };
            if (c == '"') {
                self.pos += 1;
                break;
            }
            switch (self.decodeEscape()) {
                .err => |msg| {
                    self.record(span, "{s}", .{msg});
                    out.deinit(self.gpa);
                    return .{ .id = .error_tok, .span = span };
                },
                .elided => {},
                .char => |cp| {
                    var buf: [4]u8 = undefined;
                    const n = std.unicode.utf8Encode(cp, &buf) catch {
                        self.record(span, "character 0x{x} cannot be encoded as UTF-8", .{cp});
                        out.deinit(self.gpa);
                        return .{ .id = .error_tok, .span = span };
                    };
                    out.appendSlice(self.gpa, buf[0..n]) catch {
                        out.deinit(self.gpa);
                        return .{ .id = .error_tok, .span = span };
                    };
                },
            }
        }
        const text = out.toOwnedSlice(self.gpa) catch return .{ .id = .error_tok, .span = span };
        return .{ .id = .const_str, .span = span, .text = text };
    }

    /// Scan a whole `%`-directive as one atomic token via
    /// `directives.zig`'s `Scanner` (its pathname/brace-block/alias grammar
    /// doesn't decompose into this lexer's ordinary token set — see that
    /// file's header). The parsed `Directive` is appended to `self.directives`;
    /// the returned token's `int_val` is its index there.
    fn lexDirective(self: *Lexer, span: Span) Token {
        self.pos += 1; // the '%'
        var scanner = directives_mod.Scanner.init(self.gpa, self.source, self.pos);
        defer scanner.deinit();
        const directive = scanner.scanDirective() catch {
            self.record(span, "out of memory scanning directive", .{});
            return .{ .id = .error_tok, .span = span };
        };
        for (scanner.diagnostics.items) |d| {
            const message = self.gpa.dupe(u8, d.message) catch continue;
            self.diagnostics.append(self.gpa, .{ .span = d.span, .message = message }) catch {
                self.gpa.free(message);
            };
        }
        self.pos = scanner.pos;
        const index = self.directives.items.len;
        self.directives.append(self.gpa, directive) catch {
            directive.deinit(self.gpa);
            self.record(span, "out of memory recording directive", .{});
            return .{ .id = .error_tok, .span = span };
        };
        return .{ .id = .directive, .span = span, .int_val = @intCast(index) };
    }
};

/// Convert a validated run of base-`base` digit characters to a plain
/// decimal digit string (arbitrary precision: repeated multiply-add on a
/// base-10 digit array), so `.const_int.text` never carries a source radix
/// prefix. Caller frees the result.
fn digitsToDecimal(gpa: std.mem.Allocator, digits: []const u8, base: u8) ![]u8 {
    var acc: std.ArrayList(u8) = .empty; // least-significant base-10 digit first
    defer acc.deinit(gpa);
    try acc.append(gpa, 0);
    for (digits) |d| {
        const v: u32 = std.fmt.charToDigit(d, base) catch unreachable; // caller validated
        var carry: u32 = v;
        for (acc.items) |*digit| {
            const val = @as(u32, digit.*) * base + carry;
            digit.* = @intCast(val % 10);
            carry = val / 10;
        }
        while (carry > 0) {
            try acc.append(gpa, @intCast(carry % 10));
            carry /= 10;
        }
    }
    var end = acc.items.len;
    while (end > 1 and acc.items[end - 1] == 0) end -= 1;
    const text = try gpa.alloc(u8, end);
    for (0..end) |i| text[i] = '0' + acc.items[end - 1 - i];
    return text;
}

/// Tokenize all of `source`, returning an owned slice ending in `.eof`
/// (caller frees with `gpa.free`). Diagnostics recorded during the scan are
/// discarded (nothing outlives `lexer.deinit()` above) — callers that need
/// them, or that need `.directive` tokens' payloads, want
/// `tokenizeWithDirectives` instead.
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

/// `tokenize`'s result plus the `.directive` tokens' structured payloads —
/// `tokens[i].int_val` for a `.directive` token indexes `directives`.
pub const TokenizeResult = struct {
    tokens: []Token,
    directives: []Directive,

    pub fn deinit(self: *TokenizeResult, gpa: std.mem.Allocator) void {
        gpa.free(self.tokens);
        for (self.directives) |d| d.deinit(gpa);
        gpa.free(self.directives);
    }
};

/// Like `tokenize`, but also returns the `Directive` payloads any
/// `.directive` tokens produced (see `TokenizeResult`).
pub fn tokenizeWithDirectives(gpa: std.mem.Allocator, source: *const Source) !TokenizeResult {
    var lexer = Lexer.init(gpa, source);
    defer lexer.deinit();
    var out: std.ArrayList(Token) = .empty;
    errdefer out.deinit(gpa);
    while (true) {
        const tok = lexer.next();
        try out.append(gpa, tok);
        if (tok.id == .eof) break;
    }
    return .{
        .tokens = try out.toOwnedSlice(gpa),
        .directives = try lexer.directives.toOwnedSlice(gpa),
    };
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

test "Lexer.next: decimal integer keeps its source digits verbatim" {
    const gpa = std.testing.allocator;
    var src = try testSource(gpa, "12345 0");
    defer src.deinit();
    var lex = Lexer.init(gpa, &src);
    defer lex.deinit();
    var tok = lex.next();
    try std.testing.expectEqual(TokenId.const_int, tok.id);
    try std.testing.expectEqualStrings("12345", tok.text);
    tok = lex.next();
    try std.testing.expectEqual(TokenId.const_int, tok.id);
    try std.testing.expectEqualStrings("0", tok.text);
}

test "Lexer.next: decimal floats — fraction, leading-dot, exponent forms" {
    const gpa = std.testing.allocator;
    var src = try testSource(gpa, "3.14 .5 1e10 1.5e-3 2E2");
    defer src.deinit();
    var lex = Lexer.init(gpa, &src);
    defer lex.deinit();
    const expected = [_]f64{ 3.14, 0.5, 1e10, 1.5e-3, 2e2 };
    for (expected) |v| {
        const tok = lex.next();
        try std.testing.expectEqual(TokenId.const_float, tok.id);
        try std.testing.expectApproxEqRel(v, tok.float_val, 1e-12);
    }
}

test "Lexer.next: float exponent over 3 significant digits is out of range" {
    const gpa = std.testing.allocator;
    var src = try testSource(gpa, "1e12345");
    defer src.deinit();
    var lex = Lexer.init(gpa, &src);
    defer lex.deinit();
    try std.testing.expectEqual(TokenId.error_tok, lex.next().id);
}

test "Lexer.next: float exponent with leading zeros only counts significant digits" {
    const gpa = std.testing.allocator;
    var src = try testSource(gpa, "1e0009");
    defer src.deinit();
    var lex = Lexer.init(gpa, &src);
    defer lex.deinit();
    const tok = lex.next();
    try std.testing.expectEqual(TokenId.const_float, tok.id);
    try std.testing.expectApproxEqRel(@as(f64, 1e9), tok.float_val, 1e-9);
}

test "Lexer.next: hex and octal integers convert to decimal text" {
    const gpa = std.testing.allocator;
    var src = try testSource(gpa, "0xff 0x1A2B3C 0o777");
    defer src.deinit();
    var lex = Lexer.init(gpa, &src);
    defer lex.deinit();
    var tok = lex.next();
    try std.testing.expectEqual(TokenId.const_int, tok.id);
    try std.testing.expectEqualStrings("255", tok.text);
    gpa.free(tok.text);
    tok = lex.next();
    try std.testing.expectEqual(TokenId.const_int, tok.id);
    try std.testing.expectEqualStrings("1715004", tok.text);
    gpa.free(tok.text);
    tok = lex.next();
    try std.testing.expectEqual(TokenId.const_int, tok.id);
    try std.testing.expectEqualStrings("511", tok.text);
    gpa.free(tok.text);
}

test "Lexer.next: hex-float is a deliberately unsupported error_tok" {
    const gpa = std.testing.allocator;
    var src = try testSource(gpa, "0x1.8p3");
    defer src.deinit();
    var lex = Lexer.init(gpa, &src);
    defer lex.deinit();
    try std.testing.expectEqual(TokenId.error_tok, lex.next().id);
}

test "Lexer.next: char constant — plain, and the common escapes" {
    const gpa = std.testing.allocator;
    var src = try testSource(gpa, "'a' '\\n' '\\x41' '\\65'");
    defer src.deinit();
    var lex = Lexer.init(gpa, &src);
    defer lex.deinit();
    const expected = [_]u21{ 'a', '\n', 'A', 65 };
    for (expected) |cp| {
        const tok = lex.next();
        try std.testing.expectEqual(TokenId.const_char, tok.id);
        try std.testing.expectEqual(cp, tok.char_val);
    }
}

test "Lexer.next: unterminated char constant is an error" {
    const gpa = std.testing.allocator;
    var src = try testSource(gpa, "'a");
    defer src.deinit();
    var lex = Lexer.init(gpa, &src);
    defer lex.deinit();
    try std.testing.expectEqual(TokenId.error_tok, lex.next().id);
}

test "Lexer.next: string constant decodes escapes and elides \\&" {
    const gpa = std.testing.allocator;
    var src = try testSource(gpa, "\"a\\nb\\&c\"");
    defer src.deinit();
    var lex = Lexer.init(gpa, &src);
    defer lex.deinit();
    const tok = lex.next();
    try std.testing.expectEqual(TokenId.const_str, tok.id);
    try std.testing.expectEqualStrings("a\nbc", tok.text);
    gpa.free(tok.text);
}

test "Lexer.next: unterminated string is an error, no leaked buffer" {
    const gpa = std.testing.allocator;
    var src = try testSource(gpa, "\"abc");
    defer src.deinit();
    var lex = Lexer.init(gpa, &src);
    defer lex.deinit();
    try std.testing.expectEqual(TokenId.error_tok, lex.next().id);
}

test "Lexer.next: an unescaped newline inside a string is an error" {
    const gpa = std.testing.allocator;
    var src = try testSource(gpa, "\"abc\ndef\"");
    defer src.deinit();
    var lex = Lexer.init(gpa, &src);
    defer lex.deinit();
    try std.testing.expectEqual(TokenId.error_tok, lex.next().id);
}

test "Lexer.next: a %-directive scans as one atomic .directive token" {
    const gpa = std.testing.allocator;
    var src = try testSource(gpa, "%export + -flooby\nsquare x = x * x\n");
    defer src.deinit();
    var lex = Lexer.init(gpa, &src);
    defer lex.deinit();
    const tok = lex.next();
    try std.testing.expectEqual(TokenId.directive, tok.id);
    try std.testing.expectEqual(@as(i64, 0), tok.int_val);
    try std.testing.expectEqual(@as(usize, 1), lex.directives.items.len);
    const d = lex.directives.items[0];
    try std.testing.expect(d == .export_list);
    try std.testing.expectEqualStrings("+ -flooby", d.export_list.parts_text);
    // Scanning resumes normally right after the directive's own line.
    const next_tok = lex.next();
    try std.testing.expectEqual(TokenId.name, next_tok.id);
    try std.testing.expectEqualStrings("square", next_tok.text);
}

test "Lexer.next: multiple directives each get their own index" {
    const gpa = std.testing.allocator;
    var src = try testSource(gpa, "%include \"mylib\"\n%free { elem :: type }\n");
    defer src.deinit();
    var lex = Lexer.init(gpa, &src);
    defer lex.deinit();
    const first = lex.next();
    try std.testing.expectEqual(TokenId.directive, first.id);
    try std.testing.expectEqual(@as(i64, 0), first.int_val);
    const second = lex.next();
    try std.testing.expectEqual(TokenId.directive, second.id);
    try std.testing.expectEqual(@as(i64, 1), second.int_val);
    try std.testing.expectEqual(@as(usize, 2), lex.directives.items.len);
    try std.testing.expect(lex.directives.items[0] == .include);
    try std.testing.expectEqualStrings("mylib", lex.directives.items[0].include.path);
    try std.testing.expect(lex.directives.items[1] == .free);
}

test "Lexer.next: an unknown directive keyword is recorded as a diagnostic, not error_tok" {
    const gpa = std.testing.allocator;
    var src = try testSource(gpa, "%bogus foo bar\n");
    defer src.deinit();
    var lex = Lexer.init(gpa, &src);
    defer lex.deinit();
    const tok = lex.next();
    try std.testing.expectEqual(TokenId.directive, tok.id);
    try std.testing.expect(lex.directives.items[0] == .unknown);
    try std.testing.expectEqual(@as(usize, 1), lex.diagnostics.items.len);
}

test "tokenizeWithDirectives: collects both the token stream and directive payloads" {
    const gpa = std.testing.allocator;
    var src = try testSource(gpa, "%export +\nsquare x = x * x\n");
    defer src.deinit();
    var result = try tokenizeWithDirectives(gpa, &src);
    defer result.deinit(gpa);
    try std.testing.expectEqual(TokenId.directive, result.tokens[0].id);
    try std.testing.expectEqual(@as(usize, 1), result.directives.len);
    try std.testing.expect(result.directives[0] == .export_list);
    try std.testing.expectEqualStrings("square", result.tokens[1].text);
}
