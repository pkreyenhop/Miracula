const std = @import("std");
const heap = @import("runtime/heap.zig");
const lex = @import("parser/lex.zig");
const word = @import("runtime/word.zig");
const setup = @import("compiler/setup.zig");
const rt = @import("runtime/runtime_state.zig");

pub fn main(ctx: std.process.Init) !void {
    rt.io = ctx.io;
    rt.environ = ctx.minimal.environ;
    rt.allocator = rt.gpa.allocator();

    // Anchor the GC's stack scan at this frame. gc() -> bases() walks the C
    // stack from the current SP toward rt.rs.cstack; if it stays null the scan
    // runs to address 0 and segfaults. Set it to a live local in main() before
    // any allocation can trigger a collection (mirrors startup.mainEntry).
    var cstack_base: word.Word = 0;
    rt.rs.cstack = @ptrCast(&cstack_base);

    // benchInterning() interns 100k unique identifiers (~16 bytes each) into the
    // lexer dictionary, which far exceeds the 100 KB production default. Size the
    // dictionary for the benchmark workload before setupdic() allocates it.
    rt.rs.DICSPACE = 4_000_000;

    // 1. Initialise the runtime environment
    heap.setupheap();
    lex.setupdic();
    setup.miraSetup();

    word.print("=== Miracula Micro-Benchmarks ===\n\n", .{});

    // Run allocation benchmark
    try benchAllocation();

    // Run GC benchmark
    try benchGC();

    // Run Symbol Interning benchmark
    try benchInterning();
}

fn benchAllocation() !void {
    const started = std.Io.Clock.Timestamp.now(rt.io, .awake);
    const count = 500_000;
    var i: usize = 0;
    while (i < count) : (i += 1) {
        _ = heap.make(word.CONS, word.NIL, word.NIL);
    }
    const elapsed = started.untilNow(rt.io);
    const elapsed_ms = @as(f64, @floatFromInt(elapsed.raw.nanoseconds)) / 1_000_000.0;
    const allocs_per_sec = @as(f64, count) / (elapsed_ms / 1000.0);
    word.print("Raw Cell Allocation (500k CONS cells):\n", .{});
    word.print("  Time: {d:.2} ms\n", .{elapsed_ms});
    word.print("  Rate: {d:.2} M allocs/sec\n\n", .{allocs_per_sec / 1_000_000.0});
}

fn benchGC() !void {
    // Fill the heap to 80% capacity with unreachable garbage
    const fill_count = 800_000;
    var i: usize = 0;
    while (i < fill_count) : (i += 1) {
        _ = heap.make(word.CONS, word.NIL, word.NIL);
    }

    // Measure GC execution time
    const started = std.Io.Clock.Timestamp.now(rt.io, .awake);
    heap.gc();
    const elapsed = started.untilNow(rt.io);
    const elapsed_ms = @as(f64, @floatFromInt(elapsed.raw.nanoseconds)) / 1_000_000.0;
    word.print("Garbage Collection (reclaiming 800k garbage cells):\n", .{});
    word.print("  Time: {d:.2} ms\n\n", .{elapsed_ms});
}

fn benchInterning() !void {
    const started = std.Io.Clock.Timestamp.now(rt.io, .awake);
    const count = 100_000;
    var i: usize = 0;
    var buf: [64]u8 = undefined;
    while (i < count) : (i += 1) {
        const name = try std.fmt.bufPrintZ(&buf, "sym_bench_{d}", .{i});
        _ = lex.makeId(name.ptr);
    }
    const elapsed = started.untilNow(rt.io);
    const elapsed_ms = @as(f64, @floatFromInt(elapsed.raw.nanoseconds)) / 1_000_000.0;
    const interns_per_sec = @as(f64, count) / (elapsed_ms / 1000.0);
    word.print("Symbol Interning (100k unique identifiers):\n", .{});
    word.print("  Time: {d:.2} ms\n", .{elapsed_ms});
    word.print("  Rate: {d:.2} K interns/sec\n\n", .{interns_per_sec / 1000.0});
}
