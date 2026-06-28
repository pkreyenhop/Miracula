//! big.zig — arbitrary-precision integers (bignums).
//!
//! A bignum is a linked chain of `INT` heap cells: each cell's `hd` holds one
//! base-2^15 **digit** and its `tl` points at the next, more-significant cell.
//! The chain is **little-endian** — the head cell is the least-significant digit
//! — and the **sign** lives in `SIGNBIT` of the head cell's digit. A one-cell
//! chain whose digit fits in 15 bits is an ordinary small int. Digit cells are
//! reused/mutated in place by the arithmetic routines (they own freshly-`make`d
//! chains), which is why so much works through the `*Word` cell pointers
//! (`digitPtr`/`restPtr`).
//!
//! Public API (all over `big.`): construct (`fromInt`/`fromFloat`/`scanDecimal`/
//! `scanHex`/`scanOctal`/`parseString`), convert out (`toInt`/`toFloat`/
//! `toDecimalList`/`toHexList`/`toOctalList`), arithmetic (`add`/`sub`/`mul`/
//! `div`/`mod`/`pow`/`negate`/`cmp`), maths (`ln`/`log10`), predicates
//! (`isNat`), and one-time `setup`.

const std = @import("std");

const platform = @import("../io/platform.zig");
const heap = @import("heap.zig");
const r7_reduce = @import("reduce.zig");

const Word = i64;

const SIGNBIT: Word = 0x10000000; // set on the head digit ⇒ the bignum is negative
const IBASE: Word = 0x8000; // the digit base, 2^15 (a digit is in [0, IBASE))
const MAXDIGIT: Word = 0x7fff; // IBASE-1: mask selecting a digit's 15 value bits
const DIGITWIDTH: Word = 15; // bits per digit (log2 IBASE)
const PTEN: Word = 10000; // 10^4 — chunk size for decimal scan/print
const PSIXTEEN: Word = 4096; // 16^3 — chunk size for hex scan
const PEIGHT: Word = 0x8000; // 8^5 — chunk size for octal scan
const TENW: Word = 4; // decimal digits per PTEN chunk
const CONS: u8 = 11; // NodeTag.CONS (char-list cells for the *toList helpers)
const INT: u8 = 5; // NodeTag.INT (a bignum digit cell)
const CMBASE: Word = 306;
const NIL: Word = CMBASE + 138;

const make = heap.make;
const mathError = r7_reduce.mathError;
/// Bignum subsystem state (shared-state plan Phase 2e). Accessed as `big.bn.X`;
/// folds into `Interp.big` in Phase 3. `bn.logIBASE`/`bn.log10IBASE` are caches set by
/// `setup` (runtime `@log`, not comptime); `bn.big_one`/`bn.b_rem` are heap nodes.
pub const Bignum = struct {
    logIBASE: f64 = 0,
    log10IBASE: f64 = 0,
    /// Remainder from the last division (a GC root).
    b_rem: Word = 0,
    /// Cached `INT` cell holding 1 (a GC root).
    big_one: Word = 0,
};

pub const bn = &@import("interp.zig").interp.big;

/// The node tag of cell `x`.
inline fn getTag(x: Word) u8 {
    return heap.heap.getTag(x);
}

// Raw heap cell accessors (head / tail, by value and by pointer). A bignum
// digit cell stores its digit in the head and the next cell in the tail.
/// Head (`hd`) of cell `x`.
fn h(x: Word) Word {
    return heap.heap.h(x);
}
/// Pointer to the head field of cell `x`.
fn hp(x: Word) *Word {
    return heap.heap.hp(x);
}
/// Tail (`tl`) of cell `x`.
fn t(x: Word) Word {
    return heap.heap.t(x);
}
/// Pointer to the tail field of cell `x`.
fn tp(x: Word) *Word {
    return heap.heap.tp(x);
}

