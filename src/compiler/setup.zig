const std = @import("std");
const main = @import("../main.zig");
const word = @import("../runtime/word.zig");
const abi = @import("../runtime/main_clib.zig");
const heap = @import("../runtime/heap.zig");

const Word = main.Word;
const NIL = main.NIL;

const lex_state = @import("../parser/lex_state.zig");
const r7_types = @import("types.zig");
const r7_lex = @import("../parser/lex.zig");
const r7_big = @import("../runtime/big.zig");
const core_state = @import("../runtime/core_state.zig");
const ls = lex_state.ls;

// Global variables defined/exported in parser/lex.zig

// Exported initialization functions from other modules
const setupheap = heap.setupheap;
const tsetup = r7_types.tsetup;
const resetPns = r7_lex.resetPns;
const bigsetup = r7_big.setup;
const resetLex = r7_lex.resetLex;
// Token names for out2() — replaces y.tab.c's yysterm[].
const yysterm_data = [_]?[*:0]const u8{
    null, // 0: placeholder
    "VALUE", // 1: 257
    "EVAL", // 2: 258
    "where", // 3: WHERE=259
    "if", // 4: IF=260
    "&>", // 5: 261
    "<-", // 6: LEFTARROW=262
    "::", // 7: COLONCOLON=263
    "::=", // 8: COLON2EQ=264
    "TYPEVAR", // 9: TYPEVAR=265
    "NAME", // 10: NAME=266
    "CONSTRUCTOR-NAME", // 11: CNAME=267
    "CONST", // 12: CONST=268
    "$$", // 13: DOLLARS=269
    "OFFSIDE", // 14: OFFSIDE=270
    "OFFSIDE =", // 15: ELSEQ=271
    "abstype", // 16: ABSTYPE=272
    "with", // 17: WITH=273
    "//", // 18: 274
    "==", // 19: EQEQ=275
    "%free", // 20: FREE=276
    "%include", // 21: INCLUDE=277
    "%export", // 22: EXPORT=278
    "type", // 23: TYPE=279
    "otherwise", // 24: OTHERWISE=280
    "show", // 25: SHOWSYM=281
    "PATHNAME", // 26: PATHNAME=282
    "%bnf", // 27: BNF=283
    "%lex", // 28: LEX=284
    "%%", // 29: 285
    "error", // 30: 286
    "end", // 31: 287
    "empty", // 32: 288
    "readvals", // 33: READVALSY=289
    "NAME", // 34: 290
    "`char-class`", // 35: 291
    "`char-class`", // 36: 292
    "%%begin", // 37: 293
    "->", // 38: ARROW=294
    "++", // 39: PLUSPLUS=295
    "--", // 40: MINUSMINUS=296
    "..", // 41: DOTDOT=297
    "\\/", // 42: VEL=298
    ">=", // 43: GE=299
    "~=", // 44: NE=300
    "<=", // 45: LE=301
    "mod", // 46: REM=302
    "div", // 47: DIV=303
    "$NAME", // 48: INFIXNAME=304
    "$CONSTRUCTOR", // 49: INFIXCNAME=305
};
pub var yysterm = yysterm_data;

pub fn syntax(s: [*:0]const u8) void {
    if (core_state.s.SYNERR != 0) return;
    if (main.rs.echoing != 0) {
        _ = word.printErr("\n", .{.{}});
    }
    _ = word.printErr("syntax error: {s}", .{.{s}});
    core_state.s.SYNERR = 1;
    resetLex();
}

pub fn acterror() void {
    if (core_state.s.SYNERR != 0) return;
    core_state.s.SYNERR = 1;
    resetLex();
}

/// Registers a primitive identifier `n` in the private primitive environment (`rs.primenv`).
/// `v` is the combinator value; `t_val` is the type node. Called only from primlib().
pub fn primdef(n: [*:0]const u8, v: Word, t_val: Word) void {
    const x = abi.makeId(@constCast(n));
    main.rs.primenv = main.cons(x, main.rs.primenv);
    main.heap.tp(x).* = v;
    main.heap.tp(main.heap.h(x)).* = t_val;
}

/// Registers a predefined identifier `n` in the global environment.
/// `v` is the combinator value (wrapped in `constructor()` if `n` is a constructor);
/// `t_val` is the type node. Called from privlib() and stdlib().
pub fn predef(n: [*:0]const u8, v: Word, t_val: Word) void {
    const x = abi.makeId(@constCast(n));
    main.addtoenv(x);
    main.heap.tp(x).* = if (main.isconstructor(x)) main.constructor(v, x) else v;
    main.heap.tp(main.heap.h(x)).* = t_val;
}

/// Seeds the primitive type aliases (num, char, bool) and built-in constructors
/// (True, False) into the private primitive environment. Called by miraSetup().
pub fn primlib() void {
    primdef("num", abi.make_typ(0, 0, word.synonym_t, word.num_t), word.type_t);
    primdef("char", abi.make_typ(0, 0, word.synonym_t, word.char_t), word.type_t);
    primdef("bool", abi.make_typ(0, 0, word.synonym_t, word.bool_t), word.type_t);
    primdef("True", 1, word.bool_t);
    primdef("False", 0, word.bool_t);
}

