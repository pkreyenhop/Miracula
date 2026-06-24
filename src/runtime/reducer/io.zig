//! reducer/io.zig — reduction handlers for the lazy input combinators.
//!
//! Implements `READ`/`READBIN`/`READVALS`/`STARTREADVALS`: the combinators that
//! turn a file (or stdin) into a lazy list of characters or parsed values.
//! Dispatched from `reducer/reduce.zig` by combinator tag; each `handle_<NAME>`
//! mirrors the `word.<NAME>` constant the dispatcher switches on.

const std = @import("std");
const reduce = @import("reduce_core.zig");
const ReductionCtx = reduce.ReductionCtx;
const Word = reduce.Word;
const word = @import("../word.zig");
const main_clib = @import("../main_clib.zig");
const reduce_rt = @import("../reduce.zig");

/// C runtime helper: pull the next item from the stream `ctx` is reading under
/// combinator `op`, returning the post-step action code.
extern fn streamRead(ctx: ?*anyopaque, op: Word) c_int;

/// Reduce the `READ` combinator: lazily stream characters from an input file.
pub fn handle_READ(ctx: *ReductionCtx) void {
    ctx.action = streamRead(ctx, word.READ);
}

/// Reduce the `READBIN` combinator: like `READ`, but reads raw bytes (binary mode).
pub fn handle_READBIN(ctx: *ReductionCtx) void {
    ctx.action = streamRead(ctx, word.READBIN);
}

/// Reduce the `READVALS` combinator: stream typed values parsed from a file.
pub fn handle_READVALS(ctx: *ReductionCtx) void {
    ctx.action = streamRead(ctx, word.READVALS);
}

/// Reduce `STARTREADVALS`: open the source (a file path, or stdin on `OFFSIDE`),
/// then hand off to `handle_READVALS` to stream the parsed values.
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
