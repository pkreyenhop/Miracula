const std = @import("std");

const TestCase = struct {
    name: []const u8,
    input: []const u8,
    script_content: ?[]const u8 = null,
    script_path: ?[]const u8 = null,
};

const TEST_CASES = [_]TestCase{
    .{
        .name = "arithmetic_1_plus_2",
        .input = "1+2\n/q\n",
    },
    .{
        .name = "factorial_10",
        .input = "product [1..10]\n/q\n",
    },
    .{
        .name = "map_double",
        .input = "map (2*) [1..5]\n/q\n",
    },
    .{
        .name = "big_integers",
        .input = "12345678901234567890 + 10\n2^80\n/q\n",
    },
    .{
        .name = "lazy_lists_and_strings",
        .input = "take 5 [1..]\nreverse [1,2,3]\nzip2 [1,2,3] [4,5,6]\n\"abc\" ++ \"def\"\n/q\n",
    },
    .{
        .name = "fibonacci_script",
        .script_path = "miralib/ex/fib.m",
        .input = "fib 10\n/q\n",
    },
    .{
        .name = "user_defined_script",
        .script_content = "square x = x*x\ntwice f x = f (f x)\npairup x y = (x,y)\n",
        .input = "square 12\ntwice square 2\npairup 1 2\n/q\n",
    },
};

const Stats = struct {
    reductions: u64 = 0,
    cells_claimed: u64 = 0,
    no_of_gcs: u64 = 0,
};

fn parseStats(text: []const u8, stats: *Stats) void {
    var lines = std.mem.splitScalar(u8, text, '\n');
    while (lines.next()) |line| {
        if (std.mem.startsWith(u8, line, "||")) {
            if (std.mem.indexOf(u8, line, "reductions =")) |idx| {
                const sub = line[idx + "reductions =".len..];
                const trimmed = std.mem.trim(u8, sub, " \t\r\n");
                var parts = std.mem.splitAny(u8, trimmed, ", \t\r\n");
                stats.reductions = std.fmt.parseInt(u64, parts.first(), 10) catch 0;
            }
            if (std.mem.indexOf(u8, line, "cells claimed =")) |idx| {
                const sub = line[idx + "cells claimed =".len..];
                const trimmed = std.mem.trim(u8, sub, " \t\r\n");
                var parts = std.mem.splitAny(u8, trimmed, ", \t\r\n");
                stats.cells_claimed = std.fmt.parseInt(u64, parts.first(), 10) catch 0;
            }
            if (std.mem.indexOf(u8, line, "no of gc's =")) |idx| {
                const sub = line[idx + "no of gc's =".len..];
                const trimmed = std.mem.trim(u8, sub, " \t\r\n");
                var parts = std.mem.splitAny(u8, trimmed, ", \t\r\n");
                stats.no_of_gcs = std.fmt.parseInt(u64, parts.first(), 10) catch 0;
            }
        }
    }
}

