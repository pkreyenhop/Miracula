const std = @import("std");

const max_selection = 4096;

const Driver = struct {
    allocator: std.mem.Allocator,
    viewer: []const u8,
    menuviewer: []const u8,
    fastback: bool,
    next: std.ArrayListUnmanaged(u8) = .{},
    last: std.ArrayListUnmanaged(u8) = .{},
    last_stack: std.ArrayListUnmanaged([]u8) = .{},
    shell_command: std.ArrayListUnmanaged(u8) = .{},

    fn init(allocator: std.mem.Allocator) !Driver {
        var driver = Driver{
            .allocator = allocator,
            .viewer = std.posix.getenv("VIEWER") orelse "less",
            .menuviewer = std.posix.getenv("MENUVIEWER") orelse "cat",
            .fastback = true,
        };
        if (std.posix.getenv("RETURNTOMENU")) |value| {
            driver.fastback = value.len == 0 or (value[0] != 'N' and value[0] != 'n');
        }
        try driver.last.append(allocator, '.');
        return driver;
    }

    fn deinit(self: *Driver) void {
        self.next.deinit(self.allocator);
        self.last.deinit(self.allocator);
        for (self.last_stack.items) |item| {
            self.allocator.free(item);
        }
        self.last_stack.deinit(self.allocator);
        self.shell_command.deinit(self.allocator);
    }

    fn drive(self: *Driver, dir: []const u8) !void {
        std.posix.chdir(dir) catch {
            try self.singleton(dir);
            return;
        };

        var bad = false;
        while (std.fs.cwd().statFile("contents")) |_| {
            if (self.next.items.len == 0 or bad) {
                try clearScreen();
                if (bad) {
                    if (std.mem.eql(u8, self.next.items, ".")) {
                        try std.io.getStdOut().writeAll("no previous selection to substitute for \".\"\n");
                    } else {
                        std.debug.print("selection \"{s}\" not valid\n", .{self.next.items});
                    }
                    bad = false;
                }

                try self.runViewer(self.menuviewer, "contents");
                try std.io.getStdOut().writeAll("::please type selection number (or return to exit):");
                try self.readSelection();
            }

            if (self.next.items.len == 0) {
                std.posix.chdir("..") catch {};
                try self.popLast();
                continue;
            }

            if (std.mem.eql(u8, self.next.items, ".")) {
                try self.setNext(self.last.items);
            }
            if (std.mem.eql(u8, self.next.items, "+")) {
                if (try self.lastVal()) |value| {
                    try self.setNextFmt("{d}", .{value + 1});
                }
            }
            if (std.mem.eql(u8, self.next.items, "-")) {
                if (try self.lastVal()) |value| {
                    try self.setNextFmt("{d}", .{value - 1});
                }
            }

            const stat = std.fs.cwd().statFile(self.next.items) catch {
                try self.handleSpecialOrBad(&bad);
                continue;
            };

            if (std.mem.eql(u8, self.next.items, ".") or
                std.mem.eql(u8, self.next.items, "..") or
                std.mem.indexOfScalar(u8, self.next.items, '/') != null)
            {
                bad = true;
                continue;
            }

            switch (stat.kind) {
                .directory => {
                    var cwd_buffer: [std.fs.max_path_bytes]u8 = undefined;
                    const hold = std.posix.getcwd(&cwd_buffer) catch {
                        std.debug.print("panic: cwd too long\n", .{});
                        std.process.exit(1);
                    };
                    if (std.posix.chdir(self.next.items)) |_| {
                        if (std.fs.cwd().statFile("contents")) |_| {
                            try self.setLast(self.next.items);
                            try self.pushLast();
                            self.next.clearRetainingCapacity();
                        } else |_| {
                            bad = true;
                            std.posix.chdir(hold) catch {};
                        }
                    } else |_| {
                        bad = true;
                        std.posix.chdir(hold) catch {};
                    }
                },
                .file => try self.showFile(self.next.items, stat.mode),
                else => bad = true,
            }
        } else |_| {}
    }

    fn singleton(self: *Driver, path: []const u8) !void {
        const stat = std.fs.cwd().statFile(path) catch {
            std.debug.print("menudriver: cannot access \"{s}\"\n", .{path});
            std.process.exit(1);
        };
        if (stat.kind != .file) {
            std.debug.print("menudriver: cannot access \"{s}\"\n", .{path});
            std.process.exit(1);
        }

        try clearScreen();
        if (isOwnerExecutable(stat.mode)) {
            try runExecutable(self.allocator, path);
            self.fastback = false;
        } else {
            try self.runViewer(self.viewer, path);
        }
        if (!self.fastback) {
            try waitForReturn();
        }
        std.process.exit(0);
    }

    fn showFile(self: *Driver, path: []const u8, mode: usize) !void {
        try clearScreen();
        if (isOwnerExecutable(mode)) {
            try runExecutable(self.allocator, path);
            if (self.fastback) {
                try waitForReturn();
            }
        } else {
            try self.runViewer(self.viewer, path);
        }

        try self.setLast(path);
        if (self.fastback) {
            self.next.clearRetainingCapacity();
            return;
        }

        try std.io.getStdOut().writeAll("::next selection (or return to go back to menu, or q to quit):");
        try self.readSelection();
    }

    fn handleSpecialOrBad(self: *Driver, bad: *bool) !void {
        if (std.mem.eql(u8, self.next.items, "???")) {
            try self.settings();
            try waitForReturn();
            self.next.clearRetainingCapacity();
        } else if (std.mem.eql(u8, self.next.items, "q") or std.mem.eql(u8, self.next.items, "/q")) {
            std.process.exit(0);
        } else if (self.next.items.len > 0 and self.next.items[0] == '!') {
            try self.shellEscape();
            try waitForReturn();
            self.next.clearRetainingCapacity();
        } else {
            bad.* = true;
        }
    }

    fn settings(self: *Driver) !void {
        const stdout = std.io.getStdOut();
        try stdout.writeAll("current values of menudriver internal variables are\n\n");
        try stdout.writeAll("        VIEWER=");
        try stdout.writeAll(self.viewer);
        try stdout.writeAll("\n        MENUVIEWER=");
        try stdout.writeAll(self.menuviewer);
        try stdout.writeAll("\n        RETURNTOMENU=");
        try stdout.writeAll(if (self.fastback) "YES" else "NO");
        try stdout.writeAll(
            "\n\nThese can be modified by setting environment variables of the same names\n\n" ++
                "VIEWER is the program used to display individual sections\n\n" ++
                "MENUVIEWER is the program used to display contents pages\n\n" ++
                "RETURNTOMENU=NO/YES  causes  a second prompt to be given/not given after\n" ++
                "displaying section (ie before returning to contents page).  It should be\n" ++
                "`YES' if VIEWER is a program that pauses for input at end  of  file,  or\n" ++
                "`NO' if VIEWER is a program that quits silently at end of file.\n\n",
        );
    }

    fn shellEscape(self: *Driver) !void {
        if (self.next.items.len == 1 or (self.next.items.len >= 2 and self.next.items[1] == '!')) {
            if (self.shell_command.items.len > 0) {
                if (self.next.items.len >= 2 and self.next.items[1] == '!') {
                    try self.shell_command.appendSlice(self.allocator, self.next.items[2..]);
                }
                std.debug.print("!{s}\n", .{self.shell_command.items});
            } else {
                try std.io.getStdOut().writeAll("no previous shell command to substitute for \"!\"\n");
            }
        } else {
            self.shell_command.clearRetainingCapacity();
            try self.shell_command.appendSlice(self.allocator, self.next.items[1..]);
        }
        if (self.shell_command.items.len > 0) {
            try runShell(self.allocator, self.shell_command.items);
        }
    }

    fn readSelection(self: *Driver) !void {
        var buffer: [max_selection]u8 = undefined;
        var len: usize = 0;
        var byte: [1]u8 = undefined;
        var saw_nonleading = false;
        while (true) {
            const read = try std.io.getStdIn().read(&byte);
            if (read == 0) std.process.exit(0);
            if (byte[0] == '\n') break;
            if (!saw_nonleading and (byte[0] == ' ' or byte[0] == '\t')) continue;
            saw_nonleading = true;
            if (len < buffer.len) {
                buffer[len] = byte[0];
                len += 1;
            }
        }

        var selection: []const u8 = buffer[0..len];
        if (selection.len == 0 or selection[0] != '!') {
            selection = std.mem.trimRight(u8, selection, " \t");
        }
        try self.setNext(selection);
    }

    fn lastVal(self: *Driver) !?i32 {
        if (std.mem.eql(u8, self.last.items, ".") and self.last_stack.items.len > 0) {
            try self.popLast();
            const parsed = std.fmt.parseInt(i32, self.last.items, 10) catch {
                try self.pushLast();
                return null;
            };
            std.posix.chdir("..") catch {};
            return parsed;
        }
        return std.fmt.parseInt(i32, self.last.items, 10) catch null;
    }

    fn pushLast(self: *Driver) !void {
        if (self.last.items.len > 0 and self.last.items[0] == '.') {
            if (self.last.items.len == 1) return;
            if (std.mem.eql(u8, self.last.items, "..")) {
                try self.popLast();
                return;
            }
        }
        const saved = try self.allocator.dupe(u8, self.last.items);
        try self.last_stack.append(self.allocator, saved);
        try self.setLast(".");
    }

    fn popLast(self: *Driver) !void {
        if (self.last_stack.items.len == 0) return;
        const saved = self.last_stack.pop().?;
        defer self.allocator.free(saved);
        try self.setLast(saved);
    }

    fn runViewer(self: *Driver, command: []const u8, path: []const u8) !void {
        const quoted = try shellQuote(self.allocator, path);
        defer self.allocator.free(quoted);
        const full = try std.fmt.allocPrint(self.allocator, "{s} {s}", .{ command, quoted });
        defer self.allocator.free(full);
        try runShell(self.allocator, full);
    }

    fn setNext(self: *Driver, value: []const u8) !void {
        self.next.clearRetainingCapacity();
        try self.next.appendSlice(self.allocator, value);
    }

    fn setNextFmt(self: *Driver, comptime fmt: []const u8, args: anytype) !void {
        self.next.clearRetainingCapacity();
        try self.next.writer(self.allocator).print(fmt, args);
    }

    fn setLast(self: *Driver, value: []const u8) !void {
        self.last.clearRetainingCapacity();
        try self.last.appendSlice(self.allocator, value);
    }
};

