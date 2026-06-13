const std = @import("std");

const SigAction = extern struct {
    handler: usize,
    sa_mask: std.posix.sigset_t,
    sa_flags: c_int,
};

extern fn sigaction(signum: c_int, act: ?*const SigAction, oldact: ?*SigAction) c_int;

export fn signals(signum: c_int, handler: usize) usize {
    var act: SigAction = undefined;
    var oldact: SigAction = undefined;

    act.handler = handler;
    act.sa_mask = std.posix.sigemptyset();
    act.sa_flags = std.posix.SA.RESTART;

    if (sigaction(signum, &act, &oldact) == 0) {
        return oldact.handler;
    }
    return std.math.maxInt(usize);
}
