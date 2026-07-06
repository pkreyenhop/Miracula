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
const interp_mod = @import("runtime/interp.zig");

/// Process entry point: wire up the runtime context (io / allocator / argv),
/// construct the interpreter explicitly, and forward to `startup.mainEntry`.
pub fn main(ctx: std.process.Init) !void {
    rt.io = ctx.io;
    rt.environ = ctx.minimal.environ;
    rt.allocator = rt.gpa.allocator();
    abi.env_slice = ctx.minimal.environ.block.slice;

    // Construct the interpreter explicitly (shared-state plan Phase 6) rather
    // than relying on interp.zig's own default-initialized `backing` — this
    // is what "a second Interp can be constructed and run independently"
    // means in practice: `interp_storage` lives for main()'s whole duration
    // (the process doesn't return until `std.process.exit` below), so
    // pointing `current_interp` at it is as safe as the module-level default.
    var interp_storage: interp_mod.Interp = .{};
    interp_mod.current_interp = &interp_storage;

    const raw_args = ctx.minimal.args.vector;
    const argv: [*][*:0]u8 = @ptrCast(@constCast(raw_args.ptr));
    const argc: c_int = @intCast(raw_args.len);
    const exit_code = startup.mainEntry(argc, argv);
    if (@import("version_options").is_strict or @import("builtin").mode == .Debug) {
        const heap = @import("runtime/heap.zig");
        heap.heap().validate();
        @import("compiler/trans.zig").validate(heap.heap());
        rt.rs().validate();
    }
    const check = rt.gpa.deinit();
    const final_exit_code = if (check == .leak and @import("version_options").is_strict) 1 else exit_code;
    std.process.exit(@intCast(final_exit_code));
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
    _ = @import("runtime/reducer/spine.zig");
    _ = @import("runtime/reducer/combinators.zig");
    _ = @import("runtime/errors.zig");
    _ = @import("runtime/reduce.zig");
    _ = @import("runtime/combinator.zig");
    _ = @import("runtime/big.zig");
    _ = @import("parser/lex.zig");
    _ = @import("parser/parser_tests.zig");
    _ = @import("parser/diagnostics.zig");
    _ = @import("syntax/source.zig");
    _ = @import("syntax/lexer.zig");
    _ = @import("syntax/layout.zig");
    _ = @import("syntax/differential_test.zig");
    _ = @import("syntax/directives.zig");
    _ = @import("semantics/symbols.zig");
    _ = @import("semantics/modules.zig");
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

    // Static compile-time validations
    const word = @import("runtime/word.zig");
    // Word and pointer size checks
    std.debug.assert(@bitSizeOf(word.Word) == 64);
    std.debug.assert(@sizeOf(*anyopaque) == 8);

    // Structure sizes and alignments
    std.debug.assert(@sizeOf(abi.jmp_buf) == 512);
    std.debug.assert(@sizeOf(abi.sigjmp_buf) == 528);
    std.debug.assert(@alignOf(abi.jmp_buf) == 16);
    std.debug.assert(@alignOf(abi.sigjmp_buf) == 16);

    // Enum layout checks
    std.debug.assert(@sizeOf(word.NodeTag) == 1);
    std.debug.assert(@intFromEnum(word.NodeTag.ATOM) == 0);
    std.debug.assert(@intFromEnum(word.NodeTag.TCONS) == 22);
}
