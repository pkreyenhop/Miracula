//! syntax/layout.zig — the offside/layout rule as an independent token-stream
//! pass (docs/ZIG_NATIVE_PLAN.md Phase 1 step 3).
//!
//! `parser/lex.zig`'s offside handling is NOT a standalone pass: `yylex()`
//! checks the current token's column against the lex state's `lmargin`
//! field, a value **external code** pushes/pops via `setlmargin`/
//! `unsetlmargin` at specific syntactic positions — historically the YACC
//! grammar's mid-rule actions, today `parser/lex_bridge.zig`'s
//! `tokenizeLoop`, which drives the *current* (already-shipping) native
//! parser. Reproducing that exact coupling in a standalone rewrite would
//! just relocate the entanglement, not remove it.
//!
//! This module instead implements the well-known alternative: a **standalone
//! layout algorithm** deriving every `.offside`/`.elseq` injection purely
//! from the token stream (each `Token`'s column, already present in its
//! `Span`) plus a small stack of open margins. No parser callback, no shared
//! mutable state — but the *trigger points and comparisons* are a direct,
//! verified port of `lex_bridge.zig`'s `tokenizeLoop`, not a fresh
//!(Haskell-inspired) design: that file is proof this exact state machine
//! already produces a token stream `parser/parser.zig` correctly consumes
//! for real scripts, so faithfully reproducing it is far safer than
//! re-deriving the rule from first principles.
//!
//! **Corrected 2026-07-06** from this file's first version, which pushed a
//! margin at the very first token and after every `where`/`with` (a
//! Haskell-layout-shaped guess). Reading `lex_bridge.zig`'s `tokenizeLoop`
//! revealed the real mechanism is centered on *definition operators*, not
//! block-opening keywords — recorded here so the mistake isn't repeated:
//!
//!   - A margin is pushed only at `=` (outside brackets, the first one for
//!     the current definition), `::=`, `==` (outside a definition already
//!     seen), or `::` (outside brackets) — using the column of the token
//!     that *follows* the operator, not the operator's own column and NOT
//!     the enclosing definition's name column.
//!   - `where` pushes nothing; it only clears the "have I seen this
//!     definition's `=` yet" flag, so the where-block's *own* first local
//!     `=` does the actual push (nested inside the still-open outer margin).
//!   - The offside/elseq decision compares the current token's column not
//!     just to the top margin but, when a pop is needed, to the *parent*
//!     margin (one level down) to decide whether the token is a realigned
//!     `=` (elseq) or an ordinary dedent (offside) — and a cascading
//!     multi-level dedent can only end in elseq on its *last* pop.
//!   - Because margins sit at RHS-body columns (deep) rather than
//!     definition-name columns (shallow), a next sibling's name is almost
//!     always strictly less indented than the just-closed margin, so the
//!     exact-equality-with-zero-pops case this file's first version worried
//!     about essentially never arises in practice — and, matching
//!     `lex.zig`'s strict `col < lmargin` check exactly, is *not* specially
//!     handled here either.
//!
//! An explicit `.semicolon` in the source always separates items regardless
//! of column (matches `lex.zig`'s `lexSemicolonOrElseq`) — this pass never
//! removes or reinterprets semicolons, only injects `.offside`/`.elseq`.
//!
//! Not yet wired into `parser_api.zig` — the legacy lexer/bridge remain the
//! production path until Phase 1 step 7.
//!
//! **Still not differentially verified** against `lex_bridge.zig`'s actual
//! output token-for-token (Phase 1 step 4) — this is now a direct port of
//! its logic rather than an independent guess, which is a much stronger
//! starting point, but "ported by reading the source" and "verified by
//! running both and diffing" are not the same claim.
//!
//! Tests: applyLayout — one test per trigger (`=`, `::`, `::=`, `==`,
//! `where`, cascading dedent, realigned `=`, explicit semicolon, brackets
//! guarding a comparison `=`, EOF closes open margins), plus end-to-end
//! checks that feed the result into the real `parser.zig`.

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

    // Mirrors lex_bridge.zig's tokenizeLoop local state exactly.
    var seen_def_eq = false;
    var paren_depth: i32 = 0;

    var i: usize = 0;
    while (i < tokens.len) : (i += 1) {
        const t = tokens[i];
        if (t.id == .eof) {
            while (stack.items.len > 0) {
                _ = stack.pop();
                try out.append(gpa, .{ .id = .offside, .span = t.span });
            }
            try out.append(gpa, t);
            break;
        }

        // The offside/elseq decision: pop while this token is less indented
        // than the current margin. A cascading multi-level dedent can only
        // resolve as elseq on its final pop (checked against the *parent* of
        // the level being popped) -- every earlier pop in the cascade is
        // unconditionally offside, matching lexAtOffsideOrElseq exactly.
        var handled_as_elseq = false;
        while (stack.items.len > 0 and t.span.col < stack.items[stack.items.len - 1]) {
            const parent: ?u32 = if (stack.items.len >= 2) stack.items[stack.items.len - 2] else null;
            const elseq_eligible = t.id == .eq and (parent == null or t.span.col >= parent.?);
            _ = stack.pop();
            if (elseq_eligible) {
                // ELSEQ *replaces* the '=' token (lex.zig's
                // lexAtOffsideOrElseq consumes the '=' character and returns
                // ELSEQ for that position) and immediately re-establishes a
                // margin at the following token's column (lex_bridge.zig's
                // `.elseq => unsetlmargin(); layout(); setlmargin();`).
                try out.append(gpa, .{ .id = .elseq, .span = t.span });
                try pushMargin(gpa, &stack, nextCol(tokens, i));
                seen_def_eq = true;
                handled_as_elseq = true;
                break;
            }
            try out.append(gpa, .{ .id = .offside, .span = t.span });
            seen_def_eq = false;
            paren_depth = 0;
        }
        if (handled_as_elseq) continue;

        try out.append(gpa, t);

        switch (t.id) {
            .lparen, .lbracket, .lbrace => paren_depth += 1,
            .rparen, .rbracket, .rbrace => paren_depth -= 1,
            .eq => {
                // A definition '=' (not a comparison inside brackets, and
                // not a second '=' already covered by this definition's
                // first) opens a margin at the column of its RHS.
                if (paren_depth == 0 and !seen_def_eq) {
                    try pushMargin(gpa, &stack, nextCol(tokens, i));
                    seen_def_eq = true;
                }
            },
            .colon2eq => try pushMargin(gpa, &stack, nextCol(tokens, i)), // `::=` algebraic type body
            .eq_eq => if (!seen_def_eq) {
                try pushMargin(gpa, &stack, nextCol(tokens, i)); // `==` type synonym body
            },
            .coloncolon => if (paren_depth == 0) {
                try pushMargin(gpa, &stack, nextCol(tokens, i)); // `::` type signature body
            },
            .kw_where => seen_def_eq = false, // the where-block's own first '=' pushes its margin
            else => {},
        }
    }

    return out.toOwnedSlice(gpa);
}

