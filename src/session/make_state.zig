//! make_state.zig (split from RuntimeState, Phase 4 step 4,
//! docs/GoReady.md) — the `//make`/`-make` build-mode flags and its
//! accumulated failure list (`make_status`), previously four fields
//! scattered among ~90 others in the monolithic `RuntimeState`.

const Word = i64;

/// State for the `//make`/`-make` batch mode: which sub-mode is active
/// (`making`/`mkexports`/`mksources`, set by `-make`/`-exports`/`-sources`
/// CLI flags in `session/config.zig`) and the accumulated list of
/// files that failed to compile (`make_status`, a heap `STRCONS` chain
/// built up during the run and drained by `session/boot.zig`'s
/// `reportMakeFailures`).
pub const MakeState = struct {
    /// True when `//make`/`-make` is in progress.
    making: bool = false,
    /// True when `//exports` should write an export header.
    mkexports: bool = false,
    mksources: bool = false,
    make_status: Word = 0,
};

var default_state: MakeState = .{};
var active_state: *MakeState = &default_state;

pub fn bind(state: *MakeState) void {
    active_state = state;
}

/// Pointer to the singleton make-mode state held in `current_interp` (so
/// `interp.reset()` clears it). Accessed as `make_state.make().X`.
pub inline fn make() *MakeState {
    return active_state;
}

test "MakeState default values are self-consistent" {
    const state: MakeState = .{};
    try @import("std").testing.expect(!state.making);
    try @import("std").testing.expect(!state.mkexports);
    try @import("std").testing.expect(!state.mksources);
    try @import("std").testing.expectEqual(@as(Word, 0), state.make_status);
}
