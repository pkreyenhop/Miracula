//! reducer/combinators.zig — rewrite rules for the core combinators.
//!
//! One `handle<COMBINATOR>` per combinator, dispatched from `reducer/reduce.zig`
//! by tag (the handler name mirrors the `word.<COMBINATOR>` constant). They span
//! the SK basis (`I`/`K`/`S`/`B`/`C`/`Y`/`KI`) and Turner's optimised variants
//! (`S1`/`B1`/`C1`, `S_p`/`B_p`/`C_p`), the list primitives (`MAP`/`FILTER`/
//! `FOLDL`/`DROP`/`SUBSCRIPT`/…), pattern-match support (`MATCH`/`TRY`/`FAIL`/
//! `Ug`), and the strict-primitive forcers (`handleStrict{Monadic,Diadic,Triadic}`).
//! Each rewrites the focus node in place and sets `ctx.action` for the driver.

const std = @import("std");
const word = @import("../word.zig");
const reduce = @import("reduce_core.zig");
const big = @import("../big.zig");
const heap = @import("../heap.zig");
const lex = @import("../../parser/lex.zig");
const main_clib = @import("../main_clib.zig");
const reduce_rt = @import("../reduce.zig");
const ReductionCtx = reduce.ReductionCtx;
const Word = reduce.Word;



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
    var arg1: Word = 0;
    if (reduce.getarg(ctx, &arg1)) {
        ctx.action = word.ACT_DONE;
        return;
    }
    if (reduce.upleft(ctx)) {
        ctx.action = word.ACT_DONE;
        return;
    }
    reduce.rewrite_to_value(&ctx.e, arg1);
    ctx.action = word.ACT_NEXTREDEX;
}

/// `S f g x -> (f x) (g x)` — applicative S.
pub fn handleS(ctx: *ReductionCtx) void {
    var arg1: Word = 0;
    var arg2: Word = 0;
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
    const lastarg = reduce.tl_get(ctx.e);
    reduce.hd_set(ctx.e, reduce.ap(arg1, lastarg));
    reduce.tl_set(ctx.e, reduce.ap(arg2, lastarg));
    reduce.downLeft(ctx);
    reduce.downLeft(ctx);
    ctx.action = word.ACT_NEXTREDEX;
}

/// `B f g x -> f (g x)` — composition.
pub fn handleB(ctx: *ReductionCtx) void {
    var arg1: Word = 0;
    var arg2: Word = 0;
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
    const lastarg = reduce.tl_get(ctx.e);
    reduce.hd_set(ctx.e, arg1);
    reduce.tl_set(ctx.e, reduce.ap(arg2, lastarg));
    reduce.downLeft(ctx);
    ctx.action = word.ACT_NEXTREDEX;
}

/// `CB f g x -> g (f x)` — reverse composition.
pub fn handleCB(ctx: *ReductionCtx) void {
    var arg1: Word = 0;
    var arg2: Word = 0;
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
    const lastarg = reduce.tl_get(ctx.e);
    reduce.hd_set(ctx.e, arg2);
    reduce.tl_set(ctx.e, reduce.ap(arg1, lastarg));
    reduce.downLeft(ctx);
    ctx.action = word.ACT_NEXTREDEX;
}

/// `C f g x -> f x g` — flip the last two arguments.
pub fn handleC(ctx: *ReductionCtx) void {
    var arg1: Word = 0;
    var arg2: Word = 0;
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
    const lastarg = reduce.tl_get(ctx.e);
    reduce.hd_set(ctx.e, reduce.ap(arg1, lastarg));
    reduce.tl_set(ctx.e, arg2);
    reduce.downLeft(ctx);
    reduce.downLeft(ctx);
    ctx.action = word.ACT_NEXTREDEX;
}

/// `Y f -> f (Y f)` — fixpoint, built as a self-referential (cyclic) node.
pub fn handleY(ctx: *ReductionCtx) void {
    if (reduce.upleft(ctx)) {
        ctx.action = word.ACT_DONE;
        return;
    }
    reduce.hd_set(ctx.e, reduce.tl_get(ctx.e));
    reduce.tl_set(ctx.e, ctx.e);
    reduce.downLeft(ctx);
    ctx.action = word.ACT_NEXTREDEX;
}

