const std = @import("std");

const Benchmark = struct {
    name: []const u8,
    script: []const u8,
    input: []const u8,
};

const BENCHMARKS = [_]Benchmark{
    .{
        .name = "Ackermann (3, 8)",
        .script =
        \\ack 0 n = n + 1
        \\ack m 0 = ack (m - 1) 1
        \\ack m n = ack (m - 1) (ack m (n - 1))
        \\
        ,
        .input = "ack 3 8\n",
    },
    .{
        .name = "Fibonacci (30)",
        .script =
        \\fib 0 = 0
        \\fib 1 = 1
        \\fib n = fib (n - 1) + fib (n - 2)
        \\
        ,
        .input = "fib 30\n",
    },
    .{
        .name = "Lazy Prime Sieve (take 500)",
        .script =
        \\primes = sieve [2..]
        \\sieve (p:xs) = p : sieve [x | x <- xs; x mod p ~= 0]
        \\
        ,
        .input = "take 500 primes\n",
    },
};

fn getMonotonicNs() i128 {
    var ts: std.posix.timespec = undefined;
    _ = std.posix.system.clock_gettime(std.posix.CLOCK.MONOTONIC, &ts);
    return @as(i128, ts.sec) * std.time.ns_per_s + ts.nsec;
}

fn parseStats(text: []const u8, reductions: *u64, cells: *u64, gcs: *u64) void {
    var lines = std.mem.splitScalar(u8, text, '\n');
    while (lines.next()) |line| {
        if (std.mem.indexOf(u8, line, "reductions =")) |idx| {
            const sub = line[idx + "reductions =".len ..];
            const trimmed = std.mem.trim(u8, sub, " \t\r\n");
            var parts = std.mem.splitAny(u8, trimmed, ", \t\r\n");
            reductions.* = std.fmt.parseInt(u64, parts.first(), 10) catch 0;
        }
        if (std.mem.indexOf(u8, line, "cells claimed =")) |idx| {
            const sub = line[idx + "cells claimed =".len ..];
            const trimmed = std.mem.trim(u8, sub, " \t\r\n");
            var parts = std.mem.splitAny(u8, trimmed, ", \t\r\n");
            cells.* = std.fmt.parseInt(u64, parts.first(), 10) catch 0;
        }
        if (std.mem.indexOf(u8, line, "no of gc's =")) |idx| {
            const sub = line[idx + "no of gc's =".len ..];
            const trimmed = std.mem.trim(u8, sub, " \t\r\n");
            var parts = std.mem.splitAny(u8, trimmed, ", \t\r\n");
            gcs.* = std.fmt.parseInt(u64, parts.first(), 10) catch 0;
        }
    }
}

const Result = struct {
    avg_time_ms: f64,
    reductions: u64,
    cells: u64,
    avg_gcs: f64,
    red_rate_m: f64,
};

