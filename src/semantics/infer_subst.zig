//! semantics/infer_subst.zig — type substitution/repointing machinery (docs/GoReady.md P4).

const word = @import("../graph/word.zig");
const errors = @import("../runtime/errors.zig");
const dump = @import("../compiler/dump.zig");
const strtab = @import("../graph/strtab.zig");
const compiler_state = @import("../compiler/compiler_state.zig");
const heap_mod = @import("../graph/heap.zig");
const Heap = heap_mod.Heap;
const print_mod = @import("../graph/print.zig");
const cs = compiler_state.cs;
const Word = word.Word;
const Value = @import("../graph/value.zig").Value;
const CMBASE = word.CMBASE;
const NIL = word.NIL;
const getspecloc = trans_mod.getspecloc;
const out = print_mod.outTerm;
const trans_mod = @import("../semantics/lower.zig");
const depend = @import("depend.zig");
const remove1 = depend.remove1;
const add1 = depend.add1;
const member = depend.member;
const deps = depend.deps;
pub const type_t: Word = 10;
const undef_t: Word = 0;
const bool_t: Word = 1;
const num_t: Word = 2;
const char_t: Word = 3;
const list_t: Word = 4;
const synonym_t = word.synonym_t;
const abstract_t = word.abstract_t;
const UNDEF: Word = CMBASE + 140;
const unify_mod = @import("unify.zig");
const apSubst = unify_mod.apSubst;
const redtvars = unify_mod.redtvars;
const occurs = unify_mod.occurs;
const clearSubst = unify_mod.clearSubst;
const hashsize: usize = 512;
const type_errors = @import("type_errors.zig");
const sayhere = type_errors.sayhere;
const outType = type_errors.outType;
const algebraic_t = word.algebraic_t;
const FREE = word.FREE;
const bind_t: Word = 9;
const unify = unify_mod.unify;

const infer_prims = @import("infer_prims.zig");
const getTag = infer_prims.getTag;
const h = infer_prims.h;
const hp = infer_prims.hp;
const t = infer_prims.t;
const tp = infer_prims.tp;
const cons = infer_prims.cons;
const idType = infer_prims.idType;
const isCompoundType = infer_prims.isCompoundType;
const isVarType = infer_prims.isVarType;
const tArity = infer_prims.tArity;
const tClass = infer_prims.tClass;
const tInfo = infer_prims.tInfo;
const idVal = infer_prims.idVal;
const idWho = infer_prims.idWho;
const getId = infer_prims.getId;
const ap = infer_prims.ap;
const pnVal = infer_prims.pnVal;
const tf = infer_prims.tf;
const pairType = infer_prims.pairType;
const getStdout = infer_prims.getStdout;

/// Rewrite a type's outer constructor to `list_t` in place (for structural compare).
pub fn sterilisRaw(heap: *Heap, t_val: Word) void {
    if (getTag(heap, t_val) == .AP) {
        hp(heap, t_val).* = list_t;
        tp(heap, t_val).* = num_t;
    }
}

/// `Value`-typed wrapper for `sterilisRaw` (§ GoReady Phase 5 step 4g).
///
/// Tests: sterilise: rewrites an AP-tagged type's hd/tl to (list_t . num_t)
pub fn sterilise(heap: *Heap, t_val: Value) void {
    sterilisRaw(heap, t_val.toRaw());
}