pub fn main(ctx: std.process.Init) !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const refactored_bin = "./zig-out/bin/mira";

    _ = std.Io.Dir.cwd().statFile(ctx.io, refactored_bin, .{}) catch {
        std.debug.print("Error: Refactored binary {s} not found.\n", .{refactored_bin});
        std.process.exit(1);
    };

    var failed = false;

    for (TEST_CASES) |tc| {
        std.debug.print("Verifying {s} against golden baseline ... ", .{tc.name});

        const temp_path = "./tests/golden/reg_tmp.m";
        var has_temp = false;
        
        const argv_len = 7;
        var argv = try allocator.alloc([]const u8, argv_len);
        defer allocator.free(argv);

        var argc: usize = 0;
        argv[argc] = refactored_bin;
        argc += 1;
        argv[argc] = "-lib";
        argc += 1;
        argv[argc] = "miralib";
        argc += 1;
        argv[argc] = "-hush";
        argc += 1;
        argv[argc] = "-count";
        argc += 1;

        if (tc.script_content) |content| {
            const file = try std.Io.Dir.cwd().createFile(ctx.io, temp_path, .{});
            try file.writeStreamingAll(ctx.io, content);
            file.close(ctx.io);
            argv[argc] = temp_path;
            argc += 1;
            has_temp = true;
        } else if (tc.script_path) |path| {
            argv[argc] = path;
            argc += 1;
        }
        defer if (has_temp) {
            std.Io.Dir.cwd().deleteFile(ctx.io, temp_path) catch {};
        };

        var child = try std.process.spawn(ctx.io, .{
            .argv = argv[0..argc],
            .stdin = .pipe,
            .stdout = .pipe,
            .stderr = .pipe,
        });
        errdefer child.kill(ctx.io);

        child.stdin.?.writeStreamingAll(ctx.io, tc.input) catch {};
        child.stdin.?.close(ctx.io);
        child.stdin = null;

        var multi_reader_buffer: std.Io.File.MultiReader.Buffer(2) = undefined;
        var multi_reader: std.Io.File.MultiReader = undefined;
        multi_reader.init(allocator, ctx.io, multi_reader_buffer.toStreams(), &.{ child.stdout.?, child.stderr.? });
        defer multi_reader.deinit();

        const timeout = std.Io.Timeout{ .duration = .{ .raw = std.Io.Duration.fromSeconds(10), .clock = .real } };
        while (multi_reader.fill(64, timeout)) |_| {} else |err| switch (err) {
            error.EndOfStream => {},
            error.Timeout => {
                child.kill(ctx.io);
                _ = try child.wait(ctx.io);
                return error.Timeout;
            },
            else => |e| return e,
        }

        _ = try child.wait(ctx.io);

        const stdout_text = try multi_reader.toOwnedSlice(0);
        defer allocator.free(stdout_text);
        const stderr_text = try multi_reader.toOwnedSlice(1);
        defer allocator.free(stderr_text);

        // Read golden stdout
        var golden_out_path_buf: [256]u8 = undefined;
        const golden_out_path = std.fmt.bufPrint(&golden_out_path_buf, "tests/reducer/golden/{s}.stdout", .{tc.name}) catch "";
        const golden_stdout = std.Io.Dir.cwd().readFileAlloc(ctx.io, golden_out_path, allocator, .limited(1024 * 1024)) catch |err| {
            std.debug.print("FAIL (Golden stdout not found: {any})\n", .{err});
            failed = true;
            continue;
        };
        defer allocator.free(golden_stdout);

        if (!std.mem.eql(u8, stdout_text, golden_stdout)) {
            std.debug.print("FAIL (Stdout mismatch)\n", .{});
            std.debug.print("--- Golden Stdout ---\n{s}\n", .{golden_stdout});
            std.debug.print("--- Actual Stdout ---\n{s}\n", .{stdout_text});
            failed = true;
            continue;
        }

        // Read and parse golden stats
        var golden_stats_path_buf: [256]u8 = undefined;
        const golden_stats_path = std.fmt.bufPrint(&golden_stats_path_buf, "tests/reducer/golden/{s}.stats", .{tc.name}) catch "";
        const golden_stats_text = std.Io.Dir.cwd().readFileAlloc(ctx.io, golden_stats_path, allocator, .limited(1024 * 1024)) catch |err| {
            std.debug.print("FAIL (Golden stats not found: {any})\n", .{err});
            failed = true;
            continue;
        };
        defer allocator.free(golden_stats_text);

        const parsed_golden = std.json.parseFromSlice(Stats, allocator, golden_stats_text, .{}) catch |err| {
            std.debug.print("FAIL (Failed to parse golden stats JSON: {any})\n", .{err});
            failed = true;
            continue;
        };
        defer parsed_golden.deinit();

        var actual_stats = Stats{};
        parseStats(stderr_text, &actual_stats);

        if (actual_stats.reductions != parsed_golden.value.reductions or
            actual_stats.cells_claimed != parsed_golden.value.cells_claimed or
            actual_stats.no_of_gcs != parsed_golden.value.no_of_gcs)
        {
            std.debug.print("FAIL (Stats mismatch)\n", .{});
            std.debug.print("  Actual: red={d}, cells={d}, gcs={d}\n", .{ actual_stats.reductions, actual_stats.cells_claimed, actual_stats.no_of_gcs });
            std.debug.print("  Golden: red={d}, cells={d}, gcs={d}\n", .{ parsed_golden.value.reductions, parsed_golden.value.cells_claimed, parsed_golden.value.no_of_gcs });
            failed = true;
            continue;
        }

        std.debug.print("PASS\n", .{});
    }

    if (failed) {
        std.process.exit(1);
    } else {
        std.debug.print("All reduction golden verification tests passed successfully!\n", .{});
        std.process.exit(0);
    }
}
