//! types.zig — the Hindley-Milner type inference engine.
//!
//! Infers and checks the type of every definition: `etype` walks expressions,
//! `unify` solves type equations over a mutable substitution (`lookup`/`addsubst`/
//! `subst`, with the `occurs` check), and `instantiate`/`linst`/`redtvars` handle
//! generalisation and the freshening of polymorphic variables. Also drives
//! dependency ordering (`tsort`/`deps`), abstract-type/synonym checking, and all
//! the type/pattern pretty-printing and `type_error*` reporting.

const std = @import("std");
const options = @import("version_options");
const word = @import("../graph/word.zig");
const errors = @import("../runtime/errors.zig");
const dump = @import("../compiler/dump.zig");
const strtab = @import("../graph/strtab.zig");
const os = @import("../os.zig");
const rt = @import("../runtime/runtime_state.zig");
const script_store = @import("../session/script_store.zig");

const compiler_state = @import("../compiler/compiler_state.zig");
const core_state = @import("../runtime/core_state.zig");
const heap_mod = @import("../graph/heap.zig");
const Heap = heap_mod.Heap;
const print_mod = @import("../graph/print.zig");
const tu = @import("../testutil.zig"); // unit-test harness (test builds only)
const cs = compiler_state.cs;
// `abi` — a private namespace of libc / `word`-combinator re-export aliases so
// this file can write `os.printf(...)`, `word.PLUS`, etc. Internal only (the
// container is not `pub`, so these never appear in autodoc); each member just
// re-exports an already-documented symbol from `os`/`word`.

const Word = word.Word;
const Value = @import("../graph/value.zig").Value;
const CMBASE = word.CMBASE;
const NIL = word.NIL;
const ATOMLIMIT = word.ATOMLIMIT;

// CMBASE + 138 is NIL
// CMBASE + 138 is NIL

// CMBASE + 138 is NIL
// CMBASE + 138 is NIL
// CMBASE + 138 is NIL

// CMBASE + 138 is NIL

const make = heap_mod.make;
const reverse = heap_mod.reverse;
const getspecloc = trans_mod.getspecloc;
const codegen = trans_mod.codegen;
const findid = lex_mod.findid;
const mktuple = trans_mod.mktuple;
const tclos = trans_mod.tclos;
const sortrel = trans_mod.sortrel;
const genshfns = trans_mod.genshfns;
const alfasort = depend.alfasort;
const readoption = dump.readoption;
const out = print_mod.outTerm;
const isChar = heap_mod.isChar;
const charname = print_mod.charname;
const size = heap_mod.size;
const same = trans_mod.same;
const getDbl = heap_mod.getDbl;
const lastlink = trans_mod.lastlink;
const trans_mod = @import("../semantics/lower.zig");
const lex_mod = @import("../parser/lex.zig");
const isconstrname = lex_mod.isconstrname;

const depend = @import("depend.zig");
const remove1 = depend.remove1;
const setdiff = depend.setdiff;
const add1 = depend.add1;
const UNION = depend.UNION;
const member = depend.member;
const tsort = depend.tsort;
const msc = depend.msc;
const rembvars = depend.rembvars;
const deps = depend.deps;
const redtfr = depend.redtfr;

pub const type_t: Word = 10;

const undef_t: Word = 0;
const bool_t: Word = 1;
const num_t: Word = 2;
const char_t: Word = 3;
const list_t: Word = 4;
const synonym_t = word.synonym_t;
const abstract_t = word.abstract_t;
const UNDEF: Word = CMBASE + 140;

test "sterilise: rewrites an AP-tagged type's hd/tl to (list_t . num_t)" {
    tu.freshInterp();
    const t_val = Value.fromRaw(tu.ap(tu.int(1), tu.int(2)));
    try std.testing.expectEqual(word.NodeTag.AP, getTag(heap_mod.heap(), t_val.toRaw()));
    sterilise(heap_mod.heap(), t_val);
    try std.testing.expectEqual(list_t, h(heap_mod.heap(), t_val.toRaw()));
    try std.testing.expectEqual(num_t, t(heap_mod.heap(), t_val.toRaw()));
}

