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
const word = @import("../runtime/word.zig");
const errors = @import("../runtime/errors.zig");
const dump = @import("dump.zig");
const strtab = @import("../runtime/strtab.zig");
const os = @import("../runtime/os.zig");
const rt = @import("../runtime/runtime_state.zig");

const compiler_state = @import("compiler_state.zig");
const core_state = @import("../runtime/core_state.zig");
const heap_mod = @import("../runtime/heap.zig");
const Heap = heap_mod.Heap;
const tu = @import("../testutil.zig"); // unit-test harness (test builds only)
const cs = compiler_state.cs;
// `abi` — a private namespace of libc / `word`-combinator re-export aliases so
// this file can write `os.printf(...)`, `word.PLUS`, etc. Internal only (the
// container is not `pub`, so these never appear in autodoc); each member just
// re-exports an already-documented symbol from `os`/`word`.

const Word = word.Word;
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
const alfasort = heap_mod.alfasort;
const readoption = dump.readoption;
const out = heap_mod.outTerm;
const isChar = heap_mod.isChar;
const charname = heap_mod.charname;
const size = heap_mod.size;
const same = trans_mod.same;
const getDbl = heap_mod.getDbl;
const lastlink = trans_mod.lastlink;
const trans_mod = @import("trans.zig");
const lex_mod = @import("../parser/lex.zig");
const isconstrname = lex_mod.isconstrname;

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

/// Allocate a `CONS` cell `(x . y)`.
fn cons(x: Word, y: Word) Word {
    return make(.CONS, x, y);
}

/// Remove element `e` from set `ss` (in place via the pointer).
///
/// Tests: remove1: removes an element in place, reports hit/miss
pub fn remove1(heap: *Heap, e: Word, ss: *Word) Word {
    var p = ss;
    while (p.* != NIL and h(heap, p.*) < e) {
        p = tp(heap, p.*);
    }
    if (p.* == NIL or h(heap, p.*) != e) {
        return 0;
    }
    p.* = t(heap, p.*);
    return 1;
}

test "remove1: removes an element in place, reports hit/miss" {
    tu.freshInterp();
    var s = tu.list(&[_]Word{ 1000, 2000, 3000 });
    try std.testing.expectEqual(@as(Word, 1), remove1(heap_mod.heap(), 2000, &s));
    try tu.expectWords(&[_]Word{ 1000, 3000 }, s);
    try std.testing.expectEqual(@as(Word, 0), remove1(heap_mod.heap(), 5000, &s)); // miss
}

/// Set difference `s1 \ s2`.
///
/// Tests: setdiff: s1 minus s2
pub fn setdiff(heap: *Heap, s1_input: Word, s2_input: Word) Word {
    var s1 = s1_input;
    var s2 = s2_input;
    var ss1 = &s1;
    while (ss1.* != NIL and s2 != NIL) {
        if (h(heap, ss1.*) == h(heap, s2)) {
            ss1.* = t(heap, ss1.*);
        } else if (h(heap, ss1.*) < h(heap, s2)) {
            ss1 = tp(heap, ss1.*);
        } else {
            s2 = t(heap, s2);
        }
    }
    return s1;
}

test "setdiff: s1 minus s2" {
    tu.freshInterp();
    try tu.expectWords(&[_]Word{ 1000, 3000 }, setdiff(heap_mod.heap(), tu.list(&[_]Word{ 1000, 2000, 3000 }), tu.list(&[_]Word{2000})));
}

/// Add element `e` to set `s` (if not already present).
///
/// Tests: add1: inserts in sorted order without duplicates
pub fn add1(heap: *Heap, e: Word, s_input: Word) Word {
    var s = s_input;
    if (s == NIL or e < h(heap, s)) {
        return cons(e, s);
    }
    if (e == h(heap, s)) {
        return s;
    }
    while (t(heap, s) != NIL and e > h(heap, t(heap, s))) {
        s = t(heap, s);
    }
    if (t(heap, s) == NIL) {
        tp(heap, s).* = cons(e, NIL);
    } else if (e != h(heap, t(heap, s))) {
        tp(heap, s).* = cons(e, t(heap, s));
    }
    return s_input;
}

test "add1: inserts in sorted order without duplicates" {
    tu.freshInterp();
    try tu.expectWords(&[_]Word{ 1000, 2000, 3000 }, add1(heap_mod.heap(), 2000, tu.list(&[_]Word{ 1000, 3000 })));
    // already present → unchanged
    try tu.expectWords(&[_]Word{ 1000, 2000, 3000 }, add1(heap_mod.heap(), 2000, tu.list(&[_]Word{ 1000, 2000, 3000 })));
}

/// Prepend element `e` to set `s` (no membership check).
pub fn newadd1(heap: *Heap, e: Word, s_input: Word) Word {
    var s = s_input;
    cs.NEW = 1;
    if (s == NIL or e < h(heap, s)) {
        return cons(e, s);
    }
    if (e == h(heap, s)) {
        cs.NEW = 0;
        return s;
    }
    while (t(heap, s) != NIL and e > h(heap, t(heap, s))) {
        s = t(heap, s);
    }
    if (t(heap, s) == NIL) {
        tp(heap, s).* = cons(e, NIL);
    } else if (e != h(heap, t(heap, s))) {
        tp(heap, s).* = cons(e, t(heap, s));
    } else {
        cs.NEW = 0;
    }
    return s_input;
}

/// Set union of `s1` and `s2`.
///
/// Tests: UNION: sorted set union
pub fn UNION(heap: *Heap, s1_input: Word, s2_input: Word) Word {
    var s1 = s1_input;
    var s2 = s2_input;
    var ss = &s1;
    while (ss.* != NIL and s2 != NIL) {
        if (h(heap, ss.*) == h(heap, s2)) {
            ss = tp(heap, ss.*);
            s2 = t(heap, s2);
        } else if (h(heap, ss.*) < h(heap, s2)) {
            ss = tp(heap, ss.*);
        } else {
            ss.* = cons(h(heap, s2), ss.*);
            ss = tp(heap, ss.*);
            s2 = t(heap, s2);
        }
    }
    if (ss.* == NIL) {
        while (s2 != NIL) {
            ss.* = cons(h(heap, s2), ss.*);
            ss = tp(heap, ss.*);
            s2 = t(heap, s2);
        }
    }
    return s1;
}

test "UNION: sorted set union" {
    tu.freshInterp();
    try tu.expectWords(&[_]Word{ 1000, 2000, 3000 }, UNION(heap_mod.heap(), tu.list(&[_]Word{ 1000, 3000 }), tu.list(&[_]Word{ 2000, 3000 })));
}

/// Set intersection of `s1` and `s2`.
///
/// Tests: intersection: common elements
pub fn intersection(heap: *Heap, s1_input: Word, s2_input: Word) Word {
    var s1 = s1_input;
    var s2 = s2_input;
    var r: Word = NIL;
    while (s1 != NIL and s2 != NIL) {
        if (h(heap, s1) == h(heap, s2)) {
            r = cons(h(heap, s1), r);
            s1 = t(heap, s1);
            s2 = t(heap, s2);
        } else if (h(heap, s1) < h(heap, s2)) {
            s1 = t(heap, s1);
        } else {
            s2 = t(heap, s2);
        }
    }
    return reverse(r);
}

test "intersection: common elements" {
    tu.freshInterp();
    try tu.expectWords(&[_]Word{ 2000, 3000 }, intersection(heap_mod.heap(), tu.list(&[_]Word{ 1000, 2000, 3000 }), tu.list(&[_]Word{ 2000, 3000, 4000 })));
}

/// Whether `x` is a member of set `s`.
///
/// Tests: member: set membership (1/0)
pub fn member(heap: *Heap, s_input: Word, x: Word) Word {
    var s = s_input;
    while (s != NIL and x != h(heap, s)) {
        s = t(heap, s);
    }
    return if (s != NIL) 1 else 0;
}

test "member: set membership (1/0)" {
    tu.freshInterp();
    const s = tu.list(&[_]Word{ 1000, 2000, 3000 });
    try std.testing.expectEqual(@as(Word, 1), member(heap_mod.heap(), s, 2000));
    try std.testing.expectEqual(@as(Word, 0), member(heap_mod.heap(), s, 5000));
}

const type_t: Word = 10;
const shunt = heap_mod.shunt;

/// The type field of id `x`.
fn idType(heap: *Heap, x: Word) Word {
    return t(heap, h(heap, x));
}

/// Reorder a definition list so type declarations come first.
pub fn typesfirst(heap: *Heap, input_x: Word) Word {
    var x = input_x;
    var y = &x;
    var z: Word = NIL;
    while (y.* != NIL) {
        if (idType(heap, h(heap, y.*)) == type_t) {
            z = cons(h(heap, y.*), z);
            y.* = t(heap, y.*);
        } else {
            y = tp(heap, y.*);
        }
    }
    return shunt(z, x);
}

/// The standard-error `Stream` handle.
/// Topologically sort dependency graph `g` (for definition ordering).
pub fn tsort(heap: *Heap, g_input: Word) Word {
    var NP = NIL; // NP is set of elements with no predecessor
    var g1 = g_input;
    var r = NIL; // r is result
    var g = NIL;
    while (g1 != NIL) {
        if (t(heap, h(heap, g1)) == NIL) {
            NP = cons(h(heap, h(heap, g1)), NP);
        } else {
            g = cons(h(heap, g1), g);
        }
        g1 = t(heap, g1);
    }
    while (NP != NIL) {
        var D = NIL; // ids to be removed from range of g
        while (NP != NIL) {
            r = cons(h(heap, NP), r);
            if (getTag(heap, h(heap, NP)) == .ID) {
                D = add1(heap, h(heap, NP), D);
            } else {
                D = UNION(heap, D, h(heap, NP));
            }
            NP = t(heap, NP);
        }
        g1 = g;
        g = NIL;
        while (g1 != NIL) {
            const rhs = setdiff(heap, t(heap, h(heap, g1)), D);
            if (rhs == NIL) {
                NP = cons(h(heap, h(heap, g1)), NP);
            } else {
                tp(heap, h(heap, g1)).* = rhs;
                g = cons(h(heap, g1), g);
            }
            g1 = t(heap, g1);
        }
    }
    if (g != NIL) {
        _ = word.printErr("error: impossible event in tsort\n", .{});
    }
    return reverse(r);
}

/// Collapse mutually-recursive groups in relation `R` (companion to `tsort`).
pub fn msc(heap: *Heap, R_input: Word) Word {
    var R1 = R_input;
    while (R1 != NIL) {
        var r = tp(heap, h(heap, R1)); // word *r = &tl(hd(R1))
        const l = h(heap, h(heap, R1)); // word l = hd(hd(R1))
        if (remove1(heap, l, r) != 0) {
            hp(heap, h(heap, R1)).* = cons(l, NIL); // hd(hd(R1)) = cons(l, NIL)
            while (r.* != NIL) {
                const n = h(heap, r.*);
                var R2 = tp(heap, R1); // word *R2 = &tl(R1)
                while (R2.* != NIL and h(heap, h(heap, R2.*)) != n) {
                    R2 = tp(heap, R2.*);
                }
                if (R2.* != NIL and member(heap, t(heap, h(heap, R2.*)), l) != 0) {
                    r.* = t(heap, r.*); // *r = tl(*r)
                    R2.* = t(heap, R2.*); // *R2 = tl(*R2)
                    hp(heap, h(heap, R1)).* = add1(heap, n, h(heap, h(heap, R1)));
                } else {
                    r = tp(heap, r.*);
                }
            }
        }
        R1 = t(heap, R1);
    }
    return R_input;
}

