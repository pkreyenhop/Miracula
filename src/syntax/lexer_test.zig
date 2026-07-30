//! syntax/lexer_test.zig — the inline test suite for lexer.zig, moved to a
//! companion file for the Go port's <1000-line file ratchet
//! (docs/GO_PORT_PLAN.md P4). Same tests, same names; lexer.zig aggregates
//! them via `test { _ = @import("lexer_test.zig"); }` so they run unchanged.

const std = @import("std");
const lexer = @import("lexer.zig");
const Lexer = lexer.Lexer;
const TokenId = lexer.TokenId;
const Token = lexer.Token;
const Span = lexer.Span;
const Directive = lexer.Directive;
const Diagnostic = lexer.Diagnostic;
const tokenize = lexer.tokenize;
const tokenizeWithDirectives = lexer.tokenizeWithDirectives;
const Source = @import("source.zig").Source;

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
    var src = try testSource(gpa, "- < > ~ = + . : ^ ! # & | ( ) [ ] { } , ; ? /");
    defer src.deinit();
    var lex = Lexer.init(gpa, &src);
    defer lex.deinit();
    const expected = [_]TokenId{ .minus, .lt, .gt, .tilde, .eq, .plus, .dot, .cons, .caret, .bang, .hash, .amp, .pipe, .lparen, .rparen, .lbracket, .rbracket, .lbrace, .rbrace, .comma, .semicolon, .question, .slash };
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

test "Lexer.next: $name and $Cname are infix notation for a prefix function" {
    const gpa = std.testing.allocator;
    // "max" isn't a plain-position reserved word (unlike "div"/"mod", which
    // already have direct infix syntax and so aren't realistic $-examples).
    var src = try testSource(gpa, "x $max y $Foo z");
    defer src.deinit();
    var lex = Lexer.init(gpa, &src);
    defer lex.deinit();
    _ = lex.next(); // x
    var tok = lex.next();
    try std.testing.expectEqual(TokenId.infixname, tok.id);
    try std.testing.expectEqualStrings("max", tok.text);
    _ = lex.next(); // y
    tok = lex.next();
    try std.testing.expectEqual(TokenId.infixcname, tok.id);
    try std.testing.expectEqualStrings("Foo", tok.text);
}

test "Lexer.next: $$ is its own .dollars token" {
    const gpa = std.testing.allocator;
    var src = try testSource(gpa, "$$");
    defer src.deinit();
    var lex = Lexer.init(gpa, &src);
    defer lex.deinit();
    try std.testing.expectEqual(TokenId.dollars, lex.next().id);
}

test "Lexer.next: $ forms outside $name/$Cname/$$ are out of scope, error_tok" {
    const gpa = std.testing.allocator;
    var src = try testSource(gpa, "$5");
    defer src.deinit();
    var lex = Lexer.init(gpa, &src);
    defer lex.deinit();
    try std.testing.expectEqual(TokenId.error_tok, lex.next().id);
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

test "Lexer.next: hex-float with a fraction and exponent" {
    const gpa = std.testing.allocator;
    var src = try testSource(gpa, "0x1.8p3");
    defer src.deinit();
    var lex = Lexer.init(gpa, &src);
    defer lex.deinit();
    const tok = lex.next();
    try std.testing.expectEqual(TokenId.const_float, tok.id);
    try std.testing.expectApproxEqRel(@as(f64, 12.0), tok.float_val, 1e-12);
}

test "Lexer.next: hex-float with no exponent is legal (matches hexnumeral's leniency)" {
    const gpa = std.testing.allocator;
    var src = try testSource(gpa, "0x1.8");
    defer src.deinit();
    var lex = Lexer.init(gpa, &src);
    defer lex.deinit();
    const tok = lex.next();
    try std.testing.expectEqual(TokenId.const_float, tok.id);
    try std.testing.expectApproxEqRel(@as(f64, 1.5), tok.float_val, 1e-12);
}

test "Lexer.next: hex-float with a leading-dot fraction and no digits before it" {
    const gpa = std.testing.allocator;
    var src = try testSource(gpa, "0x.8p3");
    defer src.deinit();
    var lex = Lexer.init(gpa, &src);
    defer lex.deinit();
    const tok = lex.next();
    try std.testing.expectEqual(TokenId.const_float, tok.id);
    try std.testing.expectApproxEqRel(@as(f64, 4.0), tok.float_val, 1e-12);
}

test "Lexer.next: hex-float with just a 'p' exponent, no fraction" {
    const gpa = std.testing.allocator;
    var src = try testSource(gpa, "0x1p4");
    defer src.deinit();
    var lex = Lexer.init(gpa, &src);
    defer lex.deinit();
    const tok = lex.next();
    try std.testing.expectEqual(TokenId.const_float, tok.id);
    try std.testing.expectApproxEqRel(@as(f64, 16.0), tok.float_val, 1e-12);
}

test "Lexer.next: hex-float exponent with no digits is an error" {
    const gpa = std.testing.allocator;
    var src = try testSource(gpa, "0x1.8p");
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