const unify_mod = @import("unify.zig");
const fixshows = unify_mod.fixshows;
const subst = unify_mod.subst;
const linst = unify_mod.linst;
const nonGeneric = unify_mod.nonGeneric;
const instantiate = unify_mod.instantiate;
const apSubst = unify_mod.apSubst;
const redtvars = unify_mod.redtvars;
const occurs = unify_mod.occurs;
const ispoly = unify_mod.ispoly;
const unify1 = unify_mod.unify1;
const NTV = unify_mod.NTV;
const ult = unify_mod.ult;
const clearSubst = unify_mod.clearSubst;
const hashsize: usize = 512;

const comma_t: Word = 5;
const arrow_t: Word = 6;
const void_t: Word = 7;
const wrong_t: Word = 8;

const type_errors = @import("type_errors.zig");
const locate = type_errors.locate;
const sayhere = type_errors.sayhere;
const outType = type_errors.outType;
const outPattern = type_errors.outPattern;
const outFormal1 = type_errors.outFormal1;
const typeError = type_errors.typeError;
const typeError1 = type_errors.typeError1;
const typeError2 = type_errors.typeError2;
const typeError3 = type_errors.typeError3;
const typeError4 = type_errors.typeError4;
const typeError5 = type_errors.typeError5;
const typeError6 = type_errors.typeError6;
const typeError7 = type_errors.typeError7;
const typeError8 = type_errors.typeError8;
const isArrowType = type_errors.isArrowType;

const CONST = word.CONST;

const algebraic_t = word.algebraic_t;
const FREE = word.FREE;

test "printelement: prints a non-cons value bare, a cons-list parenthesised" {
    tu.freshInterp();
    // No stdout-capture harness exists in this codebase for `word.print`
    // (it writes straight to the real fd) -- this smoke-tests both branches
    // (bare value, cons-list) rather than asserting captured text.
    printelement(heap_mod.heap(), Value.fromRaw(tu.int(5)));
    printelement(heap_mod.heap(), Value.fromRaw(tu.list(&[_]Word{ tu.int(1), tu.int(2) })));
}

test "cyclicAbstr: an empty atnames list reports no cycle" {
    tu.freshInterp();
    try std.testing.expectEqual(@as(Word, 0), cyclicAbstr(heap_mod.heap(), Value.fromRaw(word.NIL)));
}

test "txchange: installs a representation type in place of a synonym id's own type" {
    tu.freshInterp();
    const id1 = heap_mod.stoId("zzinfer_txchange_id");
    const orig_head = tu.int(111);
    const x = tu.cons(orig_head, tu.int(222));
    const ids = tu.list(&[_]Word{id1});
    txchange(heap_mod.heap(), Value.fromRaw(ids), Value.fromRaw(x));
    // id1's type field (was undef_t) now holds x's original head.
    try std.testing.expectEqual(orig_head, idType(heap_mod.heap(), id1));
    // x's head field now holds id1's original (undef_t) type.
    try std.testing.expectEqual(undef_t, h(heap_mod.heap(), x));
}

test "repT1: returns T unchanged when it has no formals to substitute" {
    tu.freshInterp();
    // num_t isn't AP-tagged (isCompoundType false) and isn't a member of an
    // empty L, so the loop never runs and `!changed` returns T verbatim.
    const T = Value.fromRaw(num_t);
    try std.testing.expectEqual(T, repT1(heap_mod.heap(), T, Value.fromRaw(word.NIL)));
}

test "repT: returns T unchanged when repT1 makes no substitution" {
    tu.freshInterp();
    const T = Value.fromRaw(num_t);
    try std.testing.expectEqual(T, repT(heap_mod.heap(), T, Value.fromRaw(word.NIL)));
}