const undef_t: Word = 0;
const bool_t: Word = 1;
const num_t: Word = 2;
const char_t: Word = 3;
const list_t: Word = 4;
const synonym_t = word.synonym_t;
const abstract_t = word.abstract_t;
const UNDEF: Word = CMBASE + 140;

/// Whether a type node is a compound (application) type.
fn isCompoundType(heap: *Heap, type_node: Word) bool {
    return getTag(heap, type_node) == .AP;
}
/// Whether a type node is a type variable.
fn isVarType(heap: *Heap, type_node: Word) bool {
    return getTag(heap, type_node) == .TVAR;
}

/// The arity stored in a type node.
fn tArity(heap: *Heap, x: Word) Word {
    return h(heap, h(heap, t(heap, x)));
}
/// The type class of a type node.
fn tClass(heap: *Heap, x: Word) Word {
    return h(heap, t(heap, t(heap, x)));
}
/// The info field of a type node.
fn tInfo(heap: *Heap, x: Word) Word {
    return t(heap, t(heap, t(heap, x)));
}
/// The `show` function recorded for a type node.
/// The value field of id `x`.
fn idVal(heap: *Heap, x: Word) Word {
    return t(heap, x);
}
/// The definition-site field of id `x`.
fn idWho(heap: *Heap, x: Word) Word {
    return t(heap, h(heap, h(heap, x)));
}

/// The interned name text of id `x`.
fn getId(heap: *Heap, x: Word) [*:0]const u8 {
    return strtab.strOf(strtab.table(), h(heap, h(heap, h(heap, x))));
}

/// Rewrite a type's outer constructor to `list_t` in place (for structural compare).
pub fn sterilise(heap: *Heap, t_val: Word) void {
    if (getTag(heap, t_val) == .AP) {
        hp(heap, t_val).* = list_t;
        tp(heap, t_val).* = num_t;
    }
}

/// Validate the well-formedness (arity) of type expression `t_val`.
fn metaTcheck(heap: *Heap, t_val: Word) errors.MiraError!Word {
    var tn = t_val;
    var i: Word = 0;
    while (isCompoundType(heap, tn)) {
        tp(heap, tn).* = try metaTcheck(heap, t(heap, tn));
        i += 1;
        tn = h(heap, tn);
    }
    if (getTag(heap, tn) != .STRCONS) {
        if (getTag(heap, tn) != .ID) {
            if (i > 0 and (isVarType(heap, tn) or tn == bool_t or tn == num_t or tn == char_t)) {
                cs().TYPERRS += 1;
                if (getTag(heap, cs().current_id) == .DATAPAIR) {
                    locateInc(heap);
                    _ = word.print("badly formed type \"", .{});
                    outType(heap, t_val);
                    _ = word.print("\" in binding for \"{s}\"\n", .{strtab.strOf(strtab.table(), h(heap, cs().current_id))});
                    _ = word.print("(", .{});
                    outType(heap, tn);
                    _ = word.print(" has zero arity)\n", .{});
                } else {
                    _ = word.print("badly formed type \"", .{});
                    outType(heap, t_val);
                    const msg: [*:0]const u8 = if (idType(heap, cs().current_id) == type_t) "== binding" else "specification";
                    _ = word.print("\" in {s} for \"{s}\"\n", .{ msg, getId(heap, cs().current_id) });
                    _ = word.print("(", .{});
                    outType(heap, tn);
                    _ = word.print(" has zero arity)\n", .{});
                    sayhere(heap, getspecloc(heap, cs().current_id), 1);
                }
                sterilise(heap, t_val);
            }
            return t_val;
        } else if (idType(heap, tn) == undef_t and idVal(heap, tn) == UNDEF) {
            cs().TYPERRS += 1;
            if (member(heap, cs().NT, tn) == 0) {
                if (getTag(heap, cs().current_id) == .DATAPAIR) {
                    locateInc(heap);
                }
                _ = word.print("undeclared typename \"{s}\" ", .{getId(heap, tn)});
                if (getTag(heap, cs().current_id) == .DATAPAIR) {
                    _ = word.print("in binding for {s}\n", .{strtab.strOf(strtab.table(), h(heap, cs().current_id))});
                } else {
                    sayhere(heap, getspecloc(heap, cs().current_id), 1);
                }
                cs().NT = add1(heap, tn, cs().NT);
            }
            return t_val;
        } else if (idType(heap, tn) != type_t or tArity(heap, tn) != i) {
            cs().TYPERRS += 1;
            if (getTag(heap, cs().current_id) == .DATAPAIR) {
                locateInc(heap);
                _ = word.print("badly formed type \"", .{});
                outType(heap, t_val);
                _ = word.print("\" in binding for \"{s}\"\n", .{strtab.strOf(strtab.table(), h(heap, cs().current_id))});
            } else {
                _ = word.print("badly formed type \"", .{});
                outType(heap, t_val);
                const msg: [*:0]const u8 = if (idType(heap, cs().current_id) == type_t) "== binding" else "specification";
                _ = word.print("\" in {s} for \"{s}\"\n", .{ msg, getId(heap, cs().current_id) });
            }
            if (idType(heap, tn) != type_t) {
                _ = word.print("({s} not defined as typename)\n", .{getId(heap, tn)});
            } else {
                _ = word.print("(typename {s} has arity {d})\n", .{ getId(heap, tn), tArity(heap, tn) });
            }
            if (getTag(heap, cs().current_id) != .DATAPAIR) {
                sayhere(heap, getspecloc(heap, cs().current_id), 1);
            }
            sterilise(heap, t_val);
            return t_val;
        }
    }

    if (tClass(heap, tn) != synonym_t) {
        return t_val;
    }
    if (member(heap, cs().meta_pending, tn) != 0) {
        cs().TYPERRS += 1; // report cycle
        if (getTag(heap, cs().current_id) == .DATAPAIR) {
            locateInc(heap);
        }
        const suffix: [*:0]const u8 = if (cs().meta_pending == NIL) "" else "s";
        _ = word.print("error: cycle in type \"==\" definition{s} ", .{suffix});
        printelement(heap, cs().meta_pending);
        _ = word.print("\n", .{});
        if (getTag(heap, cs().current_id) != .DATAPAIR) {
            sayhere(heap, idWho(heap, tn), 1);
        }
        return error.TypeCheckAbort;
    }
    cs().meta_pending = cons(tn, cs().meta_pending);
    tn = NIL;
    var cur_t = t_val;
    while (isCompoundType(heap, cur_t)) {
        tn = cons(t(heap, cur_t), tn);
        cur_t = h(heap, cur_t);
    }
    const res = try metaTcheck(heap, apSubst(heap, tInfo(heap, cur_t), tn));
    cs().meta_pending = t(heap, cs().meta_pending);
    return res;
}

/// Make a type-variable node with index `i`.
fn mktvar(i: Word) Word {
    return make(.TVAR, 0, i);
}

/// The index of type variable `x`.
fn gettvar(heap: *Heap, x: Word) Word {
    return t(heap, x);
}

/// Whether `x` and `y` are the same type variable.
fn eqtvar(heap: *Heap, x: Word, y: Word) bool {
    return t(heap, x) == t(heap, y);
}

const hashsize: usize = 512;

/// Hash a type variable to a substitution-table bucket index.
fn hashval(heap: *Heap, x: Word) usize {
    return @intCast(@mod(gettvar(heap, x), @as(Word, @intCast(hashsize))));
}

/// Allocate a fresh type variable.
fn NTV() Word {
    const res = mktvar(cs().tvcount);
    cs().tvcount += 1;
    return res;
}

/// Reset the substitution and return the empty substitution.
pub fn clearSubst(heap: *Heap) Word {
    fixshows(heap);
    @memset(&cs().SUBST, 0);
    cs().tvcount = 1;
    return 0;
}

/// Fix up the `show` functions after inference.
pub fn fixshows(heap: *Heap) void {
    while (cs().showchain != NIL) {
        tp(heap, h(heap, cs().showchain)).* = subst(heap, t(heap, h(heap, cs().showchain)));
        cs().showchain = t(heap, cs().showchain);
    }
}

/// The substitution binding for type variable `tv` (or `tv` itself if unbound).
pub fn lookup(heap: *Heap, tv: Word) Word {
    var h_val = cs().SUBST[hashval(heap, tv)];
    while (h_val != 0) {
        if (eqtvar(heap, h(heap, h(heap, h_val)), tv)) {
            return t(heap, h(heap, h_val));
        }
        h_val = t(heap, h_val);
    }
    return tv;
}

/// Bind type variable `tv` to `term` in the substitution.
pub fn addsubst(heap: *Heap, tv: Word, term: Word) void {
    const hv = hashval(heap, tv);
    cs().SUBST[hv] = cons(cons(tv, term), cs().SUBST[hv]);
}

/// Resolve `tv` to its ultimate substituted form (union-find walk).
fn ult(heap: *Heap, tv: Word) Word {
    const s = lookup(heap, tv);
    return if (s == tv) tv else subst(heap, s);
}

/// Allocate an application cell `(x y)`.
fn ap(x: Word, y: Word) Word {
    return make(.AP, x, y);
}

/// Apply `f` to every type variable in `term`, rebuilding it.
fn walktype(heap: *Heap, term: Word, f: *const fn (*Heap, Word) Word) Word {
    if (isVarType(heap, term)) {
        return f(heap, term);
    }
    if (isCompoundType(heap, term)) {
        const h1 = walktype(heap, h(heap, term), f);
        const t1 = walktype(heap, t(heap, term), f);
        return if (h1 == h(heap, term) and t1 == t(heap, term)) term else ap(h1, t1);
    }
    return term;
}

/// Apply the current substitution throughout `term`.
pub fn subst(heap: *Heap, term: Word) Word {
    return walktype(heap, term, ult);
}

/// Per-variable map for `linst`: copy generic vars, keep non-generic ones.
fn lmap(heap: *Heap, tv: Word) Word {
    if (nonGeneric(heap, tv)) {
        return tv;
    }
    var l = cs().localtvmap;
    while (l != NIL) {
        if (h(heap, h(heap, l)) == tv) {
            return t(heap, h(heap, l));
        }
        l = t(heap, l);
    }
    const new_var = NTV();
    cs().localtvmap = cons(cons(tv, new_var), cs().localtvmap);
    return new_var;
}

