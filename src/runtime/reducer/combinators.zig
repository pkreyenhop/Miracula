const std = @import("std");
const word = @import("../word.zig");
const reduce = @import("reduce_core.zig");
const ReductionCtx = reduce.ReductionCtx;
const Word = reduce.Word;
const abi = reduce.abi;

extern var tl: [*]Word;

pub fn handleI(ctx: *ReductionCtx) void {
    if (reduce.downright(ctx)) {
        ctx.action = word.ACT_DONE;
        return;
    }
    ctx.action = word.ACT_NEXTREDEX;
}

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
        const hold = abi.bigsub(lastarg, arg1);
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

pub fn handleGENSEQ(ctx: *ReductionCtx) void {
    var arg1: Word = 0;
    reduce.GETARG(ctx, &arg1);
    if (reduce.upleft(ctx)) {
        ctx.action = word.ACT_DONE;
        return;
    }
    const lastarg = reduce.tl_get(ctx.e);
    if (reduce.tl_get(arg1) != word.NIL and
        (if (reduce.is_ap(arg1)) abi.compare(lastarg, reduce.tl_get(arg1)) else abi.compare(reduce.tl_get(arg1), lastarg)) > 0)
    {
        reduce.rewrite_to_nil(&ctx.e);
    } else {
        const hold = reduce.ap(reduce.hd_get(ctx.e), abi.numplus(lastarg, reduce.hd_get(arg1)));
        reduce.rewrite_to_cons(ctx.e, lastarg, hold);
    }
    ctx.action = word.ACT_DONE;
}

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

pub fn handleLIST_LAST(ctx: *ReductionCtx) void {
    if (reduce.upleft(ctx)) {
        ctx.action = word.ACT_DONE;
        return;
    }
    var lastarg = reduce.reduce(reduce.tl_get(ctx.e));
    if (lastarg == word.NIL) {
        abi.fn_error("last []");
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
    reduce.simpl(ctx, abi.sto_int(n));
    ctx.action = word.ACT_DONE;
}

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
        abi.int_error("drop");
    }
    var n = abi.get_int(arg1);
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
        abi.subs_error();
    }
    var indx: i64 = 0;
    if (reduce.is_atom(arg1)) {
        indx = arg1;
    } else if (reduce.is_int(arg1)) {
        indx = abi.get_int(arg1);
    } else {
        abi.int_error("!");
    }
    if (indx < 0) {
        abi.subs_error();
    }
    while (indx > 0) {
        const next_tl = reduce.reduce(reduce.tl_get(lastarg));
        reduce.tl_set(lastarg, next_tl);
        lastarg = next_tl;
        if (lastarg == word.NIL) {
            abi.subs_error();
        }
        indx -= 1;
    }
    reduce.rewrite_to_value(&ctx.e, reduce.hd_get(lastarg));
    ctx.action = word.ACT_NEXTREDEX;
}

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
        abi.fn_error("foldl1 applied to []");
    }
}

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

pub fn handleBADCASE(ctx: *ReductionCtx) void {
    if (reduce.upleft(ctx)) {
        ctx.action = word.ACT_DONE;
        return;
    }
    const lastarg = reduce.tl_get(ctx.e);
    reduce.reduce_badcase_error(lastarg);
}

pub fn handleGETARGS(ctx: *ReductionCtx) void {
    if (reduce.upleft(ctx)) {
        ctx.action = word.ACT_DONE;
        return;
    }
    reduce.simpl(ctx, reduce.conv_args());
    ctx.action = word.ACT_DONE;
}

pub fn handleCONFERROR(ctx: *ReductionCtx) void {
    if (reduce.upleft(ctx)) {
        ctx.action = word.ACT_DONE;
        return;
    }
    const lastarg = reduce.tl_get(ctx.e);
    reduce.reduce_conf_error(lastarg);
}

pub fn handleERROR(ctx: *ReductionCtx) void {
    if (reduce.upleft(ctx)) {
        ctx.action = word.ACT_DONE;
        return;
    }
    const lastarg = reduce.tl_get(ctx.e);
    if (reduce.errtrap != 0) {
        word.printErr("\n(repeated error)\n", .{});
    } else {
        reduce.errtrap = 1;
        word.printErr("\nprogram error: ", .{});
        reduce.s_out = reduce.getStderr();
        reduce.print(lastarg);
        _ = word.putc('\n', reduce.getStderr().?);
    }
    abi.outstats();
    abi.exit(1);
}

fn WEXITSTATUS(status: c_int) c_int {
    return (status >> 8) & 0xff;
}

pub fn handleWAIT(ctx: *ReductionCtx) void {
    if (reduce.upleft(ctx)) {
        ctx.action = word.ACT_DONE;
        return;
    }
    const lastarg = reduce.tl_get(ctx.e);
    var hold: Word = 0;
    var w: *Word = &reduce.waiting;
    while (w.* != word.NIL and reduce.hd_get(w.*) != lastarg) {
        w = &tl[reduce.clean_ptr(reduce.tl_get(w.*)) * 2];
    }
    if (w.* != word.NIL) {
        hold = reduce.hd_get(reduce.tl_get(w.*));
        w.* = reduce.tl_get(reduce.tl_get(w.*));
    } else {
        var status: c_int = 0;
        while (true) {
            const res = abi.wait(&status);
            if (res == lastarg or res == -1) {
                hold = res;
                break;
            }
            reduce.waiting = reduce.cons(res, reduce.cons(@intCast(WEXITSTATUS(status)), reduce.waiting));
        }
        if (hold != -1) {
            hold = WEXITSTATUS(status);
        }
    }
    reduce.simpl(ctx, abi.stosmallint(hold));
    ctx.action = word.ACT_DONE;
}

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
    ctx.s = old_hd_e | abi.tlptrbit;
    ctx.action = word.ACT_NEXTREDEX;
}

pub fn handleFAIL(ctx: *ReductionCtx) void {
    while (!reduce.abnormal(ctx.s)) {
        ctx.hold = ctx.s;
        ctx.s = reduce.hd_get(ctx.s);
        reduce.hd_set(ctx.hold, word.FAIL);
        reduce.tl_set(ctx.hold, 0);
    }
    ctx.action = word.ACT_DONE;
}

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
    hold = reduce.ap2(word.APPEND, abi.str_conv(reduce.constr_name(arg1)), hold);
    if (arg2 != 0) {
        reduce.rewrite_to_cons(ctx.e, '(', hold);
        ctx.action = word.ACT_DONE;
    } else {
        reduce.rewrite_to_value(&ctx.e, hold);
        ctx.action = word.ACT_NEXTREDEX;
    }
}

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

pub fn handle_strict_monadic(ctx: *ReductionCtx) void {
    if (reduce.downright(ctx)) {
        ctx.action = word.ACT_DONE;
        return;
    }
    ctx.action = word.ACT_NEXTREDEX;
}

pub fn handle_strict_diadic(ctx: *ReductionCtx) void {
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

pub fn handle_strict_triadic(ctx: *ReductionCtx) void {
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