/// `KI x y -> y` — second projection (`K I`).
pub fn handleKI(ctx: *ReductionCtx) void {
    if (reduce.upleft(ctx)) {
        ctx.action = word.ACT_DONE;
        return;
    }
    if (reduce.upleft(ctx)) {
        ctx.action = word.ACT_DONE;
        return;
    }
    ctx.e = reduce.rewrite_to_existing_tail(ctx.e);
    ctx.action = word.ACT_NEXTREDEX;
}

/// `S1 c f g x -> c (f x) (g x)` — Turner's S' with a context `c`.
pub fn handleS1(ctx: *ReductionCtx) void {
    var arg1: Word = 0;
    var arg2: Word = 0;
    var arg3: Word = 0;
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
    const lastarg = reduce.tl_get(ctx.e);
    reduce.hd_set(ctx.e, reduce.ap(arg2, lastarg));
    reduce.hd_set(ctx.e, reduce.ap(arg1, reduce.hd_get(ctx.e)));
    reduce.tl_set(ctx.e, reduce.ap(arg3, lastarg));
    reduce.downLeft(ctx);
    reduce.downLeft(ctx);
    ctx.action = word.ACT_NEXTREDEX;
}

/// `B1 c f g x -> c (f (g x))` — Turner's B' with a context `c`.
pub fn handleB1(ctx: *ReductionCtx) void {
    var arg1: Word = 0;
    var arg2: Word = 0;
    var arg3: Word = 0;
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
    const lastarg = reduce.tl_get(ctx.e);
    reduce.hd_set(ctx.e, arg1);
    reduce.tl_set(ctx.e, reduce.ap(arg3, lastarg));
    reduce.tl_set(ctx.e, reduce.ap(arg2, reduce.tl_get(ctx.e)));
    reduce.downLeft(ctx);
    ctx.action = word.ACT_NEXTREDEX;
}

/// `C1 c f g x -> c (f x) g` — Turner's C' with a context `c`.
pub fn handleC1(ctx: *ReductionCtx) void {
    var arg1: Word = 0;
    var arg2: Word = 0;
    var arg3: Word = 0;
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
    const lastarg = reduce.tl_get(ctx.e);
    reduce.hd_set(ctx.e, reduce.ap(arg2, lastarg));
    reduce.hd_set(ctx.e, reduce.ap(arg1, reduce.hd_get(ctx.e)));
    reduce.tl_set(ctx.e, arg3);
    reduce.downLeft(ctx);
    ctx.action = word.ACT_NEXTREDEX;
}

/// `S_p f g x -> (f x) : (g x)` — paired S' (builds a cons).
pub fn handleS_p(ctx: *ReductionCtx) void {
    var arg1: Word = 0;
    var arg2: Word = 0;
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
    const lastarg = reduce.tl_get(ctx.e);
    reduce.rewrite_to_cons(ctx.e, reduce.ap(arg1, lastarg), reduce.ap(arg2, lastarg));
    ctx.action = word.ACT_DONE;
}

/// `B_p f g x -> f : (g x)` — paired B' (builds a cons).
pub fn handleB_p(ctx: *ReductionCtx) void {
    var arg1: Word = 0;
    var arg2: Word = 0;
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
    const lastarg = reduce.tl_get(ctx.e);
    reduce.rewrite_to_cons(ctx.e, arg1, reduce.ap(arg2, lastarg));
    ctx.action = word.ACT_DONE;
}

/// `C_p f g x -> (f x) : g` — paired C' (builds a cons).
pub fn handleC_p(ctx: *ReductionCtx) void {
    var arg1: Word = 0;
    var arg2: Word = 0;
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
    const lastarg = reduce.tl_get(ctx.e);
    reduce.rewrite_to_cons(ctx.e, reduce.ap(arg1, lastarg), arg2);
    ctx.action = word.ACT_DONE;
}

/// `iterate f x -> x : iterate f (f x)` — lazy infinite repeated application.
pub fn handleITERATE(ctx: *ReductionCtx) void {
    var arg1: Word = 0;
    if (reduce.getarg(ctx, &arg1)) {
        ctx.action = word.ACT_DONE;
        return;
    }
    if (reduce.upleft(ctx)) {
        ctx.action = word.ACT_DONE;
        return;
    }
    const lastarg = reduce.tl_get(ctx.e);
    const hold = reduce.ap(reduce.hd_get(ctx.e), reduce.ap(arg1, lastarg));
    reduce.rewrite_to_cons(ctx.e, lastarg, hold);
    ctx.action = word.ACT_DONE;
}

