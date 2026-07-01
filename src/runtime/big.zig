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
//!
//! **Narrow substructure threading (Track SHARED_STATE, Phase 5 Tier 1,
//! 2026-07-01).** Every function here takes the `*Heap`/`*Bignum` it needs as
//! an explicit parameter instead of reaching the global `interp` singleton
//! ambiently — the file itself never reads `bn.X`/`heap.heap.X` internally.
//! Callers still source these pointers from the (still-global, Tier-3-deferred)
//! singletons via the `bn`/`heap.heap` convenience constants below; only this
//! module's own internals stopped assuming where they come from.

const std = @import("std");

const platform = @import("../io/platform.zig");
const heap_mod = @import("heap.zig");
const Heap = heap_mod.Heap;
const word = @import("word.zig");
const reduce = @import("reduce.zig");
const tu = @import("../testutil.zig"); // unit-test harness (test builds only)

const Word = i64;

const SIGNBIT: Word = 0x10000000; // set on the head digit ⇒ the bignum is negative
const IBASE: Word = 0x8000; // the digit base, 2^15 (a digit is in [0, IBASE))
const MAXDIGIT: Word = 0x7fff; // IBASE-1: mask selecting a digit's 15 value bits
const DIGITWIDTH: Word = 15; // bits per digit (log2 IBASE)
const PTEN: Word = 10000; // 10^4 — chunk size for decimal scan/print
const PSIXTEEN: Word = 4096; // 16^3 — chunk size for hex scan
const PEIGHT: Word = 0x8000; // 8^5 — chunk size for octal scan
const TENW: Word = 4; // decimal digits per PTEN chunk
const CMBASE = word.CMBASE;
const NIL = word.NIL;

const mathError = reduce.mathError;

/// Bignum subsystem state (shared-state plan Phase 2e). `logIBASE`/`log10IBASE`
/// are caches set by `setup` (runtime `@log`, not comptime); `big_one`/`b_rem`
/// are heap nodes. Threaded explicitly as a `*Bignum` parameter by every
/// function that needs it (Phase 5 Tier 1) rather than read ambiently.
pub const Bignum = struct {
    logIBASE: f64 = 0,
    log10IBASE: f64 = 0,
    /// Remainder from the last division (a GC root).
    b_rem: Word = 0,
    /// Cached `INT` cell holding 1 (a GC root).
    big_one: Word = 0,
};

/// Pointer to the bignum subsystem state held in `interp` (so `interp.reset()`
/// clears it). A convenience for *callers* to obtain a `*Bignum` to pass in —
/// this module's own functions no longer read `bn.X` themselves.
pub const bn = &@import("interp.zig").interp.big;

/// The head cell's digit with the sign/overflow bits masked off (its plain
/// 0..MAXDIGIT value).
fn digit0(heap: *Heap, x: Word) Word {
    return heap.h(x) & MAXDIGIT;
}
/// The head cell's digit field, raw (may carry `SIGNBIT` on the head cell).
fn digit(heap: *Heap, x: Word) Word {
    return heap.h(x);
}
/// Pointer to the head cell's digit field (for in-place mutation).
fn digitPtr(heap: *Heap, x: Word) *Word {
    return heap.hp(x);
}
/// The rest of the chain — the next (more-significant) digit cell.
fn rest(heap: *Heap, x: Word) Word {
    return heap.t(x);
}
/// Pointer to the chain link, for in-place mutation / appending digits.
fn restPtr(heap: *Heap, x: Word) *Word {
    return heap.tp(x);
}

/// Whether `x` is non-negative (no `SIGNBIT` on the head digit).
fn isPositive(heap: *Heap, x: Word) bool {
    return (heap.h(x) & SIGNBIT) == 0;
}
/// The sign bit of `x` (`SIGNBIT` if negative, else 0).
fn signBit(heap: *Heap, x: Word) Word {
    return heap.h(x) & SIGNBIT;
}
/// Whether `x` is the single-cell zero.
fn isZero(heap: *Heap, x: Word) bool {
    return digit(heap, x) == 0 and rest(heap, x) == 0;
}
/// Decode a single-cell bignum to a signed `Word` (caller guarantees one cell).
fn toSmallInt(heap: *Heap, x: Word) Word {
    return if ((heap.h(x) & SIGNBIT) != 0) -digit0(heap, x) else digit(heap, x);
}

/// Initialise the bignum caches (`logIBASE`/`log10IBASE`) and `big_one`. Once, at startup.
///
/// Tests: setup: initialises the bignum constants
pub fn setup(heap: *Heap, self: *Bignum) void {
    self.logIBASE = std.math.log(f64, std.math.e, @as(f64, @floatFromInt(IBASE)));
    self.log10IBASE = std.math.log10(@as(f64, @floatFromInt(IBASE)));
    self.big_one = heap.make(.INT, 1, 0);
}

test "setup: initialises the bignum constants" {
    tu.freshInterp();
    setup(&heap_mod.heap.*, bn);
    try std.testing.expectEqual(@as(c_longlong, 1), toInt(&heap_mod.heap.*, bn.big_one));
}

/// 1 if `x` is a non-negative integer (`INT`-tagged and positive), else 0.
///
/// Tests: isNat: 1 for non-negative INTs, 0 for negatives
pub fn isNat(heap: *Heap, x: Word) bool {
    return heap.getTag(x) == .INT and isPositive(heap, x);
}

test "isNat: 1 for non-negative INTs, 0 for negatives" {
    tu.freshInterp();
    const heap = &heap_mod.heap.*;
    try std.testing.expect(isNat(heap, fromInt(heap, 5)));
    try std.testing.expect(isNat(heap, fromInt(heap, 0)));
    try std.testing.expect(!isNat(heap, fromInt(heap, -5)));
}