test "fixType: passes atoms through unchanged, recurses through an AP node's fields" {
    tu.freshInterp();
    // Atom (not AP/CONS/STRCONS): passed through unchanged (the `else` branch).
    try std.testing.expectEqual(Value.fromRaw(num_t), fixType(heap_mod.heap(), Value.fromRaw(num_t)));

    // AP-tagged: recurses into both fields. INT-tagged leaves hit the same
    // `else` branch, so the node's own hd/tl end up unchanged in value, but
    // the recursive fixTypeRaw(fixTypeRaw(...)) chain is genuinely exercised.
    const node = Value.fromRaw(tu.ap(tu.int(1), tu.int(2)));
    const before_h = h(heap_mod.heap(), node.toRaw());
    const before_t = t(heap_mod.heap(), node.toRaw());
    const result = fixType(heap_mod.heap(), node);
    try std.testing.expectEqual(node, result);
    try std.testing.expectEqual(before_h, h(heap_mod.heap(), node.toRaw()));
    try std.testing.expectEqual(before_t, t(heap_mod.heap(), node.toRaw()));
}

/// Check an abstract-type declaration `x`.
const infer_prims = @import("infer_prims.zig");
pub const getTag = infer_prims.getTag;
pub const h = infer_prims.h;
pub const hp = infer_prims.hp;
pub const t = infer_prims.t;
pub const tp = infer_prims.tp;
pub const cons = infer_prims.cons;
pub const idType = infer_prims.idType;
pub const isCompoundType = infer_prims.isCompoundType;
pub const isVarType = infer_prims.isVarType;
pub const tArity = infer_prims.tArity;
pub const tClass = infer_prims.tClass;
pub const tInfo = infer_prims.tInfo;
pub const idVal = infer_prims.idVal;
pub const idWho = infer_prims.idWho;
pub const getId = infer_prims.getId;
pub const ap = infer_prims.ap;
pub const pnVal = infer_prims.pnVal;
pub const isConstructor = infer_prims.isConstructor;
pub const theVal = infer_prims.theVal;
pub const ap2 = infer_prims.ap2;
pub const tf = infer_prims.tf;
pub const tf2 = infer_prims.tf2;
pub const tf3 = infer_prims.tf3;
pub const tf4 = infer_prims.tf4;
pub const lt = infer_prims.lt;
pub const pairType = infer_prims.pairType;
pub const dlhs = infer_prims.dlhs;
pub const dtyp = infer_prims.dtyp;
pub const dval = infer_prims.dval;
pub const getStdout = infer_prims.getStdout;
const infer_subst = @import("infer_subst.zig");
pub const sterilisRaw = infer_subst.sterilisRaw;
pub const sterilise = infer_subst.sterilise;
pub const metaTcheck = infer_subst.metaTcheck;
pub const printelementRaw = infer_subst.printelementRaw;
pub const printelement = infer_subst.printelement;
pub const printlist = infer_subst.printlist;
pub const resetSubst = infer_subst.resetSubst;
pub const locateInc = infer_subst.locateInc;
pub const cyclicAbstrRaw = infer_subst.cyclicAbstrRaw;
pub const cyclicAbstr = infer_subst.cyclicAbstr;
pub const txchangeRaw = infer_subst.txchangeRaw;
pub const txchange = infer_subst.txchange;
pub const repT1Raw = infer_subst.repT1Raw;
pub const repT1 = infer_subst.repT1;
pub const repTRaw = infer_subst.repTRaw;
pub const repT = infer_subst.repT;
pub const fixTypeRaw = infer_subst.fixTypeRaw;
pub const fixType = infer_subst.fixType;
pub const compDeps = infer_subst.compDeps;
pub const genlstatType = infer_subst.genlstatType;
pub const isBoundType = infer_subst.isBoundType;
const infer_etype = @import("infer_etype.zig");
pub const conforms = infer_etype.conforms;
pub const etype = infer_etype.etype;
pub const etypeAp = infer_etype.etypeAp;
pub const etypeCons = infer_etype.etypeCons;
pub const etypeLexer = infer_etype.etypeLexer;
pub const etypeId = infer_etype.etypeId;
pub const etypeLet = infer_etype.etypeLet;
pub const etypeLetrec = infer_etype.etypeLetrec;
pub const etypeTries = infer_etype.etypeTries;
pub const etypeAtom = infer_etype.etypeAtom;
pub const checkcolfn = infer_etype.checkcolfn;
pub const genbnft = infer_etype.genbnft;

