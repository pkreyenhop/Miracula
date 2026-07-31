//! eval/trace.zig — zero-overhead reduction tracing (functionality + perf).
//!
//! Records, per `reduce()` step, which head combinator fired — a histogram that
//! answers both "what ran" (functionality) and "what's hot" (performance), and
//! pairs with the always-on reduction/cell counters in `runtime/reduce.zig`.
//!
//! **Zero overhead when off.** Tracing is gated by the comptime constant
//! `enabled` (the `-Dreduce-trace` build option, default false). Every entry
//! point opens with `if (comptime !enabled) return;`, so with the flag off the
//! whole body — and the call itself, since these are `inline` — is eliminated
//! by the compiler. No counters, no branches, no output in a normal build.
//! Enable with: `zig build -Dreduce-trace`.

const std = @import("std");
const word = @import("../graph/word.zig");
const combinator = @import("../graph/combinator.zig");
const opts = @import("version_options");

/// Compile-time master switch. When false, every function below is a no-op that
/// inlines to nothing.
pub const enabled: bool = opts.reduce_trace;

/// Number of combinator/atom slots, indexed by `(atom - CMBASE)` — matches the
/// `combinator.cmbnms` name table so a count can be labelled.
const slots = combinator.cmbnms.len;

/// The histogram itself — a field of `reduce.EvalState` (`ctx.eval.trace` /
/// `ev.trace`) rather than a module global, per the shared-state plan's
/// Phase 6 sweep. Sized unconditionally (like the rest of `EvalState`)
/// regardless of `enabled`; only the *code* that touches it is compiled out.
pub const TraceState = struct {
    steps: u64 = 0,
    heads: [slots]u64 = .{0} ** slots,
};

/// Record one reduction step whose head is `e`. Only combinator/named-atom heads
/// (`CMBASE <= e < ATOMLIMIT`) are histogrammed — cell-tag dispatches (ID
/// substitution, saturated constructors, …) are not combinator reductions and
/// are skipped, so `steps == sum(heads)`. Inlined away when disabled.
pub inline fn step(t: *TraceState, e: word.Word) void {
    if (comptime !enabled) return;
    if (e >= word.CMBASE and word.isAtom(e)) {
        t.steps += 1;
        t.heads[@intCast(e - word.CMBASE)] += 1;
    }
}

/// Clear the histogram (e.g. between independent evaluations).
pub fn reset(t: *TraceState) void {
    if (comptime !enabled) return;
    t.steps = 0;
    @memset(&t.heads, 0);
}

/// Emit the functionality+performance histogram to stderr, combinators sorted by
/// firing count (descending). No-op when disabled.
pub fn dump(t: *TraceState) void {
    if (comptime !enabled) return;
    if (t.steps == 0) return;

    // Sort slot indices by count, descending, skipping zero-count combinators.
    var order: [slots]usize = undefined;
    var n: usize = 0;
    for (t.heads, 0..) |c, i| {
        if (c != 0) {
            order[n] = i;
            n += 1;
        }
    }
    std.sort.pdq(usize, order[0..n], t, struct {
        /// Order comparator: sort combinator slots by descending step count.
        fn lt(ts: *TraceState, a: usize, b: usize) bool {
            if (ts.heads[a] != ts.heads[b]) return ts.heads[a] > ts.heads[b];
            return a < b;
        }
    }.lt);

    std.debug.print("\n--- reduction trace: {d} combinator steps, {d} distinct heads ---\n", .{ t.steps, n });
    for (order[0..n]) |i| {
        const name: [*:0]const u8 = combinator.cmbnms[i] orelse "?";
        std.debug.print("  {s:<14} {d:>12}\n", .{ std.mem.span(name), t.heads[i] });
    }
}
