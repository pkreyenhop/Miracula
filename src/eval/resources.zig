//! Interpreter-owned opaque resource handles.
//!
//! Graph values may contain a `StreamID`'s numeric representation, but never a
//! native pointer. The table owns pointer resolution and stream lifetime.

const std = @import("std");

pub const StreamID = enum(u64) {
    invalid = 0,
    _,

    pub fn fromWord(word: i64) ResourceError!StreamID {
        if (word <= 0) return error.MissingResource;
        return @enumFromInt(@as(u64, @intCast(word)));
    }

    pub fn toWord(self: StreamID) i64 {
        return @intCast(@intFromEnum(self));
    }
};

pub const ResourceError = error{
    MissingResource,
    ClosedResource,
    WrongResourceKind,
    ResourceIdOverflow,
};

const Resource = union(enum) {
    stream: *anyopaque,
    test_resource: void,
};

const Entry = struct {
    id: u64,
    resource: Resource,
    open: bool = true,
    close_on_release: bool,
    close_fn: ?*const fn (*anyopaque) void,
};

pub const Checkpoint = struct {
    entry_count: usize,
};

pub const ResourceTable = struct {
    entries: std.ArrayListUnmanaged(Entry) = .empty,
    next_id: u64 = 1,

    pub fn registerStream(
        self: *ResourceTable,
        allocator: std.mem.Allocator,
        value: anytype,
        close_on_release: bool,
        close_fn: ?*const fn (*anyopaque) void,
    ) (std.mem.Allocator.Error || ResourceError)!StreamID {
        const id = try self.allocateID();
        try self.entries.append(allocator, .{
            .id = id,
            .resource = .{ .stream = @ptrCast(value) },
            .close_on_release = close_on_release,
            .close_fn = close_fn,
        });
        return @enumFromInt(id);
    }

    pub fn resolveStream(
        self: *ResourceTable,
        comptime Pointer: type,
        id: StreamID,
    ) ResourceError!Pointer {
        const entry = self.find(@intFromEnum(id)) orelse return error.MissingResource;
        if (!entry.open) return error.ClosedResource;
        return switch (entry.resource) {
            .stream => |value| @ptrCast(@alignCast(value)),
            .test_resource => error.WrongResourceKind,
        };
    }

    pub fn closeStream(self: *ResourceTable, id: StreamID) ResourceError!void {
        const entry = self.find(@intFromEnum(id)) orelse return error.MissingResource;
        if (!entry.open) return error.ClosedResource;
        switch (entry.resource) {
            .stream => |value| if (entry.close_on_release) {
                if (entry.close_fn) |close_fn| close_fn(value);
            },
            .test_resource => return error.WrongResourceKind,
        }
        entry.open = false;
    }

    pub fn checkpoint(self: *const ResourceTable) Checkpoint {
        return .{ .entry_count = self.entries.items.len };
    }

    pub fn restore(self: *ResourceTable, checkpoint_value: Checkpoint) void {
        if (checkpoint_value.entry_count > self.entries.items.len) return;
        for (self.entries.items[checkpoint_value.entry_count..]) |*entry| {
            self.closeEntry(entry);
        }
    }

    pub fn reset(self: *ResourceTable, allocator: std.mem.Allocator) void {
        for (self.entries.items) |*entry| self.closeEntry(entry);
        self.entries.deinit(allocator);
        const next_id = self.next_id;
        self.* = .{ .next_id = next_id };
    }

    fn closeEntry(self: *ResourceTable, entry: *Entry) void {
        _ = self;
        if (!entry.open) return;
        switch (entry.resource) {
            .stream => |value| if (entry.close_on_release) {
                if (entry.close_fn) |close_fn| close_fn(value);
            },
            .test_resource => {},
        }
        entry.open = false;
    }

    fn allocateID(self: *ResourceTable) ResourceError!u64 {
        if (self.next_id == 0 or self.next_id > std.math.maxInt(i64)) {
            return error.ResourceIdOverflow;
        }
        const result = self.next_id;
        self.next_id += 1;
        return result;
    }

    fn find(self: *ResourceTable, id: u64) ?*Entry {
        for (self.entries.items) |*entry| {
            if (entry.id == id) return entry;
        }
        return null;
    }

    fn registerTestResource(
        self: *ResourceTable,
        allocator: std.mem.Allocator,
    ) (std.mem.Allocator.Error || ResourceError)!StreamID {
        const id = try self.allocateID();
        try self.entries.append(allocator, .{
            .id = id,
            .resource = .{ .test_resource = {} },
            .close_on_release = false,
            .close_fn = null,
        });
        return @enumFromInt(id);
    }
};

pub inline fn table() *ResourceTable {
    return &@import("stream.zig").fio().resources;
}

pub fn closeNativeStream(value: *anyopaque) void {
    const stream = @import("stream.zig");
    _ = stream.fclose(@as(*stream.Stream, @ptrCast(@alignCast(value))));
}

test "resource table distinguishes missing, closed, and wrong-kind IDs" {
    var registry: ResourceTable = .{};
    defer registry.reset(std.testing.allocator);
    var value: u8 = 1;
    const id = try registry.registerStream(std.testing.allocator, &value, false, null);
    try std.testing.expectEqual(&value, try registry.resolveStream(*u8, id));
    try registry.closeStream(id);
    try std.testing.expectError(error.ClosedResource, registry.resolveStream(*u8, id));
    try std.testing.expectError(error.ClosedResource, registry.closeStream(id));
    try std.testing.expectError(
        error.MissingResource,
        registry.resolveStream(*u8, @enumFromInt(9999)),
    );
    const wrong = try registry.registerTestResource(std.testing.allocator);
    try std.testing.expectError(error.WrongResourceKind, registry.resolveStream(*u8, wrong));
}

test "checkpoint restore closes only resources created after checkpoint" {
    var registry: ResourceTable = .{};
    defer registry.reset(std.testing.allocator);
    var first: u8 = 1;
    var second: u8 = 2;
    const first_id = try registry.registerStream(std.testing.allocator, &first, false, null);
    const checkpoint_value = registry.checkpoint();
    const second_id = try registry.registerStream(std.testing.allocator, &second, false, null);
    registry.restore(checkpoint_value);
    try std.testing.expectEqual(&first, try registry.resolveStream(*u8, first_id));
    try std.testing.expectError(error.ClosedResource, registry.resolveStream(*u8, second_id));
}

test "reset invalidates IDs without reusing them in the table lifetime" {
    var registry: ResourceTable = .{};
    var value: u8 = 1;
    const id = try registry.registerStream(std.testing.allocator, &value, false, null);
    registry.reset(std.testing.allocator);
    try std.testing.expectError(error.MissingResource, registry.resolveStream(*u8, id));
    const replacement = try registry.registerStream(std.testing.allocator, &value, false, null);
    defer registry.reset(std.testing.allocator);
    try std.testing.expect(id != replacement);
    try std.testing.expectError(error.MissingResource, registry.resolveStream(*u8, id));
}
