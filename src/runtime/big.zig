const std = @import("std");

const platform = @import("../io/platform.zig");
const heap = @import("heap.zig");

const Word = i64;

const SIGNBIT: Word = 0x10000000;
const IBASE: Word = 0x8000;
const MAXDIGIT: Word = 0x7fff;
const DIGITWIDTH: Word = 15;
const PTEN: Word = 10000;
const PSIXTEEN: Word = 4096;
const PEIGHT: Word = 0x8000;
const TENW: Word = 4;
const CONS: u8 = 11;
const INT: u8 = 5;
const CMBASE: Word = 306;
const NIL: Word = CMBASE + 138;
const ATOMLIMIT: Word = CMBASE + 141;



const make = heap.make;
extern fn math_error(s: [*:0]const u8) void;

var logIBASE: f64 = 0;
var log10IBASE: f64 = 0;
export var b_rem: Word = 0;
export var big_one: Word = 0;

inline fn getTag(x: Word) u8 {
    return heap.heap.getTag(x);
}

fn h(x: Word) Word {
    return heap.heap.h(x);
}

fn hp(x: Word) *Word {
    return heap.heap.hp(x);
}

fn t(x: Word) Word {
    return heap.heap.t(x);
}

fn tp(x: Word) *Word {
    return heap.heap.tp(x);
}

fn digit0(x: Word) Word {
    return h(x) & MAXDIGIT;
}

fn digit(x: Word) Word {
    return h(x);
}

fn digitp(x: Word) *Word {
    return hp(x);
}

fn rest(x: Word) Word {
    return t(x);
}

fn restp(x: Word) *Word {
    return tp(x);
}

fn poz(x: Word) bool {
    return (h(x) & SIGNBIT) == 0;
}

fn neg(x: Word) Word {
    return h(x) & SIGNBIT;
}

fn bigzero(x: Word) bool {
    return digit(x) == 0 and rest(x) == 0;
}

fn getsmallint(x: Word) Word {
    return if ((h(x) & SIGNBIT) != 0) -digit0(x) else digit(x);
}

fn cons(x: Word, y: Word) Word {
    return make(CONS, x, y);
}

export fn bigsetup() void {
    logIBASE = std.math.log(f64, std.math.e, @as(f64, @floatFromInt(IBASE)));
    log10IBASE = std.math.log10(@as(f64, @floatFromInt(IBASE)));
    big_one = make(INT, 1, 0);
}

export fn isnat(x: Word) c_int {
    return if (getTag(x) == INT and poz(x)) 1 else 0;
}

export fn sto_int(input: c_longlong) Word {
    var i = input;
    var s: Word = 0;
    if (i < 0) {
        s = SIGNBIT;
        i = -i;
    }
    var unsigned_i: c_ulonglong = @intCast(i);
    const x = make(INT, s | @as(Word, @intCast(unsigned_i & MAXDIGIT)), 0);
    unsigned_i >>= DIGITWIDTH;
    if (unsigned_i != 0) {
        var p = restp(x);
        p.* = make(INT, @intCast(unsigned_i & MAXDIGIT), 0);
        p = restp(p.*);
        unsigned_i >>= DIGITWIDTH;
        while (unsigned_i != 0) : (unsigned_i >>= DIGITWIDTH) {
            p.* = make(INT, @intCast(unsigned_i & MAXDIGIT), 0);
            p = restp(p.*);
        }
    }
    return x;
}

export fn get_int(input: Word) c_longlong {
    var x = input;
    var n: c_longlong = @intCast(digit0(x));
    const sign = neg(x) != 0;
    x = rest(x);
    if (x == 0) return if (sign) -n else n;

    var w: Word = DIGITWIDTH;
    while (x != 0 and w < 60) : ({
        w += DIGITWIDTH;
        x = rest(x);
    }) {
        n += @as(c_longlong, @intCast(digit(x))) << @intCast(w);
    }
    if (x != 0) n = @as(c_longlong, 1) << 60;
    return if (sign) -n else n;
}

export fn bignegate(x: Word) Word {
    if (bigzero(x)) return x;
    const d = if ((h(x) & SIGNBIT) != 0) h(x) & MAXDIGIT else SIGNBIT | h(x);
    return make(INT, d, rest(x));
}

