const std = @import("std");
const builtin = @import("builtin");
const is_linux = builtin.os.tag == .linux;

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
    pub fn getErrno() c_int {
        return __errno_location().*;
    }
    pub fn setErrno(val: c_int) void {
        __errno_location().* = val;
    }

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

    pub fn geteuid() u32 {
        return std.os.linux.geteuid();
    }

    pub fn getegid() u32 {
        return std.os.linux.getegid();
    }
} else struct {
    extern fn __error() *c_int;
    extern fn stat(path: [*:0]const u8, buf: *std.posix.system.Stat) c_int;

    pub fn getErrno() c_int {
        return __error().*;
    }
    pub fn setErrno(val: c_int) void {
        __error().* = val;
    }

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

    pub fn geteuid() u32 {
        return std.posix.system.geteuid();
    }

    pub fn getegid() u32 {
        return std.posix.system.getegid();
    }
};

pub const getFileInfo = platform_impl.getFileInfo;
pub const getErrno = platform_impl.getErrno;
pub const setErrno = platform_impl.setErrno;
pub const geteuid = platform_impl.geteuid;
pub const getegid = platform_impl.getegid;
