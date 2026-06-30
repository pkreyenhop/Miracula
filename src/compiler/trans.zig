//! trans.zig — translation from parse trees to combinator graphs.
//!
//! Turns definitions and expressions into the `S`/`K`/`I`… combinator graph the
//! reducer runs: bracket abstraction (`abstract`/`abstr`/`combine`), pattern-match
//! compilation (`scanpattern`/`transtries`/`genlhs`), `let`/`letrec` and ZF
//! list-comprehension translation (`translet`/`transzf`), `show`-function
//! generation, and the top-level `codegen`. Also handles declaration bookkeeping
//! (`declare`/`declType`/`declconstr`, name-clash and arity checks) and the
//! relation/topological-sort helpers used to order mutually-recursive groups.

const std = @import("std");
const word = @import("../runtime/word.zig");
const strtab = @import("../runtime/strtab.zig");

const main_clib = @import("../runtime/main_clib.zig");

const compiler_state = @import("compiler_state.zig");
const cs = compiler_state.cs;
// `abi` — a private namespace of libc re-export aliases so this file can write
// `abi.printf(...)`, etc. Internal only (the container is not `pub`, so these
// never appear in autodoc); each member re-exports a `main_clib` symbol.
const abi = struct {
    pub const printf = main_clib.printf;
    pub const putchar = main_clib.putchar;
    pub const FILE = main_clib.FILE;
    pub const stdout = main_clib.stdout;
    pub const exit = main_clib.exit;
};

const lex_state = @import("../parser/lex_state.zig");
const core_state = @import("../runtime/core_state.zig");
const tu = @import("../testutil.zig"); // unit-test harness (test builds only)
const ls = lex_state.ls;

/// The standard-output `FILE` handle.
fn getStdout() ?*word.FILE {
    return main_clib.stdout();
}

const Word = i64;
const GENERATOR: Word = 0;
const GUARD: Word = 1;
const REPEAT: Word = 2;
const undef_t = word.undef_t;
const bool_t = word.bool_t;
const num_t = word.num_t;
const char_t = word.char_t;
const list_t = word.list_t;
const comma_t = word.comma_t;
const arrow_t = word.arrow_t;
const void_t = word.void_t;
const type_t = word.type_t;
const CMBASE = word.CMBASE;
const S: Word = CMBASE + 0;
const K: Word = CMBASE + 1;
const Y: Word = CMBASE + 2;
const C: Word = CMBASE + 3;
const B: Word = CMBASE + 4;
const I: Word = CMBASE + 6;
const S_p: Word = CMBASE + 11;
const U: Word = CMBASE + 12;
const Uf: Word = CMBASE + 13;
const U_: Word = CMBASE + 14;
const Ug: Word = CMBASE + 15;
const COND: Word = CMBASE + 16;
const APPEND: Word = CMBASE + 23;
const MAP: Word = CMBASE + 27;
const FLATMAP: Word = CMBASE + 31;
const FILTER: Word = CMBASE + 32;
const MATCH: Word = CMBASE + 38;
const MATCHINT: Word = CMBASE + 39;
const TRY: Word = CMBASE + 40;
const SUBSCRIPT: Word = CMBASE + 41;
const ATLEAST: Word = CMBASE + 42;
const P: Word = CMBASE + 43;
const B_p: Word = CMBASE + 44;
const C_p: Word = CMBASE + 45;
const S1: Word = CMBASE + 46;
const B1: Word = CMBASE + 47;
const C1: Word = CMBASE + 48;
const PLUS: Word = CMBASE + 54;
const SHOWNUM: Word = CMBASE + 79;
const G_ALT: Word = CMBASE + 97;
const G_SEQ: Word = CMBASE + 106;
const G_UNIT: Word = CMBASE + 108;
const BADCASE: Word = CMBASE + 132;
const CONFERROR: Word = CMBASE + 133;
const FAIL: Word = CMBASE + 135;
const False = word.False;
const True = word.True;
const NIL = word.NIL;
const NILS = word.NILS;
const UNDEF = word.UNDEF;
const wrong_t = word.wrong_t;
// NB: these type-declaration *kind* codes use a local 0/1/2/3 numbering that does
// NOT match word.zig (synonym_t=1, algebraic_t=2, abstract_t=3) — kept local and
// self-consistent on purpose (a flagged discrepancy); do not alias to word.*.
const placeholder_t: Word = 3;
const algebraic_t: Word = 0;
const synonym_t: Word = 1;
const abstract_t: Word = 2;
const CONST = word.CONST;
const ATOMLIMIT = word.ATOMLIMIT;

// NIL

// NIL

// NIL

// NIL

// Cross-module functions: direct @import aliases replace extern-fn linker
// declarations (R7.3 — eliminate the linker-as-module-system pattern).
const heap = @import("../runtime/heap.zig");
const types_mod = @import("types.zig");
const big = @import("../runtime/big.zig");
const lex = @import("../parser/lex.zig");
const setup = @import("setup.zig");
const rt = @import("../runtime/runtime_state.zig");

const make = heap.make;
const append1 = heap.append1;
const reverse = heap.reverse;
const shunt = heap.shunt;
const out = heap.out;
const member = types_mod.member;
const UNION = types_mod.UNION;
const add1 = types_mod.add1;
const deps = types_mod.deps;
const intersection = types_mod.intersection;
const outType = types_mod.outType;
const redtvars = types_mod.redtvars;
const sayhere = types_mod.sayhere;
const setdiff = types_mod.setdiff;
const msc = types_mod.msc;
const tsort = types_mod.tsort;
const isnat = big.isNat;
const isconstrname = lex.isconstrname;
const makePn = lex.makePn;
const mkgvar = lex.mkgvar;
const strcmp = word.strcmp;
const syntax = setup.syntax;
const acterror = setup.acterror;

/// The node tag of cell `x`.
inline fn getTag(x: Word) word.NodeTag {
    return @enumFromInt(heap.heap.getTag(x));
}

/// Head (`hd`) of cell `x`.
fn h(x: Word) Word {
    return heap.heap.h(x);
}

/// Pointer to the head field of cell `x`.
fn hp(x: Word) *Word {
    return heap.heap.hp(x);
}

/// Tail (`tl`) of cell `x`.
fn t(x: Word) Word {
    return heap.heap.t(x);
}

/// Pointer to the tail field of cell `x`.
fn tp(x: Word) *Word {
    return heap.heap.tp(x);
}

/// The head of an application spine (walk `hd` while it is an `AP`).
fn appHead(input_x: Word) Word {
    var x = input_x;
    while (getTag(x) == .AP) {
        x = h(x);
    }
    return x;
}

/// Allocate a `CONS` cell `(x . y)`.
fn cons(x: Word, y: Word) Word {
    return make(word.CONS, x, y);
}

/// Allocate a `PAIR` cell `(x . y)`.
fn pair(x: Word, y: Word) Word {
    return make(word.PAIR, x, y);
}

/// Allocate a `DATAPAIR` cell.
fn datapair(x: Word, y: Word) Word {
    return make(word.DATAPAIR, x, y);
}

/// Allocate a `CONSTRUCTOR` cell (tag `n`, fields `x`).
fn constructor(n: Word, x: Word) Word {
    return make(word.CONSTRUCTOR, n, x);
}

/// Allocate a `LAMBDA` cell `(x . y)`.
fn lambda(x: Word, y: Word) Word {
    return make(word.LAMBDA, x, y);
}

/// Allocate a `SHARE` cell (a shared / lazily-evaluated binding).
fn share(x: Word, y: Word) Word {
    return make(word.SHARE, x, y);
}

