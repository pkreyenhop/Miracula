const std = @import("std");

const c_flags = [_][]const u8{
    "-std=c11",
    "-Wall",
    "-Wextra",
    "-Wpedantic",
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

    const version_options = b.addOptions();
    version_options.addOption(i32, "version", parseVersion(version_text));
    version_options.addOption([]const u8, "vdate", vdate);
    version_options.addOption([]const u8, "host", b.fmt("compiled by zig build\n{s}\n", .{host}));

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
    });
    const clean_step = b.step("clean", "Remove Zig and legacy build outputs");
    clean_step.dependOn(&clean.step);
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