export fn bigplus(x: Word, y: Word) Word {
    if (poz(x)) {
        if (poz(y)) return bigPlus(x, y, 0);
        return bigSub(x, y);
    }
    if (poz(y)) return bigSub(y, x);
    return bigPlus(x, y, SIGNBIT);
}

fn bigPlus(input_x: Word, input_y: Word, signbit: Word) Word {
    var x = input_x;
    var y = input_y;
    var d = digit0(x) + digit0(y);
    var carry: Word = if ((d & IBASE) != 0) 1 else 0;
    const r = make(INT, signbit | (d & MAXDIGIT), 0);
    var z = restp(r);
    x = rest(x);
    y = rest(y);
    while (x != 0 and y != 0) {
        d = carry + digit(x) + digit(y);
        carry = if ((d & IBASE) != 0) 1 else 0;
        z.* = make(INT, d & MAXDIGIT, 0);
        x = rest(x);
        y = rest(y);
        z = restp(z.*);
    }
    if (y != 0) x = y;
    while (x != 0) {
        d = carry + digit(x);
        carry = if ((d & IBASE) != 0) 1 else 0;
        z.* = make(INT, d & MAXDIGIT, 0);
        x = rest(x);
        z = restp(z.*);
    }
    if (carry != 0) z.* = make(INT, 1, 0);
    return r;
}

export fn bigsub(x: Word, y: Word) Word {
    if (poz(x)) {
        if (poz(y)) return bigSub(x, y);
        return bigPlus(x, y, 0);
    }
    if (poz(y)) return bigPlus(x, y, SIGNBIT);
    return bigSub(y, x);
}

fn bigSub(input_x: Word, input_y: Word) Word {
    var x = input_x;
    var y = input_y;
    var d = digit0(x) - digit0(y);
    var borrow: Word = if ((d & IBASE) != 0) 1 else 0;
    const r = make(INT, d & MAXDIGIT, 0);
    var z = restp(r);
    var p: ?*Word = null;
    x = rest(x);
    y = rest(y);
    while (x != 0 and y != 0) {
        d = digit(x) - digit(y) - borrow;
        borrow = if ((d & IBASE) != 0) 1 else 0;
        d &= MAXDIGIT;
        z.* = make(INT, d, 0);
        if (d != 0) p = null else if (p == null) p = z;
        x = rest(x);
        y = rest(y);
        z = restp(z.*);
    }
    while (y != 0) {
        d = -digit(y) - borrow;
        borrow = if ((d & IBASE) != 0) 1 else 0;
        d &= MAXDIGIT;
        z.* = make(INT, d, 0);
        if (d != 0) p = null else if (p == null) p = z;
        y = rest(y);
        z = restp(z.*);
    }
    while (x != 0) {
        d = digit(x) - borrow;
        borrow = if ((d & IBASE) != 0) 1 else 0;
        d &= MAXDIGIT;
        z.* = make(INT, d, 0);
        if (d != 0) p = null else if (p == null) p = z;
        x = rest(x);
        z = restp(z.*);
    }
    if (borrow != 0) {
        p = null;
        d = (digit(r) ^ MAXDIGIT) + 1;
        borrow = if ((d & IBASE) != 0) 1 else 0;
        digitp(r).* = SIGNBIT | d;
        z = restp(r);
        while (z.* != 0) {
            d = (digit(z.*) ^ MAXDIGIT) + borrow;
            borrow = if ((d & IBASE) != 0) 1 else 0;
            d &= MAXDIGIT;
            digitp(z.*).* = d;
            if (d != 0) p = null else if (p == null) p = z;
            z = restp(z.*);
        }
    }
    if (p) |ptr| ptr.* = 0;
    return r;
}

export fn bigcmp(input_x: Word, input_y: Word) c_int {
    var x = input_x;
    var y = input_y;
    const s = neg(x) != 0;
    if ((neg(y) != 0) != s) return if (s) -1 else 1;
    var r = digit0(x) - digit0(y);
    while (true) {
        x = rest(x);
        y = rest(y);
        if (x == 0) {
            if (y != 0) return if (s) 1 else -1;
            return @intCast(if (s) -r else r);
        }
        if (y == 0) return if (s) -1 else 1;
        const d = digit(x) - digit(y);
        if (d != 0) r = d;
    }
}

