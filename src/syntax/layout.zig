//! syntax/layout.zig — the offside/layout rule as an independent token-stream
//! pass (docs/ZIG_NATIVE_PLAN.md Phase 1 step 3).
//!
//! `parser/lex.zig`'s offside handling is NOT a standalone pass: `yylex()`
//! checks the current token's column against the lex state's `lmargin` field,
//! a value the
//! **parser** pushes/pops via `setlmargin`/`unsetlmargin` at specific
//! syntactic positions (after `where`, `%bnf`/`%lex` bodies, `abstype...with`)
//! — lexer and parser share mutable state. Reproducing that exact coupling
//! in a native rewrite would just relocate the entanglement, not remove it.
//!
//! This module instead implements the well-known alternative: a **standalone
//! layout algorithm** (the same family as Haskell's layout rule, which the
//! Miranda offside rule predates and closely resembles) that derives every
//! `.offside`/`.elseq` injection purely from the token stream — column and
//! line-number information already present in each `Token`'s `Span`, plus a
//! small stack of open margins. No parser callback, no shared mutable state.
//!
//! **Algorithm.** A stack of margin columns. The very first token, and the
//! first token after `where`/`with`, pushes a new margin at its column — but
//! only if that column is actually greater than the enclosing margin (a
//! `where` with nothing indented under it opens no new context, matching
//! `lex.zig`'s `setlmargin`'s own `if (lmargin < col)` guard). For every
//! other token that is the first on its source line, compare its column `c`
//! to the top margin `m`:
//!   - `c > m`: continuation of the current item, no token injected.
//!   - `c == m`: a new sibling in the same block — inject `.elseq` if the
//!     token is `=` (a realigned continuation equation), else `.offside`.
//!   - `c < m`: pop the margin (injecting `.offside`) and re-compare against
//!     the new top; repeat until `c >= m` or the stack empties, then apply
//!     the `==`/`>` rule above to whatever margin remains.
//! `.eof` pops every remaining margin (one `.offside` each) before the `.eof`
//! token itself, so an unterminated block still closes cleanly.
//!
//! **Verified against, not guessed from, two independent sources (2026-07-06):**
//! `parser/lex.zig`'s `setlmargin`/`unsetlmargin` (the producer side — how
//! and when a margin is pushed/popped) *and* `parser/parser.zig`'s actual
//! token consumption (the consumer side — `parseScript`'s
//! `while (p.eat(.offside) or p.eat(.elseq) or p.eat(.semicolon)) {}` between
//! *every* top-level item, and `parseWhereDefs`'s identical tolerance between
//! where-clause siblings) — both `pub fn`s in a file with zero heap/C
//! dependency, i.e. genuinely independent of `lex.zig`'s own internal
//! bookkeeping. Both confirm a separator token is expected even between
//! *same-margin* siblings, which `lex.zig`'s single `col < lmargin` check
//! (read in isolation) does not obviously produce — reconciling that exactly
//! would need instrumenting `yylex` itself, which this module does not do.
//! **Not yet differentially verified** against the legacy lexer's actual
//! token-for-token output (Phase 1 step 4's dual-run harness, still to come)
//! — treat this as a well-reasoned first implementation, not a proven one.
//!
//! An explicit `.semicolon` in the source always separates items regardless
//! of column (matches `lex.zig`'s `lexSemicolonOrElseq`) — this pass never
//! removes or reinterprets semicolons, only injects `.offside`/`.elseq`.
//!
//! Not yet wired into `parser_api.zig` — the legacy lexer/layout remain the
//! production path until Phase 1 step 7.
//!
//! Tests: applyLayout — one test per shape (flat script, where, nested
//! where, `=`-realignment, explicit semicolon, EOF closes open blocks), plus
//! an end-to-end check that feeds the result into the real `parser.zig`.

const std = @import("std");
const tf = @import("../parser/token_filter.zig");

pub const Token = tf.Token;
pub const TokenId = tf.TokenId;
pub const Span = tf.Span;