/// Instantiate `term`, freshening its generic type variables (`ngt` = the non-generic set).
pub fn linst(heap: *Heap, term: Word, ngt: Word) Word {
    cs().localtvmap = NIL;
    cs().NGT = ngt;
    return walktype(heap, term, lmap);
}

/// Whether type variable `tv` is non-generic / monomorphic (1/0).
pub fn nonGeneric(heap: *Heap, tv: Word) bool {
    var x = cs().NGT;
    while (x != NIL) {
        if (occurs(heap, tv, subst(heap, h(heap, x)))) {
            return true;
        }
        x = t(heap, x);
    }
    return false;
}

/// Map a type variable up through `tvmap` (instantiation direction).
fn mapup(heap: *Heap, tv_in: Word) Word {
    var m: *Word = &cs().tvmap;
    var tv = gettvar(heap, tv_in);
    tv -= 1;
    while (tv > 0) : (tv -= 1) {
        m = tp(heap, m.*);
    }
    if (m.* == NIL) {
        m.* = cons(NTV(), NIL);
    }
    return h(heap, m.*);
}

/// Instantiate a polymorphic type with fresh variables.
pub fn instantiate(heap: *Heap, term: Word) Word {
    cs().tvmap = NIL;
    return walktype(heap, term, mapup);
}

/// Apply the substitution `args` to `term`.
pub fn apSubst(heap: *Heap, term: Word, args: Word) Word {
    cs().tvmap = args;
    const r = walktype(heap, term, mapup);
    cs().tvmap = NIL;
    return r;
}

/// Map a type variable down to a compact index through `tvmap`.
fn mapdown(heap: *Heap, tv: Word) Word {
    var m: *Word = &cs().tvmap;
    var i: Word = 1;
    while (m.* != NIL and !eqtvar(heap, h(heap, m.*), tv)) {
        m = tp(heap, m.*);
        i += 1;
    }
    if (m.* == NIL) {
        m.* = cons(tv, NIL);
    }
    return mktvar(i);
}

/// Renumber a term's type variables to a compact 1..n.
pub fn redtvars(heap: *Heap, term: Word) Word {
    cs().tvmap = NIL;
    return walktype(heap, term, mapdown);
}

/// The occurs check: whether `tv` appears in `t_val` (1/0).
pub fn occurs(heap: *Heap, tv: Word, t_val: Word) bool {
    var term = t_val;
    while (isCompoundType(heap, term)) {
        if (occurs(heap, tv, t(heap, term))) {
            return true;
        }
        term = h(heap, term);
    }
    return tv == term;
}

/// Whether type `t_val` is polymorphic — contains type variables (1/0).
pub fn ispoly(heap: *Heap, t_val: Word) bool {
    var term = t_val;
    while (isCompoundType(heap, term)) {
        if (ispoly(heap, t(heap, term))) {
            return true;
        }
        term = h(heap, term);
    }
    return isVarType(heap, term);
}

/// The standard-output `Stream` handle.
fn getStdout() ?*word.Stream {
    const T = @TypeOf(os.stdout);
    if (comptime @typeInfo(T) == .@"fn") {
        return os.stdout();
    } else if (comptime @typeInfo(T) == .pointer and @typeInfo(@typeInfo(T).pointer.child) == .@"fn") {
        return os.stdout();
    } else {
        return os.stdout;
    }
}

/// Record the current definition name `s` for error messages.
pub fn locate(heap: *Heap, s: [*:0]const u8) void {
    cs().TYPERRS += 1;
    if (cs().TYPERRS == 1 or cs().lastloc != cs().current_id) {
        if (cs().current_id != 0) {
            if (getTag(heap, cs().current_id) == .DATAPAIR) {
                locateInc(heap);
                _ = word.print("{s} in binding for {s}\n", .{ s, strtab.strOf(strtab.table(), h(heap, cs().current_id)) });
                return;
            }
            var x = cs().current_id;
            _ = word.print("{s} in definition of ", .{s});
            while (getTag(heap, x) == .CONS) {
                if (getTag(heap, t(heap, x)) == .ID and member(heap, rt.rs().fnts, t(heap, x)) != 0) {
                    _ = word.print("nonterminal ", .{});
                    x = h(heap, x);
                } else {
                    outFormal1(heap, getStdout().?, h(heap, x));
                    _ = word.print(", subdef of ", .{});
                    x = t(heap, x);
                }
            }
            _ = word.print("{s}", .{getId(heap, x)});
            _ = word.print("\n", .{});
        } else {
            _ = word.print("{s} in expression\n", .{s});
        }
    }
    if (cs().lineptr != 0) {
        sayhere(heap, cs().lineptr, 0);
    } else if (cs().current_id != 0 and idWho(heap, cs().current_id) != NIL) {
        sayhere(heap, idWho(heap, cs().current_id), 0);
    }
    cs().lastloc = cs().current_id;
}

/// The source location of right-hand side `r`.
pub fn rhsHere(heap: *Heap, r: Word) Word {
    if (getTag(heap, r) == .LABEL) {
        return h(heap, r);
    }
    if (getTag(heap, r) == .TRIES) {
        return h(heap, h(heap, lastlink(heap, t(heap, r))));
    }
    return 0;
}

/// Print a source-location marker `h_val` (with optional newline).
pub fn sayhere(heap: *Heap, h_val: Word, nl: Word) void {
    var h_node = h_val;
    if (getTag(heap, h_node) != .FILEINFO) {
        h_node = rhsHere(heap, h_node);
        if (getTag(heap, h_node) != .FILEINFO) {
            _ = word.printErr("(impossible event in sayhere)\n", .{});
            return;
        }
    }
    const h_str = strtab.strOf(strtab.table(), h(heap, h_node));
    const eq = std.mem.eql(u8, std.mem.span(h_str), std.mem.span(rt.rs().current_script.?));
    const prefix: [*:0]const u8 = if (eq) "" else "%insert file ";
    word.print("(line {d:>3} of {s}\"{s}\")", .{ t(heap, h_node), prefix, h_str });
    if (nl != 0) {
        _ = word.print("\n", .{});
    } else {
        _ = word.print(" ", .{});
    }
    if (eq) {
        if (core_state.s().errline == 0) {
            core_state.s().errline = t(heap, h_node);
        }
    } else {
        if (core_state.s().errs == 0) {
            core_state.s().errs = h_node;
        }
    }
}

/// Print the inferred type of `x` (the `::` response).
pub fn reportType(heap: *Heap, x: Word) void {
    _ = word.print("{s}", .{getId(heap, x)});
    if (idType(heap, x) == type_t) {
        const arity = tArity(heap, x);
        if (arity > 5) {
            _ = word.print("(arity {d})", .{arity});
        } else {
            var i: Word = 1;
            while (i <= arity) : (i += 1) {
                _ = word.print(" ", .{});
                var j: Word = 0;
                while (j < i) : (j += 1) {
                    _ = word.print("*", .{});
                }
            }
        }
    }
    _ = word.print(" :: ", .{});
    outType(heap, idType(heap, x));
}

/// Report a type mismatch between `t1_val` and `t2_val` (`a`/`b` name the sides).
pub fn typeError(heap: *Heap, a: [*:0]const u8, b: [*:0]const u8, t1_val: Word, t2_val: Word) void {
    var t1 = redtvars(heap, ap(subst(heap, t1_val), subst(heap, t2_val)));
    const t2 = t(heap, t1);
    t1 = h(heap, t1);
    locate(heap, "type error");
    _ = word.print("cannot {s} ", .{a});
    outType(heap, t1);
    _ = word.print(" {s} ", .{b});
    outType(heap, t2);
    _ = word.print("\n", .{});
}

/// Report type error variant 1 for `x`.
pub fn typeError1(heap: *Heap, x: Word) void {
    locate(heap, "type error");
    _ = word.print("typename used as identifier ({s})\n", .{getId(heap, x)});
}

/// Report type error variant 2 for `x`.
pub fn typeError2(heap: *Heap, x: Word) void {
    if (core_state.s().compiling != 0) {
        return;
    }
    cs().TYPERRS += 1;
    _ = word.print("undefined name - {s}\n", .{getId(heap, x)});
}

/// Report type error variant 3 for `x`.
pub fn typeError3(heap: *Heap, x: Word) void {
    locate(heap, "error");
    _ = word.print("constructor \"{s}\" used at wrong arity in formal\n", .{getId(heap, x)});
}

/// Report type error variant 4 for `x`.
pub fn typeError4(heap: *Heap, x: Word) void {
    locate(heap, "error");
    _ = word.print("illegal object \"", .{});
    outPattern(heap, getStdout().?, x);
    _ = word.print("\" as head of formal\n", .{});
}

/// Report type error variant 5 for `x`.
pub fn typeError5(heap: *Heap, x: Word) void {
    locate(heap, "error");
    _ = word.print("undeclared constructor \"", .{});
    outPattern(heap, getStdout().?, x);
    _ = word.print("\" in formal\n", .{});
    cs().ND = add1(heap, x, cs().ND);
}

/// Report type error variant 6 (`x` applied to `f`/`a`).
pub fn typeError6(heap: *Heap, x: Word, f: Word, a: Word) void {
    cs().TYPERRS += 1;
    _ = word.print("incorrect declaration ", .{});
    sayhere(heap, cs().lineptr, 1);
    _ = word.print("specified, {s} :: ", .{getId(heap, x)});
    outType(heap, f);
    _ = word.print("\n", .{});
    _ = word.print("inferred,  {s} :: ", .{getId(heap, x)});
    outType(heap, redtvars(heap, subst(heap, a)));
    _ = word.print("\n", .{});
}

/// Report type error variant 7 between `a` and `b`.
pub fn typeError7(heap: *Heap, a: Word, b: Word) void {
    locate(heap, "type error");
    _ = word.print("\nrhs of lex rule :: ", .{});
    outType(heap, redtvars(heap, subst(heap, b)));
    _ = word.print("\n type expected  :: ", .{});
    outType(heap, redtvars(heap, subst(heap, a)));
    _ = word.print("\n", .{});
}

/// Report type error variant 8 between `t1_val` and `t2_val`.
pub fn typeError8(heap: *Heap, t1_val: Word, t2_val: Word) void {
    var t1 = subst(heap, t1_val);
    var t2 = subst(heap, t2_val);
    if (same(heap, h(heap, t1), h(heap, t2)) != 0) {
        t1 = t(heap, t1);
        t2 = t(heap, t2);
    }
    t1 = redtvars(heap, ap(t1, t2));
    t2 = t(heap, t1);
    t1 = h(heap, t1);
    const big = size(t1) >= 10 or size(t2) >= 10;
    locate(heap, "type error");
    const prefix: [*:0]const u8 = if (big) "\n " else " ";
    _ = word.print("cannot unify{s} ", .{prefix});
    outType(heap, t1);
    const infix: [*:0]const u8 = if (big) "\nwith\n  " else " with ";
    _ = word.print("{s}", .{infix});
    outType(heap, t2);
    _ = word.print("\n", .{});
}

const comma_t: Word = 5;
const arrow_t: Word = 6;
const void_t: Word = 7;
const wrong_t: Word = 8;