/// The head cell's digit with the sign/overflow bits masked off (its plain
/// 0..MAXDIGIT value).
fn digit0(x: Word) Word {
    return h(x) & MAXDIGIT;
}
/// The head cell's digit field, raw (may carry `SIGNBIT` on the head cell).
fn digit(x: Word) Word {
    return h(x);
}
/// Pointer to the head cell's digit field (for in-place mutation).
fn digitPtr(x: Word) *Word {
    return hp(x);
}
/// The rest of the chain — the next (more-significant) digit cell.
fn rest(x: Word) Word {
    return t(x);
}
/// Pointer to the chain link, for in-place mutation / appending digits.
fn restPtr(x: Word) *Word {
    return tp(x);
}

/// Whether `x` is non-negative (no `SIGNBIT` on the head digit).
fn isPositive(x: Word) bool {
    return (h(x) & SIGNBIT) == 0;
}
/// The sign bit of `x` (`SIGNBIT` if negative, else 0).
fn signBit(x: Word) Word {
    return h(x) & SIGNBIT;
}
/// Whether `x` is the single-cell zero.
fn isZero(x: Word) bool {
    return digit(x) == 0 and rest(x) == 0;
}
/// Decode a single-cell bignum to a signed `Word` (caller guarantees one cell).
fn toSmallInt(x: Word) Word {
    return if ((h(x) & SIGNBIT) != 0) -digit0(x) else digit(x);
}

/// Build a `CONS` cell — used by the `to*List` routines to emit char lists.
fn cons(x: Word, y: Word) Word {
    return make(CONS, x, y);
}

/// Initialise the bignum caches (`logIBASE`/`log10IBASE`) and `big_one`. Once, at startup.
pub fn setup() void {
    bn.logIBASE = std.math.log(f64, std.math.e, @as(f64, @floatFromInt(IBASE)));
    bn.log10IBASE = std.math.log10(@as(f64, @floatFromInt(IBASE)));
    bn.big_one = make(INT, 1, 0);
}

/// 1 if `x` is a non-negative integer (`INT`-tagged and positive), else 0.
pub fn isNat(x: Word) c_int {
    return if (getTag(x) == INT and isPositive(x)) 1 else 0;
}

/// Build a bignum from a signed 64-bit integer.
pub fn fromInt(input: c_longlong) Word {
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
        var p = restPtr(x);
        p.* = make(INT, @intCast(unsigned_i & MAXDIGIT), 0);
        p = restPtr(p.*);
        unsigned_i >>= DIGITWIDTH;
        while (unsigned_i != 0) : (unsigned_i >>= DIGITWIDTH) {
            p.* = make(INT, @intCast(unsigned_i & MAXDIGIT), 0);
            p = restPtr(p.*);
        }
    }
    return x;
}

