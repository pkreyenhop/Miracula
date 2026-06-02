const std = @import("std");

const c_sources = [_][]const u8{
    "big.c",
    "data.c",
    "lex.c",
    "reduce.c",
    "steer.c",
    "trans.c",
    "types.c",
    "y.tab.c",
};

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
    "-std=c23",
    "-Wall",
    "-Wextra",
    "-Wpedantic",
};

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.option(std.builtin.OptimizeMode, "optimize", "Prioritize performance, safety, or binary size") orelse .ReleaseFast;
    const configured_mira_path = b.option([]const u8, "mira-path", "Path to the mira binary used by tests");
    const mira_path = configured_mira_path orelse "./zig-out/bin/mira";
    const lib_path = b.option([]const u8, "lib-path", "Path to the miralib directory used by tests") orelse "./miralib";

    const utf8_zig = addZigObject(b, "utf8-zig", "utf8.zig", target, optimize, true);
    const signals_zig = addZigObject(b, "signals-zig", "signals.zig", target, optimize, true);
    const version_zig = addVersionObject(b, target, optimize);
    const cmbnms_zig = addZigObject(b, "cmbnms-zig", "cmbnms.zig", target, optimize, false);
    const mira = addMira(b, target, optimize, utf8_zig, signals_zig, version_zig, cmbnms_zig);
    const install_mira = b.addInstallArtifact(mira, .{});
    b.getInstallStep().dependOn(&install_mira.step);

    const fdate = addZigExecutable(b, "fdate", "fdate.zig", target, optimize, true);
    const install_fdate = b.addInstallArtifact(fdate, .{});
    b.getInstallStep().dependOn(&install_fdate.step);

    const just = addZigExecutable(b, "just", "just.zig", target, optimize, false);
    const install_just = b.addInstallArtifact(just, .{});
    b.getInstallStep().dependOn(&install_just.step);

    const menudriver = addCExecutable(b, "menudriver", &.{"menudriver.c"}, target, optimize);
    menudriver.root_module.addObject(signals_zig);
    const install_menudriver = b.addInstallArtifact(menudriver, .{
        .dest_dir = .{ .override = .{ .custom = "lib/miralib" } },
    });
    b.getInstallStep().dependOn(&install_menudriver.step);

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
    test_step.dependOn(&run_mira_tests.step);

    const test_mira = b.step("test-mira", "Run Zig integration tests against mira");
    test_mira.dependOn(&run_mira_tests.step);

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
    check_step.dependOn(&run_mira_tests.step);

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

fn addMira(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    utf8_zig: *std.Build.Step.Compile,
    signals_zig: *std.Build.Step.Compile,
    version_zig: *std.Build.Step.Compile,
    cmbnms_zig: *std.Build.Step.Compile,
) *std.Build.Step.Compile {
    const mira = addCExecutable(b, "mira", &c_sources, target, optimize);
    mira.root_module.addObject(utf8_zig);
    mira.root_module.addObject(signals_zig);
    mira.root_module.addObject(version_zig);
    mira.root_module.addObject(cmbnms_zig);
    mira.linkSystemLibrary("m");
    return mira;
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
    exe.addIncludePath(b.path("."));
    exe.addCSourceFiles(.{
        .files = sources,
        .flags = &c_flags,
    });
    addPlatformMacros(exe, target);
    exe.linkLibC();
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
    check.addIncludePath(b.path("."));
    check.addCSourceFile(.{
        .file = source,
        .flags = &c_flags,
    });
    addPlatformMacros(check, target);
    check.linkLibC();
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
    return b.addObject(.{
        .name = name,
        .root_module = b.createModule(.{
            .root_source_file = b.path(path),
            .target = target,
            .optimize = optimize,
            .link_libc = link_libc,
        }),
    });
}

fn addVersionObject(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) *std.Build.Step.Compile {
    const version_text = readTrimmed(b, "miralib/.version");
    const vdate = readTrimmed(b, ".vdate");
    const host = readTrimmed(b, ".host");

    const options = b.addOptions();
    options.addOption(i32, "version", parseVersion(version_text));
    options.addOption([]const u8, "vdate", vdate);
    options.addOption([]const u8, "host", b.fmt("compiled by zig build\n{s}\n", .{host}));

    const version = addZigObject(b, "version-zig", "version.zig", target, optimize, false);
    version.root_module.addOptions("version_options", options);
    return version;
}

fn addPlatformMacros(exe: *std.Build.Step.Compile, target: std.Build.ResolvedTarget) void {
    if (target.result.os.tag == .macos) {
        exe.root_module.addCMacro("_DARWIN_C_SOURCE", "1");
    } else {
        exe.root_module.addCMacro("_POSIX_C_SOURCE", "200809L");
    }
}

fn readTrimmed(b: *std.Build, path: []const u8) []const u8 {
    const contents = std.fs.cwd().readFileAlloc(b.allocator, path, 4096) catch |err| {
        std.debug.panic("failed to read {s}: {}", .{ path, err });
    };
    return std.mem.trim(u8, contents, " \t\r\n");
}

fn parseVersion(text: []const u8) i32 {
    return std.fmt.parseInt(i32, text, 10) catch |err| {
        std.debug.panic("failed to parse miralib/.version value '{s}': {}", .{ text, err });
    };
}
