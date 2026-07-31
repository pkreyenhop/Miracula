//! eval/combinators/combinators.zig — rewrite rules for the core combinators.
//!
//! One `handle<COMBINATOR>` per combinator, dispatched from `reducer/reduce.zig`
//! by tag (the handler name mirrors the `word.<COMBINATOR>` constant). They span
//! the SK basis (`I`/`K`/`S`/`B`/`C`/`Y`/`KI`) and Turner's optimised variants
//! (`S1`/`B1`/`C1`, `S_p`/`B_p`/`C_p`), the list primitives (`MAP`/`FILTER`/
//! `FOLDL`/`DROP`/`SUBSCRIPT`/…), pattern-match support (`MATCH`/`TRY`/`FAIL`/
//! `Ug`), and the strict-primitive forcers (`handleStrict{Monadic,Diadic,Triadic}`).
//! Each rewrites the focus node in place and sets `ctx.action` for the driver.

const word = @import("../../graph/word.zig");
const reduce = @import("../reduce_core.zig");
const big = @import("../../graph/bignum.zig");
const heap = @import("../../graph/heap.zig");
const lex = @import("../../parser/lex.zig");
const os = @import("../../os.zig");
const reduce_rt = @import("../reduce_rt.zig");
const tu = @import("../../testutil.zig"); // unit-test harness (test builds only)
const ReductionCtx = reduce.ReductionCtx;
const Word = reduce.Word;
const Value = @import("../../graph/value.zig").Value;

/// `I x -> x` — identity.
pub fn handleI(ctx: *ReductionCtx) void {
    if (reduce.downright(ctx)) {
        ctx.action = word.ACT_DONE;
        return;
    }
    ctx.action = word.ACT_NEXTREDEX;
}

/// `K x y -> x` — first projection.
pub fn handleK(ctx: *ReductionCtx) void {
    var arg1: Value = Value.fromRaw(0);
    if (reduce.getarg(ctx, &arg1)) {
        ctx.action = word.ACT_DONE;
        return;
    }
    if (reduce.upleft(ctx)) {
        ctx.action = word.ACT_DONE;
        return;
    }
    reduce.rewriteToValue(ctx.heap, &ctx.e, arg1);
    ctx.action = word.ACT_NEXTREDEX;
}

/// `S f g x -> (f x) (g x)` — applicative S.
pub fn handleS(ctx: *ReductionCtx) void {
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
    const lastarg = reduce.tlGet(ctx.heap, ctx.e);
    var ap1: Value = undefined;
    var ap2: Value = undefined;
    reduce.apTwo(ctx.heap, arg1, lastarg, arg2, lastarg, &ap1, &ap2);
    reduce.hdSet(ctx.heap, ctx.e, ap1);
    reduce.tlSet(ctx.heap, ctx.e, ap2);
    reduce.downLeft(ctx);
    reduce.downLeft(ctx);
    ctx.action = word.ACT_NEXTREDEX;
}

/// `B f g x -> f (g x)` — composition.
///
/// Tests: handleB: B f g x reduces to f (g x)
pub fn handleB(ctx: *ReductionCtx) void {
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
    const lastarg = reduce.tlGet(ctx.heap, ctx.e);
    reduce.hdSet(ctx.heap, ctx.e, arg1);
    reduce.tlSet(ctx.heap, ctx.e, reduce.ap(ctx.heap, arg2, lastarg));
    reduce.downLeft(ctx);
    ctx.action = word.ACT_NEXTREDEX;
}

test "handleB: B f g x reduces to f (g x)" {
    tu.freshInterp();
    // B I I True → I (I True) → True
    try tu.expectReducesTo(word.True, tu.ap(tu.ap2(word.B, word.I, word.I), word.True));
}

/// `CB f g x -> g (f x)` — reverse composition.
///
/// Tests: handleCB: CB f g x reduces to g (f x)
pub fn handleCB(ctx: *ReductionCtx) void {
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
    const lastarg = reduce.tlGet(ctx.heap, ctx.e);
    reduce.hdSet(ctx.heap, ctx.e, arg2);
    reduce.tlSet(ctx.heap, ctx.e, reduce.ap(ctx.heap, arg1, lastarg));
    reduce.downLeft(ctx);
    ctx.action = word.ACT_NEXTREDEX;
}

test "handleCB: CB f g x reduces to g (f x)" {
    tu.freshInterp();
    // CB I (K True) False → (K True) (I False) → K True False → True
    try tu.expectReducesTo(word.True, tu.ap(tu.ap2(word.CB, word.I, tu.ap(word.K, word.True)), word.False));
}

/// `C f g x -> f x g` — flip the last two arguments.
///
/// Tests: handleC: C f g x reduces to f x g
pub fn handleC(ctx: *ReductionCtx) void {
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
    const lastarg = reduce.tlGet(ctx.heap, ctx.e);
    reduce.hdSet(ctx.heap, ctx.e, reduce.ap(ctx.heap, arg1, lastarg));
    reduce.tlSet(ctx.heap, ctx.e, arg2);
    reduce.downLeft(ctx);
    reduce.downLeft(ctx);
    ctx.action = word.ACT_NEXTREDEX;
}