/// Convert a bignum to a signed 64-bit integer (saturates above ~2^60).
pub fn toInt(input: Word) c_longlong {
    var x = input;
    var n: c_longlong = @intCast(digit0(x));
    const sign = signBit(x) != 0;
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

/// Return `-x`.
pub fn negate(x: Word) Word {
    if (isZero(x)) return x;
    const d = if ((h(x) & SIGNBIT) != 0) h(x) & MAXDIGIT else SIGNBIT | h(x);
    return make(INT, d, rest(x));
}

/// Return `x + y`.
pub fn add(x: Word, y: Word) Word {
    if (isPositive(x)) {
        if (isPositive(y)) return addMagnitude(x, y, 0);
        return subMagnitude(x, y);
    }
    if (isPositive(y)) return subMagnitude(y, x);
    return addMagnitude(x, y, SIGNBIT);
}

/// Add the unsigned magnitudes of `x` and `y`, tagging the result with `signbit`.
fn addMagnitude(input_x: Word, input_y: Word, signbit: Word) Word {
    var x = input_x;
    var y = input_y;
    var d = digit0(x) + digit0(y);
    var carry: Word = if ((d & IBASE) != 0) 1 else 0;
    const r = make(INT, signbit | (d & MAXDIGIT), 0);
    var z = restPtr(r);
    x = rest(x);
    y = rest(y);
    while (x != 0 and y != 0) {
        d = carry + digit(x) + digit(y);
        carry = if ((d & IBASE) != 0) 1 else 0;
        z.* = make(INT, d & MAXDIGIT, 0);
        x = rest(x);
        y = rest(y);
        z = restPtr(z.*);
    }
    if (y != 0) x = y;
    while (x != 0) {
        d = carry + digit(x);
        carry = if ((d & IBASE) != 0) 1 else 0;
        z.* = make(INT, d & MAXDIGIT, 0);
        x = rest(x);
        z = restPtr(z.*);
    }
    if (carry != 0) z.* = make(INT, 1, 0);
    return r;
}

/// Return `x - y`.
pub fn sub(x: Word, y: Word) Word {
    if (isPositive(x)) {
        if (isPositive(y)) return subMagnitude(x, y);
        return addMagnitude(x, y, 0);
    }
    if (isPositive(y)) return addMagnitude(x, y, SIGNBIT);
    return subMagnitude(y, x);
}

/// Subtract unsigned magnitudes (|x| - |y|, |x| >= |y|), normalising the result.
fn subMagnitude(input_x: Word, input_y: Word) Word {
    var x = input_x;
    var y = input_y;
    var d = digit0(x) - digit0(y);
    var borrow: Word = if ((d & IBASE) != 0) 1 else 0;
    const r = make(INT, d & MAXDIGIT, 0);
    var z = restPtr(r);
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
        z = restPtr(z.*);
    }
    while (y != 0) {
        d = -digit(y) - borrow;
        borrow = if ((d & IBASE) != 0) 1 else 0;
        d &= MAXDIGIT;
        z.* = make(INT, d, 0);
        if (d != 0) p = null else if (p == null) p = z;
        y = rest(y);
        z = restPtr(z.*);
    }
    while (x != 0) {
        d = digit(x) - borrow;
        borrow = if ((d & IBASE) != 0) 1 else 0;
        d &= MAXDIGIT;
        z.* = make(INT, d, 0);
        if (d != 0) p = null else if (p == null) p = z;
        x = rest(x);
        z = restPtr(z.*);
    }
    if (borrow != 0) {
        p = null;
        d = (digit(r) ^ MAXDIGIT) + 1;
        borrow = if ((d & IBASE) != 0) 1 else 0;
        digitPtr(r).* = SIGNBIT | d;
        z = restPtr(r);
        while (z.* != 0) {
            d = (digit(z.*) ^ MAXDIGIT) + borrow;
            borrow = if ((d & IBASE) != 0) 1 else 0;
            d &= MAXDIGIT;
            digitPtr(z.*).* = d;
            if (d != 0) p = null else if (p == null) p = z;
            z = restPtr(z.*);
        }
    }
    if (p) |ptr| ptr.* = 0;
    return r;
}

