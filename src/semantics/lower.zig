//! lower.zig (split from compiler/trans.zig, Phase 4 step 3,
//! docs/GoReady.md) — translation from parse trees to combinator
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

const Word = i64;
const Value = @import("../graph/value.zig").Value;
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

test "memb: membership in a list" {
    tu.freshInterp();
    const l = cons(heap_mod.heap(), word.True, cons(heap_mod.heap(), word.False, NIL));
    try std.testing.expectEqual(@as(Word, 1), memb(heap_mod.heap(), l, word.False));
    try std.testing.expectEqual(@as(Word, 0), memb(heap_mod.heap(), l, word.S));
}

test "same: structural equality of graphs" {
    tu.freshInterp();
    try std.testing.expectEqual(@as(Word, 1), same(heap_mod.heap(), word.True, word.True));
    const a = cons(heap_mod.heap(), word.True, NIL);
    const b = cons(heap_mod.heap(), word.True, NIL);
    try std.testing.expectEqual(@as(Word, 1), same(heap_mod.heap(), a, b)); // distinct cells, equal structure
    try std.testing.expectEqual(@as(Word, 0), same(heap_mod.heap(), a, cons(heap_mod.heap(), word.False, NIL)));
}

test "lastlink: the last cell of a list" {
    tu.freshInterp();
    const l = cons(heap_mod.heap(), word.True, cons(heap_mod.heap(), word.False, cons(heap_mod.heap(), word.S, NIL)));
    const last = lastlink(heap_mod.heap(), l);
    try std.testing.expectEqual(@as(Word, word.S), h(heap_mod.heap(), last));
    try std.testing.expectEqual(@as(Word, NIL), t(heap_mod.heap(), last));
}

/// Translate a `let` of definition `d` in body `e`.
const lower_prims = @import("lower_prims.zig");
pub const getTag = lower_prims.getTag;
pub const h = lower_prims.h;
pub const hp = lower_prims.hp;
pub const t = lower_prims.t;
pub const tp = lower_prims.tp;
pub const cons = lower_prims.cons;
pub const constructor = lower_prims.constructor;
pub const share = lower_prims.share;
pub const tries = lower_prims.tries;
pub const let = lower_prims.let;
pub const letrec = lower_prims.letrec;
pub const ap = lower_prims.ap;
pub const ap2 = lower_prims.ap2;
pub const getId = lower_prims.getId;
pub const idWho = lower_prims.idWho;
pub const setIdWho = lower_prims.setIdWho;
pub const idType = lower_prims.idType;
pub const idVal = lower_prims.idVal;
pub const setIdType = lower_prims.setIdType;
pub const setIdVal = lower_prims.setIdVal;
pub const makeTyp = lower_prims.makeTyp;
pub const addToEnv = lower_prims.addToEnv;
pub const isConstructor = lower_prims.isConstructor;
pub const isArrowType = lower_prims.isArrowType;
pub const isTypeVariable = lower_prims.isTypeVariable;
pub const isCompoundType = lower_prims.isCompoundType;
pub const typeArity = lower_prims.typeArity;
pub const typeShowFn = lower_prims.typeShowFn;
pub const typeClass = lower_prims.typeClass;
pub const setTypeClass = lower_prims.setTypeClass;
pub const typeInfo = lower_prims.typeInfo;
pub const setTypeInfo = lower_prims.setTypeInfo;
pub const mkindex = lower_prims.mkindex;
pub const dlhs = lower_prims.dlhs;
pub const dval = lower_prims.dval;
const lower_front = @import("lower_front.zig");
pub const primconstr = lower_front.primconstr;
pub const memb = lower_front.memb;
pub const same = lower_front.same;
pub const getIds = lower_front.getIds;
pub const mktuple = lower_front.mktuple;
pub const irrefutable = lower_front.irrefutable;
pub const fallible = lower_front.fallible;
pub const hereInfo = lower_front.hereInfo;
pub const lastlink = lower_front.lastlink;
pub const fixrepeats = lower_front.fixrepeats;
pub const abshfnck = lower_front.abshfnck;
pub const combine = lower_front.combine;
pub const liscomb = lower_front.liscomb;
pub const abstract = lower_front.abstract;
pub const abstr = lower_front.abstr;
pub const abstrlist = lower_front.abstrlist;
pub const mklazy = lower_front.mklazy;
pub const newMkLazy = lower_front.newMkLazy;
pub const compzf = lower_front.compzf;
pub const transzf = lower_front.transzf;
pub const getspecloc = lower_front.getspecloc;
pub const transtypeid = lower_front.transtypeid;
pub const leftfactor = lower_front.leftfactor;
const lower_sort = @import("lower_sort.zig");
pub const tclos = lower_sort.tclos;
pub const getrel = lower_sort.getrel;
pub const invgetrel = lower_sort.invgetrel;
pub const imageless = lower_sort.imageless;
pub const less = lower_sort.less;
pub const less1 = lower_sort.less1;
pub const sort = lower_sort.sort;
pub const sortrel = lower_sort.sortrel;

