//! bnf_state.zig (split from RuntimeState, Phase 4 step 4,
//! docs/GoReady.md) — the `%bnf` grammar-extension bookkeeping.
//! Already reduced to a handful of GC-root fields by Phase 1's lexer
//! rewrite (docs/GoReady.md Phase 1); none of these are read or
//! written anywhere in the current codebase, only traced by the GC as
//! roots in case a future `%bnf` implementation populates them.

const Word = i64;
const CMBASE: Word = 306;
const NIL: Word = CMBASE + 138;

pub const BnfState = struct {
    eprodnts: Word = NIL,
    nonterminals: Word = NIL,
    ntmap: Word = NIL,
    ihlist: Word = 0,
    ntspecmap: Word = NIL,
    lexstates: Word = NIL,
    lexdefs: Word = NIL,
};

var default_state: BnfState = .{};
var active_state: *BnfState = &default_state;

pub fn bind(state: *BnfState) void {
    active_state = state;
}

/// Pointer to the singleton `%bnf` state held in `current_interp` (so
/// `interp.reset()` clears it). Accessed as `bnf_state.bnf().X`.
pub inline fn bnf() *BnfState {
    return active_state;
}

test "BnfState default values are self-consistent" {
    const state: BnfState = .{};
    try @import("std").testing.expectEqual(@as(Word, NIL), state.eprodnts);
    try @import("std").testing.expectEqual(@as(Word, NIL), state.nonterminals);
    try @import("std").testing.expectEqual(@as(Word, NIL), state.ntmap);
    try @import("std").testing.expectEqual(@as(Word, 0), state.ihlist);
    try @import("std").testing.expectEqual(@as(Word, NIL), state.ntspecmap);
    try @import("std").testing.expectEqual(@as(Word, NIL), state.lexstates);
    try @import("std").testing.expectEqual(@as(Word, NIL), state.lexdefs);
}