/// Build a bignum from a signed 64-bit integer.
///
/// Tests: fromInt: round-trips through toInt across the digit boundary
pub fn fromInt(heap: *Heap, input: c_longlong) Word {
    var i = input;
    var s: Word = 0;
    if (i < 0) {
        s = SIGNBIT;
        i = -i;
    }
    var unsigned_i: c_ulonglong = @intCast(i);
    const x = heap.make(.INT, s | @as(Word, @intCast(unsigned_i & MAXDIGIT)), 0);
    unsigned_i >>= DIGITWIDTH;
    if (unsigned_i != 0) {
        var p = restPtr(heap, x);
        p.* = heap.make(.INT, @intCast(unsigned_i & MAXDIGIT), 0);
        p = restPtr(heap, p.*);
        unsigned_i >>= DIGITWIDTH;
        while (unsigned_i != 0) : (unsigned_i >>= DIGITWIDTH) {
            p.* = heap.make(.INT, @intCast(unsigned_i & MAXDIGIT), 0);
            p = restPtr(heap, p.*);
        }
    }
    return x;
}

test "fromInt: round-trips through toInt across the digit boundary" {
    tu.freshInterp();
    const heap = &heap_mod.heap.*;
    for ([_]c_longlong{ 0, 1, -1, 42, -42, 32768, 1 << 20, 1 << 40 }) |n| {
        try std.testing.expectEqual(n, toInt(heap, fromInt(heap, n)));
    }
}

/// Convert a bignum to a signed 64-bit integer (saturates above ~2^60).
///
/// Tests: toInt: saturates above 2^60
pub fn toInt(heap: *Heap, input: Word) c_longlong {
    var x = input;
    var n: c_longlong = @intCast(digit0(heap, x));
    const sign = signBit(heap, x) != 0;
    x = rest(heap, x);
    if (x == 0) return if (sign) -n else n;

    var w: Word = DIGITWIDTH;
    while (x != 0 and w < 60) : ({
        w += DIGITWIDTH;
        x = rest(heap, x);
    }) {
        n += @as(c_longlong, @intCast(digit(heap, x))) << @intCast(w);
    }
    if (x != 0) n = @as(c_longlong, 1) << 60;
    return if (sign) -n else n;
}

test "toInt: saturates above 2^60" {
    tu.freshInterp();
    const heap = &heap_mod.heap.*;
    // 2^61 exceeds the 60-bit window, so toInt clamps to 2^60.
    const big61 = mul(heap, fromInt(heap, 1 << 40), fromInt(heap, 1 << 21));
    try std.testing.expectEqual(@as(c_longlong, 1) << 60, toInt(heap, big61));
}

/// Return `-x`.
///
/// Tests: negate: flips the sign, fixed point at zero
pub fn negate(heap: *Heap, x: Word) Word {
    if (isZero(heap, x)) return x;
    const d = if ((heap.h(x) & SIGNBIT) != 0) heap.h(x) & MAXDIGIT else SIGNBIT | heap.h(x);
    return heap.make(.INT, d, rest(heap, x));
}

test "negate: flips the sign, fixed point at zero" {
    tu.freshInterp();
    const heap = &heap_mod.heap.*;
    try std.testing.expectEqual(@as(c_longlong, -7), toInt(heap, negate(heap, fromInt(heap, 7))));
    try std.testing.expectEqual(@as(c_longlong, 7), toInt(heap, negate(heap, fromInt(heap, -7))));
    try std.testing.expectEqual(@as(c_longlong, 0), toInt(heap, negate(heap, fromInt(heap, 0))));
}

/// Return `x + y`.
///
/// Tests: add: sums across signs and the digit boundary
pub fn add(heap: *Heap, x: Word, y: Word) Word {
    if (isPositive(heap, x)) {
        if (isPositive(heap, y)) return addMagnitude(heap, x, y, 0);
        return subMagnitude(heap, x, y);
    }
    if (isPositive(heap, y)) return subMagnitude(heap, y, x);
    return addMagnitude(heap, x, y, SIGNBIT);
}

test "add: sums across signs and the digit boundary" {
    tu.freshInterp();
    const heap = &heap_mod.heap.*;
    try std.testing.expectEqual(@as(c_longlong, 5), toInt(heap, add(heap, fromInt(heap, 2), fromInt(heap, 3))));
    try std.testing.expectEqual(@as(c_longlong, -1), toInt(heap, add(heap, fromInt(heap, 2), fromInt(heap, -3))));
    try std.testing.expectEqual(@as(c_longlong, 65536), toInt(heap, add(heap, fromInt(heap, 32768), fromInt(heap, 32768))));
}

/// Add the unsigned magnitudes of `x` and `y`, tagging the result with `signbit`.
fn addMagnitude(heap: *Heap, input_x: Word, input_y: Word, signbit: Word) Word {
    var x = input_x;
    var y = input_y;
    var d = digit0(heap, x) + digit0(heap, y);
    var carry: Word = if ((d & IBASE) != 0) 1 else 0;
    const r = heap.make(.INT, signbit | (d & MAXDIGIT), 0);
    var z = restPtr(heap, r);
    x = rest(heap, x);
    y = rest(heap, y);
    while (x != 0 and y != 0) {
        d = carry + digit(heap, x) + digit(heap, y);
        carry = if ((d & IBASE) != 0) 1 else 0;
        z.* = heap.make(.INT, d & MAXDIGIT, 0);
        x = rest(heap, x);
        y = rest(heap, y);
        z = restPtr(heap, z.*);
    }
    if (y != 0) x = y;
    while (x != 0) {
        d = carry + digit(heap, x);
        carry = if ((d & IBASE) != 0) 1 else 0;
        z.* = heap.make(.INT, d & MAXDIGIT, 0);
        x = rest(heap, x);
        z = restPtr(heap, z.*);
    }
    if (carry != 0) z.* = heap.make(.INT, 1, 0);
    return r;
}