/// Allocate a `TRIES` cell (a chain of pattern-match alternatives).
fn tries(x: Word, y: Word) Word {
    return make(word.TRIES, x, y);
}

/// Allocate a `LET` cell.
fn let(x: Word, y: Word) Word {
    return make(word.LET, x, y);
}

/// Allocate a `LETREC` cell.
fn letrec(x: Word, y: Word) Word {
    return make(word.LETREC, x, y);
}

/// Allocate an application `(x y)`.
fn ap(x: Word, y: Word) Word {
    return make(word.AP, x, y);
}

/// Allocate `((x y) z)`.
fn ap2(x: Word, y: Word, z: Word) Word {
    return ap(ap(x, y), z);
}

/// Allocate `(((w x) y) z)`.
fn ap3(w: Word, x: Word, y: Word, z: Word) Word {
    return ap(ap2(w, x, y), z);
}

/// The interned name text of id `x`.
fn getId(x: Word) [*:0]const u8 {
    return strtab.strOf(h(h(h(x))));
}

/// The definition-site field of id `x`.
fn idWho(x: Word) Word {
    return t(h(h(x)));
}

/// Set the definition-site field of id `x`.
fn setIdWho(x: Word, value: Word) void {
    tp(h(h(x))).* = value;
}

/// The type field of id `x`.
fn idType(x: Word) Word {
    return t(h(x));
}

/// The value field of id `x`.
fn idVal(x: Word) Word {
    return t(x);
}

/// Set the type field of id `x`.
fn setIdType(x: Word, value: Word) void {
    tp(h(x)).* = value;
}

/// Set the value field of id `x`.
fn setIdVal(x: Word, value: Word) void {
    tp(x).* = value;
}

/// Build a type descriptor cell `((arity . showfn) . (class . info))`.
fn makeTyp(arity: Word, showfn: Word, class: Word, info: Word) Word {
    return cons(cons(arity, showfn), cons(class, info));
}

/// Add id `x` to the current file's definition environment.
fn addToEnv(x: Word) void {
    const current_file_defs = h(heap.heap.files);
    if (current_file_defs >= ATOMLIMIT) {
        
        tp(current_file_defs).* = cons(x, tp(current_file_defs).*);
    }
}

/// Whether `x` names a data constructor.
fn isConstructor(x: Word) bool {
    return getTag(x) == .ID and isconstrname(getId(x)) != 0;
}

/// Whether `x` names an ordinary variable.
fn isVariable(x: Word) bool {
    return getTag(x) == .ID and isconstrname(getId(x)) == 0;
}

/// Whether `x` is an `n+k` pattern.
fn isNPlusKPattern(x: Word) bool {
    return getTag(x) == .AP and getTag(h(x)) == .AP and h(h(x)) == PLUS;
}

/// Whether a type node is a function (`->`) type.
fn isArrowType(x: Word) bool {
    return getTag(x) == .AP and getTag(h(x)) == .AP and h(h(x)) == arrow_t;
}

/// Whether a type node is a list type.
fn isListType(x: Word) bool {
    return getTag(x) == .AP and h(x) == list_t;
}

/// Whether a type node is a type variable.
fn isTypeVariable(x: Word) bool {
    return getTag(x) == .TVAR;
}

/// Whether a type node is a compound (application) type.
fn isCompoundType(x: Word) bool {
    return getTag(x) == .AP;
}

/// Whether `x` is a char value.
fn isChar(x: Word) bool {
    return 0 <= x and x <= 255;
}

/// The arity recorded in a type descriptor.
fn typeArity(x: Word) Word {
    return h(h(t(x)));
}

/// The `show` function recorded in a type descriptor.
fn typeShowFn(x: Word) Word {
    return t(h(t(x)));
}

/// The class (algebraic/synonym/abstract) of a type descriptor.
fn typeClass(x: Word) Word {
    return h(t(t(x)));
}

/// Set the class field of a type descriptor.
fn setTypeClass(x: Word, value: Word) void {
    hp(t(t(x))).* = value;
}

/// The info field of a type descriptor.
fn typeInfo(x: Word) Word {
    return t(t(t(x)));
}

/// Set the info field of a type descriptor.
fn setTypeInfo(x: Word, value: Word) void {
    tp(t(t(x))).* = value;
}

/// The index of type variable `x`.
fn getTypeVariable(x: Word) Word {
    return t(x);
}

/// Box index `i` (bare if small, else an `INT` cell).
fn mkindex(i: Word) Word {
    return if (word.fitsInByte(i)) i else make(word.INT, i, 0);
}

/// The left-hand side of a definition cell `d`.
fn dlhs(d: Word) Word {
    return h(d);
}

/// Set the left-hand side of a definition cell `d`.
fn setDlhs(d: Word, value: Word) void {
    hp(d).* = value;
}

/// The value of a definition cell `d`.
fn dval(d: Word) Word {
    return t(t(d));
}

/// Set the value of a definition cell `d`.
fn setDval(d: Word, value: Word) void {
    tp(t(d)).* = value;
}

/// The underlying `CONSTRUCTOR` cell of id `x` (through any `MKSTRICT` wrapper).
pub fn primconstr(input_x: Word) Word {
    var x = t(input_x); // idVal(x) = CONSTRUCTOR cell (or MKSTRICT wrapper for strict ctors)
    while (getTag(x) != .CONSTRUCTOR) {
        x = t(x);
    }
    return x;
}

/// Whether `x` is a member of list `l`.
///
/// Tests: memb: membership in a list
pub fn memb(input_l: Word, x: Word) Word {
    var l = input_l;
    if (getTag(x) == .TVAR) {
        while (l != NIL and t(h(l)) != t(x)) {
            l = t(l);
        }
    } else {
        while (l != NIL and h(l) != x) {
            l = t(l);
        }
    }
    return if (l != NIL) 1 else 0;
}

test "memb: membership in a list" {
    tu.freshInterp();
    const l = cons(word.True, cons(word.False, NIL));
    try std.testing.expectEqual(@as(Word, 1), memb(l, word.False));
    try std.testing.expectEqual(@as(Word, 0), memb(l, word.S));
}

/// Whether `x` and `y` are structurally equal.
///
/// Tests: same: structural equality of graphs
pub fn same(x: Word, y: Word) Word {
    if (x == y) {
        return 1;
    }
    const x_tag = getTag(x);
    const y_tag = getTag(y);
    if (x_tag == .ATOM or y_tag == .ATOM or x_tag != y_tag) {
        return 0;
    }
    if (@intFromEnum(x_tag) < @intFromEnum(word.NodeTag.INT)) {
        return if (h(x) == h(y) and t(x) == t(y)) 1 else 0;
    }
    if (@intFromEnum(x_tag) > @intFromEnum(word.NodeTag.STRCONS)) {
        return if (same(h(x), h(y)) != 0 and same(t(x), t(y)) != 0) 1 else 0;
    }
    return if (h(x) == h(y) and same(t(x), t(y)) != 0) 1 else 0;
}

test "same: structural equality of graphs" {
    tu.freshInterp();
    try std.testing.expectEqual(@as(Word, 1), same(word.True, word.True));
    const a = cons(word.True, NIL);
    const b = cons(word.True, NIL);
    try std.testing.expectEqual(@as(Word, 1), same(a, b)); // distinct cells, equal structure
    try std.testing.expectEqual(@as(Word, 0), same(a, cons(word.False, NIL)));
}

/// Collect the identifiers bound by pattern/definition `x`.
pub fn getIds(x: Word) Word {
    if (word.isAtom(x)) {
        return NIL;
    }
    if (h(x) == CONST or isConstructor(x)) {
        return NIL;
    }
    if (getTag(x) == .ID) {
        return cons(x, NIL);
    }
    if (isNPlusKPattern(x)) {
        return getIds(t(x));
    }
    return UNION(getIds(h(x)), getIds(t(x)));
}