fn abstrCheck(heap: *Heap, x_in: Word) errors.MiraError!void {
    var x = x_in;
    var x_root = heap.roots.root(rt.allocator, &x);
    defer x_root.deinit();
    var rtypes = t(heap, h(heap, x));
    var sigids = t(heap, x);
    var rtypes_root = heap.roots.root(rt.allocator, &rtypes);
    defer rtypes_root.deinit();
    var sigids_root = heap.roots.root(rt.allocator, &sigids);
    defer sigids_root.deinit();
    cs().ATNAMES = h(heap, h(heap, x));
    txchangeRaw(heap, sigids, rtypes); // install representation types
    x = sigids;
    while (x != NIL) {
        const oldte = cs().TYPERRS;
        cs().current_id = h(heap, x);
        var t_val = subst(heap, try etype(heap, idVal(heap, h(heap, x)), NIL, NIL));
        var t_val_root = heap.roots.root(rt.allocator, &t_val);
        defer t_val_root.deinit();
        if (subsumes(heap, t_val, instantiate(heap, idType(heap, h(heap, x)))) == 0) {
            cs().TYPERRS += 1;
            _ = word.print("abstype implementation error\n", .{});
            _ = word.print("\"{s}\" is bound to value of type: ", .{getId(heap, h(heap, x))});
            outType(heap, redtvars(heap, t_val));
            _ = word.print("\ntype expected: ", .{});
            outType(heap, idType(heap, h(heap, x)));
            _ = word.putchar('\n');
            sayhere(heap, idWho(heap, h(heap, x)), 1);
        }
        if (cs().TYPERRS > oldte) {
            tp(heap, h(heap, h(heap, x))).* = wrong_t;
            tp(heap, h(heap, x)).* = UNDEF;
            cs().ND = add1(heap, Value.fromRaw(h(heap, x)), Value.fromRaw(cs().ND)).toRaw();
        }
        resetSubst(heap);
        x = t(heap, x);
    }
    // restore the abstract types - for "finger"
    x = sigids;
    var rty = rtypes;
    while (x != NIL) {
        if (idType(heap, h(heap, x)) != wrong_t) {
            tp(heap, h(heap, h(heap, x))).* = h(heap, rty);
        }
        x = t(heap, x);
        rty = t(heap, rty);
    }
    cs().ATNAMES = 0;
}

/// Check a group of mutually-recursive abstract types.
fn abstrMcheck(heap: *Heap, tabstrs_in: Word) errors.MiraError!void {
    var tabstrs = tabstrs_in;
    while (tabstrs != NIL) {
        const atnames = h(heap, h(heap, tabstrs));
        var sigids = t(heap, h(heap, tabstrs));
        var rtypes = NIL;
        if (cyclicAbstrRaw(heap, atnames) != 0) {
            return;
        }
        while (sigids != NIL) {
            const t_val = idType(heap, h(heap, sigids));
            if (t_val == undef_t) {
                rtypes = cons(heap, undef_t, rtypes);
            } else {
                rtypes = cons(heap, try metaTcheck(heap, t_val), rtypes);
            }
            sigids = t(heap, sigids);
        }
        rtypes = reverse(rtypes);
        hp(heap, h(heap, tabstrs)).* = cons(heap, h(heap, h(heap, tabstrs)), rtypes);
        tabstrs = t(heap, tabstrs);
    }
}

