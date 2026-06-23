const std = @import("std");
const reduce = @import("reduce_core.zig");
const ReductionCtx = reduce.ReductionCtx;
const Word = reduce.Word;
const word = @import("../word.zig");
const main_clib = @import("../main_clib.zig");
const reduce_rt = @import("../reduce.zig");


extern fn reduce_stream_read(ctx: ?*anyopaque, op: Word) c_int;
pub fn handle_READ(ctx: *ReductionCtx) void {
    ctx.action = reduce_stream_read(ctx, word.READ);
}

pub fn handle_READBIN(ctx: *ReductionCtx) void {
    ctx.action = reduce_stream_read(ctx, word.READBIN);
}

pub fn handle_READVALS(ctx: *ReductionCtx) void {
    ctx.action = reduce_stream_read(ctx, word.READVALS);
}

pub fn handle_STARTREADVALS(ctx: *ReductionCtx) void {
    if (reduce.upleft(ctx)) {
        ctx.action = word.ACT_DONE;
        return;
    }

    const lastarg_val = reduce.reduce(reduce.tl_get(ctx.e));
    reduce.tl_set(ctx.e, lastarg_val);

    if (lastarg_val == word.OFFSIDE) {
        if (reduce_rt.ev.stdinuse != 0 and reduce_rt.ev.stdinuse != '+') {
            reduce.setTag(ctx.e, word.AP);
            reduce.rewrite_to_nil(&ctx.e);
            ctx.action = word.ACT_DONE;
            return;
        }
        reduce_rt.ev.stdinuse = '+';
        ctx.hold = reduce.cons(reduce.tl_get(reduce.hd_get(ctx.e)), 0);
        reduce.tl_set(ctx.e, @intCast(@intFromPtr(reduce.getStdin().?)));
    } else {
        ctx.hold = reduce.cons(reduce.tl_get(reduce.hd_get(ctx.e)), lastarg_val);
        const fil = reduce.getstring(lastarg_val, "readvals");
        const f = word.fopen(fil, "r");
        if (f == null) {
            word.printErr("\nreadvals, cannot open: \"{s}\"\n", .{std.mem.span(fil.?)});
            reduce_rt.outstats();
            main_clib.exit(1);
        }
        reduce.tl_set(ctx.e, @intCast(@intFromPtr(f.?)));
    }

    reduce.hd_set(ctx.e, reduce.ap(word.READVALS, ctx.hold));
    reduce.downLeft(ctx);
    reduce.downLeft(ctx);
    handle_READVALS(ctx);
}
