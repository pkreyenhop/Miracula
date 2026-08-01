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

    // Hosted macOS runners can spend more than ten seconds in the strict Zig
    // reference's fib-27 regression while other go-ready jobs contend for the
    // same machine. Keep a firm ceiling, aligned with the spine/signal suites,
    // without turning ordinary load into a flaky failure.
    const timeout_seconds = if (build_options.force_gc_every_allocation) 120 else 30;
    const timeout = std.Io.Timeout{ .duration = .{ .raw = std.Io.Duration.fromSeconds(timeout_seconds), .clock = .real } };
    while (multi_reader.fill(64, timeout)) |_| {
        if (multi_reader.reader(0).buffered().len > 1024 * 1024 or multi_reader.reader(1).buffered().len > 1024 * 1024) {
            return error.StreamTooLong;
        }
    } else |err| switch (err) {
        error.EndOfStream => {},
        error.Timeout => {
            _ = child.kill(testing.io);
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
    try caseReplHeapGrowthRollback();
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
    try caseDumpUndumpRoundTrip();
    try caseTofileAppendfileRoundTrip();
    try caseReadvalsSurvivesGcPressure();
}

fn caseReplHeapGrowthRollback() !void {
    var env = try TestEnv.init();
    defer env.deinit();
    const rc_path = try std.fmt.allocPrint(allocator, "{s}/.mirarc", .{env.home});
    defer allocator.free(rc_path);
    try writeFile(rc_path, "hdve 51200 100000 2067 vi +!\n");
    var result = try runMira(&env, "script.m", "fib 12\nfib 20\nfib 27\n/q\n", &.{});
    defer result.deinit();
    try assertSuccessOutput("REPL heap-growth rollback", &result, "144\n6765\n196418");
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
    const script = try std.fmt.allocPrint(allocator, "{s}/{s}.m", .{ env.work, base_name });
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

/// A real, CLI-level compile -> dump -> undump round-trip check (Phase 2
/// step 4 prerequisite, docs/GoReady.md): every successful script
/// compile unconditionally writes a `.x` dump (`module_loader.zig`'s
/// `loadfile`, confirmed by reading it directly, not assumed), and the
/// *second* invocation against an unchanged source loads from that dump
/// instead of recompiling (`dump.zig`'s `undump`, gated on the dump's
/// mtime being >= the source's). Exercises a spread of `dumpOb`'s node
/// kinds in one script — small and big integers, a double, a string, a
/// tuple, a user-defined function, and an algebraic type — so a Stream-
/// abstraction change that corrupts any one of `dumpOb`/`loadDefs`'s
/// tagged cases (`SHORT_X`/`INT_X`/`DBL_X`/`DATAPAIR`/`CONSTRUCT_X`/etc.,
/// `heap.zig`) has a concrete failure to show for it. The existing
/// `dumpOb`/`loadDefs` unit test in `heap.zig` only checks structural
/// round-trip fidelity for a bare cons of two ints in isolation, not real
/// CLI-driven behavior, and not byte-for-byte format stability.
///
/// Two independent signals, either one sufficient to catch a regression:
/// (1) evaluating the same expressions against the fresh-compiled state
/// and the dump-reloaded state gives byte-identical output, and (2) the
/// `.x` file itself is untouched (byte-identical) after the second run --
/// `dump.zig`'s `undump` only re-invokes `loadfile` (which would rewrite
/// the dump) on a load failure, so an unchanged dump file is direct
/// evidence the fast path was taken, not a silent fallback recompile.
/// Also asserts neither run's stderr contains the "contains incorrect
/// data" warning `undump` prints when a dump fails to parse.
fn caseDumpUndumpRoundTrip() !void {
    var env = try TestEnv.init();
    defer env.deinit();
    const script = try std.fmt.allocPrint(allocator, "{s}/roundtrip.m", .{env.work});
    defer allocator.free(script);
    try writeFile(script,
        \\tree ::= Leaf | Node tree num tree
        \\depth Leaf = 0
        \\depth (Node l x r) = 1 + max [depth l, depth r]
        \\sample = Node (Node Leaf 1 Leaf) 2 (Node Leaf 3 Leaf)
        \\big = 2^80 + 1
        \\pi_ish = 3.14159265358979
        \\greeting = "hello, dump"
        \\pair = (big, greeting)
        \\
    );
    const input = "depth sample\nbig\npi_ish\ngreeting\npair\n/q\n";

    const dump_path = try std.fmt.allocPrint(allocator, "{s}/roundtrip.x", .{env.work});
    defer allocator.free(dump_path);

    // Run 1: no .x present yet, compiles from source and dumps as a side effect.
    var result1 = try runMira(&env, script, input, &.{});
    defer result1.deinit();
    try assertSuccessStatus("dump/undump round trip (fresh compile)", &result1);
    try testing.expect(std.mem.find(u8, result1.stderr, "contains incorrect data") == null);

    const dump_bytes_1 = try std.Io.Dir.cwd().readFileAlloc(testing.io, dump_path, allocator, .limited(1024 * 1024));
    defer allocator.free(dump_bytes_1);
    try testing.expect(dump_bytes_1.len > 0);

    // Run 2: source unchanged, .x present and newer -- should load from the dump.
    var result2 = try runMira(&env, script, input, &.{});
    defer result2.deinit();
    try assertSuccessStatus("dump/undump round trip (reload from dump)", &result2);
    try testing.expect(std.mem.find(u8, result2.stderr, "contains incorrect data") == null);

    try testing.expectEqualStrings(result1.stdout, result2.stdout);

    const dump_bytes_2 = try std.Io.Dir.cwd().readFileAlloc(testing.io, dump_path, allocator, .limited(1024 * 1024));
    defer allocator.free(dump_bytes_2);
    try testing.expectEqualStrings(dump_bytes_1, dump_bytes_2);
}

/// `Tofile`/`Appendfile`/`Closefile` had zero test coverage before this
/// (Phase 2 step 4, docs/GoReady.md) -- and turned out to have a
/// real bug: `Tofile fil string` only switched the output stream and
/// silently dropped `string` instead of writing it (fixed in
/// `runtime/reduce.zig`'s `output()`, which now also `print`s the message's
/// own string after `outf` switches the stream, matching the manual's
/// documented behaviour and `Stdout`'s existing shape). This exercises:
/// a fresh `Tofile` (truncates + writes), then a second command-level
/// evaluation that `Appendfile`s the same path before `Tofile`-ing more
/// (append, not truncate, across separate message-list evaluations --
/// `Tofile`'s own doc comment above explains why the stream stays switched
/// open until eval end, and `Appendfile` must be re-asserted per
/// evaluation to pre-register append mode for the *next* `Tofile`).
fn caseTofileAppendfileRoundTrip() !void {
    var env = try TestEnv.init();
    defer env.deinit();
    const out_path = try std.fmt.allocPrint(allocator, "{s}/tofile_out.txt", .{env.work});
    defer allocator.free(out_path);

    const input = try std.fmt.allocPrint(allocator,
        \\[Tofile "{s}" "first\n"]
        \\[Appendfile "{s}", Tofile "{s}" "second\n"]
        \\/q
        \\
    , .{ out_path, out_path, out_path });
    defer allocator.free(input);

    var result = try runMira(&env, "", input, &.{});
    defer result.deinit();
    try assertSuccessStatus("Tofile/Appendfile round trip", &result);

    const written = try std.Io.Dir.cwd().readFileAlloc(testing.io, out_path, allocator, .limited(4096));
    defer allocator.free(written);
    try testing.expectEqualStrings("first\nsecond\n", written);
}

/// `readvals` had zero test coverage before this and was found to crash
/// with heap corruption (`heap.validate: cell ... has out-of-bounds tl
/// reference ...`) on ordinary input: `STARTREAD`/`STARTREADBIN`/
/// `STARTREADVALS`/`system`'s pipe-reading `EXEC` handler all embedded a
/// raw `Stream` pointer directly in an `AP`-tagged cell's tail (reusing the
/// reduction spine's own cell), which is above the tag-ordinal threshold
/// `Heap.mark`/`Heap.validate` use to decide whether to chase a cell's tl
/// as a reference -- so any GC landing while such a cell was reachable
/// tried to treat the pointer bit pattern as a cell index. `readvals`'s
/// own per-value reentrant parse+codegen+typecheck+fork cycle allocates
/// enough that a GC landing there was nearly certain, which is how this
/// was found; `read`/`readb`/`system` share the identical hazard, just
/// less reliably. Fixed by wrapping the pointer in a `DATAPAIR` cell
/// (`runtime/reduce.zig`'s `wrapPtr`/`unwrapPtr`) -- the same established
/// pattern `fileq`/`outfilq` already used, extended to these call sites.
/// `-heap 100` (the minimum accepted) forces maximum GC pressure so this
/// is a real regression test, not a lucky pass.
fn caseReadvalsSurvivesGcPressure() !void {
    var env = try TestEnv.init();
    defer env.deinit();
    const vals_path = try std.fmt.allocPrint(allocator, "{s}/readvals_in.txt", .{env.work});
    defer allocator.free(vals_path);
    try writeFile(vals_path, "1\n2\n3\n4\n5\n");

    const input = try std.fmt.allocPrint(allocator,
        \\sum (readvals "{s}")
        \\/q
        \\
    , .{vals_path});
    defer allocator.free(input);

    var result = try runMira(&env, "", input, &.{ "-heap", "100" });
    defer result.deinit();
    try assertSuccessStatus("readvals survives GC pressure", &result);
    // Each value read triggers its own reentrant desk-calculator echo
    // (a separate, already-known-and-documented oddity of readvals's
    // fork-per-value reuse of the REPL evaluation path, not something
    // this test asserts is *correct* -- just capturing today's actual
    // behavior) before the outer `sum`'s own result.
    try testing.expectEqualStrings("1\n2\n3\n4\n5\n15", result.stdout);
}
