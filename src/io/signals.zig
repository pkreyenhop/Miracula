const std = @import("std");

const c = @cImport({
    @cInclude("signal.h");
});

const SigAction = extern struct {
    handler: usize,
    sa_mask: c.sigset_t,
    sa_flags: c_int,
};

extern fn sigaction(signum: c_int, act: ?*const SigAction, oldact: ?*SigAction) c_int;

export fn signals(signum: c_int, handler: usize) usize {
    var act: SigAction = undefined;
    var oldact: SigAction = undefined;

    act.handler = handler;
    _ = c.sigemptyset(&act.sa_mask);
    act.sa_flags = c.SA_RESTART;

    if (sigaction(signum, &act, &oldact) == 0) {
        return oldact.handler;
    }
    return std.math.maxInt(usize);
}
