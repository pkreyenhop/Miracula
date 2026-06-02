const std = @import("std");
const testing = std.testing;
const build_options = @import("build_options");

const allocator = testing.allocator;

const TestEnv = struct {
    home: []u8,
    work: []u8,

    fn init() !TestEnv {
        var random: [8]u8 = undefined;
        std.crypto.random.bytes(&random);
        const home = try std.fmt.allocPrint(allocator, "/tmp/mira-test-{x}", .{std.mem.readInt(u64, &random, .little)});
        errdefer allocator.free(home);
        std.crypto.random.bytes(&random);
        const work = try std.fmt.allocPrint(allocator, "/tmp/mira-work-{x}", .{std.mem.readInt(u64, &random, .little)});
        errdefer allocator.free(work);
        try std.fs.makeDirAbsolute(home);
        errdefer std.fs.deleteTreeAbsolute(home) catch {};
        try std.fs.makeDirAbsolute(work);
        return .{ .home = home, .work = work };
    }

    fn deinit(self: *TestEnv) void {
        std.fs.deleteTreeAbsolute(self.home) catch {};
        std.fs.deleteTreeAbsolute(self.work) catch {};
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

    var env_map = try std.process.getEnvMap(allocator);
    defer env_map.deinit();
    try env_map.put("HOME", env.home);

    var child = std.process.Child.init(argv, allocator);
    child.env_map = &env_map;
    child.stdin_behavior = .Pipe;
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Pipe;
    try child.spawn();
    errdefer _ = child.kill() catch {};

    try child.stdin.?.writeAll(input);
    child.stdin.?.close();
    child.stdin = null;

    var stdout: std.ArrayList(u8) = .empty;
    defer stdout.deinit(allocator);
    var stderr: std.ArrayList(u8) = .empty;
    defer stderr.deinit(allocator);
    try child.collectOutput(allocator, &stdout, &stderr, 1024 * 1024);

    const term = try child.wait();
    var stdout_text = try stdout.toOwnedSlice(allocator);
    stdout = .empty;
    stdout_text = try chompStdout(stdout_text);
    const stderr_text = try stderr.toOwnedSlice(allocator);
    stderr = .empty;

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
        .Exited => |code| {
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
            std.debug.print("{s} did not exit normally: {any}\n", .{ name, result.term });
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
    var file = try std.fs.createFileAbsolute(path, .{});
    defer file.close();
    try file.writeAll(contents);
}

fn writeCompileStressScript(path: []const u8, items: usize) !void {
    var file = try std.fs.createFileAbsolute(path, .{});
    defer file.close();
    try file.writeAll("stress_list\n=[\n");
    for (0..items) |i| {
        const line = try std.fmt.allocPrint(allocator, "  \"compile-time-stress-{d:0>4}\",\n", .{i});
        defer allocator.free(line);
        try file.writeAll(line);
    }
    try file.writeAll("  \"compile-time-stress-end\"]\nstress_len = # stress_list\n");
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
    try testing.expect(std.mem.indexOf(u8, result.stderr, "<<gc after") != null);
}

fn caseRuntimeGcStress() !void {
    var env = try TestEnv.init();
    defer env.deinit();
    var result = try runMira(&env, "", "sum [1..4000]\n/q\n", &.{ "-heap", "12000", "-gc" });
    defer result.deinit();
    try assertSuccessOutput("runtime-gc-stress", &result, "8002000");
    try testing.expect(std.mem.indexOf(u8, result.stderr, "<<gc after") != null);
}
