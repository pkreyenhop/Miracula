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
    // docs/GoReady.md Phase 0 step 4: differential coverage for the
    // surfaces Phase 1's native lexer/parser rewrite will touch. Mirrors
    // tests/golden/hex_oct_literals and tests/golden/literate_intro.lit.
    .{
        .name = "hex_octal_literals",
        .input = "0xff\n0x1A2B3C\n0o777\n\n/q\n",
    },
    .{
        .name = "literate_script",
        .script_content = "> square x = x * x\n> cube x  = x * x * x\n\nProse below the code lines is not Miranda source.\n",
        .input = "square 5\ncube 3\n\n/q\n",
    },
    // %insert is pure textual substitution in the legacy lexer (no AST node),
    // so it already works; resolves relative to reg_tmp.m's directory
    // (tests/golden/), reusing directive_insert_body.txt there.
    .{
        .name = "insert_directive",
        .script_content = "%insert \"directive_insert_body.txt\"\n\nr = inserted_val + 1\n",
        .input = "r\n\n/q\n",
    },
};

const Stats = struct {
    reductions: u64 = 0,
    cells_claimed: u64 = 0,
    no_of_gcs: u64 = 0,
};

fn parseStats(allocator: std.mem.Allocator, stderr_data: []const u8, stats: *Stats) ![]const u8 {
    var other_err: std.ArrayList([]const u8) = .empty;
    defer other_err.deinit(allocator);

    var lines = std.mem.splitScalar(u8, stderr_data, '\n');
    while (lines.next()) |line| {
        if (std.mem.startsWith(u8, line, "||")) {
            if (std.mem.indexOf(u8, line, "reductions =")) |idx| {
                const sub = line[idx + "reductions =".len ..];
                const trimmed = std.mem.trim(u8, sub, " \t\r\n");
                var parts = std.mem.splitAny(u8, trimmed, ", \t\r\n");
                stats.reductions = std.fmt.parseInt(u64, parts.first(), 10) catch 0;
            }
            if (std.mem.indexOf(u8, line, "cells claimed =")) |idx| {
                const sub = line[idx + "cells claimed =".len ..];
                const trimmed = std.mem.trim(u8, sub, " \t\r\n");
                var parts = std.mem.splitAny(u8, trimmed, ", \t\r\n");
                stats.cells_claimed = std.fmt.parseInt(u64, parts.first(), 10) catch 0;
            }
            if (std.mem.indexOf(u8, line, "no of gc's =")) |idx| {
                const sub = line[idx + "no of gc's =".len ..];
                const trimmed = std.mem.trim(u8, sub, " \t\r\n");
                var parts = std.mem.splitAny(u8, trimmed, ", \t\r\n");
                stats.no_of_gcs = std.fmt.parseInt(u64, parts.first(), 10) catch 0;
            }
        } else {
            if (!std.mem.startsWith(u8, line, "[TRACE]") and
                !std.mem.startsWith(u8, line, "[ALLOC]") and
                !std.mem.startsWith(u8, line, "[DIAG"))
            {
                try other_err.append(allocator, line);
            }
        }
    }

    var total_len: usize = 0;
    for (other_err.items) |line| {
        total_len += line.len;
    }
    if (other_err.items.len > 0) {
        total_len += other_err.items.len - 1;
    }

    const joined = try allocator.alloc(u8, total_len);
    errdefer allocator.free(joined);
    var offset: usize = 0;
    for (other_err.items, 0..) |line, idx| {
        std.mem.copyForwards(u8, joined[offset..], line);
        offset += line.len;
        if (idx < other_err.items.len - 1) {
            joined[offset] = '\n';
            offset += 1;
        }
    }
    return joined;
}

const RunResult = struct {
    stdout: []const u8,
    stderr: []const u8,
    returncode: i32,
};

