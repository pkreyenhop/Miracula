//! lower.zig (split from compiler/trans.zig, Phase 4 step 3,
//! docs/ZIG_NATIVE_PLAN.md) — translation from parse trees to combinator
//! graphs.
//!
//! Turns definitions and expressions into the `S`/`K`/`I`… combinator graph the
//! reducer runs: bracket abstraction (`abstract`/`abstr`/`combine`), `let`/
//! `letrec` and ZF list-comprehension translation (`translet`/`transzf`),
//! `show`-function generation, and the top-level `codegen`. Also handles
//! declaration bookkeeping (`declare`/`declType`/`declconstr`, name-clash and
//! arity checks) and the relation/topological-sort helpers used to order
//! mutually-recursive groups. Pattern-match compilation itself
//! (`scanpattern`/`transtries`/`genlhs`) lives in the sibling `match.zig` --
//! `declare` and `codegen` call into it, and it calls back into this file's
//! `codegen` (`transtries` codegens each match alternative), a genuine
//! two-way dependency inherent to the algorithm, not an accident of the split.

const std = @import("std");
const word = @import("../graph/word.zig");
const strtab = @import("../graph/strtab.zig");

const os = @import("../os.zig");

const compiler_state = @import("../compiler/compiler_state.zig");
const cs = compiler_state.cs;
// `abi` — a private namespace of libc re-export aliases so this file can write
// `os.printf(...)`, etc. Internal only (the container is not `pub`, so these
// never appear in autodoc); each member re-exports a `os` symbol.

const lex_state = @import("../parser/lex_state.zig");
const core_state = @import("../runtime/core_state.zig");
const tu = @import("../testutil.zig"); // unit-test harness (test builds only)
const ls = lex_state.ls;
const match = @import("match.zig");

