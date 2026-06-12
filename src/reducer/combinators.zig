const std = @import("std");
const reduce = @import("reduce.zig");
const ReductionCtx = reduce.ReductionCtx;
const Word = reduce.Word;
const clib = reduce.clib;

extern var tl: [*]Word;

export fn zig_handleI(ctx: *ReductionCtx) void {
    if (reduce.downright(ctx)) {
        ctx.action = clib.ACT_DONE;
        return;
    }
    ctx.action = clib.ACT_NEXTREDEX;
}

export fn zig_handleK(ctx: *ReductionCtx) void {
    var arg1: Word = 0;
    if (reduce.getarg(ctx, &arg1)) {
        ctx.action = clib.ACT_DONE;
        return;
    }
    if (reduce.upleft(ctx)) {
        ctx.action = clib.ACT_DONE;
        return;
    }
    reduce.rewrite_to_value(&ctx.e, arg1);
    ctx.action = clib.ACT_NEXTREDEX;
}

export fn zig_handleS(ctx: *ReductionCtx) void {
    var arg1: Word = 0;
    var arg2: Word = 0;
    if (reduce.getarg(ctx, &arg1)) { ctx.action = clib.ACT_DONE; return; }
    if (reduce.getarg(ctx, &arg2)) { ctx.action = clib.ACT_DONE; return; }
    if (reduce.upleft(ctx)) { ctx.action = clib.ACT_DONE; return; }
    const lastarg = reduce.tl_get(ctx.e);
    reduce.hd_set(ctx.e, reduce.ap(arg1, lastarg));
    reduce.tl_set(ctx.e, reduce.ap(arg2, lastarg));
    reduce.downLeft(ctx);
    reduce.downLeft(ctx);
    ctx.action = clib.ACT_NEXTREDEX;
}

export fn zig_handleB(ctx: *ReductionCtx) void {
    var arg1: Word = 0;
    var arg2: Word = 0;
    if (reduce.getarg(ctx, &arg1)) { ctx.action = clib.ACT_DONE; return; }
    if (reduce.getarg(ctx, &arg2)) { ctx.action = clib.ACT_DONE; return; }
    if (reduce.upleft(ctx)) { ctx.action = clib.ACT_DONE; return; }
    const lastarg = reduce.tl_get(ctx.e);
    reduce.hd_set(ctx.e, arg1);
    reduce.tl_set(ctx.e, reduce.ap(arg2, lastarg));
    reduce.downLeft(ctx);
    ctx.action = clib.ACT_NEXTREDEX;
}

export fn zig_handleCB(ctx: *ReductionCtx) void {
    var arg1: Word = 0;
    var arg2: Word = 0;
    if (reduce.getarg(ctx, &arg1)) { ctx.action = clib.ACT_DONE; return; }
    if (reduce.getarg(ctx, &arg2)) { ctx.action = clib.ACT_DONE; return; }
    if (reduce.upleft(ctx)) { ctx.action = clib.ACT_DONE; return; }
    const lastarg = reduce.tl_get(ctx.e);
    reduce.hd_set(ctx.e, arg2);
    reduce.tl_set(ctx.e, reduce.ap(arg1, lastarg));
    reduce.downLeft(ctx);
    ctx.action = clib.ACT_NEXTREDEX;
}

export fn zig_handleC(ctx: *ReductionCtx) void {
    var arg1: Word = 0;
    var arg2: Word = 0;
    if (reduce.getarg(ctx, &arg1)) { ctx.action = clib.ACT_DONE; return; }
    if (reduce.getarg(ctx, &arg2)) { ctx.action = clib.ACT_DONE; return; }
    if (reduce.upleft(ctx)) { ctx.action = clib.ACT_DONE; return; }
    const lastarg = reduce.tl_get(ctx.e);
    reduce.hd_set(ctx.e, reduce.ap(arg1, lastarg));
    reduce.tl_set(ctx.e, arg2);
    reduce.downLeft(ctx);
    reduce.downLeft(ctx);
    ctx.action = clib.ACT_NEXTREDEX;
}

export fn zig_handleY(ctx: *ReductionCtx) void {
    if (reduce.upleft(ctx)) { ctx.action = clib.ACT_DONE; return; }
    reduce.hd_set(ctx.e, reduce.tl_get(ctx.e));
    reduce.tl_set(ctx.e, ctx.e);
    reduce.downLeft(ctx);
    ctx.action = clib.ACT_NEXTREDEX;
}

