const std = @import("std");

fn sortLess(context: void, lhs: []const u8, rhs: []const u8) bool {
    _ = context;
    return std.mem.lessThan(u8, lhs, rhs);
}

const CrashMarkers = [_][]const u8{
    "panic",
    "uncaught signal",
    "Assertion failed",
    "SIGABRT",
    "SIGILL",
    "SIGSEGV",
};

fn checkCrash(combined: []const u8) bool {
    for (CrashMarkers) |marker| {
        if (std.mem.indexOf(u8, combined, marker) != null) return true;
    }
    return false;
}

const ExCorpusItem = struct {
    script: []const u8,
    expr: []const u8,
};

const EX_CORPUS = [_]ExCorpusItem{
    .{ .script = "./miralib/ex/fib.m", .expr = "fib 27" },
    .{ .script = "./miralib/ex/quicksort.m", .expr = "qsort testdata" },
    .{ .script = "./miralib/ex/treesort.m", .expr = "treesort testdata" },
    .{ .script = "./miralib/ex/primes.m", .expr = "#(take 150 primes)" },
    .{ .script = "./miralib/ex/hamming.m", .expr = "take 30 ham" },
    .{ .script = "./miralib/ex/topsort.m", .expr = "topsort [(1,2),(2,3),(1,3),(4,1)]" },
    .{ .script = "./tests/spine_corpus/ack_nk_free.m", .expr = "ack 3 6" },
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

    _ = std.Io.Dir.cwd().statFile(ctx.io, binary_path, .{}) catch {
        std.debug.print("Error: Binary {s} not found.\n", .{binary_path});
        std.process.exit(1);
    };

    var failed = false;

    // 1. Golden corpus stress check
    const golden_dir = "./tests/golden";
    var dir = std.Io.Dir.cwd().openDir(ctx.io, golden_dir, .{ .iterate = true }) catch {
        std.debug.print("Warning: Golden directory {s} not found, skipping golden corpus stress.\n", .{golden_dir});
        std.process.exit(1);
    };
    defer dir.close(ctx.io);

    var expected_files: std.ArrayList([]const u8) = .empty;
    defer {
        for (expected_files.items) |f| allocator.free(f);
        expected_files.deinit(allocator);
    }

    var iter = dir.iterate();
    while (try iter.next(ctx.io)) |entry| {
        if (std.mem.endsWith(u8, entry.name, ".expected")) {
            try expected_files.append(allocator, try allocator.dupe(u8, entry.name));
        }
    }

    std.mem.sort([]const u8, expected_files.items, {}, sortLess);

    for (expected_files.items) |ef| {
        const name = ef[0 .. ef.len - 9]; // strip ".expected"
        var in_path_buf: [256]u8 = undefined;
        const in_path = std.fmt.bufPrint(&in_path_buf, "tests/golden/{s}.in", .{name}) catch "";
        const in_exists = if (std.Io.Dir.cwd().statFile(ctx.io, in_path, .{})) |_| true else |_| false;
        if (!in_exists) continue;

        var m_path_buf: [256]u8 = undefined;
        const m_path = std.fmt.bufPrint(&m_path_buf, "tests/golden/{s}.m", .{name}) catch "";
        const m_exists = if (std.Io.Dir.cwd().statFile(ctx.io, m_path, .{})) |_| true else |_| false;

        var x_path_buf: [256]u8 = undefined;
        const x_path = std.fmt.bufPrint(&x_path_buf, "tests/golden/{s}.x", .{name}) catch "";
        
        // Remove stale compiled-script cache
        if (m_exists) {
            std.Io.Dir.cwd().deleteFile(ctx.io, x_path) catch {};
        }

        const stdin_content = try std.Io.Dir.cwd().readFileAlloc(ctx.io, in_path, allocator, .limited(1024 * 1024));
        defer allocator.free(stdin_content);

        const argv_len = 4 + if (m_exists) @as(usize, 1) else 0;
        var argv = try allocator.alloc([]const u8, argv_len);
        defer allocator.free(argv);

        var argc: usize = 0;
        argv[argc] = binary_path;
        argc += 1;
        argv[argc] = "-lib";
        argc += 1;
        argv[argc] = "./miralib";
        argc += 1;
        argv[argc] = "-hush";
        argc += 1;
        if (m_exists) {
            argv[argc] = m_path;
            argc += 1;
        }

        var child = try std.process.spawn(ctx.io, .{
            .argv = argv[0..argc],
            .stdin = .pipe,
            .stdout = .pipe,
            .stderr = .pipe,
        });
        errdefer child.kill(ctx.io);

        child.stdin.?.writeStreamingAll(ctx.io, stdin_content) catch {};
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

        const term = try child.wait(ctx.io);

        if (m_exists) {
            std.Io.Dir.cwd().deleteFile(ctx.io, x_path) catch {};
        }

        const raw_stdout = try multi_reader.toOwnedSlice(0);
        defer allocator.free(raw_stdout);
        const raw_stderr = try multi_reader.toOwnedSlice(1);
        defer allocator.free(raw_stderr);

        const combined_len = raw_stdout.len + raw_stderr.len;
        const combined = try allocator.alloc(u8, combined_len);
        defer allocator.free(combined);
        std.mem.copyForwards(u8, combined[0..raw_stdout.len], raw_stdout);
        std.mem.copyForwards(u8, combined[raw_stdout.len..], raw_stderr);

        const exit_code = switch (term) {
            .exited => |c| @as(i32, @intCast(c)),
            else => -1,
        };

        if (exit_code < 0 or checkCrash(combined)) {
            std.debug.print("Spine differential check: golden/{s} ... FAIL\n", .{name});
            std.debug.print("  exit code: {d}\n", .{exit_code});
            std.debug.print("  output: {s}\n", .{combined[if (combined.len > 2000) combined.len - 2000 else 0..]});
            failed = true;
        } else {
            std.debug.print("Spine differential check: golden/{s} ... PASS\n", .{name});
        }
    }

    // 2. EX corpus stress check
    for (EX_CORPUS) |item| {
        const script_exists = if (std.Io.Dir.cwd().statFile(ctx.io, item.script, .{})) |_| true else |_| false;
        if (!script_exists) {
            std.debug.print("Spine differential check: {s} ... SKIP (not found)\n", .{item.script});
            continue;
        }

        var x_path_buf: [256]u8 = undefined;
        const base_len = item.script.len - 2; // strip ".m"
        std.mem.copyForwards(u8, x_path_buf[0..base_len], item.script[0..base_len]);
        std.mem.copyForwards(u8, x_path_buf[base_len .. base_len + 2], ".x");
        const x_path = x_path_buf[0 .. base_len + 2];

        std.Io.Dir.cwd().deleteFile(ctx.io, x_path) catch {};

        var stdin_content_buf: [512]u8 = undefined;
        const stdin_content = std.fmt.bufPrint(&stdin_content_buf, "{s}\n\n/q\n", .{item.expr}) catch "";

        var argv = try allocator.alloc([]const u8, 5);
        defer allocator.free(argv);

        argv[0] = binary_path;
        argv[1] = "-lib";
        argv[2] = "./miralib";
        argv[3] = "-hush";
        argv[4] = item.script;

        var child = try std.process.spawn(ctx.io, .{
            .argv = argv,
            .stdin = .pipe,
            .stdout = .pipe,
            .stderr = .pipe,
        });
        errdefer child.kill(ctx.io);

        child.stdin.?.writeStreamingAll(ctx.io, stdin_content) catch {};
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

        const term = try child.wait(ctx.io);

        std.Io.Dir.cwd().deleteFile(ctx.io, x_path) catch {};

        const raw_stdout = try multi_reader.toOwnedSlice(0);
        defer allocator.free(raw_stdout);
        const raw_stderr = try multi_reader.toOwnedSlice(1);
        defer allocator.free(raw_stderr);

        const combined_len = raw_stdout.len + raw_stderr.len;
        const combined = try allocator.alloc(u8, combined_len);
        defer allocator.free(combined);
        std.mem.copyForwards(u8, combined[0..raw_stdout.len], raw_stdout);
        std.mem.copyForwards(u8, combined[raw_stdout.len..], raw_stderr);

        const exit_code = switch (term) {
            .exited => |c| @as(i32, @intCast(c)),
            else => -1,
        };

        if (exit_code < 0 or checkCrash(combined)) {
            std.debug.print("Spine differential check: {s} : {s} ... FAIL\n", .{item.script, item.expr});
            std.debug.print("  exit code: {d}\n", .{exit_code});
            std.debug.print("  output: {s}\n", .{combined[if (combined.len > 2000) combined.len - 2000 else 0..]});
            failed = true;
        } else {
            std.debug.print("Spine differential check: {s} : {s} ... PASS\n", .{item.script, item.expr});
        }
    }

    if (failed) {
        std.debug.print("Spine stress check FAILED -- see the crash/hang above.\n", .{});
        std.process.exit(1);
    } else {
        std.debug.print("All spine stress checks passed -- clean exit across miralib/ex programs and the golden corpus.\n", .{});
        std.process.exit(0);
    }
}
