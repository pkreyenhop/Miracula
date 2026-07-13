//! setup.zig — interpreter initialisation. `miraSetup` brings up the heap, the
//! dictionary, and the primitive environment from a cold start; `primlib`,
//! `privlib`, and `stdlib` seed the built-in primitives and the standard-library
//! definitions (via `primdef`/`predef`).

const std = @import("std");
const rt = @import("../runtime/runtime_state.zig");
const repl_session = @import("../session/repl_session.zig");
const show_fns = @import("../semantics/show_fns.zig");
const cs = @import("compiler_state.zig").cs;
const word = @import("../graph/word.zig");
const abi = @import("../os.zig");
const heap_mod = @import("../graph/heap.zig");
const Heap = heap_mod.Heap;
const errors = @import("../runtime/errors.zig");

const Word = word.Word;
const Value = @import("../graph/value.zig").Value;
const NIL = word.NIL;

const lex_state = @import("../parser/lex_state.zig");
const types = @import("../semantics/infer.zig");
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
pub fn syntax(heap: *Heap, s: [*:0]const u8) errors.MiraError!void {
    if (core_state.s().SYNERR != 0) return error.SyntaxError;
    if (!@import("builtin").is_test) {
        if (repl_session.session().echoing != 0) {
            _ = word.printErr("\n", .{});
        }
        _ = word.printErr("syntax error: {s}", .{s});
    }
    core_state.s().SYNERR = 1;
    resetLex(heap);
    return error.SyntaxError;
}

/// Flag a grammar-action error (set `SYNERR`, reset the lexer, and return
/// `error.SyntaxError` -- see `syntax`'s doc comment).
pub fn acterror(heap: *Heap) errors.MiraError!void {
    if (core_state.s().SYNERR != 0) return error.SyntaxError;
    core_state.s().SYNERR = 1;
    resetLex(heap);
    return error.SyntaxError;
}

/// Registers a primitive identifier `n` in the private primitive environment (`rs.primenv`).
/// `v` is the combinator value; `t_val` is the type node. Called only from primlib().
pub fn primdef(heap: *Heap, n: [*:0]const u8, v: Value, t_val: Value) void {
    const x = abi.makeId(@constCast(n));
    rt.rs().primenv = heap.cons(x, rt.rs().primenv);
    heap.tp(x).* = v.toRaw();
    heap.tp(heap.h(x)).* = t_val.toRaw();
}

/// Registers a predefined identifier `n` in the global environment.
/// `v` is the combinator value (wrapped in `constructor()` if `n` is a constructor);
/// `t_val` is the type node. Called from privlib() and stdlib().
pub fn predef(heap: *Heap, n: [*:0]const u8, v: Value, t_val: Value) void {
    const x = abi.makeId(@constCast(n));
    heap_mod.addtoenv(heap, x);
    heap.tp(x).* = if (heap_mod.isconstructor(heap.*, x)) heap_mod.constructor(heap, v.toRaw(), x) else v.toRaw();
    heap.tp(heap.h(x)).* = t_val.toRaw();
}

/// Seeds the primitive type aliases (num, char, bool) and built-in constructors
/// (True, False) into the private primitive environment. Called by miraSetup().
pub fn primlib(heap: *Heap) void {
    primdef(heap, "num", Value.fromRaw(abi.make_typ(heap, 0, 0, word.synonym_t, word.num_t)), Value.fromRaw(word.type_t));
    primdef(heap, "char", Value.fromRaw(abi.make_typ(heap, 0, 0, word.synonym_t, word.char_t)), Value.fromRaw(word.type_t));
    primdef(heap, "bool", Value.fromRaw(abi.make_typ(heap, 0, 0, word.synonym_t, word.bool_t)), Value.fromRaw(word.type_t));
    primdef(heap, "True", Value.fromRaw(1), Value.fromRaw(word.bool_t));
    primdef(heap, "False", Value.fromRaw(0), Value.fromRaw(word.bool_t));
}

