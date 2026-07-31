//! Concrete parsers replacing the former general-purpose scanf emulation.
//! Inputs are slices or `Stream` values; results report consumption explicitly.

const std = @import("std");
const Stream = @import("../eval/stream.zig").Stream;

pub const Error = error{
    Empty,
    Invalid,
    Overflow,
    TokenTooLong,
};

pub fn IntegerResult(comptime T: type) type {
    return struct {
        value: T,
        consumed: usize,
    };
}

/// Parse the longest decimal integer prefix after leading ASCII whitespace.
/// A successful conversion may leave a malformed suffix, matching the former
/// `%ld`/`%u` call sites; callers that require the whole field use `integer`.
pub fn integerPrefix(comptime T: type, input: []const u8) Error!IntegerResult(T) {
    var index: usize = 0;
    while (index < input.len and std.ascii.isWhitespace(input[index])) : (index += 1) {}
    const start = index;
    if (index < input.len and (input[index] == '+' or input[index] == '-')) index += 1;
    const digits = index;
    while (index < input.len and std.ascii.isDigit(input[index])) : (index += 1) {}
    if (index == digits) return if (start == input.len) error.Empty else error.Invalid;
    const value = std.fmt.parseInt(T, input[start..index], 10) catch |err| switch (err) {
        error.Overflow => return error.Overflow,
        else => return error.Invalid,
    };
    return .{ .value = value, .consumed = index };
}

/// Parse one complete integer token, permitting surrounding whitespace.
pub fn integer(comptime T: type, input: []const u8) Error!T {
    const parsed = try integerPrefix(T, input);
    var end = parsed.consumed;
    while (end < input.len and std.ascii.isWhitespace(input[end])) : (end += 1) {}
    if (end != input.len) return error.Invalid;
    return parsed.value;
}

/// Parse a complete integer token with optional sign and `0x`/`0o` prefix.
pub fn integerAuto(comptime T: type, input: []const u8) Error!T {
    var start: usize = 0;
    while (start < input.len and std.ascii.isWhitespace(input[start])) : (start += 1) {}
    var end = input.len;
    while (end > start and std.ascii.isWhitespace(input[end - 1])) : (end -= 1) {}
    if (start == end) return error.Empty;

    var prefix = start;
    if (input[prefix] == '+' or input[prefix] == '-') prefix += 1;
    var base: u8 = 10;
    if (prefix + 2 <= end and input[prefix] == '0') {
        switch (std.ascii.toLower(input[prefix + 1])) {
            'x' => base = 16,
            'o' => base = 8,
            else => {},
        }
    }
    var normalized: [128]u8 = undefined;
    if (end - start > normalized.len) return error.Overflow;
    var len: usize = 0;
    if (input[start] == '+' or input[start] == '-') {
        normalized[len] = input[start];
        len += 1;
    }
    const digits_start = if (base == 10) prefix else prefix + 2;
    if (digits_start == end) return error.Invalid;
    @memcpy(normalized[len..][0 .. end - digits_start], input[digits_start..end]);
    len += end - digits_start;
    return std.fmt.parseInt(T, normalized[0..len], base) catch |err| switch (err) {
        error.Overflow => error.Overflow,
        else => error.Invalid,
    };
}

/// Parse a decimal floating-point value after leading whitespace. The complete
/// remaining slice must belong to the number; trailing whitespace is rejected
/// to preserve the former `%lf%c` validation.
pub fn float(input: []const u8) Error!f64 {
    var start: usize = 0;
    while (start < input.len and std.ascii.isWhitespace(input[start])) : (start += 1) {}
    if (start == input.len) return error.Empty;
    return std.fmt.parseFloat(f64, input[start..]) catch |err| switch (err) {
        error.InvalidCharacter => error.Invalid,
    };
}

/// Read the next whitespace-delimited token. Returns null only when EOF occurs
/// before any non-whitespace byte.
pub fn readToken(stream: *Stream, buffer: []u8) Error!?[]const u8 {
    var len: usize = 0;
    while (true) {
        const byte = stream.readByte() catch |err| switch (err) {
            error.EndOfStream => return null,
            else => return error.Invalid,
        };
        if (!std.ascii.isWhitespace(byte)) {
            if (buffer.len == 0) return error.TokenTooLong;
            buffer[0] = byte;
            len = 1;
            break;
        }
    }
    while (true) {
        const byte = stream.readByte() catch |err| switch (err) {
            error.EndOfStream => return buffer[0..len],
            else => return error.Invalid,
        };
        if (std.ascii.isWhitespace(byte)) return buffer[0..len];
        if (len == buffer.len) return error.TokenTooLong;
        buffer[len] = byte;
        len += 1;
    }
}

pub fn readInteger(comptime T: type, stream: *Stream, buffer: []u8) Error!?T {
    const token = try readToken(stream, buffer) orelse return null;
    return try integer(T, token);
}

test "integer parsing covers whitespace, signs, suffixes, width, and overflow" {
    try std.testing.expectError(error.Empty, integer(i64, ""));
    try std.testing.expectEqual(@as(i64, -42), try integer(i64, " \t-42\n"));
    try std.testing.expectEqual(@as(i64, 42), try integer(i64, "+42"));
    try std.testing.expectError(error.Invalid, integer(i64, "42x"));
    const partial = try integerPrefix(i64, "42x");
    try std.testing.expectEqual(@as(i64, 42), partial.value);
    try std.testing.expectEqual(@as(usize, 2), partial.consumed);
    try std.testing.expectError(error.Invalid, integer(i64, "0x10"));
    try std.testing.expectEqual(@as(i64, 16), try integerAuto(i64, "0x10"));
    try std.testing.expectEqual(@as(i64, -8), try integerAuto(i64, "-0o10"));
    try std.testing.expectError(error.Overflow, integer(u8, "256"));
    try std.testing.expectEqual(std.math.maxInt(i64), try integer(i64, "9223372036854775807"));
    try std.testing.expectError(error.Overflow, integer(i64, "9223372036854775808"));
}

test "float parsing covers exponent variants and strict suffix handling" {
    try std.testing.expectEqual(@as(f64, 1.0), try float("1"));
    try std.testing.expectEqual(@as(f64, -125.0), try float(" -1.25e+2"));
    try std.testing.expectEqual(@as(f64, 0.125), try float("1.25E-1"));
    try std.testing.expectError(error.Empty, float(""));
    try std.testing.expectError(error.Invalid, float("1e"));
    try std.testing.expectError(error.Invalid, float("1.0 "));
    try std.testing.expectError(error.Invalid, float("1.0junk"));
}

test "stream tokens define EOF, whitespace, width, and conversion counts" {
    var empty: Stream = .{ .mem_buf = "" };
    var buffer: [4]u8 = undefined;
    try std.testing.expect((try readToken(&empty, &buffer)) == null);

    var stream: Stream = .{ .mem_buf = " \t-7 12x 99999" };
    try std.testing.expectEqual(@as(?i32, -7), try readInteger(i32, &stream, &buffer));
    const partial = (try readToken(&stream, &buffer)).?;
    try std.testing.expectEqualStrings("12x", partial);
    try std.testing.expectError(error.Invalid, integer(i32, partial));
    try std.testing.expectError(error.TokenTooLong, readToken(&stream, &buffer));
}