/// Check the grammar's free/bound symbols (error-returning form).
fn mcheckfbs(heap: *Heap) errors.MiraError!void {
    var ff: Word = undefined;
    var formals: Word = undefined;
    var n: Word = undefined;
    cs().lasthereinc = 0;
    ff = cs().FBS;
    while (ff != NIL) {
        cs().hereinc = h(heap, h(heap, cs().FBS));
        formals = t(heap, h(heap, ff));
        while (formals != NIL) {
            const t_val = t(heap, t(heap, h(heap, formals)));
            if (t_val != type_t) {
                formals = t(heap, formals);
                continue;
            }
            cs().current_id = h(heap, t(heap, h(heap, formals))); // nb datapair(orig,0) not id
            tp(heap, t(heap, t(heap, h(heap, h(heap, formals))))).* = try metaTcheck(heap, tInfo(heap, h(heap, h(heap, formals))));
            cs().current_id = 0;
            formals = t(heap, formals);
        }
        if (cs().TYPERRS != 0) {
            return; // to avoid misleading error messages
        }
        formals = t(heap, h(heap, ff));
        while (formals != NIL) {
            const t_val = t(heap, t(heap, h(heap, formals)));
            if (t_val == type_t) {
                formals = t(heap, formals);
                continue;
            }
            cs().current_id = h(heap, t(heap, h(heap, formals))); // nb datapair(orig,0) not id
            tp(heap, t(heap, h(heap, formals))).* = redtvars(heap, try metaTcheck(heap, t_val));
            cs().current_id = 0;
            formals = t(heap, formals);
        }
        ff = t(heap, ff);
    }
    if (cs().TYPERRS != 0) {
        return;
    }
    ff = t(heap, heap.files);
    while (ff != NIL) {
        formals = t(heap, h(heap, ff));
        while (formals != NIL) {
            n = h(heap, formals);
            if (getTag(heap, n) == .ID) {
                if (idType(heap, n) == type_t) {
                    if (tClass(heap, n) == synonym_t) {
                        tp(heap, t(heap, t(heap, n))).* = try metaTcheck(heap, tInfo(heap, n));
                    }
                } else {
                    tp(heap, h(heap, n)).* = redtvars(heap, try metaTcheck(heap, idType(heap, n)));
                }
            }
            formals = t(heap, formals);
        }
        ff = t(heap, ff);
    }
}

/// Type-check the grammar's free/bound symbols.
pub fn checkfbs(heap: *Heap, core: *core_state.CoreState, comp: *compiler_state.CompilerState) void {
    const oldte = comp.TYPERRS;
    var formals: Word = undefined;
    comp.lasthereinc = 0;
    while (comp.FBS != NIL) {
        comp.hereinc = h(heap, h(heap, comp.FBS));
        formals = t(heap, h(heap, comp.FBS));
        while (formals != NIL) {
            var t_val: Word = undefined;
            const t1 = fixTypeRaw(heap, t(heap, t(heap, h(heap, formals))));
            if (t1 == type_t) {
                formals = t(heap, formals);
                continue;
            }
            comp.current_id = h(heap, t(heap, h(heap, formals))); // nb datapair(orig,0) not id
            t_val = subst(heap, etype(heap, theVal(heap, h(heap, h(heap, formals))), NIL, NIL) catch return);
            if (subsumes(heap, t_val, instantiate(heap, t1)) == 0) {
                comp.TYPERRS += 1;
                locateInc(heap);
                _ = word.print("binding for parameter `{s}' has wrong type\n", .{strtab.strOf(strtab.table(), h(heap, comp.current_id))});
                _ = word.print("required :: ", .{});
                outType(heap, t(heap, t(heap, h(heap, formals))));
                _ = word.print("\n  actual :: ", .{});
                outType(heap, redtvars(heap, t_val));
                _ = word.putchar('\n');
            }
            tp(heap, t(heap, h(heap, h(heap, formals)))).* = codegen(heap, theVal(heap, h(heap, h(heap, formals))));
            formals = t(heap, formals);
        }
        comp.FBS = t(heap, comp.FBS);
    }
    if (comp.TYPERRS > oldte) { // badly typed parameter bindings, so give up
        comp.TABSTRS = NIL;
        comp.NT = NIL;
        comp.R = NIL;
        _ = word.printErr("compilation abandoned\n", .{});
        core.SYNERR = 1;
    }
    resetSubst(heap);
}

const bind_t: Word = 9;

const subsu1 = unify_mod.subsu1;
const subsumes = unify_mod.subsumes;
const unify = unify_mod.unify;

