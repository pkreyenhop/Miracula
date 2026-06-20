const std = @import("std");
const main = @import("../main.zig");
const clib = @import("../runtime/main_clib.zig");

const Word = main.Word;
const NIL = main.NIL;

// Global variables defined/exported in parser/lex.zig
extern var common_stdin: Word;
extern var common_stdinb: Word;
extern var cook_stdin: Word;

// Exported initialization functions from other modules
extern fn setupheap() void;
extern fn tsetup() void;
extern fn reset_pns() void;
extern fn bigsetup() void;

pub fn primdef(n: [*:0]const u8, v: Word, t_val: Word) void {
    const x = clib.make_id(@constCast(n));
    main.primenv = main.cons(x, main.primenv);
    main.tp(x).* = v;
    main.tp(main.h(x)).* = t_val;
}

pub fn predef(n: [*:0]const u8, v: Word, t_val: Word) void {
    const x = clib.make_id(@constCast(n));
    main.addtoenv(x);
    main.tp(x).* = if (main.isconstructor(x)) main.constructor(v, x) else v;
    main.tp(main.h(x)).* = t_val;
}

pub fn primlib() void {
    primdef("num", clib.make_typ(0, 0, clib.synonym_t, clib.num_t), clib.type_t);
    primdef("char", clib.make_typ(0, 0, clib.synonym_t, clib.char_t), clib.type_t);
    primdef("bool", clib.make_typ(0, 0, clib.synonym_t, clib.bool_t), clib.type_t);
    primdef("True", 1, clib.bool_t);
    primdef("False", 0, clib.bool_t);
}

pub fn privlib() void {
    predef("offside", clib.OFFSIDE, clib.ltchar);
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
    predef("tinynum", main.mktiny(), clib.undef_t);
    predef("zip2", clib.ZIP, clib.undef_t);
}

pub fn mira_setup() void {
    setupheap();
    tsetup();
    reset_pns();
    bigsetup();
    common_stdin = clib.ap(clib.READ, 0);
    common_stdinb = clib.ap(clib.READBIN, 0);
    cook_stdin = clib.ap(clib.readvals(0, 0), clib.OFFSIDE);
    main.nill = main.cons(clib.CONST, NIL);
    main.Void = clib.make_id(@constCast("()"));
    main.tp(main.h(main.Void)).* = clib.void_t;
    main.tp(main.Void).* = main.constructor(0, main.Void);
    main.message = clib.make_id(@constCast("sys_message"));
    main.main_id = clib.make_id(@constCast("main"));
    main.concat = clib.make_id(@constCast("concat"));
    main.diagonalise = clib.make_id(@constCast("diagonalise"));
    main.standardout = main.constructor(0, @as([*:0]const u8, "Stdout"));
    main.indent_fn = clib.make_id(@constCast("indent"));
    main.outdent_fn = clib.make_id(@constCast("outdent"));
    main.listdiff_fn = clib.make_id(@constCast("listdiff"));
    main.shownum1 = clib.make_id(@constCast("shownum1"));
    main.showbool = clib.make_id(@constCast("showbool"));
    main.showchar = clib.make_id(@constCast("showchar"));
    main.showlist = clib.make_id(@constCast("showlist"));
    main.showstring = clib.make_id(@constCast("showstring"));
    main.showparen = clib.make_id(@constCast("showparen"));
    main.showpair = clib.make_id(@constCast("showpair"));
    main.showvoid = clib.make_id(@constCast("showvoid"));
    main.showfunction = clib.make_id(@constCast("showfunction"));
    main.showabstract = clib.make_id(@constCast("showabstract"));
    main.showwhat = clib.make_id(@constCast("showwhat"));
    primlib();
}

test "mira_setup initialisation and primitive seeding" {
    clib.setupdic();
    mira_setup();

    // Verify primitives from primlib are seeded correctly
    try std.testing.expect(main.primenv != NIL);
    try std.testing.expect(main.Void != 0);
    try std.testing.expect(main.standardout != 0);
}