/// Apply the offside/layout rule to a flat token stream (as produced by
/// `syntax/lexer.zig`, no `.offside`/`.elseq` yet), returning a new,
/// caller-owned slice with those tokens injected. `tokens` must end in
/// `.eof`. Injected tokens carry the triggering token's `Span` (or the
/// `.eof` token's, for the final unwind) and no `.text`/`.int_val`/etc.
pub fn applyLayout(gpa: std.mem.Allocator, tokens: []const Token) ![]Token {
    var out: std.ArrayList(Token) = .empty;
    errdefer out.deinit(gpa);
    var stack: std.ArrayList(u32) = .empty;
    defer stack.deinit(gpa);

    var expect_push = true; // the very first token opens the top-level margin
    var prev_line: u32 = 0;
    var first = true;

    for (tokens) |t| {
        if (t.id == .eof) {
            while (stack.items.len > 0) {
                _ = stack.pop();
                try out.append(gpa, .{ .id = .offside, .span = t.span });
            }
            try out.append(gpa, t);
            break;
        }

        const is_new_line = first or t.span.line != prev_line;
        prev_line = t.span.line;
        first = false;

        if (expect_push) {
            if (stack.items.len == 0 or t.span.col > stack.items[stack.items.len - 1]) {
                try stack.append(gpa, t.span.col);
            }
            expect_push = false;
        } else if (is_new_line) {
            while (stack.items.len > 0 and t.span.col < stack.items[stack.items.len - 1]) {
                _ = stack.pop();
                try out.append(gpa, .{ .id = .offside, .span = t.span });
            }
            if (stack.items.len > 0 and t.span.col == stack.items[stack.items.len - 1]) {
                if (t.id == .eq) {
                    // ELSEQ *replaces* the '=' token (matches `lex.zig`'s
                    // `lexAtOffsideOrElseq`, which advances past the '='
                    // character and returns ELSEQ for that position, rather
                    // than reporting a separate `.eq` afterward) -- so skip
                    // the unconditional append below for this token.
                    try out.append(gpa, .{ .id = .elseq, .span = t.span });
                    continue;
                }
                try out.append(gpa, .{ .id = .offside, .span = t.span });
            }
        }

        try out.append(gpa, t);

        if (t.id == .kw_where or t.id == .kw_with) expect_push = true;
    }

    return out.toOwnedSlice(gpa);
}

fn tok(id: TokenId, line: u32, col: u32) Token {
    return .{ .id = id, .span = .{ .line = line, .col = col } };
}

fn tokText(id: TokenId, line: u32, col: u32, text: []const u8) Token {
    return .{ .id = id, .span = .{ .line = line, .col = col }, .text = text };
}

fn idsOf(gpa: std.mem.Allocator, tokens: []const Token) ![]TokenId {
    const ids = try gpa.alloc(TokenId, tokens.len);
    for (tokens, 0..) |t, i| ids[i] = t.id;
    return ids;
}

test "applyLayout: a single top-level definition needs no separator, just a final offside+eof" {
    const gpa = std.testing.allocator;
    // square x = x * x
    const input = [_]Token{
        tokText(.name, 1, 1, "square"), tokText(.name, 1, 8, "x"), tok(.eq, 1, 10),
        tokText(.name, 1, 12, "x"),     tok(.star, 1, 14),          tokText(.name, 1, 16, "x"),
        tok(.eof, 2, 1),
    };
    const out = try applyLayout(gpa, &input);
    defer gpa.free(out);
    const ids = try idsOf(gpa, out);
    defer gpa.free(ids);
    try std.testing.expectEqualSlices(TokenId, &.{ .name, .name, .eq, .name, .star, .name, .offside, .eof }, ids);
}

test "applyLayout: two same-margin top-level definitions get an offside between them" {
    const gpa = std.testing.allocator;
    // square x = x * x
    // cube x = x * x * x
    const input = [_]Token{
        tokText(.name, 1, 1, "square"), tokText(.name, 1, 8, "x"), tok(.eq, 1, 10),
        tokText(.name, 1, 12, "x"),     tok(.star, 1, 14),          tokText(.name, 1, 16, "x"),
        tokText(.name, 2, 1, "cube"),   tokText(.name, 2, 6, "x"), tok(.eq, 2, 8),
        tokText(.name, 2, 10, "x"),     tok(.star, 2, 12),          tokText(.name, 2, 14, "x"),
        tok(.eof, 3, 1),
    };
    const out = try applyLayout(gpa, &input);
    defer gpa.free(out);
    const ids = try idsOf(gpa, out);
    defer gpa.free(ids);
    try std.testing.expectEqualSlices(TokenId, &.{
        .name, .name, .eq, .name, .star, .name,
        .offside, // separator between the two top-level defs
        .name, .name, .eq, .name, .star, .name,
        .offside, // final unwind at eof
        .eof,
    }, ids);
}