/// Build a tuple from element list `x`.
pub fn mktuple(input_x: Word) Word {
    var x = input_x;
    if (word.isAtom(x)) {
        return NIL;
    }
    if (h(x) == CONST or isConstructor(x)) {
        return NIL;
    }
    if (getTag(x) == .ID) {
        return x;
    }
    if (isNPlusKPattern(x)) {
        return mktuple(t(x));
    }
    const y = mktuple(t(x));
    x = mktuple(h(x));
    return if (x == NIL) y else if (y == NIL) x else pair(x, y);
}

/// Whether pattern `x` is irrefutable (always matches).
pub fn irrefutable(x: Word) Word {
    if (word.isAtom(x)) {
        return 0;
    }
    if (getTag(x) == .CONS) {
        return 0;
    }
    if (isConstructor(x)) {
        return member(cs.SGC, x);
    }
    if (getTag(x) == .ID) {
        return 1;
    }
    if (isNPlusKPattern(x)) {
        return 0;
    }
    return if (irrefutable(h(x)) != 0 and irrefutable(t(x)) != 0) 1 else 0;
}

/// Whether expression `e` may fail to match.
pub fn fallible(input_e: Word) Word {
    var e = input_e;
    while (true) {
        const e_tag = getTag(e);
        if (e_tag == .LABEL) {
            e = t(e);
            continue;
        }
        if (e_tag == .LETREC or e_tag == .LET) {
            e = t(e);
        } else if (e_tag == .LAMBDA) {
            if (irrefutable(h(e)) != 0) {
                e = t(e);
            } else {
                return 1;
            }
        } else if (e_tag == .AP and getTag(h(e)) == .AP and getTag(h(h(e))) == .AP and h(h(h(e))) == COND) {
            e = t(e);
        } else {
            return if (e == FAIL) 1 else 0;
        }
    }
}

/// The source-location info attached to right-hand side `rhs`.
pub fn hereInfo(rhs: Word) Word {
    var x = t(rhs);
    while (t(x) != NIL) {
        x = t(x);
    }
    return h(h(x));
}

/// The last cell of list `x`.
///
/// Tests: lastlink: the last cell of a list
pub fn lastlink(input_x: Word) Word {
    var x = input_x;
    while (t(x) != NIL) {
        x = t(x);
    }
    return x;
}

test "lastlink: the last cell of a list" {
    tu.freshInterp();
    const l = cons(word.True, cons(word.False, cons(word.S, NIL)));
    const last = lastlink(l);
    try std.testing.expectEqual(@as(Word, word.S), h(last));
    try std.testing.expectEqual(@as(Word, NIL), t(last));
}

/// Rewrite repeated variables in comprehension qualifiers `qq` into equality guards.
pub fn fixrepeats(input_qq: Word) Word {
    var q = h(input_qq);
    var rhs = q;
    var qq = t(input_qq);
    while (h(rhs) == REPEAT) {
        rhs = t(t(rhs));
    }
    rhs = t(t(rhs));
    while (h(q) == REPEAT) {
        qq = cons(cons(GENERATOR, cons(h(t(q)), rhs)), qq);
        q = t(t(q));
    }
    return cons(q, qq);
}

/// Abstract a show function `f` over a type's arity parameters.
pub fn abshfnck(t_type: Word, f_input: Word) Word {
    var f = f_input;
    var n = typeArity(t_type);
    var i: Word = 1;
    while (i <= n) {
        if (!isArrowType(f)) {
            return 0;
        }
        const param = t(h(f));
        if (!(isArrowType(param) and isTypeVariable(t(h(param))) and getTypeVariable(t(h(param))) == i and isListType(t(param)) and t(t(param)) == char_t)) {
            return 0;
        }
        i += 1;
        f = t(f);
    }
    if (!(isArrowType(f) and isListType(t(f)) and t(t(f)) == char_t)) {
        return 0;
    }
    f = t(h(f));
    while (isCompoundType(f) and isTypeVariable(t(f)) and getTypeVariable(t(f)) == n) {
        n -= 1;
        f = h(f);
    }
    return if (f == t_type) 1 else 0;
}

/// Combine two bracket-abstraction results, optimising redundant `K`s.
pub fn combine(x: Word, y: Word) Word {
    const a = getTag(x) == .AP and h(x) == K;
    const b = getTag(y) == .AP and h(y) == K;
    if (a and b) {
        return ap(K, ap(t(x), t(y)));
    }
    if (a and y == I) {
        return t(x);
    }
    const b1 = getTag(y) == .AP and getTag(h(y)) == .AP and h(h(y)) == B;
    if (a) {
        if (b1) {
            return ap3(B1, t(x), t(h(y)), t(y));
        }
        if (getTag(t(x)) == .AP and getTag(h(t(x))) == .AP and h(h(t(x))) == COND) {
            return ap3(COND, t(h(t(x))), ap(K, t(t(x))), y);
        }
        return ap2(B, t(x), y);
    }
    const a1 = getTag(x) == .AP and getTag(h(x)) == .AP and h(h(x)) == B;
    if (b) {
        if (a1) {
            if (getTag(t(h(x))) == .AP and h(t(h(x))) == COND) {
                return ap3(COND, t(t(h(x))), t(x), y);
            }
            return ap3(C1, t(h(x)), t(x), t(y));
        }
        return ap2(C, x, t(y));
    }
    if (a1) {
        if (getTag(t(h(x))) == .AP and h(t(h(x))) == COND) {
            return ap3(COND, t(t(h(x))), t(x), y);
        }
        return ap3(S1, t(h(x)), t(x), y);
    }
    return ap2(S, x, y);
}

/// Combine two abstraction results building a cons, optimising the `K` cases.
pub fn liscomb(x: Word, y: Word) Word {
    const a = getTag(x) == .AP and h(x) == K;
    const b = getTag(y) == .AP and h(y) == K;
    if (a and b) {
        return ap(K, cons(t(x), t(y)));
    }
    if (a) {
        if (y == I) {
            return ap(P, t(x));
        }
        return ap2(B_p, t(x), y);
    }
    if (b) {
        return ap2(C_p, x, t(y));
    }
    return ap2(S_p, x, y);
}

/// Bracket-abstract variable `x` out of expression `e` (Turner's algorithm).
pub fn abstract(input_x: Word, input_e: Word) Word {
    var x = input_x;
    var e = input_e;
    switch (getTag(x)) {
        .ID => {
            if (isConstructor(x)) {
                return if (member(cs.SGC, x) != 0) ap(K, e) else ap2(Ug, primconstr(x), e);
            }
            return abstr(x, e);
        },
        .CONS => {
            if (h(x) == CONST) {
                if (getTag(t(x)) == .INT) {
                    return ap2(MATCHINT, t(x), e);
                }
                return ap2(MATCH, if (t(x) == NILS) NIL else t(x), e);
            }
            return ap(U_, abstract(h(x), abstract(t(x), e)));
        },
        .TCONS, .PAIR => return ap(U, abstract(h(x), abstract(t(x), e))),
        .AP => {
            if (member(cs.SGC, appHead(x)) != 0) {
                return ap(Uf, abstract(h(x), abstract(t(x), e)));
            }
            if (getTag(h(x)) == .AP and h(h(x)) == PLUS) {
                return ap2(ATLEAST, t(h(x)), abstract(t(x), e));
            }
            while (getTag(x) == .AP) {
                e = abstract(t(x), e);
                x = h(x);
            }
        },
        else => {},
    }
    if (isConstructor(x)) {
        return ap2(Ug, primconstr(x), e);
    }
    _ = word.print("error in declaration of \"{s}\", undeclared constructor in pattern: ", .{getId(cs.current_id)});
    const stdout_val = getStdout();
    out(stdout_val, x);
    _ = word.print("\n", .{});
    return NIL;
}