export fn zig_handleKI(ctx: *ReductionCtx) void {
    if (reduce.upleft(ctx)) { ctx.action = clib.ACT_DONE; return; }
    if (reduce.upleft(ctx)) { ctx.action = clib.ACT_DONE; return; }
    ctx.e = reduce.rewrite_to_existing_tail(ctx.e);
    ctx.action = clib.ACT_NEXTREDEX;
}

export fn zig_handleS1(ctx: *ReductionCtx) void {
    var arg1: Word = 0;
    var arg2: Word = 0;
    var arg3: Word = 0;
    if (reduce.getarg(ctx, &arg1)) { ctx.action = clib.ACT_DONE; return; }
    if (reduce.getarg(ctx, &arg2)) { ctx.action = clib.ACT_DONE; return; }
    if (reduce.getarg(ctx, &arg3)) { ctx.action = clib.ACT_DONE; return; }
    if (reduce.upleft(ctx)) { ctx.action = clib.ACT_DONE; return; }
    const lastarg = reduce.tl_get(ctx.e);
    reduce.hd_set(ctx.e, reduce.ap(arg2, lastarg));
    reduce.hd_set(ctx.e, reduce.ap(arg1, reduce.hd_get(ctx.e)));
    reduce.tl_set(ctx.e, reduce.ap(arg3, lastarg));
    reduce.downLeft(ctx);
    reduce.downLeft(ctx);
    ctx.action = clib.ACT_NEXTREDEX;
}

export fn zig_handleB1(ctx: *ReductionCtx) void {
    var arg1: Word = 0;
    var arg2: Word = 0;
    var arg3: Word = 0;
    if (reduce.getarg(ctx, &arg1)) { ctx.action = clib.ACT_DONE; return; }
    if (reduce.getarg(ctx, &arg2)) { ctx.action = clib.ACT_DONE; return; }
    if (reduce.getarg(ctx, &arg3)) { ctx.action = clib.ACT_DONE; return; }
    if (reduce.upleft(ctx)) { ctx.action = clib.ACT_DONE; return; }
    const lastarg = reduce.tl_get(ctx.e);
    reduce.hd_set(ctx.e, arg1);
    reduce.tl_set(ctx.e, reduce.ap(arg3, lastarg));
    reduce.tl_set(ctx.e, reduce.ap(arg2, reduce.tl_get(ctx.e)));
    reduce.downLeft(ctx);
    ctx.action = clib.ACT_NEXTREDEX;
}

export fn zig_handleC1(ctx: *ReductionCtx) void {
    var arg1: Word = 0;
    var arg2: Word = 0;
    var arg3: Word = 0;
    if (reduce.getarg(ctx, &arg1)) { ctx.action = clib.ACT_DONE; return; }
    if (reduce.getarg(ctx, &arg2)) { ctx.action = clib.ACT_DONE; return; }
    if (reduce.getarg(ctx, &arg3)) { ctx.action = clib.ACT_DONE; return; }
    if (reduce.upleft(ctx)) { ctx.action = clib.ACT_DONE; return; }
    const lastarg = reduce.tl_get(ctx.e);
    reduce.hd_set(ctx.e, reduce.ap(arg2, lastarg));
    reduce.hd_set(ctx.e, reduce.ap(arg1, reduce.hd_get(ctx.e)));
    reduce.tl_set(ctx.e, arg3);
    reduce.downLeft(ctx);
    ctx.action = clib.ACT_NEXTREDEX;
}

export fn zig_handleS_p(ctx: *ReductionCtx) void {
    var arg1: Word = 0;
    var arg2: Word = 0;
    if (reduce.getarg(ctx, &arg1)) { ctx.action = clib.ACT_DONE; return; }
    if (reduce.getarg(ctx, &arg2)) { ctx.action = clib.ACT_DONE; return; }
    if (reduce.upleft(ctx)) { ctx.action = clib.ACT_DONE; return; }
    const lastarg = reduce.tl_get(ctx.e);
    reduce.rewrite_to_cons(ctx.e, reduce.ap(arg1, lastarg), reduce.ap(arg2, lastarg));
    ctx.action = clib.ACT_DONE;
}

export fn zig_handleB_p(ctx: *ReductionCtx) void {
    var arg1: Word = 0;
    var arg2: Word = 0;
    if (reduce.getarg(ctx, &arg1)) { ctx.action = clib.ACT_DONE; return; }
    if (reduce.getarg(ctx, &arg2)) { ctx.action = clib.ACT_DONE; return; }
    if (reduce.upleft(ctx)) { ctx.action = clib.ACT_DONE; return; }
    const lastarg = reduce.tl_get(ctx.e);
    reduce.rewrite_to_cons(ctx.e, arg1, reduce.ap(arg2, lastarg));
    ctx.action = clib.ACT_DONE;
}

