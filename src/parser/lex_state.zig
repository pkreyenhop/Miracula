//! lex_state.zig — the lexer's session state (`LexState`): the dictionary, the
//! file / margin / layout stacks, the identifier name buckets, and the scan
//! cursors. Folded into `interp.lex` so `interp.reset()` clears it; accessed as
//! `ls.X`.

const std = @import("std");

/// The interpreter machine word (see `word.Word`).
pub const Word = i64;
const CMBASE: Word = 306;
/// The empty-list sentinel (mirrors `word.NIL`).
pub const NIL: Word = CMBASE + 138;

/// The lexer's session state — the dictionary, the file/margin/layout stacks,
/// the name buckets, and the scan cursors. Folded into `interp.lex` so
/// `interp.reset()` clears it; accessed as `ls.X`.
pub const LexState = struct {
    fileq: Word = NIL,
    margstack: Word = NIL,
    col: Word = 0,
    vergstack: Word = NIL,
    line_no: Word = 0,
    litstack: Word = NIL,
    linostack: Word = NIL,
    c: Word = ' ',
    common_stdin: Word = 0,
    common_stdinb: Word = 0,
    cook_stdin: Word = 0,
    gvars: Word = NIL,
    lexvar: Word = 0,
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

    // Lexer session state absorbed from `lex.zig`'s module globals (shared-state
    // plan) so it lives in `interp.lex` and `interp.reset()` covers it — needed
    // for clean test isolation (e.g. the `prefix`/`inprelude` machinery).
    lverge: Word = 0,
    prefixbase: ?[*]u8 = null,
    prefixlimit: Word = 1024,
    prefix: Word = 0,
    lastline: Word = 0,
    litmain: Word = 0,
    literate: Word = 0,
    brct: Word = 0,
    inprelude: bool = true,
    pn_lim: Word = 200,
    atnl: Word = 1,
    rdline_linebuf: [1024]u8 = std.mem.zeroes([1024]u8),
};

/// Pointer to the singleton [LexState] held in `current_interp` (so
/// `interp.reset()` clears it). Accessed as `ls().X`.
pub inline fn ls() *LexState {
    return &@import("../runtime/interp.zig").current_interp.lex;
}
