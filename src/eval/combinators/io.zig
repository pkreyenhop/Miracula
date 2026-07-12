//! eval/combinators/io.zig — reduction handlers for the lazy input combinators.
//!
//! Implements `READ`/`READBIN`/`READVALS`/`STARTREADVALS`: the combinators that
//! turn a file (or stdin) into a lazy list of characters or parsed values.
//! Dispatched from `reducer/reduce.zig` by combinator tag; each `handle_<NAME>`
//! mirrors the `word.<NAME>` constant the dispatcher switches on.

const std = @import("std");
const reduce = @import("../reduce_core.zig");
const ReductionCtx = reduce.ReductionCtx;
const Word = reduce.Word;
const Value = @import("../../graph/value.zig").Value;
const word = @import("../../graph/word.zig");
const os = @import("../../os.zig");
const reduce_rt = @import("../reduce_rt.zig");

/// Reduce the `READ` combinator: lazily stream characters from an input file.
pub fn handle_READ(ctx: *ReductionCtx) void {
    ctx.action = @intCast(reduce_rt.streamRead(ctx, word.READ));
}

/// Reduce the `READBIN` combinator: like `READ`, but reads raw bytes (binary mode).
pub fn handle_READBIN(ctx: *ReductionCtx) void {
    ctx.action = @intCast(reduce_rt.streamRead(ctx, word.READBIN));
}

/// Reduce the `READVALS` combinator: stream typed values parsed from a file.
pub fn handle_READVALS(ctx: *ReductionCtx) void {
    ctx.action = @intCast(reduce_rt.streamRead(ctx, word.READVALS));
}

/// Reduce `STARTREADVALS`: open the source (a file path, or stdin on `OFFSIDE`),
/// then hand off to `handle_READVALS` to stream the parsed values.
pub fn handle_STARTREADVALS(ctx: *ReductionCtx) reduce.ReduceError!void {
    if (reduce.upleft(ctx)) {
        ctx.action = word.ACT_DONE;
        return;
    }

    const lastarg_val = try reduce.reduceVal(ctx.heap, reduce.tlGet(ctx.heap, ctx.e));
    reduce.tlSet(ctx.heap, ctx.e, lastarg_val);

    if (lastarg_val.toRaw() == word.OFFSIDE) {
        if (ctx.eval.stdinuse != 0 and ctx.eval.stdinuse != '+') {
            reduce.setTag(ctx.heap, ctx.e, .AP);
            reduce.rewriteToNil(ctx.heap, &ctx.e);
            ctx.action = word.ACT_DONE;
            return;
        }
        ctx.eval.stdinuse = '+';
        ctx.hold = reduce.cons(ctx.heap, reduce.tlGet(ctx.heap, reduce.hdGet(ctx.heap, ctx.e)), Value.fromRaw(0));
        reduce.tlSet(ctx.heap, ctx.e, reduce_rt.wrapPtr(ctx.heap, @intCast(@intFromPtr(reduce.getStdin().?))));
    } else {
        ctx.hold = reduce.cons(ctx.heap, reduce.tlGet(ctx.heap, reduce.hdGet(ctx.heap, ctx.e)), lastarg_val);
        const fil = try reduce.getstringVal(ctx.heap, lastarg_val, "readvals");
        const f = word.fopen(fil, "r");
        if (f == null) {
            word.printErr("\nreadvals, cannot open: \"{s}\"\n", .{std.mem.span(fil.?)});
            reduce_rt.outstats();
            os.exit(1);
        }
        reduce.tlSet(ctx.heap, ctx.e, reduce_rt.wrapPtr(ctx.heap, @intCast(@intFromPtr(f.?))));
    }

    reduce.hdSet(ctx.heap, ctx.e, reduce.ap(ctx.heap, Value.fromRaw(word.READVALS), ctx.hold));
    reduce.downLeft(ctx);
    reduce.downLeft(ctx);
    handle_READVALS(ctx);
}
