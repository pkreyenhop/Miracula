const std = @import("std");

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

    const fib_path = "tests/sigint_corpus/slow_fib.m";

    var argv = try allocator.alloc([]const u8, 5);
    defer allocator.free(argv);

    argv[0] = binary_path;
    argv[1] = "-lib";
    argv[2] = "./miralib";
    argv[3] = "-hush";
    argv[4] = fib_path;

    var child = try std.process.spawn(ctx.io, .{
        .argv = argv,
        .stdin = .pipe,
        .stdout = .pipe,
        .stderr = .pipe,
        .pgid = 0,
    });
    errdefer child.kill(ctx.io);

    // Write fib 32
    try child.stdin.?.writeStreamingAll(ctx.io, "fib 32\n\n");

    // Sleep 300ms so child starts reducing
    try ctx.io.sleep(std.Io.Duration{ .nanoseconds = 300 * 1000 * 1000 }, .real);

    // Send SIGINT to the process group
    try std.posix.kill(-child.id.?, std.posix.SIG.INT);

    // Sleep 300ms
    try ctx.io.sleep(std.Io.Duration{ .nanoseconds = 300 * 1000 * 1000 }, .real);

    // Write more input
    try child.stdin.?.writeStreamingAll(ctx.io, "2 + 2\n\n/q\n");
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

    const term = try child.wait(ctx.io);

    const stdout_text = try multi_reader.toOwnedSlice(0);
    defer allocator.free(stdout_text);
    const stderr_text = try multi_reader.toOwnedSlice(1);
    defer allocator.free(stderr_text);

    if (std.mem.indexOf(u8, stderr_text, "<<...interrupt>>") == null) {
        std.debug.print("FAIL: expected interrupt notice not seen in stderr\n", .{});
        std.debug.print("--- stderr ---\n{s}\n", .{stderr_text});
        std.process.exit(1);
    }

    if (std.mem.indexOf(u8, stdout_text, "4") == null) {
        std.debug.print("FAIL: parent REPL did not survive to evaluate '2 + 2' after the interrupt\n", .{});
        std.debug.print("--- stdout ---\n{s}\n", .{stdout_text});
        std.process.exit(1);
    }

    switch (term) {
        .exited => |code| {
            if (code != 0) {
                std.debug.print("FAIL: mira exited with code {d} instead of 0\n", .{code});
                std.process.exit(1);
            }
        },
        else => {
            std.debug.print("FAIL: mira did not exit cleanly\n", .{});
            std.process.exit(1);
        },
    }

    std.debug.print("PASS: SIGINT during reduction killed only the forked child; parent REPL survived and kept evaluating.\n", .{});
}