export fn bigtimes(input_x: Word, input_y: Word) Word {
    var x = input_x;
    var y = input_y;
    if (len(x) < len(y)) {
        const hold = x;
        x = y;
        y = hold;
    }
    var r = make(INT, 0, 0);
    var d = digit0(y);
    const s = neg(y) != 0;
    if (bigzero(x)) return r;
    var n: Word = 0;
    while (true) {
        if (d != 0) r = bigplus(r, shift(n, stimes(x, d)));
        n += 1;
        y = rest(y);
        if (y == 0) return if (s != (neg(x) != 0)) bignegate(r) else r;
        d = digit(y);
    }
}

fn shift(n_input: Word, x_input: Word) Word {
    var n = n_input;
    var x = x_input;
    while (n != 0) : (n -= 1) x = make(INT, 0, x);
    return x;
}

fn stimes(input_x: Word, n: Word) Word {
    var x = input_x;
    var d: u32 = @intCast(n * digit0(x));
    var carry: Word = @intCast(d >> DIGITWIDTH);
    const r = make(INT, @intCast(d & MAXDIGIT), 0);
    var y = restp(r);
    x = rest(x);
    while (x != 0) : (x = rest(x)) {
        d = @intCast((n * digit(x)) + carry);
        y.* = make(INT, @intCast(d & MAXDIGIT), 0);
        y = restp(y.*);
        carry = @intCast(d >> DIGITWIDTH);
    }
    if (carry != 0) y.* = make(INT, carry, 0);
    return r;
}

export fn bigdiv(input_x: Word, input_y: Word) Word {
    var x = input_x;
    var y = input_y;
    const s1 = neg(y) != 0;
    if (s1) y = make(INT, digit0(y), rest(y));
    const s2 = if (neg(x) != 0) blk: {
        x = make(INT, digit0(x), rest(x));
        break :blk !s1;
    } else s1;
    const q = if (rest(y) != 0) longdiv(x, y) else shortdiv(x, digit(y));
    if (s2) {
        if (!bigzero(b_rem)) {
            var qx = q;
            while (true) {
                digitp(qx).* += 1;
                if (digit(qx) != IBASE) break;
                digitp(qx).* = 0;
                if (rest(qx) == 0) {
                    restp(qx).* = make(INT, 1, 0);
                    break;
                }
                qx = rest(qx);
            }
        }
        if (!bigzero(q)) digitp(q).* = SIGNBIT | digit(q);
    }
    return q;
}

export fn bigmod(input_x: Word, input_y: Word) Word {
    var x = input_x;
    var y = input_y;
    const s1 = neg(y) != 0;
    if (s1) y = make(INT, digit0(y), rest(y));
    const s2 = if (neg(x) != 0) blk: {
        x = make(INT, digit0(x), rest(x));
        break :blk !s1;
    } else s1;
    _ = if (rest(y) != 0) longdiv(x, y) else shortdiv(x, digit(y));
    if (s2 and !bigzero(b_rem)) b_rem = bigsub(y, b_rem);
    return if (s1) bignegate(b_rem) else b_rem;
}

fn shortdiv(input_x: Word, n: Word) Word {
    var x = input_x;
    var d = digit(x);
    var q: Word = 0;
    while (rest(x) != 0) {
        x = rest(x);
        q = make(INT, d, q);
        d = digit(x);
    }
    var tmp: Word = undefined;
    x = q;
    var s_rem = @rem(d, n);
    d = @divTrunc(d, n);
    if (d != 0 or q == 0) q = make(INT, d, 0) else q = 0;
    while (x != 0) {
        d = (s_rem * IBASE) + digit(x);
        digitp(x).* = @divTrunc(d, n);
        s_rem = @rem(d, n);
        tmp = x;
        x = rest(x);
        restp(tmp).* = q;
        q = tmp;
    }
    b_rem = make(INT, s_rem, 0);
    return q;
}