/// Validate the well-formedness (arity) of type expression `t_val`.
pub fn metaTcheck(heap: *Heap, t_val: Word) errors.MiraError!Word {
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
                sterilisRaw(heap, t_val);
            }
            return t_val;
        } else if (idType(heap, tn) == undef_t and idVal(heap, tn) == UNDEF) {
            cs().TYPERRS += 1;
            if (member(heap, Value.fromRaw(cs().NT), Value.fromRaw(tn)) == 0) {
                if (getTag(heap, cs().current_id) == .DATAPAIR) {
                    locateInc(heap);
                }
                _ = word.print("undeclared typename \"{s}\" ", .{getId(heap, tn)});
                if (getTag(heap, cs().current_id) == .DATAPAIR) {
                    _ = word.print("in binding for {s}\n", .{strtab.strOf(strtab.table(), h(heap, cs().current_id))});
                } else {
                    sayhere(heap, getspecloc(heap, cs().current_id), 1);
                }
                cs().NT = add1(heap, Value.fromRaw(tn), Value.fromRaw(cs().NT)).toRaw();
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
            sterilisRaw(heap, t_val);
            return t_val;
        }
    }

    if (tClass(heap, tn) != synonym_t) {
        return t_val;
    }
    if (member(heap, Value.fromRaw(cs().meta_pending), Value.fromRaw(tn)) != 0) {
        cs().TYPERRS += 1; // report cycle
        if (getTag(heap, cs().current_id) == .DATAPAIR) {
            locateInc(heap);
        }
        const suffix: [*:0]const u8 = if (cs().meta_pending == NIL) "" else "s";
        _ = word.print("error: cycle in type \"==\" definition{s} ", .{suffix});
        printelementRaw(heap, cs().meta_pending);
        _ = word.print("\n", .{});
        if (getTag(heap, cs().current_id) != .DATAPAIR) {
            sayhere(heap, idWho(heap, tn), 1);
        }
        return error.TypeCheckAbort;
    }
    cs().meta_pending = cons(heap, tn, cs().meta_pending);
    tn = NIL;
    var cur_t = t_val;
    while (isCompoundType(heap, cur_t)) {
        tn = cons(heap, t(heap, cur_t), tn);
        cur_t = h(heap, cur_t);
    }
    const res = try metaTcheck(heap, apSubst(heap, tInfo(heap, cur_t), tn));
    cs().meta_pending = t(heap, cs().meta_pending);
    return res;
}

/// Compute and record the dependencies of `n`.
pub fn compDeps(heap: *Heap, n: Word) errors.MiraError!void {
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
                cs().SBND = add1(heap, Value.fromRaw(n), Value.fromRaw(cs().SBND)).toRaw();
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
        cs().SBND = add1(heap, Value.fromRaw(n), Value.fromRaw(cs().SBND)).toRaw();
        return;
    }
    r = deps(heap, Value.fromRaw(t(heap, n))).toRaw();
    while (r != NIL) {
        if (t(heap, h(heap, r)) != UNDEF and idType(heap, h(heap, r)) == undef_t) {
            rhs = add1(heap, Value.fromRaw(h(heap, r)), Value.fromRaw(rhs)).toRaw();
        }
        r = t(heap, r);
    }
    cs().R = cons(heap, cons(heap, n, rhs), cs().R);
}

