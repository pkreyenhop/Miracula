const std = @import("std");
const testing = std.testing;
const build_options = @import("build_options");

const allocator = testing.allocator;

const TestEnv = struct {
    home: []u8,
    work: []u8,

    fn init() !TestEnv {
        var random: [8]u8 = undefined;
        testing.io.random(&random);
        const home = try std.fmt.allocPrint(allocator, "/tmp/mira-test-{x}", .{std.mem.readInt(u64, &random, .little)});
        errdefer allocator.free(home);
        testing.io.random(&random);
        const work = try std.fmt.allocPrint(allocator, "/tmp/mira-work-{x}", .{std.mem.readInt(u64, &random, .little)});
        errdefer allocator.free(work);
        try std.Io.Dir.createDirAbsolute(testing.io, home, .default_dir);
        errdefer std.Io.Dir.cwd().deleteTree(testing.io, home) catch {};
        try std.Io.Dir.createDirAbsolute(testing.io, work, .default_dir);
        return .{ .home = home, .work = work };
    }

    fn deinit(self: *TestEnv) void {
        std.Io.Dir.cwd().deleteTree(testing.io, self.home) catch {};
        std.Io.Dir.cwd().deleteTree(testing.io, self.work) catch {};
        allocator.free(self.home);
        allocator.free(self.work);
    }
};

const RunResult = struct {
    term: std.process.Child.Term,
    stdout: []u8,
    stderr: []u8,

    fn deinit(self: *RunResult) void {
        allocator.free(self.stdout);
        allocator.free(self.stderr);
    }
};

fn runMira(env: *const TestEnv, script: ?[]const u8, input: []const u8, extra_args: []const []const u8) !RunResult {
    const argv_len = 1 + extra_args.len + 3 + if (script != null and script.?.len > 0) @as(usize, 1) else 0;
    var argv = try allocator.alloc([]const u8, argv_len);
    defer allocator.free(argv);

    var argc: usize = 0;
    argv[argc] = build_options.mira_path;
    argc += 1;
    for (extra_args) |arg| {
        argv[argc] = arg;
        argc += 1;
    }
    argv[argc] = "-lib";
    argc += 1;
    argv[argc] = build_options.lib_path;
    argc += 1;
    argv[argc] = "-hush";
    argc += 1;
    if (script) |script_path| {
        if (script_path.len > 0) {
            argv[argc] = script_path;
            argc += 1;
        }
    }

    var env_map = std.process.Environ.Map.init(allocator);
    defer env_map.deinit();
    try env_map.put("HOME", env.home);

    var child = try std.process.spawn(testing.io, .{
        .argv = argv,
        .environ_map = &env_map,
        .stdin = .pipe,
        .stdout = .pipe,
        .stderr = .pipe,
    });
    errdefer child.kill(testing.io);

    try child.stdin.?.writeStreamingAll(testing.io, input);
    child.stdin.?.close(testing.io);
    child.stdin = null;

    var multi_reader_buffer: std.Io.File.MultiReader.Buffer(2) = undefined;
    var multi_reader: std.Io.File.MultiReader = undefined;
    multi_reader.init(allocator, testing.io, multi_reader_buffer.toStreams(), &.{ child.stdout.?, child.stderr.? });
    defer multi_reader.deinit();

    const timeout = std.Io.Timeout{ .duration = .{ .raw = std.Io.Duration.fromSeconds(10), .clock = .real } };
    while (multi_reader.fill(64, timeout)) |_| {
        if (multi_reader.reader(0).buffered().len > 1024 * 1024 or multi_reader.reader(1).buffered().len > 1024 * 1024) {
            return error.StreamTooLong;
        }
    } else |err| switch (err) {
        error.EndOfStream => {},
        error.Timeout => {
            child.kill(testing.io);
            _ = try child.wait(testing.io);
            return error.Timeout;
        },
        else => |e| return e,
    }
    try multi_reader.checkAnyError();

    const term = try child.wait(testing.io);
    var stdout_text = try multi_reader.toOwnedSlice(0);
    stdout_text = try chompStdout(stdout_text);
    const stderr_text = try multi_reader.toOwnedSlice(1);

    return .{ .term = term, .stdout = stdout_text, .stderr = stderr_text };
}