fn longdiv(input_x: Word, input_y: Word) Word {
    var x = input_x;
    var y = input_y;
    if (bigcmp(x, y) < 0) {
        b_rem = x;
        return make(INT, 0, 0);
    }
    var y1 = msd(y);
    const scale = @divTrunc(IBASE, y1 + 1);
    if (scale > 1) {
        x = stimes(x, scale);
        y = stimes(y, scale);
        y1 = msd(y);
    }
    var n: Word = 0;
    var q: Word = 0;
    var ly = len(y);
    while (true) {
        y = make(INT, 0, y);
        if (bigcmp(x, y) < 0) break;
        n += 1;
    }
    y = rest(y);
    ly += n;
    while (true) {
        var d: Word = undefined;
        const lx = len(x);
        if (lx < ly) {
            d = 0;
        } else if (lx == ly) {
            if (bigcmp(x, y) >= 0) {
                x = bigsub(x, y);
                d = 1;
            } else {
                d = 0;
            }
        } else {
            d = @divTrunc(ms2d(x), y1);
            if (d > MAXDIGIT) d = MAXDIGIT;
            d -= 2;
            if (d > 0) {
                x = bigsub(x, stimes(y, d));
            } else {
                d = 0;
            }
            if (bigcmp(x, y) >= 0) {
                x = bigsub(x, y);
                d += 1;
                if (bigcmp(x, y) >= 0) {
                    x = bigsub(x, y);
                    d += 1;
                }
            }
        }
        q = make(INT, d, q);
        if (n == 0) {
            b_rem = if (scale == 1) x else shortdiv(x, scale);
            return q;
        }
        n -= 1;
        ly -= 1;
        y = rest(y);
    }
}

fn len(input_x: Word) Word {
    var x = input_x;
    var n: Word = 1;
    while (rest(x) != 0) {
        x = rest(x);
        n += 1;
    }
    return n;
}

fn msd(input_x: Word) Word {
    var x = input_x;
    while (rest(x) != 0) x = rest(x);
    return digit(x);
}

fn ms2d(input_x: Word) Word {
    var x = input_x;
    var d = digit(x);
    x = rest(x);
    while (rest(x) != 0) {
        d = digit(x);
        x = rest(x);
    }
    return (digit(x) * IBASE) + d;
}

export fn bigpow(input_x: Word, input_y: Word) Word {
    var x = input_x;
    var y = input_y;
    var r = make(INT, 1, 0);
    while (rest(y) != 0) {
        var i: Word = DIGITWIDTH;
        var d = digit(y);
        while (i != 0) : (i -= 1) {
            if ((d & 1) != 0) r = bigtimes(r, x);
            x = bigtimes(x, x);
            d >>= 1;
        }
        y = rest(y);
    }
    var d = digit(y);
    if ((d & 1) != 0) r = bigtimes(r, x);
    d >>= 1;
    while (d != 0) : (d >>= 1) {
        x = bigtimes(x, x);
        if ((d & 1) != 0) r = bigtimes(r, x);
    }
    return r;
}

export fn bigtodbl(input_x: Word) f64 {
    var x = input_x;
    const s = neg(x) != 0;
    var b: f64 = 1.0;
    var r: f64 = @floatFromInt(digit0(x));
    x = rest(x);
    while (x != 0) {
        b *= @floatFromInt(IBASE);
        r += b * @as(f64, @floatFromInt(digit(x)));
        x = rest(x);
    }
    return if (s) -r else r;
}

export fn dbltobig(input: f64) Word {
    const s = input < 0;
    const r = make(INT, 0, 0);
    var ptr = r;
    var y = @abs(std.math.floor(input));
    while (true) {
        const n = @rem(y, @as(f64, @floatFromInt(IBASE)));
        digitp(ptr).* = @intFromFloat(n);
        y = (y - n) / @as(f64, @floatFromInt(IBASE));
        if (y > 0.0) {
            restp(ptr).* = make(INT, 0, 0);
            ptr = rest(ptr);
        } else break;
    }
    if (s) digitp(r).* = SIGNBIT | digit(r);
    return r;
}

export fn biglog(input_x: Word) f64 {
    var x = input_x;
    var n: Word = 0;
    var r: f64 = @floatFromInt(digit(x));
    if (neg(x) != 0 or bigzero(x)) {
        setErrnoDom();
        math_error("log");
    }
    while (rest(x) != 0) {
        x = rest(x);
        n += 1;
        r = @as(f64, @floatFromInt(digit(x))) + (r / @as(f64, @floatFromInt(IBASE)));
    }
    return std.math.log(f64, std.math.e, r) + (@as(f64, @floatFromInt(n)) * logIBASE);
}