pub fn main() !void {
    var gpa: std.heap.DebugAllocator(.{}) = .init;
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);
    if (args.len > 2) {
        std.debug.print("menudriver: wrong number of args\n", .{});
        std.process.exit(1);
    }

    var driver = try Driver.init(allocator);
    defer driver.deinit();
    try driver.drive(if (args.len == 1) "." else args[1]);
}

fn clearScreen() !void {
    const stdout = std.io.getStdOut();
    try stdout.writeAll("\x1b[2J\x1b[H");
}

fn waitForReturn() !void {
    try std.io.getStdOut().writeAll("[Hit return to continue]");
    var byte: [1]u8 = undefined;
    while (try std.io.getStdIn().read(&byte) != 0) {
        if (byte[0] == '\n') break;
    }
}

fn isOwnerExecutable(mode: usize) bool {
    return mode & 0o100 != 0;
}

fn runExecutable(allocator: std.mem.Allocator, path: []const u8) !void {
    const prefixed = if (std.mem.startsWith(u8, path, "./"))
        try allocator.dupe(u8, path)
    else
        try std.fmt.allocPrint(allocator, "./{s}", .{path});
    defer allocator.free(prefixed);
    try runChild(allocator, &.{prefixed});
}

fn runShell(allocator: std.mem.Allocator, command: []const u8) !void {
    const shell = std.posix.getenv("SHELL") orelse "/bin/sh";
    try runChild(allocator, &.{ shell, "-c", command });
}