/// Print one debug element.
pub fn printelementRaw(heap: *Heap, x: Word) void {
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

/// `Value`-typed wrapper for `printelementRaw` (§ GoReady Phase 5 step 4g).
///
/// Tests: printelement: prints a non-cons value bare, a cons-list parenthesised
pub fn printelement(heap: *Heap, x: Value) void {
    printelementRaw(heap, x.toRaw());
}

/// Print a titled list (debug).
pub fn printlist(heap: *Heap, title: [*:0]const u8, l_in: Word) void {
    var l = l_in;
    _ = word.print("{s}", .{title});
    while (l != NIL) {
        printelementRaw(heap, h(heap, l));
        l = t(heap, l);
        if (l != NIL) {
            _ = word.print(",", .{});
        }
    }
    _ = word.print(";\n", .{});
}

/// Clear the substitution table.
pub fn resetSubst(heap: *Heap) void {
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
///
/// Returns a 0/1 flag, not a graph value (matches `depend.zig`'s
/// `member`/`remove1` precedent) — only `atnames` is `Value`-typed.
pub fn cyclicAbstrRaw(heap: *Heap, atnames: Word) Word {
    var x = atnames;
    var y = NIL;
    while (x != NIL) {
        y = ap(heap, y, tInfo(heap, h(heap, x)));
        x = t(heap, x);
    }
    x = atnames;
    while (x != NIL) {
        if (occurs(heap, h(heap, x), y)) {
            _ = word.print("illegal type abstraction: cycle in \"==\" binding{s} ", .{if (t(heap, atnames) == NIL) @as([*:0]const u8, "") else @as([*:0]const u8, "s")});
            printelementRaw(heap, atnames);
            _ = word.putchar('\n');
            sayhere(heap, idWho(heap, h(heap, x)), 1);
            cs().TYPERRS += 1;
            return 1;
        }
        x = t(heap, x);
    }
    return 0;
}

/// `Value`-typed wrapper for `cyclicAbstrRaw` (§ GoReady Phase 5 step 4g).
///
/// Tests: cyclicAbstr: an empty atnames list reports no cycle
pub fn cyclicAbstr(heap: *Heap, atnames: Value) Word {
    return cyclicAbstrRaw(heap, atnames.toRaw());
}

/// Expand type synonyms: replace ids `ids` throughout `x`.
pub fn txchangeRaw(heap: *Heap, ids_in: Word, x_in: Word) void {
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

/// `Value`-typed wrapper for `txchangeRaw` (§ GoReady Phase 5 step 4g).
///
/// Tests: txchange: installs a representation type in place of a synonym id's own type
pub fn txchange(heap: *Heap, ids_in: Value, x_in: Value) void {
    txchangeRaw(heap, ids_in.toRaw(), x_in.toRaw());
}

/// Substitute type arguments `L` for the formals of type `T`.
pub fn repT1Raw(heap: *Heap, T: Word, L: Word) Word {
    var args = NIL;
    var t1 = T;
    var changed = false;
    while (isCompoundType(heap, t1)) {
        const a = repT1Raw(heap, t(heap, t1), L);
        if (a != t(heap, t1)) {
            changed = true;
        }
        args = cons(heap, a, args);
        t1 = h(heap, t1);
    }
    if (member(heap, Value.fromRaw(L), Value.fromRaw(t1)) != 0) {
        return apSubst(heap, tInfo(heap, t1), args);
    }
    if (!changed) {
        return T;
    }
    while (args != NIL) {
        t1 = ap(heap, t1, h(heap, args));
        args = t(heap, args);
    }
    return t1;
}

/// `Value`-typed wrapper for `repT1Raw` (§ GoReady Phase 5 step 4g).
///
/// Tests: repT1: returns T unchanged when it has no formals to substitute
pub fn repT1(heap: *Heap, T: Value, L: Value) Value {
    return Value.fromRaw(repT1Raw(heap, T.toRaw(), L.toRaw()));
}

/// Replace type `T`'s formal parameters with arguments `L`, then renumber.
pub fn repTRaw(heap: *Heap, T: Word, L: Word) Word {
    const t_val = repT1Raw(heap, T, L);
    return if (t_val == T) t_val else redtvars(heap, t_val);
}

/// `Value`-typed wrapper for `repTRaw` (§ GoReady Phase 5 step 4g).
///
/// Tests: repT: returns T unchanged when repT1 makes no substitution
pub fn repT(heap: *Heap, T: Value, L: Value) Value {
    return Value.fromRaw(repTRaw(heap, T.toRaw(), L.toRaw()));
}

/// Normalise a type node after loading a dump (fix up indices).
pub fn fixTypeRaw(heap: *Heap, t_val: Word) Word {
    var t_node = t_val;
    switch (getTag(heap, t_node)) {
        .AP, .CONS => {
            tp(heap, t_node).* = fixTypeRaw(heap, t(heap, t_node));
            hp(heap, t_node).* = fixTypeRaw(heap, h(heap, t_node));
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

/// `Value`-typed wrapper for `fixTypeRaw` (§ GoReady Phase 5 step 4g).
///
/// Tests: fixType: passes atoms through unchanged, recurses through an AP node's fields
pub fn fixType(heap: *Heap, t_val: Value) Value {
    return Value.fromRaw(fixTypeRaw(heap, t_val.toRaw()));
}

/// Build and cache the `filestat` result type.
pub fn genlstatType(heap: *Heap) Value {
    if (cs().filestat_t == 0) {
        cs().filestat_t = tf(heap, cs().ltchar, pairType(heap, pairType(heap, num_t, num_t), num_t));
    }
    return Value.fromRaw(cs().filestat_t);
}

/// Whether a type node is a bound type variable.
pub fn isBoundType(heap: *Heap, type_node: Word) bool {
    return isCompoundType(heap, type_node) and h(heap, type_node) == bind_t;
}
