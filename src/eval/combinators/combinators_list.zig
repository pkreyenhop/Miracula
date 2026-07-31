//! eval/combinators/combinators_list.zig (split from combinators.zig for the
//! Go port's <1000-line file ratchet, docs/GoReady.md P4) — the list
//! higher-order combinator handlers: `MAP`/`FLATMAP`/`FILTER`/`LIST_LAST`/
//! `LENGTH`/`DROP`/`SUBSCRIPT`/`FOLDL1`/`FOLDL`/`FOLDR`. Each is an independent
//! `handle<COMBINATOR>(ctx)` rewrite rule dispatched from `eval/reduce.zig`,
//! identical in shape to the core handlers in `combinators.zig`; moved here
//! purely to keep each file translation-unit-sized. No shared state with
//! `combinators.zig` (both depend only on `reduce_core`'s `ReductionCtx`).

const word = @import("../../graph/word.zig");
const reduce = @import("../reduce_core.zig");
const big = @import("../../graph/bignum.zig");
const reduce_rt = @import("../reduce_rt.zig");
const tu = @import("../../testutil.zig"); // unit-test harness (test builds only)
const ReductionCtx = reduce.ReductionCtx;
const Word = reduce.Word;
const Value = @import("../../graph/value.zig").Value;

/// `map f (x:xs) -> f x : map f xs`; `map f [] -> []`.
///
/// Tests: handleMAP: map applies a function over a list
pub fn handleMAP(ctx: *ReductionCtx) reduce.ReduceError!void {
    var arg1: Value = Value.fromRaw(0);
    if (reduce.getarg(ctx, &arg1)) {
        ctx.action = word.ACT_DONE;
        return;
    }
    if (reduce.upleft(ctx)) {
        ctx.action = word.ACT_DONE;
        return;
    }
    const lastarg = try reduce.reduceVal(ctx.heap, reduce.tlGet(ctx.heap, ctx.e));
    if (lastarg.toRaw() == word.NIL) {
        reduce.rewriteToNil(ctx.heap, &ctx.e);
    } else {
        const hold = reduce.ap(ctx.heap, reduce.hdGet(ctx.heap, ctx.e), reduce.tlGet(ctx.heap, lastarg));
        reduce.rewriteToCons(ctx.heap, ctx.e, reduce.ap(ctx.heap, arg1, reduce.hdGet(ctx.heap, lastarg)), hold);
    }
    ctx.action = word.ACT_DONE;
}

test "handleMAP: map applies a function over a list" {
    tu.freshInterp();
    try tu.expectList(&.{ 1, 2, 3 }, tu.ap2(word.MAP, word.I, tu.list(&.{ tu.int(1), tu.int(2), tu.int(3) })));
}

/// Concat-map: apply `f` to each element and append the non-`FAIL`/non-`[]` results.
///
/// Tests: handleFLATMAP: concat-maps f over the list
pub fn handleFLATMAP(ctx: *ReductionCtx) reduce.ReduceError!void {
    var arg1: Value = Value.fromRaw(0);
    var arg2: Value = Value.fromRaw(0);
    if (reduce.getarg(ctx, &arg1)) {
        ctx.action = word.ACT_DONE;
        return;
    }
    if (reduce.getarg(ctx, &arg2)) {
        ctx.action = word.ACT_DONE;
        return;
    }
    while (true) {
        arg2 = try reduce.reduceVal(ctx.heap, arg2);
        if (arg2.toRaw() == word.NIL) {
            reduce.rewriteToNil(ctx.heap, &ctx.e);
            ctx.action = word.ACT_DONE;
            return;
        }
        const hold = try reduce.reduceVal(ctx.heap, reduce.ap(ctx.heap, arg1, reduce.hdGet(ctx.heap, arg2)));
        if (hold.toRaw() == word.FAIL or hold.toRaw() == word.NIL) {
            arg2 = reduce.tlGet(ctx.heap, arg2);
            continue;
        }
        reduce.tlSet(ctx.heap, ctx.e, reduce.ap(ctx.heap, reduce.hdGet(ctx.heap, ctx.e), reduce.tlGet(ctx.heap, arg2)));
        reduce.hdSet(ctx.heap, ctx.e, reduce.ap(ctx.heap, Value.fromRaw(word.APPEND), hold));
        ctx.action = word.ACT_NEXTREDEX;
        return;
    }
}

test "handleFLATMAP: concat-maps f over the list" {
    tu.freshInterp();
    const f = tu.ap(word.K, tu.list(&.{tu.int(9)})); // \\_ -> [9]
    try tu.expectList(&.{ 9, 9 }, tu.ap2(word.FLATMAP, f, tu.list(&.{ tu.int(1), tu.int(2) })));
}

