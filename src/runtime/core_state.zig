/// Core interpreter / error state, kept in this leaf module (no imports from the
/// Miracula source tree — G1 invariant) so that `heap.zig` and `parser_api.zig`
/// can reach it without `@import`-ing `main.zig` and forming a cycle. Callers
/// use `core_state.X` directly. (Historically these were `pub export var` linker
/// symbols with `extern var` re-declarations in `main.zig`; both are gone —
/// plain `pub var` suffices for cross-module Zig access.)
const Word = i64;

/// Core interpreter / error state, grouped into one struct (shared-state plan
/// Phase 2a). Accessed as `core_state.s.<field>`; folds into `Interp.core` in
/// Phase 3.
pub const CoreState = struct {
    /// Heap address of the `nil` combinator (set during miraSetup).
    nill: Word = 0,
    /// Non-zero while a source file is being loaded (`loadfile` guard).
    loading: c_int = 0,
    /// Non-zero while compilation of the current script is in progress.
    compiling: c_int = 1,
    /// Heap node of the first error location in the current compilation unit.
    errs: Word = 0,
    /// Source line number of the first error (0 = unknown).
    errline: Word = 0,
    /// Suffix appended to source filenames to form the dump filename (e.g. `"x"`).
    obsuffix: [*:0]const u8 = "x",
    /// Non-zero when a syntax error has been detected by the parser.
    /// 1 = error reported; 2 = error in an %include dependency.
    SYNERR: Word = 0,
    /// Non-zero when the interpreter is executing a `/`-command (not evaluating).
    commandmode: Word = 0,
};

/// The process-wide singleton (transitional; becomes `Interp.core` in Phase 3).
pub const s = &@import("interp.zig").interp.core;