fn runBinary(allocator: std.mem.Allocator, io: std.Io, binary_path: []const u8, tc: TestCase) !RunResult {
    const temp_path = "./tests/golden/reg_tmp.m";
    var has_temp = false;

    const argv_len = 7;
    var argv = try allocator.alloc([]const u8, argv_len);
    defer allocator.free(argv);

    var argc: usize = 0;
    argv[argc] = binary_path;
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
        const file = try std.Io.Dir.cwd().createFile(io, temp_path, .{});
        try file.writeStreamingAll(io, content);
        file.close(io);
        argv[argc] = temp_path;
        argc += 1;
        has_temp = true;
    } else if (tc.script_path) |path| {
        argv[argc] = path;
        argc += 1;
    }
    defer if (has_temp) {
        std.Io.Dir.cwd().deleteFile(io, temp_path) catch {};
    };

    var child = try std.process.spawn(io, .{
        .argv = argv[0..argc],
        .stdin = .pipe,
        .stdout = .pipe,
        .stderr = .pipe,
    });
    errdefer child.kill(io);

    child.stdin.?.writeStreamingAll(io, tc.input) catch {};
    child.stdin.?.close(io);
    child.stdin = null;

    var multi_reader_buffer: std.Io.File.MultiReader.Buffer(2) = undefined;
    var multi_reader: std.Io.File.MultiReader = undefined;
    multi_reader.init(allocator, io, multi_reader_buffer.toStreams(), &.{ child.stdout.?, child.stderr.? });
    defer multi_reader.deinit();

    const timeout = std.Io.Timeout{ .duration = .{ .raw = std.Io.Duration.fromSeconds(10), .clock = .real } };
    while (multi_reader.fill(64, timeout)) |_| {} else |err| switch (err) {
        error.EndOfStream => {},
        error.Timeout => {
            child.kill(io);
            _ = try child.wait(io);
            return error.Timeout;
        },
        else => |e| return e,
    }

    const term = try child.wait(io);
    const returncode = switch (term) {
        .exited => |code| @as(i32, @intCast(code)),
        else => -1,
    };

    const stdout_text = try multi_reader.toOwnedSlice(0);
    const stderr_text = try multi_reader.toOwnedSlice(1);

    return RunResult{
        .stdout = stdout_text,
        .stderr = stderr_text,
        .returncode = returncode,
    };
}

pub fn main(ctx: std.process.Init) !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const original_bin = "./mira_original";
    const refactored_bin = "./zig-out/bin/mira";

    _ = std.Io.Dir.cwd().statFile(ctx.io, original_bin, .{}) catch {
        std.debug.print("Original binary {s} not found, skipping differential regression checks.\n", .{original_bin});
        std.process.exit(0);
    };

    _ = std.Io.Dir.cwd().statFile(ctx.io, refactored_bin, .{}) catch {
        std.debug.print("Error: Refactored binary {s} not found.\n", .{refactored_bin});
        std.process.exit(1);
    };

    var failed = false;

    for (TEST_CASES) |tc| {
        std.debug.print("Running test: {s} ... ", .{tc.name});

        const orig_res = try runBinary(allocator, ctx.io, original_bin, tc);
        defer allocator.free(orig_res.stdout);
        defer allocator.free(orig_res.stderr);

        const ref_res = try runBinary(allocator, ctx.io, refactored_bin, tc);
        defer allocator.free(ref_res.stdout);
        defer allocator.free(ref_res.stderr);

        if (orig_res.returncode != ref_res.returncode) {
            std.debug.print("FAIL (Exit code mismatch)\n", .{});
            std.debug.print("  Original: {d}\n", .{orig_res.returncode});
            std.debug.print("  Refactored: {d}\n", .{ref_res.returncode});
            failed = true;
            continue;
        }

        if (!std.mem.eql(u8, orig_res.stdout, ref_res.stdout)) {
            std.debug.print("FAIL (Stdout mismatch)\n", .{});
            std.debug.print("--- Original Stdout ---\n{s}\n", .{orig_res.stdout});
            std.debug.print("--- Refactored Stdout ---\n{s}\n", .{ref_res.stdout});
            failed = true;
            continue;
        }

        var orig_stats = Stats{};
        var ref_stats = Stats{};

        const orig_other_err = try parseStats(allocator, orig_res.stderr, &orig_stats);
        defer allocator.free(orig_other_err);
        const ref_other_err = try parseStats(allocator, ref_res.stderr, &ref_stats);
        defer allocator.free(ref_other_err);

        if (!std.mem.eql(u8, orig_other_err, ref_other_err)) {
            std.debug.print("FAIL (Stderr mismatch, excluding stats)\n", .{});
            std.debug.print("--- Original Stderr ---\n{s}\n", .{orig_other_err});
            std.debug.print("--- Refactored Stderr ---\n{s}\n", .{ref_other_err});
            failed = true;
            continue;
        }

        if (orig_stats.reductions != ref_stats.reductions or
            orig_stats.cells_claimed != ref_stats.cells_claimed or
            orig_stats.no_of_gcs != ref_stats.no_of_gcs)
        {
            std.debug.print("FAIL (Stats mismatch: orig_red={d}, ref_red={d})\n", .{ orig_stats.reductions, ref_stats.reductions });
            failed = true;
            continue;
        }

        std.debug.print("PASS\n", .{});
    }

    if (failed) {
        std.process.exit(1);
    } else {
        std.debug.print("All verification tests passed successfully!\n", .{});
        std.process.exit(0);
    }
}