/// The standard-output `Stream` handle.
fn getStdout() ?*word.Stream {
    return os.stdout();
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
// Type-declaration kind codes — single source of truth in `word.zig`. These used to
// carry a local 0/1/2/3 numbering that disagreed with word.zig's (then 2/3/5); that
// mismatch was a real bug (codegen wrote word.* values that this checker misread, so
// every user `::=` type was processed as an `abstype`). word.zig has since been
// renumbered to these values and the goldens `algebraic_*` lock the behaviour.
const algebraic_t = word.algebraic_t;
const synonym_t = word.synonym_t;
const abstract_t = word.abstract_t;
const placeholder_t = word.placeholder_t;
const CONST = word.CONST;
const ATOMLIMIT = word.ATOMLIMIT;

// NIL

// NIL

// NIL

// NIL

// Cross-module functions: direct @import aliases replace extern-fn linker
// declarations (R7.3 — eliminate the linker-as-module-system pattern).
const heap_mod = @import("../graph/heap.zig");
const Heap = heap_mod.Heap;
const print_mod = @import("../graph/print.zig");
const depend = @import("depend.zig");
const type_errors = @import("type_errors.zig");
const unify_mod = @import("unify.zig");
const big = @import("../graph/bignum.zig");
const lex = @import("../parser/lex.zig");
const setup = @import("../compiler/setup.zig");
const rt = @import("../runtime/runtime_state.zig");
const script_store = @import("../session/script_store.zig");
const repl_session = @import("../session/repl_session.zig");
const show_fns = @import("show_fns.zig");

const make = heap_mod.make;
const append1 = heap_mod.append1;
const reverse = heap_mod.reverse;
const shunt = heap_mod.shunt;
const out = print_mod.outTerm;
const member = depend.member;
const UNION = depend.UNION;
const add1 = depend.add1;
const deps = depend.deps;
const intersection = depend.intersection;
const outType = type_errors.outType;
const redtvars = unify_mod.redtvars;
const sayhere = type_errors.sayhere;
const setdiff = depend.setdiff;
const msc = depend.msc;
const tsort = depend.tsort;
const isnat = big.isNat;
const isconstrname = lex.isconstrname;
const makePn = lex.makePn;
const mkgvar = lex.mkgvar;
const syntax = setup.syntax;
const acterror = setup.acterror;

/// The node tag of cell `x`.
inline fn getTag(heap: *Heap, x: Word) word.NodeTag {
    return heap.getTag(x);
}

/// Head (`hd`) of cell `x`.
fn h(heap: *Heap, x: Word) Word {
    return heap.h(x);
}

/// Pointer to the head field of cell `x`.
fn hp(heap: *Heap, x: Word) *Word {
    return heap.hp(x);
}

/// Tail (`tl`) of cell `x`.
fn t(heap: *Heap, x: Word) Word {
    return heap.t(x);
}

/// Pointer to the tail field of cell `x`.
fn tp(heap: *Heap, x: Word) *Word {
    return heap.tp(x);
}

/// The head of an application spine (walk `hd` while it is an `AP`).
fn appHead(heap: *Heap, input_x: Word) Word {
    var x = input_x;
    while (getTag(heap, x) == .AP) {
        x = h(heap, x);
    }
    return x;
}

/// Allocate a `CONS` cell `(x . y)`.
fn cons(x: Word, y: Word) Word {
    return make(heap_mod.heap(), .CONS, x, y);
}

/// Allocate a `PAIR` cell `(x . y)`.
fn pair(heap: *Heap, x: Word, y: Word) Word {
    return make(heap, .PAIR, x, y);
}

/// Allocate a `DATAPAIR` cell.
fn datapair(heap: *Heap, x: Word, y: Word) Word {
    return make(heap, .DATAPAIR, x, y);
}

/// Allocate a `CONSTRUCTOR` cell (tag `n`, fields `x`).
fn constructor(heap: *Heap, n: Word, x: Word) Word {
    return make(heap, .CONSTRUCTOR, n, x);
}

/// Allocate a `LAMBDA` cell `(x . y)`.
fn lambda(heap: *Heap, x: Word, y: Word) Word {
    return make(heap, .LAMBDA, x, y);
}

/// Allocate a `SHARE` cell (a shared / lazily-evaluated binding).
fn share(heap: *Heap, x: Word, y: Word) Word {
    return make(heap, .SHARE, x, y);
}

/// Allocate a `TRIES` cell (a chain of pattern-match alternatives).
fn tries(heap: *Heap, x: Word, y: Word) Word {
    return make(heap, .TRIES, x, y);
}

/// Allocate a `LET` cell.
fn let(heap: *Heap, x: Word, y: Word) Word {
    return make(heap, .LET, x, y);
}

/// Allocate a `LETREC` cell.
fn letrec(heap: *Heap, x: Word, y: Word) Word {
    return make(heap, .LETREC, x, y);
}

/// Allocate an application `(x y)`.
fn ap(x: Word, y: Word) Word {
    return make(heap_mod.heap(), .AP, x, y);
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
pub fn getId(heap: *Heap, x: Word) [*:0]const u8 {
    return strtab.strOf(strtab.table(), h(heap, h(heap, h(heap, x))));
}

/// The definition-site field of id `x`.
fn idWho(heap: *Heap, x: Word) Word {
    return t(heap, h(heap, h(heap, x)));
}

/// Set the definition-site field of id `x`.
fn setIdWho(heap: *Heap, x: Word, value: Word) void {
    tp(heap, h(heap, h(heap, x))).* = value;
}

/// The type field of id `x`.
fn idType(heap: *Heap, x: Word) Word {
    return t(heap, h(heap, x));
}

/// The value field of id `x`.
fn idVal(heap: *Heap, x: Word) Word {
    return t(heap, x);
}

/// Set the type field of id `x`.
fn setIdType(heap: *Heap, x: Word, value: Word) void {
    tp(heap, h(heap, x)).* = value;
}

/// Set the value field of id `x`.
fn setIdVal(heap: *Heap, x: Word, value: Word) void {
    tp(heap, x).* = value;
}

/// Build a type descriptor cell `((arity . showfn) . (class . info))`.
fn makeTyp(arity: Word, showfn: Word, class: Word, info: Word) Word {
    return cons(cons(arity, showfn), cons(class, info));
}

/// Add id `x` to the current file's definition environment.
fn addToEnv(heap: *Heap, x: Word) void {
    const current_file_defs = h(heap, heap.files);
    if (current_file_defs >= ATOMLIMIT) {
        tp(heap, current_file_defs).* = cons(x, tp(heap, current_file_defs).*);
    }
}

/// Whether `x` names a data constructor.
fn isConstructor(heap: *Heap, x: Word) bool {
    return getTag(heap, x) == .ID and isconstrname(getId(heap, x));
}

/// Whether `x` names an ordinary variable.
fn isVariable(heap: *Heap, x: Word) bool {
    return getTag(heap, x) == .ID and !isconstrname(getId(heap, x));
}

/// Whether `x` is an `n+k` pattern.
fn isNPlusKPattern(heap: *Heap, x: Word) bool {
    return getTag(heap, x) == .AP and getTag(heap, h(heap, x)) == .AP and h(heap, h(heap, x)) == PLUS;
}

/// Whether a type node is a function (`->`) type.
fn isArrowType(heap: *Heap, x: Word) bool {
    return getTag(heap, x) == .AP and getTag(heap, h(heap, x)) == .AP and h(heap, h(heap, x)) == arrow_t;
}

/// Whether a type node is a list type.
fn isListType(heap: *Heap, x: Word) bool {
    return getTag(heap, x) == .AP and h(heap, x) == list_t;
}

/// Whether a type node is a type variable.
fn isTypeVariable(heap: *Heap, x: Word) bool {
    return getTag(heap, x) == .TVAR;
}

/// Whether a type node is a compound (application) type.
fn isCompoundType(heap: *Heap, x: Word) bool {
    return getTag(heap, x) == .AP;
}

/// Whether `x` is a char value.
fn isChar(x: Word) bool {
    return 0 <= x and x <= 255;
}

/// The arity recorded in a type descriptor.
fn typeArity(heap: *Heap, x: Word) Word {
    return h(heap, h(heap, t(heap, x)));
}

/// The `show` function recorded in a type descriptor.
fn typeShowFn(heap: *Heap, x: Word) Word {
    return t(heap, h(heap, t(heap, x)));
}

/// The class (algebraic/synonym/abstract) of a type descriptor.
fn typeClass(heap: *Heap, x: Word) Word {
    return h(heap, t(heap, t(heap, x)));
}

/// Set the class field of a type descriptor.
fn setTypeClass(heap: *Heap, x: Word, value: Word) void {
    hp(heap, t(heap, t(heap, x))).* = value;
}

/// The info field of a type descriptor.
fn typeInfo(heap: *Heap, x: Word) Word {
    return t(heap, t(heap, t(heap, x)));
}

/// Set the info field of a type descriptor.
fn setTypeInfo(heap: *Heap, x: Word, value: Word) void {
    tp(heap, t(heap, t(heap, x))).* = value;
}

/// The index of type variable `x`.
fn getTypeVariable(heap: *Heap, x: Word) Word {
    return t(heap, x);
}

/// Box index `i` (bare if small, else an `INT` cell).
fn mkindex(i: Word) Word {
    return if (word.fitsInByte(i)) i else make(heap_mod.heap(), .INT, i, 0);
}

/// The left-hand side of a definition cell `d`.
fn dlhs(heap: *Heap, d: Word) Word {
    return h(heap, d);
}

/// Set the left-hand side of a definition cell `d`.
fn setDlhs(heap: *Heap, d: Word, value: Word) void {
    hp(heap, d).* = value;
}

/// The value of a definition cell `d`.
fn dval(heap: *Heap, d: Word) Word {
    return t(heap, t(heap, d));
}

/// Set the value of a definition cell `d`.
fn setDval(heap: *Heap, d: Word, value: Word) void {
    tp(heap, t(heap, d)).* = value;
}

/// The underlying `CONSTRUCTOR` cell of id `x` (through any `MKSTRICT` wrapper).
pub fn primconstr(heap: *Heap, input_x: Word) Word {
    var x = t(heap, input_x); // idVal(heap, x) = CONSTRUCTOR cell (or MKSTRICT wrapper for strict ctors)
    while (getTag(heap, x) != .CONSTRUCTOR) {
        x = t(heap, x);
    }
    return x;
}

/// Whether `x` is a member of list `l`.
///
/// Tests: memb: membership in a list
pub fn memb(heap: *Heap, input_l: Word, x: Word) Word {
    var l = input_l;
    if (getTag(heap, x) == .TVAR) {
        while (l != NIL and t(heap, h(heap, l)) != t(heap, x)) {
            l = t(heap, l);
        }
    } else {
        while (l != NIL and h(heap, l) != x) {
            l = t(heap, l);
        }
    }
    return if (l != NIL) 1 else 0;
}

test "memb: membership in a list" {
    tu.freshInterp();
    const l = cons(word.True, cons(word.False, NIL));
    try std.testing.expectEqual(@as(Word, 1), memb(heap_mod.heap(), l, word.False));
    try std.testing.expectEqual(@as(Word, 0), memb(heap_mod.heap(), l, word.S));
}

/// Whether `x` and `y` are structurally equal.
///
/// Tests: same: structural equality of graphs
pub fn same(heap: *Heap, x: Word, y: Word) Word {
    if (x == y) {
        return 1;
    }
    const x_tag = getTag(heap, x);
    const y_tag = getTag(heap, y);
    if (x_tag == .ATOM or y_tag == .ATOM or x_tag != y_tag) {
        return 0;
    }
    if (@intFromEnum(x_tag) < @intFromEnum(word.NodeTag.INT)) {
        return if (h(heap, x) == h(heap, y) and t(heap, x) == t(heap, y)) 1 else 0;
    }
    if (@intFromEnum(x_tag) > @intFromEnum(word.NodeTag.STRCONS)) {
        return if (same(heap, h(heap, x), h(heap, y)) != 0 and same(heap, t(heap, x), t(heap, y)) != 0) 1 else 0;
    }
    return if (h(heap, x) == h(heap, y) and same(heap, t(heap, x), t(heap, y)) != 0) 1 else 0;
}

test "same: structural equality of graphs" {
    tu.freshInterp();
    try std.testing.expectEqual(@as(Word, 1), same(heap_mod.heap(), word.True, word.True));
    const a = cons(word.True, NIL);
    const b = cons(word.True, NIL);
    try std.testing.expectEqual(@as(Word, 1), same(heap_mod.heap(), a, b)); // distinct cells, equal structure
    try std.testing.expectEqual(@as(Word, 0), same(heap_mod.heap(), a, cons(word.False, NIL)));
}

/// Collect the identifiers bound by pattern/definition `x`.
pub fn getIds(heap: *Heap, x: Word) Word {
    if (word.isAtom(x)) {
        return NIL;
    }
    if (h(heap, x) == CONST or isConstructor(heap, x)) {
        return NIL;
    }
    if (getTag(heap, x) == .ID) {
        return cons(x, NIL);
    }
    if (isNPlusKPattern(heap, x)) {
        return getIds(heap, t(heap, x));
    }
    return UNION(heap, getIds(heap, h(heap, x)), getIds(heap, t(heap, x)));
}

/// Build a tuple from element list `x`.
pub fn mktuple(heap: *Heap, input_x: Word) Word {
    var x = input_x;
    if (word.isAtom(x)) {
        return NIL;
    }
    if (h(heap, x) == CONST or isConstructor(heap, x)) {
        return NIL;
    }
    if (getTag(heap, x) == .ID) {
        return x;
    }
    if (isNPlusKPattern(heap, x)) {
        return mktuple(heap, t(heap, x));
    }
    const y = mktuple(heap, t(heap, x));
    x = mktuple(heap, h(heap, x));
    return if (x == NIL) y else if (y == NIL) x else pair(heap, x, y);
}

/// Whether pattern `x` is irrefutable (always matches).
pub fn irrefutable(heap: *Heap, x: Word) Word {
    if (word.isAtom(x)) {
        return 0;
    }
    if (getTag(heap, x) == .CONS) {
        return 0;
    }
    if (isConstructor(heap, x)) {
        return member(heap, cs().SGC, x);
    }
    if (getTag(heap, x) == .ID) {
        return 1;
    }
    if (isNPlusKPattern(heap, x)) {
        return 0;
    }
    return if (irrefutable(heap, h(heap, x)) != 0 and irrefutable(heap, t(heap, x)) != 0) 1 else 0;
}

/// Whether expression `e` may fail to match.
pub fn fallible(heap: *Heap, input_e: Word) Word {
    var e = input_e;
    while (true) {
        const e_tag = getTag(heap, e);
        switch (e_tag) {
            .LABEL => {
                e = t(heap, e);
                continue;
            },
            .LETREC, .LET => {
                e = t(heap, e);
            },
            .LAMBDA => {
                if (irrefutable(heap, h(heap, e)) != 0) {
                    e = t(heap, e);
                } else {
                    return 1;
                }
            },
            .AP => {
                if (getTag(heap, h(heap, e)) == .AP and getTag(heap, h(heap, h(heap, e))) == .AP and h(heap, h(heap, h(heap, e))) == COND) {
                    e = t(heap, e);
                } else {
                    return if (e == FAIL) 1 else 0;
                }
            },
            else => {
                return if (e == FAIL) 1 else 0;
            },
        }
    }
}

/// The source-location info attached to right-hand side `rhs`.
pub fn hereInfo(heap: *Heap, rhs: Word) Word {
    var x = t(heap, rhs);
    while (t(heap, x) != NIL) {
        x = t(heap, x);
    }
    return h(heap, h(heap, x));
}

/// The last cell of list `x`.
///
/// Tests: lastlink: the last cell of a list
pub fn lastlink(heap: *Heap, input_x: Word) Word {
    var x = input_x;
    while (t(heap, x) != NIL) {
        x = t(heap, x);
    }
    return x;
}

test "lastlink: the last cell of a list" {
    tu.freshInterp();
    const l = cons(word.True, cons(word.False, cons(word.S, NIL)));
    const last = lastlink(heap_mod.heap(), l);
    try std.testing.expectEqual(@as(Word, word.S), h(heap_mod.heap(), last));
    try std.testing.expectEqual(@as(Word, NIL), t(heap_mod.heap(), last));
}

/// Rewrite repeated variables in comprehension qualifiers `qq` into equality guards.
pub fn fixrepeats(heap: *Heap, input_qq: Word) Word {
    var q = h(heap, input_qq);
    var rhs = q;
    var qq = t(heap, input_qq);
    while (h(heap, rhs) == REPEAT) {
        rhs = t(heap, t(heap, rhs));
    }
    rhs = t(heap, t(heap, rhs));
    while (h(heap, q) == REPEAT) {
        qq = cons(cons(GENERATOR, cons(h(heap, t(heap, q)), rhs)), qq);
        q = t(heap, t(heap, q));
    }
    return cons(q, qq);
}

/// Abstract a show function `f` over a type's arity parameters.
pub fn abshfnck(heap: *Heap, t_type: Word, f_input: Word) Word {
    var f = f_input;
    var n = typeArity(heap, t_type);
    var i: Word = 1;
    while (i <= n) {
        if (!isArrowType(heap, f)) {
            return 0;
        }
        const param = t(heap, h(heap, f));
        if (!(isArrowType(heap, param) and isTypeVariable(heap, t(heap, h(heap, param))) and getTypeVariable(heap, t(heap, h(heap, param))) == i and isListType(heap, t(heap, param)) and t(heap, t(heap, param)) == char_t)) {
            return 0;
        }
        i += 1;
        f = t(heap, f);
    }
    if (!(isArrowType(heap, f) and isListType(heap, t(heap, f)) and t(heap, t(heap, f)) == char_t)) {
        return 0;
    }
    f = t(heap, h(heap, f));
    while (isCompoundType(heap, f) and isTypeVariable(heap, t(heap, f)) and getTypeVariable(heap, t(heap, f)) == n) {
        n -= 1;
        f = h(heap, f);
    }
    return if (f == t_type) 1 else 0;
}

/// Combine two bracket-abstraction results, optimising redundant `K`s.
pub fn combine(heap: *Heap, x: Word, y: Word) Word {
    const a = getTag(heap, x) == .AP and h(heap, x) == K;
    const b = getTag(heap, y) == .AP and h(heap, y) == K;
    if (a and b) {
        return ap(K, ap(t(heap, x), t(heap, y)));
    }
    if (a and y == I) {
        return t(heap, x);
    }
    const b1 = getTag(heap, y) == .AP and getTag(heap, h(heap, y)) == .AP and h(heap, h(heap, y)) == B;
    if (a) {
        if (b1) {
            return ap3(B1, t(heap, x), t(heap, h(heap, y)), t(heap, y));
        }
        if (getTag(heap, t(heap, x)) == .AP and getTag(heap, h(heap, t(heap, x))) == .AP and h(heap, h(heap, t(heap, x))) == COND) {
            return ap3(COND, t(heap, h(heap, t(heap, x))), ap(K, t(heap, t(heap, x))), y);
        }
        return ap2(B, t(heap, x), y);
    }
    const a1 = getTag(heap, x) == .AP and getTag(heap, h(heap, x)) == .AP and h(heap, h(heap, x)) == B;
    if (b) {
        if (a1) {
            if (getTag(heap, t(heap, h(heap, x))) == .AP and h(heap, t(heap, h(heap, x))) == COND) {
                return ap3(COND, t(heap, t(heap, h(heap, x))), t(heap, x), y);
            }
            return ap3(C1, t(heap, h(heap, x)), t(heap, x), t(heap, y));
        }
        return ap2(C, x, t(heap, y));
    }
    if (a1) {
        if (getTag(heap, t(heap, h(heap, x))) == .AP and h(heap, t(heap, h(heap, x))) == COND) {
            return ap3(COND, t(heap, t(heap, h(heap, x))), t(heap, x), y);
        }
        return ap3(S1, t(heap, h(heap, x)), t(heap, x), y);
    }
    return ap2(S, x, y);
}

/// Combine two abstraction results building a cons, optimising the `K` cases.
pub fn liscomb(heap: *Heap, x: Word, y: Word) Word {
    const a = getTag(heap, x) == .AP and h(heap, x) == K;
    const b = getTag(heap, y) == .AP and h(heap, y) == K;
    if (a and b) {
        return ap(K, cons(t(heap, x), t(heap, y)));
    }
    if (a) {
        if (y == I) {
            return ap(P, t(heap, x));
        }
        return ap2(B_p, t(heap, x), y);
    }
    if (b) {
        return ap2(C_p, x, t(heap, y));
    }
    return ap2(S_p, x, y);
}

/// Bracket-abstract variable `x` out of expression `e` (Turner's algorithm).
pub fn abstract(heap: *Heap, input_x: Word, input_e: Word) Word {
    var x = input_x;
    var e = input_e;
    switch (getTag(heap, x)) {
        .ID => {
            if (isConstructor(heap, x)) {
                return if (member(heap, cs().SGC, x) != 0) ap(K, e) else ap2(Ug, primconstr(heap, x), e);
            }
            return abstr(heap, x, e);
        },
        .CONS => {
            if (h(heap, x) == CONST) {
                if (getTag(heap, t(heap, x)) == .INT) {
                    return ap2(MATCHINT, t(heap, x), e);
                }
                return ap2(MATCH, if (t(heap, x) == NILS) NIL else t(heap, x), e);
            }
            return ap(U_, abstract(heap, h(heap, x), abstract(heap, t(heap, x), e)));
        },
        .TCONS, .PAIR => return ap(U, abstract(heap, h(heap, x), abstract(heap, t(heap, x), e))),
        .AP => {
            if (member(heap, cs().SGC, appHead(heap, x)) != 0) {
                return ap(Uf, abstract(heap, h(heap, x), abstract(heap, t(heap, x), e)));
            }
            if (getTag(heap, h(heap, x)) == .AP and h(heap, h(heap, x)) == PLUS) {
                return ap2(ATLEAST, t(heap, h(heap, x)), abstract(heap, t(heap, x), e));
            }
            while (getTag(heap, x) == .AP) {
                e = abstract(heap, t(heap, x), e);
                x = h(heap, x);
            }
        },
        else => {},
    }
    if (isConstructor(heap, x)) {
        return ap2(Ug, primconstr(heap, x), e);
    }
    _ = word.print("error in declaration of \"{s}\", undeclared constructor in pattern: ", .{getId(heap, cs().current_id)});
    const stdout_val = getStdout();
    out(heap, stdout_val, x);
    _ = word.print("\n", .{});
    return NIL;
}

/// Bracket-abstract `x` from `e` (the recursive inner step).
pub fn abstr(heap: *Heap, x: Word, e: Word) Word {
    switch (getTag(heap, e)) {
        .TCONS, .PAIR, .CONS => return liscomb(heap, abstr(heap, x, h(heap, e)), abstr(heap, x, t(heap, e))),
        .AP => {
            if (h(heap, e) == BADCASE or h(heap, e) == CONFERROR) {
                return ap(K, e);
            }
            return combine(heap, abstr(heap, x, h(heap, e)), abstr(heap, x, t(heap, e)));
        },
        .LAMBDA, .LET, .LETREC, .TRIES, .LABEL, .SHOW, .LEXER, .SHARE => {
            std.debug.print("impossible event in abstr (main.tag={d})\n", .{getTag(heap, e)});
            os.exit(1);
        },
        else => {
            if (x == e or (isTypeVariable(heap, x) and isTypeVariable(heap, e) and getTypeVariable(heap, x) == getTypeVariable(heap, e))) {
                return I;
            }
            return ap(K, e);
        },
    }
}

/// Bracket-abstract a list of variables `x` from `e`.
pub fn abstrlist(heap: *Heap, x_input: Word, e: Word) Word {
    switch (getTag(heap, e)) {
        .TCONS, .PAIR, .CONS => return liscomb(heap, abstrlist(heap, x_input, h(heap, e)), abstrlist(heap, x_input, t(heap, e))),
        .AP => {
            if (h(heap, e) == BADCASE or h(heap, e) == CONFERROR) {
                return ap(K, e);
            }
            return combine(heap, abstrlist(heap, x_input, h(heap, e)), abstrlist(heap, x_input, t(heap, e)));
        },
        .LAMBDA, .LET, .LETREC, .TRIES, .LABEL, .SHOW, .LEXER, .SHARE => {
            std.debug.print("impossible event in abstrlist (main.tag={d})\n", .{getTag(heap, e)});
            os.exit(1);
        },
        else => {
            var i: Word = 0;
            var x = x_input;
            while (x != NIL and h(heap, x) != e) {
                i += 1;
                x = t(heap, x);
            }
            if (x == NIL) {
                return ap(K, e);
            }
            return ap(SUBSCRIPT, mkindex(i));
        },
    }
}

/// Build a lazy (shared) binding for definition `d`.
pub fn mklazy(heap: *Heap, d: Word) Word {
    if (irrefutable(heap, dlhs(heap, d)) != 0) {
        return d;
    }
    const ids = mktuple(heap, dlhs(heap, d));
    if (ids == NIL) {
        std.debug.print("impossible event in mklazy\n", .{});
        return d;
    }
    setDval(heap, d, ap2(TRY, ap(lambda(heap, dlhs(heap, d), ids), dval(heap, d)), ap(CONFERROR, cons(dlhs(heap, d), hereInfo(heap, dval(heap, d))))));
    setDlhs(heap, d, ids);
    return d;
}

/// Build a lazy binding for `d` (the new-parser variant).
pub fn newMkLazy(heap: *Heap, d: Word) Word {
    const ids = getIds(heap, dlhs(heap, d));
    if (ids == NIL) {
        std.debug.print("impossible event in newMkLazy\n", .{});
        return d;
    }
    setDval(heap, d, ap2(TRY, ap(lambda(heap, dlhs(heap, d), ids), dval(heap, d)), ap(CONFERROR, cons(dlhs(heap, d), hereInfo(heap, dval(heap, d))))));
    setDlhs(heap, d, ids);
    return d;
}

/// Compile a ZF (list comprehension) expression.
pub fn compzf(heap: *Heap, input_e: Word, input_qq: Word, diag: Word) Word {
    var e = input_e;
    var qq = input_qq;
    var hold: Word = NIL;
    var r: Word = 0;
    var g1: Word = -1;
    while (qq != NIL) {
        if (h(heap, h(heap, qq)) == REPEAT) {
            qq = fixrepeats(heap, qq);
        }
        hold = cons(h(heap, qq), hold);
        if (h(heap, h(heap, qq)) == GUARD) {
            r += 1;
        }
        qq = t(heap, qq);
    }
    qq = hold;
    while (qq != NIL and h(heap, h(heap, qq)) == GUARD) {
        r -= 1;
        qq = t(heap, qq);
    }
    if (h(heap, h(heap, hold)) == GENERATOR) {
        g1 = t(heap, t(heap, h(heap, hold)));
    }
    e = transzf(heap, e, hold, if (diag != 0) rt.rs().diagonalise else rt.rs().concat);
    if (diag != 0) {
        while (r != 0) {
            r -= 1;
            e = ap(rt.rs().concat, e);
        }
    }
    return if (e == g1) ap2(APPEND, NIL, e) else e;
}

/// Translate a ZF comprehension body `e` over qualifiers `qq`.
pub fn transzf(heap: *Heap, e_input: Word, qq_input: Word, conc: Word) Word {
    var e = e_input;
    const qq = qq_input;
    if (qq == NIL) {
        return cons(e, NIL);
    }
    const q = h(heap, qq);
    if (h(heap, q) == GUARD) {
        return ap3(COND, t(heap, q), transzf(heap, e, t(heap, qq), conc), NIL);
    }
    if (t(heap, qq) == NIL) {
        if (h(heap, t(heap, q)) == e and isVariable(heap, e)) {
            return t(heap, t(heap, q));
        }
        if (irrefutable(heap, h(heap, t(heap, q))) != 0) {
            return ap2(MAP, lambda(heap, h(heap, t(heap, q)), e), t(heap, t(heap, q)));
        }
        return ap2(FLATMAP, lambda(heap, h(heap, t(heap, q)), cons(e, NIL)), t(heap, t(heap, q)));
    }
    const q2 = h(heap, t(heap, qq));
    if (h(heap, q2) == GUARD) {
        if (conc == rt.rs().concat) {
            tp(heap, t(heap, q)).* = ap2(FILTER, lambda(heap, h(heap, t(heap, q)), t(heap, q2)), t(heap, t(heap, q)));
            tp(heap, qq).* = t(heap, t(heap, qq));
            return transzf(heap, e, qq, conc);
        }
        e = ap3(COND, t(heap, q2), cons(e, NIL), NIL);
        tp(heap, qq).* = t(heap, t(heap, qq));
        return transzf(heap, e, qq, conc);
    }
    return ap(conc, transzf(heap, transzf(heap, e, t(heap, qq), conc), cons(q, NIL), conc));
}

/// The recorded source location of the type spec for `x`.
pub fn getspecloc(heap: *Heap, x: Word) Word {
    var s = cs().speclocs;
    while (s != NIL and h(heap, h(heap, s)) != x) {
        s = t(heap, s);
    }
    return if (s == NIL) idWho(heap, x) else t(heap, h(heap, s));
}

/// Translate a type identifier `x`.
pub fn transtypeid(heap: *Heap, x: Word) Word {
    const n_span = std.mem.span(getId(heap, x));
    if (std.mem.eql(u8, n_span, "bool")) return bool_t;
    if (std.mem.eql(u8, n_span, "num")) return num_t;
    if (std.mem.eql(u8, n_span, "char")) return char_t;
    return x;
}

/// Left-factor the common prefixes among grammar alternatives `x`.
pub fn leftfactor(heap: *Heap, x: Word) Word {
    var a: Word = undefined;
    var b: Word = undefined;
    var rhs = t(heap, h(heap, x));
    var d: Word = undefined;
    if (getTag(heap, rhs) == .AP and getTag(heap, h(heap, rhs)) == .AP and h(heap, h(heap, rhs)) == G_SEQ) {
        a = t(heap, h(heap, rhs));
        b = t(heap, rhs);
    } else {
        return x;
    }
    d = t(heap, x);
    if (same(heap, a, d) != 0) {
        hp(heap, x).* = ap(G_SEQ, a);
        tp(heap, x).* = ap2(G_ALT, b, G_UNIT);
        cs().lfrule += 1;
        return x;
    }
    if (getTag(heap, d) == .AP and getTag(heap, h(heap, d)) == .AP) {
        rhs = h(heap, h(heap, d));
    } else {
        return x;
    }
    if (rhs == G_SEQ and same(heap, a, t(heap, h(heap, d))) != 0) {
        rhs = t(heap, d);
        hp(heap, x).* = ap(G_SEQ, a);
        tp(heap, x).* = leftfactor(heap, ap2(G_ALT, b, rhs));
        cs().lfrule += 1;
        return x;
    }
    if (rhs != G_ALT) {
        return x;
    }
    rhs = t(heap, h(heap, d));
    if (same(heap, a, rhs) != 0) {
        d = t(heap, d);
        hp(heap, x).* = ap(G_ALT, ap2(G_SEQ, a, ap2(G_ALT, b, G_UNIT)));
        tp(heap, x).* = d;
        cs().lfrule += 1;
        return leftfactor(heap, x);
    }
    if (getTag(heap, rhs) == .AP and getTag(heap, h(heap, rhs)) == .AP and h(heap, h(heap, rhs)) == G_SEQ and same(heap, a, t(heap, h(heap, rhs))) != 0) {
        rhs = t(heap, rhs);
        d = t(heap, d);
        hp(heap, x).* = ap(G_ALT, ap2(G_SEQ, a, leftfactor(heap, ap2(G_ALT, b, rhs))));
        tp(heap, x).* = d;
        cs().lfrule += 1;
        return leftfactor(heap, x);
    }
    return x;
}

/// Translate a `let` of definition `d` in body `e`.
pub fn translet(heap: *Heap, d: Word, e: Word) Word {
    const x = mklazy(heap, d);
    return ap(abstract(heap, dlhs(heap, x), codegen(heap, e)), codegen(heap, dval(heap, x)));
}

/// Translate a `letrec` of definitions `dd` in body `e`.
pub fn transletrec(heap: *Heap, input_dd: Word, e: Word) Word {
    var dd = input_dd;
    var lhs: Word = NIL;
    var rhs: Word = NIL;
    var pn: Word = 1;
    while (dd != NIL) : (dd = t(heap, dd)) {
        var x = h(heap, dd);
        if (getTag(heap, dlhs(heap, x)) == .ID) {
            lhs = cons(dlhs(heap, x), lhs);
            rhs = cons(codegen(heap, dval(heap, x)), rhs);
        } else {
            var i: Word = 0;
            const p = mkgvar(heap, pn);
            pn += 1;
            x = newMkLazy(heap, x);
            var ids = dlhs(heap, x);
            lhs = cons(p, lhs);
            rhs = cons(codegen(heap, dval(heap, x)), rhs);
            while (ids != NIL) {
                lhs = cons(h(heap, ids), lhs);
                rhs = cons(ap2(SUBSCRIPT, mkindex(i), p), rhs);
                ids = t(heap, ids);
                i += 1;
            }
        }
    }
    if (t(heap, lhs) == NIL) {
        return ap(abstr(heap, h(heap, lhs), codegen(heap, e)), ap(Y, abstr(heap, h(heap, lhs), h(heap, rhs))));
    }
    return ap(abstrlist(heap, lhs, codegen(heap, e)), ap(Y, abstrlist(heap, lhs, rhs)));
}

/// Build the `show` function for a type at source location `here`.
pub fn makeshow(heap: *Heap, here: Word, type_node: Word) Word {
    cs().was_poly = 0;
    const f = mkshow(heap, 0, 0, type_node);
    if (here != 0 and cs().was_poly != 0) {
        _ = word.print("type error in definition of {s}\n", .{getId(heap, cs().current_id)});
        sayhere(heap, here, 0);
        _ = word.print(" use of \"show\" at polymorphic type ", .{});
        outType(heap, redtvars(heap, type_node));
        _ = word.putchar('\n');
        setIdType(heap, cs().current_id, wrong_t);
        setIdVal(heap, cs().current_id, UNDEF);
        cs().polyshowerror = 1;
        cs().ND = add1(heap, cs().current_id, cs().ND);
        cs().was_poly = 0;
    }
    return f;
}

/// Build a `show` application for type `t`.
pub fn mkshow(heap: *Heap, s: Word, p: Word, input_t: Word) Word {
    var args: Word = NIL;
    var type_node = input_t;
    while (getTag(heap, type_node) == .AP) {
        args = cons(t(heap, type_node), args);
        type_node = h(heap, type_node);
    }
    switch (type_node) {
        num_t => return if (p != 0) show_fns.show().shownum1 else SHOWNUM,
        bool_t => return show_fns.show().showbool,
        char_t => return show_fns.show().showchar,
        list_t => {
            if (h(heap, args) == char_t) {
                return show_fns.show().showstring;
            }
            return ap(show_fns.show().showlist, mkshow(heap, s, 0, h(heap, args)));
        },
        comma_t => return ap(show_fns.show().showparen, ap2(show_fns.show().showpair, mkshow(heap, s, 0, h(heap, args)), mkshowt(heap, s, h(heap, t(heap, args))))),
        void_t => return show_fns.show().showvoid,
        arrow_t => return show_fns.show().showfunction,
        else => {
            if (getTag(heap, type_node) == .ID) {
                var r = typeShowFn(heap, type_node);
                if (r == 0) {
                    return show_fns.show().showabstract;
                }
                if (r == show_fns.show().showwhat) {
                    return r;
                }
                while (args != NIL) {
                    r = ap(r, mkshow(heap, s, 1, h(heap, args)));
                    args = t(heap, args);
                }
                if (typeClass(heap, type_node) == 0) {
                    r = ap(r, p);
                }
                return r;
            }
            if (isTypeVariable(heap, type_node)) {
                if (s != 0) {
                    return type_node;
                }
                cs().was_poly = 1;
                return show_fns.show().showwhat;
            }
            if (getTag(heap, type_node) == .STRCONS) {
                _ = word.print("warning - mkshow applied to suppressed type\n", .{});
                return show_fns.show().showwhat;
            }
            _ = word.print("impossible event in mkshow (", .{});
            outType(heap, type_node);
            _ = word.print(")\n", .{});
            return show_fns.show().showwhat;
        },
    }
}

/// Build a `show` for a tuple type.
pub fn mkshowt(heap: *Heap, s: Word, type_tuple: Word) Word {
    if (t(heap, type_tuple) == void_t) {
        return mkshow(heap, s, 0, t(heap, h(heap, type_tuple)));
    }
    return ap2(show_fns.show().showpair, mkshow(heap, s, 0, t(heap, h(heap, type_tuple))), mkshowt(heap, s, t(heap, type_tuple)));
}

/// Name-clash check helper (returns a count).
fn nclchk(heap: *Heap, n: Word, p: Word, hr: Word) bool {
    if (h(heap, p) == CONST) {
        return false;
    }
    if (getTag(heap, p) == .ID) {
        if (n != p) {
            return false;
        }
        if (repl_session.session().echoing != 0) {
            _ = word.putchar('\n');
        }
        core_state.s().errs = hr;
        _ = word.print("syntax error: conflicting definitions of \"{s}\" in where clause\n", .{getId(heap, n)});
        acterror() catch {};
        return true;
    }
    if (getTag(heap, p) == .AP and h(heap, p) == PLUS) {
        return false;
    }
    if (nclchk(heap, n, h(heap, p), hr)) {
        return true;
    }
    return nclchk(heap, n, t(heap, p), hr);
}

/// Check definitions `dd` for name clashes with `n`.
pub fn nclashcheck(heap: *Heap, n: Word, input_dd: Word, hr: Word) void {
    var dd = input_dd;
    while (dd != NIL and !nclchk(heap, n, dlhs(heap, h(heap, dd)), hr)) {
        dd = t(heap, dd);
    }
}

/// Report a re-specification (duplicate `::`) error for `x`.
pub fn respecError(heap: *Heap, x: Word) void {
    if (repl_session.session().echoing != 0) {
        _ = word.putchar('\n');
    }
    const suffix: [*:0]const u8 = if (member(heap, rt.rs().primenv, x) != 0) " (in standard environment)" else "";
    _ = word.print("syntax error: type of \"{s}\" already declared{s}\n", .{ getId(heap, x), suffix });
    acterror() catch {};
}

/// Report a name clash for `x`.
pub fn nameclash(heap: *Heap, x: Word) void {
    if (repl_session.session().echoing != 0) {
        _ = word.putchar('\n');
    }
    const suffix: [*:0]const u8 = if (member(heap, rt.rs().primenv, x) != 0) " (in standard environment)" else "";
    _ = word.print("syntax error: nameclash, \"{s}\" already defined{s}\n", .{ getId(heap, x), suffix });
    acterror() catch {};
}

/// Declare data constructor `x` of type `constr_type`.
pub fn declconstr(heap: *Heap, x: Word, n: Word, constr_type: Word) void {
    setIdVal(heap, x, constructor(heap, n, x));
    if ((n >> 16) != 0) {
        syntax("algebraic type has too many constructors\n") catch {};
        return;
    }
    if (idType(heap, x) != undef_t) {
        core_state.s().errs = idWho(heap, x);
        respecError(heap, x);
        return;
    }
    addToEnv(heap, x);
    setIdType(heap, x, constr_type);
}

/// Attach type specification `spec_type` to `x` (a `::` declaration).
pub fn specify(heap: *Heap, input_x: Word, spec_type: Word, here: Word) void {
    var x = input_x;
    if (getTag(heap, x) != .ID and spec_type != type_t) {
        core_state.s().errs = here;
        syntax("incorrect use of ::\n") catch {};
        return;
    }
    if (spec_type == type_t) {
        var arity: Word = 0;
        while (getTag(heap, x) == .AP) {
            arity += 1;
            x = h(heap, x);
        }
        if (!(idVal(heap, x) == UNDEF and idType(heap, x) == undef_t)) {
            core_state.s().errs = here;
            nameclash(heap, x);
            return;
        }
        setIdType(heap, x, type_t);
        if (idWho(heap, x) == NIL) {
            setIdWho(heap, x, here);
        }
        setIdVal(heap, x, makeTyp(arity, show_fns.show().showwhat, placeholder_t, NIL));
        addToEnv(heap, x);
        cs().newtyps = add1(heap, x, cs().newtyps);
        return;
    }
    if (idType(heap, x) != undef_t) {
        core_state.s().errs = here;
        respecError(heap, x);
        return;
    }
    setIdType(heap, x, spec_type);
    if (idWho(heap, x) == NIL) {
        setIdWho(heap, x, here);
    } else {
        cs().speclocs = cons(cons(x, here), cs().speclocs);
    }
    if (idVal(heap, x) == UNDEF) {
        addToEnv(heap, x);
    }
}

/// Check that `type_name` is applied at its declared arity.
fn arityCheck(heap: *Heap, type_name: Word, arity: Word, here: Word) void {
    if (typeArity(heap, type_name) != arity) {
        const prefix: [*:0]const u8 = if (repl_session.session().echoing != 0) "\n" else "";
        _ = word.print("{s}syntax error: wrong number of parameters for typename \"{s}\" ({d} expected)\n", .{
            prefix,
            getId(heap, type_name),
            typeArity(heap, type_name),
        });
        core_state.s().errs = here;
        acterror() catch {};
    }
}

/// Declare a type (`tf`) with its class and info.
pub fn declType(heap: *Heap, input_tf: Word, type_class: Word, info: Word, here: Word) void {
    var tf = input_tf;
    var arity: Word = 0;
    while (getTag(heap, tf) == .AP) {
        arity += 1;
        tf = h(heap, tf);
    }
    if (type_class == synonym_t and idType(heap, tf) == type_t and typeClass(heap, tf) == abstract_t and typeInfo(heap, tf) == undef_t) {
        arityCheck(heap, tf, arity, here);
        setIdWho(heap, tf, here);
        setTypeInfo(heap, tf, info);
        return;
    }
    if (type_class == abstract_t and idType(heap, tf) == type_t and typeClass(heap, tf) == synonym_t) {
        arityCheck(heap, tf, arity, here);
        setTypeClass(heap, tf, abstract_t);
        return;
    }
    if (idVal(heap, tf) != UNDEF) {
        core_state.s().errs = here;
        nameclash(heap, tf);
        return;
    }
    if (type_class != synonym_t) {
        cs().newtyps = add1(heap, tf, cs().newtyps);
    }
    setIdVal(heap, tf, makeTyp(arity, if (type_class == algebraic_t) makePn(UNDEF) else 0, type_class, info));
    if (idType(heap, tf) != undef_t) {
        core_state.s().errs = here;
        respecError(heap, tf);
        return;
    }
    addToEnv(heap, tf);
    setIdWho(heap, tf, here);
    setIdType(heap, tf, type_t);
}

/// Declare a single binding `x` = `e` (the inner step).
fn decl1(heap: *Heap, x: Word, e: Word) void {
    if (idVal(heap, x) != UNDEF and script_store.store().lastname != x) {
        core_state.s().errs = h(heap, e);
        nameclash(heap, x);
        return;
    }
    if (idVal(heap, x) == UNDEF) {
        setIdVal(heap, x, tries(heap, x, cons(e, NIL)));
        if (idWho(heap, x) != NIL) {
            cs().speclocs = cons(cons(x, idWho(heap, x)), cs().speclocs);
        }
        setIdWho(heap, x, h(heap, e));
        if (idType(heap, x) == undef_t) {
            addToEnv(heap, x);
        }
    } else if (fallible(heap, h(heap, t(heap, idVal(heap, x)))) == 0) {
        const prefix: [*:0]const u8 = if (repl_session.session().echoing != 0) "\n" else "";
        core_state.s().errs = h(heap, e);
        _ = word.print("{s}syntax error: unreachable case in defn of \"{s}\"\n", .{ prefix, getId(heap, x) });
        acterror() catch {};
    } else {
        tp(heap, idVal(heap, x)).* = cons(e, t(heap, idVal(heap, x)));
    }
}

/// Declare definition `x` = `e` in the environment.
pub fn declare(heap: *Heap, x: Word, e: Word) void {
    if (getTag(heap, x) == .ID and !isConstructor(heap, x)) {
        decl1(heap, x, e);
        return;
    }
    var bindings = match.scanpattern(heap, x, x, share(heap, tries(heap, x, cons(e, NIL)), undef_t), ap(CONFERROR, cons(x, h(heap, e))));
    if (bindings == NIL) {
        core_state.s().errs = h(heap, e);
        syntax("illegal lhs for definition\n") catch {};
        return;
    }
    script_store.store().lastname = 0;
    while (bindings != NIL) {
        const binding = h(heap, bindings);
        const name = h(heap, binding);
        if (idVal(heap, name) != UNDEF) {
            core_state.s().errs = h(heap, e);
            nameclash(heap, name);
            return;
        }
        setIdVal(heap, name, t(heap, binding));
        if (idWho(heap, name) != NIL) {
            cs().speclocs = cons(cons(name, idWho(heap, name)), cs().speclocs);
        }
        setIdWho(heap, name, h(heap, e));
        if (idType(heap, name) == undef_t) {
            addToEnv(heap, name);
        }
        bindings = t(heap, bindings);
    }
}

/// Translate a block of definitions over expression `e`.
pub fn block(heap: *Heap, input_defs: Word, input_e: Word, keep: Word) Word {
    var defs = input_defs;
    var e = input_e;
    var ids: Word = NIL;
    var deftoids: Word = NIL;
    var g: Word = NIL;
    if (core_state.s().SYNERR != 0) {
        return NIL;
    }
    var d = defs;
    while (d != NIL) : (d = t(heap, d)) {
        const x = getIds(heap, dlhs(heap, h(heap, d)));
        ids = UNION(heap, ids, x);
        deftoids = cons(cons(h(heap, d), x), deftoids);
    }
    defs = sort(heap, defs);
    d = defs;
    while (d != NIL) : (d = t(heap, d)) {
        var x = intersection(heap, deps(heap, dval(heap, h(heap, d))), ids);
        var y: Word = NIL;
        while (x != NIL) : (x = t(heap, x)) {
            y = add1(heap, invgetrel(heap, deftoids, h(heap, x)), y);
        }
        g = cons(cons(h(heap, d), add1(heap, h(heap, d), y)), g);
    }
    g = reverse(g);
    g = tclos(heap, g);
    {
        var x = intersection(heap, deps(heap, e), ids);
        var y: Word = NIL;
        while (x != NIL) : (x = t(heap, x)) {
            d = invgetrel(heap, deftoids, h(heap, x));
            if (member(heap, y, d) == 0) {
                y = UNION(heap, y, getrel(heap, g, d));
            }
        }
        defs = setdiff(heap, defs, y);
        if (defs != NIL) {
            script_store.store().detrop = append1(script_store.store().detrop, defs);
        }
        if (keep != 0) {
            return letrec(heap, y, e);
        }
    }
    g = msc(heap, g);
    g = tsort(heap, g);
    g = reverse(g);
    while (g != NIL) : (g = t(heap, g)) {
        if (t(heap, h(heap, g)) == NIL and intersection(heap, getIds(heap, dlhs(heap, h(heap, h(heap, g)))), deps(heap, dval(heap, h(heap, h(heap, g))))) == NIL) {
            e = let(heap, h(heap, h(heap, g)), e);
        } else {
            e = letrec(heap, h(heap, g), e);
        }
    }
    return e;
}

/// Transitive closure of relation `r`.
pub fn tclos(heap: *Heap, r: Word) Word {
    var r1 = r;
    while (r1 != NIL) : (r1 = t(heap, r1)) {
        var x = less1(heap, t(heap, h(heap, r1)), h(heap, h(heap, r1)));
        while (x != NIL) {
            x = imageless(heap, r, x, t(heap, h(heap, r1)));
            tp(heap, h(heap, r1)).* = UNION(heap, t(heap, h(heap, r1)), x);
        }
    }
    return r;
}

/// The image (successors) of `x` under relation `r`.
pub fn getrel(heap: *Heap, input_r: Word, x: Word) Word {
    var r = input_r;
    while (r != NIL and h(heap, h(heap, r)) != x) r = t(heap, r);
    return if (r == NIL) NIL else t(heap, h(heap, r));
}

/// The inverse image (predecessors) of `x` under relation `r`.
pub fn invgetrel(heap: *Heap, input_r: Word, x: Word) Word {
    var r = input_r;
    while (r != NIL and member(heap, t(heap, h(heap, r)), x) == 0) r = t(heap, r);
    if (r == NIL) {
        std.debug.print("impossible event in invgetrel\n", .{});
        os.exit(1);
    }
    return h(heap, h(heap, r));
}

/// The image of `y` under `r`, excluding `z`.
pub fn imageless(heap: *Heap, input_r: Word, input_y: Word, z: Word) Word {
    var r = input_r;
    var y = input_y;
    var i: Word = NIL;
    while (r != NIL and y != NIL) {
        if (h(heap, h(heap, r)) == h(heap, y)) {
            i = UNION(heap, i, less(heap, t(heap, h(heap, r)), z));
            r = t(heap, r);
            y = t(heap, y);
        } else if (h(heap, h(heap, r)) < h(heap, y)) {
            r = t(heap, r);
        } else {
            y = t(heap, y);
        }
    }
    return i;
}

/// Whether `x` should sort before `y`.
pub fn less(heap: *Heap, input_x: Word, input_y: Word) Word {
    var x = input_x;
    var y = input_y;
    var r: Word = NIL;
    while (x != NIL and y != NIL) {
        if (h(heap, x) == h(heap, y)) {
            x = t(heap, x);
            y = t(heap, y);
        } else if (h(heap, x) < h(heap, y)) {
            r = cons(h(heap, x), r);
            x = t(heap, x);
        } else {
            y = t(heap, y);
        }
    }
    return shunt(r, x);
}

/// The elements of `x` that sort before `a`.
pub fn less1(heap: *Heap, input_x: Word, a: Word) Word {
    var x = input_x;
    var r: Word = NIL;
    while (x != NIL and h(heap, x) != a) {
        r = cons(h(heap, x), r);
        x = t(heap, x);
    }
    return shunt(r, if (x == NIL) NIL else t(heap, x));
}

/// Sort list `x`.
///
/// Tests: sort: orders a Word list ascending
pub fn sort(heap: *Heap, input_x: Word) Word {
    var x = input_x;
    var a: Word = NIL;
    var b: Word = NIL;
    if (x == NIL or t(heap, x) == NIL) return x;
    while (x != NIL) {
        const hold = a;
        a = cons(h(heap, x), b);
        b = hold;
        x = t(heap, x);
    }
    a = sort(heap, a);
    b = sort(heap, b);
    while (a != NIL and b != NIL) {
        if (h(heap, a) < h(heap, b)) {
            x = cons(h(heap, a), x);
            a = t(heap, a);
        } else {
            x = cons(h(heap, b), x);
            b = t(heap, b);
        }
    }
    if (a == NIL) a = b;
    while (a != NIL) {
        x = cons(h(heap, a), x);
        a = t(heap, a);
    }
    return reverse(x);
}

test "sort: orders a Word list ascending" {
    tu.freshInterp();
    try tu.expectWords(&[_]Word{ 1000, 2000, 3000 }, sort(heap_mod.heap(), tu.list(&[_]Word{ 3000, 1000, 2000 })));
    try tu.expectWords(&[_]Word{}, sort(heap_mod.heap(), NIL));
}

/// Topologically sort relation `x`.
pub fn sortrel(heap: *Heap, input_x: Word) Word {
    var x = input_x;
    var a: Word = NIL;
    var b: Word = NIL;
    if (x == NIL or t(heap, x) == NIL) return x;
    while (x != NIL) {
        const hold = a;
        a = cons(h(heap, x), b);
        b = hold;
        x = t(heap, x);
    }
    a = sortrel(heap, a);
    b = sortrel(heap, b);
    while (a != NIL and b != NIL) {
        if (h(heap, h(heap, a)) < h(heap, h(heap, b))) {
            x = cons(h(heap, a), x);
            a = t(heap, a);
        } else {
            x = cons(h(heap, b), x);
            b = t(heap, b);
        }
    }
    if (a == NIL) a = b;
    while (a != NIL) {
        x = cons(h(heap, a), x);
        a = t(heap, a);
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
const ispoly = unify_mod.ispoly;

/// Whether a type node is a tuple (comma) type.
/// Whether a type node is a type variable.
/// The `show` function of a type node.
fn tShowfn(heap: *Heap, x: Word) Word {
    return t(heap, h(heap, t(heap, x)));
}
/// The class of a type node.
fn tClass(heap: *Heap, x: Word) Word {
    return h(heap, t(heap, t(heap, x)));
}
/// The info field of a type node.
fn tInfo(heap: *Heap, x: Word) Word {
    return t(heap, t(heap, t(heap, x)));
}

/// Whether id `x` names a data constructor.
/// Whether id `x` names an ordinary variable.
/// The head of private-name node `x`.
/// The value (tail) of private-name node `x`.
/// Whether constructor `k` is the sole constructor of its type.
/// Compile expression `x` to its final combinator graph — the codegen entry point.
pub fn codegen(heap: *Heap, x: Word) Word {
    switch (getTag(heap, x)) {
        .AP => {
            // Walk the application spine (the deep recursion is codegen(heap, h(heap, x)))
            // iteratively so a long chain can't overflow the stack. Each node's
            // per-node logic mirrors the recursive form exactly; only the special
            // forms (the $±/stdin shares and the APPEND-NIL reversal) terminate
            // the spine and fall back to a single recursive codegen(heap, ) call — they
            // are never deep.
            var spine: std.ArrayList(Word) = .empty;
            defer spine.deinit(rt.allocator);
            var cur = x;
            var acc = while (true) {
                if (getTag(heap, cur) != .AP) break codegen(heap, cur);
                const shares = cur == ls().cook_stdin or cur == ls().common_stdin or cur == ls().common_stdinb;
                const cmd = core_state.s().commandmode != 0 and !shares;
                if (!cmd and getTag(heap, h(heap, cur)) == .AP and h(heap, h(heap, cur)) == APPEND and t(heap, h(heap, cur)) == NIL) {
                    break codegen(heap, t(heap, cur)); // post typecheck reversal of HR bug fix
                }
                spine.append(rt.allocator, cur) catch heap_mod.mallocPanic("codegen ap spine");
                cur = h(heap, cur);
            };
            var i = spine.items.len;
            while (i > 0) {
                i -= 1;
                const n = spine.items[i];
                const shares = n == ls().cook_stdin or n == ls().common_stdin or n == ls().common_stdinb;
                if (core_state.s().commandmode != 0 and !shares) { // beware of corrupting lastexp; share $+ $-
                    acc = make(heap, .AP, acc, codegen(heap, t(heap, n)));
                } else {
                    hp(heap, n).* = acc; // = codegen(heap, h(heap, n)), already computed down-spine
                    tp(heap, n).* = codegen(heap, t(heap, n));
                    acc = if (getTag(heap, h(heap, n)) == .AP and h(heap, h(heap, n)) == G_ALT) leftfactor(heap, n) else n;
                }
            }
            return acc;
        },
        .TCONS, .PAIR => {
            // Iterate the tuple spine (recursed via t(heap, x)) so a large tuple can't
            // overflow the stack; mirrors the cons-list fix.
            const result = make(heap, .CONS, codegen(heap, h(heap, x)), NIL);
            var dst = tp(heap, result);
            var cur = t(heap, x);
            while (getTag(heap, cur) == .TCONS or getTag(heap, cur) == .PAIR) {
                dst.* = make(heap, .CONS, codegen(heap, h(heap, cur)), NIL);
                dst = tp(heap, dst.*);
                cur = t(heap, cur);
            }
            dst.* = codegen(heap, cur); // final element
            return result;
        },
        .CONS => {
            // Walk the cons spine iteratively rather than recursing on the tail:
            // a long string/list literal (e.g. a 4096-char string) would otherwise
            // recurse once per element and overflow the stack (codegen's frame is
            // large). Recursion is kept only for each head and the final tail.
            if (core_state.s().commandmode != 0) {
                const result = make(heap, .CONS, codegen(heap, h(heap, x)), NIL);
                var dst = tp(heap, result);
                var cur = t(heap, x);
                while (getTag(heap, cur) == .CONS) {
                    dst.* = make(heap, .CONS, codegen(heap, h(heap, cur)), NIL);
                    dst = tp(heap, dst.*);
                    cur = t(heap, cur);
                }
                dst.* = codegen(heap, cur); // final non-cons tail (e.g. NIL)
                return result;
            }
            // otherwise do in situ (see declare)
            var cur = x;
            while (true) {
                hp(heap, cur).* = codegen(heap, h(heap, cur));
                const nxt = t(heap, cur);
                if (getTag(heap, nxt) == .CONS) {
                    cur = nxt; // tail is unchanged by in-situ codegen; keep walking
                } else {
                    tp(heap, cur).* = codegen(heap, nxt);
                    break;
                }
            }
            return x;
        },
        .LAMBDA => {
            return abstract(heap, h(heap, x), codegen(heap, t(heap, x)));
        },
        .LET => {
            return translet(heap, h(heap, x), t(heap, x));
        },
        .LETREC => {
            return transletrec(heap, h(heap, x), t(heap, x));
        },
        .TRIES => {
            return match.transtries(heap, h(heap, x), t(heap, x));
        },
        .LABEL => {
            return codegen(heap, t(heap, x));
        },
        .SHOW => {
            return makeshow(heap, h(heap, x), t(heap, x));
        },
        .LEXER => {
            var r: Word = NIL;
            var uses_state: Word = 0;
            var cur_x = x;
            while (cur_x != NIL) {
                var rule = abstr(heap, mklexvar(heap, 0), codegen(heap, t(heap, t(heap, h(heap, cur_x)))));
                rule = abstr(heap, mklexvar(heap, 1), rule);
                if (!(getTag(heap, rule) == .AP and h(heap, rule) == K)) {
                    uses_state = 1;
                }
                r = cons(cons(h(heap, h(heap, cur_x)), // start condition stuff
                    cons(ap(h(heap, t(heap, h(heap, cur_x))), NIL), // matcher []
                        rule)), r);
                cur_x = t(heap, cur_x);
            }
            if (uses_state == 0) { // strip off (K -) from each rule
                var cur_y = r;
                while (cur_y != NIL) {
                    tp(heap, t(heap, h(heap, cur_y))).* = t(heap, t(heap, t(heap, h(heap, cur_y))));
                    cur_y = t(heap, cur_y);
                }
                r = ap(LEX_RPT, ap(LEX_TRY, r));
            } else {
                r = ap(LEX_RPT1, ap(LEX_TRY1, r));
            }
            return ap(r, 0); // 0 startcond
        },
        .STARTREADVALS => {
            if (ispoly(heap, t(heap, x))) {
                const name_str: [*:0]const u8 = if (ls().cook_stdin != 0 and x == h(heap, ls().cook_stdin)) "$+" else "readvals or $+";
                _ = word.print("type error - {s} used at polymorphic type :: [", .{name_str});
                outType(heap, redtvars(heap, t(heap, x)));
                _ = word.print("]\n", .{});
                cs().polyshowerror = 1;
                if (cs().current_id != 0) {
                    cs().ND = add1(heap, cs().current_id, cs().ND);
                    setIdType(heap, cs().current_id, wrong_t);
                    setIdVal(heap, cs().current_id, UNDEF);
                }
                if (h(heap, x) != 0) {
                    sayhere(heap, h(heap, x), 1);
                }
            }
            if (core_state.s().commandmode != 0) {
                rt.rs().rv_expr = 1;
            } else {
                cs().rv_script = 1;
            }
            return x;
        },
        .SHARE => {
            if (t(heap, x) != -1) { // arbitrary flag for already visited
                hp(heap, x).* = codegen(heap, h(heap, x));
                tp(heap, x).* = -1;
            }
            return h(heap, x);
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
pub fn genshfns(heap: *Heap) void {
    var s = cs().newtyps;
    while (s != NIL) {
        if (tClass(heap, h(heap, s)) == algebraic_t) {
            var f: Word = 0;
            var r = tInfo(heap, h(heap, s)); // r is list of constructors
            const ush = if (t(heap, r) == NIL and member(heap, cs().SGC, h(heap, r)) != 0) Ush1 else Ush;
            while (r != NIL) {
                var type_var = idType(heap, h(heap, r));
                var k = idVal(heap, h(heap, r));
                while (getTag(heap, k) != .CONSTRUCTOR) {
                    k = t(heap, k); // lawful and !'d constructors
                }
                // k now holds constructor(i,main.hd(r))
                while (isArrowType(heap, type_var)) {
                    k = ap(k, mkshow(heap, 1, 1, t(heap, h(heap, type_var))));
                    type_var = t(heap, type_var);
                }
                k = ap(ush, k);
                while (isCompoundType(heap, type_var)) {
                    k = abstr(heap, t(heap, type_var), k);
                    type_var = h(heap, type_var);
                }
                // see kahrs.bug.m (this is the fix)
                if (f != 0) {
                    f = ap2(TRY, k, f);
                } else {
                    f = k;
                }
                r = t(heap, r);
            }
            // f ~= 0, placeholder types dealt with in specify(heap, )
            tp(heap, tShowfn(heap, h(heap, s))).* = f;
            cs().algshfns = cons(tShowfn(heap, h(heap, s)), cs().algshfns);
        } else if (tClass(heap, h(heap, s)) == abstract_t) {
            if (tShowfn(heap, h(heap, s)) != 0) {
                if (abshfnck(heap, h(heap, s), idType(heap, tShowfn(heap, h(heap, s)))) == 0) {
                    _ = word.print("warning - \"{s}\" has type inappropriate for a show-function\n", .{getId(heap, tShowfn(heap, h(heap, s)))});
                    tp(heap, tShowfn(heap, h(heap, s))).* = 0;
                }
            }
        }
        s = t(heap, s);
    }
}

/// Validate compiler state in Debug/Strict mode.
pub fn validate(heap: *Heap) void {
    const options = @import("version_options");
    if (@import("builtin").mode != .Debug and !options.is_strict) return;

    std.debug.assert(cs().TYPERRS >= 0);

    const top_limit = heap.TOP();

    inline for (.{ cs().ND, cs().NT, cs().ALIASES, cs().TSUPPRESSED, cs().TORPHANS, cs().DETROP, cs().MISSING }) |field| {
        if (field >= ATOMLIMIT) {
            if (field >= top_limit) {
                std.debug.panic("compiler.validate: compiler state field has out-of-bounds heap reference {d} (TOP is {d})", .{ field, top_limit });
            }
        }
    }
}