/// Whether a type node is a function (`->`) type.
fn isArrowType(heap: *Heap, t_val: Word) bool {
    return getTag(heap, t_val) == .AP and getTag(heap, h(heap, t_val)) == .AP and h(heap, h(heap, t_val)) == arrow_t;
}
/// Whether a type node is a tuple (comma) type.
fn isCommaType(heap: *Heap, t_val: Word) bool {
    return getTag(heap, t_val) == .AP and getTag(heap, h(heap, t_val)) == .AP and h(heap, h(heap, t_val)) == comma_t;
}
/// Whether a type node is a list type.
fn isListType(heap: *Heap, t_val: Word) bool {
    return getTag(heap, t_val) == .AP and h(heap, t_val) == list_t;
}

/// Print a type expression `t_val`.
pub fn outType(heap: *Heap, t_val: Word) void {
    var type_node = t_val;
    while (isArrowType(heap, type_node)) {
        outType1(heap, t(heap, h(heap, type_node)));
        _ = word.print("->", .{});
        type_node = t(heap, type_node);
    }
    outType1(heap, type_node);
}

/// Print a type at the next precedence level.
pub fn outType1(heap: *Heap, t_val: Word) void {
    var type_node = t_val;
    if (isCompoundType(heap, type_node) and !isCommaType(heap, type_node) and !isListType(heap, type_node) and !isArrowType(heap, type_node)) {
        outType1(heap, h(heap, type_node));
        _ = word.print(" ", .{});
        type_node = t(heap, type_node);
    }
    outType2(heap, type_node);
}

/// Print a primary (atomic) type.
pub fn outType2(heap: *Heap, t_val: Word) void {
    if (isListType(heap, t_val)) {
        _ = word.print("[", .{});
        outType(heap, t(heap, t_val));
        _ = word.print("]", .{});
    } else if (isCompoundType(heap, t_val)) {
        _ = word.print("(", .{});
        outTypeList(heap, t_val);
        if (isCommaType(heap, t_val) and t(heap, t_val) == void_t) {
            _ = word.print(",", .{});
        }
        _ = word.print(")", .{});
    } else {
        switch (t_val) {
            bool_t => {
                _ = word.print("bool", .{});
            },
            num_t => {
                _ = word.print("num", .{});
            },
            char_t => {
                _ = word.print("char", .{});
            },
            wrong_t => {
                _ = word.print("WRONG", .{});
            },
            undef_t => {
                _ = word.print("UNKNOWN", .{});
            },
            void_t => {
                _ = word.print("()", .{});
            },
            type_t => {
                _ = word.print("type", .{});
            },
            else => {
                switch (getTag(heap, t_val)) {
                    .ID => {
                        _ = word.print("{s}", .{getId(heap, t_val)});
                    },
                    .TVAR => {
                        var n = gettvar(heap, t_val);
                        if (n > 0 and n < 7) {
                            while (n > 0) : (n -= 1) {
                                _ = word.print("*", .{});
                            }
                        } else {
                            _ = word.print("{d}", .{n});
                        }
                    },
                    .STRCONS => {
                        const pn_val_node = pnVal(heap, t_val);
                        if (getTag(heap, pn_val_node) == .ID) {
                            _ = word.print("{s}", .{getId(heap, pn_val_node)});
                        } else if (std.mem.eql(u8, std.mem.span(strtab.strOf(strtab.table(), h(heap, t(heap, tInfo(heap, t_val))))), std.mem.span(rt.rs().current_script.?))) {
                            _ = word.print("{s}", .{strtab.strOf(strtab.table(), h(heap, h(heap, tInfo(heap, t_val))))});
                        } else {
                            _ = word.print("`{s}@{s}'", .{ strtab.strOf(strtab.table(), h(heap, h(heap, tInfo(heap, t_val)))), strtab.strOf(strtab.table(), h(heap, t(heap, tInfo(heap, t_val)))) });
                        }
                    },
                    else => {
                        _ = word.print("<BADLY FORMED TYPE:{d},{d},{d}>", .{ @intFromEnum(getTag(heap, t_val)), h(heap, t_val), t(heap, t_val) });
                    },
                }
            },
        }
    }
}

/// Print a comma-separated list of types.
pub fn outTypeList(heap: *Heap, t_val: Word) void {
    var type_node = t_val;
    while (isCommaType(heap, type_node)) {
        outType(heap, t(heap, h(heap, type_node)));
        type_node = t(heap, type_node);
        if (isCommaType(heap, type_node)) {
            _ = word.print(",", .{});
        } else if (type_node != void_t) {
            _ = word.print("<>", .{});
        }
    }
    if (type_node == void_t) {
        return;
    }
    outType(heap, type_node);
}

/// The value (tail) of a private-name node.
fn pnVal(heap: *Heap, x: Word) Word {
    return t(heap, x);
}

const PLUS: Word = CMBASE + 54;

/// The sign bit of `x` (bignum negativity test).
fn neg(heap: *Heap, x: Word) Word {
    return h(heap, x) & 0x10000000;
}

/// The argument of the outermost type application of `x`.
pub fn tail(heap: *Heap, x_in: Word) Word {
    var x = x_in;
    cs().allchars = 1;
    while (getTag(heap, x) == .CONS) {
        const char_res = isChar(h(heap, x));
        cs().allchars = if (char_res) cs().allchars & 1 else 0;
        x = t(heap, x);
    }
    return x;
}

/// Print a formal parameter at the next precedence level.
pub fn outFormal1(heap: *Heap, f: *word.Stream, x_in: Word) void {
    var x = x_in;
    if (h(heap, x) == CONST) {
        x = t(heap, x);
    }
    if (x == NIL) {
        _ = (f).print("[]", .{});
        return;
    }
    switch (getTag(heap, x)) {
        .CONS => {
            if (tail(heap, x) == NIL) {
                if (cs().allchars != 0) {
                    _ = (f).print("\"", .{});
                    while (x != NIL) {
                        _ = (f).print("{s}", .{charname(h(heap, x))});
                        x = t(heap, x);
                    }
                    _ = (f).print("\"", .{});
                } else {
                    _ = (f).print("[", .{});
                    while (x != core_state.s().nill and x != NIL) {
                        outPattern(heap, f, h(heap, x));
                        x = t(heap, x);
                        if (x != core_state.s().nill and x != NIL) {
                            _ = (f).print(",", .{});
                        }
                    }
                    _ = (f).print("]", .{});
                }
            } else {
                _ = (f).print("(", .{});
                outPattern(heap, f, x);
                _ = (f).print(")", .{});
            }
        },
        .AP => {
            _ = (f).print("(", .{});
            outPattern(heap, f, x);
            _ = (f).print(")", .{});
        },
        .TCONS, .PAIR => {
            _ = (f).print("(", .{});
            while (getTag(heap, x) == .TCONS) {
                outPattern(heap, f, h(heap, x));
                x = t(heap, x);
                _ = (f).print(",", .{});
            }
            outPattern(heap, f, h(heap, x));
            _ = (f).print(",", .{});
            outPattern(heap, f, t(heap, x));
            _ = (f).print(")", .{});
        },
        .INT => {
            if (neg(heap, x) != 0) {
                _ = (f).print("(", .{});
                out(f, x);
                _ = (f).print(")", .{});
            } else {
                out(f, x);
            }
        },
        .DOUBLE => {
            if (getDbl(x) < 0) {
                _ = (f).print("(", .{});
                out(f, x);
                _ = (f).print(")", .{});
            } else {
                out(f, x);
            }
        },
        else => {
            out(f, x);
        },
    }
}

/// Print a pattern `x`.
pub fn outPattern(heap: *Heap, f: *word.Stream, x: Word) void {
    if (getTag(heap, x) == .CONS) {
        if (h(heap, x) == CONST and (getTag(heap, t(heap, x)) == .INT or getTag(heap, t(heap, x)) == .DOUBLE)) {
            out(f, t(heap, x));
        } else if (h(heap, x) != CONST and tail(heap, x) != NIL) {
            outFormal(heap, f, h(heap, x));
            _ = (f).print(":", .{});
            outPattern(heap, f, t(heap, x));
        } else {
            outFormal(heap, f, x);
        }
    } else {
        outFormal(heap, f, x);
    }
}

/// Print a formal parameter `x`.
pub fn outFormal(heap: *Heap, f: *word.Stream, x: Word) void {
    if (getTag(heap, x) != .AP) {
        outFormal1(heap, f, x);
    } else if (getTag(heap, h(heap, x)) == .AP and h(heap, h(heap, x)) == PLUS) {
        outFormal(heap, f, t(heap, x));
        _ = (f).print("+", .{});
        out(f, t(heap, h(heap, x)));
    } else {
        outFormal(heap, f, h(heap, x));
        _ = (f).print(" ", .{});
        outFormal1(heap, f, t(heap, x));
    }
}

const CONST = word.CONST;

/// Whether `x` names a data constructor.
fn isConstructor(heap: *Heap, x: Word) bool {
    return getTag(heap, x) == .ID and isconstrname(getId(heap, x));
}

/// Remove the variables bound by pattern `p` from set `x`.
pub fn rembvars(heap: *Heap, x_in: Word, p_in: Word) Word {
    var x = x_in;
    var p = p_in;
    while (true) {
        switch (getTag(heap, p)) {
            .ID => {
                _ = remove1(heap, p, &x);
                return x;
            },
            .CONS => {
                if (h(heap, p) == CONST) {
                    return x;
                }
                x = rembvars(heap, x, h(heap, p));
                p = t(heap, p);
            },
            .AP => {
                if (getTag(heap, h(heap, p)) == .AP and h(heap, h(heap, p)) == PLUS) {
                    p = t(heap, p);
                } else {
                    x = rembvars(heap, x, h(heap, p));
                    p = t(heap, p);
                }
            },
            .PAIR, .TCONS => {
                x = rembvars(heap, x, h(heap, p));
                p = t(heap, p);
            },
            else => {
                _ = word.printErr("impossible event in rembvars\n", .{});
                return x;
            },
        }
    }
}

/// The dependency set of definition `x`.
pub fn deps(heap: *Heap, x_in: Word) Word {
    var x = x_in;
    var d = NIL;
    while (true) {
        switch (getTag(heap, x)) {
            .AP, .TCONS, .PAIR, .CONS => {
                d = UNION(heap, d, deps(heap, h(heap, x)));
                x = t(heap, x);
            },
            .ID => {
                return if (isConstructor(heap, x)) d else add1(heap, x, d);
            },
            .LAMBDA => {
                return rembvars(heap, UNION(heap, d, deps(heap, t(heap, x))), h(heap, x));
            },
            .LET => {
                d = rembvars(heap, UNION(heap, d, deps(heap, t(heap, x))), h(heap, h(heap, x)));
                return UNION(heap, d, deps(heap, t(heap, t(heap, h(heap, x)))));
            },
            .LETREC => {
                d = UNION(heap, d, deps(heap, t(heap, x)));
                var y = h(heap, x);
                while (y != NIL) {
                    d = UNION(heap, d, deps(heap, t(heap, t(heap, h(heap, y)))));
                    y = t(heap, y);
                }
                y = h(heap, x);
                while (y != NIL) {
                    d = rembvars(heap, d, h(heap, h(heap, y)));
                    y = t(heap, y);
                }
                return d;
            },
            .LEXER => {
                var lex_x = x;
                while (lex_x != NIL) {
                    d = UNION(heap, d, deps(heap, t(heap, t(heap, h(heap, lex_x)))));
                    lex_x = t(heap, lex_x);
                }
                return d;
            },
            .TRIES, .LABEL => {
                x = t(heap, x);
            },
            .SHARE => {
                x = h(heap, x);
            },
            else => return d,
        }
    }
}

