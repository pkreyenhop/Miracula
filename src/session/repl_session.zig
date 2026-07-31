//! repl_session.zig (split from RuntimeState, Phase 4 step 4,
//! docs/GoReady.md) — interactive REPL state: the last-evaluated
//! expression (`lastexp`, a GC root -- `//x`/`//f` and `$$` reference it),
//! the last-referenced identifier (`lastid`, for `//f`), the echo/listing/
//! verbosity flags (`echoing` is always `verbosity & listing`, computed
//! fresh wherever either changes), the prompt string, and the elapsed-
//! time/GC-count scratch surfaced in the *next* prompt.

const Word = i64;
const CMBASE: Word = 306;
const UNDEF: Word = CMBASE + 140;

pub const ReplSession = struct {
    /// Last identifier referenced interactively; used for `//f` finger command.
    lastid: Word = 0,
    lastexp: Word = UNDEF,

    // I/O mode flags
    echoing: Word = 0,
    listing: Word = 0,
    verbosity: Word = 0,

    promptstr: [*:0]const u8 = "Miranda ",

    /// Elapsed time and GC count from the last evaluated REPL expression,
    /// surfaced in the next prompt string. Set directly by `evaluateRepl`
    /// after each in-process evaluation (Phase 3, docs/GoReady.md —
    /// no more forked-child exit-code round trip to smuggle it back).
    last_elapsed_ns: ?i128 = null,
    last_gc_count: ?i64 = null,
};

/// Pointer to the singleton REPL session state held in `current_interp`
/// (so `interp.reset()` clears it). Accessed as `repl_session.session().X`.
pub inline fn session() *ReplSession {
    return &@import("interp.zig").current_interp.repl;
}

test "ReplSession default values are self-consistent" {
    const state: ReplSession = .{};
    try @import("std").testing.expectEqual(@as(Word, 0), state.lastid);
    try @import("std").testing.expectEqual(@as(Word, UNDEF), state.lastexp);
    try @import("std").testing.expectEqual(@as(Word, 0), state.echoing);
    try @import("std").testing.expectEqual(@as(Word, 0), state.listing);
    try @import("std").testing.expectEqual(@as(Word, 0), state.verbosity);
    try @import("std").testing.expectEqual(@as(?i128, null), state.last_elapsed_ns);
    try @import("std").testing.expectEqual(@as(?i64, null), state.last_gc_count);
}