pub fn translet(heap: *Heap, d: Word, e: Word) Word {
    const x = mklazy(heap, d);
    return ap(heap, abstract(heap, dlhs(heap, x), codegen(heap, e)), codegen(heap, dval(heap, x)));
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
            lhs = cons(heap, dlhs(heap, x), lhs);
            rhs = cons(heap, codegen(heap, dval(heap, x)), rhs);
        } else {
            var i: Word = 0;
            const p = mkgvar(heap, pn);
            pn += 1;
            x = newMkLazy(heap, x);
            var ids = dlhs(heap, x);
            lhs = cons(heap, p, lhs);
            rhs = cons(heap, codegen(heap, dval(heap, x)), rhs);
            while (ids != NIL) {
                lhs = cons(heap, h(heap, ids), lhs);
                rhs = cons(heap, ap2(heap, SUBSCRIPT, mkindex(i), p), rhs);
                ids = t(heap, ids);
                i += 1;
            }
        }
    }
    if (t(heap, lhs) == NIL) {
        return ap(heap, abstr(heap, h(heap, lhs), codegen(heap, e)), ap(heap, Y, abstr(heap, h(heap, lhs), h(heap, rhs))));
    }
    return ap(heap, abstrlist(heap, lhs, codegen(heap, e)), ap(heap, Y, abstrlist(heap, lhs, rhs)));
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
        cs().ND = add1(heap, Value.fromRaw(cs().current_id), Value.fromRaw(cs().ND)).toRaw();
        cs().was_poly = 0;
    }
    return f;
}

/// Build a `show` application for type `t`.
pub fn mkshow(heap: *Heap, s: Word, p: Word, input_t: Word) Word {
    var args: Word = NIL;
    var type_node = input_t;
    while (getTag(heap, type_node) == .AP) {
        args = cons(heap, t(heap, type_node), args);
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
            return ap(heap, show_fns.show().showlist, mkshow(heap, s, 0, h(heap, args)));
        },
        comma_t => return ap(heap, show_fns.show().showparen, ap2(heap, show_fns.show().showpair, mkshow(heap, s, 0, h(heap, args)), mkshowt(heap, s, h(heap, t(heap, args))))),
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
                    r = ap(heap, r, mkshow(heap, s, 1, h(heap, args)));
                    args = t(heap, args);
                }
                if (typeClass(heap, type_node) == 0) {
                    r = ap(heap, r, p);
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
    return ap2(heap, show_fns.show().showpair, mkshow(heap, s, 0, t(heap, h(heap, type_tuple))), mkshowt(heap, s, t(heap, type_tuple)));
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
        acterror(heap) catch {};
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
    const suffix: [*:0]const u8 = if (member(heap, Value.fromRaw(rt.rs().primenv), Value.fromRaw(x)) != 0) " (in standard environment)" else "";
    _ = word.print("syntax error: type of \"{s}\" already declared{s}\n", .{ getId(heap, x), suffix });
    acterror(heap) catch {};
}

/// Report a name clash for `x`.
pub fn nameclash(heap: *Heap, x: Word) void {
    if (repl_session.session().echoing != 0) {
        _ = word.putchar('\n');
    }
    const suffix: [*:0]const u8 = if (member(heap, Value.fromRaw(rt.rs().primenv), Value.fromRaw(x)) != 0) " (in standard environment)" else "";
    _ = word.print("syntax error: nameclash, \"{s}\" already defined{s}\n", .{ getId(heap, x), suffix });
    acterror(heap) catch {};
}

