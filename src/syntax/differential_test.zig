//! syntax/differential_test.zig — Phase 1 step 4's dual-run harness
//! (docs/ZIG_NATIVE_PLAN.md): tokenizes the same source through the legacy
//! pipeline (`parser/lex_bridge.zig`'s `tokenize`, backed by real `yylex()` +
//! `setlmargin`/`unsetlmargin`) and the native one
//! (`syntax/source.zig` → `syntax/lexer.zig` → `syntax/layout.zig`), and
//! diffs the resulting `TokenId` sequences.
//!
//! C-linked (imports `lex_bridge.zig`, which needs a real heap/dictionary) —
//! test-only, aggregated into `main-tests` the same way `parser/lex.zig`'s
//! own tests are. Each test fully resets and re-`miraSetup()`s the
//! interpreter itself (see `tokenizeBoth`) rather than using
//! `testutil.freshInterp()`'s idempotent one-time setup, since this file
//! calls the legacy tokenizer many times per process — not its normal
//! one-script-per-process usage — and several fields (SYNERR, the
//! dictionary buffer, the margin stack) turned out to carry over between
//! calls otherwise.
//!
//! **Corpus:** the golden `.m` scripts that use none of this lexer's known
//! gaps (`%`-directives, backtick infix names, char classes, hex-float) —
//! see `tests/golden/README_pending_phase1.md` for the directive scripts
//! excluded here for that reason. Each is real, already-shipping Miranda
//! source, not a hand-picked snippet.
//!
//! Tests: tokenizeBoth / assertSameIds — one test per golden script.

const std = @import("std");
const lex_bridge = @import("../parser/lex_bridge.zig");
const lex = @import("../parser/lex.zig");
const setup = @import("../compiler/setup.zig");
const interp = @import("../runtime/interp.zig");
const core_state = @import("../runtime/core_state.zig");
const Source = @import("source.zig").Source;
const lexer_mod = @import("lexer.zig");
const layout_mod = @import("layout.zig");
const TokenId = @import("../parser/token_filter.zig").TokenId;

fn idsOf(gpa: std.mem.Allocator, tokens: anytype) ![]TokenId {
    const ids = try gpa.alloc(TokenId, tokens.len);
    for (tokens, 0..) |t, i| ids[i] = t.id;
    return ids;
}

/// Tokenize `source` through both pipelines and return their `TokenId`
/// sequences (both `gpa`-owned; free with `gpa.free`). `source` need not be
/// NUL-terminated -- both the legacy and native paths get their own copy.
fn tokenizeBoth(gpa: std.mem.Allocator, source: []const u8) !struct { legacy: []TokenId, native: []TokenId } {
    // Each call scans a fresh script through the *same* legacy interpreter
    // instance (this harness calls tokenize() many times per process, which
    // is not lex_bridge.zig's normal one-script-per-process usage pattern),
    // so state that normally never needs resetting mid-process -- the
    // dictionary buffer, SYNERR, the margin stack -- carries over and
    // corrupts the next call otherwise (observed: SYNERR left set from one
    // script made the next tokenize() call return only `.eof`, since
    // `yylex()` bails immediately when SYNERR != 0). A full `interp.reset()`
    // + re-`miraSetup()` sidesteps needing to track down every sticky field.
    interp.reset();
    lex.setupdic();
    setup.miraSetup();
    core_state.s().SYNERR = 0;
    const source_z = try gpa.dupeZ(u8, source);
    defer gpa.free(source_z);
    const legacy_toks = try lex_bridge.tokenize(gpa, source_z);
    defer lex_bridge.deinit(gpa, legacy_toks);
    const legacy_ids = try idsOf(gpa, legacy_toks);
    errdefer gpa.free(legacy_ids);

    var native_src = try Source.fromBytes(gpa, source);
    defer native_src.deinit();
    const flat = try lexer_mod.tokenize(gpa, &native_src);
    defer gpa.free(flat);
    const laid_out = try layout_mod.applyLayout(gpa, flat);
    defer gpa.free(laid_out);
    const native_ids = try idsOf(gpa, laid_out);
    errdefer gpa.free(native_ids);

    return .{ .legacy = legacy_ids, .native = native_ids };
}

fn expectSameIds(gpa: std.mem.Allocator, source: []const u8) !void {
    const both = try tokenizeBoth(gpa, source);
    defer gpa.free(both.legacy);
    defer gpa.free(both.native);
    std.testing.expectEqualSlices(TokenId, both.legacy, both.native) catch |err| {
        std.debug.print("legacy:  {any}\nnative:  {any}\n", .{ both.legacy, both.native });
        return err;
    };
}

test "differential: algebraic_nullary.m (::= and ::)" {
    try expectSameIds(std.testing.allocator,
        \\colour ::= Red | Green | Blue
        \\c :: colour
        \\c = Green
        \\
    );
}

test "differential: algebraic_param.m (::= with constructor args)" {
    try expectSameIds(std.testing.allocator,
        \\tree ::= Leaf num | Branch tree tree
        \\t1 :: tree
        \\t1 = Branch (Leaf 1) (Leaf 2)
        \\
    );
}

test "differential: custom_ack.m (multiple top-level definitions)" {
    try expectSameIds(std.testing.allocator,
        \\ack 0 n = n + 1
        \\ack m 0 = ack (m - 1) 1
        \\ack m n = ack (m - 1) (ack m (n - 1))
        \\
    );
}

test "differential: custom_fib.m" {
    try expectSameIds(std.testing.allocator,
        \\fib 0 = 0
        \\fib 1 = 1
        \\fib n = fib (n-1) + fib (n-2)
        \\
    );
}

test "differential: custom_lazy.m" {
    try expectSameIds(std.testing.allocator, "ones = 1 : ones\n");
}

test "differential: list_pattern.m (cons pattern)" {
    try expectSameIds(std.testing.allocator, "firstel (x:xs) = x\n");
}

test "differential: tuple_pattern.m" {
    try expectSameIds(std.testing.allocator, "sumpair (x, y) = x + y\n");
}

test "differential: miralib/ex/fib.m verbatim (comments + realigned guard)" {
    try expectSameIds(std.testing.allocator,
        \\||fib n computes the n'th fibonacci number
        \\||by using /count you can estimate the asymptotic limit of (fib n/time to compute fib n)
        \\fib n = 1,                   if n<=2
        \\      = fib(n-1) + fib(n-2), otherwise
        \\
    );
}