export fn zig_handleC_p(ctx: *ReductionCtx) void {
    var arg1: Word = 0;
    var arg2: Word = 0;
    if (reduce.getarg(ctx, &arg1)) { ctx.action = clib.ACT_DONE; return; }
    if (reduce.getarg(ctx, &arg2)) { ctx.action = clib.ACT_DONE; return; }
    if (reduce.upleft(ctx)) { ctx.action = clib.ACT_DONE; return; }
    const lastarg = reduce.tl_get(ctx.e);
    reduce.rewrite_to_cons(ctx.e, reduce.ap(arg1, lastarg), arg2);
    ctx.action = clib.ACT_DONE;
}

export fn zig_handleITERATE(ctx: *ReductionCtx) void {
    var arg1: Word = 0;
    if (reduce.getarg(ctx, &arg1)) { ctx.action = clib.ACT_DONE; return; }
    if (reduce.upleft(ctx)) { ctx.action = clib.ACT_DONE; return; }
    const lastarg = reduce.tl_get(ctx.e);
    const hold = reduce.ap(reduce.hd_get(ctx.e), reduce.ap(arg1, lastarg));
    reduce.rewrite_to_cons(ctx.e, lastarg, hold);
    ctx.action = clib.ACT_DONE;
}

export fn zig_handleITERATE1(ctx: *ReductionCtx) void {
    var arg1: Word = 0;
    if (reduce.getarg(ctx, &arg1)) { ctx.action = clib.ACT_DONE; return; }
    if (reduce.upleft(ctx)) { ctx.action = clib.ACT_DONE; return; }
    var lastarg = reduce.tl_get(ctx.e);
    lastarg = reduce.reduce(lastarg);
    if (lastarg == clib.FAIL) {
        reduce.rewrite_to_nil(&ctx.e);
    } else {
        const hold = reduce.ap(reduce.hd_get(ctx.e), reduce.ap(arg1, lastarg));
        reduce.rewrite_to_cons(ctx.e, lastarg, hold);
    }
    ctx.action = clib.ACT_DONE;
}

export fn zig_handleP(ctx: *ReductionCtx) void {
    var arg1: Word = 0;
    if (reduce.getarg(ctx, &arg1)) { ctx.action = clib.ACT_DONE; return; }
    if (reduce.upleft(ctx)) { ctx.action = clib.ACT_DONE; return; }
    const lastarg = reduce.tl_get(ctx.e);
    reduce.rewrite_to_cons(ctx.e, arg1, lastarg);
    ctx.action = clib.ACT_DONE;
}

export fn zig_handleU(ctx: *ReductionCtx) void {
    var arg1: Word = 0;
    if (reduce.getarg(ctx, &arg1)) { ctx.action = clib.ACT_DONE; return; }
    if (reduce.upleft(ctx)) { ctx.action = clib.ACT_DONE; return; }
    const lastarg = reduce.tl_get(ctx.e);
    reduce.hd_set(ctx.e, reduce.ap(arg1, reduce.ap(clib.HD, lastarg)));
    reduce.tl_set(ctx.e, reduce.ap(clib.TL, lastarg));
    reduce.downLeft(ctx);
    reduce.downLeft(ctx);
    ctx.action = clib.ACT_NEXTREDEX;
}

export fn zig_handleUf(ctx: *ReductionCtx) void {
    var arg1: Word = 0;
    if (reduce.getarg(ctx, &arg1)) { ctx.action = clib.ACT_DONE; return; }
    if (reduce.upleft(ctx)) { ctx.action = clib.ACT_DONE; return; }
    const lastarg = reduce.tl_get(ctx.e);
    if (reduce.is_constructor(reduce.head(lastarg))) {
        reduce.hd_set(ctx.e, reduce.ap(arg1, reduce.hd_get(lastarg)));
        reduce.tl_set(ctx.e, reduce.tl_get(lastarg));
    } else {
        reduce.hd_set(ctx.e, reduce.ap(arg1, reduce.ap(clib.BODY, lastarg)));
        reduce.tl_set(ctx.e, reduce.ap(clib.LAST, lastarg));
    }
    reduce.downLeft(ctx);
    reduce.downLeft(ctx);
    ctx.action = clib.ACT_NEXTREDEX;
}