test "handleC: C f g x reduces to f x g" {
    tu.freshInterp();
    // C K True False → K False True → False
    try tu.expectReducesTo(word.False, tu.ap(tu.ap2(word.C, word.K, word.True), word.False));
}

/// `Y f -> f (Y f)` — fixpoint, built as a self-referential (cyclic) node.
///
/// Tests: handleY: Y f reduces to f (Y f)
pub fn handleY(ctx: *ReductionCtx) void {
    if (reduce.upleft(ctx)) {
        ctx.action = word.ACT_DONE;
        return;
    }
    reduce.hdSet(ctx.heap, ctx.e, reduce.tlGet(ctx.heap, ctx.e));
    reduce.tlSet(ctx.heap, ctx.e, ctx.e);
    reduce.downLeft(ctx);
    ctx.action = word.ACT_NEXTREDEX;
}

test "handleY: Y f reduces to f (Y f)" {
    tu.freshInterp();
    // Y (K 5) → (K 5) (Y (K 5)) → 5 (K discards the recursive argument)
    try tu.expectInt(5, tu.ap(word.Y, tu.ap(word.K, tu.int(5))));
}

/// `KI x y -> y` — second projection (`K I`).
///
/// Tests: handleKI: KI x y reduces to y
pub fn handleKI(ctx: *ReductionCtx) void {
    if (reduce.upleft(ctx)) {
        ctx.action = word.ACT_DONE;
        return;
    }
    if (reduce.upleft(ctx)) {
        ctx.action = word.ACT_DONE;
        return;
    }
    ctx.e = reduce.rewriteToExistingTail(ctx.heap, ctx.e);
    ctx.action = word.ACT_NEXTREDEX;
}

test "handleKI: KI x y reduces to y" {
    tu.freshInterp();
    try tu.expectReducesTo(word.False, tu.ap2(word.KI, word.True, word.False));
}

/// `S1 c f g x -> c (f x) (g x)` — Turner's S' with a context `c`.
///
/// Tests: handleS1: S1 c f g x reduces to c (f x) (g x)
pub fn handleS1(ctx: *ReductionCtx) void {
    var arg1: Value = Value.fromRaw(0);
    var arg2: Value = Value.fromRaw(0);
    var arg3: Value = Value.fromRaw(0);
    if (reduce.getarg(ctx, &arg1)) {
        ctx.action = word.ACT_DONE;
        return;
    }
    if (reduce.getarg(ctx, &arg2)) {
        ctx.action = word.ACT_DONE;
        return;
    }
    if (reduce.getarg(ctx, &arg3)) {
        ctx.action = word.ACT_DONE;
        return;
    }
    if (reduce.upleft(ctx)) {
        ctx.action = word.ACT_DONE;
        return;
    }
    const lastarg = reduce.tlGet(ctx.heap, ctx.e);
    reduce.hdSet(ctx.heap, ctx.e, reduce.ap(ctx.heap, arg2, lastarg));
    reduce.hdSet(ctx.heap, ctx.e, reduce.ap(ctx.heap, arg1, reduce.hdGet(ctx.heap, ctx.e)));
    reduce.tlSet(ctx.heap, ctx.e, reduce.ap(ctx.heap, arg3, lastarg));
    reduce.downLeft(ctx);
    reduce.downLeft(ctx);
    ctx.action = word.ACT_NEXTREDEX;
}

test "handleS1: S1 c f g x reduces to c (f x) (g x)" {
    tu.freshInterp();
    // S1 K I I True → K (I True) (I True) → K True True → True
    try tu.expectReducesTo(word.True, tu.ap(tu.ap(tu.ap2(word.S1, word.K, word.I), word.I), word.True));
}

/// `B1 c f g x -> c (f (g x))` — Turner's B' with a context `c`.
///
/// Tests: handleB1: B1 c f g x reduces to c (f (g x))
pub fn handleB1(ctx: *ReductionCtx) void {
    var arg1: Value = Value.fromRaw(0);
    var arg2: Value = Value.fromRaw(0);
    var arg3: Value = Value.fromRaw(0);
    if (reduce.getarg(ctx, &arg1)) {
        ctx.action = word.ACT_DONE;
        return;
    }
    if (reduce.getarg(ctx, &arg2)) {
        ctx.action = word.ACT_DONE;
        return;
    }
    if (reduce.getarg(ctx, &arg3)) {
        ctx.action = word.ACT_DONE;
        return;
    }
    if (reduce.upleft(ctx)) {
        ctx.action = word.ACT_DONE;
        return;
    }
    const lastarg = reduce.tlGet(ctx.heap, ctx.e);
    reduce.hdSet(ctx.heap, ctx.e, arg1);
    reduce.tlSet(ctx.heap, ctx.e, reduce.ap(ctx.heap, arg3, lastarg));
    reduce.tlSet(ctx.heap, ctx.e, reduce.ap(ctx.heap, arg2, reduce.tlGet(ctx.heap, ctx.e)));
    reduce.downLeft(ctx);
    ctx.action = word.ACT_NEXTREDEX;
}