fn chompStdout(text: []u8) ![]u8 {
    var len = text.len;
    while (len > 0 and text[len - 1] == '\n') {
        len -= 1;
    }
    if (len == text.len) {
        return text;
    }
    const trimmed = try allocator.realloc(text, len);
    return trimmed;
}

fn assertSuccessOutput(name: []const u8, result: *const RunResult, expected: []const u8) !void {
    try assertSuccessStatus(name, result);
    try testing.expectEqualStrings(expected, result.stdout);
}

fn assertSuccessStatus(name: []const u8, result: *const RunResult) !void {
    switch (result.term) {
        .exited => |code| {
            if (code != 0) {
                std.debug.print("{s} exited with {d}\nstdout:\n{s}\nstderr:\n{s}\n", .{
                    name,
                    code,
                    result.stdout,
                    result.stderr,
                });
                return error.TestExpectedSuccess;
            }
        },
        else => {
            std.debug.print("{s} did not exit normally: {any}\nstdout:\n{s}\nstderr:\n{s}\n", .{ name, result.term, result.stdout, result.stderr });
            return error.TestExpectedSuccess;
        },
    }
}

fn repeatChar(count: usize, value: u8) ![]u8 {
    const buffer = try allocator.alloc(u8, count);
    @memset(buffer, value);
    return buffer;
}

fn writeFile(path: []const u8, contents: []const u8) !void {
    const file = try std.Io.Dir.createFileAbsolute(testing.io, path, .{});
    defer file.close(testing.io);
    try file.writeStreamingAll(testing.io, contents);
}

fn writeCompileStressScript(path: []const u8, items: usize) !void {
    const file = try std.Io.Dir.createFileAbsolute(testing.io, path, .{});
    defer file.close(testing.io);
    try file.writeStreamingAll(testing.io, "stress_list\n=[\n");
    for (0..items) |i| {
        const line = try std.fmt.allocPrint(allocator, "  \"compile-time-stress-{d:0>4}\",\n", .{i});
        defer allocator.free(line);
        try file.writeStreamingAll(testing.io, line);
    }
    try file.writeStreamingAll(testing.io, "  \"compile-time-stress-end\"]\nstress_len = # stress_list\n");
}

test "mira integration suite" {
    try caseStandardArithmeticAndLists();
    try caseBigIntegers();
    try caseBigIntegerSignsDivisionAndBases();
    try caseDivModLaws();
    try caseLazyListsAndStrings();
    try caseExampleScriptFib();
    try caseUserScriptDefinitions();
    try caseTypeErrorReporting();
    try caseSyntaxErrorReporting();
    try caseVeryLongLiterals();
    try caseCompileTimeStressGuard();
    try caseStandardLibLoadSpeedGuard();
    try caseCompileGcStress();
    try caseRuntimeGcStress();
    try caseMakeFailureLongPath();
    try caseSyntaxErrorRepeat();
}

fn caseStandardArithmeticAndLists() !void {
    var env = try TestEnv.init();
    defer env.deinit();
    var result = try runMira(&env, "", "1+2\nproduct [1..10]\nmap (2*) [1..5]\n/q\n", &.{});
    defer result.deinit();
    try assertSuccessOutput("standard arithmetic and lists", &result, "3\n3628800\n[2,4,6,8,10]");
}

fn caseBigIntegers() !void {
    var env = try TestEnv.init();
    defer env.deinit();
    var result = try runMira(&env, "", "12345678901234567890 + 10\n2^80\n/q\n", &.{});
    defer result.deinit();
    try assertSuccessOutput("big integers", &result, "12345678901234567900\n1208925819614629174706176");
}

