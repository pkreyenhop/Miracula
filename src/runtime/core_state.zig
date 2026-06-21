/// C-ABI-constrained global state accessed by heap.zig and parser_api.zig.
/// Leaf module — no imports from the Miracula source tree.
/// Extracted in G1 to break the heap.zig ↔ main.zig circular dependency.
const Word = c_long;

pub export var nill: Word = 0;
pub export var loading: c_int = 0;
pub export var compiling: c_int = 1;
pub export var errs: Word = 0;
pub export var errline: Word = 0;
pub export var obsuffix: [*:0]const u8 = "x";
pub export var SYNERR: Word = 0;
pub export var commandmode: Word = 0;
