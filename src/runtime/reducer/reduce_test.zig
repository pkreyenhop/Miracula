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

const Word = word.Word;
const ap = reduce.ap;
const ap2 = reduce.ap2;

// Minimal runtime init: just the heap and the bignum globals — enough to build
// cells and do arithmetic. We deliberately avoid the full `mira_setup()` (which
// seeds `rs.*`/primenv and populates the dictionary) so these tests don't leave
// global state that later order-sensitive tests (e.g. the parser snapshots)
// would observe — this is the same pollution level as the heap unit test.
var initialized = false;
fn ensureSetup() void {
    if (initialized) return;
    heap.setupheap();
    big.bigsetup();
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
    const r = reduce.reduce(ap2(word.PLUS, big.sto_int(2), big.sto_int(3)));
    try std.testing.expect(heap.getTag(r) == .INT);
    try std.testing.expectEqual(@as(i64, 5), @as(i64, @intCast(big.get_int(r))));
}

test "strict arithmetic: reduce (TIMES 6 7) yields INT 42" {
    ensureSetup();
    const r = reduce.reduce(ap2(word.TIMES, big.sto_int(6), big.sto_int(7)));
    try std.testing.expect(heap.getTag(r) == .INT);
    try std.testing.expectEqual(@as(i64, 42), @as(i64, @intCast(big.get_int(r))));
}
