const std = @import("std");

const c = @cImport({
    @cInclude("sys/ioctl.h");
    @cInclude("unistd.h");
});

const Word = c_long;
const CONS: u8 = 11;
const AP: u8 = 9;
const CMBASE: Word = 306;
const NIL: Word = CMBASE + 138;

extern var hd: [*]Word;
extern var tl: [*]Word;
extern var tag: [*]u8;

extern fn make(t: u8, x: Word, y: Word) Word;

fn h(x: Word) Word {
    return hd[@as(usize, @intCast(x)) * 2];
}

fn t(x: Word) Word {
    return tl[@as(usize, @intCast(x)) * 2];
}

fn cons(x: Word, y: Word) Word {
    return make(CONS, x, y);
}

export fn fm_time(path: [*:0]const u8) Word {
    const stat = std.fs.cwd().statFile(std.mem.span(path)) catch return 0;
    return @intCast(@divFloor(stat.mtime, std.time.ns_per_s));
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
    var input = std.fs.cwd().openFile(std.mem.span(path), .{}) catch return;
    defer input.close();
    var stdout = std.io.getStdOut();
    copyFile(&input, &stdout) catch return;
}

export fn filecp(from: [*:0]const u8, to: [*:0]const u8) void {
    var input = std.fs.cwd().openFile(std.mem.span(from), .{}) catch return;
    defer input.close();
    var output = std.fs.cwd().createFile(std.mem.span(to), .{ .mode = 0o644 }) catch return;
    defer output.close();
    copyFile(&input, &output) catch return;
}

fn copyFile(input: *std.fs.File, output: *std.fs.File) !void {
    var buffer: [512]u8 = undefined;
    while (true) {
        const n = try input.read(&buffer);
        if (n == 0) break;
        try output.writeAll(buffer[0..n]);
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
