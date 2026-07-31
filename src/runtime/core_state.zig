//! core_state.zig — core interpreter / error state (`loading`,
//! `compiling`, `errs`, `errline`, `SYNERR`, `commandmode`, …), kept in this leaf
//! module (no imports from the Miracula source tree — the G1 acyclic invariant)
//! so that `heap.zig` and `parser_api.zig` can reach it without `@import`-ing
//! `main.zig` and forming a cycle. Callers use `core_state.X` directly.
//! (Historically these were `pub export var` linker symbols with `extern var`
//! re-declarations in `main.zig`; both are gone — plain `pub var` suffices.)

const Word = i64;

/// Core interpreter / error state, grouped into one struct (shared-state plan
/// Phase 2a). Accessed as `core_state.s().<field>`; folds into `Interp.core` in
/// Phase 3.
pub const CoreState = struct {
    /// Non-zero while a source file is being loaded (`loadfile` guard).
    loading: i32 = 0,
    /// Non-zero while compilation of the current script is in progress.
    compiling: i32 = 1,
    /// Heap node of the first error location in the current compilation unit.
    errs: Word = 0,
    /// Source line number of the first error (0 = unknown).
    errline: Word = 0,
    /// Source column number of the first error (0 = unknown).
    errcol: Word = 0,
    /// The first diagnostic's message text (Phase 2 step 2, additive —
    /// alongside `errline`/`errcol`, which already capture its position).
    /// Populated by the native pipeline (`parser_api.zig`) from
    /// `parser/token_filter.zig`'s now-shared `Diagnostic` type; not yet
    /// read by anything. A step toward eventually replacing `errs`'s
    /// "current error position" role (a live heap-cons-cell reference,
    /// so it can't outlive the arena a diagnostics list is collected in)
    /// with something that can — deliberately not attempted in this
    /// narrower slice (`errs` stays exactly as-is, still read/written by
    /// trans.zig/types.zig/reduce.zig/lex.zig's `resetLex`). No import of
    /// `parser/token_filter.zig` here: this file has zero source-tree
    /// imports (the G1 acyclic invariant, see the file's own header) so
    /// `heap.zig`/`parser_api.zig` can reach it without a cycle — callers
    /// copy just the field they need rather than the whole `Diagnostic`.
    last_diagnostic_message: []const u8 = "",
    /// Suffix appended to source filenames to form the dump filename (e.g. `"x"`).
    obsuffix: [*:0]const u8 = "x",
    /// Non-zero when a syntax error has been detected by the parser.
    /// 1 = error reported; 2 = error in an %include dependency.
    SYNERR: Word = 0,
    /// Non-zero when the interpreter is executing a `/`-command (not evaluating).
    commandmode: Word = 0,
};

var default_state: CoreState = .{};
var active_state: *CoreState = &default_state;

pub fn bind(state: *CoreState) void {
    active_state = state;
}

/// Pointer to the singleton `CoreState` inside `current_interp`. Call sites
/// use `core_state.s().X` (or `s().X` via a local alias).
pub inline fn s() *CoreState {
    return active_state;
}