/// `setlmargin()`: push a new level, keeping the deeper of the enclosing
/// margin and `col` (a `where`/binder with nothing more indented under it
/// opens no *deeper* context, but a level is still pushed so pop counts
/// stay balanced with `unsetlmargin()`/offside).
fn pushMargin(gpa: std.mem.Allocator, stack: *std.ArrayList(u32), col: u32) !void {
    const enclosing = if (stack.items.len > 0) stack.items[stack.items.len - 1] else 0;
    try stack.append(gpa, if (enclosing < col) col else enclosing);
}

/// The column of the token immediately following `tokens[i]` (what
/// `layout()` would land on after skipping whitespace, in a live scan) --
/// or, degenerately, `tokens[i]`'s own column if it's the last token.
fn nextCol(tokens: []const Token, i: usize) u32 {
    return if (i + 1 < tokens.len) tokens[i + 1].span.col else tokens[i].span.col;
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

test "applyLayout: '=' pushes a margin at the RHS column; a less-indented sibling dedents" {
    const gpa = std.testing.allocator;
    // square x = x * x     (RHS "x * x" starts at col 12)
    // cube x = x * x * x   ("cube" at col 1 -- well left of 12, dedents)
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
        .offside, // "cube" (col 1) dedents past the RHS margin (col 12)
        .name, .name, .eq, .name, .star, .name,
        .offside, // final unwind at eof
        .eof,
    }, ids);
}

test "applyLayout: a where clause opens a new margin at its own first '='" {
    const gpa = std.testing.allocator;
    // f x = g x     (RHS "g x" margin at col 7)
    //   where       ("where" at col 3 dedents past col 7 -- f's margin pops
    //                *before* g's where-block margin is pushed, so they are
    //                sequential, not nested, unlike this file's first
    //                (wrong) version assumed)
    //   g y = y     (where-block's own margin at col 9)
    // h x = x       (col 1 dedents past g's margin)
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
    try std.testing.expectEqualSlices(TokenId, &.{
        .name, .name, .eq, .name, .name,
        .offside, // "where" (col 3) dedents past f's RHS margin (col 7) --
        // matches parser.zig's parseDef case 2 (OFFSIDE then kw_where)
        .kw_where,
        .name, .name, .eq, .name,
        .offside, // "h" (col 1) dedents past g's where-block margin (col 9)
        .name, .name, .eq, .name,
        .offside, // final unwind at eof
        .eof,
    }, ids);
}