test "handleB1: B1 c f g x reduces to c (f (g x))" {
    tu.freshInterp();
    // B1 I I I True → I (I (I True)) → True
    try tu.expectReducesTo(word.True, tu.ap(tu.ap(tu.ap2(word.B1, word.I, word.I), word.I), word.True));
}

/// `C1 c f g x -> c (f x) g` — Turner's C' with a context `c`.
///
/// Tests: handleC1: C1 c f g x reduces to c (f x) g
pub fn handleC1(ctx: *ReductionCtx) void {
    var arg1: Value = Value.fromRaw(0);
    var arg2: Value = Value.fromRaw(0);
    var arg3: Value = Value.fromRaw(0);
    if (reduce.getarg(ctx, &arg1)) {
        ctx.action = word.ACT_DONE;
        return;
    }
    if (reduce.getarg(ctx, &arg2)) {
        ctx.action = word.ACT_DONE;
        return;
    }
    if (reduce.getarg(ctx, &arg3)) {
        ctx.action = word.ACT_DONE;
        return;
    }
    if (reduce.upleft(ctx)) {
        ctx.action = word.ACT_DONE;
        return;
    }
    const lastarg = reduce.tlGet(ctx.heap, ctx.e);
    reduce.hdSet(ctx.heap, ctx.e, reduce.ap(ctx.heap, arg2, lastarg));
    reduce.hdSet(ctx.heap, ctx.e, reduce.ap(ctx.heap, arg1, reduce.hdGet(ctx.heap, ctx.e)));
    reduce.tlSet(ctx.heap, ctx.e, arg3);
    reduce.downLeft(ctx);
    ctx.action = word.ACT_NEXTREDEX;
}

test "handleC1: C1 c f g x reduces to c (f x) g" {
    tu.freshInterp();
    // C1 K I False True → K (I True) False → K True False → True
    try tu.expectReducesTo(word.True, tu.ap(tu.ap(tu.ap2(word.C1, word.K, word.I), word.False), word.True));
}

/// `S_p f g x -> (f x) : (g x)` — paired S' (builds a cons).
///
/// Tests: handleS_p: S_p f g x builds (f x) : (g x)
pub fn handleS_p(ctx: *ReductionCtx) void {
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
    const lastarg = reduce.tlGet(ctx.heap, ctx.e);
    reduce.rewriteToCons(ctx.heap, ctx.e, reduce.ap(ctx.heap, arg1, lastarg), reduce.ap(ctx.heap, arg2, lastarg));
    ctx.action = word.ACT_DONE;
}

test "handleS_p: S_p f g x builds (f x) : (g x)" {
    tu.freshInterp();
    // S_p (K 1) (K []) I → (K 1 I) : (K [] I) → 1 : [] → [1]
    try tu.expectList(&.{1}, tu.ap(tu.ap2(word.S_p, tu.ap(word.K, tu.int(1)), tu.ap(word.K, word.NIL)), word.I));
}

/// `B_p f g x -> f : (g x)` — paired B' (builds a cons).
///
/// Tests: handleB_p: B_p f g x builds f : (g x)
pub fn handleB_p(ctx: *ReductionCtx) void {
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
    const lastarg = reduce.tlGet(ctx.heap, ctx.e);
    reduce.rewriteToCons(ctx.heap, ctx.e, arg1, reduce.ap(ctx.heap, arg2, lastarg));
    ctx.action = word.ACT_DONE;
}

test "handleB_p: B_p f g x builds f : (g x)" {
    tu.freshInterp();
    // B_p 1 (K []) I → 1 : (K [] I) → 1 : [] → [1]
    try tu.expectList(&.{1}, tu.ap(tu.ap2(word.B_p, tu.int(1), tu.ap(word.K, word.NIL)), word.I));
}

/// `C_p f g x -> (f x) : g` — paired C' (builds a cons).
///
/// Tests: handleC_p: C_p f g x builds (f x) : g
pub fn handleC_p(ctx: *ReductionCtx) void {
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
    const lastarg = reduce.tlGet(ctx.heap, ctx.e);
    reduce.rewriteToCons(ctx.heap, ctx.e, reduce.ap(ctx.heap, arg1, lastarg), arg2);
    ctx.action = word.ACT_DONE;
}

test "handleC_p: C_p f g x builds (f x) : g" {
    tu.freshInterp();
    // C_p (K 1) [] I → (K 1 I) : [] → 1 : [] → [1]
    try tu.expectList(&.{1}, tu.ap(tu.ap2(word.C_p, tu.ap(word.K, tu.int(1)), word.NIL), word.I));
}

/// `iterate f x -> x : iterate f (f x)` — lazy infinite repeated application.
///
/// Tests: handleITERATE: iterate f x heads x then repeats
pub fn handleITERATE(ctx: *ReductionCtx) void {
    var arg1: Value = Value.fromRaw(0);
    if (reduce.getarg(ctx, &arg1)) {
        ctx.action = word.ACT_DONE;
        return;
    }
    if (reduce.upleft(ctx)) {
        ctx.action = word.ACT_DONE;
        return;
    }
    const lastarg = reduce.tlGet(ctx.heap, ctx.e);
    const hold = reduce.ap(ctx.heap, reduce.hdGet(ctx.heap, ctx.e), reduce.ap(ctx.heap, arg1, lastarg));
    reduce.rewriteToCons(ctx.heap, ctx.e, lastarg, hold);
    ctx.action = word.ACT_DONE;
}

