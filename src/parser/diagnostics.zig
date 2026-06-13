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
    list: std.array_list.Managed(Diagnostic),
    has_errors: bool = false,

    pub fn init(allocator: std.mem.Allocator) Diagnostics {
        return .{
            .allocator = allocator,
            .list = std.array_list.Managed(Diagnostic).init(allocator),
        };
    }

    pub fn deinit(self: *Diagnostics) void {
        for (self.list.items) |diag| {
            self.allocator.free(diag.message);
        }
        self.list.deinit();
    }

    pub fn add(self: *Diagnostics, severity: Severity, line: usize, column: usize, msg: []const u8) !void {
        const owned_msg = try self.allocator.dupe(u8, msg);
        try self.list.append(.{
            .severity = severity,
            .line = line,
            .column = column,
            .message = owned_msg,
        });
        if (severity == .@"error") {
            self.has_errors = true;
        }
    }

    pub fn addError(self: *Diagnostics, line: usize, column: usize, msg: []const u8) !void {
        try self.add(.@"error", line, column, msg);
    }

    pub fn addWarning(self: *Diagnostics, line: usize, column: usize, msg: []const u8) !void {
        try self.add(.warning, line, column, msg);
    }

    pub fn addNote(self: *Diagnostics, line: usize, column: usize, msg: []const u8) !void {
        try self.add(.note, line, column, msg);
    }
};