export fn zig_handleATLEAST(ctx: *ReductionCtx) void {
    var arg1: Word = 0;
    var arg2: Word = 0;
    if (reduce.getarg(ctx, &arg1)) { ctx.action = clib.ACT_DONE; return; }
    if (reduce.getarg(ctx, &arg2)) { ctx.action = clib.ACT_DONE; return; }
    if (reduce.upleft(ctx)) { ctx.action = clib.ACT_DONE; return; }
    var lastarg = reduce.tl_get(ctx.e);
    lastarg = reduce.reduce(lastarg);
    if (reduce.is_int(lastarg)) {
        const hold = clib.bigsub(lastarg, arg1);
        if (reduce.poz(hold)) {
            reduce.hd_set(ctx.e, arg2);
            reduce.tl_set(ctx.e, hold);
        } else {
            reduce.rewrite_to_fail(&ctx.e);
        }
    } else {
        reduce.rewrite_to_fail(&ctx.e);
    }
    ctx.action = clib.ACT_NEXTREDEX;
}

export fn zig_handleU_(ctx: *ReductionCtx) void {
    var arg1: Word = 0;
    if (reduce.getarg(ctx, &arg1)) { ctx.action = clib.ACT_DONE; return; }
    if (reduce.upleft(ctx)) { ctx.action = clib.ACT_DONE; return; }
    var lastarg = reduce.tl_get(ctx.e);
    lastarg = reduce.reduce(lastarg);
    if (lastarg == clib.NIL) {
        reduce.rewrite_to_fail(&ctx.e);
        ctx.action = clib.ACT_NEXTREDEX;
        return;
    }
    reduce.hd_set(ctx.e, reduce.ap(arg1, reduce.hd_get(lastarg)));
    reduce.tl_set(ctx.e, reduce.tl_get(lastarg));
    ctx.action = clib.ACT_NEXTREDEX;
}

export fn zig_handleUg(ctx: *ReductionCtx) void {
    var arg1: Word = 0;
    var arg2: Word = 0;
    if (reduce.getarg(ctx, &arg1)) { ctx.action = clib.ACT_DONE; return; }
    if (reduce.getarg(ctx, &arg2)) { ctx.action = clib.ACT_DONE; return; }
    if (reduce.upleft(ctx)) { ctx.action = clib.ACT_DONE; return; }
    var lastarg = reduce.tl_get(ctx.e);
    lastarg = reduce.reduce(lastarg);
    if (reduce.hd_get(arg1) != reduce.hd_get(reduce.head(lastarg))) {
        reduce.rewrite_to_fail(&ctx.e);
        ctx.action = clib.ACT_NEXTREDEX;
        return;
    }
    if (reduce.is_constructor(lastarg)) {
        reduce.rewrite_to_value(&ctx.e, arg2);
        ctx.action = clib.ACT_NEXTREDEX;
        return;
    }
    reduce.hd_set(ctx.e, reduce.hd_get(lastarg));
    reduce.tl_set(ctx.e, reduce.tl_get(lastarg));
    while (!reduce.is_constructor(reduce.hd_get(ctx.e))) {
        reduce.hd_set(ctx.e, reduce.ap(reduce.hd_get(reduce.hd_get(ctx.e)), reduce.tl_get(reduce.hd_get(ctx.e))));
        reduce.downLeft(ctx);
    }
    reduce.hd_set(ctx.e, arg2);
    ctx.action = clib.ACT_NEXTREDEX;
}

export fn zig_handleMATCH(ctx: *ReductionCtx) void {
    if (reduce.upleft(ctx)) { ctx.action = clib.ACT_DONE; return; }
    ctx.args[0] = reduce.reduce(reduce.tl_get(ctx.e));
    const arg1 = ctx.args[0];
    if (reduce.getarg(ctx, &ctx.args[1])) { ctx.action = clib.ACT_DONE; return; }
    const arg2 = ctx.args[1];
    if (reduce.upleft(ctx)) { ctx.action = clib.ACT_DONE; return; }
    const lastarg = reduce.reduce(reduce.tl_get(ctx.e));
    reduce.rewrite_to_match_result(&ctx.e, arg1, lastarg, arg2);
    ctx.action = clib.ACT_NEXTREDEX;
}

export fn zig_handleMATCHINT(ctx: *ReductionCtx) void {
    var arg1: Word = 0;
    var arg2: Word = 0;
    if (reduce.getarg(ctx, &arg1)) { ctx.action = clib.ACT_DONE; return; }
    if (reduce.getarg(ctx, &arg2)) { ctx.action = clib.ACT_DONE; return; }
    if (reduce.upleft(ctx)) { ctx.action = clib.ACT_DONE; return; }
    const lastarg = reduce.reduce(reduce.tl_get(ctx.e));
    reduce.rewrite_to_int_match_result(&ctx.e, arg1, lastarg, arg2);
    ctx.action = clib.ACT_NEXTREDEX;
}

