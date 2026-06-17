const std = @import("std");

const c_sources = [_][]const u8{};

const header_check_includes =
    \\#include "runtime.h"
    \\#include "platform.h"
    \\#include "signals.h"
    \\#include "utf8.h"
    \\#include "lex.h"
    \\#include "big.h"
    \\#include "data.h"
    \\#include "version.h"
    \\int main(void) { return 0; }
    \\
;

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

    const mira = b.addExecutable(.{
        .name = "mira",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        }),
    });
    mira.root_module.addOptions("version_options", version_options);
    mira.root_module.addIncludePath(b.path("."));
    mira.root_module.addIncludePath(b.path("src/parser/legacy"));
    mira.root_module.addCSourceFiles(.{
        .files = &c_sources,
        .flags = &c_flags,
    });
    addPlatformMacros(mira, target);
    mira.root_module.linkSystemLibrary("m", .{});

    const install_mira = b.addInstallArtifact(mira, .{});
    b.getInstallStep().dependOn(&install_mira.step);

    const utf8_zig = addZigObject(b, "utf8-zig", "src/io/utf8.zig", target, optimize, true);

    const fdate = addZigExecutable(b, "fdate", "fdate.zig", target, optimize, true);
    const install_fdate = b.addInstallArtifact(fdate, .{});
    b.getInstallStep().dependOn(&install_fdate.step);

    const just = addZigExecutable(b, "just", "just.zig", target, optimize, false);
    const install_just = b.addInstallArtifact(just, .{});
    b.getInstallStep().dependOn(&install_just.step);

    const menudriver = addZigExecutable(b, "menudriver", "menudriver.zig", target, optimize, false);
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

    const utf8_tests = addUtf8Tests(b, target, optimize, utf8_zig);
    const run_utf8_tests = b.addRunArtifact(utf8_tests);
    const just_tests = b.addTest(.{
        .name = "just-tests",
        .root_module = b.createModule(.{
            .root_source_file = b.path("just.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    const run_just_tests = b.addRunArtifact(just_tests);
    const menudriver_tests = b.addTest(.{
        .name = "menudriver-tests",
        .root_module = b.createModule(.{
            .root_source_file = b.path("menudriver.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    const run_menudriver_tests = b.addRunArtifact(menudriver_tests);
    const steer_tests = b.addTest(.{
        .name = "steer-tests",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        }),
    });
    const run_steer_tests = b.addRunArtifact(steer_tests);
    steer_tests.root_module.addIncludePath(b.path("."));
    steer_tests.root_module.addIncludePath(b.path("src/parser/legacy"));
    steer_tests.root_module.addCSourceFiles(.{
        .files = &c_sources,
        .flags = &c_flags,
    });
    addPlatformMacros(steer_tests, target);
    steer_tests.root_module.linkSystemLibrary("m", .{});
    steer_tests.root_module.addOptions("version_options", version_options);
    const lex_tests = b.addTest(.{
        .name = "lex-tests",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        }),
    });
    lex_tests.root_module.addIncludePath(b.path("."));
    lex_tests.root_module.addIncludePath(b.path("src/parser/legacy"));
    lex_tests.root_module.addCSourceFiles(.{
        .files = &c_sources,
        .flags = &c_flags,
    });
    addPlatformMacros(lex_tests, target);
    lex_tests.root_module.linkSystemLibrary("m", .{});
    lex_tests.root_module.addOptions("version_options", version_options);
    const run_lex_tests = b.addRunArtifact(lex_tests);

    const parser_tests = b.addTest(.{
        .name = "parser-tests",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/parser/parser.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    const run_parser_tests = b.addRunArtifact(parser_tests);

    const header_check = addHeaderCheck(b, target, optimize);

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
    test_step.dependOn(&run_steer_tests.step);
    test_step.dependOn(&run_lex_tests.step);
    test_step.dependOn(&run_mira_tests.step);
    test_step.dependOn(&run_parser_tests.step);

    const test_mira = b.step("test-mira", "Run Zig integration tests against mira");
    test_mira.dependOn(&run_mira_tests.step);

    const test_steer = b.step("test-steer", "Run only steer tests");
    test_steer.dependOn(&run_steer_tests.step);

    const header_check_step = b.step("check-headers", "Compile standalone public-header check");
    header_check_step.dependOn(&header_check.step);

    const tools_step = b.step("tools", "Build support tools");
    tools_step.dependOn(&install_fdate.step);
    tools_step.dependOn(&install_just.step);
    tools_step.dependOn(&install_menudriver.step);

    const check_step = b.step("check", "Run the full Zig build verification gate");
    check_step.dependOn(&header_check.step);
    check_step.dependOn(&install_mira.step);
    check_step.dependOn(&install_fdate.step);
    check_step.dependOn(&install_just.step);
    check_step.dependOn(&install_menudriver.step);
    check_step.dependOn(&run_utf8_tests.step);
    check_step.dependOn(&run_just_tests.step);
    check_step.dependOn(&run_menudriver_tests.step);
    check_step.dependOn(&run_steer_tests.step);
    check_step.dependOn(&run_lex_tests.step);
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

fn addZigExecutable(
    b: *std.Build,
    name: []const u8,
    path: []const u8,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    link_libc: bool,
) *std.Build.Step.Compile {
    return b.addExecutable(.{
        .name = name,
        .root_module = b.createModule(.{
            .root_source_file = b.path(path),
            .target = target,
            .optimize = optimize,
            .link_libc = link_libc,
        }),
    });
}

fn addCExecutable(
    b: *std.Build,
    name: []const u8,
    sources: []const []const u8,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) *std.Build.Step.Compile {
    const exe = b.addExecutable(.{
        .name = name,
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        }),
    });
    exe.root_module.addIncludePath(b.path("."));
    exe.root_module.addIncludePath(b.path("src/parser/legacy"));
    exe.root_module.addCSourceFiles(.{
        .files = sources,
        .flags = &c_flags,
    });
    addPlatformMacros(exe, target);
    return exe;
}

fn addUtf8Tests(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    utf8_zig: *std.Build.Step.Compile,
) *std.Build.Step.Compile {
    const utf8_tests = addCExecutable(b, "utf8-tests-zig", &.{"tests/utf8_tests.c"}, target, optimize);
    utf8_tests.root_module.addObject(utf8_zig);
    return utf8_tests;
}

fn addHeaderCheck(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) *std.Build.Step.Compile {
    const generated = b.addWriteFiles();
    const source = generated.add("header_check.c", header_check_includes);
    const check = b.addExecutable(.{
        .name = "header-check",
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        }),
    });
    check.root_module.addIncludePath(b.path("."));
    check.root_module.addIncludePath(b.path("src/parser/legacy"));
    check.root_module.addCSourceFile(.{
        .file = source,
        .flags = &c_flags,
    });
    addPlatformMacros(check, target);
    return check;
}

fn addZigObject(
    b: *std.Build,
    name: []const u8,
    path: []const u8,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    link_libc: bool,
) *std.Build.Step.Compile {
    const obj = b.addObject(.{
        .name = name,
        .root_module = b.createModule(.{
            .root_source_file = b.path(path),
            .target = target,
            .optimize = optimize,
            .link_libc = link_libc,
        }),
    });
    obj.root_module.addIncludePath(b.path("."));
    obj.root_module.addIncludePath(b.path("src/parser/legacy"));
    return obj;
}

fn addPlatformMacros(exe: *std.Build.Step.Compile, target: std.Build.ResolvedTarget) void {
    // 1. Force override GLIBC fortification checks globally
    exe.root_module.addCMacro("_FORTIFY_SOURCE", "0");

    // 2. Enable standard GNU extensions to let fcntl functions compile cleanly
    exe.root_module.addCMacro("_GNU_SOURCE", "1");

    // 3. Keep your existing platform-specific target definitions intact
    if (target.result.os.tag == .macos) {
        exe.root_module.addCMacro("_DARWIN_C_SOURCE", "1");
    } else {
        exe.root_module.addCMacro("_POSIX_C_SOURCE", "200809L");
    }
}

fn readTrimmed(b: *std.Build, path: []const u8) []const u8 {
    const contents = b.build_root.handle.readFileAlloc(b.allocator, path, 4096) catch |err| {
        std.debug.panic("failed to read {s}: {}", .{ path, err });
    };
    return std.mem.trim(u8, contents, " \t\r\n");
}

fn parseVersion(text: []const u8) i32 {
    return std.fmt.parseInt(i32, text, 10) catch |err| {
        std.debug.panic("failed to parse miralib/.version value '{s}': {}", .{ text, err });
    };
}
