const std = @import("std");

const max_selection = 4096;

const Driver = struct {
    ctx: std.process.Init,
    next: std.ArrayListUnmanaged(u8) = .empty,
    last: std.ArrayListUnmanaged(u8) = .empty,
    last_stack: std.ArrayListUnmanaged([]u8) = .empty,
    shell_command: std.ArrayListUnmanaged(u8) = .empty,
    viewer: []const u8,
    menuviewer: []const u8,
    fastback: bool,

    fn init(ctx: std.process.Init) !Driver {
        var driver = Driver{
            .ctx = ctx,
            .viewer = ctx.environ_map.get("VIEWER") orelse "less",
            .menuviewer = ctx.environ_map.get("MENUVIEWER") orelse "cat",
            .fastback = true,
        };
        if (ctx.environ_map.get("RETURNTOMENU")) |value| {
            driver.fastback = value.len == 0 or (value[0] != 'N' and value[0] != 'n');
        }
        try driver.last.append(ctx.gpa, '.');
        return driver;
    }

    fn deinit(self: *Driver) void {
        self.next.deinit(self.ctx.gpa);
        self.last.deinit(self.ctx.gpa);
        for (self.last_stack.items) |item| {
            self.ctx.gpa.free(item);
        }
        self.last_stack.deinit(self.ctx.gpa);
        self.shell_command.deinit(self.ctx.gpa);
    }

    fn drive(self: *Driver, dir: []const u8) !void {
        std.process.setCurrentPath(self.ctx.io, dir) catch {
            try self.singleton(dir);
            return;
        };

        var bad = false;
        while (std.Io.Dir.cwd().statFile(self.ctx.io, "contents", .{})) |_| {
            if (self.next.items.len == 0 or bad) {
                try self.clearScreen();
                if (bad) {
                    if (std.mem.eql(u8, self.next.items, ".")) {
                        var out_w = std.Io.File.stdout().writer(self.ctx.io, &[_]u8{});
                try out_w.interface.writeAll("no previous selection to substitute for \".\"\n");
                    } else {
                        std.debug.print("selection \"{s}\" not valid\n", .{self.next.items});
                    }
                    bad = false;
                }

                try self.runViewer(self.menuviewer, "contents");
                var out_w = std.Io.File.stdout().writer(self.ctx.io, &[_]u8{});
                try out_w.interface.writeAll("::please type selection number (or return to exit):");
                try self.readSelection();
            }

            if (self.next.items.len == 0) {
                std.process.setCurrentPath(self.ctx.io, "..") catch {};
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

            const stat = std.Io.Dir.cwd().statFile(self.ctx.io, self.next.items, .{}) catch {
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
                    const hold_len = std.process.currentPath(self.ctx.io, &cwd_buffer) catch {
                        std.debug.print("menudriver: cwd path too long\n", .{});
                        std.process.exit(1);
                    };
                    const hold = cwd_buffer[0..hold_len];
                    if (std.process.setCurrentPath(self.ctx.io, self.next.items)) |_| {
                        if (std.Io.Dir.cwd().statFile(self.ctx.io, "contents", .{})) |_| {
                            try self.setLast(self.next.items);
                            try self.pushLast();
                            self.next.clearRetainingCapacity();
                        } else |_| {
                            bad = true;
                            std.process.setCurrentPath(self.ctx.io, hold) catch {};
                        }
                    } else |_| {
                        bad = true;
                        std.process.setCurrentPath(self.ctx.io, hold) catch {};
                    }
                },
                .file => try self.showFile(self.next.items, stat.permissions.toMode()),
                else => bad = true,
            }
        } else |_| {}
    }

    fn singleton(self: *Driver, path: []const u8) !void {
        const stat = std.Io.Dir.cwd().statFile(self.ctx.io, path, .{}) catch {
            std.debug.print("menudriver: cannot access \"{s}\"\n", .{path});
            std.process.exit(1);
        };
        if (stat.kind != .file) {
            std.debug.print("menudriver: cannot access \"{s}\"\n", .{path});
            std.process.exit(1);
        }

        try self.clearScreen();
        if (isOwnerExecutable(stat.permissions.toMode())) {
            try runExecutable(self.ctx, path);
            self.fastback = false;
        } else {
            try self.runViewer(self.viewer, path);
        }
        if (!self.fastback) {
            try self.waitForReturn();
        }
        std.process.exit(0);
    }

    fn showFile(self: *Driver, path: []const u8, mode: std.posix.mode_t) !void {
        try self.clearScreen();
        if (isOwnerExecutable(mode)) {
            try runExecutable(self.ctx, path);
            if (self.fastback) {
                try self.waitForReturn();
            }
        } else {
            try self.runViewer(self.viewer, path);
        }

        try self.setLast(path);
        if (self.fastback) {
            self.next.clearRetainingCapacity();
            return;
        }

        var out_w = std.Io.File.stdout().writer(self.ctx.io, &[_]u8{});
        try out_w.interface.writeAll("::next selection (or return to go back to menu, or q to quit):");
        try self.readSelection();
    }

    fn handleSpecialOrBad(self: *Driver, bad: *bool) !void {
        if (std.mem.eql(u8, self.next.items, "???")) {
            try self.settings();
            try self.waitForReturn();
            self.next.clearRetainingCapacity();
        } else if (std.mem.eql(u8, self.next.items, "q") or std.mem.eql(u8, self.next.items, "/q")) {
            std.process.exit(0);
        } else if (self.next.items.len > 0 and self.next.items[0] == '!') {
            try self.shellEscape();
            try self.waitForReturn();
            self.next.clearRetainingCapacity();
        } else {
            bad.* = true;
        }
    }

    fn settings(self: *Driver) !void {
        var stdout_w = std.Io.File.stdout().writer(self.ctx.io, &[_]u8{});
        const stdout = &stdout_w.interface;
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
                    try self.shell_command.appendSlice(self.ctx.gpa, self.next.items[2..]);
                }
                std.debug.print("!{s}\n", .{self.shell_command.items});
            } else {
                var out_w = std.Io.File.stdout().writer(self.ctx.io, &[_]u8{});
                try out_w.interface.writeAll("no previous shell command to substitute for \"!\"\n");
            }
        } else {
            self.shell_command.clearRetainingCapacity();
            try self.shell_command.appendSlice(self.ctx.gpa, self.next.items[1..]);
        }
        if (self.shell_command.items.len > 0) {
            try runShell(self.ctx, self.shell_command.items);
        }
    }

    fn readSelection(self: *Driver) !void {
        var buffer: [max_selection]u8 = undefined;
        var len: usize = 0;
        var byte_buf: [1]u8 = undefined;
        var saw_nonleading = false;
        const stdin = std.Io.File.stdin();
        var r = stdin.reader(self.ctx.io, &byte_buf);
        while (true) {
            const read = try r.interface.readSliceShort(&byte_buf);
            if (read == 0) std.process.exit(0);
            const ch = byte_buf[0];
            if (ch == '\n') break;
            if (!saw_nonleading and (ch == ' ' or ch == '\t')) continue;
            saw_nonleading = true;
            if (len < buffer.len) {
                buffer[len] = ch;
                len += 1;
            }
        }

        var selection: []const u8 = buffer[0..len];
        if (selection.len == 0 or selection[0] != '!') {
            selection = std.mem.trimEnd(u8, selection, " \t");
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
            std.process.setCurrentPath(self.ctx.io, "..") catch {};
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
        const saved = try self.ctx.gpa.dupe(u8, self.last.items);
        try self.last_stack.append(self.ctx.gpa, saved);
        try self.setLast(".");
    }

    fn popLast(self: *Driver) !void {
        if (self.last_stack.items.len == 0) return;
        const saved = self.last_stack.pop().?;
        defer self.ctx.gpa.free(saved);
        try self.setLast(saved);
    }

    fn runViewer(self: *Driver, command: []const u8, path: []const u8) !void {
        const quoted = try shellQuote(self.ctx.gpa, path);
        defer self.ctx.gpa.free(quoted);
        const full = try std.fmt.allocPrint(self.ctx.gpa, "{s} {s}", .{ command, quoted });
        defer self.ctx.gpa.free(full);
        try runShellViewer(self.ctx, full);
    }

    fn setNext(self: *Driver, value: []const u8) !void {
        self.next.clearRetainingCapacity();
        try self.next.appendSlice(self.ctx.gpa, value);
    }

    fn setNextFmt(self: *Driver, comptime fmt: []const u8, args: anytype) !void {
        self.next.clearRetainingCapacity();
        const s = try std.fmt.allocPrint(self.ctx.gpa, fmt, args);
        defer self.ctx.gpa.free(s);
        try self.next.appendSlice(self.ctx.gpa, s);
    }

    fn setLast(self: *Driver, value: []const u8) !void {
        self.last.clearRetainingCapacity();
        try self.last.appendSlice(self.ctx.gpa, value);
    }

    fn clearScreen(self: *Driver) !void {
        var out_w = std.Io.File.stdout().writer(self.ctx.io, &[_]u8{});
        try out_w.interface.writeAll("\x1b[2J\x1b[H");
    }

    fn waitForReturn(self: *Driver) !void {
        var out_w = std.Io.File.stdout().writer(self.ctx.io, &[_]u8{});
        try out_w.interface.writeAll("[Hit return to continue]");
        var byte_buf: [1]u8 = undefined;
        const stdin = std.Io.File.stdin();
        var r = stdin.reader(self.ctx.io, &byte_buf);
        while (try r.interface.readSliceShort(&byte_buf) != 0) {
            if (byte_buf[0] == '\n') break;
        }
    }
};

