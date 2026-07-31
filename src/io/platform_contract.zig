//! Language-neutral contracts for services supplied by the host platform.
//! No POSIX constants, C integer aliases, wait-status layouts, descriptors,
//! or native handler pointers cross this boundary.

const std = @import("std");

pub const supported_targets = [_][]const u8{
    "aarch64-macos",
    "x86_64-linux",
};

pub const FileMetadata = struct {
    identity: struct { device: u64, inode: u64 },
    modified_seconds: i64,
    mode: u32,
    owner: u32,
    group: u32,
};

pub const ProcessRequest = struct {
    executable: []const u8,
    arguments: []const []const u8,
    working_directory: ?[]const u8 = null,
    inherit_environment: bool = true,
    stdin: StreamMode = .inherit,
    stdout: StreamMode = .inherit,
    stderr: StreamMode = .inherit,
};

pub const StreamMode = enum {
    inherit,
    pipe,
    discard,
};

pub const ProcessOutcome = union(enum) {
    exited: u8,
    signaled: u8,
};

pub const ProcessError = error{
    SpawnFailed,
    WaitFailed,
    TimedOut,
    Interrupted,
};

pub const ShellContract = struct {
    pub const fallback_path = "/bin/sh";
    pub const command_argument = "-c";
    pub const inherits_environment = true;
    pub const inherits_working_directory = true;
    pub const stdout_stderr_are_distinct = true;
    pub const close_parent_pipe_ends_before_wait = true;
    pub const consume_pipes_before_wait = true;
    pub const eof_after_child_closes_writer = true;
    pub const cleanup_child_on_interrupt_or_timeout = true;
};

pub const Signal = enum {
    interrupt,
    terminate,
};

pub const SignalAction = enum {
    notify,
    ignore,
    default,
};

pub const TerminalInfo = struct {
    interactive: bool,
    columns: ?u16,
};

pub const Services = struct {
    context: *anyopaque,
    metadata_fn: *const fn (*anyopaque, []const u8) ?FileMetadata,
    run_fn: *const fn (*anyopaque, ProcessRequest) ProcessError!ProcessOutcome,
    terminal_fn: *const fn (*anyopaque, u32) TerminalInfo,
    monotonic_ns_fn: *const fn (*anyopaque) i128,
    environment_fn: *const fn (*anyopaque, []const u8) ?[]const u8,
    executable_fn: *const fn (*anyopaque, []const u8) ?[]const u8,

    pub fn metadata(self: Services, path: []const u8) ?FileMetadata {
        return self.metadata_fn(self.context, path);
    }

    pub fn run(self: Services, request: ProcessRequest) ProcessError!ProcessOutcome {
        return self.run_fn(self.context, request);
    }

    pub fn terminal(self: Services, descriptor: u32) TerminalInfo {
        return self.terminal_fn(self.context, descriptor);
    }

    pub fn monotonicNs(self: Services) i128 {
        return self.monotonic_ns_fn(self.context);
    }

    pub fn environment(self: Services, name: []const u8) ?[]const u8 {
        return self.environment_fn(self.context, name);
    }

    pub fn findExecutable(self: Services, name: []const u8) ?[]const u8 {
        return self.executable_fn(self.context, name);
    }
};

test "process contract has portable outcomes and explicit shell semantics" {
    try std.testing.expectEqualStrings("/bin/sh", ShellContract.fallback_path);
    try std.testing.expectEqualStrings("-c", ShellContract.command_argument);
    try std.testing.expect(ShellContract.inherits_environment);
    try std.testing.expect(ShellContract.inherits_working_directory);
    try std.testing.expect(ShellContract.stdout_stderr_are_distinct);
    try std.testing.expect(ShellContract.close_parent_pipe_ends_before_wait);
    try std.testing.expect(ShellContract.consume_pipes_before_wait);
    try std.testing.expect(ShellContract.eof_after_child_closes_writer);
    try std.testing.expect(ShellContract.cleanup_child_on_interrupt_or_timeout);

    const normal: ProcessOutcome = .{ .exited = 7 };
    const killed: ProcessOutcome = .{ .signaled = 2 };
    try std.testing.expectEqual(@as(u8, 7), normal.exited);
    try std.testing.expectEqual(@as(u8, 2), killed.signaled);
}

test "service interface accepts a deterministic substitute" {
    const Fake = struct {
        now: i128 = 41,
        runs: usize = 0,

        fn metadata(_: *anyopaque, path: []const u8) ?FileMetadata {
            if (!std.mem.eql(u8, path, "present")) return null;
            return .{
                .identity = .{ .device = 2, .inode = 3 },
                .modified_seconds = 4,
                .mode = 0o644,
                .owner = 5,
                .group = 6,
            };
        }

        fn run(context: *anyopaque, request: ProcessRequest) ProcessError!ProcessOutcome {
            const self: *@This() = @ptrCast(@alignCast(context));
            self.runs += 1;
            if (request.executable.len == 0) return error.SpawnFailed;
            return .{ .exited = 0 };
        }

        fn terminal(_: *anyopaque, descriptor: u32) TerminalInfo {
            return .{ .interactive = descriptor == 0, .columns = 80 };
        }

        fn clock(context: *anyopaque) i128 {
            const self: *@This() = @ptrCast(@alignCast(context));
            self.now += 1;
            return self.now;
        }

        fn environment(_: *anyopaque, name: []const u8) ?[]const u8 {
            return if (std.mem.eql(u8, name, "SHELL")) "/test/sh" else null;
        }

        fn executable(_: *anyopaque, name: []const u8) ?[]const u8 {
            return if (std.mem.eql(u8, name, "sh")) "/test/sh" else null;
        }
    };

    var fake: Fake = .{};
    const services: Services = .{
        .context = &fake,
        .metadata_fn = Fake.metadata,
        .run_fn = Fake.run,
        .terminal_fn = Fake.terminal,
        .monotonic_ns_fn = Fake.clock,
        .environment_fn = Fake.environment,
        .executable_fn = Fake.executable,
    };
    try std.testing.expectEqual(@as(u64, 3), services.metadata("present").?.identity.inode);
    try std.testing.expect(services.metadata("absent") == null);
    try std.testing.expectEqual(@as(i128, 42), services.monotonicNs());
    try std.testing.expect(services.terminal(0).interactive);
    try std.testing.expectEqualStrings("/test/sh", services.environment("SHELL").?);
    try std.testing.expectEqualStrings("/test/sh", services.findExecutable("sh").?);
    try std.testing.expectEqual(ProcessOutcome{ .exited = 0 }, try services.run(.{
        .executable = "/test/sh",
        .arguments = &.{ "-c", "true" },
    }));
    try std.testing.expectEqual(@as(usize, 1), fake.runs);
}
