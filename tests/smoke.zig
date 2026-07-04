const std = @import("std");

fn repeatChar(allocator: std.mem.Allocator, char: u8, count: usize) ![]const u8 {
    const buf = try allocator.alloc(u8, count);
    @memset(buf, char);
    return buf;
}

fn writeCompileStressScript(io: std.Io, path: []const u8, items: usize) !void {
    const file = try std.Io.Dir.cwd().createFile(io, path, .{});
    defer file.close(io);

    try file.writeStreamingAll(io, "stress_list\n=[\n");
    var i: usize = 0;
    while (i < items) : (i += 1) {
        var buf: [64]u8 = undefined;
        const line = try std.fmt.bufPrint(&buf, "  \"compile-time-stress-{d:0>4}\",\n", .{i});
        try file.writeStreamingAll(io, line);
    }
    try file.writeStreamingAll(io, "  \"compile-time-stress-end\"]\nstress_len = # stress_list\n");
}

fn run_mira(
    allocator: std.mem.Allocator,
    io: std.Io,
    env_map: *const std.process.Environ.Map,
    binary_path: []const u8,
    name: []const u8,
    script: ?[]const u8,
    input: []const u8,
    expected: []const u8,
) !void {
    const argv_len = 5 + if (script != null) @as(usize, 1) else 0;
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
    if (script) |s| {
        argv[argc] = s;
        argc += 1;
    }

    var child = try std.process.spawn(io, .{
        .argv = argv[0..argc],
        .stdin = .pipe,
        .stdout = .pipe,
        .stderr = .pipe,
        .environ_map = env_map,
    });
    errdefer child.kill(io);

    child.stdin.?.writeStreamingAll(io, input) catch {};
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

    _ = try child.wait(io);

    const stdout_text = try multi_reader.toOwnedSlice(0);
    defer allocator.free(stdout_text);

    const actual = std.mem.trim(u8, stdout_text, " \t\r\n");
    const expected_trimmed = std.mem.trim(u8, expected, " \t\r\n");

    if (!std.mem.eql(u8, actual, expected_trimmed)) {
        std.debug.print("FAIL: {s}\n", .{name});
        std.debug.print("expected:\n{s}\n", .{expected_trimmed});
        std.debug.print("got:\n{s}\n", .{actual});
        std.process.exit(1);
    }
}

fn run_mira_expect_stderr(
    allocator: std.mem.Allocator,
    io: std.Io,
    env_map: *const std.process.Environ.Map,
    binary_path: []const u8,
    name: []const u8,
    script: ?[]const u8,
    input: []const u8,
    expected_output: []const u8,
    expected_stderr: []const u8,
    extra_args: []const []const u8,
) !void {
    const argv_len = 5 + (if (script != null) @as(usize, 1) else 0) + extra_args.len;
    var argv = try allocator.alloc([]const u8, argv_len);
    defer allocator.free(argv);

    var argc: usize = 0;
    argv[argc] = binary_path;
    argc += 1;
    for (extra_args) |arg| {
        argv[argc] = arg;
        argc += 1;
    }
    argv[argc] = "-lib";
    argc += 1;
    argv[argc] = "./miralib";
    argc += 1;
    argv[argc] = "-hush";
    argc += 1;
    if (script) |s| {
        argv[argc] = s;
        argc += 1;
    }

    var child = try std.process.spawn(io, .{
        .argv = argv[0..argc],
        .stdin = .pipe,
        .stdout = .pipe,
        .stderr = .pipe,
        .environ_map = env_map,
    });
    errdefer child.kill(io);

    child.stdin.?.writeStreamingAll(io, input) catch {};
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
    const code = switch (term) {
        .exited => |c| c,
        else => 1,
    };
    if (code != 0) {
        std.debug.print("FAIL: {s} exited with status {d}\n", .{name, code});
        std.process.exit(1);
    }

    const stdout_text = try multi_reader.toOwnedSlice(0);
    defer allocator.free(stdout_text);
    const stderr_text = try multi_reader.toOwnedSlice(1);
    defer allocator.free(stderr_text);

    const actual_stdout = std.mem.trim(u8, stdout_text, " \t\r\n");
    const expected_out_trimmed = std.mem.trim(u8, expected_output, " \t\r\n");

    if (!std.mem.eql(u8, actual_stdout, expected_out_trimmed)) {
        std.debug.print("FAIL: {s} stdout mismatch\n", .{name});
        std.debug.print("expected:\n{s}\n", .{expected_out_trimmed});
        std.debug.print("got:\n{s}\n", .{actual_stdout});
        std.process.exit(1);
    }

    if (std.mem.indexOf(u8, stderr_text, expected_stderr) == null) {
        std.debug.print("FAIL: {s} expected stderr to contain '{s}'\n", .{name, expected_stderr});
        std.debug.print("got stderr:\n{s}\n", .{stderr_text});
        std.process.exit(1);
    }
}

