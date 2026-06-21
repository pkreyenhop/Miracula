const std = @import("std");
const clib = @import("main_clib.zig");

const Word = c_long;
const CMBASE: Word = 306;
const NIL: Word = CMBASE + 138;
const UNDEF: Word = CMBASE + 140;

/// All mutable interpreter state that does not require a C-ABI linker symbol
/// (see main.zig for the 8 vars that must remain as export var due to heap.zig /
/// parser_api.zig circular-import constraints: loading, compiling, nill, errs,
/// errline, obsuffix, SYNERR, commandmode).
pub const RuntimeState = struct {
    // Identity atoms — heap node IDs set by mira_setup(); valid after setup, zero before.
    Void: Word = 0,
    main_id: Word = 0,
    message: Word = 0,
    standardout: Word = 0,
    diagonalise: Word = 0,
    concat: Word = 0,
    indent_fn: Word = 0,
    outdent_fn: Word = 0,
    listdiff_fn: Word = 0,
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
    /// Last identifier referenced interactively; used for `//f` finger command.
    lastid: Word = 0,
    rv_expr: Word = 0,

    // File paths — null-terminated byte arrays populated by startup; treated as C strings.
    PRELUDE: [clib.pnlim + 10]u8 = undefined,
    STDENV: [clib.pnlim + 9]u8 = undefined,

    // Compiler flags (Word-typed because they are linker-visible to lex.zig / trans.zig
    // which CAN switch to @import — no circular constraint, but keep as Word for now)
    /// Heap node holding the list of free-name-to-type bindings for %bnf rules.
    fnts: Word = NIL,
    /// Maximum heap cells before GC triggers; set from `-heap N` CLI flag.
    SPACELIMIT: Word = 2500000,
    /// Dictionary space in bytes; set from `-dic N` CLI flag.
    DICSPACE: Word = 100000,
    UTF8: c_int = 0,
    UTF8OUT: c_int = 0,

    // Configuration — set from CLI flags or .mirarc before mira_setup().
    editor: ?[*:0]u8 = null,
    /// True when the prelude has been accepted without error.
    okprel: bool = false,
    /// True when `-nostandard` flag suppresses loading STDENV.
    nostdenv: bool = false,
    /// Non-zero when the configured editor command is invalid.
    baded: Word = 0,
    miralib: ?[*:0]u8 = null,
    promptstr: [*:0]const u8 = "Miranda ",
    s_in: ?*clib.FILE = null,

    // Runtime counters (all updated by the GC and evaluator; read by //stats).
    atobject: c_int = 0,
    atgc: c_int = 0,
    atcount: c_int = 0,
    debug: c_int = 0,

    // Evaluation control flags
    /// True when building a .mirarc dump; suppresses side-effects.
    magic: bool = false,
    /// True when `//make` is in progress.
    making: bool = false,
    /// True when `//exports` should write an export header.
    mkexports: bool = false,
    mksources: bool = false,
    make_status: Word = 0,
    ideep: c_int = 0,
    /// Non-zero during the one-time startup before `commandloop` begins.
    /// Guards paths that must not repeat (e.g. panic on missing prelude).
    initialising: Word = 1,
    /// Heap list of primitive environment bindings, built by primlib().
    primenv: Word = NIL,
    /// Path of the .m file currently being loaded; null outside a load.
    current_script: ?[*:0]u8 = null,
    lastexp: Word = UNDEF,

    // I/O mode flags
    echoing: Word = 0,
    listing: Word = 0,
    verbosity: Word = 0,
    /// When true, `if` guards are strict (unevaluated guards are errors).
    /// Converted from Word at B1; only ever true/false.
    strictif: bool = true,
    rechecking: Word = 0,
    cstack: ?[*]Word = null,

    // Working buffers — sized for the longest supported pathname (pnlim).
    linebuf: [clib.BUFSIZE]u8 = undefined,
    ebuf: [clib.pnlim]u8 = undefined,
    home_rc: [clib.pnlim + 8]u8 = undefined,
    lib_rc: [clib.pnlim + 8]u8 = undefined,
    /// Non-null when rc_read fails; points into home_rc or lib_rc (not heap-allocated).
    rc_error: ?[*:0]const u8 = null,

    // Signal / longjmp recovery
    /// Recovery point for SIGINT and SIGFPE via siglongjmp().  POSIX signal
    /// handlers are asynchronous (fire on any call stack) and cannot propagate
    /// Zig error unions via stack unwinding.  This sigjmp_buf MUST remain —
    /// it cannot be replaced with error{EvaluationInterrupted}.
    env: clib.sigjmp_buf = .{},
    /// Path of a temp file to unlink if a signal fires during dump/undump.
    unlinkme: ?[*:0]const u8 = null,
    sigflag: c_int = 0,

    // Sorted output and GC-adjacent state
    sorted: c_int = 0,
    detrop: Word = NIL,
    /// Reload-file list: heap list of file nodes needing re-checking after a change.
    rfl: Word = NIL,
    bereaved: Word = 0,
    ld_stuff: Word = NIL,

    // Module / name tables
    /// Snapshot of `files` at the start of a load; restored on error.
    oldfiles: Word = NIL,
    includees: Word = NIL,
    freeids: Word = NIL,
    exports: Word = NIL,
    embargoes: Word = NIL,
    lastname: Word = 0,
    suppressids: Word = NIL,
    col_fn: Word = 0,

    // BNF / lex extension state
    eprodnts: Word = NIL,
    nonterminals: Word = NIL,
    ntmap: Word = NIL,
    ihlist: Word = 0,
    ntspecmap: Word = NIL,
    lexstates: Word = NIL,
    lexdefs: Word = NIL,
};

test "RuntimeState default values are self-consistent" {
    const rs: RuntimeState = .{};
    try std.testing.expectEqual(@as(Word, NIL), rs.detrop);
    try std.testing.expectEqual(@as(Word, NIL), rs.primenv);
    try std.testing.expectEqual(true, rs.strictif);
    try std.testing.expectEqual(@as(Word, 1), rs.initialising);
    try std.testing.expectEqual(@as(Word, 2500000), rs.SPACELIMIT);
}

test "RuntimeState bool fields default to false" {
    const rs: RuntimeState = .{};
    try std.testing.expect(!rs.magic);
    try std.testing.expect(!rs.making);
    try std.testing.expect(!rs.mkexports);
    try std.testing.expect(!rs.mksources);
    try std.testing.expect(!rs.okprel);
    try std.testing.expect(!rs.nostdenv);
}

test "RuntimeState null-initialised optional fields" {
    const rs: RuntimeState = .{};
    try std.testing.expectEqual(@as(?[*:0]u8, null), rs.editor);
    try std.testing.expectEqual(@as(?[*:0]u8, null), rs.current_script);
    try std.testing.expectEqual(@as(?[*:0]const u8, null), rs.rc_error);
    try std.testing.expectEqual(@as(?[*:0]const u8, null), rs.unlinkme);
}