/// Type-check `x`, returning 1 if it typechecks cleanly, 0 otherwise (a flag,
/// not a graph value — matches `cyclicAbstr`'s precedent above).
///
/// Bug fixed in the same edit that gave this function its first caller (a unit
/// test — it had none before, Zig's lazy analysis never compiled this body):
/// `cs.TYPERRS` (missing the call parens on the `cs()` singleton accessor) does
/// not compile — `cs` is a function value, not a struct, so it has no
/// `.TYPERRS` field. Every other reference in this file correctly calls `cs()`.
fn checktypeRaw(heap: *Heap, x: Word) Word {
    cs().TYPERRS = 0;
    _ = etype(heap, x, NIL, NIL) catch return 0;
    resetSubst(heap);
    return if (cs().TYPERRS == 0) 1 else 0;
}

/// `Value`-typed wrapper for `checktypeRaw` (§ GoReady Phase 5 step 4g).
///
/// Tests: checktype: a boxed int typechecks cleanly, returning 1
pub fn checktype(heap: *Heap, x: Value) Word {
    return checktypeRaw(heap, x.toRaw());
}

test "checktype: a boxed int typechecks cleanly, returning 1" {
    tu.freshInterp();
    // etype's `.INT` branch returns num_t unconditionally -- no unify/TYPERRS
    // involvement, so this is a safe, minimal well-typed expression.
    try std.testing.expectEqual(@as(Word, 1), checktype(heap_mod.heap(), Value.fromRaw(tu.int(42))));
    try std.testing.expectEqual(@as(Word, 0), cs().TYPERRS);
}

/// The inferred type of expression `x`.
pub fn typeOf(heap: *Heap, x: Value) Value {
    cs().TYPERRS = 0;
    var t_val = redtvars(heap, subst(heap, etype(heap, x.toRaw(), NIL, NIL) catch return Value.fromRaw(wrong_t)));
    fixshows(heap);
    if (cs().TYPERRS > 0) {
        t_val = wrong_t;
    }
    return Value.fromRaw(t_val);
}

/// Run type inference over definition `x`.
fn inferType(heap: *Heap, x: Word) void {
    var x_root = heap.roots.root(rt.allocator, &x);
    defer x_root.deinit();
    if (getTag(heap, x) == .ID) {
        var t_val: Word = NIL;
        var t_val_root = heap.roots.root(rt.allocator, &t_val);
        defer t_val_root.deinit();
        const oldte = cs().TYPERRS;
        cs().current_id = x;
        if (idType(heap, x) != undef_t) {
            t_val = subst(heap, etype(heap, idVal(heap, x), NIL, NIL) catch return);
            if (subsumes(heap, t_val, instantiate(heap, idType(heap, x))) == 0) {
                typeError8(heap, idType(heap, x), t_val);
            }
        } else {
            t_val = subst(heap, etype(heap, idVal(heap, x), NIL, NIL) catch return);
        }
        if (cs().TYPERRS > oldte) {
            tp(heap, h(heap, x)).* = wrong_t;
            tp(heap, x).* = UNDEF;
            cs().ND = add1(heap, Value.fromRaw(x), Value.fromRaw(cs().ND)).toRaw();
        } else if (idType(heap, x) == undef_t) {
            tp(heap, h(heap, x)).* = redtvars(heap, t_val);
        }
        resetSubst(heap);
    } else {
        var x1 = x;
        var oldte: Word = undefined;
        var ngt = NIL;
        var x1_root = heap.roots.root(rt.allocator, &x1);
        defer x1_root.deinit();
        var ngt_root = heap.roots.root(rt.allocator, &ngt);
        defer ngt_root.deinit();
        while (x1 != NIL) {
            ngt = cons(heap, NTV(heap), ngt);
            tp(heap, h(heap, h(heap, x1))).* = ap(heap, bind_t, h(heap, ngt));
            x1 = t(heap, x1);
        }
        x1 = x;
        while (x1 != NIL) {
            oldte = cs().TYPERRS;
            cs().current_id = h(heap, x1);
            _ = unify(heap, t(heap, idType(heap, h(heap, x1))), etype(heap, idVal(heap, h(heap, x1)), NIL, ngt) catch return);
            if (cs().TYPERRS > oldte) {
                tp(heap, h(heap, h(heap, x1))).* = wrong_t;
                tp(heap, h(heap, x1)).* = UNDEF;
                cs().ND = add1(heap, Value.fromRaw(h(heap, x1)), Value.fromRaw(cs().ND)).toRaw();
            }
            x1 = t(heap, x1);
        }
        x1 = x;
        while (x1 != NIL) {
            if (idType(heap, h(heap, x1)) != wrong_t) {
                tp(heap, h(heap, h(heap, x1))).* = redtvars(heap, ult(heap, t(heap, idType(heap, h(heap, x1)))));
            }
            x1 = t(heap, x1);
        }
        resetSubst(heap);
    }
    cs().current_id = 0;
}

