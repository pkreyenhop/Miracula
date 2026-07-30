//! syntax/parser_test.zig — the inline test suite for parser.zig, moved to a
//! companion file for the Go port's <1000-line file ratchet
//! (docs/GO_PORT_PLAN.md P4). It is the root of the `parser-tests` build
//! target: it imports parser.zig one-way (no cycle) and also aggregates
//! lexer.zig's moved tests via `_ = @import("lexer_test.zig")`.

const std = @import("std");
const parser = @import("parser.zig");
const Parser = parser.Parser;
const parseType = parser.parseType;
const parseTypeSpec = parser.parseTypeSpec;
const parsePat = parser.parsePat;
const parseExpr = parser.parseExpr;
const parseRhs = parser.parseRhs;
const parseDef = parser.parseDef;
const parseScript = parser.parseScript;
const ast = parser.ast;
const Token = parser.tf.Token;
const TokenId = parser.tf.TokenId;

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test "parseType: simple name" {
    const gpa = std.testing.allocator;
    const tokens = [_]Token{
        .{ .id = .name, .span = .{ .line = 1, .col = 1 }, .text = "num" },
        .{ .id = .eof, .span = .{ .line = 1, .col = 4 } },
    };
    var p = Parser.init(gpa, &tokens);
    const te = try parseType(&p);
    try std.testing.expectEqual(std.meta.Tag(ast.TypeExpr).type_name, std.meta.activeTag(te));
    try std.testing.expectEqualStrings("num", te.type_name.name);
}

test "parseType: list type [num]" {
    const gpa = std.testing.allocator;
    const tokens = [_]Token{
        .{ .id = .lbracket, .span = .{ .line = 1, .col = 1 } },
        .{ .id = .name, .span = .{ .line = 1, .col = 2 }, .text = "num" },
        .{ .id = .rbracket, .span = .{ .line = 1, .col = 5 } },
        .{ .id = .eof, .span = .{ .line = 1, .col = 6 } },
    };
    var p = Parser.init(gpa, &tokens);
    const te = try parseType(&p);
    defer gpa.destroy(te.list);
    try std.testing.expectEqual(std.meta.Tag(ast.TypeExpr).list, std.meta.activeTag(te));
    try std.testing.expectEqualStrings("num", te.list.type_name.name);
}

test "parseType: arrow type num -> bool" {
    const gpa = std.testing.allocator;
    const tokens = [_]Token{
        .{ .id = .name, .span = .{ .line = 1, .col = 1 }, .text = "num" },
        .{ .id = .arrow, .span = .{ .line = 1, .col = 5 } },
        .{ .id = .name, .span = .{ .line = 1, .col = 8 }, .text = "bool" },
        .{ .id = .eof, .span = .{ .line = 1, .col = 12 } },
    };
    var p = Parser.init(gpa, &tokens);
    const te = try parseType(&p);
    defer {
        gpa.destroy(te.arrow.from);
        gpa.destroy(te.arrow.to);
    }
    try std.testing.expectEqual(std.meta.Tag(ast.TypeExpr).arrow, std.meta.activeTag(te));
    try std.testing.expectEqualStrings("num", te.arrow.from.type_name.name);
    try std.testing.expectEqualStrings("bool", te.arrow.to.type_name.name);
}

test "parseTap: type application Tree *a" {
    const gpa = std.testing.allocator;
    const tokens = [_]Token{
        .{ .id = .name, .span = .{ .line = 1, .col = 1 }, .text = "Tree" },
        .{ .id = .typevar, .span = .{ .line = 1, .col = 6 }, .text = "*a" },
        .{ .id = .eof, .span = .{ .line = 1, .col = 9 } },
    };
    var p = Parser.init(gpa, &tokens);
    const te = try parseType(&p);
    defer {
        gpa.destroy(te.type_app.func);
        gpa.free(te.type_app.args);
    }
    try std.testing.expectEqual(std.meta.Tag(ast.TypeExpr).type_app, std.meta.activeTag(te));
    try std.testing.expectEqualStrings("Tree", te.type_app.func.type_name.name);
    try std.testing.expectEqual(@as(usize, 1), te.type_app.args.len);
    try std.testing.expectEqualStrings("*a", te.type_app.args[0].type_var.name);
}

