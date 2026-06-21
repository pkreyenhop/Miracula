/// C-ABI-constrained global state that must remain as `export var` linker
/// symbols.  These cannot live in `RuntimeState` because `heap.zig` and
/// `parser_api.zig` access them and cannot `@import main.zig` without
/// creating a circular dependency.
///
/// Leaf module — no imports from the Miracula source tree (G1 invariant).
/// `main.zig` re-declares each as `pub extern var` so callers using `main.X`
/// continue to compile unchanged.
const Word = c_long;

/// Heap address of the `nil` combinator (set during mira_setup).
pub export var nill: Word = 0;
/// Non-zero while a source file is being loaded (`loadfile` guard).
pub export var loading: c_int = 0;
/// Non-zero while compilation of the current script is in progress.
pub export var compiling: c_int = 1;
/// Heap node of the first error location in the current compilation unit.
pub export var errs: Word = 0;
/// Source line number of the first error (0 = unknown).
pub export var errline: Word = 0;
/// Suffix appended to source filenames to form the dump filename (e.g. `"x"`).
pub export var obsuffix: [*:0]const u8 = "x";
/// Non-zero when a syntax error has been detected by the parser.
/// 1 = error reported; 2 = error in an %include dependency.
pub export var SYNERR: Word = 0;
/// Non-zero when the interpreter is executing a `/`-command (not evaluating).
pub export var commandmode: Word = 0;