/// Bracket-abstract `x` from `e` (the recursive inner step).
pub fn abstr(x: Word, e: Word) Word {
    switch (getTag(e)) {
        .TCONS, .PAIR, .CONS => return liscomb(abstr(x, h(e)), abstr(x, t(e))),
        .AP => {
            if (h(e) == BADCASE or h(e) == CONFERROR) {
                return ap(K, e);
            }
            return combine(abstr(x, h(e)), abstr(x, t(e)));
        },
        .LAMBDA, .LET, .LETREC, .TRIES, .LABEL, .SHOW, .LEXER, .SHARE => {
            std.debug.print("impossible event in abstr (main.tag={d})\n", .{getTag(e)});
            abi.exit(1);
        },
        else => {
            if (x == e or (isTypeVariable(x) and isTypeVariable(e) and getTypeVariable(x) == getTypeVariable(e))) {
                return I;
            }
            return ap(K, e);
        },
    }
}

/// Bracket-abstract a list of variables `x` from `e`.
pub fn abstrlist(x_input: Word, e: Word) Word {
    switch (getTag(e)) {
        .TCONS, .PAIR, .CONS => return liscomb(abstrlist(x_input, h(e)), abstrlist(x_input, t(e))),
        .AP => {
            if (h(e) == BADCASE or h(e) == CONFERROR) {
                return ap(K, e);
            }
            return combine(abstrlist(x_input, h(e)), abstrlist(x_input, t(e)));
        },
        .LAMBDA, .LET, .LETREC, .TRIES, .LABEL, .SHOW, .LEXER, .SHARE => {
            std.debug.print("impossible event in abstrlist (main.tag={d})\n", .{getTag(e)});
            abi.exit(1);
        },
        else => {
            var i: Word = 0;
            var x = x_input;
            while (x != NIL and h(x) != e) {
                i += 1;
                x = t(x);
            }
            if (x == NIL) {
                return ap(K, e);
            }
            return ap(SUBSCRIPT, mkindex(i));
        },
    }
}

/// Compile pattern `p` against scrutinee `x` into `e`, with `fail` as the no-match continuation.
pub fn scanpattern(p: Word, x: Word, e: Word, fail: Word) Word {
    if (h(x) == CONST or isConstructor(x)) {
        return NIL;
    }
    if (getTag(x) == .ID) {
        const binding = cons(x, ap2(TRY, ap(lambda(p, x), e), fail));
        return cons(binding, NIL);
    }
    if (isNPlusKPattern(x)) {
        return scanpattern(p, t(x), e, fail);
    }
    return shunt(scanpattern(p, h(x), e, fail), scanpattern(p, t(x), e, fail));
}

/// Build a lazy (shared) binding for definition `d`.
pub fn mklazy(d: Word) Word {
    if (irrefutable(dlhs(d)) != 0) {
        return d;
    }
    const ids = mktuple(dlhs(d));
    if (ids == NIL) {
        std.debug.print("impossible event in mklazy\n", .{});
        return d;
    }
    setDval(d, ap2(TRY, ap(lambda(dlhs(d), ids), dval(d)), ap(CONFERROR, cons(dlhs(d), hereInfo(dval(d))))));
    setDlhs(d, ids);
    return d;
}

/// Build a lazy binding for `d` (the new-parser variant).
pub fn newMkLazy(d: Word) Word {
    const ids = getIds(dlhs(d));
    if (ids == NIL) {
        std.debug.print("impossible event in newMkLazy\n", .{});
        return d;
    }
    setDval(d, ap2(TRY, ap(lambda(dlhs(d), ids), dval(d)), ap(CONFERROR, cons(dlhs(d), hereInfo(dval(d))))));
    setDlhs(d, ids);
    return d;
}

/// Compile a ZF (list comprehension) expression.
pub fn compzf(input_e: Word, input_qq: Word, diag: Word) Word {
    var e = input_e;
    var qq = input_qq;
    var hold: Word = NIL;
    var r: Word = 0;
    var g1: Word = -1;
    while (qq != NIL) {
        if (h(h(qq)) == REPEAT) {
            qq = fixrepeats(qq);
        }
        hold = cons(h(qq), hold);
        if (h(h(qq)) == GUARD) {
            r += 1;
        }
        qq = t(qq);
    }
    qq = hold;
    while (qq != NIL and h(h(qq)) == GUARD) {
        r -= 1;
        qq = t(qq);
    }
    if (h(h(hold)) == GENERATOR) {
        g1 = t(t(h(hold)));
    }
    e = transzf(e, hold, if (diag != 0) rt.rs.diagonalise else rt.rs.concat);
    if (diag != 0) {
        while (r != 0) {
            r -= 1;
            e = ap(rt.rs.concat, e);
        }
    }
    return if (e == g1) ap2(APPEND, NIL, e) else e;
}

/// Translate a ZF comprehension body `e` over qualifiers `qq`.
pub fn transzf(e_input: Word, qq_input: Word, conc: Word) Word {
    var e = e_input;
    const qq = qq_input;
    if (qq == NIL) {
        return cons(e, NIL);
    }
    const q = h(qq);
    if (h(q) == GUARD) {
        return ap3(COND, t(q), transzf(e, t(qq), conc), NIL);
    }
    if (t(qq) == NIL) {
        if (h(t(q)) == e and isVariable(e)) {
            return t(t(q));
        }
        if (irrefutable(h(t(q))) != 0) {
            return ap2(MAP, lambda(h(t(q)), e), t(t(q)));
        }
        return ap2(FLATMAP, lambda(h(t(q)), cons(e, NIL)), t(t(q)));
    }
    const q2 = h(t(qq));
    if (h(q2) == GUARD) {
        if (conc == rt.rs.concat) {
            tp(t(q)).* = ap2(FILTER, lambda(h(t(q)), t(q2)), t(t(q)));
            tp(qq).* = t(t(qq));
            return transzf(e, qq, conc);
        }
        e = ap3(COND, t(q2), cons(e, NIL), NIL);
        tp(qq).* = t(t(qq));
        return transzf(e, qq, conc);
    }
    return ap(conc, transzf(transzf(e, t(qq), conc), cons(q, NIL), conc));
}

/// The recorded source location of the type spec for `x`.
pub fn getspecloc(x: Word) Word {
    var s = cs.speclocs;
    while (s != NIL and h(h(s)) != x) {
        s = t(s);
    }
    return if (s == NIL) idWho(x) else t(h(s));
}

/// Translate a type identifier `x`.
pub fn transtypeid(x: Word) Word {
    const n = getId(x);
    if (strcmp(n, "bool") == 0) return bool_t;
    if (strcmp(n, "num") == 0) return num_t;
    if (strcmp(n, "char") == 0) return char_t;
    return x;
}

/// Generate the canonical left-hand-side pattern from definition head `x`.
pub fn genlhs(x: Word) Word {
    switch (getTag(x)) {
        .AP => {
            if (getTag(h(x)) == .AP and h(h(x)) == PLUS and isnat(t(x)) != 0) {
                return ap2(PLUS, t(x), genlhs(t(h(x))));
            }
            const hold = genlhs(h(x));
            return make(word.AP, hold, genlhs(t(x)));
        },
        .CONS, .TCONS, .PAIR => {
            const hold = genlhs(h(x));
            return make(@intFromEnum(getTag(x)), hold, genlhs(t(x)));
        },
        .ID => {
            if (member(ls.idsused, x) != 0) {
                return cons(CONST, x);
            }
            if (!isConstructor(x)) {
                ls.idsused = cons(x, ls.idsused);
            }
            return x;
        },
        .INT => return cons(CONST, x),
        .DOUBLE => {
            syntax("floating point literal in pattern\n");
            return core_state.s.nill;
        },
        .ATOM => {
            if (x == True or x == False or x == NILS or x == NIL or isChar(x)) {
                return cons(CONST, x);
            }
        },
        else => {},
    }
    syntax("illegal form on left of <-\n");
    return core_state.s.nill;
}

