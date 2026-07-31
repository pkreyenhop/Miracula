//! platform.zig — OS abstraction for the few syscalls the interpreter needs.
//!
//! Wraps `errno`, file `stat`, and effective uid/gid behind a small API, with a
//! Linux (`statx`) branch and a BSD/macOS (`stat`) branch selected at comptime.
//! Used by the loader (file freshness/identity) and the `filemode`/`filestat`
//! built-ins.

const std = @import("std");
const builtin = @import("builtin");
const contract = @import("platform_contract.zig");
const is_linux = builtin.os.tag == .linux;
extern fn isatty(descriptor: c_int) c_int;
extern fn ioctl(descriptor: c_int, request: c_ulong, arg: *WindowSize) c_int;

const WindowSize = extern struct {
    rows: u16,
    columns: u16,
    x_pixels: u16,
    y_pixels: u16,
};

comptime {
    const supported = (builtin.os.tag == .macos and builtin.cpu.arch == .aarch64) or
        (builtin.os.tag == .linux and builtin.cpu.arch == .x86_64);
    if (!supported) {
        @compileError("unsupported target: supported targets are aarch64-macos and x86_64-linux");
    }
}

/// The subset of `stat` fields the interpreter uses: identity (`ino`/`dev`),
/// modification time, and the permission/ownership bits for `filemode`.
pub const FileInfo = struct {
    ino: u64,
    dev: u64,
    mtime: i64,
    mode: u32,
    uid: u32,
    gid: u32,
};

const platform_impl = if (is_linux) struct {
    extern fn __errno_location() *c_int;
    ///
    pub fn getErrno() i32 {
        return @intCast(__errno_location().*);
    }
    ///
    pub fn setErrno(val: i32) void {
        __errno_location().* = @intCast(val);
    }

    ///
    pub fn getFileInfo(path: ?[*:0]const u8) ?FileInfo {
        const p = path orelse return null;
        var statx = std.mem.zeroes(std.os.linux.Statx);
        const AT_FDCWD = -100;
        const mask = std.os.linux.STATX{ .INO = true, .MTIME = true, .MODE = true, .UID = true, .GID = true };
        const rc = std.os.linux.statx(AT_FDCWD, p, 0, mask, &statx);
        if (rc == 0) {
            const dev = (@as(u64, statx.dev_major) << 32) | statx.dev_minor;
            return FileInfo{
                .ino = statx.ino,
                .dev = dev,
                .mtime = statx.mtime.sec,
                .mode = statx.mode,
                .uid = statx.uid,
                .gid = statx.gid,
            };
        }
        return null;
    }

    ///
    pub fn geteuid() u32 {
        return std.os.linux.geteuid();
    }

    ///
    pub fn getegid() u32 {
        return std.os.linux.getegid();
    }
} else struct {
    extern fn __error() *c_int;
    extern fn stat(path: [*:0]const u8, buf: *std.posix.system.Stat) c_int;

    ///
    pub fn getErrno() i32 {
        return @intCast(__error().*);
    }
    ///
    pub fn setErrno(val: i32) void {
        __error().* = @intCast(val);
    }

    ///
    pub fn getFileInfo(path: ?[*:0]const u8) ?FileInfo {
        const p = path orelse return null;
        var stat_buf: std.posix.system.Stat = undefined;
        if (stat(p, &stat_buf) == 0) {
            const mtime: i64 = blk: {
                if (comptime @hasField(std.posix.system.Stat, "mtim")) {
                    break :blk stat_buf.mtim.sec;
                } else if (comptime @hasField(std.posix.system.Stat, "mtimespec")) {
                    break :blk stat_buf.mtimespec.sec;
                } else if (comptime @hasField(std.posix.system.Stat, "mtime")) {
                    break :blk stat_buf.mtime;
                } else {
                    break :blk 0;
                }
            };
            return FileInfo{
                .ino = @intCast(stat_buf.ino),
                .dev = @intCast(stat_buf.dev),
                .mtime = mtime,
                .mode = @intCast(stat_buf.mode),
                .uid = @intCast(stat_buf.uid),
                .gid = @intCast(stat_buf.gid),
            };
        }
        return null;
    }

    ///
    pub fn geteuid() u32 {
        return std.posix.system.geteuid();
    }

    ///
    pub fn getegid() u32 {
        return std.posix.system.getegid();
    }
};

/// `stat` a file, returning its size/mtime/inode info (platform-specific impl).
pub const getFileInfo = platform_impl.getFileInfo;
/// Read the current `errno` value.
pub const getErrno = platform_impl.getErrno;
/// Set the current `errno` value.
pub const setErrno = platform_impl.setErrno;
pub fn setDomainError() void {
    setErrno(@intCast(@intFromEnum(std.posix.E.DOM)));
}
/// The process's effective user id.
pub const geteuid = platform_impl.geteuid;
/// The process's effective group id.
pub const getegid = platform_impl.getegid;

pub fn monotonicNs() i128 {
    var ts: std.posix.timespec = undefined;
    _ = std.posix.system.clock_gettime(std.posix.CLOCK.MONOTONIC, &ts);
    return @as(i128, ts.sec) * std.time.ns_per_s + ts.nsec;
}

pub fn isTerminal(descriptor: i32) bool {
    return isatty(@intCast(descriptor)) != 0;
}

pub fn terminalWidth(descriptor: i32) ?u16 {
    var size: WindowSize = undefined;
    const request: c_ulong = if (builtin.os.tag == .macos) 0x40087468 else 0x5413;
    if (ioctl(@intCast(descriptor), request, &size) != 0 or size.columns == 0) return null;
    return size.columns;
}

/// Execute `shell -c command`, inheriting the parent's environment, working
/// directory, and standard streams. Waiting is mandatory before return.
pub fn runShell(io: std.Io, shell: []const u8, command: []const u8) contract.ProcessError!contract.ProcessOutcome {
    const argv = [_][]const u8{ shell, contract.ShellContract.command_argument, command };
    var child = std.process.spawn(io, .{
        .argv = &argv,
        .stdin = .inherit,
        .stdout = .inherit,
        .stderr = .inherit,
    }) catch return error.SpawnFailed;
    const term = child.wait(io) catch return error.WaitFailed;
    return switch (term) {
        .exited => |code| .{ .exited = @intCast(@min(code, std.math.maxInt(u8))) },
        .signal => |signal| .{ .signaled = @intCast(@min(@intFromEnum(signal), std.math.maxInt(u8))) },
        else => .{ .signaled = 0 },
    };
}

test "shell execution maps exit and signal termination without wait bits" {
    try std.testing.expectEqual(
        contract.ProcessOutcome{ .exited = 7 },
        try runShell(std.testing.io, contract.ShellContract.fallback_path, "exit 7"),
    );
    try std.testing.expectEqual(
        contract.ProcessOutcome{ .signaled = 15 },
        try runShell(std.testing.io, contract.ShellContract.fallback_path, "kill -TERM $$"),
    );
    try std.testing.expectError(
        error.SpawnFailed,
        runShell(std.testing.io, "/definitely/not/a/shell", "true"),
    );
}
