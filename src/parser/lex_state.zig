const std = @import("std");

pub const Word = c_long;
const CMBASE: Word = 306;
pub const NIL: Word = CMBASE + 138;

pub const LexState = struct {
    fileq: Word = NIL,
    margstack: Word = NIL,
    col: Word = 0,
    tok_start_col: Word = 0,
    vergstack: Word = NIL,
    line_no: Word = 0,
    litstack: Word = NIL,
    linostack: Word = NIL,
    c: Word = ' ',
    common_stdin: Word = 0,
    common_stdinb: Word = 0,
    cook_stdin: Word = 0,
    blankerr: c_int = 0,
    gvars: Word = NIL,
    lexvar: Word = 0,
    namebucket: [128]Word = std.mem.zeroes([128]Word),
    nextpn: Word = 0,
    pnvec: ?[*]Word = null,
    dic: ?[*]u8 = null,
    dicp: [*:0]u8 = undefined,
    dicq: [*:0]u8 = undefined,
    insertdepth: Word = -1,
    lmargin: Word = 0,
    echostack: Word = NIL,
    prefixstack: Word = NIL,
    inbnf: Word = 0,
    inlex: Word = 0,
    sreds: Word = 0,
    exportfiles: Word = NIL,
    inexplist: Word = 0,
    idsused: Word = NIL,
    ARGC: c_int = 0,
    ARGV: [*]?[*:0]u8 = undefined,
    yylval: Word = NIL,
};

pub var ls: LexState = .{};