export fn biglog10(input_x: Word) f64 {
    var x = input_x;
    var n: Word = 0;
    var r: f64 = @floatFromInt(digit(x));
    if (neg(x) != 0 or bigzero(x)) {
        setErrnoDom();
        math_error("log10");
    }
    while (rest(x) != 0) {
        x = rest(x);
        n += 1;
        r = @as(f64, @floatFromInt(digit(x))) + (r / @as(f64, @floatFromInt(IBASE)));
    }
    return std.math.log10(r) + (@as(f64, @floatFromInt(n)) * log10IBASE);
}

fn setErrnoDom() void {
    platform.setErrno(@intCast(@intFromEnum(std.posix.E.DOM)));
}

export fn bigscan(p: [*:0]const u8) Word {
    var cursor: usize = 0;
    var s = false;
    const r = make(INT, 0, 0);
    if (p[0] == '-') {
        s = true;
        cursor += 1;
    }
    while (p[cursor] != 0) {
        var d: Word = p[cursor] - '0';
        var f: Word = 10;
        cursor += 1;
        while (p[cursor] != 0 and f < PTEN) {
            d = (10 * d) + p[cursor] - '0';
            f *= 10;
            cursor += 1;
        }
        multiplyAddInPlace(r, f, d);
    }
    if (s and !bigzero(r)) digitp(r).* |= SIGNBIT;
    return r;
}

export fn bigxscan(p: [*]const u8, q: [*]const u8) Word {
    const start_addr = @intFromPtr(p);
    var end_addr = @intFromPtr(q);
    if (end_addr == start_addr + 1 and p[0] == '0') return make(INT, 0, 0);
    var r: Word = undefined;
    var x = &r;
    while (end_addr > start_addr) {
        const remaining = end_addr - start_addr;
        const seg_len = @min(remaining, 15);
        const seg_addr = end_addr - seg_len;
        const seg: [*]const u8 = @ptrFromInt(seg_addr);
        var hold: u64 = 0;
        for (0..seg_len) |i| hold = (hold << 4) + @as(u64, @intCast(hexVal(seg[i])));
        var count: Word = 4;
        while (count != 0 and !(hold == 0 and seg_addr == start_addr)) : (count -= 1) {
            x.* = make(INT, @intCast(hold & MAXDIGIT), 0);
            hold >>= DIGITWIDTH;
            x = restp(x.*);
        }
        end_addr = seg_addr;
    }
    return r;
}

export fn bigoscan(p: [*]const u8, q: [*]const u8) Word {
    const start_addr = @intFromPtr(p);
    var end_addr = @intFromPtr(q);
    var r: Word = undefined;
    var x = &r;
    while (end_addr > start_addr) {
        const remaining = end_addr - start_addr;
        const seg_len = @min(remaining, 5);
        const seg_addr = end_addr - seg_len;
        const seg: [*]const u8 = @ptrFromInt(seg_addr);
        var hold: u32 = 0;
        for (0..seg_len) |i| hold = (hold << 3) + @as(u32, @intCast(seg[i] - '0'));
        x.* = make(INT, @intCast(hold), 0);
        x = restp(x.*);
        end_addr = seg_addr;
    }
    return r;
}

fn digitval(ch: Word) Word {
    const cch: u8 = @intCast(ch);
    if (std.ascii.isDigit(cch)) return cch - '0';
    if (std.ascii.isUpper(cch)) return 10 + cch - 'A';
    return 10 + cch - 'a';
}

fn hexVal(ch: u8) Word {
    if (std.ascii.isDigit(ch)) return ch - '0';
    if (std.ascii.isUpper(ch)) return 10 + ch - 'A';
    return 10 + ch - 'a';
}

export fn strtobig(input_z: Word, base: c_int) Word {
    var z = input_z;
    var s = false;
    const r = make(INT, 0, 0);
    var pbase: Word = PTEN;
    if (base == 16) pbase = PSIXTEEN else if (base == 8) pbase = PEIGHT;
    if (z != NIL and h(z) == '-') {
        s = true;
        z = t(z);
    }
    if (base != 10) z = t(t(z));
    while (z != NIL) {
        var d = digitval(h(z));
        var f: Word = base;
        z = t(z);
        while (z != NIL and f < pbase) {
            d = (@as(Word, base) * d) + digitval(h(z));
            f *= base;
            z = t(z);
        }
        multiplyAddInPlace(r, f, d);
    }
    if (s and !bigzero(r)) digitp(r).* |= SIGNBIT;
    return r;
}