/// Like `ITERATE`, but stops when the next value reduces to `FAIL`.
pub fn handleITERATE1(ctx: *ReductionCtx) void {
    var arg1: Word = 0;
    if (reduce.getarg(ctx, &arg1)) {
        ctx.action = word.ACT_DONE;
        return;
    }
    if (reduce.upleft(ctx)) {
        ctx.action = word.ACT_DONE;
        return;
    }
    var lastarg = reduce.tl_get(ctx.e);
    lastarg = reduce.reduce(lastarg);
    if (lastarg == word.FAIL) {
        reduce.rewrite_to_nil(&ctx.e);
    } else {
        const hold = reduce.ap(reduce.hd_get(ctx.e), reduce.ap(arg1, lastarg));
        reduce.rewrite_to_cons(ctx.e, lastarg, hold);
    }
    ctx.action = word.ACT_DONE;
}

/// `P x xs -> x : xs` — the cons (pair) constructor.
pub fn handleP(ctx: *ReductionCtx) void {
    var arg1: Word = 0;
    if (reduce.getarg(ctx, &arg1)) {
        ctx.action = word.ACT_DONE;
        return;
    }
    if (reduce.upleft(ctx)) {
        ctx.action = word.ACT_DONE;
        return;
    }
    const lastarg = reduce.tl_get(ctx.e);
    reduce.rewrite_to_cons(ctx.e, arg1, lastarg);
    ctx.action = word.ACT_DONE;
}

/// `U f p -> f (hd p) (tl p)` — uncurry a pair.
pub fn handleU(ctx: *ReductionCtx) void {
    var arg1: Word = 0;
    if (reduce.getarg(ctx, &arg1)) {
        ctx.action = word.ACT_DONE;
        return;
    }
    if (reduce.upleft(ctx)) {
        ctx.action = word.ACT_DONE;
        return;
    }
    const lastarg = reduce.tl_get(ctx.e);
    reduce.hd_set(ctx.e, reduce.ap(arg1, reduce.ap(word.HD, lastarg)));
    reduce.tl_set(ctx.e, reduce.ap(word.TL, lastarg));
    reduce.downLeft(ctx);
    reduce.downLeft(ctx);
    ctx.action = word.ACT_NEXTREDEX;
}

/// Uncurry handling partial constructors: split via hd/tl for a cons, else via `BODY`/`LAST`, and apply `f`.
pub fn handleUf(ctx: *ReductionCtx) void {
    var arg1: Word = 0;
    if (reduce.getarg(ctx, &arg1)) {
        ctx.action = word.ACT_DONE;
        return;
    }
    if (reduce.upleft(ctx)) {
        ctx.action = word.ACT_DONE;
        return;
    }
    const lastarg = reduce.tl_get(ctx.e);
    if (reduce.is_constructor(reduce.head(lastarg))) {
        reduce.hd_set(ctx.e, reduce.ap(arg1, reduce.hd_get(lastarg)));
        reduce.tl_set(ctx.e, reduce.tl_get(lastarg));
    } else {
        reduce.hd_set(ctx.e, reduce.ap(arg1, reduce.ap(word.BODY, lastarg)));
        reduce.tl_set(ctx.e, reduce.ap(word.LAST, lastarg));
    }
    reduce.downLeft(ctx);
    reduce.downLeft(ctx);
    ctx.action = word.ACT_NEXTREDEX;
}

/// `ATLEAST n f k -> f (k - n)` when `k` is an int `>= n`, else `FAIL` (a repetition guard).
pub fn handleATLEAST(ctx: *ReductionCtx) void {
    var arg1: Word = 0;
    var arg2: Word = 0;
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
    var lastarg = reduce.tl_get(ctx.e);
    lastarg = reduce.reduce(lastarg);
    if (reduce.is_int(lastarg)) {
        const hold = big.sub(lastarg, arg1);
        if (reduce.poz(hold)) {
            reduce.hd_set(ctx.e, arg2);
            reduce.tl_set(ctx.e, hold);
        } else {
            reduce.rewrite_to_fail(&ctx.e);
        }
    } else {
        reduce.rewrite_to_fail(&ctx.e);
    }
    ctx.action = word.ACT_NEXTREDEX;
}