/// `filter p xs` — skip leading elements failing predicate `p`, then emit the next survivor lazily.
///
/// Tests: handleFILTER: keeps elements satisfying the predicate
pub fn handleFILTER(ctx: *ReductionCtx) reduce.ReduceError!void {
    var arg1: Value = Value.fromRaw(0);
    if (reduce.getarg(ctx, &arg1)) {
        ctx.action = word.ACT_DONE;
        return;
    }
    if (reduce.upleft(ctx)) {
        ctx.action = word.ACT_DONE;
        return;
    }
    var lastarg = try reduce.reduceVal(ctx.heap, reduce.tlGet(ctx.heap, ctx.e));
    while (lastarg.toRaw() != word.NIL and (try reduce.reduceVal(ctx.heap, reduce.ap(ctx.heap, arg1, reduce.hdGet(ctx.heap, lastarg)))).toRaw() == word.False) {
        lastarg = try reduce.reduceVal(ctx.heap, reduce.tlGet(ctx.heap, lastarg));
    }
    if (lastarg.toRaw() == word.NIL) {
        reduce.rewriteToNil(ctx.heap, &ctx.e);
    } else {
        const hold = reduce.ap(ctx.heap, reduce.hdGet(ctx.heap, ctx.e), reduce.tlGet(ctx.heap, lastarg));
        reduce.rewriteToCons(ctx.heap, ctx.e, reduce.hdGet(ctx.heap, lastarg), hold);
    }
    ctx.action = word.ACT_DONE;
}

test "handleFILTER: keeps elements satisfying the predicate" {
    tu.freshInterp();
    // K True is the always-true predicate → keeps everything
    try tu.expectList(&.{ 1, 2, 3 }, tu.ap2(word.FILTER, tu.ap(word.K, word.True), tu.list(&.{ tu.int(1), tu.int(2), tu.int(3) })));
    // K False is always-false → keeps nothing
    try tu.expectList(&.{}, tu.ap2(word.FILTER, tu.ap(word.K, word.False), tu.list(&.{ tu.int(1), tu.int(2) })));
}

/// `last xs` — the final element of a non-empty list (errors on `[]`); shortens the spine as it walks.
///
/// Tests: handleLIST_LAST: the final element of a list
pub fn handleLIST_LAST(ctx: *ReductionCtx) reduce.ReduceError!void {
    if (reduce.upleft(ctx)) {
        ctx.action = word.ACT_DONE;
        return;
    }
    var lastarg = try reduce.reduceVal(ctx.heap, reduce.tlGet(ctx.heap, ctx.e));
    if (lastarg.toRaw() == word.NIL) {
        reduce_rt.fnError("last []");
    }
    while (true) {
        const next_tl = try reduce.reduceVal(ctx.heap, reduce.tlGet(ctx.heap, lastarg));
        reduce.tlSet(ctx.heap, lastarg, next_tl);
        if (next_tl.toRaw() == word.NIL) break;
        lastarg = next_tl;
    }
    reduce.rewriteToValue(ctx.heap, &ctx.e, reduce.hdGet(ctx.heap, lastarg));
    ctx.action = word.ACT_NEXTREDEX;
}

test "handleLIST_LAST: the final element of a list" {
    tu.freshInterp();
    try tu.expectInt(3, tu.ap(word.LIST_LAST, tu.list(&.{ tu.int(1), tu.int(2), tu.int(3) })));
}

/// `#xs` — the length of a list, as an `INT`.
///
/// Tests: handleLENGTH: # is the length of a list
pub fn handleLENGTH(ctx: *ReductionCtx) reduce.ReduceError!void {
    if (reduce.upleft(ctx)) {
        ctx.action = word.ACT_DONE;
        return;
    }
    var n: i64 = 0;
    var lastarg = reduce.tlGet(ctx.heap, ctx.e);
    while (true) {
        lastarg = try reduce.reduceVal(ctx.heap, lastarg);
        if (lastarg.toRaw() == word.NIL) break;
        lastarg = reduce.tlGet(ctx.heap, lastarg);
        n += 1;
    }
    reduce.simpl(ctx, Value.fromRaw(big.fromInt(ctx.heap, n)));
    ctx.action = word.ACT_DONE;
}

test "handleLENGTH: # is the length of a list" {
    tu.freshInterp();
    try tu.expectInt(3, tu.ap(word.LENGTH, tu.list(&.{ tu.int(1), tu.int(2), tu.int(3) })));
    try tu.expectInt(0, tu.ap(word.LENGTH, word.NIL));
}