/// Declare data constructor `x` of type `constr_type`.
pub fn declconstr(heap: *Heap, x: Word, n: Word, constr_type: Word) void {
    setIdVal(heap, x, constructor(heap, n, x));
    if ((n >> 16) != 0) {
        syntax(heap, "algebraic type has too many constructors\n") catch {};
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
        syntax(heap, "incorrect use of ::\n") catch {};
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
        setIdVal(heap, x, makeTyp(heap, arity, show_fns.show().showwhat, placeholder_t, NIL));
        addToEnv(heap, x);
        cs().newtyps = add1(heap, Value.fromRaw(x), Value.fromRaw(cs().newtyps)).toRaw();
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
        cs().speclocs = cons(heap, cons(heap, x, here), cs().speclocs);
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
        acterror(heap) catch {};
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
        cs().newtyps = add1(heap, Value.fromRaw(tf), Value.fromRaw(cs().newtyps)).toRaw();
    }
    setIdVal(heap, tf, makeTyp(heap, arity, if (type_class == algebraic_t) makePn(heap, UNDEF) else 0, type_class, info));
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
        setIdVal(heap, x, tries(heap, x, cons(heap, e, NIL)));
        if (idWho(heap, x) != NIL) {
            cs().speclocs = cons(heap, cons(heap, x, idWho(heap, x)), cs().speclocs);
        }
        setIdWho(heap, x, h(heap, e));
        if (idType(heap, x) == undef_t) {
            addToEnv(heap, x);
        }
    } else if (fallible(heap, h(heap, t(heap, idVal(heap, x)))) == 0) {
        const prefix: [*:0]const u8 = if (repl_session.session().echoing != 0) "\n" else "";
        core_state.s().errs = h(heap, e);
        _ = word.print("{s}syntax error: unreachable case in defn of \"{s}\"\n", .{ prefix, getId(heap, x) });
        acterror(heap) catch {};
    } else {
        tp(heap, idVal(heap, x)).* = cons(heap, e, t(heap, idVal(heap, x)));
    }
}

/// Declare definition `x` = `e` in the environment.
pub fn declare(heap: *Heap, x: Word, e: Word) void {
    if (getTag(heap, x) == .ID and !isConstructor(heap, x)) {
        decl1(heap, x, e);
        return;
    }
    var bindings = match.scanpattern(heap, Value.fromRaw(x), Value.fromRaw(x), Value.fromRaw(share(heap, tries(heap, x, cons(heap, e, NIL)), undef_t)), Value.fromRaw(ap(heap, CONFERROR, cons(heap, x, h(heap, e))))).toRaw();
    if (bindings == NIL) {
        core_state.s().errs = h(heap, e);
        syntax(heap, "illegal lhs for definition\n") catch {};
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
            cs().speclocs = cons(heap, cons(heap, name, idWho(heap, name)), cs().speclocs);
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
        ids = UNION(heap, Value.fromRaw(ids), Value.fromRaw(x)).toRaw();
        deftoids = cons(heap, cons(heap, h(heap, d), x), deftoids);
    }
    defs = sort(heap, defs);
    d = defs;
    while (d != NIL) : (d = t(heap, d)) {
        var x = intersection(heap, deps(heap, Value.fromRaw(dval(heap, h(heap, d)))), Value.fromRaw(ids)).toRaw();
        var y: Word = NIL;
        while (x != NIL) : (x = t(heap, x)) {
            y = add1(heap, Value.fromRaw(invgetrel(heap, deftoids, h(heap, x))), Value.fromRaw(y)).toRaw();
        }
        g = cons(heap, cons(heap, h(heap, d), add1(heap, Value.fromRaw(h(heap, d)), Value.fromRaw(y)).toRaw()), g);
    }
    g = reverse(g);
    g = tclos(heap, g);
    {
        var x = intersection(heap, deps(heap, Value.fromRaw(e)), Value.fromRaw(ids)).toRaw();
        var y: Word = NIL;
        while (x != NIL) : (x = t(heap, x)) {
            d = invgetrel(heap, deftoids, h(heap, x));
            if (member(heap, Value.fromRaw(y), Value.fromRaw(d)) == 0) {
                y = UNION(heap, Value.fromRaw(y), Value.fromRaw(getrel(heap, g, d))).toRaw();
            }
        }
        defs = setdiff(heap, Value.fromRaw(defs), Value.fromRaw(y)).toRaw();
        if (defs != NIL) {
            script_store.store().detrop = append1(script_store.store().detrop, defs);
        }
        if (keep != 0) {
            return letrec(heap, y, e);
        }
    }
    g = msc(heap, Value.fromRaw(g)).toRaw();
    g = tsort(heap, Value.fromRaw(g)).toRaw();
    g = reverse(g);
    while (g != NIL) : (g = t(heap, g)) {
        if (t(heap, h(heap, g)) == NIL and intersection(heap, Value.fromRaw(getIds(heap, dlhs(heap, h(heap, h(heap, g))))), deps(heap, Value.fromRaw(dval(heap, h(heap, h(heap, g)))))).toRaw() == NIL) {
            e = let(heap, h(heap, h(heap, g)), e);
        } else {
            e = letrec(heap, h(heap, g), e);
        }
    }
    return e;
}