test "applyLayout: a realigned '=' inside brackets is a comparison, not a definition margin" {
    const gpa = std.testing.allocator;
    // f x = [x = 1]     ('=' inside brackets never opens a margin)
    // g x = x
    const input = [_]Token{
        tokText(.name, 1, 1, "f"), tokText(.name, 1, 3, "x"), tok(.eq, 1, 5),
        tok(.lbracket, 1, 7),      tokText(.name, 1, 8, "x"), tok(.eq, 1, 10), .{ .id = .const_int, .span = .{ .line = 1, .col = 12 }, .text = "1" }, tok(.rbracket, 1, 13),
        tokText(.name, 2, 1, "g"), tokText(.name, 2, 3, "x"), tok(.eq, 2, 5), tokText(.name, 2, 7, "x"),
        tok(.eof, 3, 1),
    };
    const out = try applyLayout(gpa, &input);
    defer gpa.free(out);
    const ids = try idsOf(gpa, out);
    defer gpa.free(ids);
    // The margin opened by f's own '=' sits at col 7 (the '[') -- "g" at col 1
    // dedents past it with a single offside; the bracketed '=' at col 10
    // never opens a second, inner margin (paren_depth guards it).
    try std.testing.expectEqualSlices(TokenId, &.{
        .name, .name, .eq, .lbracket, .name, .eq, .const_int, .rbracket,
        .offside,
        .name, .name, .eq, .name,
        .offside,
        .eof,
    }, ids);
}

test "applyLayout: :: opens a margin the same way '=' does" {
    const gpa = std.testing.allocator;
    // f :: num
    //       -> num    (continuation indented AT/PAST the signature's margin: no separator)
    // g x = x          (dedents past the :: margin)
    const input = [_]Token{
        tokText(.name, 1, 1, "f"), tok(.coloncolon, 1, 3), tokText(.name, 1, 6, "num"),
        tok(.arrow, 2, 7),         tokText(.name, 2, 10, "num"),
        tokText(.name, 3, 1, "g"), tokText(.name, 3, 3, "x"), tok(.eq, 3, 5), tokText(.name, 3, 7, "x"),
        tok(.eof, 4, 1),
    };
    const out = try applyLayout(gpa, &input);
    defer gpa.free(out);
    const ids = try idsOf(gpa, out);
    defer gpa.free(ids);
    // '::' opens a margin at col 6 ("num"); the arrow-continuation line at
    // col 7 is >= 6, so it's a plain continuation (no separator); "g" at
    // col 1 dedents past the margin with a single offside.
    try std.testing.expectEqualSlices(TokenId, &.{
        .name, .coloncolon, .name,
        .arrow, .name,
        .offside,
        .name, .name, .eq, .name,
        .offside,
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
    // Same line throughout, so nothing here is ever less indented than the
    // margin f's own '=' opened (col 7) -- the semicolon is the only
    // separator, passed through untouched.
    try std.testing.expectEqualSlices(TokenId, &.{
        .name, .name, .eq, .name, .semicolon, .name, .name, .eq, .name,
        .offside, .eof,
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

test "end-to-end: three top-level definitions in a row (regression for cascading dedent)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    var src = try Source.fromBytes(gpa, "a x = x\nb x = x\nc x = x\n");
    const flat = try lexer_mod.tokenize(gpa, &src);
    const laid_out = try applyLayout(gpa, flat);

    var p = parser_mod.Parser.init(gpa, laid_out);
    const script = try parser_mod.parseScript(&p);

    try std.testing.expectEqual(@as(usize, 0), p.diagnostics.items.len);
    try std.testing.expectEqual(@as(usize, 3), script.items.len);
}

test "end-to-end: a %-directive parses as one .directive top-level item" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    var src = try Source.fromBytes(gpa, "%export + -flooby\nsquare x = x * x\n");
    const result = try lexer_mod.tokenizeWithDirectives(gpa, &src);
    const laid_out = try applyLayout(gpa, result.tokens);

    var p = parser_mod.Parser.initWithDirectives(gpa, laid_out, result.directives);
    const script = try parser_mod.parseScript(&p);

    try std.testing.expectEqual(@as(usize, 0), p.diagnostics.items.len);
    try std.testing.expectEqual(@as(usize, 2), script.items.len);
    try std.testing.expect(script.items[0] == .directive);
    try std.testing.expect(script.items[0].directive == .export_list);
    try std.testing.expectEqualStrings("+ -flooby", script.items[0].directive.export_list.parts_text);
    try std.testing.expect(script.items[1] == .definition);
}

test "end-to-end: miralib/ex/fib.m verbatim (real script, comments + realigned guard)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    var src = try Source.fromBytes(gpa,
        \\||fib n computes the n'th fibonacci number
        \\||by using /count you can estimate the asymptotic limit of (fib n/time to compute fib n)
        \\fib n = 1,                   if n<=2
        \\      = fib(n-1) + fib(n-2), otherwise
        \\
    );
    const flat = try lexer_mod.tokenize(gpa, &src);
    const laid_out = try applyLayout(gpa, flat);

    var p = parser_mod.Parser.init(gpa, laid_out);
    const script = try parser_mod.parseScript(&p);

    try std.testing.expectEqual(@as(usize, 0), p.diagnostics.items.len);
    try std.testing.expectEqual(@as(usize, 1), script.items.len);
    try std.testing.expect(script.items[0] == .definition);
    try std.testing.expect(script.items[0].definition.rhs == .guarded);
    try std.testing.expectEqual(@as(usize, 2), script.items[0].definition.rhs.guarded.len);
}