/// Return `x - y`.
///
/// Tests: sub: differences across signs
pub fn sub(heap: *Heap, x: Word, y: Word) Word {
    if (isPositive(heap, x)) {
        if (isPositive(heap, y)) return subMagnitude(heap, x, y);
        return addMagnitude(heap, x, y, 0);
    }
    if (isPositive(heap, y)) return addMagnitude(heap, x, y, SIGNBIT);
    return subMagnitude(heap, y, x);
}

test "sub: differences across signs" {
    tu.freshInterp();
    const heap = &heap_mod.heap.*;
    try std.testing.expectEqual(@as(c_longlong, -1), toInt(heap, sub(heap, fromInt(heap, 2), fromInt(heap, 3))));
    try std.testing.expectEqual(@as(c_longlong, 5), toInt(heap, sub(heap, fromInt(heap, 2), fromInt(heap, -3))));
    try std.testing.expectEqual(@as(c_longlong, 0), toInt(heap, sub(heap, fromInt(heap, 40), fromInt(heap, 40))));
}

/// Subtract unsigned magnitudes (|x| - |y|, |x| >= |y|), normalising the result.
fn subMagnitude(heap: *Heap, input_x: Word, input_y: Word) Word {
    var x = input_x;
    var y = input_y;
    var d = digit0(heap, x) - digit0(heap, y);
    var borrow: Word = if ((d & IBASE) != 0) 1 else 0;
    const r = heap.make(.INT, d & MAXDIGIT, 0);
    var z = restPtr(heap, r);
    var p: ?*Word = null;
    x = rest(heap, x);
    y = rest(heap, y);
    while (x != 0 and y != 0) {
        d = digit(heap, x) - digit(heap, y) - borrow;
        borrow = if ((d & IBASE) != 0) 1 else 0;
        d &= MAXDIGIT;
        z.* = heap.make(.INT, d, 0);
        if (d != 0) p = null else if (p == null) p = z;
        x = rest(heap, x);
        y = rest(heap, y);
        z = restPtr(heap, z.*);
    }
    while (y != 0) {
        d = -digit(heap, y) - borrow;
        borrow = if ((d & IBASE) != 0) 1 else 0;
        d &= MAXDIGIT;
        z.* = heap.make(.INT, d, 0);
        if (d != 0) p = null else if (p == null) p = z;
        y = rest(heap, y);
        z = restPtr(heap, z.*);
    }
    while (x != 0) {
        d = digit(heap, x) - borrow;
        borrow = if ((d & IBASE) != 0) 1 else 0;
        d &= MAXDIGIT;
        z.* = heap.make(.INT, d, 0);
        if (d != 0) p = null else if (p == null) p = z;
        x = rest(heap, x);
        z = restPtr(heap, z.*);
    }
    if (borrow != 0) {
        p = null;
        d = (digit(heap, r) ^ MAXDIGIT) + 1;
        borrow = if ((d & IBASE) != 0) 1 else 0;
        digitPtr(heap, r).* = SIGNBIT | d;
        z = restPtr(heap, r);
        while (z.* != 0) {
            d = (digit(heap, z.*) ^ MAXDIGIT) + borrow;
            borrow = if ((d & IBASE) != 0) 1 else 0;
            d &= MAXDIGIT;
            digitPtr(heap, z.*).* = d;
            if (d != 0) p = null else if (p == null) p = z;
            z = restPtr(heap, z.*);
        }
    }
    if (p) |ptr| ptr.* = 0;
    return r;
}

/// Three-way compare: -1 / 0 / 1 for `x < y` / `x == y` / `x > y`.
///
/// Tests: cmp: three-way -1 / 0 / 1
pub fn cmp(heap: *Heap, input_x: Word, input_y: Word) c_int {
    var x = input_x;
    var y = input_y;
    const s = signBit(heap, x) != 0;
    if ((signBit(heap, y) != 0) != s) return if (s) -1 else 1;
    var r = digit0(heap, x) - digit0(heap, y);
    while (true) {
        x = rest(heap, x);
        y = rest(heap, y);
        if (x == 0) {
            if (y != 0) return if (s) 1 else -1;
            return @intCast(if (s) -r else r);
        }
        if (y == 0) return if (s) -1 else 1;
        const d = digit(heap, x) - digit(heap, y);
        if (d != 0) r = d;
    }
}

test "cmp: three-way -1 / 0 / 1" {
    tu.freshInterp();
    const heap = &heap_mod.heap.*;
    try std.testing.expectEqual(@as(c_int, -1), cmp(heap, fromInt(heap, 1), fromInt(heap, 2)));
    try std.testing.expectEqual(@as(c_int, 0), cmp(heap, fromInt(heap, 2), fromInt(heap, 2)));
    try std.testing.expectEqual(@as(c_int, 1), cmp(heap, fromInt(heap, 2), fromInt(heap, 1)));
    try std.testing.expectEqual(@as(c_int, -1), cmp(heap, fromInt(heap, -2), fromInt(heap, 1)));
}