test "handleITERATE: iterate f x heads x then repeats" {
    tu.freshInterp();
    const lst = try reduce.reduceVal(heap.heap(), Value.fromRaw(tu.ap2(word.ITERATE, word.I, tu.int(5))));
    try tu.expectInt(5, reduce.hdGet(heap.heap(), lst).toRaw()); // head is x
    const rest = try reduce.reduceVal(heap.heap(), reduce.tlGet(heap.heap(), lst));
    try tu.expectInt(5, reduce.hdGet(heap.heap(), rest).toRaw()); // next element is I 5 = 5
}

/// Like `ITERATE`, but stops when the next value reduces to `FAIL`.
pub fn handleITERATE1(ctx: *ReductionCtx) reduce.ReduceError!void {
    var arg1: Value = Value.fromRaw(0);
    if (reduce.getarg(ctx, &arg1)) {
        ctx.action = word.ACT_DONE;
        return;
    }
    if (reduce.upleft(ctx)) {
        ctx.action = word.ACT_DONE;
        return;
    }
    var lastarg = reduce.tlGet(ctx.heap, ctx.e);
    lastarg = try reduce.reduceVal(ctx.heap, lastarg);
    ctx.hold = lastarg;
    if (lastarg.toRaw() == word.FAIL) {
        reduce.rewriteToNil(ctx.heap, &ctx.e);
    } else {
        const hold = reduce.ap(ctx.heap, reduce.hdGet(ctx.heap, ctx.e), reduce.ap(ctx.heap, arg1, lastarg));
        reduce.rewriteToCons(ctx.heap, ctx.e, lastarg, hold);
    }
    ctx.action = word.ACT_DONE;
}

/// `P x xs -> x : xs` — the cons (pair) constructor.
///
/// Tests: handleP: P x xs builds the cons (x : xs)
pub fn handleP(ctx: *ReductionCtx) void {
    var arg1: Value = Value.fromRaw(0);
    if (reduce.getarg(ctx, &arg1)) {
        ctx.action = word.ACT_DONE;
        return;
    }
    if (reduce.upleft(ctx)) {
        ctx.action = word.ACT_DONE;
        return;
    }
    const lastarg = reduce.tlGet(ctx.heap, ctx.e);
    reduce.rewriteToCons(ctx.heap, ctx.e, arg1, lastarg);
    ctx.action = word.ACT_DONE;
}

test "handleP: P x xs builds the cons (x : xs)" {
    tu.freshInterp();
    try tu.expectList(&.{1}, tu.ap2(word.P, tu.int(1), word.NIL));
    try tu.expectList(&.{ 1, 2 }, tu.ap2(word.P, tu.int(1), tu.list(&.{tu.int(2)})));
}

/// `U f p -> f (hd p) (tl p)` — uncurry a pair.
///
/// Tests: handleU: U f p applies f to hd p and tl p
pub fn handleU(ctx: *ReductionCtx) void {
    var arg1: Value = Value.fromRaw(0);
    if (reduce.getarg(ctx, &arg1)) {
        ctx.action = word.ACT_DONE;
        return;
    }
    if (reduce.upleft(ctx)) {
        ctx.action = word.ACT_DONE;
        return;
    }
    const lastarg = reduce.tlGet(ctx.heap, ctx.e);
    reduce.hdSet(ctx.heap, ctx.e, reduce.ap(ctx.heap, arg1, reduce.ap(ctx.heap, Value.fromRaw(word.HD), lastarg)));
    reduce.tlSet(ctx.heap, ctx.e, reduce.ap(ctx.heap, Value.fromRaw(word.TL), lastarg));
    reduce.downLeft(ctx);
    reduce.downLeft(ctx);
    ctx.action = word.ACT_NEXTREDEX;
}

test "handleU: U f p applies f to hd p and tl p" {
    tu.freshInterp();
    // U K [1, 2] → K (hd [1,2]) (tl [1,2]) → K 1 [2] → 1
    try tu.expectInt(1, tu.ap2(word.U, word.K, tu.list(&.{ tu.int(1), tu.int(2) })));
}

