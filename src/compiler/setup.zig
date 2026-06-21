const std = @import("std");
const main = @import("../main.zig");
const clib = @import("../runtime/main_clib.zig");
const heap = @import("../runtime/heap.zig");

const Word = main.Word;
const NIL = main.NIL;

const lex_state = @import("../parser/lex_state.zig");
const ls = &lex_state.ls;

// Global variables defined/exported in parser/lex.zig

// Exported initialization functions from other modules
const setupheap = heap.setupheap;
extern fn tsetup() void;
extern fn reset_pns() void;
extern fn bigsetup() void;
extern fn reset_lex() void;

// Token names for out2() — replaces y.tab.c's yysterm[].
const yysterm_data = [_]?[*:0]const u8{
    null,                  // 0: placeholder
    "VALUE",               // 1: 257
    "EVAL",                // 2: 258
    "where",               // 3: WHERE=259
    "if",                  // 4: IF=260
    "&>",                  // 5: 261
    "<-",                  // 6: LEFTARROW=262
    "::",                  // 7: COLONCOLON=263
    "::=",                 // 8: COLON2EQ=264
    "TYPEVAR",             // 9: TYPEVAR=265
    "NAME",                // 10: NAME=266
    "CONSTRUCTOR-NAME",    // 11: CNAME=267
    "CONST",               // 12: CONST=268
    "$$",                  // 13: DOLLARS=269
    "OFFSIDE",             // 14: OFFSIDE=270
    "OFFSIDE =",           // 15: ELSEQ=271
    "abstype",             // 16: ABSTYPE=272
    "with",                // 17: WITH=273
    "//",                  // 18: 274
    "==",                  // 19: EQEQ=275
    "%free",               // 20: FREE=276
    "%include",            // 21: INCLUDE=277
    "%export",             // 22: EXPORT=278
    "type",                // 23: TYPE=279
    "otherwise",           // 24: OTHERWISE=280
    "show",                // 25: SHOWSYM=281
    "PATHNAME",            // 26: PATHNAME=282
    "%bnf",                // 27: BNF=283
    "%lex",                // 28: LEX=284
    "%%",                  // 29: 285
    "error",               // 30: 286
    "end",                 // 31: 287
    "empty",               // 32: 288
    "readvals",            // 33: READVALSY=289
    "NAME",                // 34: 290
    "`char-class`",        // 35: 291
    "`char-class`",        // 36: 292
    "%%begin",             // 37: 293
    "->",                  // 38: ARROW=294
    "++",                  // 39: PLUSPLUS=295
    "--",                  // 40: MINUSMINUS=296
    "..",                  // 41: DOTDOT=297
    "\\/",                 // 42: VEL=298
    ">=",                  // 43: GE=299
    "~=",                  // 44: NE=300
    "<=",                  // 45: LE=301
    "mod",                 // 46: REM=302
    "div",                 // 47: DIV=303
    "$NAME",               // 48: INFIXNAME=304
    "$CONSTRUCTOR",        // 49: INFIXCNAME=305
};
export var yysterm = yysterm_data;

export fn syntax(s: [*:0]const u8) void {
    if (main.SYNERR != 0) return;
    if (main.rs.echoing != 0) {
        _ = clib.fprintf(main.getStderr().?, "\n", .{.{}});
    }
    _ = clib.fprintf(main.getStderr().?, "syntax error: %s", .{.{s}});
    main.SYNERR = 1;
    reset_lex();
}

export fn acterror() void {
    if (main.SYNERR != 0) return;
    main.SYNERR = 1;
    reset_lex();
}

/// Registers a primitive identifier `n` in the private primitive environment (`rs.primenv`).
/// `v` is the combinator value; `t_val` is the type node. Called only from primlib().
pub fn primdef(n: [*:0]const u8, v: Word, t_val: Word) void {
    const x = clib.make_id(@constCast(n));
    main.rs.primenv = main.cons(x, main.rs.primenv);
    main.heap.tp(x).* = v;
    main.heap.tp(main.heap.h(x)).* = t_val;
}