test "applyLayout: a where clause opens a new, more-indented margin and closes on dedent" {
    const gpa = std.testing.allocator;
    // f x = g x
    //   where
    //   g y = y
    // h x = x
    const input = [_]Token{
        tokText(.name, 1, 1, "f"),  tokText(.name, 1, 3, "x"), tok(.eq, 1, 5),
        tokText(.name, 1, 7, "g"),  tokText(.name, 1, 9, "x"),
        tok(.kw_where, 2, 3),
        tokText(.name, 3, 3, "g"),  tokText(.name, 3, 5, "y"), tok(.eq, 3, 7), tokText(.name, 3, 9, "y"),
        tokText(.name, 4, 1, "h"),  tokText(.name, 4, 3, "x"), tok(.eq, 4, 5), tokText(.name, 4, 7, "x"),
        tok(.eof, 5, 1),
    };
    const out = try applyLayout(gpa, &input);
    defer gpa.free(out);
    const ids = try idsOf(gpa, out);
    defer gpa.free(ids);
    // f x = g x where <offside(sibling in where-block, none here)> g y = y
    // <offside(close where)> <offside(sibling at top level)> h x = x <offside(eof)> eof
    try std.testing.expectEqualSlices(TokenId, &.{
        .name, .name, .eq, .name, .name, .kw_where,
        .name, .name, .eq, .name,
        .offside, // dedent closes the where-block margin
        .offside, // top-level sibling separator before `h`
        .name, .name, .eq, .name,
        .offside, // final unwind at eof
        .eof,
    }, ids);
}

test "applyLayout: a realigned '=' at the block margin is elseq, not offside" {
    const gpa = std.testing.allocator;
    // f 0 = 1
    // = 2
    const input = [_]Token{
        tokText(.name, 1, 1, "f"), .{ .id = .const_int, .span = .{ .line = 1, .col = 3 }, .text = "0" }, tok(.eq, 1, 5), .{ .id = .const_int, .span = .{ .line = 1, .col = 7 }, .text = "1" },
        tok(.eq, 2, 1), .{ .id = .const_int, .span = .{ .line = 2, .col = 3 }, .text = "2" },
        tok(.eof, 3, 1),
    };
    const out = try applyLayout(gpa, &input);
    defer gpa.free(out);
    const ids = try idsOf(gpa, out);
    defer gpa.free(ids);
    try std.testing.expectEqualSlices(TokenId, &.{
        .name, .const_int, .eq, .const_int,
        .elseq, // realigned '=' at the top-level margin -- replaces the '=',
        // not followed by a separate .eq (matches lex.zig's
        // lexAtOffsideOrElseq, which consumes the '=' character)
        .const_int,
        .offside, // final unwind at eof
        .eof,
    }, ids);
}

test "applyLayout: an explicit semicolon is left alone, no extra offside injected" {
    const gpa = std.testing.allocator;
    // f x = x; g y = y
    const input = [_]Token{
        tokText(.name, 1, 1, "f"), tokText(.name, 1, 3, "x"), tok(.eq, 1, 5), tokText(.name, 1, 7, "x"),
        tok(.semicolon, 1, 8),
        tokText(.name, 1, 10, "g"), tokText(.name, 1, 12, "y"), tok(.eq, 1, 14), tokText(.name, 1, 16, "y"),
        tok(.eof, 2, 1),
    };
    const out = try applyLayout(gpa, &input);
    defer gpa.free(out);
    const ids = try idsOf(gpa, out);
    defer gpa.free(ids);
    // Same line, so no newline-triggered offside check runs at all -- the
    // semicolon is the only separator, passed through untouched.
    try std.testing.expectEqualSlices(TokenId, &.{
        .name, .name, .eq, .name, .semicolon, .name, .name, .eq, .name,
        .offside, .eof,
    }, ids);
}

test "applyLayout: nested where-in-where closes both margins on a full dedent" {
    const gpa = std.testing.allocator;
    // f x = g x
    //   where
    //   g y = h y
    //     where
    //     h z = z
    // top = 1
    const input = [_]Token{
        tokText(.name, 1, 1, "f"),   tokText(.name, 1, 3, "x"), tok(.eq, 1, 5), tokText(.name, 1, 7, "g"), tokText(.name, 1, 9, "x"),
        tok(.kw_where, 2, 3),
        tokText(.name, 3, 3, "g"),   tokText(.name, 3, 5, "y"), tok(.eq, 3, 7), tokText(.name, 3, 9, "h"), tokText(.name, 3, 11, "y"),
        tok(.kw_where, 4, 5),
        tokText(.name, 5, 5, "h"),   tokText(.name, 5, 7, "z"), tok(.eq, 5, 9), tokText(.name, 5, 11, "z"),
        tokText(.name, 6, 1, "top"), tok(.eq, 6, 5), .{ .id = .const_int, .span = .{ .line = 6, .col = 7 }, .text = "1" },
        tok(.eof, 7, 1),
    };
    const out = try applyLayout(gpa, &input);
    defer gpa.free(out);
    const ids = try idsOf(gpa, out);
    defer gpa.free(ids);
    try std.testing.expectEqualSlices(TokenId, &.{
        .name, .name, .eq, .name, .name, .kw_where,
        .name, .name, .eq, .name, .name, .kw_where,
        .name, .name, .eq, .name,
        .offside, // dedent closes the inner where (h's block)
        .offside, // dedent closes the outer where (g's block)
        .offside, // top-level sibling separator before `top`
        .name, .eq, .const_int,
        .offside, // final unwind at eof
        .eof,
    }, ids);
}

