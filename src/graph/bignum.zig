//! bignum.zig (renamed from big.zig, Phase 4 step 1, docs/GoReady.md)
//! — arbitrary-precision integers (bignums).
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
//! ambiently — the file itself never reads `bn.X`/`heap.heap().X` internally.
//! Callers still source these pointers from the (still-global, Tier-3-deferred)
//! singletons via the `bn`/`heap.heap()` convenience constants below; only this
//! module's own internals stopped assuming where they come from.

const std = @import("std");
const rt = @import("../runtime/runtime_state.zig");

const platform = @import("../io/platform.zig");
const heap_mod = @import("heap.zig");
const Heap = heap_mod.Heap;
const word = @import("word.zig");
const reduce = @import("../eval/reduce_rt.zig");
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

/// Pointer to the bignum subsystem state held in `current_interp` (so
/// `interp.reset()` clears it). A convenience for *callers* to obtain a
/// `*Bignum` to pass in — this module's own functions no longer read `bn.X`
/// themselves.
pub inline fn bn() *Bignum {
    return &@import("../session/interp.zig").current_interp.big;
}

/// The head cell's digit with the sign/overflow bits masked off (its plain
/// 0..MAXDIGIT value).
pub fn digit0(heap: *Heap, x: Word) Word {
    return heap.h(x) & MAXDIGIT;
}
/// The head cell's digit field, raw (may carry `SIGNBIT` on the head cell).
pub fn digit(heap: *Heap, x: Word) Word {
    return heap.h(x);
}
/// Pointer to the head cell's digit field (for in-place mutation).
pub fn digitPtr(heap: *Heap, x: Word) *Word {
    return heap.hp(x);
}
/// The rest of the chain — the next (more-significant) digit cell.
pub fn rest(heap: *Heap, x: Word) Word {
    return heap.t(x);
}
/// Pointer to the chain link, for in-place mutation / appending digits.
pub const CellPtr = struct {
    heap: *Heap,
    cell: Word,
    pub inline fn set(self: CellPtr, val: Word) void {
        self.heap.tp(self.cell).* = val;
    }
    pub inline fn get(self: CellPtr) Word {
        return self.heap.tp(self.cell).*;
    }
};
pub fn restPtr(heap: *Heap, x: Word) CellPtr {
    return .{ .heap = heap, .cell = x };
}

/// Whether `x` is non-negative (no `SIGNBIT` on the head digit).
fn isPositive(heap: *Heap, x: Word) bool {
    return (heap.h(x) & SIGNBIT) == 0;
}
/// The sign bit of `x` (`SIGNBIT` if negative, else 0).
pub fn signBit(heap: *Heap, x: Word) Word {
    return heap.h(x) & SIGNBIT;
}
/// Whether `x` is the single-cell zero.
pub fn isZero(heap: *Heap, x: Word) bool {
    return digit(heap, x) == 0 and rest(heap, x) == 0;
}
/// Decode a single-cell bignum to a signed `Word` (caller guarantees one cell).
pub fn toSmallInt(heap: *Heap, x: Word) Word {
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
    setup(&heap_mod.heap().*, bn());
    try std.testing.expectEqual(@as(i64, 1), toInt(&heap_mod.heap().*, bn().big_one));
}

/// 1 if `x` is a non-negative integer (`INT`-tagged and positive), else 0.
///
/// Tests: isNat: 1 for non-negative INTs, 0 for negatives
pub fn isNat(heap: *Heap, x: Word) bool {
    return heap.getTag(x) == .INT and isPositive(heap, x);
}

test "isNat: 1 for non-negative INTs, 0 for negatives" {
    tu.freshInterp();
    const heap = &heap_mod.heap().*;
    try std.testing.expect(isNat(heap, fromInt(heap, 5)));
    try std.testing.expect(isNat(heap, fromInt(heap, 0)));
    try std.testing.expect(!isNat(heap, fromInt(heap, -5)));
}

