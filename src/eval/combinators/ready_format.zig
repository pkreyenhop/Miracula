//! eval/combinators/ready_format.zig (split from ready.zig for the Go port's
//! <1000-line file ratchet, docs/GO_PORT_PLAN.md P4) — Miranda `show`/`shownum`
//! float formatting: `formatMiraShowNum`/`formatMiraFixed`/`formatMiraScaled`/
//! `formatMiraHex` (and the `bufFallback`/`toCScientificExponent` helpers).
//! Pure `(buf, value) -> []const u8` string formatting, depending only on
//! `std`; `ready.zig`'s `handleReadyState` calls the four entry points via
//! aliases. The output format is golden-pinned, moved here byte-for-byte.

const std = @import("std");

/// Miranda's `shownum` on a double: the shortest decimal string that
/// round-trips exactly, with a guaranteed ".0" suffix if it would
/// otherwise look like an integer (`show 2.0` must print "2.0", not "2").
/// Verified byte-identical to the old `sprintf(..., "%.16g", ...)` path
/// across a range of representative values (both already delegated to
/// Zig's own `{d}` float formatter under the hood — `os.zig`'s
/// `formatC`'s `'f'/'g'/'e'/'a'` case ignored the requested C specifier
/// and precision entirely, always calling `std.fmt.bufPrint(&buf, "{d}",
/// .{val})` — so this is a direct, behavior-preserving port of what was
/// already happening, minus the pointless C-format-string round trip).
///
/// Tests: formatMiraShowNum matches shownum's ".0"-suffix rule
pub fn formatMiraShowNum(buf: []u8, value: f64) []const u8 {
    const s = std.fmt.bufPrint(buf, "{d}", .{value}) catch return bufFallback(buf, "0.0");
    if (std.mem.indexOfAny(u8, s, ".eE") != null) return s;
    // No '.'/exponent -- looks like a bare integer; append ".0" in place.
    if (s.len + 2 > buf.len) return s;
    buf[s.len] = '.';
    buf[s.len + 1] = '0';
    return buf[0 .. s.len + 2];
}

/// A buffer-backed fallback string (so callers that index into the
/// returned slice's own backing `buf` — to place a NUL terminator right
/// after it, matching `sprintf`'s convention — stay correct even on the
/// rare error path, where returning a bare string literal instead would
/// leave `buf` holding stale bytes before the terminator).
fn bufFallback(buf: []u8, text: []const u8) []const u8 {
    const n = @min(text.len, buf.len);
    @memcpy(buf[0..n], text[0..n]);
    return buf[0..n];
}

/// Miranda's `showfloat n x`: `x` fixed to exactly `n` decimal places
/// (`%.*f`). The old `sprintf(..., "%.*f", .{n, x})` call silently
/// discarded `n` (`formatC`'s float case never read its `precision`
/// argument — confirmed via `_ = precision;` in `formatArg`) and, worse,
/// `formatC`'s own `%.*` width/precision parsing didn't handle the `*`
/// (read-precision-from-args) form at all, producing literal garbage
/// (`?INVALID_SPECIFIER?f`) for every call — a real, pre-existing,
/// completely broken builtin, not merely an imprecise one. Fixed here
/// using Zig's own precision-aware float formatting, which needs no
/// C-convention translation (unlike scientific notation's exponent sign).
///
/// Tests: formatMiraFixed matches a fixed decimal-places count
pub fn formatMiraFixed(buf: []u8, precision: usize, value: f64) []const u8 {
    return std.fmt.bufPrint(buf, "{d:.[1]}", .{ value, precision }) catch bufFallback(buf, "0.0");
}

/// Miranda's `showscaled n x`: `x` in scientific notation with `n`
/// digits after the mantissa's decimal point (`%.*e`) — same
/// precision-discarding/garbage-output bug as `showfloat` (see
/// `formatMiraFixed`'s doc comment), fixed here the same way, plus one
/// extra step: Zig's `{e}` exponent is bare (`e5`, `e-4`), where C's `%e`
/// requires an explicit sign and a minimum of two digits (`e+05`,
/// `e-04`) — `toCScientificExponent` bridges that gap. Verified against
/// the C standard's own `%e` specification (mandatory sign, zero-padded
/// to at least 2 digits), not a live reference binary (none was
/// available in this sandbox) — flagged as the one part of this
/// conversion without an executable oracle to check against.
///
/// Tests: formatMiraScaled produces a C-style signed, zero-padded exponent
pub fn formatMiraScaled(buf: []u8, precision: usize, value: f64) []const u8 {
    var zig_buf: [64]u8 = undefined;
    const zig_sci = std.fmt.bufPrint(&zig_buf, "{e:.[1]}", .{ value, precision }) catch return bufFallback(buf, "0.0e+00");
    return toCScientificExponent(buf, zig_sci) catch bufFallback(buf, "0.0e+00");
}

