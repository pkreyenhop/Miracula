const std = @import("std");
const reduce = @import("reduce.zig");
const ReductionCtx = reduce.ReductionCtx;
const Word = reduce.Word;
const clib = reduce.clib;

extern var tag: [*]u8;
extern fn reduce_stream_read(ctx: ?*anyopaque, op: Word) c_int;

export fn handle_READ(ctx: *ReductionCtx) void {
    ctx.action = reduce_stream_read(ctx, clib.READ);
}

export fn handle_READBIN(ctx: *ReductionCtx) void {
    ctx.action = reduce_stream_read(ctx, clib.READBIN);
}

export fn handle_READVALS(ctx: *ReductionCtx) void {
    ctx.action = reduce_stream_read(ctx, clib.READVALS);
}

export fn handle_STARTREADVALS(ctx: *ReductionCtx) void {
    if (reduce.upleft(ctx)) {
        ctx.action = clib.ACT_DONE;
        return;
    }
    
    const lastarg_val = reduce.reduce(reduce.tl_get(ctx.e));
    reduce.tl_set(ctx.e, lastarg_val);
    
    if (lastarg_val == clib.OFFSIDE) {
        if (reduce.stdinuse != 0 and reduce.stdinuse != '+') {
            tag[reduce.clean_ptr(ctx.e)] = clib.AP;
            reduce.rewrite_to_nil(&ctx.e);
            ctx.action = clib.ACT_DONE;
            return;
        }
        reduce.stdinuse = '+';
        ctx.hold = reduce.cons(reduce.tl_get(reduce.hd_get(ctx.e)), 0);
        reduce.tl_set(ctx.e, @intCast(@intFromPtr(reduce.getStdin().?)));
    } else {
        ctx.hold = reduce.cons(reduce.tl_get(reduce.hd_get(ctx.e)), lastarg_val);
        const fil = reduce.getstring(lastarg_val, "readvals");
        const f = clib.fopen(fil, "r");
        if (f == null) {
            _ = clib.fprintf(reduce.getStderr().?, "\nreadvals, cannot open: \"%s\"\n", fil);
            clib.outstats();
            clib.exit(1);
        }
        reduce.tl_set(ctx.e, @intCast(@intFromPtr(f.?)));
    }
    
    reduce.hd_set(ctx.e, reduce.ap(clib.READVALS, ctx.hold));
    reduce.downLeft(ctx);
    reduce.downLeft(ctx);
    handle_READVALS(ctx);
}
