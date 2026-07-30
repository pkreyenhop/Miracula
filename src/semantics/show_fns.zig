//! show_fns.zig (split from RuntimeState, Phase 4 step 4,
//! docs/GO_PORT_PLAN.md) — the per-type `show` combinator identifiers
//! (heap `ID` nodes for `shownum1`/`showbool`/…, interned once at startup
//! by `compiler/setup.zig` and read by `semantics/lower.zig`'s `mkshowt`
//! when generating a type's derived show function).
//!
//! The plan's one-line description reads "the 20 `show*` atom fields ->
//! `std.EnumArray(ShowFn, Value)`" — but only 11 such fields exist in the
//! current `RuntimeState` (the rest were presumably already retired by an
//! earlier phase), and `Value` (the typed graph handle) doesn't exist until
//! Phase 5. This move keeps today's plain named fields and Word type,
//! deferring the `EnumArray`/`Value` retyping to Phase 5 where the rest of
//! the graph API gets typed at once — converting the access pattern itself
//! (named field -> enum-keyed lookup) is a bigger, distinct change from
//! "which struct owns this data", which is all step 4 is doing.

const Word = i64;

pub const ShowFns = struct {
    shownum1: Word = 0,
    showbool: Word = 0,
    showchar: Word = 0,
    showlist: Word = 0,
    showstring: Word = 0,
    showparen: Word = 0,
    showpair: Word = 0,
    showvoid: Word = 0,
    showfunction: Word = 0,
    showabstract: Word = 0,
    showwhat: Word = 0,
};

/// Pointer to the singleton show-function-id state held in `current_interp`
/// (so `interp.reset()` clears it). Accessed as `show_fns.show().X`.
pub inline fn show() *ShowFns {
    return &@import("../session/interp.zig").current_interp.show;
}

test "ShowFns default values are self-consistent" {
    const state: ShowFns = .{};
    try @import("std").testing.expectEqual(@as(Word, 0), state.shownum1);
    try @import("std").testing.expectEqual(@as(Word, 0), state.showwhat);
}