fn runChild(allocator: std.mem.Allocator, argv: []const []const u8) !void {
    var child = std.process.Child.init(argv, allocator);
    child.stdin_behavior = .Inherit;
    child.stdout_behavior = .Inherit;
    child.stderr_behavior = .Inherit;
    _ = try child.spawnAndWait();
}

fn shellQuote(allocator: std.mem.Allocator, text: []const u8) ![]u8 {
    var out: std.ArrayListUnmanaged(u8) = .{};
    errdefer out.deinit(allocator);
    try out.append(allocator, '\'');
    for (text) |ch| {
        if (ch == '\'') {
            try out.appendSlice(allocator, "'\\''");
        } else {
            try out.append(allocator, ch);
        }
    }
    try out.append(allocator, '\'');
    return out.toOwnedSlice(allocator);
}

test "shellQuote wraps paths and escapes single quotes" {
    const quoted = try shellQuote(std.testing.allocator, "manual/it's here");
    defer std.testing.allocator.free(quoted);
    try std.testing.expectEqualStrings("'manual/it'\\''s here'", quoted);
}

test "owner execute bit detection matches manual executable sections" {
    try std.testing.expect(isOwnerExecutable(0o100));
    try std.testing.expect(isOwnerExecutable(0o755));
    try std.testing.expect(!isOwnerExecutable(0o644));
    try std.testing.expect(!isOwnerExecutable(0o010));
}