/// Seeds the private-prelude identifiers (offside, changetype, hd/tl, etc.) that are
/// always in scope but not user-visible. Called during prelude loading.
pub fn privlib(heap: *Heap) void {
    predef(heap, "offside", Value.fromRaw(word.OFFSIDE), Value.fromRaw(cs().ltchar));
    predef(heap, "changetype", Value.fromRaw(word.I), Value.fromRaw(word.wrong_t));
    predef(heap, "first", Value.fromRaw(word.HD), Value.fromRaw(word.wrong_t));
    predef(heap, "rest", Value.fromRaw(word.TL), Value.fromRaw(word.wrong_t));
    predef(heap, "code", Value.fromRaw(word.CODE), Value.fromRaw(word.undef_t));
    predef(heap, "concat", Value.fromRaw(abi.ap2(heap, word.FOLDR, word.APPEND, NIL)), Value.fromRaw(word.undef_t));
    predef(heap, "decode", Value.fromRaw(word.DECODE), Value.fromRaw(word.undef_t));
    predef(heap, "drop", Value.fromRaw(word.DROP), Value.fromRaw(word.undef_t));
    predef(heap, "error", Value.fromRaw(word.ERROR), Value.fromRaw(word.undef_t));
    predef(heap, "filter", Value.fromRaw(word.FILTER), Value.fromRaw(word.undef_t));
    predef(heap, "foldr", Value.fromRaw(word.FOLDR), Value.fromRaw(word.undef_t));
    predef(heap, "hd", Value.fromRaw(word.HD), Value.fromRaw(word.undef_t));
    predef(heap, "map", Value.fromRaw(word.MAP), Value.fromRaw(word.undef_t));
    predef(heap, "shownum", Value.fromRaw(word.SHOWNUM), Value.fromRaw(word.undef_t));
    predef(heap, "take", Value.fromRaw(word.TAKE), Value.fromRaw(word.undef_t));
    predef(heap, "tl", Value.fromRaw(word.TL), Value.fromRaw(word.undef_t));
}