/// Three-way compare: -1 / 0 / 1 for `x < y` / `x == y` / `x > y`.
pub fn cmp(input_x: Word, input_y: Word) c_int {
    var x = input_x;
    var y = input_y;
    const s = signBit(x) != 0;
    if ((signBit(y) != 0) != s) return if (s) -1 else 1;
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

/// Return `x * y`.
pub fn mul(input_x: Word, input_y: Word) Word {
    var x = input_x;
    var y = input_y;
    if (digitCount(x) < digitCount(y)) {
        const hold = x;
        x = y;
        y = hold;
    }
    var r = make(INT, 0, 0);
    var d = digit0(y);
    const s = signBit(y) != 0;
    if (isZero(x)) return r;
    var n: Word = 0;
    while (true) {
        if (d != 0) r = add(r, shiftLeftDigits(n, scaleBy(x, d)));
        n += 1;
        y = rest(y);
        if (y == 0) return if (s != (signBit(x) != 0)) negate(r) else r;
        d = digit(y);
    }
}

/// Prepend `n` zero digits — i.e. multiply `x` by `IBASE^n`.
fn shiftLeftDigits(n_input: Word, x_input: Word) Word {
    var n = n_input;
    var x = x_input;
    while (n != 0) : (n -= 1) x = make(INT, 0, x);
    return x;
}

/// Multiply the magnitude of `x` by the small (single-digit) integer `n`.
fn scaleBy(input_x: Word, n: Word) Word {
    var x = input_x;
    var d: u32 = @intCast(n * digit0(x));
    var carry: Word = @intCast(d >> DIGITWIDTH);
    const r = make(INT, @intCast(d & MAXDIGIT), 0);
    var y = restPtr(r);
    x = rest(x);
    while (x != 0) : (x = rest(x)) {
        d = @intCast((n * digit(x)) + carry);
        y.* = make(INT, @intCast(d & MAXDIGIT), 0);
        y = restPtr(y.*);
        carry = @intCast(d >> DIGITWIDTH);
    }
    if (carry != 0) y.* = make(INT, carry, 0);
    return r;
}

/// Return `x / y` truncated toward zero; leaves the remainder in `bn.b_rem`.
pub fn div(input_x: Word, input_y: Word) Word {
    var x = input_x;
    var y = input_y;
    const s1 = signBit(y) != 0;
    if (s1) y = make(INT, digit0(y), rest(y));
    const s2 = if (signBit(x) != 0) blk: {
        x = make(INT, digit0(x), rest(x));
        break :blk !s1;
    } else s1;
    const q = if (rest(y) != 0) longDiv(x, y) else shortDiv(x, digit(y));
    if (s2) {
        if (!isZero(bn.b_rem)) {
            var qx = q;
            while (true) {
                digitPtr(qx).* += 1;
                if (digit(qx) != IBASE) break;
                digitPtr(qx).* = 0;
                if (rest(qx) == 0) {
                    restPtr(qx).* = make(INT, 1, 0);
                    break;
                }
                qx = rest(qx);
            }
        }
        if (!isZero(q)) digitPtr(q).* = SIGNBIT | digit(q);
    }
    return q;
}

/// Return `x mod y` (the result's sign follows the divisor `y`).
pub fn mod(input_x: Word, input_y: Word) Word {
    var x = input_x;
    var y = input_y;
    const s1 = signBit(y) != 0;
    if (s1) y = make(INT, digit0(y), rest(y));
    const s2 = if (signBit(x) != 0) blk: {
        x = make(INT, digit0(x), rest(x));
        break :blk !s1;
    } else s1;
    _ = if (rest(y) != 0) longDiv(x, y) else shortDiv(x, digit(y));
    if (s2 and !isZero(bn.b_rem)) bn.b_rem = sub(y, bn.b_rem);
    return if (s1) negate(bn.b_rem) else bn.b_rem;
}

/// Divide a bignum by a single digit `n`; remainder left in `bn.b_rem`.
fn shortDiv(input_x: Word, n: Word) Word {
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
        digitPtr(x).* = @divTrunc(d, n);
        s_rem = @rem(d, n);
        tmp = x;
        x = rest(x);
        restPtr(tmp).* = q;
        q = tmp;
    }
    bn.b_rem = make(INT, s_rem, 0);
    return q;
}

/// Long division of `x` by a multi-digit `y`; remainder left in `bn.b_rem`.
fn longDiv(input_x: Word, input_y: Word) Word {
    var x = input_x;
    var y = input_y;
    if (cmp(x, y) < 0) {
        bn.b_rem = x;
        return make(INT, 0, 0);
    }
    var y1 = mostSignificantDigit(y);
    const scale = @divTrunc(IBASE, y1 + 1);
    if (scale > 1) {
        x = scaleBy(x, scale);
        y = scaleBy(y, scale);
        y1 = mostSignificantDigit(y);
    }
    var n: Word = 0;
    var q: Word = 0;
    var ly = digitCount(y);
    while (true) {
        y = make(INT, 0, y);
        if (cmp(x, y) < 0) break;
        n += 1;
    }
    y = rest(y);
    ly += n;
    while (true) {
        var d: Word = undefined;
        const lx = digitCount(x);
        if (lx < ly) {
            d = 0;
        } else if (lx == ly) {
            if (cmp(x, y) >= 0) {
                x = sub(x, y);
                d = 1;
            } else {
                d = 0;
            }
        } else {
            d = @divTrunc(topTwoDigits(x), y1);
            if (d > MAXDIGIT) d = MAXDIGIT;
            d -= 2;
            if (d > 0) {
                x = sub(x, scaleBy(y, d));
            } else {
                d = 0;
            }
            if (cmp(x, y) >= 0) {
                x = sub(x, y);
                d += 1;
                if (cmp(x, y) >= 0) {
                    x = sub(x, y);
                    d += 1;
                }
            }
        }
        q = make(INT, d, q);
        if (n == 0) {
            bn.b_rem = if (scale == 1) x else shortDiv(x, scale);
            return q;
        }
        n -= 1;
        ly -= 1;
        y = rest(y);
    }
}

