//! Typed signal registration. Native handler pointers and `sigaction` values
//! are confined to this platform implementation.

const std = @import("std");
const contract = @import("platform_contract.zig");

extern fn sigaction(signum: c_int, act: ?*const std.posix.Sigaction, oldact: ?*std.posix.Sigaction) c_int;

pub const Notify = *const fn () void;
var notification: ?Notify = null;

pub const Action = union(contract.SignalAction) {
    notify: Notify,
    ignore,
    default,
};

pub const Registration = struct {
    signal: contract.Signal,
    previous: std.posix.Sigaction,

    pub fn restore(self: Registration) void {
        _ = sigaction(signalNumber(self.signal), &self.previous, null);
    }
};

pub const RegisterError = error{RegistrationFailed};

pub fn register(signal: contract.Signal, action: Action) RegisterError!Registration {
    var act: std.posix.Sigaction = undefined;
    var oldact: std.posix.Sigaction = undefined;

    act.handler = .{ .handler = switch (action) {
        .notify => |handler| blk: {
            notification = handler;
            break :blk nativeNotify;
        },
        .ignore => @ptrFromInt(1),
        .default => null,
    } };
    act.mask = std.posix.sigemptyset();
    act.flags = std.posix.SA.RESTART;

    if (sigaction(signalNumber(signal), &act, &oldact) != 0) {
        return error.RegistrationFailed;
    }
    return .{ .signal = signal, .previous = oldact };
}

fn nativeNotify(_: std.posix.SIG) callconv(.c) void {
    if (notification) |notify| notify();
}

fn signalNumber(signal: contract.Signal) c_int {
    return @intCast(@intFromEnum(switch (signal) {
        .interrupt => std.posix.SIG.INT,
        .terminate => std.posix.SIG.TERM,
    }));
}
