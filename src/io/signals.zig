const std = @import("std");

extern fn sigaction(signum: c_int, act: ?*const std.posix.Sigaction, oldact: ?*std.posix.Sigaction) c_int;

pub export fn signals(signum: c_int, handler: usize) usize {
    var act: std.posix.Sigaction = undefined;
    var oldact: std.posix.Sigaction = undefined;

    act.handler = .{ .handler = @ptrFromInt(handler) };
    act.mask = std.posix.sigemptyset();
    act.flags = std.posix.SA.RESTART;

    if (sigaction(signum, &act, &oldact) == 0) {
        if (oldact.handler.handler) |h| {
            return @intFromPtr(h);
        }
        return 0; // SIG_DFL
    }
    return std.math.maxInt(usize);
}
