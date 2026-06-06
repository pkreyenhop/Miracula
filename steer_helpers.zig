const std = @import("std");

const c = @cImport({
    @cInclude("sys/ioctl.h");
    @cInclude("unistd.h");
    @cInclude("sys/stat.h");
    @cInclude("fcntl.h");
    @cInclude("stdio.h");
});

const Word = c_long;
const CONS: u8 = 11;
const AP: u8 = 9;
const CMBASE: Word = 306;
const NIL: Word = CMBASE + 138;
const ATOMLIMIT: Word = CMBASE + 141;

extern var hd: [*]Word;
extern var tl: [*]Word;
extern var tag: [*]u8;

extern fn make(t: u8, x: Word, y: Word) Word;

var test_heap_heads: [2]Word = .{ 0, 0 };
var test_heap_tails: [2]Word = .{ 0, 0 };
var test_heap_tags: [1]u8 = .{0};
var test_hd: [*]Word = test_heap_heads[0..].ptr;
var test_tl: [*]Word = test_heap_tails[0..].ptr;
var test_tag: [*]u8 = test_heap_tags[0..].ptr;

comptime {
    if (@import("builtin").is_test) {
        @export(&test_hd, .{ .name = "hd" });
        @export(&test_tl, .{ .name = "tl" });
        @export(&test_tag, .{ .name = "tag" });
        @export(&testMake, .{ .name = "make" });
    }
}

fn testMake(_: u8, _: Word, _: Word) callconv(.c) Word {
    unreachable;
}

fn h(x: Word) Word {
    if (x < ATOMLIMIT) return 0;
    return hd[@as(usize, @intCast(x)) * 2];
}

fn t(x: Word) Word {
    if (x < ATOMLIMIT) return 0;
    return tl[@as(usize, @intCast(x)) * 2];
}

fn cons(x: Word, y: Word) Word {
    return make(CONS, x, y);
}

export fn fm_time(path: [*:0]const u8) Word {
    var stat: c.struct_stat = undefined;
    if (c.stat(path, &stat) != 0) return 0;
    if (comptime @hasField(c.struct_stat, "st_mtim")) {
        return @intCast(stat.st_mtim.tv_sec);
    } else if (comptime @hasField(c.struct_stat, "st_mtimespec")) {
        return @intCast(stat.st_mtimespec.tv_sec);
    } else {
        return @intCast(stat.st_mtime);
    }
}

export fn normal(path: [*:0]const u8) c_int {
    const text = std.mem.span(path);
    return if (text.len >= 2 and std.mem.eql(u8, text[text.len - 2 ..], ".m")) 1 else 0;
}

export fn reverse(input: Word) Word {
    var x = input;
    var y: Word = NIL;
    while (x != NIL) {
        y = cons(h(x), y);
        x = t(x);
    }
    return y;
}

export fn shunt(input_x: Word, input_y: Word) Word {
    var x = input_x;
    var y = input_y;
    while (x != NIL) {
        y = cons(h(x), y);
        x = t(x);
    }
    return y;
}

export fn size(input: Word) Word {
    var x = input;
    var s: Word = 0;
    while (tag[@intCast(x)] == CONS or tag[@intCast(x)] == AP) {
        s += 1 + size(h(x));
        x = t(x);
    }
    return s;
}

export fn filecopy(path: [*:0]const u8) void {
    const fd = c.open(path, c.O_RDONLY);
    if (fd < 0) return;
    defer _ = c.close(fd);

    var buffer: [512]u8 = undefined;
    while (true) {
        const n = c.read(fd, &buffer, buffer.len);
        if (n <= 0) break;
        _ = c.write(c.STDOUT_FILENO, &buffer, @intCast(n));
    }
}

export fn filecp(from: [*:0]const u8, to: [*:0]const u8) void {
    const f_in = c.open(from, c.O_RDONLY);
    if (f_in < 0) return;
    defer _ = c.close(f_in);

    const f_out = c.open(to, c.O_WRONLY | c.O_CREAT | c.O_TRUNC, @as(c_uint, 0o644));
    if (f_out < 0) return;
    defer _ = c.close(f_out);

    var buffer: [512]u8 = undefined;
    while (true) {
        const n = c.read(f_in, &buffer, buffer.len);
        if (n <= 0) break;
        _ = c.write(f_out, &buffer, @intCast(n));
    }
}

export fn twidth() c_int {
    var window: c.struct_winsize = undefined;
    if (c.ioctl(c.STDOUT_FILENO, c.TIOCGWINSZ, &window) == -1 or window.ws_col == 0) {
        return 78;
    }
    return @as(c_int, @intCast(window.ws_col)) - 2;
}

test "normal recognizes Miranda source suffix" {
    try std.testing.expect(normal("script.m") == 1);
    try std.testing.expect(normal("script.x") == 0);
    try std.testing.expect(normal("m") == 0);
}