/// Uncurry handling partial constructors: split via hd/tl for a cons, else via `BODY`/`LAST`, and apply `f`.
pub fn handleUf(ctx: *ReductionCtx) void {
    var arg1: Value = Value.fromRaw(0);
    if (reduce.getarg(ctx, &arg1)) {
        ctx.action = word.ACT_DONE;
        return;
    }
    if (reduce.upleft(ctx)) {
        ctx.action = word.ACT_DONE;
        return;
    }
    const lastarg = reduce.tlGet(ctx.heap, ctx.e);
    if (reduce.isConstructor(ctx.heap, reduce.headVal(ctx.heap, lastarg))) {
        reduce.hdSet(ctx.heap, ctx.e, reduce.ap(ctx.heap, arg1, reduce.hdGet(ctx.heap, lastarg)));
        reduce.tlSet(ctx.heap, ctx.e, reduce.tlGet(ctx.heap, lastarg));
    } else {
        reduce.hdSet(ctx.heap, ctx.e, reduce.ap(ctx.heap, arg1, reduce.ap(ctx.heap, Value.fromRaw(word.BODY), lastarg)));
        reduce.tlSet(ctx.heap, ctx.e, reduce.ap(ctx.heap, Value.fromRaw(word.LAST), lastarg));
    }
    reduce.downLeft(ctx);
    reduce.downLeft(ctx);
    ctx.action = word.ACT_NEXTREDEX;
}

/// `ATLEAST n f k -> f (k - n)` when `k` is an int `>= n`, else `FAIL` (a repetition guard).
///
/// Tests: handleATLEAST: passes f (k - n) when k >= n, else FAIL
pub fn handleATLEAST(ctx: *ReductionCtx) reduce.ReduceError!void {
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
    lastarg = try reduce.reduceVal(ctx.heap, lastarg);
    if (reduce.isInt(ctx.heap, lastarg)) {
        const hold = Value.fromRaw(big.sub(ctx.heap, lastarg.toRaw(), arg1.toRaw()));
        if (reduce.poz(ctx.heap, hold)) {
            reduce.hdSet(ctx.heap, ctx.e, arg2);
            reduce.tlSet(ctx.heap, ctx.e, hold);
        } else {
            reduce.rewriteToFail(ctx.heap, &ctx.e);
        }
    } else {
        reduce.rewriteToFail(ctx.heap, &ctx.e);
    }
    ctx.action = word.ACT_NEXTREDEX;
}

test "handleATLEAST: passes f (k - n) when k >= n, else FAIL" {
    tu.freshInterp();
    // ATLEAST 1 I 3 → I (3 - 1) → 2
    try tu.expectInt(2, tu.ap(tu.ap2(word.ATLEAST, tu.int(1), word.I), tu.int(3)));
    // ATLEAST 5 I 3 → 3 - 5 < 0 → FAIL
    try tu.expectReducesTo(word.FAIL, tu.ap(tu.ap2(word.ATLEAST, tu.int(5), word.I), tu.int(3)));
}

/// `U_ f xs -> f (hd xs) (tl xs)`, or `FAIL` on `[]` — strict uncurry of a non-empty list.
///
/// Tests: handleU_: strict uncurry, FAIL on the empty list
pub fn handleU_(ctx: *ReductionCtx) reduce.ReduceError!void {
    var arg1: Value = Value.fromRaw(0);
    if (reduce.getarg(ctx, &arg1)) {
        ctx.action = word.ACT_DONE;
        return;
    }
    if (reduce.upleft(ctx)) {
        ctx.action = word.ACT_DONE;
        return;
    }
    var lastarg = reduce.tlGet(ctx.heap, ctx.e);
    lastarg = try reduce.reduceVal(ctx.heap, lastarg);
    if (lastarg.toRaw() == word.NIL) {
        reduce.rewriteToFail(ctx.heap, &ctx.e);
        ctx.action = word.ACT_NEXTREDEX;
        return;
    }
    reduce.hdSet(ctx.heap, ctx.e, reduce.ap(ctx.heap, arg1, reduce.hdGet(ctx.heap, lastarg)));
    reduce.tlSet(ctx.heap, ctx.e, reduce.tlGet(ctx.heap, lastarg));
    ctx.action = word.ACT_NEXTREDEX;
}

test "handleU_: strict uncurry, FAIL on the empty list" {
    tu.freshInterp();
    // U_ K [1,2] → K 1 [2] → 1
    try tu.expectInt(1, tu.ap2(word.U_, word.K, tu.list(&.{ tu.int(1), tu.int(2) })));
    // U_ K [] → FAIL
    try tu.expectReducesTo(word.FAIL, tu.ap2(word.U_, word.K, word.NIL));
}

/// Guarded uncurry: match the value's constructor against `arg1`; on mismatch `FAIL`, else deconstruct and apply (the pattern-match destructor).
pub fn handleUg(ctx: *ReductionCtx) reduce.ReduceError!void {
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
    lastarg = try reduce.reduceVal(ctx.heap, lastarg);
    ctx.hold = lastarg;
    if (reduce.hdGet(ctx.heap, arg1) != reduce.hdGet(ctx.heap, reduce.headVal(ctx.heap, lastarg))) {
        reduce.rewriteToFail(ctx.heap, &ctx.e);
        ctx.action = word.ACT_NEXTREDEX;
        return;
    }
    if (reduce.isConstructor(ctx.heap, lastarg)) {
        reduce.rewriteToValue(ctx.heap, &ctx.e, arg2);
        ctx.action = word.ACT_NEXTREDEX;
        return;
    }
    reduce.hdSet(ctx.heap, ctx.e, reduce.hdGet(ctx.heap, lastarg));
    reduce.tlSet(ctx.heap, ctx.e, reduce.tlGet(ctx.heap, lastarg));
    while (!reduce.isConstructor(ctx.heap, reduce.hdGet(ctx.heap, ctx.e))) {
        reduce.hdSet(ctx.heap, ctx.e, reduce.ap(ctx.heap, reduce.hdGet(ctx.heap, reduce.hdGet(ctx.heap, ctx.e)), reduce.tlGet(ctx.heap, reduce.hdGet(ctx.heap, ctx.e))));
        reduce.downLeft(ctx);
    }
    reduce.hdSet(ctx.heap, ctx.e, arg2);
    ctx.action = word.ACT_NEXTREDEX;
}