fn caseBigIntegerSignsDivisionAndBases() !void {
    var env = try TestEnv.init();
    defer env.deinit();
    var result = try runMira(
        &env,
        "",
        "(-12345678901234567890) + 12345678901234567880\n" ++
            "(-12345678901234567890) * 9\n" ++
            "(-12345678901234567890) div 97\n" ++
            "(-12345678901234567890) mod 97\n" ++
            "12345678901234567890 > 12345678901234567889\n" ++
            "showhex 12345678901234567890\n" ++
            "showoct 0\n" ++
            "numval \"0xab54a98ceb1f0ad2\"\n" ++
            "/q\n",
        &.{},
    );
    defer result.deinit();
    try assertSuccessOutput(
        "big integer signs division and bases",
        &result,
        "-10\n" ++
            "-111111110111111111010\n" ++
            "-127275040218913072\n" ++
            "94\n" ++
            "True\n" ++
            "0xab54a98ceb1f0ad2\n" ++
            "0o0\n" ++
            "12345678901234567890",
    );
}

fn caseDivModLaws() !void {
    var env = try TestEnv.init();
    defer env.deinit();
    const script = try std.fmt.allocPrint(allocator, "{s}/ex/divmodtest.m", .{build_options.lib_path});
    defer allocator.free(script);
    var result = try runMira(&env, script, "test1\ntest2\ntest3\n/q\n", &.{});
    defer result.deinit();
    try assertSuccessOutput("div/mod laws", &result, "True\nTrue\nTrue");
}

fn caseLazyListsAndStrings() !void {
    var env = try TestEnv.init();
    defer env.deinit();
    var result = try runMira(&env, "", "take 5 [1..]\nreverse [1,2,3]\nzip2 [1,2,3] [4,5,6]\n\"abc\" ++ \"def\"\n/q\n", &.{});
    defer result.deinit();
    try assertSuccessOutput("lazy lists and strings", &result, "[1,2,3,4,5]\n[3,2,1]\n[(1,4),(2,5),(3,6)]\nabcdef");
}

fn caseExampleScriptFib() !void {
    var env = try TestEnv.init();
    defer env.deinit();
    const script = try std.fmt.allocPrint(allocator, "{s}/ex/fib", .{build_options.lib_path});
    defer allocator.free(script);
    var result = try runMira(&env, script, "fib 10\n/q\n", &.{});
    defer result.deinit();
    try assertSuccessOutput("example script fib", &result, "55");
}

fn caseUserScriptDefinitions() !void {
    var env = try TestEnv.init();
    defer env.deinit();
    const script = try std.fmt.allocPrint(allocator, "{s}/user-defs.m", .{env.work});
    defer allocator.free(script);
    try writeFile(script, "square x = x*x\ntwice f x = f (f x)\npairup x y = (x,y)\n");
    var result = try runMira(&env, script, "square 12\ntwice square 2\npairup \"a\" [1,2]\n/q\n", &.{});
    defer result.deinit();
    try assertSuccessOutput("user script definitions", &result, "144\n16\n(\"a\",[1,2])");
}

fn caseTypeErrorReporting() !void {
    var env = try TestEnv.init();
    defer env.deinit();
    var result = try runMira(&env, "", "1 + \"x\"\n/q\n", &.{});
    defer result.deinit();
    try assertSuccessOutput("type error reporting", &result, "type error in expression\ncannot unify [char] with num");
}

fn caseSyntaxErrorReporting() !void {
    var env = try TestEnv.init();
    defer env.deinit();
    var result = try runMira(&env, "", "1 +\n/q\n", &.{});
    defer result.deinit();
    try assertSuccessOutput("syntax error reporting", &result, "syntax error - unexpected newline");
}

