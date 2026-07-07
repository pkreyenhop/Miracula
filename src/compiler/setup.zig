//! setup.zig — interpreter initialisation. `miraSetup` brings up the heap, the
//! dictionary, and the primitive environment from a cold start; `primlib`,
//! `privlib`, and `stdlib` seed the built-in primitives and the standard-library
//! definitions (via `primdef`/`predef`).

const std = @import("std");
const rt = @import("../runtime/runtime_state.zig");
const cs = @import("compiler_state.zig").cs;
const word = @import("../graph/word.zig");
const abi = @import("../os.zig");
const heap_mod = @import("../runtime/heap.zig");
const Heap = heap_mod.Heap;
const errors = @import("../runtime/errors.zig");

const Word = word.Word;
const NIL = word.NIL;

const lex_state = @import("../parser/lex_state.zig");
const types = @import("types.zig");
const lex = @import("../parser/lex.zig");
const big = @import("../graph/bignum.zig");
const core_state = @import("../runtime/core_state.zig");
const ls = lex_state.ls;

// Global variables defined/exported in parser/lex.zig

// Exported initialization functions from other modules
const setupheap = heap_mod.setupheap;
const tsetup = types.tsetup;
const resetPns = lex.resetPns;
const bigsetup = big.setup;
const resetLex = lex.resetLex;
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
/// The terminal-symbol name table (token code → display name), used in syntax-error messages.
pub const yysterm = yysterm_data;

/// Report a syntax error `s`: print the location, set `SYNERR`, and return
/// `error.SyntaxError` (Phase 3 step 5, docs/ZIG_NATIVE_PLAN.md — callers
/// that already gate on `SYNERR` afterward can keep doing so via `catch {}`;
/// callers that want an honest fallible contract can `try`/propagate it).
pub fn syntax(s: [*:0]const u8) errors.MiraError!void {
    if (core_state.s().SYNERR != 0) return error.SyntaxError;
    if (!@import("builtin").is_test) {
        if (rt.rs().echoing != 0) {
            _ = word.printErr("\n", .{});
        }
        _ = word.printErr("syntax error: {s}", .{s});
    }
    core_state.s().SYNERR = 1;
    resetLex(heap_mod.heap());
    return error.SyntaxError;
}

/// Flag a grammar-action error (set `SYNERR`, reset the lexer, and return
/// `error.SyntaxError` -- see `syntax`'s doc comment).
pub fn acterror() errors.MiraError!void {
    if (core_state.s().SYNERR != 0) return error.SyntaxError;
    core_state.s().SYNERR = 1;
    resetLex(heap_mod.heap());
    return error.SyntaxError;
}

/// Registers a primitive identifier `n` in the private primitive environment (`rs.primenv`).
/// `v` is the combinator value; `t_val` is the type node. Called only from primlib().
pub fn primdef(heap: *Heap, n: [*:0]const u8, v: Word, t_val: Word) void {
    const x = abi.makeId(@constCast(n));
    rt.rs().primenv = heap.cons(x, rt.rs().primenv);
    heap.tp(x).* = v;
    heap.tp(heap.h(x)).* = t_val;
}

/// Registers a predefined identifier `n` in the global environment.
/// `v` is the combinator value (wrapped in `constructor()` if `n` is a constructor);
/// `t_val` is the type node. Called from privlib() and stdlib().
pub fn predef(heap: *Heap, n: [*:0]const u8, v: Word, t_val: Word) void {
    const x = abi.makeId(@constCast(n));
    heap_mod.addtoenv(heap, x);
    heap.tp(x).* = if (heap_mod.isconstructor(heap.*, x)) heap_mod.constructor(heap, v, x) else v;
    heap.tp(heap.h(x)).* = t_val;
}

/// Seeds the primitive type aliases (num, char, bool) and built-in constructors
/// (True, False) into the private primitive environment. Called by miraSetup().
pub fn primlib(heap: *Heap) void {
    primdef(heap, "num", abi.make_typ(0, 0, word.synonym_t, word.num_t), word.type_t);
    primdef(heap, "char", abi.make_typ(0, 0, word.synonym_t, word.char_t), word.type_t);
    primdef(heap, "bool", abi.make_typ(0, 0, word.synonym_t, word.bool_t), word.type_t);
    primdef(heap, "True", 1, word.bool_t);
    primdef(heap, "False", 0, word.bool_t);
}

/// Seeds the private-prelude identifiers (offside, changetype, hd/tl, etc.) that are
/// always in scope but not user-visible. Called during prelude loading.
pub fn privlib(heap: *Heap) void {
    predef(heap, "offside", word.OFFSIDE, cs().ltchar);
    predef(heap, "changetype", word.I, word.wrong_t);
    predef(heap, "first", word.HD, word.wrong_t);
    predef(heap, "rest", word.TL, word.wrong_t);
    predef(heap, "code", word.CODE, word.undef_t);
    predef(heap, "concat", abi.ap2(word.FOLDR, word.APPEND, NIL), word.undef_t);
    predef(heap, "decode", word.DECODE, word.undef_t);
    predef(heap, "drop", word.DROP, word.undef_t);
    predef(heap, "error", word.ERROR, word.undef_t);
    predef(heap, "filter", word.FILTER, word.undef_t);
    predef(heap, "foldr", word.FOLDR, word.undef_t);
    predef(heap, "hd", word.HD, word.undef_t);
    predef(heap, "map", word.MAP, word.undef_t);
    predef(heap, "shownum", word.SHOWNUM, word.undef_t);
    predef(heap, "take", word.TAKE, word.undef_t);
    predef(heap, "tl", word.TL, word.undef_t);
}