/// `MATCH p v k` — match value `v` against pattern `p`, giving `k` on success or `FAIL`.
pub fn handleMATCH(ctx: *ReductionCtx) reduce.ReduceError!void {
    if (reduce.upleft(ctx)) {
        ctx.action = word.ACT_DONE;
        return;
    }
    ctx.args[0] = try reduce.reduceVal(ctx.heap, reduce.tlGet(ctx.heap, ctx.e));
    const arg1 = ctx.args[0];
    if (reduce.getarg(ctx, &ctx.args[1])) {
        ctx.action = word.ACT_DONE;
        return;
    }
    const arg2 = ctx.args[1];
    if (reduce.upleft(ctx)) {
        ctx.action = word.ACT_DONE;
        return;
    }
    const lastarg = try reduce.reduceVal(ctx.heap, reduce.tlGet(ctx.heap, ctx.e));
    try reduce.rewriteToMatchResult(ctx.heap, &ctx.e, arg1, lastarg, arg2);
    ctx.action = word.ACT_NEXTREDEX;
}

/// As `MATCH`, specialised to an integer-literal pattern.
pub fn handleMATCHINT(ctx: *ReductionCtx) reduce.ReduceError!void {
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
    reduce.rewriteToIntMatchResult(ctx.heap, &ctx.e, arg1, lastarg, arg2);
    ctx.action = word.ACT_NEXTREDEX;
}

/// Arithmetic-sequence step (`[a..b]`): emit the next term and recurse, stopping past the bound.
pub fn handleGENSEQ(ctx: *ReductionCtx) reduce.ReduceError!void {
    var arg1: Value = Value.fromRaw(0);
    reduce.GETARG(ctx, &arg1);
    if (reduce.upleft(ctx)) {
        ctx.action = word.ACT_DONE;
        return;
    }
    const lastarg = reduce.tlGet(ctx.heap, ctx.e);
    if (reduce.tlGet(ctx.heap, arg1).toRaw() != word.NIL and
        (if (reduce.isAp(ctx.heap, arg1)) try reduce_rt.compare(ctx.heap, lastarg, reduce.tlGet(ctx.heap, arg1)) else try reduce_rt.compare(ctx.heap, reduce.tlGet(ctx.heap, arg1), lastarg)) > 0)
    {
        reduce.rewriteToNil(ctx.heap, &ctx.e);
    } else {
        const hold = reduce.ap(ctx.heap, reduce.hdGet(ctx.heap, ctx.e), Value.fromRaw(try reduce_rt.numplus(ctx.heap, lastarg, reduce.hdGet(ctx.heap, arg1))));
        reduce.rewriteToCons(ctx.heap, ctx.e, lastarg, hold);
    }
    ctx.action = word.ACT_DONE;
}

/// Raise the "no matching case" runtime error for the offending value.
pub fn handleBADCASE(ctx: *ReductionCtx) reduce.ReduceError!void {
    if (reduce.upleft(ctx)) {
        ctx.action = word.ACT_DONE;
        return;
    }
    const lastarg = reduce.tlGet(ctx.heap, ctx.e);
    try reduce.badcaseErrorVal(ctx.heap, lastarg);
}

/// Yield the program's command-line arguments as a Miranda list (`convArgs`).
pub fn handleGETARGS(ctx: *ReductionCtx) void {
    if (reduce.upleft(ctx)) {
        ctx.action = word.ACT_DONE;
        return;
    }
    reduce.simpl(ctx, Value.fromRaw(reduce.convArgs()));
    ctx.action = word.ACT_DONE;
}

/// Raise the conformality (pattern-conflict) runtime error.
pub fn handleCONFERROR(ctx: *ReductionCtx) reduce.ReduceError!void {
    if (reduce.upleft(ctx)) {
        ctx.action = word.ACT_DONE;
        return;
    }
    const lastarg = reduce.tlGet(ctx.heap, ctx.e);
    reduce.confErrorVal(ctx.heap, lastarg);
}

/// `error s` — print the message and abort the program (guarding against repeated errors).
pub fn handleERROR(ctx: *ReductionCtx) reduce.ReduceError!void {
    if (reduce.upleft(ctx)) {
        ctx.action = word.ACT_DONE;
        return;
    }
    const lastarg = reduce.tlGet(ctx.heap, ctx.e);
    if (ctx.eval.errtrap != 0) {
        word.printErr("\n(repeated error)\n", .{});
    } else {
        ctx.eval.errtrap = 1;
        word.printErr("\nprogram error: ", .{});
        ctx.eval.s_out = reduce.getStderr();
        try reduce_rt.print(ctx.heap, ctx.eval, ctx.rs, lastarg);
        _ = word.putc('\n', reduce.getStderr().?);
    }
    reduce_rt.outstats();
    os.exit(1);
}