/// Return `x * y`.
///
/// Tests: mul: products including large operands
pub fn mul(heap: *Heap, input_x: Word, input_y: Word) Word {
    var x = input_x;
    var y = input_y;
    if (digitCount(heap, x) < digitCount(heap, y)) {
        const hold = x;
        x = y;
        y = hold;
    }
    var r = heap.make(.INT, 0, 0);
    var d = digit0(heap, y);
    const s = signBit(heap, y) != 0;
    if (isZero(heap, x)) return r;
    var n: Word = 0;
    while (true) {
        if (d != 0) r = add(heap, r, shiftLeftDigits(heap, n, scaleBy(heap, x, d)));
        n += 1;
        y = rest(heap, y);
        if (y == 0) return if (s != (signBit(heap, x) != 0)) negate(heap, r) else r;
        d = digit(heap, y);
    }
}

test "mul: products including large operands" {
    tu.freshInterp();
    const heap = &heap_mod.heap.*;
    try std.testing.expectEqual(@as(c_longlong, 42), toInt(heap, mul(heap, fromInt(heap, 6), fromInt(heap, 7))));
    try std.testing.expectEqual(@as(c_longlong, -42), toInt(heap, mul(heap, fromInt(heap, -6), fromInt(heap, 7))));
    try std.testing.expectEqual(@as(c_longlong, 1 << 40), toInt(heap, mul(heap, fromInt(heap, 1 << 20), fromInt(heap, 1 << 20))));
}

/// Prepend `n` zero digits — i.e. multiply `x` by `IBASE^n`.
fn shiftLeftDigits(heap: *Heap, n_input: Word, x_input: Word) Word {
    var n = n_input;
    var x = x_input;
    while (n != 0) : (n -= 1) x = heap.make(.INT, 0, x);
    return x;
}

/// Multiply the magnitude of `x` by the small (single-digit) integer `n`.
fn scaleBy(heap: *Heap, input_x: Word, n: Word) Word {
    var x = input_x;
    var d: u32 = @intCast(n * digit0(heap, x));
    var carry: Word = @intCast(d >> DIGITWIDTH);
    const r = heap.make(.INT, @intCast(d & MAXDIGIT), 0);
    var y = restPtr(heap, r);
    x = rest(heap, x);
    while (x != 0) : (x = rest(heap, x)) {
        d = @intCast((n * digit(heap, x)) + carry);
        y.* = heap.make(.INT, @intCast(d & MAXDIGIT), 0);
        y = restPtr(heap, y.*);
        carry = @intCast(d >> DIGITWIDTH);
    }
    if (carry != 0) y.* = heap.make(.INT, carry, 0);
    return r;
}

/// Return `x / y` floored toward negative infinity (Miranda `div`); leaves the
/// remainder in `self.b_rem`. Negative results with a non-zero remainder round
/// away from zero so that `div`/`mod` satisfy `x = y*(x div y) + (x mod y)`.
///
/// Tests: div: floored division (toward negative infinity)
pub fn div(heap: *Heap, self: *Bignum, input_x: Word, input_y: Word) Word {
    var x = input_x;
    var y = input_y;
    const s1 = signBit(heap, y) != 0;
    if (s1) y = heap.make(.INT, digit0(heap, y), rest(heap, y));
    const s2 = if (signBit(heap, x) != 0) blk: {
        x = heap.make(.INT, digit0(heap, x), rest(heap, x));
        break :blk !s1;
    } else s1;
    const q = if (rest(heap, y) != 0) longDiv(heap, self, x, y) else shortDiv(heap, self, x, digit(heap, y));
    if (s2) {
        if (!isZero(heap, self.b_rem)) {
            var qx = q;
            while (true) {
                digitPtr(heap, qx).* += 1;
                if (digit(heap, qx) != IBASE) break;
                digitPtr(heap, qx).* = 0;
                if (rest(heap, qx) == 0) {
                    restPtr(heap, qx).* = heap.make(.INT, 1, 0);
                    break;
                }
                qx = rest(heap, qx);
            }
        }
        if (!isZero(heap, q)) digitPtr(heap, q).* = SIGNBIT | digit(heap, q);
    }
    return q;
}

test "div: floored division (toward negative infinity)" {
    tu.freshInterp();
    const heap = &heap_mod.heap.*;
    try std.testing.expectEqual(@as(c_longlong, 6), toInt(heap, div(heap, bn, fromInt(heap, 20), fromInt(heap, 3))));
    try std.testing.expectEqual(@as(c_longlong, 5), toInt(heap, div(heap, bn, fromInt(heap, 20), fromInt(heap, 4))));
    try std.testing.expectEqual(@as(c_longlong, -7), toInt(heap, div(heap, bn, fromInt(heap, -20), fromInt(heap, 3))));
    try std.testing.expectEqual(@as(c_longlong, 6), toInt(heap, div(heap, bn, fromInt(heap, -20), fromInt(heap, -3))));
}

/// Return `x mod y` (the result's sign follows the divisor `y`).
///
/// Tests: mod: remainder whose sign follows the divisor
pub fn mod(heap: *Heap, self: *Bignum, input_x: Word, input_y: Word) Word {
    var x = input_x;
    var y = input_y;
    const s1 = signBit(heap, y) != 0;
    if (s1) y = heap.make(.INT, digit0(heap, y), rest(heap, y));
    const s2 = if (signBit(heap, x) != 0) blk: {
        x = heap.make(.INT, digit0(heap, x), rest(heap, x));
        break :blk !s1;
    } else s1;
    _ = if (rest(heap, y) != 0) longDiv(heap, self, x, y) else shortDiv(heap, self, x, digit(heap, y));
    if (s2 and !isZero(heap, self.b_rem)) self.b_rem = sub(heap, y, self.b_rem);
    return if (s1) negate(heap, self.b_rem) else self.b_rem;
}

