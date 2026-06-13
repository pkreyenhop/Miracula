const std = @import("std");
const builtin = @import("builtin");
const is_linux = builtin.os.tag == .linux;

const clib = if (is_linux) struct {} else @cImport({
    @cInclude("sys/stat.h");
    @cInclude("unistd.h");
});

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
    pub fn getErrno() c_int {
        return __error().*;
    }
    pub fn setErrno(val: c_int) void {
        __error().* = val;
    }

    pub fn getFileInfo(path: ?[*:0]const u8) ?FileInfo {
        const p = path orelse return null;
        var stat_buf: clib.struct_stat = undefined;
        if (clib.stat(p, &stat_buf) == 0) {
            const mtime: i64 = blk: {
                if (comptime @hasField(clib.struct_stat, "st_mtim")) {
                    break :blk stat_buf.st_mtim.tv_sec;
                } else if (comptime @hasField(clib.struct_stat, "st_mtimespec")) {
                    break :blk stat_buf.st_mtimespec.tv_sec;
                } else {
                    break :blk stat_buf.st_mtime;
                }
            };
            return FileInfo{
                .ino = @intCast(stat_buf.st_ino),
                .dev = @intCast(stat_buf.st_dev),
                .mtime = mtime,
                .mode = @intCast(stat_buf.st_mode),
                .uid = @intCast(stat_buf.st_uid),
                .gid = @intCast(stat_buf.st_gid),
            };
        }
        return null;
    }

    pub fn geteuid() u32 {
        return std.c.geteuid();
    }

    pub fn getegid() u32 {
        return std.c.getegid();
    }
};

pub const getFileInfo = platform_impl.getFileInfo;
pub const getErrno = platform_impl.getErrno;
pub const setErrno = platform_impl.setErrno;
pub const geteuid = platform_impl.geteuid;
pub const getegid = platform_impl.getegid;