/// Number of digit cells in the chain.
fn digitCount(input_x: Word) Word {
    var x = input_x;
    var n: Word = 1;
    while (rest(x) != 0) {
        x = rest(x);
        n += 1;
    }
    return n;
}

/// The leading (most-significant) digit.
fn mostSignificantDigit(input_x: Word) Word {
    var x = input_x;
    while (rest(x) != 0) x = rest(x);
    return digit(x);
}

/// The top two digits combined as `msd * IBASE + next`.
fn topTwoDigits(input_x: Word) Word {
    var x = input_x;
    var d = digit(x);
    x = rest(x);
    while (rest(x) != 0) {
        d = digit(x);
        x = rest(x);
    }
    return (digit(x) * IBASE) + d;
}

/// Return `x ** y` via repeated squaring (`y >= 0`).
pub fn pow(input_x: Word, input_y: Word) Word {
    var x = input_x;
    var y = input_y;
    var r = make(INT, 1, 0);
    while (rest(y) != 0) {
        var i: Word = DIGITWIDTH;
        var d = digit(y);
        while (i != 0) : (i -= 1) {
            if ((d & 1) != 0) r = mul(r, x);
            x = mul(x, x);
            d >>= 1;
        }
        y = rest(y);
    }
    var d = digit(y);
    if ((d & 1) != 0) r = mul(r, x);
    d >>= 1;
    while (d != 0) : (d >>= 1) {
        x = mul(x, x);
        if ((d & 1) != 0) r = mul(r, x);
    }
    return r;
}

/// Convert a bignum to an `f64`.
pub fn toFloat(input_x: Word) f64 {
    var x = input_x;
    const s = signBit(x) != 0;
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

/// Build a bignum from the integer part of an `f64`.
pub fn fromFloat(input: f64) Word {
    const s = input < 0;
    const r = make(INT, 0, 0);
    var ptr = r;
    var y = @abs(std.math.floor(input));
    while (true) {
        const n = @rem(y, @as(f64, @floatFromInt(IBASE)));
        digitPtr(ptr).* = @intFromFloat(n);
        y = (y - n) / @as(f64, @floatFromInt(IBASE));
        if (y > 0.0) {
            restPtr(ptr).* = make(INT, 0, 0);
            ptr = rest(ptr);
        } else break;
    }
    if (s) digitPtr(r).* = SIGNBIT | digit(r);
    return r;
}

/// Natural logarithm of a positive bignum (domain-errors on `<= 0`).
pub fn ln(input_x: Word) f64 {
    var x = input_x;
    var n: Word = 0;
    var r: f64 = @floatFromInt(digit(x));
    if (signBit(x) != 0 or isZero(x)) {
        setErrnoDomain();
        mathError("log");
    }
    while (rest(x) != 0) {
        x = rest(x);
        n += 1;
        r = @as(f64, @floatFromInt(digit(x))) + (r / @as(f64, @floatFromInt(IBASE)));
    }
    return std.math.log(f64, std.math.e, r) + (@as(f64, @floatFromInt(n)) * bn.logIBASE);
}

/// Base-10 logarithm of a positive bignum (domain-errors on `<= 0`).
pub fn log10(input_x: Word) f64 {
    var x = input_x;
    var n: Word = 0;
    var r: f64 = @floatFromInt(digit(x));
    if (signBit(x) != 0 or isZero(x)) {
        setErrnoDomain();
        mathError("log10");
    }
    while (rest(x) != 0) {
        x = rest(x);
        n += 1;
        r = @as(f64, @floatFromInt(digit(x))) + (r / @as(f64, @floatFromInt(IBASE)));
    }
    return std.math.log10(r) + (@as(f64, @floatFromInt(n)) * bn.log10IBASE);
}

/// Set errno to `EDOM` (a maths domain error).
fn setErrnoDomain() void {
    platform.setErrno(@intCast(@intFromEnum(std.posix.E.DOM)));
}

/// Parse a NUL-terminated decimal string into a bignum.
pub fn scanDecimal(p: [*:0]const u8) Word {
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
    if (s and !isZero(r)) digitPtr(r).* |= SIGNBIT;
    return r;
}

/// Parse the hex digits in the byte range `[p, q)` into a bignum.
pub fn scanHex(p: [*]const u8, q: [*]const u8) Word {
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
        for (0..seg_len) |i| hold = (hold << 4) + @as(u64, @intCast(hexValue(seg[i])));
        var count: Word = 4;
        while (count != 0 and !(hold == 0 and seg_addr == start_addr)) : (count -= 1) {
            x.* = make(INT, @intCast(hold & MAXDIGIT), 0);
            hold >>= DIGITWIDTH;
            x = restPtr(x.*);
        }
        end_addr = seg_addr;
    }
    return r;
}