export fn zig_handleGENSEQ(ctx: *ReductionCtx) void {
    var arg1: Word = 0;
    reduce.GETARG(ctx, &arg1);
    if (reduce.upleft(ctx)) { ctx.action = clib.ACT_DONE; return; }
    const lastarg = reduce.tl_get(ctx.e);
    if (reduce.tl_get(arg1) != clib.NIL and
        (if (reduce.is_ap(arg1)) clib.compare(lastarg, reduce.tl_get(arg1)) else clib.compare(reduce.tl_get(arg1), lastarg)) > 0) {
        reduce.rewrite_to_nil(&ctx.e);
    } else {
        const hold = reduce.ap(reduce.hd_get(ctx.e), clib.numplus(lastarg, reduce.hd_get(arg1)));
        reduce.rewrite_to_cons(ctx.e, lastarg, hold);
    }
    ctx.action = clib.ACT_DONE;
}

export fn zig_handleMAP(ctx: *ReductionCtx) void {
    var arg1: Word = 0;
    if (reduce.getarg(ctx, &arg1)) { ctx.action = clib.ACT_DONE; return; }
    if (reduce.upleft(ctx)) { ctx.action = clib.ACT_DONE; return; }
    const lastarg = reduce.reduce(reduce.tl_get(ctx.e));
    if (lastarg == clib.NIL) {
        reduce.rewrite_to_nil(&ctx.e);
    } else {
        const hold = reduce.ap(reduce.hd_get(ctx.e), reduce.tl_get(lastarg));
        reduce.rewrite_to_cons(ctx.e, reduce.ap(arg1, reduce.hd_get(lastarg)), hold);
    }
    ctx.action = clib.ACT_DONE;
}

export fn zig_handleFLATMAP(ctx: *ReductionCtx) void {
    var arg1: Word = 0;
    var arg2: Word = 0;
    if (reduce.getarg(ctx, &arg1)) { ctx.action = clib.ACT_DONE; return; }
    if (reduce.getarg(ctx, &arg2)) { ctx.action = clib.ACT_DONE; return; }
    while (true) {
        arg2 = reduce.reduce(arg2);
        if (arg2 == clib.NIL) {
            reduce.rewrite_to_nil(&ctx.e);
            ctx.action = clib.ACT_DONE;
            return;
        }
        const hold = reduce.reduce(reduce.ap(arg1, reduce.hd_get(arg2)));
        if (hold == clib.FAIL or hold == clib.NIL) {
            arg2 = reduce.tl_get(arg2);
            continue;
        }
        reduce.tl_set(ctx.e, reduce.ap(reduce.hd_get(ctx.e), reduce.tl_get(arg2)));
        reduce.hd_set(ctx.e, reduce.ap(clib.APPEND, hold));
        ctx.action = clib.ACT_NEXTREDEX;
        return;
    }
}

export fn zig_handleFILTER(ctx: *ReductionCtx) void {
    var arg1: Word = 0;
    if (reduce.getarg(ctx, &arg1)) { ctx.action = clib.ACT_DONE; return; }
    if (reduce.upleft(ctx)) { ctx.action = clib.ACT_DONE; return; }
    var lastarg = reduce.reduce(reduce.tl_get(ctx.e));
    while (lastarg != clib.NIL and reduce.reduce(reduce.ap(arg1, reduce.hd_get(lastarg))) == clib.False) {
        lastarg = reduce.reduce(reduce.tl_get(lastarg));
    }
    if (lastarg == clib.NIL) {
        reduce.rewrite_to_nil(&ctx.e);
    } else {
        const hold = reduce.ap(reduce.hd_get(ctx.e), reduce.tl_get(lastarg));
        reduce.rewrite_to_cons(ctx.e, reduce.hd_get(lastarg), hold);
    }
    ctx.action = clib.ACT_DONE;
}

export fn zig_handleLIST_LAST(ctx: *ReductionCtx) void {
    if (reduce.upleft(ctx)) { ctx.action = clib.ACT_DONE; return; }
    var lastarg = reduce.reduce(reduce.tl_get(ctx.e));
    if (lastarg == clib.NIL) {
        clib.fn_error("last []");
    }
    while (true) {
        const next_tl = reduce.reduce(reduce.tl_get(lastarg));
        reduce.tl_set(lastarg, next_tl);
        if (next_tl == clib.NIL) break;
        lastarg = next_tl;
    }
    reduce.rewrite_to_value(&ctx.e, reduce.hd_get(lastarg));
    ctx.action = clib.ACT_NEXTREDEX;
}