test "parsePat: cons pattern x : xs" {
    const gpa = std.testing.allocator;
    const tokens = [_]Token{
        .{ .id = .name, .span = .{ .line = 1, .col = 1 }, .text = "x" },
        .{ .id = .cons, .span = .{ .line = 1, .col = 3 } }, // `:` is .cons, not .colon
        .{ .id = .name, .span = .{ .line = 1, .col = 5 }, .text = "xs" },
        .{ .id = .eof, .span = .{ .line = 1, .col = 7 } },
    };
    var p = Parser.init(gpa, &tokens);
    const pat = try parsePat(&p);
    defer {
        gpa.destroy(pat.cons_pat.head);
        gpa.destroy(pat.cons_pat.tail);
    }
    try std.testing.expectEqual(std.meta.Tag(ast.Pat).cons_pat, std.meta.activeTag(pat));
    try std.testing.expectEqualStrings("x", pat.cons_pat.head.name.text);
    try std.testing.expectEqualStrings("xs", pat.cons_pat.tail.name.text);
}

test "parsePat: empty list pattern" {
    const gpa = std.testing.allocator;
    const tokens = [_]Token{
        .{ .id = .lbracket, .span = .{ .line = 1, .col = 1 } },
        .{ .id = .rbracket, .span = .{ .line = 1, .col = 2 } },
        .{ .id = .eof, .span = .{ .line = 1, .col = 3 } },
    };
    var p = Parser.init(gpa, &tokens);
    const pat = try parsePat(&p);
    defer gpa.free(pat.list);
    try std.testing.expectEqual(std.meta.Tag(ast.Pat).list, std.meta.activeTag(pat));
    try std.testing.expectEqual(@as(usize, 0), pat.list.len);
}

test "parseScript: error recovery records diagnostic and parses remaining items" {
    // Use an arena so all parser allocations (including diagnostic messages)
    // are freed together without per-allocation tracking.
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    // Tokens: bare `=` (syntax error), OFFSIDE, then `id x = x` (valid def).
    const tokens = [_]Token{
        // Bad item: `=` cannot start a definition LHS
        .{ .id = .eq, .span = .{ .line = 1, .col = 1 } },
        // Layout separator between items
        .{ .id = .offside, .span = .{ .line = 2, .col = 1 } },
        // Valid item: id x = x
        .{ .id = .name, .span = .{ .line = 2, .col = 1 }, .text = "id" },
        .{ .id = .name, .span = .{ .line = 2, .col = 4 }, .text = "x" },
        .{ .id = .eq, .span = .{ .line = 2, .col = 6 } },
        .{ .id = .name, .span = .{ .line = 2, .col = 8 }, .text = "x" },
        .{ .id = .eof, .span = .{ .line = 2, .col = 9 } },
    };
    var p = Parser.init(gpa, &tokens);
    const script = try parseScript(&p);

    // Exactly one diagnostic for the bad item
    try std.testing.expectEqual(@as(usize, 1), p.diagnostics.items.len);
    // Exactly one successfully parsed item
    try std.testing.expectEqual(@as(usize, 1), script.items.len);
    try std.testing.expectEqual(
        std.meta.Tag(ast.TopLevel).definition,
        std.meta.activeTag(script.items[0]),
    );
}

test {
    // lexer.zig's inline tests were moved to `lexer_test.zig` for the Go
    // port's <1000-line file ratchet (docs/GO_PORT_PLAN.md P4). Aggregating
    // them here (the syntax test-target root imports lexer one-way) keeps them
    // in the same test run without a lexer<->lexer_test import cycle.
    _ = @import("lexer_test.zig");
}