/// POSIX `WEXITSTATUS`: the low-byte exit code from a child's wait status.
fn WEXITSTATUS(status: i32) i32 {
    return (status >> 8) & 0xff;
}

/// `wait pid` — reap child `pid` (consulting the pending-children list) and yield its exit status.
pub fn handleWAIT(ctx: *ReductionCtx) void {
    if (reduce.upleft(ctx)) {
        ctx.action = word.ACT_DONE;
        return;
    }
    const lastarg = reduce.tlGet(ctx.heap, ctx.e);
    var hold: Word = 0;
    var w: *Word = &ctx.eval.waiting;
    while (w.* != word.NIL and reduce.hdGet(ctx.heap, Value.fromRaw(w.*)).toRaw() != lastarg.toRaw()) {
        w = reduce.tlPtr(ctx.heap, reduce.tlGet(ctx.heap, Value.fromRaw(w.*)));
    }
    if (w.* != word.NIL) {
        hold = reduce.hdGet(ctx.heap, reduce.tlGet(ctx.heap, Value.fromRaw(w.*))).toRaw();
        w.* = reduce.tlGet(ctx.heap, reduce.tlGet(ctx.heap, Value.fromRaw(w.*))).toRaw();
    } else {
        var status: i32 = 0;
        while (true) {
            const res = os.wait(&status);
            if (res == lastarg.toRaw() or res == -1) {
                hold = res;
                break;
            }
            ctx.eval.waiting = reduce.cons(ctx.heap, Value.fromRaw(res), reduce.cons(ctx.heap, Value.fromRaw(@intCast(WEXITSTATUS(status))), Value.fromRaw(ctx.eval.waiting))).toRaw();
        }
        if (hold != -1) {
            hold = WEXITSTATUS(status);
        }
    }
    reduce.simpl(ctx, Value.fromRaw(heap.stosmallint(hold)));
    ctx.action = word.ACT_DONE;
}

/// Alternation: evaluate the first alternative, falling back to the second on `FAIL` — backtracking across multi-equation definitions.
pub fn handleTRY(ctx: *ReductionCtx) void {
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
    while (!ctx.spine.atArgumentChainBoundary()) {
        if (reduce.upleft(ctx)) {
            ctx.action = word.ACT_DONE;
            return;
        }
        const lastarg = reduce.tlGet(ctx.heap, ctx.e);
        arg1 = reduce.ap(ctx.heap, arg1, lastarg);
        reduce.hdSet(ctx.heap, ctx.e, reduce.ap(ctx.heap, Value.fromRaw(word.TRY), arg1));
        arg2 = reduce.ap(ctx.heap, arg2, lastarg);
        reduce.tlSet(ctx.heap, ctx.e, arg2);
    }
    // Fabricates a frame out of a cell already in hand (old_hd_e), tagged
    // via_tl from the start -- distinct from an ordinary downLeft/downRight
    // pair, hence the direct Spine.pushRaw rather than one of the four
    // primitives. h_node (what downLeft is about to push a frame for) must be
    // captured *before* the call -- there is no ctx.s to read it back from
    // afterward the way the old pointer-reversal encoding allowed.
    const h_node = ctx.e;
    reduce.downLeft(ctx);
    const old_hd_e = ctx.e;
    ctx.e = reduce.tlGet(ctx.heap, old_hd_e);
    reduce.tlSet(ctx.heap, old_hd_e, h_node);
    ctx.spine.pushRaw(old_hd_e, true);
    ctx.action = word.ACT_NEXTREDEX;
}

/// Propagate `FAIL` up the spine, collapsing pending alternatives until a `TRY` catches it.
pub fn handleFAIL(ctx: *ReductionCtx) void {
    while (!ctx.spine.atArgumentChainBoundary()) {
        const node = ctx.spine.popNodeOnly().?;
        reduce.hdSet(ctx.heap, node, Value.fromRaw(word.FAIL));
        reduce.tlSet(ctx.heap, node, Value.fromRaw(0));
    }
    ctx.action = word.ACT_DONE;
}

