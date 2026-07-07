//! unify.zig (split from compiler/types.zig, Phase 4 step 3,
//! docs/ZIG_NATIVE_PLAN.md) — the substitution/unification engine:
//! `lookup`/`addsubst`/`subst` maintain a mutable substitution over type
//! variables (with the `occurs` check), and `instantiate`/`linst`/
//! `redtvars` handle generalisation and freshening of polymorphic
//! variables. `infer.zig`'s `etype`/`conforms`/`metaTcheck` drive this;
//! `isCompoundType`/`isVarType` are `pub` in `infer.zig` and referenced
//! from here rather than duplicated, since they're used identically by
//! both files' otherwise-unrelated logic.

const std = @import("std");
const word = @import("../graph/word.zig");
const heap_mod = @import("../runtime/heap.zig");
const Heap = heap_mod.Heap;
const compiler_state = @import("../compiler/compiler_state.zig");
const cs = compiler_state.cs;
const infer = @import("infer.zig");

const Word = word.Word;
const NIL = word.NIL;

const make = heap_mod.make;
const isCompoundType = infer.isCompoundType;
const isVarType = infer.isVarType;

/// The node tag of cell `x`.
inline fn getTag(heap: *Heap, x: Word) word.NodeTag {
    return heap.getTag(x);
}

/// Head (`hd`) of cell `x`.
fn h(heap: *Heap, x: Word) Word {
    return heap.h(x);
}

/// Pointer to the tail field of cell `x`.
fn tp(heap: *Heap, x: Word) *Word {
    return heap.tp(x);
}

/// Tail (`tl`) of cell `x`.
fn t(heap: *Heap, x: Word) Word {
    return heap.t(x);
}

/// Allocate a `CONS` cell `(x . y)`.
fn cons(x: Word, y: Word) Word {
    return make(.CONS, x, y);
}

/// Make a type-variable node with index `i`.
fn mktvar(i: Word) Word {
    return make(.TVAR, 0, i);
}

/// The index of type variable `x`.
pub fn gettvar(heap: *Heap, x: Word) Word {
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
pub fn NTV() Word {
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
pub fn ult(heap: *Heap, tv: Word) Word {
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

const type_errors = @import("type_errors.zig");
const typeError = type_errors.typeError;
const wrong_t = word.wrong_t;

/// Whether `t1` can be made to match `t2` (one-directional; extends the
/// substitution, unlike `unify`). `T2` is the top-level type `t2` came
/// from, used for the `occurs` check against the whole term.
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
pub fn unify1(heap: *Heap, t1_val: Word, t2_val: Word) c_int {
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
pub fn unify(heap: *Heap, t1_val: Word, t2_val: Word) c_int {
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
