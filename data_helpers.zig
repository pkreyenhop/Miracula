const std = @import("std");

const c = @cImport({
    @cInclude("stdio.h");
    @cInclude("stdlib.h");
    @cInclude("signal.h");
});

const Word = c_long;
const DOUBLE: u8 = 1;
const ID: u8 = 8;
const UNICODE: u8 = 21;
const CONS: u8 = 11;

extern var hd: [*]Word;
extern var tl: [*]Word;
extern var tag: [*]u8;

extern fn make(t: u8, x: Word, y: Word) Word;
extern fn reverse(x: Word) Word;
extern fn strcmp(a: [*:0]const u8, b: [*:0]const u8) c_int;
extern fn fpe_error(sig: c_int) void;

const fpdatum = if (@sizeOf(Word) == 4)
    extern union {
        real: f64,
        bits: extern struct {
            left: Word,
            right: Word,
        },
    }
else if (@sizeOf(Word) == 8)
    extern union {
        real: f64,
        bits: Word,
    }
else
    @compileError("platform has unknown word size");

const ATOMLIMIT: Word = 447;
var charname_buffer: [8]u8 = undefined;

fn h(x: Word) Word {
    if (x < ATOMLIMIT) return 0;
    return hd[@as(usize, @intCast(x)) * 2];
}

fn hp(x: Word) *Word {
    std.debug.assert(x >= ATOMLIMIT);
    return &hd[@as(usize, @intCast(x)) * 2];
}

fn t(x: Word) Word {
    if (x < ATOMLIMIT) return 0;
    return tl[@as(usize, @intCast(x)) * 2];
}

fn tp(x: Word) *Word {
    std.debug.assert(x >= ATOMLIMIT);
    return &tl[@as(usize, @intCast(x)) * 2];
}

fn cons(x: Word, y: Word) Word {
    return make(CONS, x, y);
}

fn idWho(x: Word) Word {
    return t(h(h(x)));
}

fn getId(x: Word) [*:0]const u8 {
    return @ptrFromInt(@as(usize, @intCast(h(h(h(x))))));
}

export fn sto_char(ch: c_int) Word {
    return if (ch < 256) ch else make(UNICODE, ch, 0);
}

export fn get_char(x: Word) Word {
    if (x < 256) return x;
    if (tag[@intCast(x)] == UNICODE) return h(x);
    std.debug.print("impossible event in get_char(x), tag[x]=={d}\n", .{tag[@intCast(x)]});
    c.exit(1);
}

export fn is_char(x: Word) c_int {
    if (0 <= x and x < 256) return 1;
    if (x >= 0 and tag[@intCast(x)] == UNICODE) return 1;
    return 0;
}

export fn get_here(x: Word) Word {
    const y = idWho(x);
    return if (tag[@intCast(y)] == CONS) t(y) else y;
}

export fn getaka(x: Word) [*:0]const u8 {
    const y = idWho(x);
    return if (tag[@intCast(y)] != CONS) getId(x) else @ptrFromInt(@as(usize, @intCast(h(h(y)))));
}

export fn append1(x: Word, y: Word) Word {
    var x1 = x;
    if (x1 == nil()) return y;
    while (t(x1) != nil()) x1 = t(x1);
    tp(x1).* = y;
    return x;
}

export fn hdsort(input: Word) Word {
    var x = input;
    var a: Word = nil();
    var b: Word = nil();
    if (x == nil()) return nil();
    if (t(x) == nil()) return x;
    while (x != nil()) {
        const hold = a;
        a = cons(h(x), b);
        b = hold;
        x = t(x);
    }
    a = hdsort(a);
    b = hdsort(b);
    while (a != nil() and b != nil()) {
        if (strcmp(getId(h(h(a))), getId(h(h(b)))) < 0) {
            x = cons(h(a), x);
            a = t(a);
        } else {
            x = cons(h(b), x);
            b = t(b);
        }
    }
    if (a == nil()) a = b;
    while (a != nil()) {
        x = cons(h(a), x);
        a = t(a);
    }
    return reverse(x);
}

export fn charname(ch: Word) [*:0]const u8 {
    return switch (ch) {
        '\n' => "\\n",
        '\t' => "\\t",
        '\x08' => "\\b",
        '\x0c' => "\\f",
        '\r' => "\\r",
        '\\' => "\\\\",
        '\'' => "\\'",
        '"' => "\\\"",
        else => blk: {
            if (ch < 32 or ch > 126) {
                const text = std.fmt.bufPrintZ(&charname_buffer, "\\{d}", .{ch}) catch unreachable;
                break :blk text.ptr;
            }
            charname_buffer[0] = @intCast(ch);
            charname_buffer[1] = 0;
            break :blk @as([*:0]const u8, @ptrCast(charname_buffer[0..].ptr));
        },
    };
}

export fn outr(file: ?*c.FILE, value: f64) void {
    const magnitude = if (value < 0) -value else value;
    if (magnitude >= 1000.0 or magnitude <= 0.001) {
        _ = c.fprintf(file, "%e", value);
    } else {
        _ = c.fprintf(file, "%f", value);
    }
}

export fn get_dbl(x: Word) f64 {
    var r: fpdatum = undefined;
    if (comptime @sizeOf(Word) == 4) {
        r.bits.left = h(x);
        r.bits.right = t(x);
    } else {
        r.bits = h(x);
    }
    return r.real;
}

export fn sto_dbl(R: f64) Word {
    if (!std.math.isFinite(R)) {
        fpe_error(c.SIGFPE);
    }
    var r: fpdatum = undefined;
    r.real = R;
    if (comptime @sizeOf(Word) == 4) {
        return make(DOUBLE, r.bits.left, r.bits.right);
    } else {
        return make(DOUBLE, r.bits, 0);
    }
}

export fn setdbl(x: Word, R: f64) void {
    if (!std.math.isFinite(R)) {
        fpe_error(c.SIGFPE);
    }
    var r: fpdatum = undefined;
    r.real = R;
    tag[@intCast(x)] = DOUBLE;
    if (comptime @sizeOf(Word) == 4) {
        hp(x).* = r.bits.left;
        tp(x).* = r.bits.right;
    } else {
        hp(x).* = r.bits;
        tp(x).* = 0;
    }
}

fn nil() Word {
    return 306 + 138;
}

test "sto_char returns atoms for Latin-1 values" {
    try std.testing.expectEqual(@as(Word, 65), sto_char(65));
    try std.testing.expectEqual(@as(c_int, 1), is_char(65));
}
