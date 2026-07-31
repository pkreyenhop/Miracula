//! Language-neutral semantic handle vocabulary.
//!
//! These types are the authoritative mapping used by the automated Go port.
//! Their integer representation is deliberately explicit, but distinct enum
//! types prevent accidental interchange inside the implementation.

const std = @import("std");

pub const ImmediateByte = enum(u8) {
    _,
};

pub const StringID = enum(u32) {
    none = 0,
    _,

    pub fn fromStored(raw: i64) ?StringID {
        if (raw >= 0) return if (raw == 0) .none else null;
        return @enumFromInt(@as(u32, @intCast(-raw)));
    }

    pub fn toStored(self: StringID) i64 {
        const raw: i64 = @intCast(@intFromEnum(self));
        return if (raw == 0) 0 else -raw;
    }
};

pub const ProcessID = enum(i32) {
    invalid = -1,
    _,
};

pub const ProcessStatus = packed struct {
    raw: i32,

    pub fn exited(self: ProcessStatus) i32 {
        return (self.raw >> 8) & 0xff;
    }
};

pub const SourceID = enum(u32) {
    none = 0,
    _,
};

pub const FileID = enum(u32) {
    none = 0,
    _,
};

pub const ModuleID = enum(u32) {
    none = 0,
    _,
};

pub const Count = enum(u64) {
    _,
};

pub const Index = enum(u64) {
    _,
};

pub const SourceOffset = enum(u64) {
    _,
};

/// Exact signed word stored by the `.x` codec. It must never be interpreted
/// without an explicit typed constructor at the codec boundary.
pub const RawDumpWord = packed struct {
    bits: i64,
};

test "semantic IDs cannot be implicitly interchanged and preserve wire values" {
    const string_id: StringID = @enumFromInt(7);
    try std.testing.expectEqual(@as(i64, -7), string_id.toStored());
    try std.testing.expectEqual(string_id, StringID.fromStored(-7).?);
    try std.testing.expectEqual(StringID.none, StringID.fromStored(0).?);
    try std.testing.expect(StringID.fromStored(7) == null);
    try std.testing.expect(@TypeOf(@as(FileID, .none)) != @TypeOf(@as(ModuleID, .none)));
}
