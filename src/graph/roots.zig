//! Explicit off-heap graph roots.
//!
//! A root registration records the address of a `Word` (or a slice of Words)
//! whose contents must survive graph collection. Registrations are scoped and
//! strictly LIFO, matching nested/reentrant interpreter calls without relying
//! on the location or direction of the native stack.

const std = @import("std");

const Word = i64;

const Entry = union(enum) {
    one: *const Word,
    many: []const Word,
    list: *const std.ArrayListUnmanaged(Word),
};

pub const Registry = struct {
    entries: std.ArrayListUnmanaged(Entry) = .empty,

    pub fn root(self: *Registry, allocator: std.mem.Allocator, value: *const Word) Guard {
        self.entries.append(allocator, .{ .one = value }) catch @panic("unable to register GC root");
        return .{ .registry = self, .allocator = allocator, .depth = self.entries.items.len };
    }

    pub fn rootSlice(self: *Registry, allocator: std.mem.Allocator, values: []const Word) Guard {
        self.entries.append(allocator, .{ .many = values }) catch @panic("unable to register GC roots");
        return .{ .registry = self, .allocator = allocator, .depth = self.entries.items.len };
    }

    pub fn rootList(self: *Registry, allocator: std.mem.Allocator, values: *const std.ArrayListUnmanaged(Word)) Guard {
        self.entries.append(allocator, .{ .list = values }) catch @panic("unable to register GC root list");
        return .{ .registry = self, .allocator = allocator, .depth = self.entries.items.len };
    }

    pub fn markAll(self: *const Registry, mark_fn: *const fn (Word) void) void {
        for (self.entries.items) |entry| switch (entry) {
            .one => |value| mark_fn(value.*),
            .many => |values| for (values) |value| mark_fn(value),
            .list => |values| for (values.items) |value| mark_fn(value),
        };
    }

    pub fn reset(self: *Registry, allocator: std.mem.Allocator) void {
        std.debug.assert(self.entries.items.len == 0);
        self.entries.deinit(allocator);
        self.* = .{};
    }
};

pub const Guard = struct {
    registry: *Registry,
    allocator: std.mem.Allocator,
    depth: usize,
    active: bool = true,

    pub fn deinit(self: *Guard) void {
        if (!self.active) return;
        std.debug.assert(self.registry.entries.items.len == self.depth);
        _ = self.registry.entries.pop();
        self.active = false;
        _ = self.allocator;
    }
};

test "scoped roots support values, slices, nesting, and safe unregistering" {
    var registry: Registry = .{};
    defer registry.reset(std.testing.allocator);

    var one: Word = 11;
    const many = [_]Word{ 22, 33 };
    var outer = registry.root(std.testing.allocator, &one);
    defer outer.deinit();
    {
        var inner = registry.rootSlice(std.testing.allocator, &many);
        defer inner.deinit();
        try std.testing.expectEqual(@as(usize, 2), registry.entries.items.len);
    }
    try std.testing.expectEqual(@as(usize, 1), registry.entries.items.len);
}