/// Registers a predefined identifier `n` in the global environment.
/// `v` is the combinator value (wrapped in `constructor()` if `n` is a constructor);
/// `t_val` is the type node. Called from privlib() and stdlib().
pub fn predef(n: [*:0]const u8, v: Word, t_val: Word) void {
    const x = clib.make_id(@constCast(n));
    main.addtoenv(x);
    main.heap.tp(x).* = if (main.isconstructor(x)) main.constructor(v, x) else v;
    main.heap.tp(main.heap.h(x)).* = t_val;
}

/// Seeds the primitive type aliases (num, char, bool) and built-in constructors
/// (True, False) into the private primitive environment. Called by mira_setup().
pub fn primlib() void {
    primdef("num", clib.make_typ(0, 0, clib.synonym_t, clib.num_t), clib.type_t);
    primdef("char", clib.make_typ(0, 0, clib.synonym_t, clib.char_t), clib.type_t);
    primdef("bool", clib.make_typ(0, 0, clib.synonym_t, clib.bool_t), clib.type_t);
    primdef("True", 1, clib.bool_t);
    primdef("False", 0, clib.bool_t);
}

/// Seeds the private-prelude identifiers (offside, changetype, hd/tl, etc.) that are
/// always in scope but not user-visible. Called during prelude loading.
pub fn privlib() void {
    predef("offside", clib.OFFSIDE, main.cs.ltchar);
    predef("changetype", clib.I, clib.wrong_t);
    predef("first", clib.HD, clib.wrong_t);
    predef("rest", clib.TL, clib.wrong_t);
    predef("code", clib.CODE, clib.undef_t);
    predef("concat", clib.ap2(clib.FOLDR, clib.APPEND, NIL), clib.undef_t);
    predef("decode", clib.DECODE, clib.undef_t);
    predef("drop", clib.DROP, clib.undef_t);
    predef("error", clib.ERROR, clib.undef_t);
    predef("filter", clib.FILTER, clib.undef_t);
    predef("foldr", clib.FOLDR, clib.undef_t);
    predef("hd", clib.HD, clib.undef_t);
    predef("map", clib.MAP, clib.undef_t);
    predef("shownum", clib.SHOWNUM, clib.undef_t);
    predef("take", clib.TAKE, clib.undef_t);
    predef("tl", clib.TL, clib.undef_t);
}

/// Seeds the standard-library identifiers (map, filter, foldr, trig fns, etc.) into
/// the global environment. Called when STDENV is loaded successfully.
pub fn stdlib() void {
    predef("arctan", clib.ARCTAN_FN, clib.undef_t);
    predef("code", clib.CODE, clib.undef_t);
    predef("cos", clib.COS_FN, clib.undef_t);
    predef("decode", clib.DECODE, clib.undef_t);
    predef("drop", clib.DROP, clib.undef_t);
    predef("entier", clib.ENTIER_FN, clib.undef_t);
    predef("error", clib.ERROR, clib.undef_t);
    predef("exp", clib.EXP_FN, clib.undef_t);
    predef("filemode", clib.FILEMODE, clib.undef_t);
    predef("filestat", clib.FILESTAT, clib.undef_t);
    predef("foldl", clib.FOLDL, clib.undef_t);
    predef("foldl1", clib.FOLDL1, clib.undef_t);
    predef("hugenum", clib.sto_dbl(clib.DBL_MAX), clib.undef_t);
    predef("last", clib.LIST_LAST, clib.undef_t);
    predef("foldr", clib.FOLDR, clib.undef_t);
    predef("force", clib.FORCE, clib.undef_t);
    predef("getenv", clib.GETENV, clib.undef_t);
    predef("integer", clib.INTEGER, clib.undef_t);
    predef("log", clib.LOG_FN, clib.undef_t);
    predef("log10", clib.LOG10_FN, clib.undef_t);
    predef("merge", clib.MERGE, clib.undef_t);
    predef("numval", clib.NUMVAL, clib.undef_t);
    predef("read", clib.STARTREAD, clib.undef_t);
    predef("readb", clib.STARTREADBIN, clib.undef_t);
    predef("seq", clib.SEQ, clib.undef_t);
    predef("shownum", clib.SHOWNUM, clib.undef_t);
    predef("showhex", clib.SHOWHEX, clib.undef_t);
    predef("showoct", clib.SHOWOCT, clib.undef_t);
    predef("showfloat", clib.SHOWFLOAT, clib.undef_t);
    predef("showscaled", clib.SHOWSCALED, clib.undef_t);
    predef("sin", clib.SIN_FN, clib.undef_t);
    predef("sqrt", clib.SQRT_FN, clib.undef_t);
    predef("system", clib.EXEC, clib.undef_t);
    predef("take", clib.TAKE, clib.undef_t);
    predef("tinynum", mktiny(), clib.undef_t);
    predef("zip2", clib.ZIP, clib.undef_t);
}