/// Left-factor the common prefixes among grammar alternatives `x`.
pub fn leftfactor(x: Word) Word {
    var a: Word = undefined;
    var b: Word = undefined;
    var rhs = t(h(x));
    var d: Word = undefined;
    if (getTag(rhs) == .AP and getTag(h(rhs)) == .AP and h(h(rhs)) == G_SEQ) {
        a = t(h(rhs));
        b = t(rhs);
    } else {
        return x;
    }
    d = t(x);
    if (same(a, d) != 0) {
        hp(x).* = ap(G_SEQ, a);
        tp(x).* = ap2(G_ALT, b, G_UNIT);
        cs.lfrule += 1;
        return x;
    }
    if (getTag(d) == .AP and getTag(h(d)) == .AP) {
        rhs = h(h(d));
    } else {
        return x;
    }
    if (rhs == G_SEQ and same(a, t(h(d))) != 0) {
        rhs = t(d);
        hp(x).* = ap(G_SEQ, a);
        tp(x).* = leftfactor(ap2(G_ALT, b, rhs));
        cs.lfrule += 1;
        return x;
    }
    if (rhs != G_ALT) {
        return x;
    }
    rhs = t(h(d));
    if (same(a, rhs) != 0) {
        d = t(d);
        hp(x).* = ap(G_ALT, ap2(G_SEQ, a, ap2(G_ALT, b, G_UNIT)));
        tp(x).* = d;
        cs.lfrule += 1;
        return leftfactor(x);
    }
    if (getTag(rhs) == .AP and getTag(h(rhs)) == .AP and h(h(rhs)) == G_SEQ and same(a, t(h(rhs))) != 0) {
        rhs = t(rhs);
        d = t(d);
        hp(x).* = ap(G_ALT, ap2(G_SEQ, a, leftfactor(ap2(G_ALT, b, rhs))));
        tp(x).* = d;
        cs.lfrule += 1;
        return leftfactor(x);
    }
    return x;
}

/// Translate a `let` of definition `d` in body `e`.
pub fn translet(d: Word, e: Word) Word {
    const x = mklazy(d);
    return ap(abstract(dlhs(x), codegen(e)), codegen(dval(x)));
}

/// Translate a `letrec` of definitions `dd` in body `e`.
pub fn transletrec(input_dd: Word, e: Word) Word {
    var dd = input_dd;
    var lhs: Word = NIL;
    var rhs: Word = NIL;
    var pn: Word = 1;
    while (dd != NIL) : (dd = t(dd)) {
        var x = h(dd);
        if (getTag(dlhs(x)) == .ID) {
            lhs = cons(dlhs(x), lhs);
            rhs = cons(codegen(dval(x)), rhs);
        } else {
            var i: Word = 0;
            const p = mkgvar(pn);
            pn += 1;
            x = newMkLazy(x);
            var ids = dlhs(x);
            lhs = cons(p, lhs);
            rhs = cons(codegen(dval(x)), rhs);
            while (ids != NIL) {
                lhs = cons(h(ids), lhs);
                rhs = cons(ap2(SUBSCRIPT, mkindex(i), p), rhs);
                ids = t(ids);
                i += 1;
            }
        }
    }
    if (t(lhs) == NIL) {
        return ap(abstr(h(lhs), codegen(e)), ap(Y, abstr(h(lhs), h(rhs))));
    }
    return ap(abstrlist(lhs, codegen(e)), ap(Y, abstrlist(lhs, rhs)));
}

/// Translate the pattern-match alternatives `x` of an id into a `TRIES` chain.
pub fn transtries(id: Word, input_x: Word) Word {
    var x = input_x;
    var info: Word = 0;
    var earliest: Word = 0;
    var r: Word = undefined;
    if (fallible(h(x)) != 0) {
        const oldn = if (getTag(id) == .ID) datapair(@as(Word, strtab.strBits(getId(id))), 0) else 0;
        info = cons(oldn, 0);
        r = ap(BADCASE, info);
        if (x == NIL) {
            std.debug.print("Internal error: `earliest' is used uninitialised in transtries()\nPlease report it to miranda@groups.io\n", .{});
        }
    } else {
        earliest = h(x);
        r = codegen(earliest);
        x = t(x);
    }
    while (x != NIL) {
        earliest = h(x);
        r = ap2(TRY, codegen(earliest), r);
        x = t(x);
    }
    if (info != 0) {
        tp(info).* = h(earliest);
    }
    return r;
}

/// Build the `show` function for a type at source location `here`.
pub fn makeshow(here: Word, type_node: Word) Word {
    cs.was_poly = 0;
    const f = mkshow(0, 0, type_node);
    if (here != 0 and cs.was_poly != 0) {
        _ = word.print("type error in definition of {s}\n", .{getId(cs.current_id)});
        sayhere(here, 0);
        _ = word.print(" use of \"show\" at polymorphic type ", .{});
        outType(redtvars(type_node));
        _ = word.putchar('\n');
        setIdType(cs.current_id, wrong_t);
        setIdVal(cs.current_id, UNDEF);
        cs.polyshowerror = 1;
        cs.ND = add1(cs.current_id, cs.ND);
        cs.was_poly = 0;
    }
    return f;
}

/// Build a `show` application for type `t`.
pub fn mkshow(s: Word, p: Word, input_t: Word) Word {
    var args: Word = NIL;
    var type_node = input_t;
    while (getTag(type_node) == .AP) {
        args = cons(t(type_node), args);
        type_node = h(type_node);
    }
    switch (type_node) {
        num_t => return if (p != 0) rt.rs.shownum1 else SHOWNUM,
        bool_t => return rt.rs.showbool,
        char_t => return rt.rs.showchar,
        list_t => {
            if (h(args) == char_t) {
                return rt.rs.showstring;
            }
            return ap(rt.rs.showlist, mkshow(s, 0, h(args)));
        },
        comma_t => return ap(rt.rs.showparen, ap2(rt.rs.showpair, mkshow(s, 0, h(args)), mkshowt(s, h(t(args))))),
        void_t => return rt.rs.showvoid,
        arrow_t => return rt.rs.showfunction,
        else => {
            if (getTag(type_node) == .ID) {
                var r = typeShowFn(type_node);
                if (r == 0) {
                    return rt.rs.showabstract;
                }
                if (r == rt.rs.showwhat) {
                    return r;
                }
                while (args != NIL) {
                    r = ap(r, mkshow(s, 1, h(args)));
                    args = t(args);
                }
                if (typeClass(type_node) == 0) {
                    r = ap(r, p);
                }
                return r;
            }
            if (isTypeVariable(type_node)) {
                if (s != 0) {
                    return type_node;
                }
                cs.was_poly = 1;
                return rt.rs.showwhat;
            }
            if (getTag(type_node) == .STRCONS) {
                _ = word.print("warning - mkshow applied to suppressed type\n", .{});
                return rt.rs.showwhat;
            }
            _ = word.print("impossible event in mkshow (", .{});
            outType(type_node);
            _ = word.print(")\n", .{});
            return rt.rs.showwhat;
        },
    }
}