test "sort: orders a Word list ascending" {
    tu.freshInterp();
    try tu.expectWords(&[_]Word{ 1000, 2000, 3000 }, sort(heap_mod.heap(), tu.list(&[_]Word{ 3000, 1000, 2000 })));
    try tu.expectWords(&[_]Word{}, sort(heap_mod.heap(), NIL));
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
    var x_root = heap.roots.root(rt.allocator, &x);
    defer x_root.deinit();
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
            return match.transtries(heap, Value.fromRaw(h(heap, x)), Value.fromRaw(t(heap, x))).toRaw();
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
                r = cons(heap, cons(heap, h(heap, h(heap, cur_x)), // start condition stuff
                    cons(heap, ap(heap, h(heap, t(heap, h(heap, cur_x))), NIL), // matcher []
                        rule)), r);
                cur_x = t(heap, cur_x);
            }
            if (uses_state == 0) { // strip off (K -) from each rule
                var cur_y = r;
                while (cur_y != NIL) {
                    tp(heap, t(heap, h(heap, cur_y))).* = t(heap, t(heap, t(heap, h(heap, cur_y))));
                    cur_y = t(heap, cur_y);
                }
                r = ap(heap, LEX_RPT, ap(heap, LEX_TRY, r));
            } else {
                r = ap(heap, LEX_RPT1, ap(heap, LEX_TRY1, r));
            }
            return ap(heap, r, 0); // 0 startcond
        },
        .STARTREADVALS => {
            if (ispoly(heap, t(heap, x))) {
                const name_str: [*:0]const u8 = if (ls().cook_stdin != 0 and x == h(heap, ls().cook_stdin)) "$+" else "readvals or $+";
                _ = word.print("type error - {s} used at polymorphic type :: [", .{name_str});
                outType(heap, redtvars(heap, t(heap, x)));
                _ = word.print("]\n", .{});
                cs().polyshowerror = 1;
                if (cs().current_id != 0) {
                    cs().ND = add1(heap, Value.fromRaw(cs().current_id), Value.fromRaw(cs().ND)).toRaw();
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
            const ush = if (t(heap, r) == NIL and member(heap, Value.fromRaw(cs().SGC), Value.fromRaw(h(heap, r))) != 0) Ush1 else Ush;
            while (r != NIL) {
                var type_var = idType(heap, h(heap, r));
                var k = idVal(heap, h(heap, r));
                while (getTag(heap, k) != .CONSTRUCTOR) {
                    k = t(heap, k); // lawful and !'d constructors
                }
                // k now holds constructor(i,main.hd(r))
                while (isArrowType(heap, type_var)) {
                    k = ap(heap, k, mkshow(heap, 1, 1, t(heap, h(heap, type_var))));
                    type_var = t(heap, type_var);
                }
                k = ap(heap, ush, k);
                while (isCompoundType(heap, type_var)) {
                    k = abstr(heap, t(heap, type_var), k);
                    type_var = h(heap, type_var);
                }
                // see kahrs.bug.m (this is the fix)
                if (f != 0) {
                    f = ap2(heap, TRY, k, f);
                } else {
                    f = k;
                }
                r = t(heap, r);
            }
            // f ~= 0, placeholder types dealt with in specify(heap, )
            tp(heap, tShowfn(heap, h(heap, s))).* = f;
            cs().algshfns = cons(heap, tShowfn(heap, h(heap, s)), cs().algshfns);
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