/// Parse the octal digits in the byte range `[p, q)` into a bignum.
pub fn scanOctal(p: [*]const u8, q: [*]const u8) Word {
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
        x = restPtr(x.*);
        end_addr = seg_addr;
    }
    return r;
}

/// Numeric value of a decimal/hex digit character (`0`-`9`, `A`-`F`/`a`-`f`).
fn digitValue(ch: Word) Word {
    const cch: u8 = @intCast(ch);
    if (std.ascii.isDigit(cch)) return cch - '0';
    if (std.ascii.isUpper(cch)) return 10 + cch - 'A';
    return 10 + cch - 'a';
}

/// Numeric value of a hex digit byte.
fn hexValue(ch: u8) Word {
    if (std.ascii.isDigit(ch)) return ch - '0';
    if (std.ascii.isUpper(ch)) return 10 + ch - 'A';
    return 10 + ch - 'a';
}

/// Parse a Miranda char-list `z` of digits in `base` (10/16/8) into a bignum.
pub fn parseString(input_z: Word, base: c_int) Word {
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
        var d = digitValue(h(z));
        var f: Word = base;
        z = t(z);
        while (z != NIL and f < pbase) {
            d = (@as(Word, base) * d) + digitValue(h(z));
            f *= base;
            z = t(z);
        }
        multiplyAddInPlace(r, f, d);
    }
    if (s and !isZero(r)) digitPtr(r).* |= SIGNBIT;
    return r;
}

/// In place: `r = r*f + addend` — the Horner step shared by the scanners.
fn multiplyAddInPlace(r: Word, f: Word, addend: Word) void {
    var d = (f * digit(r)) + addend;
    var carry = d >> DIGITWIDTH;
    var x = restPtr(r);
    digitPtr(r).* = d & MAXDIGIT;
    while (x.* != 0) {
        d = (f * digit(x.*)) + carry;
        digitPtr(x.*).* = d & MAXDIGIT;
        carry = d >> DIGITWIDTH;
        x = restPtr(x.*);
    }
    if (carry != 0) x.* = make(INT, carry, 0);
}

/// Render a bignum as a Miranda char list of decimal digits.
pub fn toDecimalList(input_x: Word) Word {
    var x = input_x;
    if (rest(x) == 0) return wordToDecimalList(toSmallInt(x));
    const sign = signBit(x) != 0;
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
        if (d != 0) digitPtr(x).* = d else x = x1;
        while (x1 != 0) {
            d = (rem * IBASE) + digit(x1);
            digitPtr(x1).* = @divTrunc(d, PTEN);
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

/// Render a small `Word` as a decimal char list.
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

/// Render a bignum as a `0x`-prefixed hex char list (leading zeros trimmed).
pub fn toHexList(input_x: Word) Word {
    var x = input_x;
    var r: Word = NIL;
    const s = signBit(x) != 0;
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

/// Render a bignum as a `0o`-prefixed octal char list (leading zeros trimmed).
pub fn toOctalList(input_x: Word) Word {
    var x = input_x;
    var r: Word = NIL;
    const s = signBit(x) != 0;
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
