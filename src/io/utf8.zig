const std = @import("std");

pub const FILE = opaque {};
extern fn getc(fil: ?*FILE) c_int;
extern fn putc(ch: c_int, fil: ?*FILE) c_int;
const EOF: c_int = -1;

export fn fromUTF8(fil: ?*FILE) c_ulong {
    const c0 = getc(fil);
    if (c0 == EOF) {
        return std.math.maxInt(c_ulong);
    }
    if (c0 <= 0x7f) {
        return @intCast(c0);
    }

    if ((c0 & 0xe0) == 0xc0) {
        const c1 = getc(fil);
        if (c1 == EOF or (c1 & 0xc0) != 0x80) {
            reportError(&.{ c0, c1 });
        }
        return @intCast(((c0 & 0x1f) << 6) | (c1 & 0x3f));
    }

    if ((c0 & 0xf0) == 0xe0) {
        const c1 = getc(fil);
        if (c1 == EOF or (c1 & 0xc0) != 0x80) {
            reportError(&.{ c0, c1 });
        }
        const c2 = getc(fil);
        if (c2 == EOF or (c2 & 0xc0) != 0x80) {
            reportError(&.{ c0, c1, c2 });
        }
        return @intCast(((c0 & 0x0f) << 12) | ((c1 & 0x3f) << 6) | (c2 & 0x3f));
    }

    if ((c0 & 0xf8) == 0xf0) {
        const c1 = getc(fil);
        if (c1 == EOF or (c1 & 0xc0) != 0x80) {
            reportError(&.{ c0, c1 });
        }
        const c2 = getc(fil);
        if (c2 == EOF or (c2 & 0xc0) != 0x80) {
            reportError(&.{ c0, c1, c2 });
        }
        const c3 = getc(fil);
        if (c3 == EOF or (c3 & 0xc0) != 0x80) {
            reportError(&.{ c0, c1, c2, c3 });
        }
        return @intCast(((c0 & 0x07) << 18) | ((c1 & 0x3f) << 12) | ((c2 & 0x3f) << 6) | (c3 & 0x3f));
    }

    reportError(&.{c0});
}

export fn outUTF8(u: c_ulong, fil: ?*FILE) void {
    if (u <= 0x7f) {
        out(u, fil);
    } else if (u <= 0x7ff) {
        out(0xc0 | ((u & 0x7c0) >> 6), fil);
        out(0x80 | (u & 0x3f), fil);
    } else if (u <= 0xffff) {
        out(0xe0 | ((u & 0xf000) >> 12), fil);
        out(0x80 | ((u & 0x0fc0) >> 6), fil);
        out(0x80 | (u & 0x3f), fil);
    } else if (u <= 0x10ffff) {
        out(0xf0 | ((u & 0x1c0000) >> 18), fil);
        out(0x80 | ((u & 0x03f000) >> 12), fil);
        out(0x80 | ((u & 0x000fc0) >> 6), fil);
        out(0x80 | (u & 0x3f), fil);
    } else {
        std.debug.print("char 0x{x} out of unicode range\n", .{u});
        std.process.exit(1);
    }
}

fn out(byte: c_ulong, fil: ?*FILE) void {
    _ = putc(@intCast(byte), fil);
}

fn reportError(bytes: []const c_int) noreturn {
    var incomplete = false;
    for (bytes) |byte| {
        if (byte == EOF) {
            incomplete = true;
            break;
        }
    }

    const kind = if (incomplete) "incomplete" else "invalid";
    std.debug.print("protocol error - {s} sequence:", .{kind});
    for (bytes) |byte| {
        if (byte == EOF) {
            std.debug.print(" EOF", .{});
        } else {
            std.debug.print(" 0x{x}", .{@as(c_uint, @intCast(byte))});
        }
    }
    std.debug.print("\n", .{});
    std.process.exit(1);
}