/// Build a `show` for a tuple type.
pub fn mkshowt(s: Word, type_tuple: Word) Word {
    if (t(type_tuple) == void_t) {
        return mkshow(s, 0, t(h(type_tuple)));
    }
    return ap2(rt.rs.showpair, mkshow(s, 0, t(h(type_tuple))), mkshowt(s, t(type_tuple)));
}

/// Name-clash check helper (returns a count).
fn nclchk(n: Word, p: Word, hr: Word) c_int {
    if (h(p) == CONST) {
        return 0;
    }
    if (getTag(p) == .ID) {
        if (n != p) {
            return 0;
        }
        if (rt.rs.echoing != 0) {
            _ = word.putchar('\n');
        }
        core_state.s.errs = hr;
        _ = word.print("syntax error: conflicting definitions of \"{s}\" in where clause\n", .{getId(n)});
        acterror();
        return 1;
    }
    if (getTag(p) == .AP and h(p) == PLUS) {
        return 0;
    }
    if (nclchk(n, h(p), hr) != 0) {
        return 1;
    }
    return nclchk(n, t(p), hr);
}

/// Check definitions `dd` for name clashes with `n`.
pub fn nclashcheck(n: Word, input_dd: Word, hr: Word) void {
    var dd = input_dd;
    while (dd != NIL and nclchk(n, dlhs(h(dd)), hr) == 0) {
        dd = t(dd);
    }
}

/// Report a re-specification (duplicate `::`) error for `x`.
pub fn respecError(x: Word) void {
    if (rt.rs.echoing != 0) {
        _ = word.putchar('\n');
    }
    const suffix: [*:0]const u8 = if (member(rt.rs.primenv, x) != 0) " (in standard environment)" else "";
    _ = word.print("syntax error: type of \"{s}\" already declared{s}\n", .{ getId(x), suffix });
    acterror();
}

/// Report a name clash for `x`.
pub fn nameclash(x: Word) void {
    if (rt.rs.echoing != 0) {
        _ = word.putchar('\n');
    }
    const suffix: [*:0]const u8 = if (member(rt.rs.primenv, x) != 0) " (in standard environment)" else "";
    _ = word.print("syntax error: nameclash, \"{s}\" already defined{s}\n", .{ getId(x), suffix });
    acterror();
}

/// Declare data constructor `x` of type `constr_type`.
pub fn declconstr(x: Word, n: Word, constr_type: Word) void {
    setIdVal(x, constructor(n, x));
    if ((n >> 16) != 0) {
        syntax("algebraic type has too many constructors\n");
        return;
    }
    if (idType(x) != undef_t) {
        core_state.s.errs = idWho(x);
        respecError(x);
        return;
    }
    addToEnv(x);
    setIdType(x, constr_type);
}

/// Attach type specification `spec_type` to `x` (a `::` declaration).
pub fn specify(input_x: Word, spec_type: Word, here: Word) void {
    var x = input_x;
    if (getTag(x) != .ID and spec_type != type_t) {
        core_state.s.errs = here;
        syntax("incorrect use of ::\n");
        return;
    }
    if (spec_type == type_t) {
        var arity: Word = 0;
        while (getTag(x) == .AP) {
            arity += 1;
            x = h(x);
        }
        if (!(idVal(x) == UNDEF and idType(x) == undef_t)) {
            core_state.s.errs = here;
            nameclash(x);
            return;
        }
        setIdType(x, type_t);
        if (idWho(x) == NIL) {
            setIdWho(x, here);
        }
        setIdVal(x, makeTyp(arity, rt.rs.showwhat, placeholder_t, NIL));
        addToEnv(x);
        cs.newtyps = add1(x, cs.newtyps);
        return;
    }
    if (idType(x) != undef_t) {
        core_state.s.errs = here;
        respecError(x);
        return;
    }
    setIdType(x, spec_type);
    if (idWho(x) == NIL) {
        setIdWho(x, here);
    } else {
        cs.speclocs = cons(cons(x, here), cs.speclocs);
    }
    if (idVal(x) == UNDEF) {
        addToEnv(x);
    }
}

/// Check that `type_name` is applied at its declared arity.
fn arityCheck(type_name: Word, arity: Word, here: Word) void {
    if (typeArity(type_name) != arity) {
        const prefix: [*:0]const u8 = if (rt.rs.echoing != 0) "\n" else "";
        _ = word.print("{s}syntax error: wrong number of parameters for typename \"{s}\" ({d} expected)\n", .{
            prefix,
            getId(type_name),
            typeArity(type_name),
        });
        core_state.s.errs = here;
        acterror();
    }
}

/// Declare a type (`tf`) with its class and info.
pub fn declType(input_tf: Word, type_class: Word, info: Word, here: Word) void {
    var tf = input_tf;
    var arity: Word = 0;
    while (getTag(tf) == .AP) {
        arity += 1;
        tf = h(tf);
    }
    if (type_class == synonym_t and idType(tf) == type_t and typeClass(tf) == abstract_t and typeInfo(tf) == undef_t) {
        arityCheck(tf, arity, here);
        setIdWho(tf, here);
        setTypeInfo(tf, info);
        return;
    }
    if (type_class == abstract_t and idType(tf) == type_t and typeClass(tf) == synonym_t) {
        arityCheck(tf, arity, here);
        setTypeClass(tf, abstract_t);
        return;
    }
    if (idVal(tf) != UNDEF) {
        core_state.s.errs = here;
        nameclash(tf);
        return;
    }
    if (type_class != synonym_t) {
        cs.newtyps = add1(tf, cs.newtyps);
    }
    setIdVal(tf, makeTyp(arity, if (type_class == algebraic_t) makePn(UNDEF) else 0, type_class, info));
    if (idType(tf) != undef_t) {
        core_state.s.errs = here;
        respecError(tf);
        return;
    }
    addToEnv(tf);
    setIdWho(tf, here);
    setIdType(tf, type_t);
}

/// Declare a single binding `x` = `e` (the inner step).
fn decl1(x: Word, e: Word) void {
    if (idVal(x) != UNDEF and rt.rs.lastname != x) {
        core_state.s.errs = h(e);
        nameclash(x);
        return;
    }
    if (idVal(x) == UNDEF) {
        setIdVal(x, tries(x, cons(e, NIL)));
        if (idWho(x) != NIL) {
            cs.speclocs = cons(cons(x, idWho(x)), cs.speclocs);
        }
        setIdWho(x, h(e));
        if (idType(x) == undef_t) {
            addToEnv(x);
        }
    } else if (fallible(h(t(idVal(x)))) == 0) {
        const prefix: [*:0]const u8 = if (rt.rs.echoing != 0) "\n" else "";
        core_state.s.errs = h(e);
        _ = word.print("{s}syntax error: unreachable case in defn of \"{s}\"\n", .{ prefix, getId(x) });
        acterror();
    } else {
        tp(idVal(x)).* = cons(e, t(idVal(x)));
    }
}

/// Declare definition `x` = `e` in the environment.
pub fn declare(x: Word, e: Word) void {
    if (getTag(x) == .ID and !isConstructor(x)) {
        decl1(x, e);
        return;
    }
    var bindings = scanpattern(x, x, share(tries(x, cons(e, NIL)), undef_t), ap(CONFERROR, cons(x, h(e))));
    if (bindings == NIL) {
        core_state.s.errs = h(e);
        syntax("illegal lhs for definition\n");
        return;
    }
    rt.rs.lastname = 0;
    while (bindings != NIL) {
        const binding = h(bindings);
        const name = h(binding);
        if (idVal(name) != UNDEF) {
            core_state.s.errs = h(e);
            nameclash(name);
            return;
        }
        setIdVal(name, t(binding));
        if (idWho(name) != NIL) {
            cs.speclocs = cons(cons(name, idWho(name)), cs.speclocs);
        }
        setIdWho(name, h(e));
        if (idType(name) == undef_t) {
            addToEnv(name);
        }
        bindings = t(bindings);
    }
}