/// `U_ f xs -> f (hd xs) (tl xs)`, or `FAIL` on `[]` — strict uncurry of a non-empty list.
pub fn handleU_(ctx: *ReductionCtx) void {
    var arg1: Word = 0;
    if (reduce.getarg(ctx, &arg1)) {
        ctx.action = word.ACT_DONE;
        return;
    }
    if (reduce.upleft(ctx)) {
        ctx.action = word.ACT_DONE;
        return;
    }
    var lastarg = reduce.tl_get(ctx.e);
    lastarg = reduce.reduce(lastarg);
    if (lastarg == word.NIL) {
        reduce.rewrite_to_fail(&ctx.e);
        ctx.action = word.ACT_NEXTREDEX;
        return;
    }
    reduce.hd_set(ctx.e, reduce.ap(arg1, reduce.hd_get(lastarg)));
    reduce.tl_set(ctx.e, reduce.tl_get(lastarg));
    ctx.action = word.ACT_NEXTREDEX;
}

/// Guarded uncurry: match the value's constructor against `arg1`; on mismatch `FAIL`, else deconstruct and apply (the pattern-match destructor).
pub fn handleUg(ctx: *ReductionCtx) void {
    var arg1: Word = 0;
    var arg2: Word = 0;
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
    var lastarg = reduce.tl_get(ctx.e);
    lastarg = reduce.reduce(lastarg);
    if (reduce.hd_get(arg1) != reduce.hd_get(reduce.head(lastarg))) {
        reduce.rewrite_to_fail(&ctx.e);
        ctx.action = word.ACT_NEXTREDEX;
        return;
    }
    if (reduce.is_constructor(lastarg)) {
        reduce.rewrite_to_value(&ctx.e, arg2);
        ctx.action = word.ACT_NEXTREDEX;
        return;
    }
    reduce.hd_set(ctx.e, reduce.hd_get(lastarg));
    reduce.tl_set(ctx.e, reduce.tl_get(lastarg));
    while (!reduce.is_constructor(reduce.hd_get(ctx.e))) {
        reduce.hd_set(ctx.e, reduce.ap(reduce.hd_get(reduce.hd_get(ctx.e)), reduce.tl_get(reduce.hd_get(ctx.e))));
        reduce.downLeft(ctx);
    }
    reduce.hd_set(ctx.e, arg2);
    ctx.action = word.ACT_NEXTREDEX;
}

/// `MATCH p v k` — match value `v` against pattern `p`, giving `k` on success or `FAIL`.
pub fn handleMATCH(ctx: *ReductionCtx) void {
    if (reduce.upleft(ctx)) {
        ctx.action = word.ACT_DONE;
        return;
    }
    ctx.args[0] = reduce.reduce(reduce.tl_get(ctx.e));
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
    const lastarg = reduce.reduce(reduce.tl_get(ctx.e));
    reduce.rewrite_to_match_result(&ctx.e, arg1, lastarg, arg2);
    ctx.action = word.ACT_NEXTREDEX;
}

/// As `MATCH`, specialised to an integer-literal pattern.
pub fn handleMATCHINT(ctx: *ReductionCtx) void {
    var arg1: Word = 0;
    var arg2: Word = 0;
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
    const lastarg = reduce.reduce(reduce.tl_get(ctx.e));
    reduce.rewrite_to_int_match_result(&ctx.e, arg1, lastarg, arg2);
    ctx.action = word.ACT_NEXTREDEX;
}

/// Arithmetic-sequence step (`[a..b]`): emit the next term and recurse, stopping past the bound.
pub fn handleGENSEQ(ctx: *ReductionCtx) void {
    var arg1: Word = 0;
    reduce.GETARG(ctx, &arg1);
    if (reduce.upleft(ctx)) {
        ctx.action = word.ACT_DONE;
        return;
    }
    const lastarg = reduce.tl_get(ctx.e);
    if (reduce.tl_get(arg1) != word.NIL and
        (if (reduce.is_ap(arg1)) reduce_rt.compare(lastarg, reduce.tl_get(arg1)) else reduce_rt.compare(reduce.tl_get(arg1), lastarg)) > 0)
    {
        reduce.rewrite_to_nil(&ctx.e);
    } else {
        const hold = reduce.ap(reduce.hd_get(ctx.e), reduce_rt.numplus(lastarg, reduce.hd_get(arg1)));
        reduce.rewrite_to_cons(ctx.e, lastarg, hold);
    }
    ctx.action = word.ACT_DONE;
}

