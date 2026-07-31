//! Dependency-neutral byte and record vocabulary for the `.x` object format.
//! This file intentionally imports only the standard library. Graph allocation,
//! name lookup, aliases, and module reconstruction belong in `dump_load.zig`.

const std = @import("std");

pub const version: u8 = 83;
pub const word_bits: u8 = 64;
pub const word_bytes: usize = word_bits / 8;
pub const definition_end: u8 = 202;
pub const integer_end: i32 = -1;

pub const Error = error{
    Truncated,
    WrongVersion,
    WrongWordSize,
    InvalidTag,
    MissingTerminator,
    TrailingBytes,
};

/// Wire markers. Values 0...190 and 207...255 encode atoms directly.
pub const Tag = enum(u8) {
    char = 191,
    short = 192,
    integer = 193,
    double = 194,
    identifier = 195,
    alias = 196,
    here = 197,
    constructor = 198,
    read_values = 199,
    pattern = 200,
    wide_pattern = 201,
    definition = 202,
    application = 203,
    cons = 204,
    type_variable = 205,
    unicode = 206,

    pub fn decode(byte: u8) Error!Tag {
        if (byte < @intFromEnum(Tag.char) or byte > @intFromEnum(Tag.unicode)) {
            return error.InvalidTag;
        }
        return @enumFromInt(byte);
    }
};

/// Runtime node tags are listed here so a target implementation does not have
/// to recover their stable numeric ABI from heap code.
pub const NodeTag = enum(u8) {
    atom = 0,
    double = 1,
    data_pair = 2,
    file_info = 3,
    type_variable = 4,
    integer = 5,
    constructor = 6,
    string_cons = 7,
    identifier = 8,
    application = 9,
    lambda = 10,
    cons = 11,
    tries = 12,
    label = 13,
    show = 14,
    start_read_values = 15,
    let = 16,
    letrec = 17,
    share = 18,
    lexer = 19,
    pair = 20,
    unicode = 21,
    type_cons = 22,
};

pub const Header = struct {
    pub const encoded_len = 2;

    pub fn encode(out: []u8) Error!void {
        if (out.len < encoded_len) return error.Truncated;
        out[0] = word_bits;
        out[1] = version;
    }

    pub fn decode(input: []const u8) Error!void {
        if (input.len < encoded_len) return error.Truncated;
        if (input[0] != word_bits) return error.WrongWordSize;
        if (input[1] != version) return error.WrongVersion;
    }
};

pub const Reader = struct {
    bytes: []const u8,
    pos: usize = 0,

    pub fn init(bytes: []const u8) Reader {
        return .{ .bytes = bytes };
    }

    pub fn remaining(self: Reader) usize {
        return self.bytes.len - self.pos;
    }

    pub fn finish(self: Reader) Error!void {
        if (self.remaining() != 0) return error.TrailingBytes;
    }

    pub fn readByte(self: *Reader) Error!u8 {
        if (self.pos == self.bytes.len) return error.Truncated;
        defer self.pos += 1;
        return self.bytes[self.pos];
    }

    pub fn readU16(self: *Reader) Error!u16 {
        const bytes = try self.take(2);
        return std.mem.readInt(u16, bytes[0..2], .little);
    }

    pub fn readI32(self: *Reader) Error!i32 {
        const bytes = try self.take(4);
        return std.mem.readInt(i32, bytes[0..4], .little);
    }

    pub fn readWord(self: *Reader) Error!i64 {
        const bytes = try self.take(word_bytes);
        return std.mem.readInt(i64, bytes[0..word_bytes], .little);
    }

    pub fn readDouble(self: *Reader) Error!f64 {
        const bits: u64 = @bitCast(try self.readWord());
        return @bitCast(bits);
    }

    /// Strings and paths are uninterpreted bytes terminated by NUL. UTF-8 is
    /// conventional but the wire format neither validates nor normalizes it.
    pub fn readZ(self: *Reader) Error![]const u8 {
        const start = self.pos;
        while (self.pos < self.bytes.len) : (self.pos += 1) {
            if (self.bytes[self.pos] == 0) {
                const value = self.bytes[start..self.pos];
                self.pos += 1;
                return value;
            }
        }
        return error.MissingTerminator;
    }

    fn take(self: *Reader, len: usize) Error![]const u8 {
        if (len > self.remaining()) return error.Truncated;
        defer self.pos += len;
        return self.bytes[self.pos..][0..len];
    }
};