/// `drop n xs` — discard the first `n` elements (clamping at `[]`).
///
/// Tests: handleDROP: drop n discards the first n elements
pub fn handleDROP(ctx: *ReductionCtx) reduce.ReduceError!void {
    var arg1: Value = Value.fromRaw(0);
    if (reduce.getarg(ctx, &arg1)) {
        ctx.action = word.ACT_DONE;
        return;
    }
    if (reduce.upleft(ctx)) {
        ctx.action = word.ACT_DONE;
        return;
    }
    arg1 = try reduce.reduceVal(ctx.heap, reduce.tlGet(ctx.heap, reduce.hdGet(ctx.heap, ctx.e)));
    reduce.tlSet(ctx.heap, reduce.hdGet(ctx.heap, ctx.e), arg1);
    if (!reduce.isInt(ctx.heap, arg1)) {
        reduce_rt.intError("drop");
    }
    var n = big.toInt(ctx.heap, arg1.toRaw());
    var lastarg = reduce.tlGet(ctx.heap, ctx.e);
    while (n > 0) : (n -= 1) {
        lastarg = try reduce.reduceVal(ctx.heap, lastarg);
        if (lastarg.toRaw() == word.NIL) {
            reduce.rewriteToNil(ctx.heap, &ctx.e);
            ctx.action = word.ACT_DONE;
            return;
        } else {
            lastarg = reduce.tlGet(ctx.heap, lastarg);
        }
    }
    reduce.rewriteToValue(ctx.heap, &ctx.e, lastarg);
    ctx.action = word.ACT_NEXTREDEX;
}

test "handleDROP: drop n discards the first n elements" {
    tu.freshInterp();
    try tu.expectList(&.{ 2, 3 }, tu.ap2(word.DROP, tu.int(1), tu.list(&.{ tu.int(1), tu.int(2), tu.int(3) })));
}

/// `xs ! n` — the n-th element (0-based); raises a subscript error if out of range.
///
/// Tests: handleSUBSCRIPT: xs ! n indexes the list
pub fn handleSUBSCRIPT(ctx: *ReductionCtx) reduce.ReduceError!void {
    if (reduce.upleft(ctx)) {
        ctx.action = word.ACT_DONE;
        return;
    }
    if (reduce.upleft(ctx)) {
        ctx.action = word.ACT_DONE;
        return;
    }
    const arg1 = try reduce.reduceVal(ctx.heap, reduce.tlGet(ctx.heap, reduce.hdGet(ctx.heap, ctx.e)));
    reduce.tlSet(ctx.heap, reduce.hdGet(ctx.heap, ctx.e), arg1);
    var lastarg = try reduce.reduceVal(ctx.heap, reduce.tlGet(ctx.heap, ctx.e));
    if (lastarg.toRaw() == word.NIL) {
        reduce_rt.subsError();
    }
    var indx: i64 = 0;
    if (reduce.isAtom(ctx.heap, arg1)) {
        indx = arg1.toRaw();
    } else if (reduce.isInt(ctx.heap, arg1)) {
        indx = big.toInt(ctx.heap, arg1.toRaw());
    } else {
        reduce_rt.intError("!");
    }
    if (indx < 0) {
        reduce_rt.subsError();
    }
    while (indx > 0) {
        const next_tl = try reduce.reduceVal(ctx.heap, reduce.tlGet(ctx.heap, lastarg));
        reduce.tlSet(ctx.heap, lastarg, next_tl);
        lastarg = next_tl;
        if (lastarg.toRaw() == word.NIL) {
            reduce_rt.subsError();
        }
        indx -= 1;
    }
    reduce.rewriteToValue(ctx.heap, &ctx.e, reduce.hdGet(ctx.heap, lastarg));
    ctx.action = word.ACT_NEXTREDEX;
}

test "handleSUBSCRIPT: xs ! n indexes the list" {
    tu.freshInterp();
    // [10, 20, 30] ! 1 → 20
    try tu.expectInt(20, tu.ap2(word.SUBSCRIPT, tu.int(1), tu.list(&.{ tu.int(10), tu.int(20), tu.int(30) })));
}