/// Seeds the standard-library identifiers (map, filter, foldr, trig fns, etc.) into
/// the global environment. Called when STDENV is loaded successfully.
pub fn stdlib(heap: *Heap) void {
    predef(heap, "arctan", Value.fromRaw(word.ARCTAN_FN), Value.fromRaw(word.undef_t));
    predef(heap, "code", Value.fromRaw(word.CODE), Value.fromRaw(word.undef_t));
    predef(heap, "cos", Value.fromRaw(word.COS_FN), Value.fromRaw(word.undef_t));
    predef(heap, "decode", Value.fromRaw(word.DECODE), Value.fromRaw(word.undef_t));
    predef(heap, "drop", Value.fromRaw(word.DROP), Value.fromRaw(word.undef_t));
    predef(heap, "entier", Value.fromRaw(word.ENTIER_FN), Value.fromRaw(word.undef_t));
    predef(heap, "error", Value.fromRaw(word.ERROR), Value.fromRaw(word.undef_t));
    predef(heap, "exp", Value.fromRaw(word.EXP_FN), Value.fromRaw(word.undef_t));
    predef(heap, "filemode", Value.fromRaw(word.FILEMODE), Value.fromRaw(word.undef_t));
    predef(heap, "filestat", Value.fromRaw(word.FILESTAT), Value.fromRaw(word.undef_t));
    predef(heap, "foldl", Value.fromRaw(word.FOLDL), Value.fromRaw(word.undef_t));
    predef(heap, "foldl1", Value.fromRaw(word.FOLDL1), Value.fromRaw(word.undef_t));
    predef(heap, "hugenum", Value.fromRaw(abi.stoDbl(abi.DBL_MAX) catch unreachable), Value.fromRaw(word.undef_t));
    predef(heap, "last", Value.fromRaw(word.LIST_LAST), Value.fromRaw(word.undef_t));
    predef(heap, "foldr", Value.fromRaw(word.FOLDR), Value.fromRaw(word.undef_t));
    predef(heap, "force", Value.fromRaw(word.FORCE), Value.fromRaw(word.undef_t));
    predef(heap, "getenv", Value.fromRaw(word.GETENV), Value.fromRaw(word.undef_t));
    predef(heap, "integer", Value.fromRaw(word.INTEGER), Value.fromRaw(word.undef_t));
    predef(heap, "log", Value.fromRaw(word.LOG_FN), Value.fromRaw(word.undef_t));
    predef(heap, "log10", Value.fromRaw(word.LOG10_FN), Value.fromRaw(word.undef_t));
    predef(heap, "merge", Value.fromRaw(word.MERGE), Value.fromRaw(word.undef_t));
    predef(heap, "numval", Value.fromRaw(word.NUMVAL), Value.fromRaw(word.undef_t));
    predef(heap, "read", Value.fromRaw(word.STARTREAD), Value.fromRaw(word.undef_t));
    predef(heap, "readb", Value.fromRaw(word.STARTREADBIN), Value.fromRaw(word.undef_t));
    predef(heap, "seq", Value.fromRaw(word.SEQ), Value.fromRaw(word.undef_t));
    predef(heap, "shownum", Value.fromRaw(word.SHOWNUM), Value.fromRaw(word.undef_t));
    predef(heap, "showhex", Value.fromRaw(word.SHOWHEX), Value.fromRaw(word.undef_t));
    predef(heap, "showoct", Value.fromRaw(word.SHOWOCT), Value.fromRaw(word.undef_t));
    predef(heap, "showfloat", Value.fromRaw(word.SHOWFLOAT), Value.fromRaw(word.undef_t));
    predef(heap, "showscaled", Value.fromRaw(word.SHOWSCALED), Value.fromRaw(word.undef_t));
    predef(heap, "sin", Value.fromRaw(word.SIN_FN), Value.fromRaw(word.undef_t));
    predef(heap, "sqrt", Value.fromRaw(word.SQRT_FN), Value.fromRaw(word.undef_t));
    predef(heap, "system", Value.fromRaw(word.EXEC), Value.fromRaw(word.undef_t));
    predef(heap, "take", Value.fromRaw(word.TAKE), Value.fromRaw(word.undef_t));
    predef(heap, "tinynum", Value.fromRaw(mktiny()), Value.fromRaw(word.undef_t));
    predef(heap, "zip2", Value.fromRaw(word.ZIP), Value.fromRaw(word.undef_t));
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
pub fn miraSetup(heap: *Heap) void {
    heap.setupheap();
    tsetup(heap);
    resetPns();
    bigsetup(heap, big.bn());
    ls().common_stdin = abi.ap(heap, word.READ, 0);
    ls().common_stdinb = abi.ap(heap, word.READBIN, 0);
    ls().cook_stdin = abi.ap(heap, abi.readvals(heap, 0, 0), word.OFFSIDE);
    heap.nill = heap.cons(word.CONST, NIL);
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
    show_fns.show().shownum1 = abi.makeId(@constCast("shownum1"));
    show_fns.show().showbool = abi.makeId(@constCast("showbool"));
    show_fns.show().showchar = abi.makeId(@constCast("showchar"));
    show_fns.show().showlist = abi.makeId(@constCast("showlist"));
    show_fns.show().showstring = abi.makeId(@constCast("showstring"));
    show_fns.show().showparen = abi.makeId(@constCast("showparen"));
    show_fns.show().showpair = abi.makeId(@constCast("showpair"));
    show_fns.show().showvoid = abi.makeId(@constCast("showvoid"));
    show_fns.show().showfunction = abi.makeId(@constCast("showfunction"));
    show_fns.show().showabstract = abi.makeId(@constCast("showabstract"));
    show_fns.show().showwhat = abi.makeId(@constCast("showwhat"));
    primlib(heap);
}

test "miraSetup initialisation and primitive seeding" {
    abi.setupdic();
    miraSetup(heap_mod.heap());

    // Verify primitives from primlib are seeded correctly
    try std.testing.expect(rt.rs().primenv != NIL);
    try std.testing.expect(rt.rs().Void != 0);
    try std.testing.expect(rt.rs().standardout != 0);
}