fn mktiny() Word {
    var x: f64 = 1.0;
    var x1: f64 = x / 2.0;
    while (x1 > 0.0) {
        x = x1;
        x1 = x1 / 2.0;
    }
    return clib.sto_dbl(x);
}

/// Performs one-time interpreter initialisation: sets up the heap, type system,
/// dictionary, and parser state, then seeds the primitive environment.
/// Must be called exactly once before any source file is loaded.
pub fn mira_setup() void {
    setupheap();
    tsetup();
    reset_pns();
    bigsetup();
    ls.common_stdin = clib.ap(clib.READ, 0);
    ls.common_stdinb = clib.ap(clib.READBIN, 0);
    ls.cook_stdin = clib.ap(clib.readvals(0, 0), clib.OFFSIDE);
    main.nill = main.cons(clib.CONST, NIL);
    main.rs.Void = clib.make_id(@constCast("()"));
    main.heap.tp(main.heap.h(main.rs.Void)).* = clib.void_t;
    main.heap.tp(main.rs.Void).* = main.constructor(0, main.rs.Void);
    main.rs.message = clib.make_id(@constCast("sys_message"));
    main.rs.main_id = clib.make_id(@constCast("main"));
    main.rs.concat = clib.make_id(@constCast("concat"));
    main.rs.diagonalise = clib.make_id(@constCast("diagonalise"));
    main.rs.standardout = main.constructor(0, @as([*:0]const u8, "Stdout"));
    main.rs.indent_fn = clib.make_id(@constCast("indent"));
    main.rs.outdent_fn = clib.make_id(@constCast("outdent"));
    main.rs.listdiff_fn = clib.make_id(@constCast("listdiff"));
    main.rs.shownum1 = clib.make_id(@constCast("shownum1"));
    main.rs.showbool = clib.make_id(@constCast("showbool"));
    main.rs.showchar = clib.make_id(@constCast("showchar"));
    main.rs.showlist = clib.make_id(@constCast("showlist"));
    main.rs.showstring = clib.make_id(@constCast("showstring"));
    main.rs.showparen = clib.make_id(@constCast("showparen"));
    main.rs.showpair = clib.make_id(@constCast("showpair"));
    main.rs.showvoid = clib.make_id(@constCast("showvoid"));
    main.rs.showfunction = clib.make_id(@constCast("showfunction"));
    main.rs.showabstract = clib.make_id(@constCast("showabstract"));
    main.rs.showwhat = clib.make_id(@constCast("showwhat"));
    primlib();
}

test "mira_setup initialisation and primitive seeding" {
    clib.setupdic();
    mira_setup();

    // Verify primitives from primlib are seeded correctly
    try std.testing.expect(main.rs.primenv != NIL);
    try std.testing.expect(main.rs.Void != 0);
    try std.testing.expect(main.rs.standardout != 0);
}