export fn zig_handleLENGTH(ctx: *ReductionCtx) void {
    if (reduce.upleft(ctx)) { ctx.action = clib.ACT_DONE; return; }
    var n: i64 = 0;
    var lastarg = reduce.tl_get(ctx.e);
    while (true) {
        lastarg = reduce.reduce(lastarg);
        if (lastarg == clib.NIL) break;
        lastarg = reduce.tl_get(lastarg);
        n += 1;
    }
    reduce.simpl(ctx, clib.sto_int(n));
    ctx.action = clib.ACT_DONE;
}

export fn zig_handleDROP(ctx: *ReductionCtx) void {
    var arg1: Word = 0;
    if (reduce.getarg(ctx, &arg1)) { ctx.action = clib.ACT_DONE; return; }
    if (reduce.upleft(ctx)) { ctx.action = clib.ACT_DONE; return; }
    arg1 = reduce.reduce(reduce.tl_get(reduce.hd_get(ctx.e)));
    reduce.tl_set(reduce.hd_get(ctx.e), arg1);
    if (!reduce.is_int(arg1)) {
        clib.int_error("drop");
    }
    var n = clib.get_int(arg1);
    var lastarg = reduce.tl_get(ctx.e);
    while (n > 0) : (n -= 1) {
        lastarg = reduce.reduce(lastarg);
        if (lastarg == clib.NIL) {
            reduce.rewrite_to_nil(&ctx.e);
            ctx.action = clib.ACT_DONE;
            return;
        } else {
            lastarg = reduce.tl_get(lastarg);
        }
    }
    reduce.rewrite_to_value(&ctx.e, lastarg);
    ctx.action = clib.ACT_NEXTREDEX;
}

export fn zig_handleSUBSCRIPT(ctx: *ReductionCtx) void {
    if (reduce.upleft(ctx)) { ctx.action = clib.ACT_DONE; return; }
    if (reduce.upleft(ctx)) { ctx.action = clib.ACT_DONE; return; }
    const arg1 = reduce.reduce(reduce.tl_get(reduce.hd_get(ctx.e)));
    reduce.tl_set(reduce.hd_get(ctx.e), arg1);
    var lastarg = reduce.reduce(reduce.tl_get(ctx.e));
    if (lastarg == clib.NIL) {
        clib.subs_error();
    }
    var indx: i64 = 0;
    if (reduce.is_atom(arg1)) {
        indx = arg1;
    } else if (reduce.is_int(arg1)) {
        indx = clib.get_int(arg1);
    } else {
        clib.int_error("!");
    }
    if (indx < 0) {
        clib.subs_error();
    }
    while (indx > 0) {
        const next_tl = reduce.reduce(reduce.tl_get(lastarg));
        reduce.tl_set(lastarg, next_tl);
        lastarg = next_tl;
        if (lastarg == clib.NIL) {
            clib.subs_error();
        }
        indx -= 1;
    }
    reduce.rewrite_to_value(&ctx.e, reduce.hd_get(lastarg));
    ctx.action = clib.ACT_NEXTREDEX;
}

export fn zig_handleFOLDL1(ctx: *ReductionCtx) void {
    var arg1: Word = 0;
    if (reduce.getarg(ctx, &arg1)) { ctx.action = clib.ACT_DONE; return; }
    if (reduce.upleft(ctx)) { ctx.action = clib.ACT_DONE; return; }
    const lastarg = reduce.reduce(reduce.tl_get(ctx.e));
    if (lastarg != clib.NIL) {
        reduce.hd_set(ctx.e, reduce.ap2(clib.FOLDL, arg1, reduce.hd_get(lastarg)));
        reduce.tl_set(ctx.e, reduce.tl_get(lastarg));
        ctx.action = clib.ACT_NEXTREDEX;
    } else {
        clib.fn_error("foldl1 applied to []");
    }
}

export fn zig_handleFOLDL(ctx: *ReductionCtx) void {
    var arg1: Word = 0;
    var arg2: Word = 0;
    if (reduce.getarg(ctx, &arg1)) { ctx.action = clib.ACT_DONE; return; }
    if (reduce.getarg(ctx, &arg2)) { ctx.action = clib.ACT_DONE; return; }
    if (reduce.upleft(ctx)) { ctx.action = clib.ACT_DONE; return; }
    var lastarg = reduce.tl_get(ctx.e);
    while (true) {
        lastarg = reduce.reduce(lastarg);
        if (lastarg == clib.NIL) break;
        arg2 = reduce.reduce(reduce.ap2(arg1, arg2, reduce.hd_get(lastarg)));
        lastarg = reduce.tl_get(lastarg);
    }
    reduce.rewrite_to_value(&ctx.e, arg2);
    ctx.action = clib.ACT_NEXTREDEX;
}

