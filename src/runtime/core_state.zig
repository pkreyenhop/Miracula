/// Core interpreter / error state, kept in this leaf module (no imports from the
/// Miracula source tree — G1 invariant) so that `heap.zig` and `parser_api.zig`
/// can reach it without `@import`-ing `main.zig` and forming a cycle. Callers
/// use `core_state.X` directly. (Historically these were `pub export var` linker
/// symbols with `extern var` re-declarations in `main.zig`; both are gone —
/// plain `pub var` suffices for cross-module Zig access. Shared-state plan
/// Phase 2a folds them into a `CoreState` struct.)
const Word = i64;

/// Heap address of the `nil` combinator (set during mira_setup).
pub var nill: Word = 0;
/// Non-zero while a source file is being loaded (`loadfile` guard).
pub var loading: c_int = 0;
/// Non-zero while compilation of the current script is in progress.
pub var compiling: c_int = 1;
/// Heap node of the first error location in the current compilation unit.
pub var errs: Word = 0;
/// Source line number of the first error (0 = unknown).
pub var errline: Word = 0;
/// Suffix appended to source filenames to form the dump filename (e.g. `"x"`).
pub var obsuffix: [*:0]const u8 = "x";
/// Non-zero when a syntax error has been detected by the parser.
/// 1 = error reported; 2 = error in an %include dependency.
pub var SYNERR: Word = 0;
/// Non-zero when the interpreter is executing a `/`-command (not evaluating).
pub var commandmode: Word = 0;