/// Render a constructor application as text for `show`: the constructor name plus space-separated, parenthesised arguments.
pub fn handleUsh1(ctx: *ReductionCtx) reduce.ReduceError!void {
    var arg1: Value = Value.fromRaw(0);
    var arg2: Value = Value.fromRaw(0);
    var arg3: Value = Value.fromRaw(0);
    if (reduce.getarg(ctx, &arg1)) {
        ctx.action = word.ACT_DONE;
        return;
    }
    arg1 = try reduce.reduceVal(ctx.heap, arg1);
    if (reduce.getarg(ctx, &arg2)) {
        ctx.action = word.ACT_DONE;
        return;
    }
    arg2 = try reduce.reduceVal(ctx.heap, arg2);
    if (reduce.getarg(ctx, &arg3)) {
        ctx.action = word.ACT_DONE;
        return;
    }
    if (reduce.isConstructor(ctx.heap, arg1)) {
        if (reduce.suppressed(ctx.heap, arg1)) {
            reduce.rewriteToString(ctx.heap, &ctx.e, "<unprintable>");
        } else {
            reduce.rewriteToString(ctx.heap, &ctx.e, reduce.constrName(ctx.heap, arg1));
        }
        ctx.action = word.ACT_DONE;
        return;
    }
    var hold = if (arg2.toRaw() != 0) reduce.cons(ctx.heap, Value.imm(')'), Value.fromRaw(word.NIL)) else Value.fromRaw(word.NIL);
    while (!reduce.isConstructor(ctx.heap, arg1)) {
        hold = reduce.cons(ctx.heap, Value.imm(' '), reduce.ap2(ctx.heap, Value.fromRaw(word.APPEND), reduce.ap(ctx.heap, reduce.tlGet(ctx.heap, arg1), reduce.ap(ctx.heap, Value.fromRaw(word.LAST), arg3)), hold));
        arg1 = reduce.hdGet(ctx.heap, arg1);
        arg3 = reduce.ap(ctx.heap, Value.fromRaw(word.BODY), arg3);
    }
    if (reduce.suppressed(ctx.heap, arg1)) {
        reduce.rewriteToString(ctx.heap, &ctx.e, "<unprintable>");
        ctx.action = word.ACT_DONE;
        return;
    }
    hold = reduce.ap2(ctx.heap, Value.fromRaw(word.APPEND), Value.fromRaw(lex.strConv(reduce.constrName(ctx.heap, arg1))), hold);
    if (arg2.toRaw() != 0) {
        reduce.rewriteToCons(ctx.heap, ctx.e, Value.imm('('), hold);
        ctx.action = word.ACT_DONE;
    } else {
        reduce.rewriteToValue(ctx.heap, &ctx.e, hold);
        ctx.action = word.ACT_NEXTREDEX;
    }
}

/// `mkstrict n f` — force the first `n` arguments before applying `f` (a strictness annotation).
pub fn handleMKSTRICT(ctx: *ReductionCtx) reduce.ReduceError!void {
    var arg1_val: Value = Value.fromRaw(0);
    var arg2: Value = Value.fromRaw(0);
    reduce.GETARG(ctx, &arg1_val);
    if (reduce.getarg(ctx, &arg2)) {
        ctx.action = word.ACT_DONE;
        return;
    }
    // `arg1` is used purely as a decrementing strictness count (`mkstrict n
    // f`'s `n`), never dereferenced as a heap value, so it's a plain scalar
    // here (decoded once from the pulled `Value`), not `Value` itself.
    var arg1 = arg1_val.toRaw();
    {
        var i = arg1;
        while (i > 0) {
            if (reduce.upleft(ctx)) {
                ctx.action = word.ACT_DONE;
                return;
            }
            i -= 1;
        }
    }
    var lastarg = reduce.tlGet(ctx.heap, ctx.e);
    lastarg = try reduce.reduceVal(ctx.heap, lastarg);
    while (arg1 > 1) {
        reduce.hdSet(ctx.heap, ctx.e, reduce.ap(ctx.heap, reduce.hdGet(ctx.heap, reduce.hdGet(ctx.heap, ctx.e)), reduce.tlGet(ctx.heap, reduce.hdGet(ctx.heap, ctx.e))));
        reduce.downLeft(ctx);
        arg1 -= 1;
    }
    reduce.hdSet(ctx.heap, ctx.e, arg2);
    ctx.action = word.ACT_NEXTREDEX;
}

/// Strict 1-arg primitive: force the single argument, then re-dispatch (`NEG`, `HD`, the maths functions, ...).
pub fn handleStrictMonadic(ctx: *ReductionCtx) void {
    if (reduce.downright(ctx)) {
        ctx.action = word.ACT_DONE;
        return;
    }
    ctx.action = word.ACT_NEXTREDEX;
}

/// Strict 2-arg primitive: force both arguments, then re-dispatch (`PLUS`, `EQ`, `MOD`, ...).
pub fn handleStrictDiadic(ctx: *ReductionCtx) void {
    if (reduce.upleft(ctx)) {
        ctx.action = word.ACT_DONE;
        return;
    }
    if (reduce.downright(ctx)) {
        ctx.action = word.ACT_DONE;
        return;
    }
    ctx.action = word.ACT_NEXTREDEX;
}

/// Strict 3-arg primitive: force all three arguments, then re-dispatch (`Ush`, `STEPUNTIL`).
pub fn handleStrictTriadic(ctx: *ReductionCtx) void {
    if (reduce.upleft(ctx)) {
        ctx.action = word.ACT_DONE;
        return;
    }
    if (reduce.upleft(ctx)) {
        ctx.action = word.ACT_DONE;
        return;
    }
    if (reduce.downright(ctx)) {
        ctx.action = word.ACT_DONE;
        return;
    }
    ctx.action = word.ACT_NEXTREDEX;
}
