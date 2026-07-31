//! Small, dependency-free compatibility helpers for translated C-style code.
//! Keep this layer below graph, evaluator, compiler, and session packages.

const std = @import("std");

pub const EOF: c_int = -1;

pub inline fn ptrInt(p: anytype) usize {
    return @intFromPtr(p);
}

pub fn strcmp(a: ?*const anyopaque, b: ?*const anyopaque) c_int {
    if (a == null or b == null) return 0;
    const sa = std.mem.span(@as([*:0]const u8, @ptrCast(a.?)));
    const sb = std.mem.span(@as([*:0]const u8, @ptrCast(b.?)));
    return switch (std.mem.order(u8, sa, sb)) {
        .lt => -1,
        .eq => 0,
        .gt => 1,
    };
}

pub fn strcpy(dst: ?*anyopaque, src: ?*const anyopaque) ?*anyopaque {
    if (dst == null or src == null) return dst;
    const d = @as([*]u8, @ptrCast(dst.?));
    const s = @as([*:0]const u8, @ptrCast(src.?));
    var i: usize = 0;
    while (s[i] != 0) : (i += 1) d[i] = s[i];
    d[i] = 0;
    return dst;
}

pub fn unlink(path: [*:0]const u8) c_int {
    const rc = std.posix.system.unlink(path);
    if (comptime @TypeOf(rc) == usize) {
        return @truncate(@as(isize, @bitCast(rc)));
    }
    return @intCast(rc);
}
