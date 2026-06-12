const std = @import("std");
const reduce = @import("reduce.zig");
const ReductionCtx = reduce.ReductionCtx;
const Word = reduce.Word;
const clib = reduce.clib;

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