fn run_compile_time_guard(
    allocator: std.mem.Allocator,
    io: std.Io,
    env_map: *const std.process.Environ.Map,
    binary_path: []const u8,
    name: []const u8,
    script: []const u8,
) !void {
    const argv = &[_][]const u8{
        binary_path,
        "-lib",
        "./miralib",
        "-hush",
        "-make",
        script,
    };

    var child = try std.process.spawn(io, .{
        .argv = argv,
        .stdin = .pipe,
        .stdout = .pipe,
        .stderr = .pipe,
        .environ_map = env_map,
    });
    errdefer child.kill(io);

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
    const code = switch (term) {
        .exited => |c| c,
        else => 1,
    };
    if (code != 0) {
        const raw_stderr = try multi_reader.toOwnedSlice(1);
        defer allocator.free(raw_stderr);
        std.debug.print("FAIL: {s} failed to compile, exit code {d}\n", .{name, code});
        std.debug.print("stderr:\n{s}\n", .{raw_stderr});
        std.process.exit(1);
    }
}

fn run_standard_lib_load_guard(
    allocator: std.mem.Allocator,
    io: std.Io,
    env_map: *const std.process.Environ.Map,
    binary_path: []const u8,
    name: []const u8,
) !void {
    const input = "product [1..10]\nreverse [1,2,3]\n\"abc\" ++ \"def\"\n/q\n";
    const expected = "3628800\n[3,2,1]\nabcdef";

    const argv = &[_][]const u8{
        binary_path,
        "-lib",
        "./miralib",
        "-hush",
    };

    var child = try std.process.spawn(io, .{
        .argv = argv,
        .stdin = .pipe,
        .stdout = .pipe,
        .stderr = .pipe,
        .environ_map = env_map,
    });
    errdefer child.kill(io);

    child.stdin.?.writeStreamingAll(io, input) catch {};
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

    _ = try child.wait(io);

    const stdout_text = try multi_reader.toOwnedSlice(0);
    defer allocator.free(stdout_text);

    const actual = std.mem.trim(u8, stdout_text, " \t\r\n");
    const expected_trimmed = std.mem.trim(u8, expected, " \t\r\n");

    if (!std.mem.eql(u8, actual, expected_trimmed)) {
        std.debug.print("FAIL: {s}\n", .{name});
        std.debug.print("expected:\n{s}\n", .{expected_trimmed});
        std.debug.print("got:\n{s}\n", .{actual});
        std.process.exit(1);
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

    _ = std.Io.Dir.cwd().statFile(ctx.io, binary_path, .{}) catch {
        std.debug.print("Error: Binary {s} not found.\n", .{binary_path});
        std.process.exit(1);
    };

    // Setup temp home and work directories
    std.Io.Dir.cwd().createDirPath(ctx.io, "./tests/golden/tmp_smoke_home") catch {};
    std.Io.Dir.cwd().createDirPath(ctx.io, "./tests/golden/tmp_smoke_work") catch {};
    defer {
        std.Io.Dir.cwd().deleteTree(ctx.io, "./tests/golden/tmp_smoke_home") catch {};
        std.Io.Dir.cwd().deleteTree(ctx.io, "./tests/golden/tmp_smoke_work") catch {};
    }

    const home_abs = try std.Io.Dir.cwd().realPathFileAlloc(ctx.io, "./tests/golden/tmp_smoke_home", allocator);
    defer allocator.free(home_abs);

    var env_map = std.process.Environ.Map.init(allocator);
    defer env_map.deinit();
    try env_map.put("HOME", home_abs);

    std.debug.print("Running smoke tests...\n", .{});

    try run_mira(allocator, ctx.io, &env_map, binary_path, "standard arithmetic and lists", null,
        \\1+2
        \\product [1..10]
        \\map (2*) [1..5]
        \\/q
        \\
    ,
        \\3
        \\3628800
        \\[2,4,6,8,10]
    );

    try run_mira(allocator, ctx.io, &env_map, binary_path, "big integers", null,
        \\12345678901234567890 + 10
        \\2^80
        \\/q
        \\
    ,
        \\12345678901234567900
        \\1208925819614629174706176
    );

    try run_mira(allocator, ctx.io, &env_map, binary_path, "lazy lists and strings", null,
        \\take 5 [1..]
        \\reverse [1,2,3]
        \\zip2 [1,2,3] [4,5,6]
        \\"abc" ++ "def"
        \\/q
        \\
    ,
        \\[1,2,3,4,5]
        \\[3,2,1]
        \\[(1,4),(2,5),(3,6)]
        \\abcdef
    );

    try run_mira(allocator, ctx.io, &env_map, binary_path, "example script fib", "miralib/ex/fib.m",
        \\fib 10
        \\/q
        \\
    , "55");

    // Write user-defs.m
    const user_defs_path = "./tests/golden/tmp_smoke_work/user-defs.m";
    const user_defs_file = try std.Io.Dir.cwd().createFile(ctx.io, user_defs_path, .{});
    try user_defs_file.writeStreamingAll(ctx.io,
        \\square x = x*x
        \\twice f x = f (f x)
        \\pairup x y = (x,y)
        \\
    );
    user_defs_file.close(ctx.io);
    defer std.Io.Dir.cwd().deleteFile(ctx.io, user_defs_path) catch {};

    try run_mira(allocator, ctx.io, &env_map, binary_path, "user script definitions", user_defs_path,
        \\square 12
        \\twice square 2
        \\pairup "a" [1,2]
        \\/q
        \\
    ,
        \\144
        \\16
        \\("a",[1,2])
    );

    try run_mira(allocator, ctx.io, &env_map, binary_path, "type error reporting", null,
        \\1 + "x"
        \\/q
        \\
    ,
        \\type error in expression
        \\cannot unify [char] with num
    );

    try run_mira(allocator, ctx.io, &env_map, binary_path, "syntax error reporting", null,
        \\1 +
        \\/q
        \\
    , "syntax error - unexpected newline");

    const long_string = try repeatChar(allocator, 'a', 4096);
    defer allocator.free(long_string);
    const long_integer = try repeatChar(allocator, '9', 512);
    defer allocator.free(long_integer);
    const long_integer_plus_one_body = try repeatChar(allocator, '0', 512);
    defer allocator.free(long_integer_plus_one_body);

    var long_input_buf: [10240]u8 = undefined;
    const long_input = try std.fmt.bufPrint(&long_input_buf,
        \\# "{s}"
        \\{s} + 1
        \\/q
        \\
    , .{ long_string, long_integer });

    var long_expected_buf: [1024]u8 = undefined;
    const long_expected = try std.fmt.bufPrint(&long_expected_buf,
        \\4096
        \\1{s}
    , .{long_integer_plus_one_body});

    try run_mira(allocator, ctx.io, &env_map, binary_path, "very long literals", null, long_input, long_expected);

    // Compile stress checks
    const compile_stress_path = "./tests/golden/tmp_smoke_work/compile-stress.m";
    try writeCompileStressScript(ctx.io, compile_stress_path, 1500);
    defer std.Io.Dir.cwd().deleteFile(ctx.io, compile_stress_path) catch {};

    try run_compile_time_guard(allocator, ctx.io, &env_map, binary_path, "compile time stress guard", compile_stress_path);
    try run_standard_lib_load_guard(allocator, ctx.io, &env_map, binary_path, "standard lib load speed guard");

    const compile_gc_stress_path = "./tests/golden/tmp_smoke_work/compile-gc-stress.m";
    try writeCompileStressScript(ctx.io, compile_gc_stress_path, 600);
    defer std.Io.Dir.cwd().deleteFile(ctx.io, compile_gc_stress_path) catch {};

    try run_mira_expect_stderr(allocator, ctx.io, &env_map, binary_path, "compile-gc-stress", compile_gc_stress_path,
        \\stress_len
        \\/q
        \\
    , "601", "<<gc after", &.{ "-heap", "25000", "-gc" });

    try run_mira_expect_stderr(allocator, ctx.io, &env_map, binary_path, "runtime-gc-stress", null,
        \\sum [1..4000]
        \\/q
        \\
    , "8002000", "<<gc after", &.{ "-heap", "12000", "-gc" });

    std.debug.print("smoke tests passed successfully\n", .{});
}