export fn zig_handleFOLDR(ctx: *ReductionCtx) void {
    var arg1: Word = 0;
    var arg2: Word = 0;
    if (reduce.getarg(ctx, &arg1)) { ctx.action = clib.ACT_DONE; return; }
    if (reduce.getarg(ctx, &arg2)) { ctx.action = clib.ACT_DONE; return; }
    if (reduce.upleft(ctx)) { ctx.action = clib.ACT_DONE; return; }
    const lastarg = reduce.reduce(reduce.tl_get(ctx.e));
    if (lastarg == clib.NIL) {
        reduce.rewrite_to_value(&ctx.e, arg2);
    } else {
        const hold = reduce.ap(reduce.hd_get(ctx.e), reduce.tl_get(lastarg));
        reduce.hd_set(ctx.e, reduce.ap(arg1, reduce.hd_get(lastarg)));
        reduce.tl_set(ctx.e, hold);
    }
    ctx.action = clib.ACT_NEXTREDEX;
}

export fn zig_handleBADCASE(ctx: *ReductionCtx) void {
    if (reduce.upleft(ctx)) { ctx.action = clib.ACT_DONE; return; }
    const lastarg = reduce.tl_get(ctx.e);
    reduce.reduce_badcase_error(lastarg);
}

export fn zig_handleGETARGS(ctx: *ReductionCtx) void {
    if (reduce.upleft(ctx)) { ctx.action = clib.ACT_DONE; return; }
    reduce.simpl(ctx, reduce.conv_args());
    ctx.action = clib.ACT_DONE;
}

export fn zig_handleCONFERROR(ctx: *ReductionCtx) void {
    if (reduce.upleft(ctx)) { ctx.action = clib.ACT_DONE; return; }
    const lastarg = reduce.tl_get(ctx.e);
    reduce.reduce_conf_error(lastarg);
}

export fn zig_handleERROR(ctx: *ReductionCtx) void {
    if (reduce.upleft(ctx)) { ctx.action = clib.ACT_DONE; return; }
    const lastarg = reduce.tl_get(ctx.e);
    if (reduce.errtrap != 0) {
        _ = clib.fprintf(reduce.getStderr().?, "\n(repeated error)\n");
    } else {
        reduce.errtrap = 1;
        _ = clib.fprintf(reduce.getStderr().?, "\nprogram error: ");
        reduce.s_out = reduce.getStderr();
        reduce.print(lastarg);
        _ = clib.putc('\n', reduce.getStderr().?);
    }
    clib.outstats();
    clib.exit(1);
}

fn WEXITSTATUS(status: c_int) c_int {
    return (status >> 8) & 0xff;
}

