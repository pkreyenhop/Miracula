//! platform.zig — OS abstraction for the few syscalls the interpreter needs.
//!
//! Wraps `errno`, file `stat`, and effective uid/gid behind a small API, with a
//! Linux (`statx`) branch and a BSD/macOS (`stat`) branch selected at comptime.
//! Used by the loader (file freshness/identity) and the `filemode`/`filestat`
//! built-ins.

const std = @import("std");
const builtin = @import("builtin");
const is_linux = builtin.os.tag == .linux;

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
/// The process's effective user id.
pub const geteuid = platform_impl.geteuid;
/// The process's effective group id.
pub const getegid = platform_impl.getegid;
