const std = @import("std");
const word = @import("../runtime/word.zig");
const Word = word.Word;
const NIL = word.NIL;

pub const CompilerState = struct {
    // From types.zig
    NEW: Word = 0,
    TYPERRS: Word = 0,
    current_id: Word = 0,
    NT: Word = NIL,
    ND: Word = NIL,
    lineptr: Word = 0,
    R: Word = NIL,
    SBND: Word = NIL,
    FBS: Word = NIL,
    ATNAMES: Word = 0,
    TABSTRS: Word = NIL,
    bnf_t: Word = 0,
    meta_pending: Word = NIL,
    SUBST: [512]Word = [_]Word{0} ** 512,
    tvmap: Word = NIL,
    localtvmap: Word = NIL,
    showchain: Word = NIL,
    tvcount: Word = 1,
    lastloc: Word = 0,
    hereinc: Word = 0,
    lasthereinc: Word = 0,
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

    // From trans.zig
    SGC: Word = NIL,
    lfrule: i32 = 0,
    newtyps: Word = NIL,
    polyshowerror: i32 = 0,
    speclocs: Word = NIL,
    was_poly: Word = 0,
    algshfns: Word = NIL,
    rv_script: Word = 0,

    // From heap.zig
    BAD_DUMP: Word = 0,
    CLASHES: Word = 0,
    ALIASES: Word = 0,
    SUPPRESSED: Word = 0,
    TSUPPRESSED: Word = 0,
    TORPHANS: Word = 0,
    DETROP: Word = 0,
    MISSING: Word = 0,
};

pub var cs: CompilerState = .{};