test "mod: remainder whose sign follows the divisor" {
    tu.freshInterp();
    const heap = &heap_mod.heap.*;
    try std.testing.expectEqual(@as(c_longlong, 2), toInt(heap, mod(heap, bn, fromInt(heap, 20), fromInt(heap, 3))));
    try std.testing.expectEqual(@as(c_longlong, 0), toInt(heap, mod(heap, bn, fromInt(heap, 20), fromInt(heap, 4))));
    try std.testing.expectEqual(@as(c_longlong, 1), toInt(heap, mod(heap, bn, fromInt(heap, -20), fromInt(heap, 3))));
    try std.testing.expectEqual(@as(c_longlong, -1), toInt(heap, mod(heap, bn, fromInt(heap, 20), fromInt(heap, -3))));
}

/// Divide a bignum by a single digit `n`; remainder left in `self.b_rem`.
fn shortDiv(heap: *Heap, self: *Bignum, input_x: Word, n: Word) Word {
    var x = input_x;
    var d = digit(heap, x);
    var q: Word = 0;
    while (rest(heap, x) != 0) {
        x = rest(heap, x);
        q = heap.make(.INT, d, q);
        d = digit(heap, x);
    }
    var tmp: Word = undefined;
    x = q;
    var s_rem = @rem(d, n);
    d = @divTrunc(d, n);
    if (d != 0 or q == 0) q = heap.make(.INT, d, 0) else q = 0;
    while (x != 0) {
        d = (s_rem * IBASE) + digit(heap, x);
        digitPtr(heap, x).* = @divTrunc(d, n);
        s_rem = @rem(d, n);
        tmp = x;
        x = rest(heap, x);
        restPtr(heap, tmp).* = q;
        q = tmp;
    }
    self.b_rem = heap.make(.INT, s_rem, 0);
    return q;
}

/// Long division of `x` by a multi-digit `y`; remainder left in `self.b_rem`.
fn longDiv(heap: *Heap, self: *Bignum, input_x: Word, input_y: Word) Word {
    var x = input_x;
    var y = input_y;
    if (cmp(heap, x, y) < 0) {
        self.b_rem = x;
        return heap.make(.INT, 0, 0);
    }
    var y1 = mostSignificantDigit(heap, y);
    const scale = @divTrunc(IBASE, y1 + 1);
    if (scale > 1) {
        x = scaleBy(heap, x, scale);
        y = scaleBy(heap, y, scale);
        y1 = mostSignificantDigit(heap, y);
    }
    var n: Word = 0;
    var q: Word = 0;
    var ly = digitCount(heap, y);
    while (true) {
        y = heap.make(.INT, 0, y);
        if (cmp(heap, x, y) < 0) break;
        n += 1;
    }
    y = rest(heap, y);
    ly += n;
    while (true) {
        var d: Word = undefined;
        const lx = digitCount(heap, x);
        if (lx < ly) {
            d = 0;
        } else if (lx == ly) {
            if (cmp(heap, x, y) >= 0) {
                x = sub(heap, x, y);
                d = 1;
            } else {
                d = 0;
            }
        } else {
            d = @divTrunc(topTwoDigits(heap, x), y1);
            if (d > MAXDIGIT) d = MAXDIGIT;
            d -= 2;
            if (d > 0) {
                x = sub(heap, x, scaleBy(heap, y, d));
            } else {
                d = 0;
            }
            if (cmp(heap, x, y) >= 0) {
                x = sub(heap, x, y);
                d += 1;
                if (cmp(heap, x, y) >= 0) {
                    x = sub(heap, x, y);
                    d += 1;
                }
            }
        }
        q = heap.make(.INT, d, q);
        if (n == 0) {
            self.b_rem = if (scale == 1) x else shortDiv(heap, self, x, scale);
            return q;
        }
        n -= 1;
        ly -= 1;
        y = rest(heap, y);
    }
}

/// Number of digit cells in the chain.
fn digitCount(heap: *Heap, input_x: Word) Word {
    var x = input_x;
    var n: Word = 1;
    while (rest(heap, x) != 0) {
        x = rest(heap, x);
        n += 1;
    }
    return n;
}

/// The leading (most-significant) digit.
fn mostSignificantDigit(heap: *Heap, input_x: Word) Word {
    var x = input_x;
    while (rest(heap, x) != 0) x = rest(heap, x);
    return digit(heap, x);
}

/// The top two digits combined as `msd * IBASE + next`.
fn topTwoDigits(heap: *Heap, input_x: Word) Word {
    var x = input_x;
    var d = digit(heap, x);
    x = rest(heap, x);
    while (rest(heap, x) != 0) {
        d = digit(heap, x);
        x = rest(heap, x);
    }
    return (digit(heap, x) * IBASE) + d;
}

/// Return `x ** y` via repeated squaring (`y >= 0`).
///
/// Tests: pow: repeated-squaring exponentiation
pub fn pow(heap: *Heap, input_x: Word, input_y: Word) Word {
    var x = input_x;
    var y = input_y;
    var r = heap.make(.INT, 1, 0);
    while (rest(heap, y) != 0) {
        var i: Word = DIGITWIDTH;
        var d = digit(heap, y);
        while (i != 0) : (i -= 1) {
            if ((d & 1) != 0) r = mul(heap, r, x);
            x = mul(heap, x, x);
            d >>= 1;
        }
        y = rest(heap, y);
    }
    var d = digit(heap, y);
    if ((d & 1) != 0) r = mul(heap, r, x);
    d >>= 1;
    while (d != 0) : (d >>= 1) {
        x = mul(heap, x, x);
        if ((d & 1) != 0) r = mul(heap, r, x);
    }
    return r;
}

