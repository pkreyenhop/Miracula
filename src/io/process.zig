//! Native process implementation. PID representation and wait-status bit
//! layouts are confined here; callers receive typed roles and outcomes.

const contract = @import("platform_contract.zig");

extern fn fork() c_int;
extern fn waitpid(pid: c_int, status: *c_int, options: c_int) c_int;

pub const ProcessId = enum(u32) { _ };

pub const ForkResult = union(enum) {
    child,
    parent: ProcessId,
};

pub fn forkProcess() contract.ProcessError!ForkResult {
    const result = fork();
    if (result < 0) return error.SpawnFailed;
    if (result == 0) return .child;
    return .{ .parent = @enumFromInt(@as(u32, @intCast(result))) };
}

pub fn waitChild(id: ProcessId) contract.ProcessError!contract.ProcessOutcome {
    var status: c_int = 0;
    const pid: c_int = @intCast(@intFromEnum(id));
    if (waitpid(pid, &status, 0) != pid) return error.WaitFailed;
    if ((status & 0x7f) == 0) {
        return .{ .exited = @intCast((status >> 8) & 0xff) };
    }
    return .{ .signaled = @intCast(status & 0x7f) };
}
