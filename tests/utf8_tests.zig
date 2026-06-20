const std = @import("std");
const testing = std.testing;

const utf8 = @import("utf8");

var mock_read_buf: []const u8 = &.{};
var mock_read_idx: usize = 0;

var mock_write_buf: [100]u8 = undefined;
var mock_write_len: usize = 0;

export fn getc(fil: ?*utf8.FILE) c_int {
    _ = fil;
    if (mock_read_idx >= mock_read_buf.len) {
        return -1;
    }
    const byte = mock_read_buf[mock_read_idx];
    mock_read_idx += 1;
    return byte;
}

export fn putc(ch: c_int, fil: ?*utf8.FILE) c_int {
    _ = fil;
    if (mock_write_len < mock_write_buf.len) {
        mock_write_buf[mock_write_len] = @intCast(ch);
        mock_write_len += 1;
    }
    return ch;
}

test "fromUTF8 - successful decoding" {
    const Case = struct {
        bytes: []const u8,
        expected: c_ulong,
    };
    const cases = [_]Case{
        .{ .bytes = &.{0x41}, .expected = 0x41 }, // ascii
        .{ .bytes = &.{0xc2, 0xa3}, .expected = 0x00a3 }, // two-byte
        .{ .bytes = &.{0xe2, 0x82, 0xac}, .expected = 0x20ac }, // three-byte
        .{ .bytes = &.{0xf0, 0x9f, 0x98, 0x80}, .expected = 0x1f600 }, // four-byte
    };

    for (cases) |c| {
        mock_read_buf = c.bytes;
        mock_read_idx = 0;
        const actual = utf8.fromUTF8(null);
        try testing.expectEqual(c.expected, actual);
    }
}

test "outUTF8 - successful encoding" {
    const Case = struct {
        val: c_ulong,
        expected: []const u8,
    };
    const cases = [_]Case{
        .{ .val = 0x41, .expected = &.{0x41} },
        .{ .val = 0x00a3, .expected = &.{0xc2, 0xa3} },
        .{ .val = 0x20ac, .expected = &.{0xe2, 0x82, 0xac} },
        .{ .val = 0x1f600, .expected = &.{0xf0, 0x9f, 0x98, 0x80} },
    };

    for (cases) |c| {
        mock_write_len = 0;
        utf8.outUTF8(c.val, null);
        try testing.expectEqualSlices(u8, c.expected, mock_write_buf[0..mock_write_len]);
    }
}

fn fatalFromUTF8(bytes: []const u8) void {
    mock_read_buf = bytes;
    mock_read_idx = 0;
    _ = utf8.fromUTF8(null);
}

fn fatalOutUTF8(val: c_ulong) void {
    utf8.outUTF8(val, null);
}

fn runExpectFatal(action: anytype, arg: anytype, expected_stderr: []const u8) !void {
    var pipe_fds: [2]c_int = undefined;
    _ = std.posix.system.pipe(&pipe_fds);

    const S = struct {
        extern fn fork() c_int;
    };
    const pid = S.fork();
    if (pid == -1) return error.ForkFailed;

    if (pid == 0) {
        // Child
        _ = std.posix.system.close(pipe_fds[0]);
        _ = std.posix.system.dup2(pipe_fds[1], std.posix.STDERR_FILENO);
        _ = std.posix.system.close(pipe_fds[1]);

        action(arg);
        std.process.exit(0);
    } else {
        // Parent
        _ = std.posix.system.close(pipe_fds[1]);
        var buf: [512]u8 = undefined;
        var total_read: usize = 0;
        while (true) {
            const rc = std.posix.system.read(pipe_fds[0], buf[total_read..].ptr, buf[total_read..].len);
            if (rc < 0) return error.ReadFailed;
            if (rc == 0) break;
            total_read += @intCast(rc);
        }
        _ = std.posix.system.close(pipe_fds[0]);

        var status: c_int = 0;
        _ = std.posix.system.waitpid(pid, @ptrCast(&status), 0);
        try testing.expect(status != 0);
        try testing.expectEqualStrings(expected_stderr, buf[0..total_read]);
    }
}


test "fromUTF8/outUTF8 - fatal cases" {
    // invalid lead byte
    try runExpectFatal(fatalFromUTF8, &.{0xff}, "protocol error - invalid sequence: 0xff\n");

    // incomplete two-byte sequence
    try runExpectFatal(fatalFromUTF8, &.{0xc2}, "protocol error - incomplete sequence: 0xc2 EOF\n");

    // out of range output (0x10ffff + 1 = 0x110000)
    try runExpectFatal(fatalOutUTF8, 0x110000, "char 0x110000 out of unicode range\n");
}
