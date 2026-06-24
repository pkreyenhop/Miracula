//! reduce_test.zig — unit tests for the graph-reduction engine (`reduce()`).
//!
//! Each test builds a small combinator graph by hand and checks that `reduce`
//! drives it to the expected weak-head-normal form. These exercise the core
//! machine (spine unwind, pointer-reversal traversal, combinator dispatch, the
//! in-place `simpl` rewrite, and the up-walk that forces strict arguments)
//! without going through the parser/compiler. Run via the `main-tests` step.

const std = @import("std");
const word = @import("../word.zig");
const heap = @import("../heap.zig");
const big = @import("../big.zig");
const reduce = @import("reduce.zig");
const reduce_rt = @import("../reduce.zig");
const interp = @import("../interp.zig");
const rt = @import("../runtime_state.zig");
const core_state = @import("../core_state.zig");
const setup = @import("../../compiler/setup.zig");
const lex = @import("../../parser/lex.zig");

const Word = word.Word;
const ap = reduce.ap;
const ap2 = reduce.ap2;

// Phase 4 (shared-state plan): start from a pristine `Interp` via `interp.reset()`,
// then run the *full* `miraSetup()` — the heavyweight init (rs.*/primenv, the
// dictionary, interned strings) that used to pollute the order-sensitive parser
// snapshot tests. With `reset()` covering all aggregated state and the snapshot
// tests now capturing token text reliably (interned id, not the lagging dic
// buffer), that pollution is gone and full setup here is safe.
var initialized = false;
fn ensureSetup() void {
    if (initialized) return;
    interp.reset();
    lex.setupdic();
    setup.miraSetup();
    initialized = true;
}

test "I combinator: reduce (I x) == x" {
    ensureSetup();
    try std.testing.expectEqual(@as(Word, word.NIL), reduce.reduce(ap(word.I, word.NIL)));
}

test "K combinator: reduce (K x y) == x" {
    ensureSetup();
    try std.testing.expectEqual(@as(Word, word.True), reduce.reduce(ap2(word.K, word.True, word.False)));
}

test "nested identity: reduce (I (I x)) == x" {
    ensureSetup();
    try std.testing.expectEqual(@as(Word, word.False), reduce.reduce(ap(word.I, ap(word.I, word.False))));
}

test "already in WHNF: reduce of a CONS returns the same cell" {
    ensureSetup();
    const c = reduce.cons(word.True, word.NIL);
    try std.testing.expectEqual(c, reduce.reduce(c));
}

test "strict arithmetic: reduce (PLUS 2 3) yields INT 5" {
    ensureSetup();
    const r = reduce.reduce(ap2(word.PLUS, big.fromInt(2), big.fromInt(3)));
    try std.testing.expect(heap.getTag(r) == .INT);
    try std.testing.expectEqual(@as(i64, 5), @as(i64, @intCast(big.toInt(r))));
}

test "strict arithmetic: reduce (TIMES 6 7) yields INT 42" {
    ensureSetup();
    const r = reduce.reduce(ap2(word.TIMES, big.fromInt(6), big.fromInt(7)));
    try std.testing.expect(heap.getTag(r) == .INT);
    try std.testing.expectEqual(@as(i64, 42), @as(i64, @intCast(big.toInt(r))));
}

// Phase 4 proof: `interp.reset()` restores every aggregated state struct to its
// default in one call — the injectability primitive that lets a test start from
// a clean slate (here across RuntimeState / CoreState / EvalState / Bignum).
test "interp.reset clears the aggregated state structs" {
    ensureSetup();

    // Dirty fields in four different aggregated structs.
    rt.rs.SPACELIMIT = 42;
    core_state.s.SYNERR = 7;
    reduce_rt.ev.cycles = 999;
    big.bn.b_rem = 123;

    interp.reset();

    // One reset returns them all to their struct defaults.
    try std.testing.expectEqual(@as(Word, 2500000), rt.rs.SPACELIMIT);
    try std.testing.expectEqual(@as(Word, 0), core_state.s.SYNERR);
    try std.testing.expectEqual(@as(i64, 0), reduce_rt.ev.cycles);
    try std.testing.expectEqual(@as(Word, 0), big.bn.b_rem);

    // Re-establish a working interpreter for subsequent tests (reset wiped it).
    initialized = false;
    ensureSetup();
}