/// Initialise the type-system state (base types and counters).
pub fn tsetup(heap: *Heap) void {
    cs().tfnum = tf(heap, num_t, num_t);
    cs().tfbool = tf(heap, bool_t, bool_t);
    cs().tfnum2 = tf(heap, num_t, cs().tfnum);
    cs().tfbool2 = tf(heap, bool_t, cs().tfbool);
    cs().ltchar = lt(heap, char_t);
    cs().tfstrstr = tf(heap, cs().ltchar, cs().ltchar);
    cs().tfnumnum = tf(heap, num_t, num_t);
    cs().tstep = tf2(heap, num_t, num_t, lt(heap, num_t));
    cs().tstepuntil = tf(heap, num_t, cs().tstep);
}

/// Type-check every definition in the current script.
pub fn checktypes(heap: *Heap, core: *core_state.CoreState, comp: *compiler_state.CompilerState, rs: *rt.RuntimeState) void {
    comp.ATNAMES = 0;
    comp.TYPERRS = 0;
    comp.NT = NIL;
    comp.R = NIL;
    comp.SBND = NIL;
    comp.ND = NIL;
    outer: {
        if (script_store.store().rfl != NIL) {
            readoption(heap, comp, rs);
        }
        var s = reverse(t(heap, h(heap, heap.files)));
        var s_root = heap.roots.root(rt.allocator, &s);
        defer s_root.deinit();
        while (s != NIL) {
            compDeps(heap, h(heap, s)) catch break :outer;
            s = t(heap, s);
        }
        comp.R = tclos(heap, sortrel(heap, comp.R));
        if (comp.FBS != NIL) {
            mcheckfbs(heap) catch break :outer;
        }
        abstrMcheck(heap, comp.TABSTRS) catch break :outer;
    }
    if (comp.TYPERRS != 0) {
        comp.TABSTRS = NIL;
        comp.NT = NIL;
        comp.R = NIL;
        _ = word.printErr("typecheck cannot proceed - compilation abandoned\n", .{});
        core.SYNERR = 1;
        return;
    }
    if (script_store.store().freeids != NIL) {
        redtfr(heap, Value.fromRaw(script_store.store().freeids));
    }
    genshfns(heap);
    if (script_store.store().fnts != NIL) {
        genbnft(heap);
    }
    comp.R = msc(heap, Value.fromRaw(comp.R)).toRaw();
    var s = tsort(heap, Value.fromRaw(comp.R)).toRaw();
    var s_root = heap.roots.root(rt.allocator, &s);
    defer s_root.deinit();
    comp.NT = NIL;
    comp.R = NIL;
    while (s != NIL) {
        inferType(heap, h(heap, s));
        s = t(heap, s);
    }
    checkfbs(heap, core, comp);
    while (comp.TABSTRS != NIL) {
        abstrCheck(heap, h(heap, comp.TABSTRS)) catch {};
        comp.TABSTRS = t(heap, comp.TABSTRS);
    }
    if (comp.SBND != NIL) {
        printlist(heap, "SPECIFIED BUT NOT DEFINED: ", alfasort(heap, Value.fromRaw(comp.SBND)).toRaw());
        comp.SBND = NIL;
    }
    fixshows(heap);
    comp.lastloc = 0;
    if (options.is_strict or @import("builtin").mode == .Debug) {
        heap.validate();
        @import("../semantics/lower.zig").validate(heap);
        rs.validate();
    }
}
