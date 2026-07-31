//! script_store.zig (split from RuntimeState, Phase 4 step 4,
//! docs/GoReady.md) — the currently-loaded script's module/name
//! tables: the file lists a load walks and restores on error (`oldfiles`,
//! `includees`, `ld_stuff`, `rfl`), the identifier sets a load produces
//! (`freeids`, `exports`, `embargoes`, `detrop`), small per-load counters
//! (`lastname`, `suppressids`, `col_fn`, `sorted`, `bereaved`), the path of
//! the file currently being compiled (`current_script`), and the `%bnf`
//! free-name-to-type list (`fnts`). `Heap.files` (the file list itself)
//! stays on `Heap` -- it was folded there by an earlier phase (shared-state
//! Phase 2b) and every accessor already reaches it as `heap().files`.

const Word = i64;
const CMBASE: Word = 306;
const NIL: Word = CMBASE + 138;

pub const ScriptStore = struct {
    /// Snapshot of `files` at the start of a load; restored on error.
    oldfiles: Word = NIL,
    includees: Word = NIL,
    freeids: Word = NIL,
    exports: Word = NIL,
    embargoes: Word = NIL,
    lastname: Word = 0,
    suppressids: Word = NIL,
    col_fn: Word = 0,

    sorted: i32 = 0,
    detrop: Word = NIL,
    /// Reload-file list: heap list of file nodes needing re-checking after a change.
    rfl: Word = NIL,
    bereaved: Word = 0,
    ld_stuff: Word = NIL,

    /// Path of the .m file currently being loaded; null outside a load.
    current_script: ?[:0]const u8 = null,

    /// Heap node holding the list of free-name-to-type bindings for %bnf rules.
    fnts: Word = NIL,
};

var default_state: ScriptStore = .{};
var active_state: *ScriptStore = &default_state;

pub fn bind(state: *ScriptStore) void {
    active_state = state;
}

/// Pointer to the singleton script-store state held in `current_interp` (so
/// `interp.reset()` clears it). Accessed as `script_store.store().X`.
pub inline fn store() *ScriptStore {
    return active_state;
}

test "ScriptStore default values are self-consistent" {
    const state: ScriptStore = .{};
    try @import("std").testing.expectEqual(@as(Word, NIL), state.oldfiles);
    try @import("std").testing.expectEqual(@as(Word, NIL), state.freeids);
    try @import("std").testing.expectEqual(@as(Word, NIL), state.detrop);
    try @import("std").testing.expectEqual(@as(Word, NIL), state.rfl);
    try @import("std").testing.expectEqual(@as(Word, NIL), state.fnts);
    try @import("std").testing.expectEqual(@as(?[:0]const u8, null), state.current_script);
}