/// Seeds the standard-library identifiers (map, filter, foldr, trig fns, etc.) into
/// the global environment. Called when STDENV is loaded successfully.
pub fn stdlib(heap: *Heap) void {
    predef(heap, "arctan", word.ARCTAN_FN, word.undef_t);
    predef(heap, "code", word.CODE, word.undef_t);
    predef(heap, "cos", word.COS_FN, word.undef_t);
    predef(heap, "decode", word.DECODE, word.undef_t);
    predef(heap, "drop", word.DROP, word.undef_t);
    predef(heap, "entier", word.ENTIER_FN, word.undef_t);
    predef(heap, "error", word.ERROR, word.undef_t);
    predef(heap, "exp", word.EXP_FN, word.undef_t);
    predef(heap, "filemode", word.FILEMODE, word.undef_t);
    predef(heap, "filestat", word.FILESTAT, word.undef_t);
    predef(heap, "foldl", word.FOLDL, word.undef_t);
    predef(heap, "foldl1", word.FOLDL1, word.undef_t);
    predef(heap, "hugenum", abi.stoDbl(abi.DBL_MAX) catch unreachable, word.undef_t);
    predef(heap, "last", word.LIST_LAST, word.undef_t);
    predef(heap, "foldr", word.FOLDR, word.undef_t);
    predef(heap, "force", word.FORCE, word.undef_t);
    predef(heap, "getenv", word.GETENV, word.undef_t);
    predef(heap, "integer", word.INTEGER, word.undef_t);
    predef(heap, "log", word.LOG_FN, word.undef_t);
    predef(heap, "log10", word.LOG10_FN, word.undef_t);
    predef(heap, "merge", word.MERGE, word.undef_t);
    predef(heap, "numval", word.NUMVAL, word.undef_t);
    predef(heap, "read", word.STARTREAD, word.undef_t);
    predef(heap, "readb", word.STARTREADBIN, word.undef_t);
    predef(heap, "seq", word.SEQ, word.undef_t);
    predef(heap, "shownum", word.SHOWNUM, word.undef_t);
    predef(heap, "showhex", word.SHOWHEX, word.undef_t);
    predef(heap, "showoct", word.SHOWOCT, word.undef_t);
    predef(heap, "showfloat", word.SHOWFLOAT, word.undef_t);
    predef(heap, "showscaled", word.SHOWSCALED, word.undef_t);
    predef(heap, "sin", word.SIN_FN, word.undef_t);
    predef(heap, "sqrt", word.SQRT_FN, word.undef_t);
    predef(heap, "system", word.EXEC, word.undef_t);
    predef(heap, "take", word.TAKE, word.undef_t);
    predef(heap, "tinynum", mktiny(), word.undef_t);
    predef(heap, "zip2", word.ZIP, word.undef_t);
}

/// The smallest positive double the host represents, as a `DOUBLE` node (for `tiny`).
fn mktiny() Word {
    var x: f64 = 1.0;
    var x1: f64 = x / 2.0;
    while (x1 > 0.0) {
        x = x1;
        x1 = x1 / 2.0;
    }
    return abi.stoDbl(x) catch unreachable;
}

/// Performs one-time interpreter initialisation: sets up the heap, type system,
/// dictionary, and parser state, then seeds the primitive environment.
/// Must be called exactly once before any source file is loaded.
pub fn miraSetup() void {
    const heap = heap_mod.heap();
    setupheap();
    tsetup();
    resetPns();
    bigsetup(heap, big.bn());
    ls().common_stdin = abi.ap(word.READ, 0);
    ls().common_stdinb = abi.ap(word.READBIN, 0);
    ls().cook_stdin = abi.ap(abi.readvals(0, 0), word.OFFSIDE);
    core_state.s().nill = heap.cons(word.CONST, NIL);
    rt.rs().Void = abi.makeId(@constCast("()"));
    heap.tp(heap.h(rt.rs().Void)).* = word.void_t;
    heap.tp(rt.rs().Void).* = heap_mod.constructor(heap, 0, rt.rs().Void);
    rt.rs().message = abi.makeId(@constCast("sys_message"));
    rt.rs().main_id = abi.makeId(@constCast("main"));
    rt.rs().concat = abi.makeId(@constCast("concat"));
    rt.rs().diagonalise = abi.makeId(@constCast("diagonalise"));
    rt.rs().standardout = heap_mod.constructor(heap, 0, @as([*:0]const u8, "Stdout"));
    rt.rs().indent_fn = abi.makeId(@constCast("indent"));
    rt.rs().outdent_fn = abi.makeId(@constCast("outdent"));
    rt.rs().listdiff_fn = abi.makeId(@constCast("listdiff"));
    rt.rs().shownum1 = abi.makeId(@constCast("shownum1"));
    rt.rs().showbool = abi.makeId(@constCast("showbool"));
    rt.rs().showchar = abi.makeId(@constCast("showchar"));
    rt.rs().showlist = abi.makeId(@constCast("showlist"));
    rt.rs().showstring = abi.makeId(@constCast("showstring"));
    rt.rs().showparen = abi.makeId(@constCast("showparen"));
    rt.rs().showpair = abi.makeId(@constCast("showpair"));
    rt.rs().showvoid = abi.makeId(@constCast("showvoid"));
    rt.rs().showfunction = abi.makeId(@constCast("showfunction"));
    rt.rs().showabstract = abi.makeId(@constCast("showabstract"));
    rt.rs().showwhat = abi.makeId(@constCast("showwhat"));
    primlib(heap);
}

test "miraSetup initialisation and primitive seeding" {
    abi.setupdic();
    miraSetup();

    // Verify primitives from primlib are seeded correctly
    try std.testing.expect(rt.rs().primenv != NIL);
    try std.testing.expect(rt.rs().Void != 0);
    try std.testing.expect(rt.rs().standardout != 0);
}
