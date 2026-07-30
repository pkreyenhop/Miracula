//! bignum_fmt.zig (split from graph/bignum.zig for the Go port's <1000-line
//! file ratchet, docs/GO_PORT_PLAN.md P4) — the string<->bignum conversion
//! half: scan (`scanDecimal`/`scanHex`/`scanOctal`/`parseString`) and format
//! (`toDecimalList`/`toHexList`/`toOctalList`). The arithmetic core and the
//! shared digit-cell primitives stay in `bignum.zig`; the moved bodies reach
//! them one-way through the `big.*` aliases below (no import cycle).

const std = @import("std");
const heap_mod = @import("heap.zig");
const Heap = heap_mod.Heap;
const word = @import("word.zig");
const tu = @import("../testutil.zig"); // unit-test harness (test builds only)

const Word = i64;
const SIGNBIT: Word = 0x10000000;
const IBASE: Word = 0x8000;
const MAXDIGIT: Word = 0x7fff;
const DIGITWIDTH: Word = 15;
const PTEN: Word = 10000;
const PSIXTEEN: Word = 4096;
const PEIGHT: Word = 0x8000;
const TENW: Word = 4;
const NIL = word.NIL;

const big = @import("bignum.zig");
const digit0 = big.digit0;
const digit = big.digit;
const digitPtr = big.digitPtr;
const isZero = big.isZero;
const rest = big.rest;
const restPtr = big.restPtr;
const signBit = big.signBit;
const toSmallInt = big.toSmallInt;
const fromInt = big.fromInt;
const toInt = big.toInt;
const CellPtr = big.CellPtr;

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
    const heap = &heap_mod.heap().*;
    try std.testing.expectEqual(@as(i64, 12345), toInt(heap, scanDecimal(heap, "12345")));
    try std.testing.expectEqual(@as(i64, -42), toInt(heap, scanDecimal(heap, "-42")));
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
    const heap = &heap_mod.heap().*;
    const p: [*]const u8 = "ff";
    try std.testing.expectEqual(@as(i64, 255), toInt(heap, scanHex(heap, p, p + 2)));
    const q: [*]const u8 = "1000";
    try std.testing.expectEqual(@as(i64, 0x1000), toInt(heap, scanHex(heap, q, q + 4)));
    const z: [*]const u8 = "00";
    try std.testing.expectEqual(@as(i64, 0), toInt(heap, scanHex(heap, z, z + 2)));
    const val: [*]const u8 = "1A2B3C";
    try std.testing.expectEqual(@as(i64, 1715004), toInt(heap, scanHex(heap, val, val + 6)));
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
    const heap = &heap_mod.heap().*;
    const p: [*]const u8 = "17";
    try std.testing.expectEqual(@as(i64, 15), toInt(heap, scanOctal(heap, p, p + 2)));
    const q: [*]const u8 = "777";
    try std.testing.expectEqual(@as(i64, 511), toInt(heap, scanOctal(heap, q, q + 3)));
    const z: [*]const u8 = "0000";
    try std.testing.expectEqual(@as(i64, 0), toInt(heap, scanOctal(heap, z, z + 4)));
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
pub fn parseString(heap: *Heap, input_z: Word, base: i32) Word {
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
    const heap = &heap_mod.heap().*;
    try std.testing.expectEqual(@as(i64, 123), toInt(heap, parseString(heap, tu.str("123"), 10)));
    try std.testing.expectEqual(@as(i64, -7), toInt(heap, parseString(heap, tu.str("-7"), 10)));
    // base != 10 skips the two-char prefix (e.g. "0xff")
    try std.testing.expectEqual(@as(i64, 255), toInt(heap, parseString(heap, tu.str("0xff"), 16)));
}

/// In place: `r = r*f + addend` — the Horner step shared by the scanners.
fn multiplyAddInPlace(heap: *Heap, r: Word, f: Word, addend: Word) void {
    var d = (f * digit(heap, r)) + addend;
    var carry = d >> DIGITWIDTH;
    var x = restPtr(heap, r);
    digitPtr(heap, r).* = d & MAXDIGIT;
    while (x.get() != 0) {
        d = (f * digit(heap, x.get())) + carry;
        digitPtr(heap, x.get()).* = d & MAXDIGIT;
        carry = d >> DIGITWIDTH;
        x = restPtr(heap, x.get());
    }
    if (carry != 0) x.set(heap.make(.INT, carry, 0));
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
    const heap = &heap_mod.heap().*;
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
    const heap = &heap_mod.heap().*;
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
    const heap = &heap_mod.heap().*;
    try tu.expectStr("0o17", toOctalList(heap, fromInt(heap, 15)));
    try tu.expectStr("0o0", toOctalList(heap, fromInt(heap, 0)));
}