/// Compute and record the dependencies of `n`.
fn compDeps(heap: *Heap, n: Word) errors.MiraError!void {
    var rhs = NIL;
    var r: Word = 0;
    if (idType(heap, n) == type_t) {
        switch (tClass(heap, n)) {
            algebraic_t => {
                r = tInfo(heap, n);
                while (r != NIL) {
                    cs().current_id = h(heap, r);
                    tp(heap, h(heap, h(heap, r))).* = redtvars(heap, try metaTcheck(heap, idType(heap, h(heap, r))));
                    r = t(heap, r);
                }
            },
            synonym_t => {
                cs().current_id = n;
                tp(heap, t(heap, t(heap, n))).* = try metaTcheck(heap, tInfo(heap, n));
            },
            abstract_t => {
                if (tInfo(heap, n) == undef_t) {
                    _ = word.print("error: script contains no binding for abstract typename \"{s}\"\n", .{getId(heap, n)});
                    sayhere(heap, idWho(heap, n), 1);
                    cs().TYPERRS += 1;
                } else {
                    cs().current_id = n;
                    tp(heap, t(heap, t(heap, n))).* = try metaTcheck(heap, tInfo(heap, n));
                }
            },
            else => {},
        }
        cs().current_id = 0;
        return;
    }
    if (getTag(heap, t(heap, n)) == .CONSTRUCTOR) {
        return;
    }
    if (idType(heap, n) != undef_t) {
        cs().current_id = n;
        if (getTag(heap, idType(heap, n)) == .CONS) {
            if (t(heap, n) == UNDEF) {
                cs().SBND = add1(heap, n, cs().SBND);
            }
            tp(heap, h(heap, n)).* = redtvars(heap, try metaTcheck(heap, h(heap, idType(heap, n))));
            cs().current_id = 0;
            return;
        }
        tp(heap, h(heap, n)).* = redtvars(heap, try metaTcheck(heap, idType(heap, n)));
        cs().current_id = 0;
    }
    if (t(heap, n) == FREE) {
        return;
    }
    if (t(heap, n) == UNDEF) {
        cs().SBND = add1(heap, n, cs().SBND);
        return;
    }
    r = deps(heap, t(heap, n));
    while (r != NIL) {
        if (t(heap, h(heap, r)) != UNDEF and idType(heap, h(heap, r)) == undef_t) {
            rhs = add1(heap, h(heap, r), rhs);
        }
        r = t(heap, r);
    }
    cs().R = cons(cons(n, rhs), cs().R);
}

const algebraic_t = word.algebraic_t;
const FREE = word.FREE;

/// Renumber type variables across a list of definitions.
pub fn redtfr(heap: *Heap, x_in: Word) void {
    var x = x_in;
    while (x != NIL) {
        tp(heap, t(heap, h(heap, x))).* = idType(heap, h(heap, h(heap, x)));
        x = t(heap, x);
    }
}

/// Print one debug element.
pub fn printelement(heap: *Heap, x: Word) void {
    if (getTag(heap, x) != .CONS) {
        out(getStdout().?, x);
        return;
    }
    _ = word.print("(", .{});
    var cur = x;
    while (cur != NIL) {
        out(getStdout().?, h(heap, cur));
        cur = t(heap, cur);
        if (cur != NIL) {
            _ = word.print(" ", .{});
        }
    }
    _ = word.print(")", .{});
}

/// Print a titled list (debug).
pub fn printlist(heap: *Heap, title: [*:0]const u8, l_in: Word) void {
    var l = l_in;
    _ = word.print("{s}", .{title});
    while (l != NIL) {
        printelement(heap, h(heap, l));
        l = t(heap, l);
        if (l != NIL) {
            _ = word.print(",", .{});
        }
    }
    _ = word.print(";\n", .{});
}

/// The value field of a type/definition cell.
fn theVal(heap: *Heap, x: Word) Word {
    return t(heap, x);
}

/// Clear the substitution table.
fn resetSubst(heap: *Heap) void {
    cs().current_id = if (cs().tvcount >= @as(Word, @intCast(hashsize))) clearSubst(heap) else 0;
}

/// Mark the current location as inside an `%include`.
pub fn locateInc(heap: *Heap) void {
    if (cs().lasthereinc == cs().hereinc) {
        return;
    }
    _ = word.print("incorrect %include directive ", .{});
    cs().lasthereinc = cs().hereinc;
    sayhere(heap, cs().hereinc, 1);
}

/// Detect cyclic abstract-type definitions among `atnames`.
pub fn cyclicAbstr(heap: *Heap, atnames: Word) Word {
    var x = atnames;
    var y = NIL;
    while (x != NIL) {
        y = ap(y, tInfo(heap, h(heap, x)));
        x = t(heap, x);
    }
    x = atnames;
    while (x != NIL) {
        if (occurs(heap, h(heap, x), y)) {
            _ = word.print("illegal type abstraction: cycle in \"==\" binding{s} ", .{if (t(heap, atnames) == NIL) @as([*:0]const u8, "") else @as([*:0]const u8, "s")});
            printelement(heap, atnames);
            _ = word.putchar('\n');
            sayhere(heap, idWho(heap, h(heap, x)), 1);
            cs().TYPERRS += 1;
            return 1;
        }
        x = t(heap, x);
    }
    return 0;
}

/// Expand type synonyms: replace ids `ids` throughout `x`.
pub fn txchange(heap: *Heap, ids_in: Word, x_in: Word) void {
    var ids = ids_in;
    var x = x_in;
    while (ids != NIL) {
        const t_val = idType(heap, h(heap, ids));
        tp(heap, h(heap, h(heap, ids))).* = h(heap, x);
        hp(heap, x).* = t_val;
        ids = t(heap, ids);
        x = t(heap, x);
    }
}

/// Substitute type arguments `L` for the formals of type `T`.
pub fn repT1(heap: *Heap, T: Word, L: Word) Word {
    var args = NIL;
    var t1 = T;
    var changed = false;
    while (isCompoundType(heap, t1)) {
        const a = repT1(heap, t(heap, t1), L);
        if (a != t(heap, t1)) {
            changed = true;
        }
        args = cons(a, args);
        t1 = h(heap, t1);
    }
    if (member(heap, L, t1) != 0) {
        return apSubst(heap, tInfo(heap, t1), args);
    }
    if (!changed) {
        return T;
    }
    while (args != NIL) {
        t1 = ap(t1, h(heap, args));
        args = t(heap, args);
    }
    return t1;
}

/// Replace type `T`'s formal parameters with arguments `L`, then renumber.
pub fn repT(heap: *Heap, T: Word, L: Word) Word {
    const t_val = repT1(heap, T, L);
    return if (t_val == T) t_val else redtvars(heap, t_val);
}

/// Normalise a type node after loading a dump (fix up indices).
pub fn fixType(heap: *Heap, t_val: Word) Word {
    var t_node = t_val;
    switch (getTag(heap, t_node)) {
        .AP, .CONS => {
            tp(heap, t_node).* = fixType(heap, t(heap, t_node));
            hp(heap, t_node).* = fixType(heap, h(heap, t_node));
            return t_node;
        },
        .STRCONS => {
            while (getTag(heap, pnVal(heap, t_node)) != .CONS) {
                t_node = pnVal(heap, t_node);
            }
            return t_node;
        },
        else => {
            return t_node;
        },
    }
}

