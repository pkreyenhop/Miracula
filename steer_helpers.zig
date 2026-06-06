const std = @import("std");

const c = @cImport({
    @cInclude("sys/ioctl.h");
    @cInclude("unistd.h");
    @cInclude("sys/stat.h");
    @cInclude("fcntl.h");
    @cInclude("stdio.h");
    @cInclude("data.h");
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

extern fn sto_dbl(d: f64) Word;
extern var version: c_int;
extern var obsuffix: [*:0]const u8;
extern var TABSTRS: Word;
extern var SGC: Word;
extern var speclocs: Word;
extern var newtyps: Word;
extern var rv_script: Word;
extern var algshfns: Word;
extern var nextpn: Word;
extern var includees: Word;
extern var freeids: Word;
extern var internals: Word;
extern var files: Word;
extern var ld_stuff: Word;
extern var sorted: c_int;
extern var ND: Word;

var vstack: [4]c_int = undefined;
var mstack: [4][*:0]const u8 = undefined;
var mvp: usize = 0;
var vbuf: [12]u8 = undefined;

fn hp(x: Word) *Word {
    return &hd[@as(usize, @intCast(x)) * 2];
}

fn tp(x: Word) *Word {
    return &tl[@as(usize, @intCast(x)) * 2];
}

export fn mktiny() Word {
    var x: f64 = 1.0;
    var x1: f64 = x / 2.0;
    while (x1 > 0.0) {
        x = x1;
        x1 = x1 / 2.0;
    }
    return sto_dbl(x);
}

export fn checkversion(m: [*:0]const u8) c_int {
    var path_buf: [1024]u8 = undefined;
    const path = std.fmt.bufPrintZ(&path_buf, "{s}/.version", .{m}) catch return 0;
    const f = c.fopen(path.ptr, "r");
    var v1: c_uint = 0;
    var read_ok: bool = false;
    var r: c_int = 0;
    if (f != null) {
        if (c.fscanf(f, "%u", &v1) == 1) {
            r = if (v1 == version) 1 else 0;
            read_ok = true;
        }
        _ = c.fclose(f);
    }
    if (read_ok and r == 0) {
        if (mvp < 4) {
            mstack[mvp] = m;
            vstack[mvp] = @intCast(v1);
            mvp += 1;
        }
    }
    return r;
}

fn getStderr() ?*c.FILE {
    const T = @TypeOf(c.stderr);
    if (comptime @typeInfo(T) == .@"fn") {
        return c.stderr();
    } else if (comptime @typeInfo(T) == .pointer and @typeInfo(@typeInfo(T).pointer.child) == .@"fn") {
        return c.stderr();
    } else {
        return c.stderr;
    }
}

export fn libfails() void {
    const stderr = getStderr().?;
    _ = c.fprintf(stderr, "found");
    var i: usize = 0;
    while (i < mvp) : (i += 1) {
        _ = c.fprintf(stderr, "\tversion %s at: %s\n", strvers(vstack[i]), mstack[i]);
    }
}

export fn strvers(v: c_int) [*:0]const u8 {
    if (v < 0 or v > 999999) {
        return "???";
    }
    _ = c.snprintf(&vbuf, vbuf.len, "%.3f", @as(f64, @floatFromInt(v)) / 1000.0);
    return @ptrCast(&vbuf);
}

export fn unlinkx(t_path: [*:0]const u8) void {
    var obf_buf: [1024]u8 = undefined;
    const t_slice = std.mem.span(t_path);
    if (t_slice.len == 0) return;
    const len = t_slice.len;
    
    // Copy the path up to len - 1
    @memcpy(obf_buf[0 .. len - 1], t_slice[0 .. len - 1]);
    
    // Copy obsuffix
    const obsuffix_slice = std.mem.span(obsuffix);
    @memcpy(obf_buf[len - 1 .. len - 1 + obsuffix_slice.len], obsuffix_slice);
    obf_buf[len - 1 + obsuffix_slice.len] = 0;
    
    const obf = @as([*:0]const u8, @ptrCast(obf_buf[0..].ptr));
    var stat_buf: c.struct_stat = undefined;
    if (c.stat(obf, &stat_buf) == 0) {
        _ = c.unlink(obf);
    }
}

export fn unsetids(d_val: Word) void {
    var d = d_val;
    while (d != NIL) : (d = t(d)) {
        const item = h(d);
        if (tag[@intCast(item)] == c.ID) {
            tp(item).* = c.UNDEF;
            tp(h(h(item))).* = c.NIL;
            tp(h(item)).* = c.undef_t;
        }
    }
}

export fn unload() void {
    sorted = 0;
    speclocs = NIL;
    nextpn = 0;
    rv_script = 0;
    algshfns = NIL;
    unsetids(newtyps);
    newtyps = NIL;
    unsetids(freeids);
    freeids = NIL;
    includees = NIL;
    SGC = NIL;
    TABSTRS = NIL;
    ND = NIL;
    unsetids(internals);
    internals = NIL;
    while (files != NIL) : (files = t(files)) {
        const fil = h(files);
        unsetids(t(fil));
        tp(fil).* = c.NIL;
    }
    var ld = ld_stuff;
    while (ld != NIL) : (ld = t(ld)) {
        var x = h(ld);
        while (x != NIL) : (x = t(x)) {
            unsetids(t(h(x)));
        }
    }
    ld_stuff = NIL;
}

test "normal recognizes Miranda source suffix" {
    try std.testing.expect(normal("script.m") == 1);
    try std.testing.expect(normal("script.x") == 0);
    try std.testing.expect(normal("m") == 0);
}