/// Build a bignum from a signed 64-bit integer.
///
/// Tests: fromInt: round-trips through toInt across the digit boundary
pub fn fromInt(heap: *Heap, input: i64) Word {
    var i = input;
    var s: Word = 0;
    if (i < 0) {
        s = SIGNBIT;
        i = -i;
    }
    var unsigned_i: u64 = @intCast(i);
    const x = heap.make(.INT, s | @as(Word, @intCast(unsigned_i & MAXDIGIT)), 0);
    unsigned_i >>= DIGITWIDTH;
    if (unsigned_i != 0) {
        var p = restPtr(heap, x);
        p.set(heap.make(.INT, @intCast(unsigned_i & MAXDIGIT), 0));
        p = restPtr(heap, p.get());
        unsigned_i >>= DIGITWIDTH;
        while (unsigned_i != 0) : (unsigned_i >>= DIGITWIDTH) {
            p.set(heap.make(.INT, @intCast(unsigned_i & MAXDIGIT), 0));
            p = restPtr(heap, p.get());
        }
    }
    return x;
}

test "fromInt: round-trips through toInt across the digit boundary" {
    tu.freshInterp();
    const heap = &heap_mod.heap().*;
    for ([_]i64{ 0, 1, -1, 42, -42, 32768, 1 << 20, 1 << 40 }) |n| {
        try std.testing.expectEqual(n, toInt(heap, fromInt(heap, n)));
    }
}

/// Convert a bignum to a signed 64-bit integer (saturates above ~2^60).
///
/// Tests: toInt: saturates above 2^60
pub fn toInt(heap: *Heap, input: Word) i64 {
    var x = input;
    var n: i64 = @intCast(digit0(heap, x));
    const sign = signBit(heap, x) != 0;
    x = rest(heap, x);
    if (x == 0) return if (sign) -n else n;

    var w: Word = DIGITWIDTH;
    while (x != 0 and w < 60) : ({
        w += DIGITWIDTH;
        x = rest(heap, x);
    }) {
        n += @as(i64, @intCast(digit(heap, x))) << @intCast(w);
    }
    if (x != 0) n = @as(i64, 1) << 60;
    return if (sign) -n else n;
}

test "toInt: saturates above 2^60" {
    tu.freshInterp();
    const heap = &heap_mod.heap().*;
    // 2^61 exceeds the 60-bit window, so toInt clamps to 2^60.
    const big61 = mul(heap, fromInt(heap, 1 << 40), fromInt(heap, 1 << 21));
    try std.testing.expectEqual(@as(i64, 1) << 60, toInt(heap, big61));
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
    const heap = &heap_mod.heap().*;
    try std.testing.expectEqual(@as(i64, -7), toInt(heap, negate(heap, fromInt(heap, 7))));
    try std.testing.expectEqual(@as(i64, 7), toInt(heap, negate(heap, fromInt(heap, -7))));
    try std.testing.expectEqual(@as(i64, 0), toInt(heap, negate(heap, fromInt(heap, 0))));
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
    const heap = &heap_mod.heap().*;
    try std.testing.expectEqual(@as(i64, 5), toInt(heap, add(heap, fromInt(heap, 2), fromInt(heap, 3))));
    try std.testing.expectEqual(@as(i64, -1), toInt(heap, add(heap, fromInt(heap, 2), fromInt(heap, -3))));
    try std.testing.expectEqual(@as(i64, 65536), toInt(heap, add(heap, fromInt(heap, 32768), fromInt(heap, 32768))));
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
    if (x == 0 and y == 0 and carry == 0) return r;
    var x_root = heap.roots.root(rt.allocator, &x);
    defer x_root.deinit();
    var y_root = heap.roots.root(rt.allocator, &y);
    defer y_root.deinit();
    var r_root = heap.roots.root(rt.allocator, &r);
    defer r_root.deinit();
    while (x != 0 and y != 0) {
        d = carry + digit(heap, x) + digit(heap, y);
        carry = if ((d & IBASE) != 0) 1 else 0;
        z.set(heap.make(.INT, d & MAXDIGIT, 0));
        x = rest(heap, x);
        y = rest(heap, y);
        z = restPtr(heap, z.get());
    }
    if (y != 0) x = y;
    while (x != 0) {
        d = carry + digit(heap, x);
        carry = if ((d & IBASE) != 0) 1 else 0;
        z.set(heap.make(.INT, d & MAXDIGIT, 0));
        x = rest(heap, x);
        z = restPtr(heap, z.get());
    }
    if (carry != 0) z.set(heap.make(.INT, 1, 0));
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
    const heap = &heap_mod.heap().*;
    try std.testing.expectEqual(@as(i64, -1), toInt(heap, sub(heap, fromInt(heap, 2), fromInt(heap, 3))));
    try std.testing.expectEqual(@as(i64, 5), toInt(heap, sub(heap, fromInt(heap, 2), fromInt(heap, -3))));
    try std.testing.expectEqual(@as(i64, 0), toInt(heap, sub(heap, fromInt(heap, 40), fromInt(heap, 40))));
}

