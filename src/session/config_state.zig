//! config_state.zig (split from RuntimeState, Phase 4 step 4,
//! docs/GoReady.md) — process-wide configuration set once at
//! startup from CLI flags or `.mirarc` (`session/config.zig`'s
//! `parseFlags`/`readRc`) and read throughout the run: the prelude/stdenv
//! paths, the heap/dictionary size limits, the editor command, and the
//! open source stream.
//!
//! Named `config_state.zig` rather than `config.zig` to avoid colliding
//! with the existing `session/config.zig` (flag parsing and `.mirarc`
//! I/O, from the Phase 4 step 3 `startup.zig` split) — that file is the
//! *logic* that populates this struct, not the struct itself.
//!
//! `UTF8`/`UTF8OUT` stay on `RuntimeState` for now, not here: they're read
//! through `ctx.rs.UTF8` inside `eval/reduce_rt.zig`'s `ReductionCtx` (the
//! reduction hot path's own receiver-carrying context), so moving them
//! means giving `ReductionCtx` a second config pointer -- a `ReductionCtx`
//! signature change, which is eval's step-5 receiver-threading work, not
//! a data-ownership move.

const abi = @import("../os.zig");
const Word = i64;

pub const ConfigState = struct {
    // File paths — null-terminated byte arrays populated by startup; treated as C strings.
    // Zero-initialised so a `.{}` singleton reads as the empty string before startup fills them.
    PRELUDE: [abi.pnlim + 10]u8 = @import("std").mem.zeroes([abi.pnlim + 10]u8),
    STDENV: [abi.pnlim + 9]u8 = @import("std").mem.zeroes([abi.pnlim + 9]u8),

    /// Maximum heap cells before GC triggers; set from `-heap N` CLI flag.
    SPACELIMIT: Word = 2500000,
    /// Dictionary space in bytes; set from `-dic N` CLI flag.
    DICSPACE: Word = 100000,

    editor: ?[*:0]u8 = null,
    /// True when the prelude has been accepted without error.
    okprel: bool = false,
    /// True when `-nostandard` flag suppresses loading STDENV.
    nostdenv: bool = false,
    /// Non-zero when the configured editor command is invalid.
    baded: Word = 0,
    miralib: ?[*:0]u8 = null,
    s_in: ?*abi.Stream = null,
};

/// Pointer to the singleton config state held in `current_interp` (so
/// `interp.reset()` clears it). Accessed as `config_state.config().X`.
pub inline fn config() *ConfigState {
    return &@import("interp.zig").current_interp.config;
}

test "ConfigState default values are self-consistent" {
    const state: ConfigState = .{};
    try @import("std").testing.expectEqual(@as(Word, 2500000), state.SPACELIMIT);
    try @import("std").testing.expectEqual(@as(Word, 100000), state.DICSPACE);
    try @import("std").testing.expectEqual(@as(?[*:0]u8, null), state.editor);
    try @import("std").testing.expectEqual(@as(?[*:0]u8, null), state.miralib);
    try @import("std").testing.expect(!state.okprel);
    try @import("std").testing.expect(!state.nostdenv);
}