/// `map f (x:xs) -> f x : map f xs`; `map f [] -> []`.
pub fn handleMAP(ctx: *ReductionCtx) void {
    var arg1: Word = 0;
    if (reduce.getarg(ctx, &arg1)) {
        ctx.action = word.ACT_DONE;
        return;
    }
    if (reduce.upleft(ctx)) {
        ctx.action = word.ACT_DONE;
        return;
    }
    const lastarg = reduce.reduce(reduce.tl_get(ctx.e));
    if (lastarg == word.NIL) {
        reduce.rewrite_to_nil(&ctx.e);
    } else {
        const hold = reduce.ap(reduce.hd_get(ctx.e), reduce.tl_get(lastarg));
        reduce.rewrite_to_cons(ctx.e, reduce.ap(arg1, reduce.hd_get(lastarg)), hold);
    }
    ctx.action = word.ACT_DONE;
}

/// Concat-map: apply `f` to each element and append the non-`FAIL`/non-`[]` results.
pub fn handleFLATMAP(ctx: *ReductionCtx) void {
    var arg1: Word = 0;
    var arg2: Word = 0;
    if (reduce.getarg(ctx, &arg1)) {
        ctx.action = word.ACT_DONE;
        return;
    }
    if (reduce.getarg(ctx, &arg2)) {
        ctx.action = word.ACT_DONE;
        return;
    }
    while (true) {
        arg2 = reduce.reduce(arg2);
        if (arg2 == word.NIL) {
            reduce.rewrite_to_nil(&ctx.e);
            ctx.action = word.ACT_DONE;
            return;
        }
        const hold = reduce.reduce(reduce.ap(arg1, reduce.hd_get(arg2)));
        if (hold == word.FAIL or hold == word.NIL) {
            arg2 = reduce.tl_get(arg2);
            continue;
        }
        reduce.tl_set(ctx.e, reduce.ap(reduce.hd_get(ctx.e), reduce.tl_get(arg2)));
        reduce.hd_set(ctx.e, reduce.ap(word.APPEND, hold));
        ctx.action = word.ACT_NEXTREDEX;
        return;
    }
}

/// `filter p xs` — skip leading elements failing predicate `p`, then emit the next survivor lazily.
pub fn handleFILTER(ctx: *ReductionCtx) void {
    var arg1: Word = 0;
    if (reduce.getarg(ctx, &arg1)) {
        ctx.action = word.ACT_DONE;
        return;
    }
    if (reduce.upleft(ctx)) {
        ctx.action = word.ACT_DONE;
        return;
    }
    var lastarg = reduce.reduce(reduce.tl_get(ctx.e));
    while (lastarg != word.NIL and reduce.reduce(reduce.ap(arg1, reduce.hd_get(lastarg))) == word.False) {
        lastarg = reduce.reduce(reduce.tl_get(lastarg));
    }
    if (lastarg == word.NIL) {
        reduce.rewrite_to_nil(&ctx.e);
    } else {
        const hold = reduce.ap(reduce.hd_get(ctx.e), reduce.tl_get(lastarg));
        reduce.rewrite_to_cons(ctx.e, reduce.hd_get(lastarg), hold);
    }
    ctx.action = word.ACT_DONE;
}

/// `last xs` — the final element of a non-empty list (errors on `[]`); shortens the spine as it walks.
pub fn handleLIST_LAST(ctx: *ReductionCtx) void {
    if (reduce.upleft(ctx)) {
        ctx.action = word.ACT_DONE;
        return;
    }
    var lastarg = reduce.reduce(reduce.tl_get(ctx.e));
    if (lastarg == word.NIL) {
        reduce_rt.fnError("last []");
    }
    while (true) {
        const next_tl = reduce.reduce(reduce.tl_get(lastarg));
        reduce.tl_set(lastarg, next_tl);
        if (next_tl == word.NIL) break;
        lastarg = next_tl;
    }
    reduce.rewrite_to_value(&ctx.e, reduce.hd_get(lastarg));
    ctx.action = word.ACT_NEXTREDEX;
}

/// `#xs` — the length of a list, as an `INT`.
pub fn handleLENGTH(ctx: *ReductionCtx) void {
    if (reduce.upleft(ctx)) {
        ctx.action = word.ACT_DONE;
        return;
    }
    var n: i64 = 0;
    var lastarg = reduce.tl_get(ctx.e);
    while (true) {
        lastarg = reduce.reduce(lastarg);
        if (lastarg == word.NIL) break;
        lastarg = reduce.tl_get(lastarg);
        n += 1;
    }
    reduce.simpl(ctx, big.fromInt(n));
    ctx.action = word.ACT_DONE;
}