/// Subtract unsigned magnitudes (|x| - |y|, |x| >= |y|), normalising the result.
fn subMagnitude(heap: *Heap, input_x: Word, input_y: Word) Word {
    var x = input_x;
    var y = input_y;
    var d = digit0(heap, x) - digit0(heap, y);
    var borrow: Word = if ((d & IBASE) != 0) 1 else 0;
    const r = heap.make(.INT, d & MAXDIGIT, 0);
    var z = restPtr(heap, r);
    var p: ?CellPtr = null;
    x = rest(heap, x);
    y = rest(heap, y);
    if (x == 0 and y == 0 and borrow == 0) return r;
    var x_root = heap.roots.root(rt.allocator, &x);
    defer x_root.deinit();
    var y_root = heap.roots.root(rt.allocator, &y);
    defer y_root.deinit();
    var r_root = heap.roots.root(rt.allocator, &r);
    defer r_root.deinit();
    while (x != 0 and y != 0) {
        d = digit(heap, x) - digit(heap, y) - borrow;
        borrow = if ((d & IBASE) != 0) 1 else 0;
        d &= MAXDIGIT;
        z.set(heap.make(.INT, d, 0));
        if (d != 0) p = null else if (p == null) p = z;
        x = rest(heap, x);
        y = rest(heap, y);
        z = restPtr(heap, z.get());
    }
    while (y != 0) {
        d = -digit(heap, y) - borrow;
        borrow = if ((d & IBASE) != 0) 1 else 0;
        d &= MAXDIGIT;
        z.set(heap.make(.INT, d, 0));
        if (d != 0) p = null else if (p == null) p = z;
        y = rest(heap, y);
        z = restPtr(heap, z.get());
    }
    while (x != 0) {
        d = digit(heap, x) - borrow;
        borrow = if ((d & IBASE) != 0) 1 else 0;
        d &= MAXDIGIT;
        z.set(heap.make(.INT, d, 0));
        if (d != 0) p = null else if (p == null) p = z;
        x = rest(heap, x);
        z = restPtr(heap, z.get());
    }
    if (borrow != 0) {
        p = null;
        d = (digit(heap, r) ^ MAXDIGIT) + 1;
        borrow = if ((d & IBASE) != 0) 1 else 0;
        digitPtr(heap, r).* = SIGNBIT | d;
        z = restPtr(heap, r);
        while (z.get() != 0) {
            d = (digit(heap, z.get()) ^ MAXDIGIT) + borrow;
            borrow = if ((d & IBASE) != 0) 1 else 0;
            d &= MAXDIGIT;
            digitPtr(heap, z.get()).* = d;
            if (d != 0) p = null else if (p == null) p = z;
            z = restPtr(heap, z.get());
        }
    }
    if (p) |ptr| ptr.set(0);
    return r;
}