/// Check an abstract-type declaration `x`.
fn abstrCheck(heap: *Heap, x_in: Word) errors.MiraError!void {
    var x = x_in;
    const rtypes = t(heap, h(heap, x));
    const sigids = t(heap, x);
    cs().ATNAMES = h(heap, h(heap, x));
    txchange(heap, sigids, rtypes); // install representation types
    x = sigids;
    while (x != NIL) {
        const oldte = cs().TYPERRS;
        cs().current_id = h(heap, x);
        const t_val = subst(heap, try etype(heap, idVal(heap, h(heap, x)), NIL, NIL));
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
            cs().ND = add1(heap, h(heap, x), cs().ND);
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
        if (cyclicAbstr(heap, atnames) != 0) {
            return;
        }
        while (sigids != NIL) {
            const t_val = idType(heap, h(heap, sigids));
            if (t_val == undef_t) {
                rtypes = cons(undef_t, rtypes);
            } else {
                rtypes = cons(try metaTcheck(heap, t_val), rtypes);
            }
            sigids = t(heap, sigids);
        }
        rtypes = reverse(rtypes);
        hp(heap, h(heap, tabstrs)).* = cons(h(heap, h(heap, tabstrs)), rtypes);
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
            const t1 = fixType(heap, t(heap, t(heap, h(heap, formals))));
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

/// Build and cache the `filestat` result type.
pub fn genlstatType() Word {
    if (cs().filestat_t == 0) {
        cs().filestat_t = tf(cs().ltchar, pairType(pairType(num_t, num_t), num_t));
    }
    return cs().filestat_t;
}

const bind_t: Word = 9;

/// Whether a type node is a bound type variable.
fn isBoundType(heap: *Heap, type_node: Word) bool {
    return isCompoundType(heap, type_node) and h(heap, type_node) == bind_t;
}

/// Allocate `((x y) z)`.
fn ap2(x: Word, y: Word, z: Word) Word {
    return ap(ap(x, y), z);
}

/// Build a function type `a -> b`.
fn tf(a: Word, b: Word) Word {
    return ap2(arrow_t, a, b);
}

/// Build the function type `a -> b -> c`.
fn tf2(a: Word, b: Word, c_param: Word) Word {
    return tf(a, tf(b, c_param));
}

/// Build the function type `a -> b -> c -> d`.
fn tf3(a: Word, b: Word, c_param: Word, d: Word) Word {
    return tf(a, tf2(b, c_param, d));
}

/// Build the function type `a -> b -> c -> d -> e`.
fn tf4(a: Word, b: Word, c_param: Word, d: Word, e: Word) Word {
    return tf(a, tf3(b, c_param, d, e));
}

/// Build the list type `[a]`.
fn lt(a: Word) Word {
    return ap(list_t, a);
}

/// Build a pair (tuple) type `(x, y)`.
fn pairType(x: Word, y: Word) Word {
    return ap2(comma_t, x, ap2(comma_t, y, void_t));
}

/// The left-hand side (head) of a definition cell `d`.
fn dlhs(heap: *Heap, d: Word) Word {
    return h(heap, d);
}

/// The type field of a definition cell `d`.
fn dtyp(heap: *Heap, d: Word) Word {
    return h(heap, t(heap, d));
}

/// The value field of a definition cell `d`.
fn dval(heap: *Heap, d: Word) Word {
    return t(heap, t(heap, d));
}

/// One-sided subsumption helper for `subsumes`.
pub fn subsu1(heap: *Heap, t1_in: Word, t2: Word, T2: Word) Word {
    const t1 = subst(heap, t1_in);
    if (t1 == t2) {
        return 1;
    }
    if (isVarType(heap, t1) and !occurs(heap, t1, T2)) {
        addsubst(heap, t1, t2);
        return 1;
    }
    if (isCompoundType(heap, t1) and isCompoundType(heap, t2)) {
        return if (subsu1(heap, h(heap, t1), h(heap, t2), T2) != 0 and subsu1(heap, t(heap, t1), t(heap, t2), T2) != 0) 1 else 0;
    }
    return 0;
}

/// Whether type `t1` is at least as general as `t2`.
pub fn subsumes(heap: *Heap, t1: Word, t2: Word) Word {
    if (t2 == wrong_t) {
        return 1;
    }
    return subsu1(heap, t1, t2, t2);
}

/// Core recursive step of `unify`.
fn unify1(heap: *Heap, t1_val: Word, t2_val: Word) c_int {
    const t1 = subst(heap, t1_val);
    const t2 = subst(heap, t2_val);
    if (t1 == t2) {
        return 1;
    }
    if (isVarType(heap, t1) and !occurs(heap, t1, t2)) {
        addsubst(heap, t1, t2);
        return 1;
    }
    if (isVarType(heap, t2) and !occurs(heap, t2, t1)) {
        addsubst(heap, t2, t1);
        return 1;
    }
    if (isCompoundType(heap, t1) and isCompoundType(heap, t2)) {
        return if (unify1(heap, h(heap, t1), h(heap, t2)) != 0 and unify1(heap, t(heap, t1), t(heap, t2)) != 0) 1 else 0;
    }
    return 0;
}

/// Unify types `t1` and `t2`, extending the substitution (1 on success).
fn unify(heap: *Heap, t1_val: Word, t2_val: Word) c_int {
    const t1 = subst(heap, t1_val);
    const t2 = subst(heap, t2_val);
    if (t1 == t2) {
        return 1;
    }
    if (isVarType(heap, t1) and !occurs(heap, t1, t2)) {
        addsubst(heap, t1, t2);
        return 1;
    }
    if (isVarType(heap, t2) and !occurs(heap, t2, t1)) {
        addsubst(heap, t2, t1);
        return 1;
    }
    if (isCompoundType(heap, t1) and isCompoundType(heap, t2) and unify1(heap, h(heap, t1), h(heap, t2)) != 0 and unify1(heap, t(heap, t1), t(heap, t2)) != 0) {
        return 1;
    }
    typeError(heap, "unify", "with", t1, t2);
    return 0;
}

/// Type-check that pattern `p` conforms to type `t_val` in environment `e`.
fn conforms(heap: *Heap, p: Word, t_val: Word, e_in: Word, ngt: Word) errors.MiraError!Word {
    var e = e_in;
    if (e == -1) {
        return -1;
    }
    if (getTag(heap, p) == .ID and !isConstructor(heap, p)) {
        return cons(cons(p, t_val), e);
    }
    if (h(heap, p) == CONST) {
        _ = unify(heap, try etype(heap, t(heap, p), e, ngt), t_val);
        return e;
    }
    if (getTag(heap, p) == .CONS) {
        const at = NTV();
        if (unify(heap, lt(at), t_val) == 0) {
            return -1;
        }
        return try conforms(heap, t(heap, p), t_val, try conforms(heap, h(heap, p), at, e, ngt), ngt);
    }
    if (getTag(heap, p) == .TCONS) {
        const at = NTV();
        const bt = NTV();
        if (unify(heap, ap2(comma_t, at, bt), t_val) == 0) {
            return -1;
        }
        return try conforms(heap, t(heap, p), bt, try conforms(heap, h(heap, p), at, e, ngt), ngt);
    }
    if (getTag(heap, p) == .PAIR) {
        const at = NTV();
        const bt = NTV();
        if (unify(heap, ap2(comma_t, at, ap2(comma_t, bt, void_t)), t_val) == 0) {
            return -1;
        }
        return try conforms(heap, t(heap, p), bt, try conforms(heap, h(heap, p), at, e, ngt), ngt);
    }
    if (getTag(heap, p) == .AP and getTag(heap, h(heap, p)) == .AP and h(heap, h(heap, p)) == word.PLUS) { // n+k pattern
        if (unify(heap, num_t, t_val) == 0) {
            return 1;
        }
        return try conforms(heap, t(heap, p), num_t, e, ngt);
    }
    {
        var p_args = NIL;
        var pt: Word = undefined;
        var cur_p = p;
        while (getTag(heap, cur_p) == .AP) {
            p_args = cons(t(heap, cur_p), p_args);
            cur_p = h(heap, cur_p);
        }
        if (!isConstructor(heap, cur_p)) {
            typeError4(heap, cur_p);
            return -1;
        }
        if (idType(heap, cur_p) == undef_t) {
            typeError5(heap, cur_p);
            return -1;
        }
        pt = instantiate(heap, if (cs().ATNAMES != 0) repT(heap, idType(heap, cur_p), cs().ATNAMES) else idType(heap, cur_p));
        while (p_args != NIL and isArrowType(heap, pt)) {
            e = try conforms(heap, h(heap, p_args), t(heap, h(heap, pt)), e, ngt);
            pt = t(heap, pt);
            p_args = t(heap, p_args);
            if (e == -1) {
                return -1;
            }
        }
        if (p_args != NIL or isArrowType(heap, pt)) {
            typeError3(heap, cur_p);
            return -1;
        }
        if (unify(heap, pt, t_val) == 0) {
            return -1;
        }
        return e;
    }
}

/// Infer the type of expression `x` in environment `env` — the core of inference.
fn etype(heap: *Heap, x: Word, env: Word, ngt: Word) errors.MiraError!Word {
    switch (getTag(heap, x)) {
        .AP => return etypeAp(heap, x, env, ngt),
        .CONS => return etypeCons(heap, x, env, ngt),
        .LEXER => return etypeLexer(heap, x, env, ngt),
        .TCONS => {
            return ap2(comma_t, try etype(heap, h(heap, x), env, ngt), try etype(heap, t(heap, x), env, ngt));
        },
        .PAIR => {
            return ap2(comma_t, try etype(heap, h(heap, x), env, ngt), ap2(comma_t, try etype(heap, t(heap, x), env, ngt), void_t));
        },
        .DOUBLE, .INT => {
            return num_t;
        },
        .ID => return etypeId(heap, x, env, ngt),
        .LAMBDA => {
            const a = NTV();
            const b = NTV();
            const d = cons(a, ngt);
            const c_local = try conforms(heap, h(heap, x), a, env, d);
            if (c_local == -1 or unify(heap, b, try etype(heap, t(heap, x), c_local, d)) == 0) {
                return NTV();
            }
            return tf(a, b);
        },
        .LET => return etypeLet(heap, x, env, ngt),
        .LETREC => return etypeLetrec(heap, x, env, ngt),
        .TRIES => return etypeTries(heap, x, env, ngt),
        .LABEL => {
            const hold = cs().lineptr;
            cs().lineptr = h(heap, x);
            const ty = try etype(heap, t(heap, x), env, ngt);
            cs().lineptr = hold;
            return ty;
        },
        .STARTREADVALS => {
            if (t(heap, x) == 0) {
                hp(heap, x).* = cs().lineptr;
                tp(heap, x).* = NTV();
                cs().showchain = cons(x, cs().showchain);
            }
            return tf(cs().ltchar, lt(t(heap, x)));
        },
        .SHOW => {
            hp(heap, x).* = cs().lineptr;
            cs().showchain = cons(x, cs().showchain);
            tp(heap, x).* = NTV();
            return tf(t(heap, x), cs().ltchar);
        },
        .SHARE => {
            if (t(heap, x) == undef_t) {
                const hold = cs().TYPERRS;
                tp(heap, x).* = subst(heap, try etype(heap, h(heap, x), env, ngt));
                if (cs().TYPERRS > hold) {
                    hp(heap, x).* = UNDEF;
                    tp(heap, x).* = wrong_t;
                }
            }
            if (t(heap, x) == wrong_t) {
                cs().TYPERRS += 1;
                return NTV();
            }
            return t(heap, x);
        },
        .CONSTRUCTOR => {
            const a = idType(heap, t(heap, x));
            return instantiate(heap, if (cs().ATNAMES != 0) repT(heap, a, cs().ATNAMES) else a);
        },
        .UNICODE => {
            return char_t;
        },
        .ATOM => return etypeAtom(heap, x),
        else => {
            _ = word.print("unexpected tag in etype ", .{});
            out(getStdout().?, @intFromEnum(getTag(heap, x)));
            _ = word.putchar('\n');
            return wrong_t;
        },
    }
}

/// [etype] for an `.AP` node: infers the function and argument types, unifies
/// the function's type with `arg -> fresh result`, and reports a mismatch
/// (with a special-cased message for grammar `%include` application errors).
fn etypeAp(heap: *Heap, x: Word, env: Word, ngt: Word) errors.MiraError!Word {
    if (h(heap, x) == word.BADCASE or h(heap, x) == word.CONFERROR) {
        return NTV();
    }
    const ft_val = try etype(heap, h(heap, x), env, ngt);
    const at = try etype(heap, t(heap, x), env, ngt);
    const rt_ty = NTV();
    if (unify1(heap, ft_val, ap2(arrow_t, at, rt_ty)) == 0) {
        const ft = subst(heap, ft_val);
        if (isArrowType(heap, ft)) {
            if (getTag(heap, h(heap, x)) == .AP and h(heap, h(heap, x)) == word.G_ERROR) {
                typeError8(heap, at, t(heap, h(heap, ft)));
            } else {
                typeError(heap, "unify", "with", at, t(heap, h(heap, ft)));
            }
        } else {
            typeError(heap, "apply", "to", ft, at);
        }
        return NTV();
    }
    return rt_ty;
}

/// [etype] for a `.CONS` node: finds the chain's tail, unifies its type with
/// the list type, then unifies every head's type with the list's element
/// type, reporting the first mismatch found (checked tail-first, matching the
/// original C reducer's error-reporting order).
fn etypeCons(heap: *Heap, x: Word, env: Word, ngt: Word) errors.MiraError!Word {
    const elem_type = NTV();
    const list_type = lt(elem_type);

    // 1. Find the tail of the CONS chain
    var cur = x;
    while (getTag(heap, cur) == .CONS) {
        cur = t(heap, cur);
    }
    const tail_expr = cur;

    // 2. Type check the tail
    const tail_type = try etype(heap, tail_expr, env, ngt);
    if (unify1(heap, list_type, tail_type) == 0) {
        // Find the last CONS node to report the error on
        var last_cons = x;
        while (t(heap, last_cons) != tail_expr) {
            last_cons = t(heap, last_cons);
        }
        const ht = try etype(heap, h(heap, last_cons), env, ngt);
        typeError(heap, "cons", "to", ht, tail_type);
        return NTV();
    }

    // 3. Type check each head in the chain
    cur = x;
    while (getTag(heap, cur) == .CONS) {
        const ht = try etype(heap, h(heap, cur), env, ngt);
        if (unify1(heap, ht, elem_type) == 0) {
            const rt_ty = try etype(heap, t(heap, cur), env, ngt);
            typeError(heap, "cons", "to", ht, rt_ty);
            return NTV();
        }
        cur = t(heap, cur);
    }
    return list_type;
}

/// [etype] for a `.LEXER` node: type-checks each alternative's grammar body
/// against the first alternative's type, restoring `cs.lineptr` (used for
/// error-location reporting) around each check.
fn etypeLexer(heap: *Heap, x: Word, env: Word, ngt: Word) errors.MiraError!Word {
    const hold = cs().lineptr;
    cs().lineptr = h(heap, t(heap, t(heap, h(heap, x))));
    tp(heap, t(heap, h(heap, x))).* = t(heap, t(heap, t(heap, h(heap, x))));
    const a = try etype(heap, t(heap, t(heap, h(heap, x))), env, ngt);
    var cur_x = x;
    while (true) {
        cur_x = t(heap, cur_x);
        if (cur_x == NIL) break;
        cs().lineptr = h(heap, t(heap, t(heap, h(heap, cur_x))));
        tp(heap, t(heap, h(heap, cur_x))).* = t(heap, t(heap, t(heap, h(heap, cur_x))));
        const b = try etype(heap, t(heap, t(heap, h(heap, cur_x))), env, ngt);
        if (unify1(heap, a, b) == 0) {
            typeError7(heap, a, b);
            cs().lineptr = hold;
            return NTV();
        }
    }
    cs().lineptr = hold;
    return tf(cs().ltchar, lt(a));
}

/// [etype] for a `.ID` node: looks it up in the local type environment first
/// (`env`, generalizing on hit), then the global identifier table, reporting
/// undefined/wrongly-typed names.
fn etypeId(heap: *Heap, x: Word, env: Word, ngt: Word) errors.MiraError!Word {
    var cur_env = env;
    while (cur_env != NIL) {
        if (h(heap, h(heap, cur_env)) == x) {
            tp(heap, h(heap, cur_env)).* = subst(heap, t(heap, h(heap, cur_env)));
            return linst(heap, t(heap, h(heap, cur_env)), ngt);
        }
        cur_env = t(heap, cur_env);
    }
    const a = idType(heap, x);
    if (isBoundType(heap, a)) {
        return t(heap, a);
    }
    if (a == type_t) {
        typeError1(heap, x);
    }
    if (a == undef_t) {
        if (core_state.s().commandmode != 0) {
            typeError2(heap, x);
        } else if (member(heap, cs().ND, x) == 0) {
            if (cs().lineptr != 0) {
                sayhere(heap, cs().lineptr, 0);
            } else if (getTag(heap, cs().current_id) == .DATAPAIR) {
                locateInc(heap);
            }
            _ = word.print("undefined name \"{s}\"\n", .{getId(heap, x)});
            cs().ND = add1(heap, x, cs().ND);
        }
        return NTV();
    }
    if (a == wrong_t) {
        return NTV();
    }
    return instantiate(heap, if (cs().ATNAMES != 0) repT(heap, a, cs().ATNAMES) else a);
}

/// [etype] for a `.LET` node: infers the bound expression's type against the
/// pattern, then the body's type in the extended environment.
fn etypeLet(heap: *Heap, x: Word, env: Word, ngt: Word) errors.MiraError!Word {
    var e: Word = undefined;
    const def = h(heap, x);
    const a = NTV();
    e = try conforms(heap, dlhs(heap, def), a, env, cons(a, ngt));
    cs().current_id = cons(dlhs(heap, def), cs().current_id);
    const c_local = cs().lineptr;
    cs().lineptr = dval(heap, def);
    const unified = unify(heap, a, try etype(heap, dval(heap, def), env, ngt));
    cs().lineptr = c_local;
    cs().current_id = t(heap, cs().current_id);
    if (e == -1 or unified == 0) {
        return NTV();
    }
    return try etype(heap, t(heap, x), e, ngt);
}

/// [etype] for a `.LETREC` node: assigns each definition a fresh type
/// variable (or its declared type, if any), extends the environment with all
/// of them (so mutual recursion type-checks), then checks each definition's
/// body against its assigned type -- explicitly-typed definitions are
/// checked for subsumption rather than plain unification.
fn etypeLetrec(heap: *Heap, x: Word, env: Word, ngt: Word) errors.MiraError!Word {
    var e = env;
    var s = NIL;
    var a = NIL;
    var c_local = ngt;
    var cur_d = h(heap, x);
    while (cur_d != NIL) {
        if (dtyp(heap, h(heap, cur_d)) == undef_t) {
            a = cons(h(heap, cur_d), a);
            const b = NTV();
            hp(heap, t(heap, h(heap, cur_d))).* = b;
            c_local = cons(b, c_local);
            e = try conforms(heap, dlhs(heap, h(heap, cur_d)), b, e, c_local);
        } else {
            hp(heap, t(heap, h(heap, cur_d))).* = try metaTcheck(heap, dtyp(heap, h(heap, cur_d)));
            s = cons(h(heap, cur_d), s);
            e = cons(cons(dlhs(heap, h(heap, cur_d)), dtyp(heap, h(heap, cur_d))), e);
        }
        cur_d = t(heap, cur_d);
    }
    if (e == -1) {
        return NTV();
    }
    var success = true;
    var cur_a = a;
    while (cur_a != NIL) {
        cs().current_id = cons(dlhs(heap, h(heap, cur_a)), cs().current_id);
        const hold = cs().lineptr;
        cs().lineptr = dval(heap, h(heap, cur_a));
        if (unify(heap, dtyp(heap, h(heap, cur_a)), try etype(heap, dval(heap, h(heap, cur_a)), e, c_local)) == 0) {
            success = false;
        }
        cs().lineptr = hold;
        cs().current_id = t(heap, cs().current_id);
        cur_a = t(heap, cur_a);
    }
    var cur_s = s;
    while (cur_s != NIL) {
        cs().current_id = cons(dlhs(heap, h(heap, cur_s)), cs().current_id);
        const hold = cs().lineptr;
        cs().lineptr = dval(heap, h(heap, cur_s));
        const ety = try etype(heap, dval(heap, h(heap, cur_s)), e, ngt);
        if (subsumes(heap, ety, linst(heap, dtyp(heap, h(heap, cur_s)), ngt)) == 0) {
            success = false;
            typeError6(heap, dlhs(heap, h(heap, cur_s)), dtyp(heap, h(heap, cur_s)), ety);
        }
        cs().lineptr = hold;
        cs().current_id = t(heap, cs().current_id);
        cur_s = t(heap, cur_s);
    }
    if (!success) {
        return NTV();
    }
    return try etype(heap, t(heap, x), e, ngt);
}

/// [etype] for a `.TRIES` node (a `%include`/grammar alternative chain):
/// unifies every alternative's type with the first, reporting a mismatch at
/// the first alternative that disagrees.
fn etypeTries(heap: *Heap, x: Word, env: Word, ngt: Word) errors.MiraError!Word {
    const hold = cs().lineptr;
    const a = NTV();
    var cur_x = t(heap, x);
    while (cur_x != NIL) {
        cs().lineptr = h(heap, h(heap, cur_x));
        if (unify(heap, a, try etype(heap, t(heap, h(heap, cur_x)), env, ngt)) == 0) {
            break;
        }
        cur_x = t(heap, cur_x);
    }
    cs().lineptr = hold;
    if (cur_x != NIL) {
        return NTV();
    }
    return a;
}

/// [etype] for an `.ATOM` node: single-byte atoms are characters; otherwise
/// this is one of the built-in SK-family combinators or primitive operators,
/// each with a fixed (possibly polymorphic, via fresh `NTV()` type
/// variables) type -- effectively a static type table for the whole
/// combinator/operator vocabulary.
fn etypeAtom(heap: *Heap, x: Word) Word {
    if (word.fitsInByte(x)) {
        return char_t;
    }
    switch (x) {
        word.S => {
            const a = NTV();
            const b = NTV();
            const c_local = NTV();
            const d = tf3(tf2(a, b, c_local), tf(a, b), a, c_local);
            return d;
        },
        word.K => {
            const a = NTV();
            const b = NTV();
            return tf2(a, b, a);
        },
        word.Y => {
            const a = NTV();
            return tf(tf(a, a), a);
        },
        word.C => {
            const a = NTV();
            const b = NTV();
            const c_local = NTV();
            return tf3(tf2(a, b, c_local), b, a, c_local);
        },
        word.B => {
            const a = NTV();
            const b = NTV();
            const c_local = NTV();
            return tf3(tf(a, b), tf(c_local, a), c_local, b);
        },
        word.FORCE, word.G_UNIT, word.G_RULE, word.I => {
            const a = NTV();
            return tf(a, a);
        },
        word.G_ZERO => {
            return NTV();
        },
        word.HD => {
            const a = NTV();
            return tf(lt(a), a);
        },
        word.TL => {
            const a = lt(NTV());
            return tf(a, a);
        },
        word.BODY => {
            const a = NTV();
            const b = NTV();
            return tf(ap(a, b), a);
        },
        word.LAST => {
            const a = NTV();
            const b = NTV();
            return tf(ap(a, b), b);
        },
        word.S_p => {
            const a = NTV();
            const b = NTV();
            const c_local = lt(b);
            return tf3(tf(a, b), tf(a, c_local), a, c_local);
        },
        word.U, word.U_ => {
            const a = NTV();
            const b = NTV();
            const c_local = lt(a);
            return tf2(tf2(a, c_local, b), c_local, b);
        },
        word.Uf => {
            const a = NTV();
            const b = NTV();
            const c_local = NTV();
            return tf2(tf2(tf(a, b), a, c_local), b, c_local);
        },
        word.COND => {
            const a = NTV();
            return tf3(bool_t, a, a, a);
        },
        word.EQ, word.GR, word.GRE, word.NEQ => {
            const a = NTV();
            return tf2(a, a, bool_t);
        },
        word.NEG => {
            return cs().tfnum;
        },
        word.AND, word.OR => {
            return cs().tfbool2;
        },
        word.NOT => {
            return cs().tfbool;
        },
        word.MERGE, word.APPEND => {
            const a = lt(NTV());
            return tf2(a, a, a);
        },
        word.STEP => {
            return cs().tstep;
        },
        word.STEPUNTIL => {
            return cs().tstepuntil;
        },
        word.MAP => {
            const a = NTV();
            const b = NTV();
            return tf2(tf(a, b), lt(a), lt(b));
        },
        word.FLATMAP => {
            const a = NTV();
            const b = lt(NTV());
            return tf2(tf(a, b), lt(a), b);
        },
        word.FILTER => {
            const a = NTV();
            const b = lt(a);
            return tf2(tf(a, bool_t), b, b);
        },
        word.ZIP => {
            const a = NTV();
            const b = NTV();
            return tf2(lt(a), lt(b), lt(pairType(a, b)));
        },
        word.FOLDL => {
            const a = NTV();
            const b = NTV();
            return tf3(tf2(a, b, a), a, lt(b), a);
        },
        word.FOLDL1 => {
            const a = NTV();
            return tf2(tf2(a, a, a), lt(a), a);
        },
        word.LIST_LAST => {
            const a = NTV();
            return tf(lt(a), a);
        },
        word.FOLDR => {
            const a = NTV();
            const b = NTV();
            return tf3(tf2(a, b, b), b, lt(a), b);
        },
        word.MATCHINT, word.MATCH => {
            const a = NTV();
            const b = NTV();
            return tf3(a, b, a, b);
        },
        word.TRY => {
            const a = NTV();
            return tf2(a, a, a);
        },
        word.DROP, word.TAKE => {
            const a = lt(NTV());
            return tf2(num_t, a, a);
        },
        word.SUBSCRIPT => {
            const a = NTV();
            return tf2(num_t, lt(a), a);
        },
        word.P => {
            const a = NTV();
            const b = lt(a);
            return tf2(a, b, b);
        },
        word.B_p => {
            const a = NTV();
            const b = NTV();
            const c_local = lt(a);
            return tf3(a, tf(b, c_local), b, c_local);
        },
        word.C_p => {
            const a = NTV();
            const b = NTV();
            const c_local = lt(b);
            return tf3(tf(a, b), c_local, a, c_local);
        },
        word.S1 => {
            const a = NTV();
            const b = NTV();
            const c_local = NTV();
            const d = NTV();
            return tf4(tf2(a, b, c_local), tf(d, a), tf(d, b), d, c_local);
        },
        word.B1 => {
            const a = NTV();
            const b = NTV();
            const c_local = NTV();
            const d = NTV();
            return tf4(tf(a, b), tf(c_local, a), tf(d, c_local), d, b);
        },
        word.C1 => {
            const a = NTV();
            const b = NTV();
            const c_local = NTV();
            const d = NTV();
            return tf4(tf2(a, b, c_local), tf(d, a), b, d, c_local);
        },
        word.SEQ => {
            const a = NTV();
            const b = NTV();
            return tf2(a, b, b);
        },
        word.ITERATE1, word.ITERATE => {
            const a = NTV();
            return tf2(tf(a, a), a, lt(a));
        },
        word.EXEC => {
            if (cs().exec_t == 0) {
                const a = ap2(comma_t, cs().ltchar, ap2(comma_t, num_t, void_t));
                cs().exec_t = tf(cs().ltchar, ap2(comma_t, cs().ltchar, a));
            }
            return cs().exec_t;
        },
        word.READBIN, word.READ => {
            if (cs().read_t == 0) {
                cs().read_t = tf(char_t, cs().ltchar);
            }
            return cs().read_t;
        },
        word.FILESTAT => {
            return genlstatType();
        },
        word.FILEMODE, word.GETENV, word.NB_STARTREAD, word.STARTREADBIN, word.STARTREAD => {
            return cs().tfstrstr;
        },
        word.GETARGS => {
            return tf(char_t, lt(cs().ltchar));
        },
        word.SHOWHEX, word.SHOWOCT, word.SHOWNUM => {
            return tf(num_t, cs().ltchar);
        },
        word.SHOWFLOAT, word.SHOWSCALED => {
            return tf2(num_t, num_t, cs().ltchar);
        },
        word.NUMVAL => {
            return tf(cs().ltchar, num_t);
        },
        word.INTEGER => {
            return tf(num_t, bool_t);
        },
        word.CODE => {
            return tf(char_t, num_t);
        },
        word.DECODE => {
            return tf(num_t, char_t);
        },
        word.LENGTH => {
            return tf(lt(NTV()), num_t);
        },
        word.ENTIER_FN, word.ARCTAN_FN, word.EXP_FN, word.SIN_FN, word.COS_FN, word.SQRT_FN, word.LOG_FN, word.LOG10_FN => {
            return cs().tfnumnum;
        },
        word.MINUS, word.PLUS, word.TIMES, word.INTDIV, word.FDIV, word.MOD, word.POWER => {
            return cs().tfnum2;
        },
        word.True, word.False => {
            return bool_t;
        },
        NIL => {
            const a = lt(NTV());
            return a;
        },
        word.NILS => {
            return cs().ltchar;
        },
        word.MKSTRICT => {
            const a = NTV();
            return tf(char_t, tf(a, a));
        },
        word.G_ALT => {
            const a = NTV();
            return tf2(a, a, a);
        },
        word.G_ERROR => {
            const a = NTV();
            return tf2(a, tf(lt(cs().bnf_t), a), a);
        },
        word.G_OPT, word.G_STAR => {
            const a = NTV();
            return tf(a, lt(a));
        },
        word.G_FBSTAR => {
            const a = NTV();
            const b = tf(a, a);
            return tf(b, b);
        },
        word.G_SYMB => {
            return cs().tfstrstr;
        },
        word.G_ANY => {
            return cs().ltchar;
        },
        word.G_SUCHTHAT => {
            return tf(tf(cs().ltchar, bool_t), cs().ltchar);
        },
        word.G_END => {
            return lt(cs().bnf_t);
        },
        word.G_STATE => {
            return t(heap, h(heap, t(heap, cs().bnf_t)));
        },
        word.G_SEQ => {
            const a = NTV();
            const b = NTV();
            return tf2(a, tf(a, b), b);
        },
        word.G_CLOSE => {
            const a = NTV();
            if (rt.rs().col_fn != 0) {
                if (rt.rs().col_fn == -1) {
                    cs().TYPERRS += 1;
                } else {
                    checkcolfn(heap);
                }
            }
            return tf3(cs().ltchar, a, lt(cs().bnf_t), a);
        },
        word.OFFSIDE => {
            return cs().ltchar;
        },
        word.FAIL, word.CONFERROR, word.BADCASE, UNDEF => {
            return NTV();
        },
        word.ERROR => {
            return tf(cs().ltchar, NTV());
        },
        else => {
            _ = word.print("do not know type of ", .{});
            out(getStdout().?, x);
            _ = word.putchar('\n');
            return wrong_t;
        },
    }
}

/// Type-check the grammar's collector function (`col_fn`).
pub fn checkcolfn(heap: *Heap) void {
    const t_val = idType(heap, rt.rs().col_fn);
    const f = tf(t(heap, h(heap, t(heap, cs().bnf_t))), num_t);
    if (t_val == undef_t or t_val == wrong_t or subsumes(heap, instantiate(heap, t_val), f) != 0) {
        rt.rs().col_fn = 0;
        return;
    }
    _ = word.print("`bnftokenindentation' has wrong type for use in offside rule\n", .{});
    _ = word.print("type required :: ", .{});
    outType(heap, f);
    _ = word.putchar('\n');
    _ = word.print("  actual type :: ", .{});
    outType(heap, t_val);
    _ = word.putchar('\n');
    sayhere(heap, getspecloc(heap, rt.rs().col_fn), 1);
    cs().TYPERRS += 1;
    rt.rs().col_fn = -1;
}

/// Derive the BNF token type from the grammar's `bnftokenstate`.
pub fn genbnft(heap: *Heap) void {
    const bnftokenstate = findid(heap, "bnftokenstate");
    if (bnftokenstate != NIL and idType(heap, bnftokenstate) == type_t) {
        if (tArity(heap, bnftokenstate) == 0) {
            cs().bnf_t = if (tClass(heap, bnftokenstate) == synonym_t) tInfo(heap, bnftokenstate) else bnftokenstate;
        } else {
            _ = word.print("warning - bnftokenstate has arity>0 (ignored by parser)\n", .{});
            cs().bnf_t = void_t;
        }
    } else {
        cs().bnf_t = void_t;
    }
    cs().bnf_t = ap2(comma_t, cs().ltchar, ap2(comma_t, cs().bnf_t, void_t));
}

/// Type-check `x`, returning its inferred type.
pub fn checktype(heap: *Heap, x: Word) Word {
    cs.TYPERRS = 0;
    _ = etype(heap, x, NIL, NIL) catch return 0;
    resetSubst(heap);
    return if (cs.TYPERRS == 0) 1 else 0;
}

/// The inferred type of expression `x`.
pub fn typeOf(heap: *Heap, x: Word) Word {
    cs().TYPERRS = 0;
    var t_val = redtvars(heap, subst(heap, etype(heap, x, NIL, NIL) catch return wrong_t));
    fixshows(heap);
    if (cs().TYPERRS > 0) {
        t_val = wrong_t;
    }
    return t_val;
}

/// Run type inference over definition `x`.
fn inferType(heap: *Heap, x: Word) void {
    if (getTag(heap, x) == .ID) {
        var t_val: Word = undefined;
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
            cs().ND = add1(heap, x, cs().ND);
        } else if (idType(heap, x) == undef_t) {
            tp(heap, h(heap, x)).* = redtvars(heap, t_val);
        }
        resetSubst(heap);
    } else {
        var x1 = x;
        var oldte: Word = undefined;
        var ngt = NIL;
        while (x1 != NIL) {
            ngt = cons(NTV(), ngt);
            tp(heap, h(heap, h(heap, x1))).* = ap(bind_t, h(heap, ngt));
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
                cs().ND = add1(heap, h(heap, x1), cs().ND);
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
pub fn tsetup() void {
    cs().tfnum = tf(num_t, num_t);
    cs().tfbool = tf(bool_t, bool_t);
    cs().tfnum2 = tf(num_t, cs().tfnum);
    cs().tfbool2 = tf(bool_t, cs().tfbool);
    cs().ltchar = lt(char_t);
    cs().tfstrstr = tf(cs().ltchar, cs().ltchar);
    cs().tfnumnum = tf(num_t, num_t);
    cs().tstep = tf2(num_t, num_t, lt(num_t));
    cs().tstepuntil = tf(num_t, cs().tstep);
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
        if (rs.rfl != NIL) {
            readoption(heap, comp, rs);
        }
        var s = reverse(t(heap, h(heap, heap.files)));
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
    if (rs.freeids != NIL) {
        redtfr(heap, rs.freeids);
    }
    genshfns(heap);
    if (rs.fnts != NIL) {
        genbnft(heap);
    }
    comp.R = msc(heap, comp.R);
    var s = tsort(heap, comp.R);
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
        printlist(heap, "SPECIFIED BUT NOT DEFINED: ", alfasort(comp.SBND));
        comp.SBND = NIL;
    }
    fixshows(heap);
    comp.lastloc = 0;
    if (options.is_strict or @import("builtin").mode == .Debug) {
        heap.validate();
        @import("trans.zig").validate(heap);
        rs.validate();
    }
}
