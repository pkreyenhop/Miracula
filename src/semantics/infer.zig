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
    return make(heap_mod.heap(), .CONS, x, y);
}

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

/// The type field of id `x`.
pub fn idType(heap: *Heap, x: Word) Word {
    return t(heap, h(heap, x));
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
pub fn isCompoundType(heap: *Heap, type_node: Word) bool {
    return getTag(heap, type_node) == .AP;
}
/// Whether a type node is a type variable.
pub fn isVarType(heap: *Heap, type_node: Word) bool {
    return getTag(heap, type_node) == .TVAR;
}

/// The arity stored in a type node.
pub fn tArity(heap: *Heap, x: Word) Word {
    return h(heap, h(heap, t(heap, x)));
}
/// The type class of a type node.
fn tClass(heap: *Heap, x: Word) Word {
    return h(heap, t(heap, t(heap, x)));
}
/// The info field of a type node.
pub fn tInfo(heap: *Heap, x: Word) Word {
    return t(heap, t(heap, t(heap, x)));
}
/// The `show` function recorded for a type node.
/// The value field of id `x`.
fn idVal(heap: *Heap, x: Word) Word {
    return t(heap, x);
}
/// The definition-site field of id `x`.
pub fn idWho(heap: *Heap, x: Word) Word {
    return t(heap, h(heap, h(heap, x)));
}

/// The interned name text of id `x`.
pub fn getId(heap: *Heap, x: Word) [*:0]const u8 {
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

/// Allocate an application cell `(x y)`.
fn ap(x: Word, y: Word) Word {
    return make(heap_mod.heap(), .AP, x, y);
}

/// The value (tail) of a private-name node.
fn pnVal(heap: *Heap, x: Word) Word {
    return t(heap, x);
}

const comma_t: Word = 5;
const arrow_t: Word = 6;
const void_t: Word = 7;
const wrong_t: Word = 8;

/// The standard-output `Stream` handle.
pub fn getStdout() ?*word.Stream {
    const T = @TypeOf(os.stdout);
    if (comptime @typeInfo(T) == .@"fn") {
        return os.stdout();
    } else if (comptime @typeInfo(T) == .pointer and @typeInfo(@typeInfo(T).pointer.child) == .@"fn") {
        return os.stdout();
    } else {
        return os.stdout;
    }
}

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

/// Whether `x` names a data constructor.
fn isConstructor(heap: *Heap, x: Word) bool {
    return getTag(heap, x) == .ID and isconstrname(getId(heap, x));
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

/// Print one debug element.
pub fn printelement(heap: *Heap, x: Word) void {
    if (getTag(heap, x) != .CONS) {
        out(heap, getStdout().?, x);
        return;
    }
    _ = word.print("(", .{});
    var cur = x;
    while (cur != NIL) {
        out(heap, getStdout().?, h(heap, cur));
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

const subsu1 = unify_mod.subsu1;
const subsumes = unify_mod.subsumes;
const unify = unify_mod.unify;

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
            out(heap, getStdout().?, @intFromEnum(getTag(heap, x)));
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
            if (script_store.store().col_fn != 0) {
                if (script_store.store().col_fn == -1) {
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
            out(heap, getStdout().?, x);
            _ = word.putchar('\n');
            return wrong_t;
        },
    }
}

/// Type-check the grammar's collector function (`col_fn`).
pub fn checkcolfn(heap: *Heap) void {
    const t_val = idType(heap, script_store.store().col_fn);
    const f = tf(t(heap, h(heap, t(heap, cs().bnf_t))), num_t);
    if (t_val == undef_t or t_val == wrong_t or subsumes(heap, instantiate(heap, t_val), f) != 0) {
        script_store.store().col_fn = 0;
        return;
    }
    _ = word.print("`bnftokenindentation' has wrong type for use in offside rule\n", .{});
    _ = word.print("type required :: ", .{});
    outType(heap, f);
    _ = word.putchar('\n');
    _ = word.print("  actual type :: ", .{});
    outType(heap, t_val);
    _ = word.putchar('\n');
    sayhere(heap, getspecloc(heap, script_store.store().col_fn), 1);
    cs().TYPERRS += 1;
    script_store.store().col_fn = -1;
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
        if (script_store.store().rfl != NIL) {
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
    if (script_store.store().freeids != NIL) {
        redtfr(heap, script_store.store().freeids);
    }
    genshfns(heap);
    if (script_store.store().fnts != NIL) {
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
        printlist(heap, "SPECIFIED BUT NOT DEFINED: ", alfasort(heap, comp.SBND));
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
