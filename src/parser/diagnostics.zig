//! diagnostics.zig — a collector for parser/compiler messages.
//!
//! `Diagnostics` accumulates `error`/`warning`/`note` entries with source
//! positions for the new Zig parser pipeline to report.

const std = @import("std");

pub const Severity = enum {
    @"error",
    warning,
    note,
};

pub const Diagnostic = struct {
    severity: Severity,
    line: usize,
    column: usize,
    message: []const u8,
};

pub const Diagnostics = struct {
    allocator: std.mem.Allocator,
    list: std.ArrayList(Diagnostic),
    has_errors: bool = false,

    /// Create an empty diagnostics collector backed by `allocator`.
    pub fn init(allocator: std.mem.Allocator) Diagnostics {
        return .{
            .allocator = allocator,
            .list = .empty,
        };
    }

    /// Free the collected diagnostics and their messages.
    pub fn deinit(self: *Diagnostics) void {
        for (self.list.items) |diag| {
            self.allocator.free(diag.message);
        }
        self.list.deinit(self.allocator);
    }

    /// Append a diagnostic of `severity` at `line:column` with message `msg`.
    pub fn add(self: *Diagnostics, severity: Severity, line: usize, column: usize, msg: []const u8) !void {
        const owned_msg = try self.allocator.dupe(u8, msg);
        try self.list.append(self.allocator, .{
            .severity = severity,
            .line = line,
            .column = column,
            .message = owned_msg,
        });
        if (severity == .@"error") {
            self.has_errors = true;
        }
    }

    /// Append an error diagnostic at `line:column`.
    pub fn addError(self: *Diagnostics, line: usize, column: usize, msg: []const u8) !void {
        try self.add(.@"error", line, column, msg);
    }

    /// Append a warning diagnostic at `line:column`.
    pub fn addWarning(self: *Diagnostics, line: usize, column: usize, msg: []const u8) !void {
        try self.add(.warning, line, column, msg);
    }

    /// Append a note diagnostic at `line:column`.
    pub fn addNote(self: *Diagnostics, line: usize, column: usize, msg: []const u8) !void {
        try self.add(.note, line, column, msg);
    }
};

test "Diagnostics: collects entries and only errors set has_errors" {
    var d = Diagnostics.init(std.testing.allocator);
    defer d.deinit();
    try std.testing.expect(!d.has_errors);

    try d.addWarning(1, 2, "watch out");
    try std.testing.expect(!d.has_errors); // a warning does not flag errors

    try d.addError(3, 4, "boom");
    try std.testing.expect(d.has_errors);

    try d.addNote(5, 6, "fyi");
    try std.testing.expectEqual(@as(usize, 3), d.list.items.len);
    try std.testing.expectEqual(Severity.@"error", d.list.items[1].severity);
    try std.testing.expectEqual(@as(usize, 3), d.list.items[1].line);
    try std.testing.expectEqualStrings("boom", d.list.items[1].message);
}
