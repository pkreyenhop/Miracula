const std = @import("std");

fn sortLess(context: void, lhs: []const u8, rhs: []const u8) bool {
    _ = context;
    return std.mem.lessThan(u8, lhs, rhs);
}

fn cleanOutput(allocator: std.mem.Allocator, text: []const u8) ![]const u8 {
    var list: std.ArrayList([]const u8) = .empty;
    defer list.deinit(allocator);
    var iter = std.mem.splitScalar(u8, text, '\n');
    while (iter.next()) |line| {
        if (std.mem.startsWith(u8, line, "||reductions =") or
            std.mem.startsWith(u8, line, "[TRACE]") or
            std.mem.startsWith(u8, line, "[ALLOC]") or
            std.mem.startsWith(u8, line, "[DIAG"))
        {
            continue;
        }
        try list.append(allocator, line);
    }
    
    var total_len: usize = 0;
    for (list.items) |line| {
        total_len += line.len;
    }
    if (list.items.len > 0) {
        total_len += list.items.len - 1;
    }
    
    const joined = try allocator.alloc(u8, total_len);
    errdefer allocator.free(joined);
    var offset: usize = 0;
    for (list.items, 0..) |line, idx| {
        std.mem.copyForwards(u8, joined[offset..], line);
        offset += line.len;
        if (idx < list.items.len - 1) {
            joined[offset] = '\n';
            offset += 1;
        }
    }
    
    const trimmed = std.mem.trim(u8, joined, " \t\r\n");
    const result = try allocator.dupe(u8, trimmed);
    allocator.free(joined);
    return result;
}