pub fn main(ctx: std.process.Init) !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const raw_args = ctx.minimal.args.vector;
    var binary_path: []const u8 = "./zig-out/bin/mira";
    if (raw_args.len > 1) {
        binary_path = std.mem.span(raw_args[1]);
    }

    // Verify binary exists
    _ = std.Io.Dir.cwd().statFile(ctx.io, binary_path, .{}) catch {
        std.debug.print("Error: Binary {s} not found.\n", .{binary_path});
        std.process.exit(1);
    };

    std.debug.print("=== Miracula Macro-Benchmarks ({s}) ===\n\n", .{binary_path});

    var results: [BENCHMARKS.len]Result = undefined;

    for (BENCHMARKS, 0..) |bench, bench_idx| {
        std.debug.print("Running macro-benchmark: {s} ...\n", .{bench.name});

        const temp_path = "./tests/golden/bench_tmp.m";
        const file = try std.Io.Dir.cwd().createFile(ctx.io, temp_path, .{});
        try file.writeStreamingAll(ctx.io, bench.script);
        file.close(ctx.io);
        defer std.Io.Dir.cwd().deleteFile(ctx.io, temp_path) catch {};

        var times: std.ArrayList(f64) = .empty;
        defer times.deinit(allocator);
        var gcs_list: std.ArrayList(u64) = .empty;
        defer gcs_list.deinit(allocator);

        var max_reductions: u64 = 0;
        var max_cells: u64 = 0;

        var i: usize = 0;
        while (i < 3) : (i += 1) {
            const start = getMonotonicNs();

            var argv = try allocator.alloc([]const u8, 5);
            defer allocator.free(argv);

            argv[0] = binary_path;
            argv[1] = "-lib";
            argv[2] = "./miralib";
            argv[3] = "-count";
            argv[4] = temp_path;

            var child = try std.process.spawn(ctx.io, .{
                .argv = argv,
                .stdin = .pipe,
                .stdout = .pipe,
                .stderr = .pipe,
            });
            errdefer child.kill(ctx.io);

            child.stdin.?.writeStreamingAll(ctx.io, bench.input) catch {};
            child.stdin.?.close(ctx.io);
            child.stdin = null;

            var multi_reader_buffer: std.Io.File.MultiReader.Buffer(2) = undefined;
            var multi_reader: std.Io.File.MultiReader = undefined;
            multi_reader.init(allocator, ctx.io, multi_reader_buffer.toStreams(), &.{ child.stdout.?, child.stderr.? });
            defer multi_reader.deinit();

            while (multi_reader.fill(64, .none)) |_| {} else |err| switch (err) {
                error.EndOfStream => {},
                else => |e| return e,
            }

            _ = try child.wait(ctx.io);

            const elapsed_ns = getMonotonicNs() - start;
            const elapsed_sec = @as(f64, @floatFromInt(elapsed_ns)) / 1_000_000_000.0;
            try times.append(allocator, elapsed_sec);

            const raw_stderr = try multi_reader.toOwnedSlice(1);
            defer allocator.free(raw_stderr);
            const raw_stdout = try multi_reader.toOwnedSlice(0);
            defer allocator.free(raw_stdout);

            var red_i: u64 = 0;
            var cells_i: u64 = 0;
            var gcs_i: u64 = 0;
            parseStats(raw_stderr, &red_i, &cells_i, &gcs_i);

            max_reductions = @max(max_reductions, red_i);
            max_cells = @max(max_cells, cells_i);
            try gcs_list.append(allocator, gcs_i);
        }

        var total_time_sec: f64 = 0.0;
        for (times.items) |t| total_time_sec += t;
        var total_gcs: f64 = 0.0;
        for (gcs_list.items) |g| total_gcs += @as(f64, @floatFromInt(g));

        const avg_time_sec = total_time_sec / 3.0;
        const avg_time_ms = avg_time_sec * 1000.0;
        const avg_gcs = total_gcs / 3.0;
        const red_rate = if (avg_time_sec > 0) @as(f64, @floatFromInt(max_reductions)) / avg_time_sec else 0;
        const red_rate_m = red_rate / 1_000_000.0;

        results[bench_idx] = .{
            .avg_time_ms = avg_time_ms,
            .reductions = max_reductions,
            .cells = max_cells,
            .avg_gcs = avg_gcs,
            .red_rate_m = red_rate_m,
        };
    }

    std.debug.print("\n| Benchmark Name | Avg Time (ms) | Reductions | Reclaimed GCs | Throughput (M reductions/s) |\n", .{});
    std.debug.print("|----------------|---------------|------------|---------------|-----------------------------|\n", .{});
    for (BENCHMARKS, 0..) |bench, bench_idx| {
        const res = results[bench_idx];
        std.debug.print("| {s} | {d:.2} | {d} | {d:.1} | {d:.3} |\n", .{
            bench.name,
            res.avg_time_ms,
            res.reductions,
            res.avg_gcs,
            res.red_rate_m,
        });
    }
    std.debug.print("\n", .{});
}