/// Seeds the private-prelude identifiers (offside, changetype, hd/tl, etc.) that are
/// always in scope but not user-visible. Called during prelude loading.
pub fn privlib() void {
    predef("offside", word.OFFSIDE, main.cs.ltchar);
    predef("changetype", word.I, word.wrong_t);
    predef("first", word.HD, word.wrong_t);
    predef("rest", word.TL, word.wrong_t);
    predef("code", word.CODE, word.undef_t);
    predef("concat", abi.ap2(word.FOLDR, word.APPEND, NIL), word.undef_t);
    predef("decode", word.DECODE, word.undef_t);
    predef("drop", word.DROP, word.undef_t);
    predef("error", word.ERROR, word.undef_t);
    predef("filter", word.FILTER, word.undef_t);
    predef("foldr", word.FOLDR, word.undef_t);
    predef("hd", word.HD, word.undef_t);
    predef("map", word.MAP, word.undef_t);
    predef("shownum", word.SHOWNUM, word.undef_t);
    predef("take", word.TAKE, word.undef_t);
    predef("tl", word.TL, word.undef_t);
}

/// Seeds the standard-library identifiers (map, filter, foldr, trig fns, etc.) into
/// the global environment. Called when STDENV is loaded successfully.
pub fn stdlib() void {
    predef("arctan", word.ARCTAN_FN, word.undef_t);
    predef("code", word.CODE, word.undef_t);
    predef("cos", word.COS_FN, word.undef_t);
    predef("decode", word.DECODE, word.undef_t);
    predef("drop", word.DROP, word.undef_t);
    predef("entier", word.ENTIER_FN, word.undef_t);
    predef("error", word.ERROR, word.undef_t);
    predef("exp", word.EXP_FN, word.undef_t);
    predef("filemode", word.FILEMODE, word.undef_t);
    predef("filestat", word.FILESTAT, word.undef_t);
    predef("foldl", word.FOLDL, word.undef_t);
    predef("foldl1", word.FOLDL1, word.undef_t);
    predef("hugenum", abi.stoDbl(abi.DBL_MAX), word.undef_t);
    predef("last", word.LIST_LAST, word.undef_t);
    predef("foldr", word.FOLDR, word.undef_t);
    predef("force", word.FORCE, word.undef_t);
    predef("getenv", word.GETENV, word.undef_t);
    predef("integer", word.INTEGER, word.undef_t);
    predef("log", word.LOG_FN, word.undef_t);
    predef("log10", word.LOG10_FN, word.undef_t);
    predef("merge", word.MERGE, word.undef_t);
    predef("numval", word.NUMVAL, word.undef_t);
    predef("read", word.STARTREAD, word.undef_t);
    predef("readb", word.STARTREADBIN, word.undef_t);
    predef("seq", word.SEQ, word.undef_t);
    predef("shownum", word.SHOWNUM, word.undef_t);
    predef("showhex", word.SHOWHEX, word.undef_t);
    predef("showoct", word.SHOWOCT, word.undef_t);
    predef("showfloat", word.SHOWFLOAT, word.undef_t);
    predef("showscaled", word.SHOWSCALED, word.undef_t);
    predef("sin", word.SIN_FN, word.undef_t);
    predef("sqrt", word.SQRT_FN, word.undef_t);
    predef("system", word.EXEC, word.undef_t);
    predef("take", word.TAKE, word.undef_t);
    predef("tinynum", mktiny(), word.undef_t);
    predef("zip2", word.ZIP, word.undef_t);
}

fn mktiny() Word {
    var x: f64 = 1.0;
    var x1: f64 = x / 2.0;
    while (x1 > 0.0) {
        x = x1;
        x1 = x1 / 2.0;
    }
    return abi.stoDbl(x);
}

/// Performs one-time interpreter initialisation: sets up the heap, type system,
/// dictionary, and parser state, then seeds the primitive environment.
/// Must be called exactly once before any source file is loaded.
pub fn miraSetup() void {
    setupheap();
    tsetup();
    resetPns();
    bigsetup();
    ls.common_stdin = abi.ap(word.READ, 0);
    ls.common_stdinb = abi.ap(word.READBIN, 0);
    ls.cook_stdin = abi.ap(abi.readvals(0, 0), word.OFFSIDE);
    core_state.s.nill = main.cons(word.CONST, NIL);
    main.rs.Void = abi.makeId(@constCast("()"));
    main.heap.tp(main.heap.h(main.rs.Void)).* = word.void_t;
    main.heap.tp(main.rs.Void).* = main.constructor(0, main.rs.Void);
    main.rs.message = abi.makeId(@constCast("sys_message"));
    main.rs.main_id = abi.makeId(@constCast("main"));
    main.rs.concat = abi.makeId(@constCast("concat"));
    main.rs.diagonalise = abi.makeId(@constCast("diagonalise"));
    main.rs.standardout = main.constructor(0, @as([*:0]const u8, "Stdout"));
    main.rs.indent_fn = abi.makeId(@constCast("indent"));
    main.rs.outdent_fn = abi.makeId(@constCast("outdent"));
    main.rs.listdiff_fn = abi.makeId(@constCast("listdiff"));
    main.rs.shownum1 = abi.makeId(@constCast("shownum1"));
    main.rs.showbool = abi.makeId(@constCast("showbool"));
    main.rs.showchar = abi.makeId(@constCast("showchar"));
    main.rs.showlist = abi.makeId(@constCast("showlist"));
    main.rs.showstring = abi.makeId(@constCast("showstring"));
    main.rs.showparen = abi.makeId(@constCast("showparen"));
    main.rs.showpair = abi.makeId(@constCast("showpair"));
    main.rs.showvoid = abi.makeId(@constCast("showvoid"));
    main.rs.showfunction = abi.makeId(@constCast("showfunction"));
    main.rs.showabstract = abi.makeId(@constCast("showabstract"));
    main.rs.showwhat = abi.makeId(@constCast("showwhat"));
    primlib();
}

test "miraSetup initialisation and primitive seeding" {
    abi.setupdic();
    miraSetup();

    // Verify primitives from primlib are seeded correctly
    try std.testing.expect(main.rs.primenv != NIL);
    try std.testing.expect(main.rs.Void != 0);
    try std.testing.expect(main.rs.standardout != 0);
}