pub fn main(ctx: std.process.Init) !void {
    const args = try ctx.minimal.args.toSlice(ctx.gpa);
    defer ctx.gpa.free(args);
    if (args.len > 2) {
        std.debug.print("menudriver: wrong number of args\n", .{});
        std.process.exit(1);
    }

    var driver = try Driver.init(ctx);
    defer driver.deinit();
    try driver.drive(if (args.len == 1) "." else args[1]);
}

fn isOwnerExecutable(mode: std.posix.mode_t) bool {
    return mode & 0o100 != 0;
}

fn runExecutable(ctx: std.process.Init, path: []const u8) !void {
    const prefixed = if (std.mem.startsWith(u8, path, "./"))
        try ctx.gpa.dupe(u8, path)
    else
        try std.fmt.allocPrint(ctx.gpa, "./{s}", .{path});
    defer ctx.gpa.free(prefixed);
    try runChild(ctx, &.{prefixed}, .inherit);
}

// Run a shell command for display purposes (viewer, menuviewer).
// stdin is redirected to /dev/null so that the shell itself cannot read-ahead
// and consume buffered terminal input that belongs to the menudriver's own
// readSelection().  Pagers like `less` open /dev/tty independently for
// interactive keystrokes, so they work correctly even with stdin closed.
fn runShellViewer(ctx: std.process.Init, command: []const u8) !void {
    try runChild(ctx, &.{ "/bin/sh", "-c", command }, .ignore);
}

// Run a shell command for interactive use (shell escapes via !cmd).
// stdin is inherited so the user can interact with the spawned shell.
fn runShell(ctx: std.process.Init, command: []const u8) !void {
    try runChild(ctx, &.{ "/bin/sh", "-c", command }, .inherit);
}

fn runChild(ctx: std.process.Init, argv: []const []const u8, stdin_mode: std.process.SpawnOptions.StdIo) !void {
    var child = try std.process.spawn(ctx.io, .{
        .argv = argv,
        .stdin = stdin_mode,
        .stdout = .inherit,
        .stderr = .inherit,
    });
    _ = try child.wait(ctx.io);
}

fn shellQuote(allocator: std.mem.Allocator, text: []const u8) ![]u8 {
    var out: std.ArrayListUnmanaged(u8) = .empty;
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