fn multiplyAddInPlace(r: Word, f: Word, add: Word) void {
    var d = (f * digit(r)) + add;
    var carry = d >> DIGITWIDTH;
    var x = restp(r);
    digitp(r).* = d & MAXDIGIT;
    while (x.* != 0) {
        d = (f * digit(x.*)) + carry;
        digitp(x.*).* = d & MAXDIGIT;
        carry = d >> DIGITWIDTH;
        x = restp(x.*);
    }
    if (carry != 0) x.* = make(INT, carry, 0);
}

export fn bigtostr(input_x: Word) Word {
    var x = input_x;
    if (rest(x) == 0) return wordToDecimalList(getsmallint(x));
    const sign = neg(x) != 0;
    var x1 = make(INT, digit0(x), 0);
    x = rest(x);
    while (x != 0) {
        x1 = make(INT, digit(x), x1);
        x = rest(x);
    }
    x = x1;
    var s: Word = NIL;
    while (true) {
        var d = digit(x);
        var rem = @rem(d, PTEN);
        d = @divTrunc(d, PTEN);
        x1 = rest(x);
        if (d != 0) digitp(x).* = d else x = x1;
        while (x1 != 0) {
            d = (rem * IBASE) + digit(x1);
            digitp(x1).* = @divTrunc(d, PTEN);
            rem = @rem(d, PTEN);
            x1 = rest(x1);
        }
        if (x != 0) {
            var i: Word = TENW;
            while (i != 0) : (i -= 1) {
                s = cons('0' + @rem(rem, 10), s);
                rem = @divTrunc(rem, 10);
            }
        } else {
            while (rem != 0) {
                s = cons('0' + @rem(rem, 10), s);
                rem = @divTrunc(rem, 10);
            }
            return if (sign) cons('-', s) else s;
        }
    }
}

fn wordToDecimalList(value: Word) Word {
    var buffer: [64]u8 = undefined;
    // 64 bytes holds any decimal Word (<= 20 digits); bufPrint cannot overflow.
    const text = std.fmt.bufPrint(&buffer, "{d}", .{value}) catch unreachable;
    var result: Word = NIL;
    var i = text.len;
    while (i != 0) {
        i -= 1;
        result = cons(text[i], result);
    }
    return result;
}

export fn bigtostrx(input_x: Word) Word {
    var x = input_x;
    var r: Word = NIL;
    const s = neg(x) != 0;
    while (x != 0) {
        var count: Word = 4;
        var factor: u64 = 1;
        var hold: u64 = 0;
        while (count != 0 and x != 0) : (count -= 1) {
            hold += factor * @as(u64, @intCast(digit0(x)));
            factor <<= 15;
            x = rest(x);
        }
        var buffer: [16]u8 = undefined;
        // exactly 15 hex digits formatted into a 16-byte buffer; cannot overflow.
        const text = std.fmt.bufPrint(&buffer, "{x:0>15}", .{hold}) catch unreachable;
        var i = text.len;
        while (i != 0) {
            i -= 1;
            r = cons(text[i], r);
        }
    }
    while (digit(r) == '0' and rest(r) != NIL) r = rest(r);
    r = cons('0', cons('x', r));
    if (s) r = cons('-', r);
    return r;
}

export fn bigtostr8(input_x: Word) Word {
    var x = input_x;
    var r: Word = NIL;
    const s = neg(x) != 0;
    while (x != 0) {
        var buffer: [6]u8 = undefined;
        // exactly 5 octal digits formatted into a 6-byte buffer; cannot overflow.
        const text = std.fmt.bufPrint(&buffer, "{o:0>5}", .{@as(u64, @intCast(digit0(x)))}) catch unreachable;
        var i = text.len;
        while (i != 0) {
            i -= 1;
            r = cons(text[i], r);
        }
        x = rest(x);
    }
    while (digit(r) == '0' and rest(r) != NIL) r = rest(r);
    r = cons('0', cons('o', r));
    if (s) r = cons('-', r);
    return r;
}