test "pow: repeated-squaring exponentiation" {
    tu.freshInterp();
    const heap = &heap_mod.heap.*;
    try std.testing.expectEqual(@as(c_longlong, 1024), toInt(heap, pow(heap, fromInt(heap, 2), fromInt(heap, 10))));
    try std.testing.expectEqual(@as(c_longlong, 1), toInt(heap, pow(heap, fromInt(heap, 7), fromInt(heap, 0))));
    try std.testing.expectEqual(@as(c_longlong, 59049), toInt(heap, pow(heap, fromInt(heap, 3), fromInt(heap, 10))));
}

/// Convert a bignum to an `f64`.
///
/// Tests: toFloat: exact for small integers
pub fn toFloat(heap: *Heap, input_x: Word) f64 {
    var x = input_x;
    const s = signBit(heap, x) != 0;
    var b: f64 = 1.0;
    var r: f64 = @floatFromInt(digit0(heap, x));
    x = rest(heap, x);
    while (x != 0) {
        b *= @floatFromInt(IBASE);
        r += b * @as(f64, @floatFromInt(digit(heap, x)));
        x = rest(heap, x);
    }
    return if (s) -r else r;
}

test "toFloat: exact for small integers" {
    tu.freshInterp();
    const heap = &heap_mod.heap.*;
    try std.testing.expectEqual(@as(f64, 3.0), toFloat(heap, fromInt(heap, 3)));
    try std.testing.expectEqual(@as(f64, -3.0), toFloat(heap, fromInt(heap, -3)));
}

/// Build a bignum from the floor of an `f64` (toward negative infinity).
///
/// Tests: fromFloat: floors the input toward negative infinity
pub fn fromFloat(heap: *Heap, input: f64) Word {
    const s = input < 0;
    const r = heap.make(.INT, 0, 0);
    var ptr = r;
    var y = @abs(std.math.floor(input));
    while (true) {
        const n = @rem(y, @as(f64, @floatFromInt(IBASE)));
        digitPtr(heap, ptr).* = @intFromFloat(n);
        y = (y - n) / @as(f64, @floatFromInt(IBASE));
        if (y > 0.0) {
            restPtr(heap, ptr).* = heap.make(.INT, 0, 0);
            ptr = rest(heap, ptr);
        } else break;
    }
    if (s) digitPtr(heap, r).* = SIGNBIT | digit(heap, r);
    return r;
}

test "fromFloat: floors the input toward negative infinity" {
    tu.freshInterp();
    const heap = &heap_mod.heap.*;
    try std.testing.expectEqual(@as(c_longlong, 3), toInt(heap, fromFloat(heap, 3.9)));
    try std.testing.expectEqual(@as(c_longlong, 3), toInt(heap, fromFloat(heap, 3.0)));
    try std.testing.expectEqual(@as(c_longlong, -4), toInt(heap, fromFloat(heap, -3.9)));
}

/// Natural logarithm of a positive bignum (domain-errors on `<= 0`).
///
/// Tests: ln: natural logarithm; ln 1 == 0
pub fn ln(heap: *Heap, self: *Bignum, input_x: Word) f64 {
    var x = input_x;
    var n: Word = 0;
    var r: f64 = @floatFromInt(digit(heap, x));
    if (signBit(heap, x) != 0 or isZero(heap, x)) {
        setErrnoDomain();
        mathError("log");
    }
    while (rest(heap, x) != 0) {
        x = rest(heap, x);
        n += 1;
        r = @as(f64, @floatFromInt(digit(heap, x))) + (r / @as(f64, @floatFromInt(IBASE)));
    }
    return std.math.log(f64, std.math.e, r) + (@as(f64, @floatFromInt(n)) * self.logIBASE);
}

test "ln: natural logarithm; ln 1 == 0" {
    tu.freshInterp();
    const heap = &heap_mod.heap.*;
    setup(heap, bn);
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), ln(heap, bn, fromInt(heap, 1)), 1e-9);
    try std.testing.expectApproxEqAbs(@as(f64, 6.907755), ln(heap, bn, fromInt(heap, 1000)), 1e-5);
}

/// Base-10 logarithm of a positive bignum (domain-errors on `<= 0`).
///
/// Tests: log10: base-10 logarithm; log10 1000 == 3
pub fn log10(heap: *Heap, self: *Bignum, input_x: Word) f64 {
    var x = input_x;
    var n: Word = 0;
    var r: f64 = @floatFromInt(digit(heap, x));
    if (signBit(heap, x) != 0 or isZero(heap, x)) {
        setErrnoDomain();
        mathError("log10");
    }
    while (rest(heap, x) != 0) {
        x = rest(heap, x);
        n += 1;
        r = @as(f64, @floatFromInt(digit(heap, x))) + (r / @as(f64, @floatFromInt(IBASE)));
    }
    return std.math.log10(r) + (@as(f64, @floatFromInt(n)) * self.log10IBASE);
}

test "log10: base-10 logarithm; log10 1000 == 3" {
    tu.freshInterp();
    const heap = &heap_mod.heap.*;
    setup(heap, bn);
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), log10(heap, bn, fromInt(heap, 1)), 1e-9);
    try std.testing.expectApproxEqAbs(@as(f64, 3.0), log10(heap, bn, fromInt(heap, 1000)), 1e-9);
}

/// Set errno to `EDOM` (a maths domain error).
fn setErrnoDomain() void {
    platform.setErrno(@intCast(@intFromEnum(std.posix.E.DOM)));
}