/// `drop n xs` — discard the first `n` elements (clamping at `[]`).
pub fn handleDROP(ctx: *ReductionCtx) void {
    var arg1: Word = 0;
    if (reduce.getarg(ctx, &arg1)) {
        ctx.action = word.ACT_DONE;
        return;
    }
    if (reduce.upleft(ctx)) {
        ctx.action = word.ACT_DONE;
        return;
    }
    arg1 = reduce.reduce(reduce.tl_get(reduce.hd_get(ctx.e)));
    reduce.tl_set(reduce.hd_get(ctx.e), arg1);
    if (!reduce.is_int(arg1)) {
        reduce_rt.intError("drop");
    }
    var n = big.toInt(arg1);
    var lastarg = reduce.tl_get(ctx.e);
    while (n > 0) : (n -= 1) {
        lastarg = reduce.reduce(lastarg);
        if (lastarg == word.NIL) {
            reduce.rewrite_to_nil(&ctx.e);
            ctx.action = word.ACT_DONE;
            return;
        } else {
            lastarg = reduce.tl_get(lastarg);
        }
    }
    reduce.rewrite_to_value(&ctx.e, lastarg);
    ctx.action = word.ACT_NEXTREDEX;
}

/// `xs ! n` — the n-th element (0-based); raises a subscript error if out of range.
pub fn handleSUBSCRIPT(ctx: *ReductionCtx) void {
    if (reduce.upleft(ctx)) {
        ctx.action = word.ACT_DONE;
        return;
    }
    if (reduce.upleft(ctx)) {
        ctx.action = word.ACT_DONE;
        return;
    }
    const arg1 = reduce.reduce(reduce.tl_get(reduce.hd_get(ctx.e)));
    reduce.tl_set(reduce.hd_get(ctx.e), arg1);
    var lastarg = reduce.reduce(reduce.tl_get(ctx.e));
    if (lastarg == word.NIL) {
        reduce_rt.subsError();
    }
    var indx: i64 = 0;
    if (reduce.is_atom(arg1)) {
        indx = arg1;
    } else if (reduce.is_int(arg1)) {
        indx = big.toInt(arg1);
    } else {
        reduce_rt.intError("!");
    }
    if (indx < 0) {
        reduce_rt.subsError();
    }
    while (indx > 0) {
        const next_tl = reduce.reduce(reduce.tl_get(lastarg));
        reduce.tl_set(lastarg, next_tl);
        lastarg = next_tl;
        if (lastarg == word.NIL) {
            reduce_rt.subsError();
        }
        indx -= 1;
    }
    reduce.rewrite_to_value(&ctx.e, reduce.hd_get(lastarg));
    ctx.action = word.ACT_NEXTREDEX;
}

/// `foldl1 f (x:xs) -> foldl f x xs` (errors on `[]`).
pub fn handleFOLDL1(ctx: *ReductionCtx) void {
    var arg1: Word = 0;
    if (reduce.getarg(ctx, &arg1)) {
        ctx.action = word.ACT_DONE;
        return;
    }
    if (reduce.upleft(ctx)) {
        ctx.action = word.ACT_DONE;
        return;
    }
    const lastarg = reduce.reduce(reduce.tl_get(ctx.e));
    if (lastarg != word.NIL) {
        reduce.hd_set(ctx.e, reduce.ap2(word.FOLDL, arg1, reduce.hd_get(lastarg)));
        reduce.tl_set(ctx.e, reduce.tl_get(lastarg));
        ctx.action = word.ACT_NEXTREDEX;
    } else {
        reduce_rt.fnError("foldl1 applied to []");
    }
}

/// `foldl f a xs` — strict left fold.
pub fn handleFOLDL(ctx: *ReductionCtx) void {
    var arg1: Word = 0;
    var arg2: Word = 0;
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
    var lastarg = reduce.tl_get(ctx.e);
    while (true) {
        lastarg = reduce.reduce(lastarg);
        if (lastarg == word.NIL) break;
        arg2 = reduce.reduce(reduce.ap2(arg1, arg2, reduce.hd_get(lastarg)));
        lastarg = reduce.tl_get(lastarg);
    }
    reduce.rewrite_to_value(&ctx.e, arg2);
    ctx.action = word.ACT_NEXTREDEX;
}

