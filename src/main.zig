//! main.zig — the composition root. Just the process entry point (`main`) and the
//! `comptime` block that aggregates every module's unit tests into the
//! `main-tests` binary. All interpreter functionality lives in the runtime /
//! compiler / parser / driver / io modules, which call each other directly (the
//! old `main.*` re-export namespace is gone — Part A of the idiomatic-architecture
//! plan).

const std = @import("std");
const rt = @import("runtime/runtime_state.zig");
const abi = @import("runtime/main_clib.zig");
const startup = @import("driver/startup.zig");

/// Process entry point: wire up the runtime context (io / allocator / argv) and
/// forward to `startup.mainEntry`.
pub fn main(ctx: std.process.Init) !void {
    rt.io = ctx.io;
    rt.environ = ctx.minimal.environ;
    rt.allocator = rt.gpa.allocator();
    abi.env_slice = ctx.minimal.environ.block.slice;
    const raw_args = ctx.minimal.args.vector;
    const argv: [*][*:0]u8 = @ptrCast(@constCast(raw_args.ptr));
    const argc: c_int = @intCast(raw_args.len);
    const exit_code = startup.mainEntry(argc, argv);
    _ = rt.gpa.deinit();
    std.process.exit(@intCast(exit_code));
}

// Pull every module's inline tests into the `main-tests` binary. (Files with no
// tests are listed too so they are still type-checked as part of this build.)
comptime {
    _ = @import("runtime/core_state.zig");
    _ = @import("driver/startup.zig");
    _ = @import("driver/repl.zig");
    _ = @import("driver/commands.zig");
    _ = @import("runtime/heap.zig");
    _ = @import("runtime/strtab.zig");
    _ = @import("runtime/reducer/reduce_test.zig");
    _ = @import("runtime/reducer/combinators.zig");
    _ = @import("runtime/errors.zig");
    _ = @import("runtime/reduce.zig");
    _ = @import("runtime/combinator.zig");
    _ = @import("runtime/big.zig");
    _ = @import("parser/lex.zig");
    _ = @import("parser/parser_tests.zig");
    _ = @import("parser/diagnostics.zig");
    _ = @import("compiler/trans.zig");
    _ = @import("compiler/types.zig");
    _ = @import("compiler/setup.zig");
    _ = @import("compiler/module_loader.zig");
    _ = @import("compiler/dump.zig");
    _ = @import("io/files.zig");
    _ = @import("io/signals.zig");
    _ = @import("runtime/version.zig");
    _ = @import("runtime/runtime_state.zig");
    _ = @import("testutil.zig");
}