// ---------------------------------------------------------------------------
// End-to-end check: Source -> lexer.tokenize -> applyLayout -> parser.zig.
//
// The whole point of this module is producing a stream `parser/parser.zig`
// can actually consume — so exercise the real parser, not a hand-built token
// list, for at least the shapes above. An arena backs every allocation here
// (tokens' owned text, the AST) so the test doesn't need to hand-walk the
// tree to free it.
// ---------------------------------------------------------------------------

const lexer_mod = @import("lexer.zig");
const Source = @import("source.zig").Source;
const parser_mod = @import("../parser/parser.zig");

test "end-to-end: two top-level definitions parse as two definition items, no diagnostics" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    var src = try Source.fromBytes(gpa, "square x = x * x\ncube x = x * x * x\n");
    const flat = try lexer_mod.tokenize(gpa, &src);
    const laid_out = try applyLayout(gpa, flat);

    var p = parser_mod.Parser.init(gpa, laid_out);
    const script = try parser_mod.parseScript(&p);

    try std.testing.expectEqual(@as(usize, 0), p.diagnostics.items.len);
    try std.testing.expectEqual(@as(usize, 2), script.items.len);
    try std.testing.expect(script.items[0] == .definition);
    try std.testing.expect(script.items[1] == .definition);
}

test "end-to-end: a where clause attaches its local defs to the enclosing definition" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    var src = try Source.fromBytes(gpa,
        \\f x = g x
        \\  where
        \\  g y = y + 1
        \\h x = x
        \\
    );
    const flat = try lexer_mod.tokenize(gpa, &src);
    const laid_out = try applyLayout(gpa, flat);

    var p = parser_mod.Parser.init(gpa, laid_out);
    const script = try parser_mod.parseScript(&p);

    try std.testing.expectEqual(@as(usize, 0), p.diagnostics.items.len);
    try std.testing.expectEqual(@as(usize, 2), script.items.len);
    try std.testing.expect(script.items[0] == .definition);
    try std.testing.expectEqual(@as(usize, 1), script.items[0].definition.where_defs.len);
    try std.testing.expect(script.items[1] == .definition);
    try std.testing.expectEqual(@as(usize, 0), script.items[1].definition.where_defs.len);
}

test "end-to-end: a realigned '=' continues a guarded equation, not a new top-level item" {
    // parser.zig's parseGuardedRhs only takes the ELSEQ branch when the
    // first alternative was itself guarded (`body , if cond` / `, otherwise`)
    // -- a bare second `= body` with no guard on the first line is not valid
    // input for this construct (confirmed by first writing this test with
    // "f 0 = 1\n= 2\n", which the real parser correctly rejects: parseRhs
    // never looks for a following ELSEQ unless it saw ',' first, so the
    // literal ELSEQ + "2" are left dangling as a bogus second item).
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    var src = try Source.fromBytes(gpa, "f x = 1, if x>0\n= 2, otherwise\n");
    const flat = try lexer_mod.tokenize(gpa, &src);
    const laid_out = try applyLayout(gpa, flat);

    var p = parser_mod.Parser.init(gpa, laid_out);
    const script = try parser_mod.parseScript(&p);

    // The realigned '=' must not be mistaken for a second top-level item --
    // this is the whole reason elseq (not offside) exists.
    try std.testing.expectEqual(@as(usize, 0), p.diagnostics.items.len);
    try std.testing.expectEqual(@as(usize, 1), script.items.len);
    try std.testing.expect(script.items[0] == .definition);
    try std.testing.expect(script.items[0].definition.rhs == .guarded);
    try std.testing.expectEqual(@as(usize, 2), script.items[0].definition.rhs.guarded.len);
}