/// `foldr f a (x:xs) -> f x (foldr f a xs)`; `foldr f a [] -> a`.
pub fn handleFOLDR(ctx: *ReductionCtx) void {
    var arg1: Word = 0;
    var arg2: Word = 0;
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
    const lastarg = reduce.reduce(reduce.tl_get(ctx.e));
    if (lastarg == word.NIL) {
        reduce.rewrite_to_value(&ctx.e, arg2);
    } else {
        const hold = reduce.ap(reduce.hd_get(ctx.e), reduce.tl_get(lastarg));
        reduce.hd_set(ctx.e, reduce.ap(arg1, reduce.hd_get(lastarg)));
        reduce.tl_set(ctx.e, hold);
    }
    ctx.action = word.ACT_NEXTREDEX;
}

/// Raise the "no matching case" runtime error for the offending value.
pub fn handleBADCASE(ctx: *ReductionCtx) void {
    if (reduce.upleft(ctx)) {
        ctx.action = word.ACT_DONE;
        return;
    }
    const lastarg = reduce.tl_get(ctx.e);
    reduce.badcaseError(lastarg);
}

/// Yield the program's command-line arguments as a Miranda list (`conv_args`).
pub fn handleGETARGS(ctx: *ReductionCtx) void {
    if (reduce.upleft(ctx)) {
        ctx.action = word.ACT_DONE;
        return;
    }
    reduce.simpl(ctx, reduce.conv_args());
    ctx.action = word.ACT_DONE;
}

/// Raise the conformality (pattern-conflict) runtime error.
pub fn handleCONFERROR(ctx: *ReductionCtx) void {
    if (reduce.upleft(ctx)) {
        ctx.action = word.ACT_DONE;
        return;
    }
    const lastarg = reduce.tl_get(ctx.e);
    reduce.confError(lastarg);
}

/// `error s` — print the message and abort the program (guarding against repeated errors).
pub fn handleERROR(ctx: *ReductionCtx) void {
    if (reduce.upleft(ctx)) {
        ctx.action = word.ACT_DONE;
        return;
    }
    const lastarg = reduce.tl_get(ctx.e);
    if (reduce_rt.ev.errtrap != 0) {
        word.printErr("\n(repeated error)\n", .{});
    } else {
        reduce_rt.ev.errtrap = 1;
        word.printErr("\nprogram error: ", .{});
        reduce_rt.ev.s_out = reduce.getStderr();
        reduce.print(lastarg);
        _ = word.putc('\n', reduce.getStderr().?);
    }
    reduce_rt.outstats();
    main_clib.exit(1);
}

/// POSIX `WEXITSTATUS`: the low-byte exit code from a child's wait status.
fn WEXITSTATUS(status: c_int) c_int {
    return (status >> 8) & 0xff;
}

/// `wait pid` — reap child `pid` (consulting the pending-children list) and yield its exit status.
pub fn handleWAIT(ctx: *ReductionCtx) void {
    if (reduce.upleft(ctx)) {
        ctx.action = word.ACT_DONE;
        return;
    }
    const lastarg = reduce.tl_get(ctx.e);
    var hold: Word = 0;
    var w: *Word = &reduce_rt.ev.waiting;
    while (w.* != word.NIL and reduce.hd_get(w.*) != lastarg) {
        w = reduce.tl_ptr(reduce.tl_get(w.*));
    }
    if (w.* != word.NIL) {
        hold = reduce.hd_get(reduce.tl_get(w.*));
        w.* = reduce.tl_get(reduce.tl_get(w.*));
    } else {
        var status: c_int = 0;
        while (true) {
            const res = main_clib.wait(&status);
            if (res == lastarg or res == -1) {
                hold = res;
                break;
            }
            reduce_rt.ev.waiting = reduce.cons(res, reduce.cons(@intCast(WEXITSTATUS(status)), reduce_rt.ev.waiting));
        }
        if (hold != -1) {
            hold = WEXITSTATUS(status);
        }
    }
    reduce.simpl(ctx, heap.stosmallint(hold));
    ctx.action = word.ACT_DONE;
}

