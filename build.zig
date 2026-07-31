const std = @import("std");
const zlinter = @import("zlinter");

const c_flags = [_][]const u8{
    "-std=c11",
    "-Wall",
    "-Wextra",
    "-Wpedantic",
    "-Werror",
};

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.option(std.builtin.OptimizeMode, "optimize", "Prioritize performance, safety, or binary size") orelse .Debug;
    const configured_mira_path = b.option([]const u8, "mira-path", "Path to the mira binary used by tests");
    const mira_path = configured_mira_path orelse "./zig-out/bin/mira";
    const lib_path = b.option([]const u8, "lib-path", "Path to the miralib directory used by tests") orelse "./miralib";
    const reference_manifest = b.option([]const u8, "reference-manifest", "Pinned reference manifest used by differential tests") orelse "tests/reference/manifest.json";
    const reference_platform = b.option([]const u8, "reference-platform", "Pinned reference platform key") orelse switch (target.result.os.tag) {
        .macos => switch (target.result.cpu.arch) {
            .aarch64 => "darwin-arm64",
            else => @panic("no pinned reference executable for this macOS architecture"),
        },
        .linux => switch (target.result.cpu.arch) {
            .x86_64 => "linux-amd64",
            else => @panic("no pinned reference executable for this Linux architecture"),
        },
        else => @panic("no pinned reference executable for this operating system"),
    };
    const reference_path = b.option([]const u8, "reference-path", "Override path to the pinned reference executable") orelse b.fmt("tests/reference/artifacts/{s}/mira", .{reference_platform});

    const version_text = readTrimmed(b, "miralib/.version");
    const vdate = readTrimmed(b, ".vdate");
    const host = readTrimmed(b, ".host");

    // Zero-overhead reduction tracing: off by default, so trace calls compile
    // away entirely. `zig build -Dreduce-trace` turns on per-combinator firing
    // counts (emitted to stderr by the reducer's stats dump).
    const reduce_trace = b.option(bool, "reduce-trace", "Enable reduction tracing (per-combinator counts to stderr)") orelse false;

    const is_strict = b.option(bool, "strict", "Enable strict build validation features") orelse false;

    // Some sandboxed environments hang indefinitely on the default test
    // runner's `--listen=-` IPC protocol (the build's `run test ...` step
    // blocks forever after the test binary finishes compiling, requiring an
    // operator to notice, kill the hung process by hand, and re-run the
    // compiled binary directly to see results). Force the compiler's own
    // default test runner into its "simple" mode instead: it runs to
    // completion and reports pass/fail via its exit code, like any other
    // program, with no IPC — `addRunArtifact` skips `--listen=-` entirely
    // whenever a test's `test_runner.mode` is `.simple`.
    const simple_test_runner: std.Build.Step.Compile.TestRunner = .{
        .path = .{ .cwd_relative = b.fmt("{s}/compiler/test_runner.zig", .{
            b.graph.zig_lib_directory.path orelse @panic("zig_lib_directory.path is null"),
        }) },
        .mode = .simple,
    };

    const version_options = b.addOptions();
    version_options.addOption(i32, "version", parseVersion(version_text));
    version_options.addOption([]const u8, "vdate", vdate);
    version_options.addOption([]const u8, "host", b.fmt("compiled by zig build\n{s}\n", .{host}));
    version_options.addOption(bool, "reduce_trace", reduce_trace);
    version_options.addOption(bool, "is_strict", is_strict);

    // On macOS, libSystem is implicitly linked by the OS linker — no explicit link_libc needed.
    // On Linux (including musl targets), link musl/glibc so setjmp, strcmp, getcwd etc. resolve.
    // With a musl target the link is static, producing a self-contained binary.
    const need_libc = target.result.os.tag != .macos;

    // Define reusable modules to avoid compiling the same code units multiple times
    const mira_module = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = need_libc,
    });
    mira_module.addOptions("version_options", version_options);

    // zigline gives the interactive REPL line editing + history. It is wired into
    // mira_module only (shared by the `mira` exe and main-tests); the standalone
    // parser/tool test modules don't import the REPL, so they don't pull it in.
    const zigline_dep = b.dependency("zigline", .{ .target = target, .optimize = optimize });
    mira_module.addImport("zigline", zigline_dep.module("zigline"));

    const just_module = b.createModule(.{
        .root_source_file = b.path("src/tools/just.zig"),
        .target = target,
        .optimize = optimize,
    });

    const menudriver_module = b.createModule(.{
        .root_source_file = b.path("src/tools/menudriver.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Build Executables
    const mira = b.addExecutable(.{
        .name = "mira",
        .root_module = mira_module,
    });

    const install_mira = b.addInstallArtifact(mira, .{});
    b.getInstallStep().dependOn(&install_mira.step);

    const fdate = b.addExecutable(.{
        .name = "fdate",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/tools/fdate.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    const install_fdate = b.addInstallArtifact(fdate, .{});
    b.getInstallStep().dependOn(&install_fdate.step);

    const just = b.addExecutable(.{
        .name = "just",
        .root_module = just_module,
    });
    const install_just = b.addInstallArtifact(just, .{});
    b.getInstallStep().dependOn(&install_just.step);

    const menudriver = b.addExecutable(.{
        .name = "menudriver",
        .root_module = menudriver_module,
    });
    const install_menudriver = b.addInstallArtifact(menudriver, .{
        .dest_dir = .{ .override = .{ .custom = "lib/miralib" } },
    });
    b.getInstallStep().dependOn(&install_menudriver.step);

    // Also place menudriver in the source miralib/ directory (gitignored) so that
    // running `./zig-out/bin/mira` from the project root can find it without -lib.
    const copy_menudriver = b.addSystemCommand(&.{"cp"});
    copy_menudriver.addFileArg(menudriver.getEmittedBin());
    copy_menudriver.addArg(b.pathFromRoot("miralib/menudriver"));
    copy_menudriver.step.dependOn(&menudriver.step);
    b.getInstallStep().dependOn(&copy_menudriver.step);

    const install_miralib = b.addInstallDirectory(.{
        .source_dir = b.path("miralib"),
        .install_dir = .lib,
        .install_subdir = "miralib",
        .exclude_extensions = &.{".x"},
    });
    b.getInstallStep().dependOn(&install_miralib.step);

    // Build Tests
    const utf8_module = b.createModule(.{
        .root_source_file = b.path("src/io/utf8.zig"),
        .target = target,
        .optimize = optimize,
    });

    const utf8_tests = b.addTest(.{
        .name = "utf8-tests",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/utf8_tests.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = need_libc,
        }),
        .test_runner = simple_test_runner,
    });
    utf8_tests.root_module.addImport("utf8", utf8_module);
    const run_utf8_tests = b.addRunArtifact(utf8_tests);

    const just_tests = b.addTest(.{
        .name = "just-tests",
        .root_module = just_module,
        .test_runner = simple_test_runner,
    });
    const run_just_tests = b.addRunArtifact(just_tests);

    const menudriver_tests = b.addTest(.{
        .name = "menudriver-tests",
        .root_module = menudriver_module,
        .test_runner = simple_test_runner,
    });
    const run_menudriver_tests = b.addRunArtifact(menudriver_tests);

    const main_tests = b.addTest(.{
        .name = "main-tests",
        .root_module = mira_module,
        .test_runner = simple_test_runner,
    });
    const run_main_tests = b.addRunArtifact(main_tests);

    const parser_tests = b.addTest(.{
        .name = "parser-tests",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/syntax/parser_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
        .test_runner = simple_test_runner,
    });
    const run_parser_tests = b.addRunArtifact(parser_tests);

    const mira_test_options = b.addOptions();
    mira_test_options.addOption([]const u8, "mira_path", mira_path);
    mira_test_options.addOption([]const u8, "lib_path", lib_path);

    const mira_tests = b.addTest(.{
        .name = "mira-tests",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/mira_tests.zig"),
            .target = target,
            .optimize = optimize,
        }),
        .test_runner = simple_test_runner,
    });
    mira_tests.root_module.addOptions("build_options", mira_test_options);
    const run_mira_tests = b.addRunArtifact(mira_tests);
    if (configured_mira_path == null) {
        run_mira_tests.step.dependOn(&install_mira.step);
    }

    const golden_runner = b.addExecutable(.{
        .name = "golden_runner",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/golden_runner.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    const run_sigint_check = b.addRunArtifact(b.addExecutable(.{
        .name = "sigint_check",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/sigint_check.zig"),
            .target = target,
            .optimize = optimize,
        }),
    }));
    run_sigint_check.addArg(mira_path);
    run_sigint_check.step.dependOn(&install_mira.step);

    const run_spine_check = b.addRunArtifact(b.addExecutable(.{
        .name = "spine_check",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/spine_differential_check.zig"),
            .target = target,
            .optimize = optimize,
        }),
    }));
    run_spine_check.addArg(mira_path);
    run_spine_check.step.dependOn(&install_mira.step);

    const verify_reference = b.addSystemCommand(&.{ "python3", "scripts/reference_oracle.py" });
    verify_reference.addArgs(&.{ "--manifest", reference_manifest, "verify", "--platform", reference_platform, "--binary", reference_path, "--library", lib_path });

    const run_phase1_acceptance = b.addSystemCommand(&.{ "python3", "-B", "-m", "unittest", "tests/test_phase1.py" });

    const run_regression = b.addSystemCommand(&.{ "python3", "tests/regression.py" });
    run_regression.addArg("--candidate");
    run_regression.addFileArg(mira.getEmittedBin());
    run_regression.addArgs(&.{ "--reference", reference_path, "--library", lib_path, "--repository", b.pathFromRoot(".") });
    run_regression.step.dependOn(&install_mira.step);
    run_regression.step.dependOn(&verify_reference.step);

    const run_smoke = b.addRunArtifact(b.addExecutable(.{
        .name = "smoke_runner",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/smoke.zig"),
            .target = target,
            .optimize = optimize,
        }),
    }));
    run_smoke.addArg(mira_path);
    run_smoke.step.dependOn(&install_mira.step);

    const run_generate_golden = b.addRunArtifact(b.addExecutable(.{
        .name = "generate_golden",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/generate_golden.zig"),
            .target = target,
            .optimize = optimize,
        }),
    }));
    run_generate_golden.addArg(mira_path);
    run_generate_golden.step.dependOn(&install_mira.step);

    const run_golden_capture = b.addRunArtifact(b.addExecutable(.{
        .name = "golden_capture",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/reducer/golden_capture.zig"),
            .target = target,
            .optimize = optimize,
        }),
    }));
    run_golden_capture.step.dependOn(&install_mira.step);

    const run_reducer_verify = b.addRunArtifact(b.addExecutable(.{
        .name = "reducer_verify",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/reducer/verify_golden.zig"),
            .target = target,
            .optimize = optimize,
        }),
    }));
    run_reducer_verify.step.dependOn(&install_mira.step);

    const test_step = b.step("test", "Run all tests");
    test_step.dependOn(&run_utf8_tests.step);
    test_step.dependOn(&run_just_tests.step);
    test_step.dependOn(&run_menudriver_tests.step);
    test_step.dependOn(&run_main_tests.step);
    test_step.dependOn(&run_mira_tests.step);
    test_step.dependOn(&run_parser_tests.step);
    test_step.dependOn(&run_sigint_check.step);
    test_step.dependOn(&run_spine_check.step);
    test_step.dependOn(&run_smoke.step);

    const test_mira = b.step("test-mira", "Run Zig integration tests against mira");
    test_mira.dependOn(&run_mira_tests.step);

    const run_golden_tests = b.addRunArtifact(golden_runner);
    run_golden_tests.addArg(mira_path);
    run_golden_tests.step.dependOn(&install_mira.step);

    // These process-level suites create and remove compiled `.x` caches in
    // shared fixture directories. Keep the spine corpus last so aggregate
    // `test`/`check` runs cannot race another runner over the same cache.
    run_smoke.step.dependOn(&run_mira_tests.step);
    run_golden_tests.step.dependOn(&run_smoke.step);
    run_sigint_check.step.dependOn(&run_golden_tests.step);
    run_spine_check.step.dependOn(&run_main_tests.step);
    run_spine_check.step.dependOn(&run_parser_tests.step);
    run_spine_check.step.dependOn(&run_sigint_check.step);
    run_spine_check.step.dependOn(&run_utf8_tests.step);
    run_spine_check.step.dependOn(&run_just_tests.step);
    run_spine_check.step.dependOn(&run_menudriver_tests.step);
    run_spine_check.step.dependOn(&run_golden_tests.step);

    const test_golden = b.step("test-golden", "Run the golden output snapshot tests");
    test_golden.dependOn(&run_golden_tests.step);

    const test_sigint = b.step("test-sigint", "Run the SIGINT integration check");
    test_sigint.dependOn(&run_sigint_check.step);

    const test_spine = b.step("test-spine", "Run the spine differential stress checks");
    test_spine.dependOn(&run_spine_check.step);

    const test_regression = b.step("test-regression", "Run the C compatibility differential regression tests");
    test_regression.dependOn(&run_regression.step);

    const test_verify_reference = b.step("verify-reference", "Verify pinned reference executable and Miranda library checksums");
    test_verify_reference.dependOn(&verify_reference.step);

    const test_phase1_acceptance = b.step("test-phase1", "Run fail-closed compatibility harness acceptance tests");
    test_phase1_acceptance.dependOn(&run_phase1_acceptance.step);

    const test_smoke = b.step("test-smoke", "Run the REPL integration smoke tests");
    test_smoke.dependOn(&run_smoke.step);

    const test_generate_golden = b.step("generate-golden", "Regenerate golden snapshots");
    test_generate_golden.dependOn(&run_generate_golden.step);

    const test_golden_capture = b.step("capture-reducer-golden", "Capture baseline metrics for reducer");
    test_golden_capture.dependOn(&run_golden_capture.step);

    const test_reducer_verify = b.step("verify-reducer-golden", "Verify reducer metrics against golden baseline");
    test_reducer_verify.dependOn(&run_reducer_verify.step);

    const test_steer = b.step("test-steer", "Run only steer tests");
    test_steer.dependOn(&run_main_tests.step);

    const tools_step = b.step("tools", "Build support tools");
    tools_step.dependOn(&install_fdate.step);
    tools_step.dependOn(&install_just.step);
    tools_step.dependOn(&install_menudriver.step);

    const check_step = b.step("check", "Run the full Zig build verification gate");
    check_step.dependOn(&install_mira.step);
    check_step.dependOn(&install_fdate.step);
    check_step.dependOn(&install_just.step);
    check_step.dependOn(&install_menudriver.step);
    check_step.dependOn(&run_utf8_tests.step);
    check_step.dependOn(&run_just_tests.step);
    check_step.dependOn(&run_menudriver_tests.step);
    check_step.dependOn(&run_main_tests.step);
    check_step.dependOn(&run_mira_tests.step);
    check_step.dependOn(&run_parser_tests.step);
    check_step.dependOn(&run_sigint_check.step);
    check_step.dependOn(&run_spine_check.step);
    check_step.dependOn(&run_smoke.step);

    const migration_check = b.step("check-migration", "Alias for the full Zig build verification gate");
    migration_check.dependOn(check_step);

    const clean = b.addSystemCommand(&.{
        "rm",
        "-rf",
        ".zig-cache",
        "zig-out",
        "mira",
        "fdate",
        "just",
        "miralib/menudriver",
        "tests/utf8_tests",
        "tests/mira_tests",
        "miralib/preludx",
        "miralib/stdenv.x",
        "script.x",
    });
    const clean_step = b.step("clean", "Remove Zig and legacy build outputs");
    clean_step.dependOn(&clean.step);

    // `zig build lint` — lint the project's own Zig sources with zlinter.
    // Scoped to src/ and tests/ so the dependency cache (zig-pkg/) is not linted.
    const lint_step = b.step("lint", "Lint Zig source with zlinter");
    lint_step.dependOn(step: {
        var lint = zlinter.builder(b, .{});
        lint.addRule(.{ .builtin = .no_unused }, .{});
        lint.addRule(.{ .builtin = .no_deprecated }, .{});
        lint.addRule(.{ .builtin = .no_orelse_unreachable }, .{});
        lint.addPaths(.{ .include = &.{ b.path("src"), b.path("tests") } });
        break :step lint.build();
    });

    // --- Strict Build Configuration ---
    const strict_version_options = b.addOptions();
    strict_version_options.addOption(i32, "version", parseVersion(version_text));
    strict_version_options.addOption([]const u8, "vdate", vdate);
    strict_version_options.addOption([]const u8, "host", b.fmt("compiled by zig build\n{s}\n", .{host}));
    strict_version_options.addOption(bool, "reduce_trace", reduce_trace);
    strict_version_options.addOption(bool, "is_strict", true);

    const strict_mira_module = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = .Debug,
        .link_libc = need_libc,
    });
    strict_mira_module.addOptions("version_options", strict_version_options);
    strict_mira_module.addImport("zigline", zigline_dep.module("zigline"));

    const strict_mira = b.addExecutable(.{
        .name = "strict-mira",
        .root_module = strict_mira_module,
    });
    const install_strict_mira = b.addInstallArtifact(strict_mira, .{});

    const strict_fdate = b.addExecutable(.{
        .name = "strict-fdate",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/tools/fdate.zig"),
            .target = target,
            .optimize = .Debug,
        }),
    });
    const install_strict_fdate = b.addInstallArtifact(strict_fdate, .{});

    const strict_just_module = b.createModule(.{
        .root_source_file = b.path("src/tools/just.zig"),
        .target = target,
        .optimize = .Debug,
    });
    const strict_just = b.addExecutable(.{
        .name = "strict-just",
        .root_module = strict_just_module,
    });
    const install_strict_just = b.addInstallArtifact(strict_just, .{});

    const strict_menudriver_module = b.createModule(.{
        .root_source_file = b.path("src/tools/menudriver.zig"),
        .target = target,
        .optimize = .Debug,
    });
    const strict_menudriver = b.addExecutable(.{
        .name = "strict-menudriver",
        .root_module = strict_menudriver_module,
    });
    const install_strict_menudriver = b.addInstallArtifact(strict_menudriver, .{
        .dest_dir = .{ .override = .{ .custom = "lib/miralib" } },
    });

    const copy_strict_menudriver = b.addSystemCommand(&.{"cp"});
    copy_strict_menudriver.addFileArg(strict_menudriver.getEmittedBin());
    copy_strict_menudriver.addArg(b.pathFromRoot("miralib/menudriver"));
    copy_strict_menudriver.step.dependOn(&strict_menudriver.step);

    // Strict tests
    const strict_utf8_tests = b.addTest(.{
        .name = "strict-utf8-tests",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/utf8_tests.zig"),
            .target = target,
            .optimize = .Debug,
            .link_libc = need_libc,
        }),
        .test_runner = simple_test_runner,
    });
    strict_utf8_tests.root_module.addImport("utf8", utf8_module);
    const run_strict_utf8_tests = b.addRunArtifact(strict_utf8_tests);

    const strict_just_tests = b.addTest(.{
        .name = "strict-just-tests",
        .root_module = strict_just_module,
        .test_runner = simple_test_runner,
    });
    const run_strict_just_tests = b.addRunArtifact(strict_just_tests);

    const strict_menudriver_tests = b.addTest(.{
        .name = "strict-menudriver-tests",
        .root_module = strict_menudriver_module,
        .test_runner = simple_test_runner,
    });
    const run_strict_menudriver_tests = b.addRunArtifact(strict_menudriver_tests);

    const strict_main_tests = b.addTest(.{
        .name = "strict-main-tests",
        .root_module = strict_mira_module,
        .test_runner = simple_test_runner,
    });
    const run_strict_main_tests = b.addRunArtifact(strict_main_tests);

    const strict_parser_module = b.createModule(.{
        .root_source_file = b.path("src/syntax/parser_test.zig"),
        .target = target,
        .optimize = .Debug,
    });
    strict_parser_module.addOptions("version_options", strict_version_options);

    const strict_parser_tests = b.addTest(.{
        .name = "strict-parser-tests",
        .root_module = strict_parser_module,
        .test_runner = simple_test_runner,
    });
    const run_strict_parser_tests = b.addRunArtifact(strict_parser_tests);

    const strict_mira_test_options = b.addOptions();
    strict_mira_test_options.addOption([]const u8, "mira_path", "./zig-out/bin/strict-mira");
    strict_mira_test_options.addOption([]const u8, "lib_path", lib_path);

    const strict_mira_tests = b.addTest(.{
        .name = "strict-mira-tests",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/mira_tests.zig"),
            .target = target,
            .optimize = .Debug,
        }),
        .test_runner = simple_test_runner,
    });
    strict_mira_tests.root_module.addOptions("build_options", strict_mira_test_options);
    const run_strict_mira_tests = b.addRunArtifact(strict_mira_tests);
    run_strict_mira_tests.step.dependOn(&install_strict_mira.step);
    run_strict_mira_tests.step.dependOn(&copy_strict_menudriver.step);

    const run_strict_golden_tests = b.addRunArtifact(golden_runner);
    run_strict_golden_tests.addArg("./zig-out/bin/strict-mira");
    run_strict_golden_tests.step.dependOn(&install_strict_mira.step);
    run_strict_golden_tests.step.dependOn(&copy_strict_menudriver.step);

    const fmt_check = b.addSystemCommand(&.{
        b.graph.zig_exe, "fmt", "--check", "src", "tests", "build.zig",
    });

    const strict_step = b.step("strict", "Run all strict validation tests and checks");
    strict_step.dependOn(&install_strict_mira.step);
    strict_step.dependOn(&install_strict_fdate.step);
    strict_step.dependOn(&install_strict_just.step);
    strict_step.dependOn(&install_strict_menudriver.step);
    strict_step.dependOn(&copy_strict_menudriver.step);

    strict_step.dependOn(&run_strict_utf8_tests.step);
    strict_step.dependOn(&run_strict_just_tests.step);
    strict_step.dependOn(&run_strict_menudriver_tests.step);
    strict_step.dependOn(&run_strict_main_tests.step);
    strict_step.dependOn(&run_strict_parser_tests.step);
    strict_step.dependOn(&run_strict_mira_tests.step);
    strict_step.dependOn(&run_strict_golden_tests.step);
    strict_step.dependOn(&fmt_check.step);
    strict_step.dependOn(lint_step);

    // Language-neutral, per-stage migration oracles. Each verifier launches
    // an external producer and compares canonical JSONL; it never imports or
    // calls the implementation under test.
    const oracle_producer = b.option([]const u8, "oracle-producer", "External stage-oracle producer command");
    const oracle_stages = [_][]const u8{
        "source",
        "lex",
        "layout",
        "parse",
        "module",
        "typecheck",
        "lower",
        "reduce",
        "dump",
    };
    const verify_all_oracles = b.step("verify-oracles", "Verify every language-neutral stage oracle");
    inline for (oracle_stages) |stage| {
        const capture = b.addSystemCommand(&.{ "python3", "tests/oracle/oracle.py", "capture", "--stage", stage });
        if (oracle_producer) |producer| capture.addArgs(&.{ "--producer", producer });
        const capture_step = b.step(
            "capture-" ++ stage ++ "-oracle",
            "Capture the " ++ stage ++ " oracle (maintainer operation)",
        );
        capture_step.dependOn(&capture.step);

        const verify = b.addSystemCommand(&.{ "python3", "tests/oracle/oracle.py", "verify", "--stage", stage });
        if (oracle_producer) |producer| verify.addArgs(&.{ "--producer", producer });
        const verify_step = b.step(
            "verify-" ++ stage ++ "-oracle",
            "Verify the " ++ stage ++ " oracle without changing fixtures",
        );
        verify_step.dependOn(&verify.step);
        verify_all_oracles.dependOn(verify_step);
    }
    const run_phase2_acceptance = b.addSystemCommand(&.{ "python3", "-B", "-m", "unittest", "tests/test_phase2.py" });
    const test_phase2 = b.step("test-phase2", "Run stage-oracle protocol acceptance tests");
    test_phase2.dependOn(&run_phase2_acceptance.step);
    const run_phase3_inventory = b.addSystemCommand(&.{ "python3", "scripts/pointer_inventory.py" });
    const test_phase3 = b.step("test-phase3", "Verify graph values contain no native resource pointers");
    test_phase3.dependOn(&run_phase3_inventory.step);
    const run_phase4_roots = b.addSystemCommand(&.{ "python3", "scripts/phase4_roots.py" });
    const test_phase4 = b.step("test-phase4", "Verify explicit GC roots and native-stack independence");
    test_phase4.dependOn(&run_phase4_roots.step);

    // Mandatory migration-readiness gate. Reference preparation is deliberately
    // separate: this target fails closed when the pinned artifact is absent.
    const go_ready_step = b.step("go-ready", "Run the complete fail-closed Go migration readiness gate");
    go_ready_step.dependOn(check_step);
    go_ready_step.dependOn(strict_step);
    go_ready_step.dependOn(test_golden);
    go_ready_step.dependOn(test_regression);
    go_ready_step.dependOn(test_verify_reference);
    go_ready_step.dependOn(test_phase1_acceptance);
    go_ready_step.dependOn(verify_all_oracles);
    go_ready_step.dependOn(test_phase2);
    go_ready_step.dependOn(test_phase3);
    go_ready_step.dependOn(test_phase4);

    // Benchmark targets (optimized for ReleaseFast)
    const bench_version_options = b.addOptions();
    bench_version_options.addOption(i32, "version", parseVersion(version_text));
    bench_version_options.addOption([]const u8, "vdate", vdate);
    bench_version_options.addOption([]const u8, "host", b.fmt("compiled by zig build\n{s}\n", .{host}));
    bench_version_options.addOption(bool, "reduce_trace", false);
    bench_version_options.addOption(bool, "is_strict", false);

    const bench_mira_module = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = .ReleaseFast,
        .link_libc = need_libc,
    });
    bench_mira_module.addOptions("version_options", bench_version_options);
    bench_mira_module.addImport("zigline", zigline_dep.module("zigline"));

    const bench_mira = b.addExecutable(.{
        .name = "bench-mira",
        .root_module = bench_mira_module,
    });
    const install_bench_mira = b.addInstallArtifact(bench_mira, .{});

    const bench_micro_module = b.createModule(.{
        .root_source_file = b.path("src/micro_benchmarks.zig"),
        .target = target,
        .optimize = .ReleaseFast,
        .link_libc = need_libc,
    });
    bench_micro_module.addOptions("version_options", bench_version_options);
    bench_micro_module.addImport("zigline", zigline_dep.module("zigline"));

    const bench_micro = b.addExecutable(.{
        .name = "bench-micro",
        .root_module = bench_micro_module,
    });
    const install_bench_micro = b.addInstallArtifact(bench_micro, .{});

    const run_bench_micro = b.addRunArtifact(bench_micro);

    const benchmark_runner = b.addExecutable(.{
        .name = "benchmark_runner",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/benchmark_runner.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    const run_bench_macro = b.addRunArtifact(benchmark_runner);
    run_bench_macro.addFileArg(bench_mira.getEmittedBin());
    run_bench_macro.step.dependOn(&install_bench_mira.step);

    const bench_step = b.step("bench", "Run micro-benchmarks and macro-benchmarks");
    bench_step.dependOn(&install_bench_mira.step);
    bench_step.dependOn(&install_bench_micro.step);
    bench_step.dependOn(&run_bench_micro.step);
    bench_step.dependOn(&run_bench_macro.step);
}

fn readTrimmed(b: *std.Build, path: []const u8) []const u8 {
    const contents = b.build_root.handle.readFileAlloc(b.graph.io, path, b.allocator, .limited(4096)) catch |err| {
        if (std.mem.eql(u8, path, ".vdate")) {
            return "unknown-date";
        } else if (std.mem.eql(u8, path, ".host")) {
            return "unknown-host";
        }
        std.debug.panic("failed to read {s}: {}", .{ path, err });
    };
    return std.mem.trim(u8, contents, " \t\r\n");
}

fn parseVersion(text: []const u8) i32 {
    return std.fmt.parseInt(i32, text, 10) catch |err| {
        std.debug.panic("failed to parse miralib/.version value '{s}': {}", .{ text, err });
    };
}