fn caseVeryLongLiterals() !void {
    var env = try TestEnv.init();
    defer env.deinit();
    const long_string = try repeatChar(4096, 'a');
    defer allocator.free(long_string);
    const long_integer = try repeatChar(512, '9');
    defer allocator.free(long_integer);
    const zeroes = try repeatChar(512, '0');
    defer allocator.free(zeroes);
    const input = try std.fmt.allocPrint(allocator, "# \"{s}\"\n{s} + 1\n/q\n", .{ long_string, long_integer });
    defer allocator.free(input);
    const expected = try std.fmt.allocPrint(allocator, "4096\n1{s}", .{zeroes});
    defer allocator.free(expected);

    var result = try runMira(&env, "", input, &.{});
    defer result.deinit();
    try assertSuccessOutput("very long literals", &result, expected);
}

fn caseCompileTimeStressGuard() !void {
    var env = try TestEnv.init();
    defer env.deinit();
    const script = try std.fmt.allocPrint(allocator, "{s}/compile-stress.m", .{env.work});
    defer allocator.free(script);
    try writeCompileStressScript(script, 1500);
    var result = try runMira(&env, script, "", &.{"-make"});
    defer result.deinit();
    try assertSuccessStatus("compile time stress guard", &result);
}

fn caseStandardLibLoadSpeedGuard() !void {
    var env = try TestEnv.init();
    defer env.deinit();
    var result = try runMira(&env, "", "product [1..10]\nreverse [1,2,3]\n\"abc\" ++ \"def\"\n/q\n", &.{});
    defer result.deinit();
    try assertSuccessOutput("standard lib load speed guard", &result, "3628800\n[3,2,1]\nabcdef");
}

fn caseCompileGcStress() !void {
    var env = try TestEnv.init();
    defer env.deinit();
    const script = try std.fmt.allocPrint(allocator, "{s}/compile-gc-stress.m", .{env.work});
    defer allocator.free(script);
    try writeCompileStressScript(script, 600);
    var result = try runMira(&env, script, "stress_len\n/q\n", &.{ "-heap", "25000", "-gc" });
    defer result.deinit();
    try assertSuccessOutput("compile-gc-stress", &result, "601");
    try testing.expect(std.mem.find(u8, result.stderr, "<<gc after") != null);
}

fn caseRuntimeGcStress() !void {
    var env = try TestEnv.init();
    defer env.deinit();
    var result = try runMira(&env, "", "sum [1..4000]\n/q\n", &.{ "-heap", "12000", "-gc" });
    defer result.deinit();
    try assertSuccessOutput("runtime-gc-stress", &result, "8002000");
    try testing.expect(std.mem.find(u8, result.stderr, "<<gc after") != null);
}

fn caseMakeFailureLongPath() !void {
    var env = try TestEnv.init();
    defer env.deinit();
    const base_name = "a_file_with_an_undefined_name_and_a_very_long_path_to_reproduce_the_divide_by_zero_panic";
    const script = try std.fmt.allocPrint(allocator, "{s}/{s}.m", .{env.work, base_name});
    defer allocator.free(script);
    try writeFile(script, "foo = bar\n");
    var result = try runMira(&env, script, "", &.{"-make"});
    defer result.deinit();
    switch (result.term) {
        .exited => |code| {
            try testing.expectEqual(@as(u32, 1), @as(u32, code));
        },
        else => {
            std.debug.print("Expected normal exit code 1, but got: {any}\nstdout:\n{s}\nstderr:\n{s}\n", .{ result.term, result.stdout, result.stderr });
            return error.TestExpectedNormalExit;
        },
    }
}

fn caseSyntaxErrorRepeat() !void {
    var env = try TestEnv.init();
    defer env.deinit();
    const script = try std.fmt.allocPrint(allocator, "{s}/bad_syntax.m", .{env.work});
    defer allocator.free(script);
    try writeFile(script, "x = 1 +\n");

    // First run - compile from source, should report syntax error
    var result1 = try runMira(&env, script, "", &.{});
    defer result1.deinit();
    try testing.expect(std.mem.find(u8, result1.stderr, "syntax error") != null);

    // Second run - should still report syntax error, not load silently from dump cache
    var result2 = try runMira(&env, script, "", &.{});
    defer result2.deinit();
    try testing.expect(std.mem.find(u8, result2.stderr, "syntax error") != null);
}