/// Three-way compare: -1 / 0 / 1 for `x < y` / `x == y` / `x > y`.
///
/// Tests: cmp: three-way -1 / 0 / 1
pub fn cmp(heap: *Heap, input_x: Word, input_y: Word) i32 {
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
    const heap = &heap_mod.heap().*;
    try std.testing.expectEqual(@as(i32, -1), cmp(heap, fromInt(heap, 1), fromInt(heap, 2)));
    try std.testing.expectEqual(@as(i32, 0), cmp(heap, fromInt(heap, 2), fromInt(heap, 2)));
    try std.testing.expectEqual(@as(i32, 1), cmp(heap, fromInt(heap, 2), fromInt(heap, 1)));
    try std.testing.expectEqual(@as(i32, -1), cmp(heap, fromInt(heap, -2), fromInt(heap, 1)));
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
    const heap = &heap_mod.heap().*;
    try std.testing.expectEqual(@as(i64, 42), toInt(heap, mul(heap, fromInt(heap, 6), fromInt(heap, 7))));
    try std.testing.expectEqual(@as(i64, -42), toInt(heap, mul(heap, fromInt(heap, -6), fromInt(heap, 7))));
    try std.testing.expectEqual(@as(i64, 1 << 40), toInt(heap, mul(heap, fromInt(heap, 1 << 20), fromInt(heap, 1 << 20))));
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
        y.set(heap.make(.INT, @intCast(d & MAXDIGIT), 0));
        y = restPtr(heap, y.get());
        carry = @intCast(d >> DIGITWIDTH);
    }
    if (carry != 0) y.set(heap.make(.INT, carry, 0));
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
                    restPtr(heap, qx).set(heap.make(.INT, 1, 0));
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
    const heap = &heap_mod.heap().*;
    try std.testing.expectEqual(@as(i64, 6), toInt(heap, div(heap, bn(), fromInt(heap, 20), fromInt(heap, 3))));
    try std.testing.expectEqual(@as(i64, 5), toInt(heap, div(heap, bn(), fromInt(heap, 20), fromInt(heap, 4))));
    try std.testing.expectEqual(@as(i64, -7), toInt(heap, div(heap, bn(), fromInt(heap, -20), fromInt(heap, 3))));
    try std.testing.expectEqual(@as(i64, 6), toInt(heap, div(heap, bn(), fromInt(heap, -20), fromInt(heap, -3))));
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
    const heap = &heap_mod.heap().*;
    try std.testing.expectEqual(@as(i64, 2), toInt(heap, mod(heap, bn(), fromInt(heap, 20), fromInt(heap, 3))));
    try std.testing.expectEqual(@as(i64, 0), toInt(heap, mod(heap, bn(), fromInt(heap, 20), fromInt(heap, 4))));
    try std.testing.expectEqual(@as(i64, 1), toInt(heap, mod(heap, bn(), fromInt(heap, -20), fromInt(heap, 3))));
    try std.testing.expectEqual(@as(i64, -1), toInt(heap, mod(heap, bn(), fromInt(heap, 20), fromInt(heap, -3))));
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
        restPtr(heap, tmp).set(q);
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
    const heap = &heap_mod.heap().*;
    try std.testing.expectEqual(@as(i64, 1024), toInt(heap, pow(heap, fromInt(heap, 2), fromInt(heap, 10))));
    try std.testing.expectEqual(@as(i64, 1), toInt(heap, pow(heap, fromInt(heap, 7), fromInt(heap, 0))));
    try std.testing.expectEqual(@as(i64, 59049), toInt(heap, pow(heap, fromInt(heap, 3), fromInt(heap, 10))));
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
    const heap = &heap_mod.heap().*;
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
            restPtr(heap, ptr).set(heap.make(.INT, 0, 0));
            ptr = rest(heap, ptr);
        } else break;
    }
    if (s) digitPtr(heap, r).* = SIGNBIT | digit(heap, r);
    return r;
}

test "fromFloat: floors the input toward negative infinity" {
    tu.freshInterp();
    const heap = &heap_mod.heap().*;
    try std.testing.expectEqual(@as(i64, 3), toInt(heap, fromFloat(heap, 3.9)));
    try std.testing.expectEqual(@as(i64, 3), toInt(heap, fromFloat(heap, 3.0)));
    try std.testing.expectEqual(@as(i64, -4), toInt(heap, fromFloat(heap, -3.9)));
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
    const heap = &heap_mod.heap().*;
    setup(heap, bn());
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), ln(heap, bn(), fromInt(heap, 1)), 1e-9);
    try std.testing.expectApproxEqAbs(@as(f64, 6.907755), ln(heap, bn(), fromInt(heap, 1000)), 1e-5);
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
    const heap = &heap_mod.heap().*;
    setup(heap, bn());
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), log10(heap, bn(), fromInt(heap, 1)), 1e-9);
    try std.testing.expectApproxEqAbs(@as(f64, 3.0), log10(heap, bn(), fromInt(heap, 1000)), 1e-9);
}

/// Set errno to `EDOM` (a maths domain error).
fn setErrnoDomain() void {
    platform.setErrno(@intCast(@intFromEnum(std.posix.E.DOM)));
}