/// `foldl1 f (x:xs) -> foldl f x xs` (errors on `[]`).
///
/// Tests: handleFOLDL1: left fold seeded by the first element
pub fn handleFOLDL1(ctx: *ReductionCtx) reduce.ReduceError!void {
    var arg1: Value = Value.fromRaw(0);
    if (reduce.getarg(ctx, &arg1)) {
        ctx.action = word.ACT_DONE;
        return;
    }
    if (reduce.upleft(ctx)) {
        ctx.action = word.ACT_DONE;
        return;
    }
    const lastarg = try reduce.reduceVal(ctx.heap, reduce.tlGet(ctx.heap, ctx.e));
    if (lastarg.toRaw() != word.NIL) {
        reduce.hdSet(ctx.heap, ctx.e, reduce.ap2(ctx.heap, Value.fromRaw(word.FOLDL), arg1, reduce.hdGet(ctx.heap, lastarg)));
        reduce.tlSet(ctx.heap, ctx.e, reduce.tlGet(ctx.heap, lastarg));
        ctx.action = word.ACT_NEXTREDEX;
    } else {
        reduce_rt.fnError("foldl1 applied to []");
    }
}

test "handleFOLDL1: left fold seeded by the first element" {
    tu.freshInterp();
    // foldl1 (+) [1,2,3] → ((1+2)+3) → 6
    try tu.expectInt(6, tu.ap2(word.FOLDL1, word.PLUS, tu.list(&.{ tu.int(1), tu.int(2), tu.int(3) })));
}

/// `foldl f a xs` — strict left fold.
///
/// Tests: handleFOLDL: strict left fold
pub fn handleFOLDL(ctx: *ReductionCtx) reduce.ReduceError!void {
    var arg1: Value = Value.fromRaw(0);
    var arg2: Value = Value.fromRaw(0);
    if (reduce.getarg(ctx, &arg1)) {
        ctx.action = word.ACT_DONE;
        return;
    }
    if (reduce.getarg(ctx, &arg2)) {
        ctx.action = word.ACT_DONE;
        return;
    }
    if (reduce.upleft(ctx)) {
        ctx.action = word.ACT_DONE;
        return;
    }
    var lastarg = reduce.tlGet(ctx.heap, ctx.e);
    while (true) {
        lastarg = try reduce.reduceVal(ctx.heap, lastarg);
        if (lastarg.toRaw() == word.NIL) break;
        arg2 = try reduce.reduceVal(ctx.heap, reduce.ap2(ctx.heap, arg1, arg2, reduce.hdGet(ctx.heap, lastarg)));
        lastarg = reduce.tlGet(ctx.heap, lastarg);
    }
    reduce.rewriteToValue(ctx.heap, &ctx.e, arg2);
    ctx.action = word.ACT_NEXTREDEX;
}

test "handleFOLDL: strict left fold" {
    tu.freshInterp();
    // foldl (+) 0 [1,2,3] → 6
    try tu.expectInt(6, tu.ap(tu.ap2(word.FOLDL, word.PLUS, tu.int(0)), tu.list(&.{ tu.int(1), tu.int(2), tu.int(3) })));
}

/// `foldr f a (x:xs) -> f x (foldr f a xs)`; `foldr f a [] -> a`.
///
/// Tests: handleFOLDR: right fold
pub fn handleFOLDR(ctx: *ReductionCtx) reduce.ReduceError!void {
    var arg1: Value = Value.fromRaw(0);
    var arg2: Value = Value.fromRaw(0);
    if (reduce.getarg(ctx, &arg1)) {
        ctx.action = word.ACT_DONE;
        return;
    }
    if (reduce.getarg(ctx, &arg2)) {
        ctx.action = word.ACT_DONE;
        return;
    }
    if (reduce.upleft(ctx)) {
        ctx.action = word.ACT_DONE;
        return;
    }
    const lastarg = try reduce.reduceVal(ctx.heap, reduce.tlGet(ctx.heap, ctx.e));
    if (lastarg.toRaw() == word.NIL) {
        reduce.rewriteToValue(ctx.heap, &ctx.e, arg2);
    } else {
        const hold = reduce.ap(ctx.heap, reduce.hdGet(ctx.heap, ctx.e), reduce.tlGet(ctx.heap, lastarg));
        reduce.hdSet(ctx.heap, ctx.e, reduce.ap(ctx.heap, arg1, reduce.hdGet(ctx.heap, lastarg)));
        reduce.tlSet(ctx.heap, ctx.e, hold);
    }
    ctx.action = word.ACT_NEXTREDEX;
}

test "handleFOLDR: right fold" {
    tu.freshInterp();
    // foldr (+) 0 [1,2,3] → 1+(2+(3+0)) → 6
    try tu.expectInt(6, tu.ap(tu.ap2(word.FOLDR, word.PLUS, tu.int(0)), tu.list(&.{ tu.int(1), tu.int(2), tu.int(3) })));
}
