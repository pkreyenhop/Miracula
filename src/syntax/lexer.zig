//! syntax/lexer.zig — the native tokenizer core (docs/GoReady.md Phase 1
//! step 2), replacing (eventually) `parser/lex.zig`'s `yylex`.
//!
//! Scope of this increment: whitespace/comment skipping, identifiers/keywords,
//! typevars/`*`, the fixed operator/punctuation set, numerals (decimal/hex/
//! octal integers, decimal and hex floats), string/char literals with the
//! full escape table, `%`-directives, and `$name`/`$Cname`/`$$` infix
//! notation. Not yet implemented, on purpose (kept as separately-staged,
//! separately-verified work per the plan):
//!
//!   - Char classes (`` `[...]` ``, `%bnf`/`%lex`-only) — deferred with
//!     `%bnf`/`%lex` themselves, which the plan orders last (hairiest,
//!     least-covered corner).
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
const tf = @import("token_filter.zig");
const Source = @import("source.zig").Source;
const directives_mod = @import("directives.zig");

pub const Token = tf.Token;
pub const TokenId = tf.TokenId;
pub const Span = tf.Span;
pub const Directive = directives_mod.Directive;

/// A structured lex error recorded during scanning. Re-exported from
/// `token_filter.zig` (Phase 2 step 2) — shared with `parser/parser.zig`'s
/// and `syntax/directives.zig`'s own diagnostics; `token_filter.zig` has
/// no dependencies of its own, so this doesn't pull in the legacy
/// `parser/parser.zig` tree (the reason this was a separate, duplicated
/// type before).
///
/// `stream`/`add_prefix` exist because legacy's diagnostic printing isn't
/// uniform across call sites: the shared `syntax()` helper
/// (`compiler/setup.zig`) writes to *stderr* with a "syntax error: " prefix
/// it adds itself; other call sites (`errclass()`'s string/char-const
/// escape errors, `directive()`'s "unknown directive") print directly to
/// *stdout*, ad hoc, sometimes with their own "syntax error: " text already
/// in the literal, sometimes not. Each diagnostic records which so the
/// caller (`parser_api.zig`) can match exactly instead of assuming one.
pub const Diagnostic = tf.Diagnostic;

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

    /// Record a diagnostic matching legacy's `syntax()` helper: stderr, with
    /// a "syntax error: " prefix added at print time (not baked into
    /// `message` itself).
    fn record(self: *Lexer, span: Span, comptime fmt: []const u8, args: anytype) void {
        const msg = std.fmt.allocPrint(self.gpa, fmt, args) catch return;
        self.diagnostics.append(self.gpa, .{ .span = span, .message = msg }) catch {};
    }

    /// Record a diagnostic matching legacy's ad hoc `word.print(...)`
    /// call sites (`errclass()`, `directive()`'s "unknown directive"):
    /// stdout, `message` printed exactly as given, no added prefix (bake
    /// "syntax error: " into `fmt` directly if the specific call site needs
    /// it — `directive()`'s does, `errclass()`'s doesn't).
    fn recordStdout(self: *Lexer, span: Span, comptime fmt: []const u8, args: anytype) void {
        const msg = std.fmt.allocPrint(self.gpa, fmt, args) catch return;
        self.diagnostics.append(self.gpa, .{ .span = span, .message = msg, .stream = .stdout, .add_prefix = false }) catch {};
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
        if (ch == '$') return self.lexDollar(span);

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
            // Verified against lex.zig's own '/' case: a bare '/' is the
            // (floating-point) division operator, .slash -- already in
            // token_filter.zig's vocabulary (lex_bridge.zig maps it too),
            // just never actually produced here. '//' (word.DIAG,
            // "diagonalise" for infinite list comprehensions) has no
            // TokenId or lex_bridge.zig mapping at all -- out of scope,
            // matching this lexer's other documented gaps, not this fix.
            '/' => .{ .id = .slash, .span = span },
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

    /// `$name`/`$Cname` — Miranda's notation for using an ordinarily-prefix
    /// function as an infix operator (`` x $mod y ``, equivalent to
    /// `mod x y`); `$$` is its own `.dollars` token. Verified against
    /// `lex.zig`'s `'$'` case, not guessed (an earlier, unverified draft of
    /// this file's header described this as backtick notation — wrong; real
    /// Miranda uses `$`, backtick has no general lexical meaning here).
    ///
    /// The other `$`-forms `lex.zig` recognizes (`$1`-`$9` interactive
    /// history references, `$-`/`$:-`/`$+` REPL stdin/stdinb constants, `$#`
    /// a `%lex`-only internal) build heap values or read interpreter state
    /// directly in the legacy lexer — out of scope for a pure, heap-free
    /// lexer (this file's own design constraint) and not part of ordinary
    /// compiled-script syntax anyway. `error_tok`, not a silent mis-scan.
    /// A `$` followed by a *keyword* (`$where`, `$if`, …) is also out of
    /// scope here (legacy falls through to a bare `'$'` char token in that
    /// case, which has no equivalent in this token vocabulary) — vanishingly
    /// unlikely in real source, `error_tok` rather than misclassifying it as
    /// an infix name.
    fn lexDollar(self: *Lexer, span: Span) Token {
        self.pos += 1; // the '$'
        if (self.peekByte() == '$') {
            self.pos += 1;
            return .{ .id = .dollars, .span = span };
        }
        if (self.peekByte()) |c| {
            if (std.ascii.isAlphabetic(c)) {
                const start = self.pos;
                self.pos += 1;
                while (self.peekByte()) |cc| {
                    if (!isIdentCont(cc)) break;
                    self.pos += 1;
                }
                const text = self.source.bytes[start..self.pos];
                if (keywords.get(text) == null) {
                    const id: TokenId = if (std.ascii.isUpper(text[0])) .infixcname else .infixname;
                    return .{ .id = id, .span = span, .text = text };
                }
            }
        }
        self.record(span, "unexpected symbol after '$' (only $name, $Cname, $$ are supported)", .{});
        return .{ .id = .error_tok, .span = span };
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

    /// Scan a numeral: `0x`/`0o` integer, `0x` hex-float, or decimal
    /// integer/float (verified against `lex.zig`'s `numeral`/`hexnumeral`/
    /// `octnumeral`).
    fn lexNumeral(self: *Lexer, start: usize, span: Span) Token {
        if (self.peekByte() == '0' and (self.peekByteAt(1) == 'x' or self.peekByteAt(1) == 'X')) {
            return self.lexRadixInt(start, span, 16);
        }
        if (self.peekByte() == '0' and (self.peekByteAt(1) == 'o' or self.peekByteAt(1) == 'O')) {
            return self.lexRadixInt(start, span, 8);
        }
        return self.lexDecimal(start, span);
    }

    fn isRadixDigit(c: u8, base: u8) bool {
        _ = std.fmt.charToDigit(c, base) catch return false;
        return true;
    }

    /// `0x`/`0o` integer literal, or (base 16 only) a hex-float continuation
    /// (`lexHexFloat`) once a `.`/`p`/`P` follows the digits. Integer digits
    /// are converted to decimal text on the spot (`digitsToDecimal`) — see
    /// the file header for why.
    fn lexRadixInt(self: *Lexer, start: usize, span: Span, base: u8) Token {
        self.pos += 2; // the "0x"/"0o" (or upper-case) prefix
        const digits_start = self.pos;
        while (self.peekByte()) |c| {
            if (!isRadixDigit(c, base)) break;
            self.pos += 1;
        }
        // Matches `hexnumeral`'s own grammar: a hex-float's fraction may lead
        // with `.` before any digits (`0x.8p3`), so this check comes before
        // the "at least one digit" requirement below, not after.
        if (base == 16 and (self.peekByte() == '.' or self.peekByte() == 'p' or self.peekByte() == 'P')) {
            return self.lexHexFloat(start, span);
        }
        if (self.pos == digits_start) {
            self.record(span, "malformed base-{d} number: no digits after the prefix", .{base});
            return .{ .id = .error_tok, .span = span };
        }
        const digits = self.source.bytes[digits_start..self.pos];
        const decimal = digitsToDecimal(self.gpa, digits, base) catch {
            self.record(span, "out of memory converting numeral", .{});
            return .{ .id = .error_tok, .span = span };
        };
        return .{ .id = .const_int, .span = span, .text = decimal };
    }

    /// A hex-float continuation after `0x`'s digits: an optional `.`-fraction
    /// (itself hex digits, possibly none — `0x.8p3` is legal, matching
    /// `hexnumeral`'s own grammar) and/or a `p`/`P` exponent (decimal digits,
    /// optional sign). Unlike decimal floats, the exponent is *not* required
    /// (`0x1.8` alone is a legal hex-float, matching `hexnumeral`'s lenient
    /// `sscanf("%lf", ...)` — Zig's `parseFloat` accepts the same shape,
    /// verified: it defaults a missing exponent to 0). The whole matched
    /// text (from `0x`/`0X` onward) is handed to `parseFloat` rather than
    /// hand-rolling hex-float arithmetic here.
    fn lexHexFloat(self: *Lexer, start: usize, span: Span) Token {
        if (self.peekByte() == '.') {
            self.pos += 1;
            while (self.peekByte()) |c| {
                if (!isRadixDigit(c, 16)) break;
                self.pos += 1;
            }
        }
        if (self.peekByte() == 'p' or self.peekByte() == 'P') {
            self.pos += 1;
            if (self.peekByte() == '+' or self.peekByte() == '-') self.pos += 1;
            const exp_start = self.pos;
            while (self.peekByte()) |c| {
                if (!std.ascii.isDigit(c)) break;
                self.pos += 1;
            }
            if (self.pos == exp_start) {
                self.record(span, "malformed hex float: no digits in the exponent", .{});
                return .{ .id = .error_tok, .span = span };
            }
        }
        const text = self.source.bytes[start..self.pos];
        if (text.len > 60) {
            self.record(span, "illegal floating point constant (too many digits)", .{});
            return .{ .id = .error_tok, .span = span };
        }
        const value = std.fmt.parseFloat(f64, text) catch {
            self.record(span, "malformed hex float '{s}'", .{text});
            return .{ .id = .error_tok, .span = span };
        };
        return .{ .id = .const_float, .span = span, .float_val = value };
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

    /// The bad-escape cases `parser/lex.zig`'s `errclass()` reports —
    /// mirrors its `val` codes (-2, -3, -5, -6; -4, decimal-escape-out-of-
    /// range, is unreachable from `getlitch()`, the function this decoder
    /// matches, so it's not modeled here; -7, `\&` outside a string, is
    /// `.elided` at the `Escape` level, not an error here). `errclass()`'s
    /// exact wording needs the string/char-const *context* this decoder
    /// doesn't have, and its own newline/EOF handling differs entirely by
    /// caller (`string()` vs `lexCharConst`) rather than sharing one
    /// message — callers (`lexCharConst`/`lexStringConst`) special-case
    /// `.newline`/`.eof` themselves and delegate the rest to
    /// `recordEscapeError`.
    const EscapeErrorKind = union(enum) {
        newline,
        eof,
        invalid_utf8,
        unterminated_escape,
        no_hex_digits,
        hex_out_of_range,
        unrecognised_escape: u8,
    };

    /// One decoded logical character from a string/char literal, or `.elided`
    /// (the `\&` no-op escape — legal only inside a string), or an error.
    const Escape = union(enum) {
        char: u21,
        elided,
        err: EscapeErrorKind,
    };

    /// Decode one character at `self.pos`: a raw byte (UTF-8-decoded if its
    /// top bit is set — see the file header on the UTF-8-always choice), or a
    /// backslash escape. Verified digit-for-digit against `lex.zig`'s
    /// `getlitch`: `\a\b\f\n\r\t\v`, `\x`/`\X` hex (4/6 digits), up to 3
    /// decimal digits, `\'\"\\\``, `\&` (elides), `\<newline>` (line
    /// continuation, recurses for the next real character). An unescaped
    /// literal newline is always an error.
    fn decodeEscape(self: *Lexer) Escape {
        const ch = self.peekByte() orelse return .{ .err = .eof };
        if (ch == '\n') return .{ .err = .newline };
        if (ch != '\\') {
            if (ch < 0x80) {
                self.pos += 1;
                return .{ .char = ch };
            }
            const len = std.unicode.utf8ByteSequenceLength(ch) catch {
                self.pos += 1;
                return .{ .err = .invalid_utf8 };
            };
            if (self.pos + len > self.source.bytes.len) {
                self.pos += 1;
                return .{ .err = .invalid_utf8 };
            }
            const seq = self.source.bytes[self.pos .. self.pos + len];
            const cp = std.unicode.utf8Decode(seq) catch {
                self.pos += 1;
                return .{ .err = .invalid_utf8 };
            };
            self.pos += len;
            return .{ .char = cp };
        }
        self.pos += 1; // consume '\'
        const esc = self.peekByte() orelse return .{ .err = .unterminated_escape };
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
                if (count == 0) return .{ .err = .no_hex_digits };
                if (value > 0x10ffff) return .{ .err = .hex_out_of_range };
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
            else => return .{ .err = .{ .unrecognised_escape = esc } },
        }
    }

    /// Report the `errclass()`-style escape errors with `errclass()`'s exact
    /// wording (`ctx` is "string" or "char const"). `.newline`/`.eof` aren't
    /// handled here — `errclass()` never sees them either; `string()`/
    /// `lexCharConst()` report those with their own, unrelated wording
    /// (see the call sites).
    fn recordEscapeError(self: *Lexer, span: Span, kind: EscapeErrorKind, ctx: []const u8) void {
        switch (kind) {
            .newline, .eof => unreachable, // handled by each caller directly
            .invalid_utf8 => self.recordStdout(span, "unrecognised character in {s}(UTF8 error)", .{ctx}),
            .unterminated_escape => self.recordStdout(span, "unterminated escape sequence in {s}", .{ctx}),
            .no_hex_digits => self.recordStdout(span, "\\x with no xdigits in {s}", .{ctx}),
            .hex_out_of_range => self.recordStdout(span, "hexadecimal escape out of range in {s}", .{ctx}),
            .unrecognised_escape => |c| self.recordStdout(span, "unrecognised escape \\{c} in {s}", .{ c, ctx }),
        }
    }

    /// Scans a `'c'` character constant. Verified against `lex.zig`'s
    /// `lexCharConst`: an unescaped newline *or* a missing closing `'` are
    /// the same "improperly terminated char const" message (via `syntax()`
    /// — unlike `string()`, which reports these two cases differently and
    /// doesn't cover the missing-terminator case for them at all as a
    /// distinct message).
    fn lexCharConst(self: *Lexer, span: Span) Token {
        self.pos += 1; // opening '\''
        switch (self.decodeEscape()) {
            .err => |kind| {
                switch (kind) {
                    .newline, .eof => self.record(span, "improperly terminated char const", .{}),
                    else => self.recordEscapeError(span, kind, "char const"),
                }
                return .{ .id = .error_tok, .span = span };
            },
            .elided => {
                self.recordStdout(span, "illegal use of \\& in char const", .{});
                return .{ .id = .error_tok, .span = span };
            },
            .char => |cp| {
                if (self.peekByte() != '\'') {
                    self.record(span, "improperly terminated char const", .{});
                    return .{ .id = .error_tok, .span = span };
                }
                self.pos += 1; // closing '\''
                return .{ .id = .const_char, .span = span, .char_val = cp };
            },
        }
    }

    /// Scans a `"..."` string constant. Verified against `lex.zig`'s
    /// `string()`: an unescaped newline is `syntax()` (stderr, "syntax
    /// error: " prefix added there); running out of input first is a
    /// separate, stdout-routed message with its own baked-in "syntax
    /// error: " text (this decoder's version doesn't replicate `string()`'s
    /// further behaviour of echoing back the partial string content — not
    /// exercised by the shipped corpus, a known simplification).
    fn lexStringConst(self: *Lexer, span: Span) Token {
        self.pos += 1; // opening '"'
        var out: std.ArrayList(u8) = .empty;
        errdefer out.deinit(self.gpa);
        while (true) {
            const c = self.peekByte() orelse {
                self.recordStdout(span, "syntax error: script ends inside unclosed string quotes", .{});
                out.deinit(self.gpa);
                return .{ .id = .error_tok, .span = span };
            };
            if (c == '"') {
                self.pos += 1;
                break;
            }
            switch (self.decodeEscape()) {
                .err => |kind| {
                    switch (kind) {
                        .newline => self.record(span, "non-escaped newline encountered inside string quotes", .{}),
                        .eof => self.recordStdout(span, "syntax error: script ends inside unclosed string quotes", .{}),
                        else => self.recordEscapeError(span, kind, "string"),
                    }
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
            self.diagnostics.append(self.gpa, .{ .span = d.span, .message = message, .stream = d.stream, .add_prefix = d.add_prefix }) catch {
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

/// `tokenize`'s result plus the `.directive` tokens' structured payloads and
/// any lexical diagnostics (unterminated strings, bad escapes, unknown
/// directive keywords, …) — `tokens[i].int_val` for a `.directive` token
/// indexes `directives`.
pub const TokenizeResult = struct {
    tokens: []Token,
    directives: []Directive,
    diagnostics: []Diagnostic,

    pub fn deinit(self: *TokenizeResult, gpa: std.mem.Allocator) void {
        gpa.free(self.tokens);
        for (self.directives) |d| d.deinit(gpa);
        gpa.free(self.directives);
        for (self.diagnostics) |d| gpa.free(d.message);
        gpa.free(self.diagnostics);
    }
};

/// Like `tokenize`, but also returns the `Directive` payloads any
/// `.directive` tokens produced, and any diagnostics recorded during the
/// scan (see `TokenizeResult`).
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
        .diagnostics = try lexer.diagnostics.toOwnedSlice(gpa),
    };
}
