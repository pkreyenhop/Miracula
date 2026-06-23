const word = @import("../runtime/word.zig");
const Word = word.Word;
const NIL = word.NIL;

/// All mutable compiler and typechecker state that does not require a C-ABI
/// linker symbol.  Extracted in H1 from the scattered `export var` globals in
/// `types.zig`, `trans.zig`, and `heap.zig`.
///
/// Accessed via `pub const cs = compiler_state.cs` in `main.zig`.
pub const CompilerState = struct {
    // ── Typechecker (types.zig) ──────────────────────────────────────────────
    /// Fresh type-variable counter; reset at start of each type-check pass.
    NEW: Word = 0,
    /// Number of type errors found in the current compilation unit.
    TYPERRS: Word = 0,
    /// Heap node of the identifier currently being type-checked.
    current_id: Word = 0,
    /// List of non-terminal type definitions (BNF/lex).
    NT: Word = NIL,
    /// List of identifiers whose type is still `wrong_t` (definition failed).
    ND: Word = NIL,
    /// Source-location word for the current declaration being type-checked.
    lineptr: Word = 0,
    /// Temporary result word used inside recursive type matching.
    R: Word = NIL,
    SBND: Word = NIL,
    /// Free-binding-set list for BNF rules.
    FBS: Word = NIL,
    /// Heap list of type atoms (atoms used as type names).
    ATNAMES: Word = 0,
    /// Heap list of constructor–arity pairs for algebraic types.
    TABSTRS: Word = NIL,
    /// Heap node for the `bool` primitive type function.
    bnf_t: Word = 0,
    /// Queue of pending `%rules` meta-annotations to attach.
    meta_pending: Word = NIL,
    /// Substitution array for unification; index by type-variable number.
    SUBST: [512]Word = [_]Word{0} ** 512,
    /// Current unification substitution map (heap list).
    tvmap: Word = NIL,
    localtvmap: Word = NIL,
    showchain: Word = NIL,
    /// Next fresh type-variable number to allocate.
    tvcount: Word = 1,
    lastloc: Word = 0,
    hereinc: Word = 0,
    lasthereinc: Word = 0,
    // Built-in type functions (set during mira_setup):
    tfnum: Word = 0,
    tfbool: Word = 0,
    tfbool2: Word = 0,
    tfnum2: Word = 0,
    tfstrstr: Word = 0,
    tfnumnum: Word = 0,
    ltchar: Word = 0,
    tstep: Word = 0,
    tstepuntil: Word = 0,
    exec_t: Word = 0,
    read_t: Word = 0,
    filestat_t: Word = 0,

    // ── Translator (trans.zig) ───────────────────────────────────────────────
    /// Heap list of algebraic-type constructor sets, used for irrefutability.
    SGC: Word = NIL,
    /// Count of common left-factors found by the grammar optimiser.
    lfrule: i32 = 0,
    /// Heap list of newly-defined type names in the current load.
    newtyps: Word = NIL,
    /// Non-zero when a polymorphic `show` error has been reported.
    polyshowerror: i32 = 0,
    /// Heap list of source-location annotations for type-error reporting.
    speclocs: Word = NIL,
    was_poly: Word = 0,
    /// Heap list of algebraic-type head functions (for `show`/`output`).
    algshfns: Word = NIL,
    /// Heap node of the script currently being reduced for `//recheck`.
    rv_script: Word = 0,

    // ── Heap / dump integrity (heap.zig) ────────────────────────────────────
    /// Non-zero when the current .x dump was written by a different mira version.
    BAD_DUMP: Word = 0,
    /// Count of name clashes detected during module loading.
    CLASHES: Word = 0,
    /// Heap list of alias bindings introduced by `%include`.
    ALIASES: Word = 0,
    SUPPRESSED: Word = 0,
    /// Heap list of type names suppressed by privacy rules.
    TSUPPRESSED: Word = 0,
    TORPHANS: Word = 0,
    /// Heap list of identifiers that became undefined after a reload.
    DETROP: Word = 0,
    /// Heap list of identifiers referenced but not found during load.
    MISSING: Word = 0,
};

/// Singleton compiler-state instance.  Access via `main.cs` (a `*CompilerState`
/// pointer alias) so all mutations are reflected everywhere.
pub const cs = &@import("../runtime/interp.zig").interp.comp;
