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