/// Alternation: evaluate the first alternative, falling back to the second on `FAIL` — backtracking across multi-equation definitions.
pub fn handleTRY(ctx: *ReductionCtx) void {
    var arg1: Word = 0;
    var arg2: Word = 0;
    if (reduce.getarg(ctx, &arg1)) {
        ctx.action = word.ACT_DONE;
        return;
    }
    if (reduce.getarg(ctx, &arg2)) {
        ctx.action = word.ACT_DONE;
        return;
    }
    while (!reduce.abnormal(ctx.s)) {
        if (reduce.upleft(ctx)) {
            ctx.action = word.ACT_DONE;
            return;
        }
        const lastarg = reduce.tl_get(ctx.e);
        arg1 = reduce.ap(arg1, lastarg);
        reduce.hd_set(ctx.e, reduce.ap(word.TRY, arg1));
        arg2 = reduce.ap(arg2, lastarg);
        reduce.tl_set(ctx.e, arg2);
    }
    reduce.downLeft(ctx);
    const old_e = ctx.s;
    const old_hd_e = ctx.e;
    ctx.e = reduce.tl_get(old_hd_e);
    reduce.tl_set(old_hd_e, old_e);
    ctx.s = old_hd_e | word.tlptrbit;
    ctx.action = word.ACT_NEXTREDEX;
}

/// Propagate `FAIL` up the spine, collapsing pending alternatives until a `TRY` catches it.
pub fn handleFAIL(ctx: *ReductionCtx) void {
    while (!reduce.abnormal(ctx.s)) {
        ctx.hold = ctx.s;
        ctx.s = reduce.hd_get(ctx.s);
        reduce.hd_set(ctx.hold, word.FAIL);
        reduce.tl_set(ctx.hold, 0);
    }
    ctx.action = word.ACT_DONE;
}

/// Render a constructor application as text for `show`: the constructor name plus space-separated, parenthesised arguments.
pub fn handleUsh1(ctx: *ReductionCtx) void {
    var arg1: Word = 0;
    var arg2: Word = 0;
    var arg3: Word = 0;
    if (reduce.getarg(ctx, &arg1)) {
        ctx.action = word.ACT_DONE;
        return;
    }
    arg1 = reduce.reduce(arg1);
    if (reduce.getarg(ctx, &arg2)) {
        ctx.action = word.ACT_DONE;
        return;
    }
    arg2 = reduce.reduce(arg2);
    if (reduce.getarg(ctx, &arg3)) {
        ctx.action = word.ACT_DONE;
        return;
    }
    if (reduce.is_constructor(arg1)) {
        if (reduce.suppressed(arg1)) {
            reduce.rewrite_to_string(&ctx.e, "<unprintable>");
        } else {
            reduce.rewrite_to_string(&ctx.e, reduce.constr_name(arg1));
        }
        ctx.action = word.ACT_DONE;
        return;
    }
    var hold = if (arg2 != 0) reduce.cons(')', word.NIL) else word.NIL;
    while (!reduce.is_constructor(arg1)) {
        hold = reduce.cons(' ', reduce.ap2(word.APPEND, reduce.ap(reduce.tl_get(arg1), reduce.ap(word.LAST, arg3)), hold));
        arg1 = reduce.hd_get(arg1);
        arg3 = reduce.ap(word.BODY, arg3);
    }
    if (reduce.suppressed(arg1)) {
        reduce.rewrite_to_string(&ctx.e, "<unprintable>");
        ctx.action = word.ACT_DONE;
        return;
    }
    hold = reduce.ap2(word.APPEND, lex.str_conv(reduce.constr_name(arg1)), hold);
    if (arg2 != 0) {
        reduce.rewrite_to_cons(ctx.e, '(', hold);
        ctx.action = word.ACT_DONE;
    } else {
        reduce.rewrite_to_value(&ctx.e, hold);
        ctx.action = word.ACT_NEXTREDEX;
    }
}

/// `mkstrict n f` — force the first `n` arguments before applying `f` (a strictness annotation).
pub fn handleMKSTRICT(ctx: *ReductionCtx) void {
    var arg1: Word = 0;
    var arg2: Word = 0;
    reduce.GETARG(ctx, &arg1);
    if (reduce.getarg(ctx, &arg2)) {
        ctx.action = word.ACT_DONE;
        return;
    }
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
    var lastarg = reduce.tl_get(ctx.e);
    lastarg = reduce.reduce(lastarg);
    while (arg1 > 1) {
        reduce.hd_set(ctx.e, reduce.ap(reduce.hd_get(reduce.hd_get(ctx.e)), reduce.tl_get(reduce.hd_get(ctx.e))));
        reduce.downLeft(ctx);
        arg1 -= 1;
    }
    reduce.hd_set(ctx.e, arg2);
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