/// Reformat Zig's `{e:.N}` output (`"1.235e5"`, `"1.234e-4"`) into C's
/// `%.*e` convention (`"1.235e+05"`, `"1.234e-04"`).
fn toCScientificExponent(buf: []u8, zig_sci: []const u8) ![]const u8 {
    const e_idx = std.mem.indexOfScalar(u8, zig_sci, 'e').?;
    const mantissa = zig_sci[0..e_idx];
    const exp = try std.fmt.parseInt(i32, zig_sci[e_idx + 1 ..], 10);
    return std.fmt.bufPrint(buf, "{s}e{c}{:0>2}", .{ mantissa, @as(u8, if (exp < 0) '-' else '+'), @abs(exp) });
}

/// Miranda's `showhex x`: `x` as a C99 hex-float literal (`%a`) — per the
/// manual (`docs/man/mira.man.ms`), `showhex pi => 0x1.921fb54442d18p+1`.
/// The old `sprintf(..., "%a", ...)` call hit the same `formatC` fallback
/// as `shownum`'s `%.16g` (see `formatMiraShowNum`'s doc comment) and
/// printed a plain *decimal* number instead — not merely imprecise, the
/// wrong notation entirely. Fixed here with Zig's own `{x}` float
/// formatting, verified to match the manual's own worked example exactly
/// (`0x1.921fb54442d18` — a real `f64`'s 52-bit mantissa is exactly 13
/// hex digits, and C99 specifies `%a` prints the *exact*, non-shortened
/// mantissa when no precision is given, same as Zig's default): the only
/// gap is the exponent's mandatory sign (`p+1`, not Zig's bare `p1`) —
/// `%a`'s exponent has no minimum-digit-count requirement (unlike `%e`'s
/// 2-digit floor), so no zero-padding is needed here.
///
/// Tests: formatMiraHex matches the manual's showhex pi example
pub fn formatMiraHex(buf: []u8, value: f64) []const u8 {
    var zig_buf: [64]u8 = undefined;
    const zig_hex = std.fmt.bufPrint(&zig_buf, "{x}", .{value}) catch return bufFallback(buf, "0x0p+0");
    const p_idx = std.mem.indexOfScalar(u8, zig_hex, 'p') orelse return bufFallback(buf, zig_hex);
    if (zig_hex[p_idx + 1] == '-') return bufFallback(buf, zig_hex);
    return std.fmt.bufPrint(buf, "{s}+{s}", .{ zig_hex[0 .. p_idx + 1], zig_hex[p_idx + 1 ..] }) catch bufFallback(buf, zig_hex);
}

test "formatMiraShowNum matches shownum's \".0\"-suffix rule" {
    var buf: [64]u8 = undefined;
    try std.testing.expectEqualStrings("2.0", formatMiraShowNum(&buf, 2.0));
    try std.testing.expectEqualStrings("12.34", formatMiraShowNum(&buf, 12.34));
    try std.testing.expectEqualStrings("0.3333333333333333", formatMiraShowNum(&buf, 1.0 / 3.0));
    try std.testing.expectEqualStrings("-12.5", formatMiraShowNum(&buf, -12.5));
    try std.testing.expectEqualStrings("0.0", formatMiraShowNum(&buf, 0.0));
}

test "formatMiraFixed matches a fixed decimal-places count" {
    var buf: [64]u8 = undefined;
    try std.testing.expectEqualStrings("3.142", formatMiraFixed(&buf, 3, 3.14159265358979));
    try std.testing.expectEqualStrings("3", formatMiraFixed(&buf, 0, 3.14159265358979));
    try std.testing.expectEqualStrings("3.14159", formatMiraFixed(&buf, 5, 3.14159265358979));
}

test "formatMiraScaled produces a C-style signed, zero-padded exponent" {
    var buf: [64]u8 = undefined;
    try std.testing.expectEqualStrings("1.235e+05", formatMiraScaled(&buf, 3, 123456.789));
    try std.testing.expectEqualStrings("1.234e-04", formatMiraScaled(&buf, 3, 0.0001234));
    try std.testing.expectEqualStrings("1.000e+00", formatMiraScaled(&buf, 3, 1.0));
    try std.testing.expectEqualStrings("-5.50e+00", formatMiraScaled(&buf, 2, -5.5));
}

test "formatMiraHex matches the manual's showhex pi example" {
    var buf: [64]u8 = undefined;
    try std.testing.expectEqualStrings("0x1.921fb54442d18p+1", formatMiraHex(&buf, std.math.pi));
    try std.testing.expectEqualStrings("0x1p+0", formatMiraHex(&buf, 1.0));
    try std.testing.expectEqualStrings("0x1p-1", formatMiraHex(&buf, 0.5));
}
