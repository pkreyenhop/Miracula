const std = @import("std");

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

    const golden_dir = "./tests/golden";
    var dir = std.Io.Dir.cwd().openDir(ctx.io, golden_dir, .{ .iterate = true }) catch {
        std.debug.print("Error: Golden directory {s} not found.\n", .{golden_dir});
        std.process.exit(1);
    };
    defer dir.close(ctx.io);

    var iter = dir.iterate();
    while (try iter.next(ctx.io)) |entry| {
        if (std.mem.endsWith(u8, entry.name, ".in")) {
            const name = entry.name[0 .. entry.name.len - 3]; // strip ".in"
            std.debug.print("Generating golden files for: {s} ...\n", .{name});

            var script_path_buf: [256]u8 = undefined;
            const script_path = std.fmt.bufPrint(&script_path_buf, "tests/golden/{s}.m", .{name}) catch "";
            const script_exists = if (std.Io.Dir.cwd().statFile(ctx.io, script_path, .{})) |_| true else |_| false;

            var in_path_buf: [256]u8 = undefined;
            const in_path = std.fmt.bufPrint(&in_path_buf, "tests/golden/{s}.in", .{name}) catch "";

            const stdin_content = try std.Io.Dir.cwd().readFileAlloc(ctx.io, in_path, allocator, .limited(1024 * 1024));
            defer allocator.free(stdin_content);

            const argv_len = 4 + if (script_exists) @as(usize, 1) else 0;
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

            _ = try child.wait(ctx.io);

            const raw_stdout = try multi_reader.toOwnedSlice(0);
            defer allocator.free(raw_stdout);
            const raw_stderr = try multi_reader.toOwnedSlice(1);
            defer allocator.free(raw_stderr);

            const actual_stdout = try cleanOutput(allocator, raw_stdout);
            defer allocator.free(actual_stdout);
            const actual_stderr = try cleanOutput(allocator, raw_stderr);
            defer allocator.free(actual_stderr);

            // Write expected stdout
            var out_path_buf: [256]u8 = undefined;
            const out_path = std.fmt.bufPrint(&out_path_buf, "tests/golden/{s}.expected", .{name}) catch "";
            const out_file = try std.Io.Dir.cwd().createFile(ctx.io, out_path, .{});
            try out_file.writeStreamingAll(ctx.io, actual_stdout);
            if (actual_stdout.len > 0) {
                try out_file.writeStreamingAll(ctx.io, "\n");
            }
            out_file.close(ctx.io);

            // Write expected stderr if any
            var err_path_buf: [256]u8 = undefined;
            const err_path = std.fmt.bufPrint(&err_path_buf, "tests/golden/{s}.expected_err", .{name}) catch "";
            if (actual_stderr.len > 0) {
                const err_file = try std.Io.Dir.cwd().createFile(ctx.io, err_path, .{});
                try err_file.writeStreamingAll(ctx.io, actual_stderr);
                try err_file.writeStreamingAll(ctx.io, "\n");
                err_file.close(ctx.io);
            } else {
                std.Io.Dir.cwd().deleteFile(ctx.io, err_path) catch {};
            }
        }
    }
}