fn printDiff(allocator: std.mem.Allocator, expected: []const u8, actual: []const u8) !void {
    var exp_lines: std.ArrayList([]const u8) = .empty;
    defer exp_lines.deinit(allocator);
    var exp_iter = std.mem.splitScalar(u8, expected, '\n');
    while (exp_iter.next()) |line| {
        try exp_lines.append(allocator, line);
    }

    var act_lines: std.ArrayList([]const u8) = .empty;
    defer act_lines.deinit(allocator);
    var act_iter = std.mem.splitScalar(u8, actual, '\n');
    while (act_iter.next()) |line| {
        try act_lines.append(allocator, line);
    }

    var i: usize = 0;
    var j: usize = 0;
    while (i < exp_lines.items.len or j < act_lines.items.len) {
        if (i < exp_lines.items.len and j < act_lines.items.len) {
            if (std.mem.eql(u8, exp_lines.items[i], act_lines.items[j])) {
                std.debug.print("  {s}\n", .{exp_lines.items[i]});
                i += 1;
                j += 1;
            } else {
                std.debug.print("- {s}\n", .{exp_lines.items[i]});
                std.debug.print("+ {s}\n", .{act_lines.items[j]});
                i += 1;
                j += 1;
            }
        } else if (i < exp_lines.items.len) {
            std.debug.print("- {s}\n", .{exp_lines.items[i]});
            i += 1;
        } else {
            std.debug.print("+ {s}\n", .{act_lines.items[j]});
            j += 1;
        }
    }
}

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

    const golden_dir = "./tests/golden";
    var dir = std.Io.Dir.cwd().openDir(ctx.io, golden_dir, .{ .iterate = true }) catch {
        std.debug.print("Error: Golden directory {s} not found.\n", .{golden_dir});
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

    if (expected_files.items.len == 0) {
        std.debug.print("Error: No expected files found.\n", .{});
        std.process.exit(1);
    }

    std.mem.sort([]const u8, expected_files.items, {}, sortLess);

    var failed = false;
    for (expected_files.items) |ef| {
        const name = ef[0 .. ef.len - 9]; // strip ".expected"
        std.debug.print("Verifying golden test: {s} ... ", .{name});

        var script_path_buf: [256]u8 = undefined;
        const script_path = std.fmt.bufPrint(&script_path_buf, "tests/golden/{s}.m", .{name}) catch "";
        const script_exists = if (std.Io.Dir.cwd().statFile(ctx.io, script_path, .{})) |_| true else |_| false;

        var in_path_buf: [256]u8 = undefined;
        const in_path = std.fmt.bufPrint(&in_path_buf, "tests/golden/{s}.in", .{name}) catch "";
        const in_exists = if (std.Io.Dir.cwd().statFile(ctx.io, in_path, .{})) |_| true else |_| false;

        if (!in_exists) {
            std.debug.print("FAIL (missing {s}.in)\n", .{name});
            failed = true;
            continue;
        }

        const stdin_content = std.Io.Dir.cwd().readFileAlloc(ctx.io, in_path, allocator, .limited(1024 * 1024)) catch |err| {
            std.debug.print("FAIL (failed to read stdin: {any})\n", .{err});
            failed = true;
            continue;
        };
        defer allocator.free(stdin_content);

        var ef_path_buf: [256]u8 = undefined;
        const ef_path = std.fmt.bufPrint(&ef_path_buf, "tests/golden/{s}.expected", .{name}) catch "";
        const expected_stdout = std.Io.Dir.cwd().readFileAlloc(ctx.io, ef_path, allocator, .limited(1024 * 1024)) catch |err| {
            std.debug.print("FAIL (failed to read expected stdout: {any})\n", .{err});
            failed = true;
            continue;
        };
        defer allocator.free(expected_stdout);
        const expected_stdout_trimmed = std.mem.trim(u8, expected_stdout, " \t\r\n");

        var expected_stderr_path_buf: [256]u8 = undefined;
        const expected_stderr_path = std.fmt.bufPrint(&expected_stderr_path_buf, "tests/golden/{s}.expected_err", .{name}) catch "";
        const expected_stderr_exists = if (std.Io.Dir.cwd().statFile(ctx.io, expected_stderr_path, .{})) |_| true else |_| false;

        var expected_stderr: []const u8 = "";
        var expected_stderr_alloc: ?[]const u8 = null;
        if (expected_stderr_exists) {
            const data = std.Io.Dir.cwd().readFileAlloc(ctx.io, expected_stderr_path, allocator, .limited(1024 * 1024)) catch |err| {
                std.debug.print("FAIL (failed to read expected stderr: {any})\n", .{err});
                failed = true;
                continue;
            };
            expected_stderr_alloc = data;
            expected_stderr = std.mem.trim(u8, data, " \t\r\n");
        }
        defer if (expected_stderr_alloc) |data| allocator.free(data);

        // Run mira
        const argv_len = 5 + if (script_exists) @as(usize, 1) else 0;
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
        if (script_exists) {
            argv[argc] = script_path;
            argc += 1;
        }

        var child = std.process.spawn(ctx.io, .{
            .argv = argv[0..argc],
            .stdin = .pipe,
            .stdout = .pipe,
            .stderr = .pipe,
        }) catch |err| {
            std.debug.print("FAIL (failed to spawn: {any})\n", .{err});
            failed = true;
            continue;
        };
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
            else => |e| {
                std.debug.print("FAIL (failed to read: {any})\n", .{e});
                failed = true;
                continue;
            },
        }

        _ = child.wait(ctx.io) catch {};

        const raw_stdout = try multi_reader.toOwnedSlice(0);
        defer allocator.free(raw_stdout);
        const raw_stderr = try multi_reader.toOwnedSlice(1);
        defer allocator.free(raw_stderr);

        const actual_stdout = try cleanOutput(allocator, raw_stdout);
        defer allocator.free(actual_stdout);
        const actual_stderr = try cleanOutput(allocator, raw_stderr);
        defer allocator.free(actual_stderr);

        if (!std.mem.eql(u8, actual_stdout, expected_stdout_trimmed)) {
            std.debug.print("FAIL (stdout mismatch)\n", .{});
            std.debug.print("Diff:\n", .{});
            try printDiff(allocator, expected_stdout_trimmed, actual_stdout);
            failed = true;
            continue;
        }

        if (!std.mem.eql(u8, actual_stderr, expected_stderr)) {
            std.debug.print("FAIL (stderr mismatch)\n", .{});
            std.debug.print("Expected stderr:\n{s}\n", .{expected_stderr});
            std.debug.print("Actual stderr:\n{s}\n", .{actual_stderr});
            failed = true;
            continue;
        }

        std.debug.print("PASS\n", .{});
    }

    if (failed) {
        std.debug.print("Golden verification failed.\n", .{});
        std.process.exit(1);
    } else {
        std.debug.print("All golden verification tests passed successfully!\n", .{});
        std.process.exit(0);
    }
}