/// Parse a NUL-terminated decimal string into a bignum.
///
/// Tests: scanDecimal: parses a NUL-terminated decimal string
pub fn scanDecimal(heap: *Heap, p: [*:0]const u8) Word {
    var cursor: usize = 0;
    var s = false;
    const r = heap.make(.INT, 0, 0);
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
        multiplyAddInPlace(heap, r, f, d);
    }
    if (s and !isZero(heap, r)) digitPtr(heap, r).* |= SIGNBIT;
    return r;
}

test "scanDecimal: parses a NUL-terminated decimal string" {
    tu.freshInterp();
    const heap = &heap_mod.heap.*;
    try std.testing.expectEqual(@as(c_longlong, 12345), toInt(heap, scanDecimal(heap, "12345")));
    try std.testing.expectEqual(@as(c_longlong, -42), toInt(heap, scanDecimal(heap, "-42")));
}

/// Parse the hex digits in the byte range `[p, q)` into a bignum.
///
/// Tests: scanHex: parses a hex byte range into a bignum
pub fn scanHex(heap: *Heap, p: [*]const u8, q: [*]const u8) Word {
    const r = heap.make(.INT, 0, 0);
    var cursor: usize = 0;
    const len = @intFromPtr(q) - @intFromPtr(p);
    while (cursor < len) {
        var d: Word = hexValue(p[cursor]);
        var f: Word = 16;
        cursor += 1;
        while (cursor < len and f < PSIXTEEN) {
            d = (16 * d) + hexValue(p[cursor]);
            f *= 16;
            cursor += 1;
        }
        multiplyAddInPlace(heap, r, f, d);
    }
    return r;
}

test "scanHex: parses a hex byte range into a bignum" {
    tu.freshInterp();
    const heap = &heap_mod.heap.*;
    const p: [*]const u8 = "ff";
    try std.testing.expectEqual(@as(c_longlong, 255), toInt(heap, scanHex(heap, p, p + 2)));
    const q: [*]const u8 = "1000";
    try std.testing.expectEqual(@as(c_longlong, 0x1000), toInt(heap, scanHex(heap, q, q + 4)));
    const z: [*]const u8 = "00";
    try std.testing.expectEqual(@as(c_longlong, 0), toInt(heap, scanHex(heap, z, z + 2)));
    const val: [*]const u8 = "1A2B3C";
    try std.testing.expectEqual(@as(c_longlong, 1715004), toInt(heap, scanHex(heap, val, val + 6)));
}

/// Parse the octal digits in the byte range `[p, q)` into a bignum.
///
/// Tests: scanOctal: parses an octal byte range into a bignum
pub fn scanOctal(heap: *Heap, p: [*]const u8, q: [*]const u8) Word {
    const r = heap.make(.INT, 0, 0);
    var cursor: usize = 0;
    const len = @intFromPtr(q) - @intFromPtr(p);
    while (cursor < len) {
        var d: Word = p[cursor] - '0';
        var f: Word = 8;
        cursor += 1;
        while (cursor < len and f < PEIGHT) {
            d = (8 * d) + p[cursor] - '0';
            f *= 8;
            cursor += 1;
        }
        multiplyAddInPlace(heap, r, f, d);
    }
    return r;
}

