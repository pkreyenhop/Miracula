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

    const version_text = readTrimmed(b, "miralib/.version");
    const vdate = readTrimmed(b, ".vdate");
    const host = readTrimmed(b, ".host");

    // Zero-overhead reduction tracing: off by default, so trace calls compile
    // away entirely. `zig build -Dreduce-trace` turns on per-combinator firing
    // counts (emitted to stderr by the reducer's stats dump).
    const reduce_trace = b.option(bool, "reduce-trace", "Enable reduction tracing (per-combinator counts to stderr)") orelse false;

    const is_strict = b.option(bool, "strict", "Enable strict build validation features") orelse false;

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
    });
    utf8_tests.root_module.addImport("utf8", utf8_module);
    const run_utf8_tests = b.addRunArtifact(utf8_tests);

    const just_tests = b.addTest(.{
        .name = "just-tests",
        .root_module = just_module,
    });
    const run_just_tests = b.addRunArtifact(just_tests);

    const menudriver_tests = b.addTest(.{
        .name = "menudriver-tests",
        .root_module = menudriver_module,
    });
    const run_menudriver_tests = b.addRunArtifact(menudriver_tests);

    const main_tests = b.addTest(.{
        .name = "main-tests",
        .root_module = mira_module,
    });
    const run_main_tests = b.addRunArtifact(main_tests);

    const parser_tests = b.addTest(.{
        .name = "parser-tests",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/parser/parser.zig"),
            .target = target,
            .optimize = optimize,
        }),
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
    });
    mira_tests.root_module.addOptions("build_options", mira_test_options);
    const run_mira_tests = b.addRunArtifact(mira_tests);
    if (configured_mira_path == null) {
        run_mira_tests.step.dependOn(&install_mira.step);
    }

    const test_step = b.step("test", "Run all tests");
    test_step.dependOn(&run_utf8_tests.step);
    test_step.dependOn(&run_just_tests.step);
    test_step.dependOn(&run_menudriver_tests.step);
    test_step.dependOn(&run_main_tests.step);
    test_step.dependOn(&run_mira_tests.step);
    test_step.dependOn(&run_parser_tests.step);

    const test_mira = b.step("test-mira", "Run Zig integration tests against mira");
    test_mira.dependOn(&run_mira_tests.step);

    const run_golden_tests = b.addSystemCommand(&.{ "python3", "tests/golden_runner.py" });
    run_golden_tests.step.dependOn(&install_mira.step);

    const test_golden = b.step("test-golden", "Run the golden output snapshot tests");
    test_golden.dependOn(&run_golden_tests.step);

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
    });
    strict_utf8_tests.root_module.addImport("utf8", utf8_module);
    const run_strict_utf8_tests = b.addRunArtifact(strict_utf8_tests);

    const strict_just_tests = b.addTest(.{
        .name = "strict-just-tests",
        .root_module = strict_just_module,
    });
    const run_strict_just_tests = b.addRunArtifact(strict_just_tests);

    const strict_menudriver_tests = b.addTest(.{
        .name = "strict-menudriver-tests",
        .root_module = strict_menudriver_module,
    });
    const run_strict_menudriver_tests = b.addRunArtifact(strict_menudriver_tests);

    const strict_main_tests = b.addTest(.{
        .name = "strict-main-tests",
        .root_module = strict_mira_module,
    });
    const run_strict_main_tests = b.addRunArtifact(strict_main_tests);

    const strict_parser_module = b.createModule(.{
        .root_source_file = b.path("src/parser/parser.zig"),
        .target = target,
        .optimize = .Debug,
    });
    strict_parser_module.addOptions("version_options", strict_version_options);

    const strict_parser_tests = b.addTest(.{
        .name = "strict-parser-tests",
        .root_module = strict_parser_module,
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
    });
    strict_mira_tests.root_module.addOptions("build_options", strict_mira_test_options);
    const run_strict_mira_tests = b.addRunArtifact(strict_mira_tests);
    run_strict_mira_tests.step.dependOn(&install_strict_mira.step);
    run_strict_mira_tests.step.dependOn(&copy_strict_menudriver.step);

    const run_strict_golden_tests = b.addSystemCommand(&.{ "python3", "tests/golden_runner.py", "./zig-out/bin/strict-mira" });
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