export fn zig_handleWAIT(ctx: *ReductionCtx) void {
    if (reduce.upleft(ctx)) { ctx.action = clib.ACT_DONE; return; }
    const lastarg = reduce.tl_get(ctx.e);
    var hold: Word = 0;
    var w: *Word = &reduce.waiting;
    while (w.* != clib.NIL and reduce.hd_get(w.*) != lastarg) {
        w = &tl[reduce.clean_ptr(reduce.tl_get(w.*)) * 2];
    }
    if (w.* != clib.NIL) {
        hold = reduce.hd_get(reduce.tl_get(w.*));
        w.* = reduce.tl_get(reduce.tl_get(w.*));
    } else {
        var status: c_int = 0;
        while (true) {
            const res = clib.wait(&status);
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
    reduce.simpl(ctx, clib.stosmallint(hold));
    ctx.action = clib.ACT_DONE;
}

export fn zig_handleTRY(ctx: *ReductionCtx) void {
    var arg1: Word = 0;
    var arg2: Word = 0;
    if (reduce.getarg(ctx, &arg1)) { ctx.action = clib.ACT_DONE; return; }
    if (reduce.getarg(ctx, &arg2)) { ctx.action = clib.ACT_DONE; return; }
    while (!reduce.abnormal(ctx.s)) {
        if (reduce.upleft(ctx)) { ctx.action = clib.ACT_DONE; return; }
        const lastarg = reduce.tl_get(ctx.e);
        arg1 = reduce.ap(arg1, lastarg);
        reduce.hd_set(ctx.e, reduce.ap(clib.TRY, arg1));
        arg2 = reduce.ap(arg2, lastarg);
        reduce.tl_set(ctx.e, arg2);
    }
    reduce.downLeft(ctx);
    ctx.hold = ctx.s;
    ctx.s = ctx.e;
    ctx.e = reduce.tl_get(ctx.e);
    reduce.tl_set(ctx.hold, ctx.s);
    ctx.s |= clib.tlptrbit;
    ctx.action = clib.ACT_NEXTREDEX;
}

export fn zig_handleFAIL(ctx: *ReductionCtx) void {
    while (!reduce.abnormal(ctx.s)) {
        ctx.hold = ctx.s;
        ctx.s = reduce.hd_get(ctx.s);
        reduce.hd_set(ctx.hold, clib.FAIL);
        reduce.tl_set(ctx.hold, 0);
    }
    ctx.action = clib.ACT_DONE;
}

export fn zig_handleUsh1(ctx: *ReductionCtx) void {
    var arg1: Word = 0;
    var arg2: Word = 0;
    var arg3: Word = 0;
    if (reduce.getarg(ctx, &arg1)) { ctx.action = clib.ACT_DONE; return; }
    arg1 = reduce.reduce(arg1);
    if (reduce.getarg(ctx, &arg2)) { ctx.action = clib.ACT_DONE; return; }
    arg2 = reduce.reduce(arg2);
    if (reduce.getarg(ctx, &arg3)) { ctx.action = clib.ACT_DONE; return; }
    if (reduce.is_constructor(arg1)) {
        if (reduce.suppressed(arg1)) {
            reduce.rewrite_to_string(&ctx.e, "<unprintable>");
        } else {
            reduce.rewrite_to_string(&ctx.e, reduce.constr_name(arg1));
        }
        ctx.action = clib.ACT_DONE;
        return;
    }
    var hold = if (arg2 != 0) reduce.cons(')', clib.NIL) else clib.NIL;
    while (!reduce.is_constructor(arg1)) {
        hold = reduce.cons(' ', reduce.ap2(clib.APPEND, reduce.ap(reduce.tl_get(arg1), reduce.ap(clib.LAST, arg3)), hold));
        arg1 = reduce.hd_get(arg1);
        arg3 = reduce.ap(clib.BODY, arg3);
    }
    if (reduce.suppressed(arg1)) {
        reduce.rewrite_to_string(&ctx.e, "<unprintable>");
        ctx.action = clib.ACT_DONE;
        return;
    }
    hold = reduce.ap2(clib.APPEND, clib.str_conv(reduce.constr_name(arg1)), hold);
    if (arg2 != 0) {
        reduce.rewrite_to_cons(ctx.e, '(', hold);
        ctx.action = clib.ACT_DONE;
    } else {
        reduce.rewrite_to_value(&ctx.e, hold);
        ctx.action = clib.ACT_NEXTREDEX;
    }
}

export fn zig_handleMKSTRICT(ctx: *ReductionCtx) void {
    var arg1: Word = 0;
    var arg2: Word = 0;
    reduce.GETARG(ctx, &arg1);
    if (reduce.getarg(ctx, &arg2)) { ctx.action = clib.ACT_DONE; return; }
    {
        var i = arg1;
        while (i > 0) {
            if (reduce.upleft(ctx)) { ctx.action = clib.ACT_DONE; return; }
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
    ctx.action = clib.ACT_NEXTREDEX;
}

export fn zig_handle_strict_monadic(ctx: *ReductionCtx) void {
    if (reduce.downright(ctx)) {
        ctx.action = clib.ACT_DONE;
        return;
    }
    ctx.action = clib.ACT_NEXTREDEX;
}

export fn zig_handle_strict_diadic(ctx: *ReductionCtx) void {
    if (reduce.upleft(ctx)) { ctx.action = clib.ACT_DONE; return; }
    if (reduce.downright(ctx)) { ctx.action = clib.ACT_DONE; return; }
    ctx.action = clib.ACT_NEXTREDEX;
}

export fn zig_handle_strict_triadic(ctx: *ReductionCtx) void {
    if (reduce.upleft(ctx)) { ctx.action = clib.ACT_DONE; return; }
    if (reduce.upleft(ctx)) { ctx.action = clib.ACT_DONE; return; }
    if (reduce.downright(ctx)) { ctx.action = clib.ACT_DONE; return; }
    ctx.action = clib.ACT_NEXTREDEX;
}