pub const Writer = struct {
    bytes: []u8,
    pos: usize = 0,

    pub fn init(bytes: []u8) Writer {
        return .{ .bytes = bytes };
    }

    pub fn written(self: Writer) []const u8 {
        return self.bytes[0..self.pos];
    }

    pub fn writeByte(self: *Writer, value: u8) Error!void {
        const out = try self.take(1);
        out[0] = value;
    }

    pub fn writeU16(self: *Writer, value: u16) Error!void {
        const out = try self.take(2);
        std.mem.writeInt(u16, out[0..2], value, .little);
    }

    pub fn writeI32(self: *Writer, value: i32) Error!void {
        const out = try self.take(4);
        std.mem.writeInt(i32, out[0..4], value, .little);
    }

    pub fn writeWord(self: *Writer, value: i64) Error!void {
        const out = try self.take(word_bytes);
        std.mem.writeInt(i64, out[0..word_bytes], value, .little);
    }

    pub fn writeDouble(self: *Writer, value: f64) Error!void {
        const bits: u64 = @bitCast(value);
        try self.writeWord(@bitCast(bits));
    }

    pub fn writeZ(self: *Writer, value: []const u8) Error!void {
        const out = try self.take(value.len + 1);
        @memcpy(out[0..value.len], value);
        out[value.len] = 0;
    }

    fn take(self: *Writer, len: usize) Error![]u8 {
        if (len > self.bytes.len - self.pos) return error.Truncated;
        defer self.pos += len;
        return self.bytes[self.pos..][0..len];
    }
};

/// A typed, allocation-free record returned above the byte-reader layer.
/// Composite graph records are postfix operations; reconstruction owns the
/// value stack and assigns identity when a value is first pushed.
pub const Record = union(enum) {
    atom: u16,
    char: u8,
    short: i8,
    integer_digit: i32,
    double: f64,
    identifier: []const u8,
    alias: []const u8,
    here: struct { path: []const u8, line: u16 },
    constructor: u16,
    read_values,
    pattern: u16,
    definition,
    application,
    cons,
    type_variable: u8,
    unicode: u32,
};

/// Reconstruction boundary implemented by the heap/compiler layer. Repeated
/// references are preserved by IDs owned by that layer, never native pointers.
pub const Reconstructor = struct {
    context: *anyopaque,
    apply_record: *const fn (*anyopaque, Record) anyerror!void,

    pub fn apply(self: Reconstructor, record: Record) !void {
        try self.apply_record(self.context, record);
    }
};

test "canonical scalar encodings are little endian and host independent" {
    var storage: [32]u8 = undefined;
    var writer = Writer.init(&storage);
    try writer.writeWord(-2);
    try writer.writeI32(-0x1020304);
    try writer.writeDouble(-0.0);
    try std.testing.expectEqualSlices(u8, &.{
        0xfe, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
        0xfc, 0xfc, 0xfd, 0xfe, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x80,
    }, writer.written());

    var reader = Reader.init(writer.written());
    try std.testing.expectEqual(@as(i64, -2), try reader.readWord());
    try std.testing.expectEqual(@as(i32, -0x1020304), try reader.readI32());
    try std.testing.expectEqual(@as(u64, 0x8000000000000000), @as(u64, @bitCast(try reader.readDouble())));
    try reader.finish();
}

test "headers, terminated bytes, truncation, and trailing bytes fail closed" {
    var header: [2]u8 = undefined;
    try Header.encode(&header);
    try Header.decode(&header);
    try std.testing.expectError(error.Truncated, Header.decode(header[0..1]));
    try std.testing.expectError(error.WrongWordSize, Header.decode(&.{ 32, version }));
    try std.testing.expectError(error.WrongVersion, Header.decode(&.{ word_bits, version + 1 }));

    var reader = Reader.init("λ/mira\x00x");
    try std.testing.expectEqualStrings("λ/mira", try reader.readZ());
    try std.testing.expectError(error.TrailingBytes, reader.finish());
    var unterminated = Reader.init("mira");
    try std.testing.expectError(error.MissingTerminator, unterminated.readZ());
    var short = Reader.init(&.{ 1, 2, 3 });
    try std.testing.expectError(error.Truncated, short.readI32());
}

test "wire and node tag ranges are exhaustive and stable" {
    inline for (std.meta.fields(Tag), 0..) |field, index| {
        try std.testing.expectEqual(@as(u8, 191 + index), @intFromEnum(@field(Tag, field.name)));
    }
    inline for (std.meta.fields(NodeTag), 0..) |field, index| {
        try std.testing.expectEqual(@as(u8, index), @intFromEnum(@field(NodeTag, field.name)));
    }
    try std.testing.expectError(error.InvalidTag, Tag.decode(190));
    try std.testing.expectError(error.InvalidTag, Tag.decode(207));
}