/// Translate a block of definitions over expression `e`.
pub fn block(input_defs: Word, input_e: Word, keep: Word) Word {
    var defs = input_defs;
    var e = input_e;
    var ids: Word = NIL;
    var deftoids: Word = NIL;
    var g: Word = NIL;
    if (core_state.s.SYNERR != 0) {
        return NIL;
    }
    var d = defs;
    while (d != NIL) : (d = t(d)) {
        const x = getIds(dlhs(h(d)));
        ids = UNION(ids, x);
        deftoids = cons(cons(h(d), x), deftoids);
    }
    defs = sort(defs);
    d = defs;
    while (d != NIL) : (d = t(d)) {
        var x = intersection(deps(dval(h(d))), ids);
        var y: Word = NIL;
        while (x != NIL) : (x = t(x)) {
            y = add1(invgetrel(deftoids, h(x)), y);
        }
        g = cons(cons(h(d), add1(h(d), y)), g);
    }
    g = reverse(g);
    g = tclos(g);
    {
        var x = intersection(deps(e), ids);
        var y: Word = NIL;
        while (x != NIL) : (x = t(x)) {
            d = invgetrel(deftoids, h(x));
            if (member(y, d) == 0) {
                y = UNION(y, getrel(g, d));
            }
        }
        defs = setdiff(defs, y);
        if (defs != NIL) {
            rt.rs.detrop = append1(rt.rs.detrop, defs);
        }
        if (keep != 0) {
            return letrec(y, e);
        }
    }
    g = msc(g);
    g = tsort(g);
    g = reverse(g);
    while (g != NIL) : (g = t(g)) {
        if (t(h(g)) == NIL and intersection(getIds(dlhs(h(h(g)))), deps(dval(h(h(g))))) == NIL) {
            e = let(h(h(g)), e);
        } else {
            e = letrec(h(g), e);
        }
    }
    return e;
}

/// Transitive closure of relation `r`.
pub fn tclos(r: Word) Word {
    var r1 = r;
    while (r1 != NIL) : (r1 = t(r1)) {
        var x = less1(t(h(r1)), h(h(r1)));
        while (x != NIL) {
            x = imageless(r, x, t(h(r1)));
            tp(h(r1)).* = UNION(t(h(r1)), x);
        }
    }
    return r;
}

/// The image (successors) of `x` under relation `r`.
pub fn getrel(input_r: Word, x: Word) Word {
    var r = input_r;
    while (r != NIL and h(h(r)) != x) r = t(r);
    return if (r == NIL) NIL else t(h(r));
}

/// The inverse image (predecessors) of `x` under relation `r`.
pub fn invgetrel(input_r: Word, x: Word) Word {
    var r = input_r;
    while (r != NIL and member(t(h(r)), x) == 0) r = t(r);
    if (r == NIL) {
        std.debug.print("impossible event in invgetrel\n", .{});
        abi.exit(1);
    }
    return h(h(r));
}

/// The image of `y` under `r`, excluding `z`.
pub fn imageless(input_r: Word, input_y: Word, z: Word) Word {
    var r = input_r;
    var y = input_y;
    var i: Word = NIL;
    while (r != NIL and y != NIL) {
        if (h(h(r)) == h(y)) {
            i = UNION(i, less(t(h(r)), z));
            r = t(r);
            y = t(y);
        } else if (h(h(r)) < h(y)) {
            r = t(r);
        } else {
            y = t(y);
        }
    }
    return i;
}

/// Whether `x` should sort before `y`.
pub fn less(input_x: Word, input_y: Word) Word {
    var x = input_x;
    var y = input_y;
    var r: Word = NIL;
    while (x != NIL and y != NIL) {
        if (h(x) == h(y)) {
            x = t(x);
            y = t(y);
        } else if (h(x) < h(y)) {
            r = cons(h(x), r);
            x = t(x);
        } else {
            y = t(y);
        }
    }
    return shunt(r, x);
}

/// The elements of `x` that sort before `a`.
pub fn less1(input_x: Word, a: Word) Word {
    var x = input_x;
    var r: Word = NIL;
    while (x != NIL and h(x) != a) {
        r = cons(h(x), r);
        x = t(x);
    }
    return shunt(r, if (x == NIL) NIL else t(x));
}

/// Sort list `x`.
///
/// Tests: sort: orders a Word list ascending
pub fn sort(input_x: Word) Word {
    var x = input_x;
    var a: Word = NIL;
    var b: Word = NIL;
    if (x == NIL or t(x) == NIL) return x;
    while (x != NIL) {
        const hold = a;
        a = cons(h(x), b);
        b = hold;
        x = t(x);
    }
    a = sort(a);
    b = sort(b);
    while (a != NIL and b != NIL) {
        if (h(a) < h(b)) {
            x = cons(h(a), x);
            a = t(a);
        } else {
            x = cons(h(b), x);
            b = t(b);
        }
    }
    if (a == NIL) a = b;
    while (a != NIL) {
        x = cons(h(a), x);
        a = t(a);
    }
    return reverse(x);
}

test "sort: orders a Word list ascending" {
    tu.freshInterp();
    try tu.expectWords(&[_]Word{ 1000, 2000, 3000 }, sort(tu.list(&[_]Word{ 3000, 1000, 2000 })));
    try tu.expectWords(&[_]Word{}, sort(NIL));
}

/// Topologically sort relation `x`.
pub fn sortrel(input_x: Word) Word {
    var x = input_x;
    var a: Word = NIL;
    var b: Word = NIL;
    if (x == NIL or t(x) == NIL) return x;
    while (x != NIL) {
        const hold = a;
        a = cons(h(x), b);
        b = hold;
        x = t(x);
    }
    a = sortrel(a);
    b = sortrel(b);
    while (a != NIL and b != NIL) {
        if (h(h(a)) < h(h(b))) {
            x = cons(h(a), x);
            a = t(a);
        } else {
            x = cons(h(b), x);
            b = t(b);
        }
    }
    if (a == NIL) a = b;
    while (a != NIL) {
        x = cons(h(a), x);
        a = t(a);
    }
    return reverse(x);
}

const Ush: Word = CMBASE + 93;
const Ush1: Word = CMBASE + 94;
const LEX_RPT: Word = CMBASE + 112;
const LEX_RPT1: Word = CMBASE + 113;
const LEX_TRY: Word = CMBASE + 114;
const LEX_TRY1: Word = CMBASE + 116;

const mklexvar = lex.mklexvar;
const ispoly = types_mod.ispoly;

/// Whether a type node is a tuple (comma) type.
/// Whether a type node is a type variable.

/// The `show` function of a type node.
fn tShowfn(x: Word) Word {
    return t(h(t(x)));
}
/// The class of a type node.
fn tClass(x: Word) Word {
    return h(t(t(x)));
}
/// The info field of a type node.
fn tInfo(x: Word) Word {
    return t(t(t(x)));
}

/// Whether id `x` names a data constructor.
/// Whether id `x` names an ordinary variable.

/// The head of private-name node `x`.
/// The value (tail) of private-name node `x`.

/// Whether constructor `k` is the sole constructor of its type.