test "scanOctal: parses an octal byte range into a bignum" {
    tu.freshInterp();
    const heap = &heap_mod.heap.*;
    const p: [*]const u8 = "17";
    try std.testing.expectEqual(@as(c_longlong, 15), toInt(heap, scanOctal(heap, p, p + 2)));
    const q: [*]const u8 = "777";
    try std.testing.expectEqual(@as(c_longlong, 511), toInt(heap, scanOctal(heap, q, q + 3)));
    const z: [*]const u8 = "0000";
    try std.testing.expectEqual(@as(c_longlong, 0), toInt(heap, scanOctal(heap, z, z + 4)));
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
///
/// Tests: parseString: parses a char-list of digits in a given base
pub fn parseString(heap: *Heap, input_z: Word, base: c_int) Word {
    var z = input_z;
    var s = false;
    const r = heap.make(.INT, 0, 0);
    var pbase: Word = PTEN;
    if (base == 16) pbase = PSIXTEEN else if (base == 8) pbase = PEIGHT;
    if (z != NIL and heap.h(z) == '-') {
        s = true;
        z = heap.t(z);
    }
    if (base != 10) z = heap.t(heap.t(z));
    while (z != NIL) {
        var d = digitValue(heap.h(z));
        var f: Word = base;
        z = heap.t(z);
        while (z != NIL and f < pbase) {
            d = (@as(Word, base) * d) + digitValue(heap.h(z));
            f *= base;
            z = heap.t(z);
        }
        multiplyAddInPlace(heap, r, f, d);
    }
    if (s and !isZero(heap, r)) digitPtr(heap, r).* |= SIGNBIT;
    return r;
}

test "parseString: parses a char-list of digits in a given base" {
    tu.freshInterp();
    const heap = &heap_mod.heap.*;
    try std.testing.expectEqual(@as(c_longlong, 123), toInt(heap, parseString(heap, tu.str("123"), 10)));
    try std.testing.expectEqual(@as(c_longlong, -7), toInt(heap, parseString(heap, tu.str("-7"), 10)));
    // base != 10 skips the two-char prefix (e.g. "0xff")
    try std.testing.expectEqual(@as(c_longlong, 255), toInt(heap, parseString(heap, tu.str("0xff"), 16)));
}

/// In place: `r = r*f + addend` — the Horner step shared by the scanners.
fn multiplyAddInPlace(heap: *Heap, r: Word, f: Word, addend: Word) void {
    var d = (f * digit(heap, r)) + addend;
    var carry = d >> DIGITWIDTH;
    var x = restPtr(heap, r);
    digitPtr(heap, r).* = d & MAXDIGIT;
    while (x.* != 0) {
        d = (f * digit(heap, x.*)) + carry;
        digitPtr(heap, x.*).* = d & MAXDIGIT;
        carry = d >> DIGITWIDTH;
        x = restPtr(heap, x.*);
    }
    if (carry != 0) x.* = heap.make(.INT, carry, 0);
}

/// Render a bignum as a Miranda char list of decimal digits.
///
/// Tests: toDecimalList: renders a bignum as decimal digits
pub fn toDecimalList(heap: *Heap, input_x: Word) Word {
    var x = input_x;
    if (rest(heap, x) == 0) return wordToDecimalList(heap, toSmallInt(heap, x));
    const sign = signBit(heap, x) != 0;
    var x1 = heap.make(.INT, digit0(heap, x), 0);
    x = rest(heap, x);
    while (x != 0) {
        x1 = heap.make(.INT, digit(heap, x), x1);
        x = rest(heap, x);
    }
    x = x1;
    var s: Word = NIL;
    while (true) {
        var d = digit(heap, x);
        var rem = @rem(d, PTEN);
        d = @divTrunc(d, PTEN);
        x1 = rest(heap, x);
        if (d != 0) digitPtr(heap, x).* = d else x = x1;
        while (x1 != 0) {
            d = (rem * IBASE) + digit(heap, x1);
            digitPtr(heap, x1).* = @divTrunc(d, PTEN);
            rem = @rem(d, PTEN);
            x1 = rest(heap, x1);
        }
        if (x != 0) {
            var i: Word = TENW;
            while (i != 0) : (i -= 1) {
                s = heap.cons('0' + @rem(rem, 10), s);
                rem = @divTrunc(rem, 10);
            }
        } else {
            while (rem != 0) {
                s = heap.cons('0' + @rem(rem, 10), s);
                rem = @divTrunc(rem, 10);
            }
            return if (sign) heap.cons('-', s) else s;
        }
    }
}

test "toDecimalList: renders a bignum as decimal digits" {
    tu.freshInterp();
    const heap = &heap_mod.heap.*;
    try tu.expectStr("12345", toDecimalList(heap, fromInt(heap, 12345)));
    try tu.expectStr("-42", toDecimalList(heap, fromInt(heap, -42)));
    try tu.expectStr("0", toDecimalList(heap, fromInt(heap, 0)));
}

/// Render a small `Word` as a decimal char list.
fn wordToDecimalList(heap: *Heap, value: Word) Word {
    var buffer: [64]u8 = undefined;
    // 64 bytes holds any decimal Word (<= 20 digits); bufPrint cannot overflow.
    const text = std.fmt.bufPrint(&buffer, "{d}", .{value}) catch unreachable;
    var result: Word = NIL;
    var i = text.len;
    while (i != 0) {
        i -= 1;
        result = heap.cons(text[i], result);
    }
    return result;
}

/// Render a bignum as a `0x`-prefixed hex char list (leading zeros trimmed).
///
/// Tests: toHexList: renders a 0x-prefixed hex char list
pub fn toHexList(heap: *Heap, input_x: Word) Word {
    var x = input_x;
    var r: Word = NIL;
    const s = signBit(heap, x) != 0;
    while (x != 0) {
        var count: Word = 4;
        var factor: u64 = 1;
        var hold: u64 = 0;
        while (count != 0 and x != 0) : (count -= 1) {
            hold += factor * @as(u64, @intCast(digit0(heap, x)));
            factor <<= 15;
            x = rest(heap, x);
        }
        var buffer: [16]u8 = undefined;
        // exactly 15 hex digits formatted into a 16-byte buffer; cannot overflow.
        const text = std.fmt.bufPrint(&buffer, "{x:0>15}", .{hold}) catch unreachable;
        var i = text.len;
        while (i != 0) {
            i -= 1;
            r = heap.cons(text[i], r);
        }
    }
    while (digit(heap, r) == '0' and rest(heap, r) != NIL) r = rest(heap, r);
    r = heap.cons('0', heap.cons('x', r));
    if (s) r = heap.cons('-', r);
    return r;
}

test "toHexList: renders a 0x-prefixed hex char list" {
    tu.freshInterp();
    const heap = &heap_mod.heap.*;
    try tu.expectStr("0xff", toHexList(heap, fromInt(heap, 255)));
    try tu.expectStr("0x0", toHexList(heap, fromInt(heap, 0)));
}

/// Render a bignum as a `0o`-prefixed octal char list (leading zeros trimmed).
///
/// Tests: toOctalList: renders a 0o-prefixed octal char list
pub fn toOctalList(heap: *Heap, input_x: Word) Word {
    var x = input_x;
    var r: Word = NIL;
    const s = signBit(heap, x) != 0;
    while (x != 0) {
        var buffer: [6]u8 = undefined;
        // exactly 5 octal digits formatted into a 6-byte buffer; cannot overflow.
        const text = std.fmt.bufPrint(&buffer, "{o:0>5}", .{@as(u64, @intCast(digit0(heap, x)))}) catch unreachable;
        var i = text.len;
        while (i != 0) {
            i -= 1;
            r = heap.cons(text[i], r);
        }
        x = rest(heap, x);
    }
    while (digit(heap, r) == '0' and rest(heap, r) != NIL) r = rest(heap, r);
    r = heap.cons('0', heap.cons('o', r));
    if (s) r = heap.cons('-', r);
    return r;
}

test "toOctalList: renders a 0o-prefixed octal char list" {
    tu.freshInterp();
    const heap = &heap_mod.heap.*;
    try tu.expectStr("0o17", toOctalList(heap, fromInt(heap, 15)));
    try tu.expectStr("0o0", toOctalList(heap, fromInt(heap, 0)));
}
