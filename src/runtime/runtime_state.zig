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
    // Identity atoms set by mira_setup()
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
    lastid: Word = 0,
    rv_expr: Word = 0,

    // File paths (populated at startup)
    PRELUDE: [clib.pnlim + 10]u8 = undefined,
    STDENV: [clib.pnlim + 9]u8 = undefined,

    // Compiler flags (Word-typed because they are linker-visible to lex.zig / trans.zig
    // which CAN switch to @import — no circular constraint, but keep as Word for now)
    fnts: Word = NIL,
    SPACELIMIT: Word = 2500000,
    DICSPACE: Word = 100000,
    UTF8: c_int = 0,
    UTF8OUT: c_int = 0,

    // Configuration (set from CLI / .mirarc before mira_setup)
    editor: ?[*:0]u8 = null,
    okprel: Word = 0,
    nostdenv: Word = 0,
    baded: Word = 0,
    miralib: ?[*:0]u8 = null,
    promptstr: [*:0]const u8 = "Miranda ",
    s_in: ?*clib.FILE = null,

    // Runtime counters
    atobject: c_int = 0,
    atgc: c_int = 0,
    atcount: c_int = 0,
    debug: c_int = 0,

    // Evaluation control flags
    magic: Word = 0,
    making: Word = 0,
    mkexports: Word = 0,
    mksources: Word = 0,
    make_status: Word = 0,
    ideep: c_int = 0,
    initialising: Word = 1,
    primenv: Word = NIL,
    current_script: ?[*:0]u8 = null,
    lastexp: Word = UNDEF,

    // I/O mode flags
    echoing: Word = 0,
    listing: Word = 0,
    verbosity: Word = 0,
    strictif: bool = true, // bool conversion from Word (only boolean use)
    rechecking: Word = 0,
    cstack: ?[*]Word = null,

    // Working buffers
    linebuf: [clib.BUFSIZE]u8 = undefined,
    ebuf: [clib.pnlim]u8 = undefined,
    home_rc: [clib.pnlim + 8]u8 = undefined,
    lib_rc: [clib.pnlim + 8]u8 = undefined,
    rc_error: ?[*:0]const u8 = null,

    // Signal / longjmp recovery
    env: clib.sigjmp_buf = .{},
    unlinkme: ?[*:0]const u8 = null,
    sigflag: c_int = 0,

    // Sorted output and GC-adjacent state
    sorted: c_int = 0,
    detrop: Word = NIL,
    rfl: Word = NIL,
    bereaved: Word = 0,
    ld_stuff: Word = NIL,

    // Module / name tables
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