/// Compile expression `x` to its final combinator graph — the codegen entry point.
pub fn codegen(x: Word) Word {
    switch (getTag(x)) {
        .AP => {
            // Walk the application spine (the deep recursion is codegen(h(x)))
            // iteratively so a long chain can't overflow the stack. Each node's
            // per-node logic mirrors the recursive form exactly; only the special
            // forms (the $±/stdin shares and the APPEND-NIL reversal) terminate
            // the spine and fall back to a single recursive codegen() call — they
            // are never deep.
            var spine: std.ArrayList(Word) = .empty;
            defer spine.deinit(rt.allocator);
            var cur = x;
            var acc = while (true) {
                if (getTag(cur) != .AP) break codegen(cur);
                const shares = cur == ls.cook_stdin or cur == ls.common_stdin or cur == ls.common_stdinb;
                const cmd = core_state.s.commandmode != 0 and !shares;
                if (!cmd and getTag(h(cur)) == .AP and h(h(cur)) == APPEND and t(h(cur)) == NIL) {
                    break codegen(t(cur)); // post typecheck reversal of HR bug fix
                }
                spine.append(rt.allocator, cur) catch heap.mallocPanic("codegen ap spine");
                cur = h(cur);
            };
            var i = spine.items.len;
            while (i > 0) {
                i -= 1;
                const n = spine.items[i];
                const shares = n == ls.cook_stdin or n == ls.common_stdin or n == ls.common_stdinb;
                if (core_state.s.commandmode != 0 and !shares) { // beware of corrupting lastexp; share $+ $-
                    acc = make(word.AP, acc, codegen(t(n)));
                } else {
                    hp(n).* = acc; // = codegen(h(n)), already computed down-spine
                    tp(n).* = codegen(t(n));
                    acc = if (getTag(h(n)) == .AP and h(h(n)) == G_ALT) leftfactor(n) else n;
                }
            }
            return acc;
        },
        .TCONS, .PAIR => {
            // Iterate the tuple spine (recursed via t(x)) so a large tuple can't
            // overflow the stack; mirrors the cons-list fix.
            const result = make(word.CONS, codegen(h(x)), NIL);
            var dst = tp(result);
            var cur = t(x);
            while (getTag(cur) == .TCONS or getTag(cur) == .PAIR) {
                dst.* = make(word.CONS, codegen(h(cur)), NIL);
                dst = tp(dst.*);
                cur = t(cur);
            }
            dst.* = codegen(cur); // final element
            return result;
        },
        .CONS => {
            // Walk the cons spine iteratively rather than recursing on the tail:
            // a long string/list literal (e.g. a 4096-char string) would otherwise
            // recurse once per element and overflow the stack (codegen's frame is
            // large). Recursion is kept only for each head and the final tail.
            if (core_state.s.commandmode != 0) {
                const result = make(word.CONS, codegen(h(x)), NIL);
                var dst = tp(result);
                var cur = t(x);
                while (getTag(cur) == .CONS) {
                    dst.* = make(word.CONS, codegen(h(cur)), NIL);
                    dst = tp(dst.*);
                    cur = t(cur);
                }
                dst.* = codegen(cur); // final non-cons tail (e.g. NIL)
                return result;
            }
            // otherwise do in situ (see declare)
            var cur = x;
            while (true) {
                hp(cur).* = codegen(h(cur));
                const nxt = t(cur);
                if (getTag(nxt) == .CONS) {
                    cur = nxt; // tail is unchanged by in-situ codegen; keep walking
                } else {
                    tp(cur).* = codegen(nxt);
                    break;
                }
            }
            return x;
        },
        .LAMBDA => {
            return abstract(h(x), codegen(t(x)));
        },
        .LET => {
            return translet(h(x), t(x));
        },
        .LETREC => {
            return transletrec(h(x), t(x));
        },
        .TRIES => {
            return transtries(h(x), t(x));
        },
        .LABEL => {
            return codegen(t(x));
        },
        .SHOW => {
            return makeshow(h(x), t(x));
        },
        .LEXER => {
            var r: Word = NIL;
            var uses_state: Word = 0;
            var cur_x = x;
            while (cur_x != NIL) {
                var rule = abstr(mklexvar(0), codegen(t(t(h(cur_x)))));
                rule = abstr(mklexvar(1), rule);
                if (!(getTag(rule) == .AP and h(rule) == K)) {
                    uses_state = 1;
                }
                r = cons(cons(h(h(cur_x)), // start condition stuff
                    cons(ap(h(t(h(cur_x))), NIL), // matcher []
                        rule)), r);
                cur_x = t(cur_x);
            }
            if (uses_state == 0) { // strip off (K -) from each rule
                var cur_y = r;
                while (cur_y != NIL) {
                    tp(t(h(cur_y))).* = t(t(t(h(cur_y))));
                    cur_y = t(cur_y);
                }
                r = ap(LEX_RPT, ap(LEX_TRY, r));
            } else {
                r = ap(LEX_RPT1, ap(LEX_TRY1, r));
            }
            return ap(r, 0); // 0 startcond
        },
        .STARTREADVALS => {
            if (ispoly(t(x)) != 0) {
                const name_str: [*:0]const u8 = if (ls.cook_stdin != 0 and x == h(ls.cook_stdin)) "$+" else "readvals or $+";
                _ = word.print("type error - {s} used at polymorphic type :: [", .{name_str});
                outType(redtvars(t(x)));
                _ = word.print("]\n", .{});
                cs.polyshowerror = 1;
                if (cs.current_id != 0) {
                    cs.ND = add1(cs.current_id, cs.ND);
                    setIdType(cs.current_id, wrong_t);
                    setIdVal(cs.current_id, UNDEF);
                }
                if (h(x) != 0) {
                    sayhere(h(x), 1);
                }
            }
            if (core_state.s.commandmode != 0) {
                rt.rs.rv_expr = 1;
            } else {
                cs.rv_script = 1;
            }
            return x;
        },
        .SHARE => {
            if (t(x) != -1) { // arbitrary flag for already visited
                hp(x).* = codegen(h(x));
                tp(x).* = -1;
            }
            return h(x);
        },
        else => {
            if (x == NILS) {
                return NIL;
            }
            return x; // identifier, private name, or constant
        },
    }
}

/// Generate the `show` functions for all declared types.
pub fn genshfns() void {
    var s = cs.newtyps;
    while (s != NIL) {
        if (tClass(h(s)) == algebraic_t) {
            var f: Word = 0;
            var r = tInfo(h(s)); // r is list of constructors
            const ush = if (t(r) == NIL and member(cs.SGC, h(r)) != 0) Ush1 else Ush;
            while (r != NIL) {
                var type_var = idType(h(r));
                var k = idVal(h(r));
                while (getTag(k) != .CONSTRUCTOR) {
                    k = t(k); // lawful and !'d constructors
                }
                // k now holds constructor(i,main.hd(r))
                while (isArrowType(type_var)) {
                    k = ap(k, mkshow(1, 1, t(h(type_var))));
                    type_var = t(type_var);
                }
                k = ap(ush, k);
                while (isCompoundType(type_var)) {
                    k = abstr(t(type_var), k);
                    type_var = h(type_var);
                }
                // see kahrs.bug.m (this is the fix)
                if (f != 0) {
                    f = ap2(TRY, k, f);
                } else {
                    f = k;
                }
                r = t(r);
            }
            // f ~= 0, placeholder types dealt with in specify()
            tp(tShowfn(h(s))).* = f;
            cs.algshfns = cons(tShowfn(h(s)), cs.algshfns);
        } else if (tClass(h(s)) == abstract_t) {
            if (tShowfn(h(s)) != 0) {
                if (abshfnck(h(s), idType(tShowfn(h(s)))) == 0) {
                    _ = word.print("warning - \"{s}\" has type inappropriate for a show-function\n", .{getId(tShowfn(h(s)))});
                    tp(tShowfn(h(s))).* = 0;
                }
            }
        }
        s = t(s);
    }
}
