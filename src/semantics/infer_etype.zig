//! semantics/infer_etype.zig — expression type-inference walker + conforms (docs/GoReady.md P4).

const word = @import("../graph/word.zig");
const errors = @import("../runtime/errors.zig");
const script_store = @import("../session/script_store.zig");
const compiler_state = @import("../compiler/compiler_state.zig");
const core_state = @import("../runtime/core_state.zig");
const rt = @import("../runtime/runtime_state.zig");
const heap_mod = @import("../graph/heap.zig");
const Heap = heap_mod.Heap;
const print_mod = @import("../graph/print.zig");
const cs = compiler_state.cs;
const Word = word.Word;
const Value = @import("../graph/value.zig").Value;
const CMBASE = word.CMBASE;
const NIL = word.NIL;
const getspecloc = trans_mod.getspecloc;
const findid = lex_mod.findid;
const out = print_mod.outTerm;
const trans_mod = @import("../semantics/lower.zig");
const lex_mod = @import("../parser/lex.zig");
const depend = @import("depend.zig");
const add1 = depend.add1;
const member = depend.member;
pub const type_t: Word = 10;
const undef_t: Word = 0;
const bool_t: Word = 1;
const num_t: Word = 2;
const char_t: Word = 3;
const synonym_t = word.synonym_t;
const UNDEF: Word = CMBASE + 140;
const unify_mod = @import("unify.zig");
const subst = unify_mod.subst;
const linst = unify_mod.linst;
const instantiate = unify_mod.instantiate;
const unify1 = unify_mod.unify1;
const NTV = unify_mod.NTV;
const comma_t: Word = 5;
const arrow_t: Word = 6;
const void_t: Word = 7;
const wrong_t: Word = 8;
const type_errors = @import("type_errors.zig");
const sayhere = type_errors.sayhere;
const outType = type_errors.outType;
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
const subsumes = unify_mod.subsumes;
fn unify(heap: *Heap, t1: Word, t2: Word) i32 {
    const result = unify_mod.unify(heap, t1, t2);
    if (result == 0) typeError(heap, "unify", "with", t1, t2);
    return result;
}

const infer_prims = @import("infer_prims.zig");
const getTag = infer_prims.getTag;
const h = infer_prims.h;
const hp = infer_prims.hp;
const t = infer_prims.t;
const tp = infer_prims.tp;
const cons = infer_prims.cons;
const idType = infer_prims.idType;
const tArity = infer_prims.tArity;
const tClass = infer_prims.tClass;
const tInfo = infer_prims.tInfo;
const getId = infer_prims.getId;
const ap = infer_prims.ap;
const isConstructor = infer_prims.isConstructor;
const ap2 = infer_prims.ap2;
const tf = infer_prims.tf;
const tf2 = infer_prims.tf2;
const tf3 = infer_prims.tf3;
const tf4 = infer_prims.tf4;
const lt = infer_prims.lt;
const pairType = infer_prims.pairType;
const dlhs = infer_prims.dlhs;
const dtyp = infer_prims.dtyp;
const dval = infer_prims.dval;
const getStdout = infer_prims.getStdout;
const infer_subst = @import("infer_subst.zig");
const metaTcheck = infer_subst.metaTcheck;
const locateInc = infer_subst.locateInc;
const repTRaw = infer_subst.repTRaw;
const genlstatType = infer_subst.genlstatType;
const isBoundType = infer_subst.isBoundType;

/// Type-check that pattern `p` conforms to type `t_val` in environment `e`.
pub fn conforms(heap: *Heap, p: Word, t_val: Word, e_in: Word, ngt: Word) errors.MiraError!Word {
    var p_root = heap.roots.root(rt.allocator, &p);
    defer p_root.deinit();
    var t_root = heap.roots.root(rt.allocator, &t_val);
    defer t_root.deinit();
    var env_root = heap.roots.root(rt.allocator, &e_in);
    defer env_root.deinit();
    var ngt_root = heap.roots.root(rt.allocator, &ngt);
    defer ngt_root.deinit();
    var e = e_in;
    if (e == -1) {
        return -1;
    }
    if (getTag(heap, p) == .ID and !isConstructor(heap, p)) {
        return cons(heap, cons(heap, p, t_val), e);
    }
    if (h(heap, p) == CONST) {
        _ = unify(heap, try etype(heap, t(heap, p), e, ngt), t_val);
        return e;
    }
    if (getTag(heap, p) == .CONS) {
        const at = NTV(heap);
        if (unify(heap, lt(heap, at), t_val) == 0) {
            return -1;
        }
        return try conforms(heap, t(heap, p), t_val, try conforms(heap, h(heap, p), at, e, ngt), ngt);
    }
    if (getTag(heap, p) == .TCONS) {
        const at = NTV(heap);
        const bt = NTV(heap);
        if (unify(heap, ap2(heap, comma_t, at, bt), t_val) == 0) {
            return -1;
        }
        return try conforms(heap, t(heap, p), bt, try conforms(heap, h(heap, p), at, e, ngt), ngt);
    }
    if (getTag(heap, p) == .PAIR) {
        const at = NTV(heap);
        const bt = NTV(heap);
        if (unify(heap, ap2(heap, comma_t, at, ap2(heap, comma_t, bt, void_t)), t_val) == 0) {
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
            p_args = cons(heap, t(heap, cur_p), p_args);
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
        pt = instantiate(heap, if (cs().ATNAMES != 0) repTRaw(heap, idType(heap, cur_p), cs().ATNAMES) else idType(heap, cur_p));
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
pub fn etype(heap: *Heap, x: Word, env: Word, ngt: Word) errors.MiraError!Word {
    var x_root = heap.roots.root(rt.allocator, &x);
    defer x_root.deinit();
    var env_root = heap.roots.root(rt.allocator, &env);
    defer env_root.deinit();
    var ngt_root = heap.roots.root(rt.allocator, &ngt);
    defer ngt_root.deinit();
    switch (getTag(heap, x)) {
        .AP => return etypeAp(heap, x, env, ngt),
        .CONS => return etypeCons(heap, x, env, ngt),
        .LEXER => return etypeLexer(heap, x, env, ngt),
        .TCONS => {
            var left = try etype(heap, h(heap, x), env, ngt);
            var left_root = heap.roots.root(rt.allocator, &left);
            defer left_root.deinit();
            return ap2(heap, comma_t, left, try etype(heap, t(heap, x), env, ngt));
        },
        .PAIR => {
            var left = try etype(heap, h(heap, x), env, ngt);
            var left_root = heap.roots.root(rt.allocator, &left);
            defer left_root.deinit();
            return ap2(heap, comma_t, left, ap2(heap, comma_t, try etype(heap, t(heap, x), env, ngt), void_t));
        },
        .DOUBLE, .INT => {
            return num_t;
        },
        .ID => return etypeId(heap, x, env, ngt),
        .LAMBDA => {
            const a = NTV(heap);
            const b = NTV(heap);
            const d = cons(heap, a, ngt);
            const c_local = try conforms(heap, h(heap, x), a, env, d);
            if (c_local == -1 or unify(heap, b, try etype(heap, t(heap, x), c_local, d)) == 0) {
                return NTV(heap);
            }
            return tf(heap, a, b);
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
                tp(heap, x).* = NTV(heap);
                cs().showchain = cons(heap, x, cs().showchain);
            }
            return tf(heap, cs().ltchar, lt(heap, t(heap, x)));
        },
        .SHOW => {
            hp(heap, x).* = cs().lineptr;
            cs().showchain = cons(heap, x, cs().showchain);
            tp(heap, x).* = NTV(heap);
            return tf(heap, t(heap, x), cs().ltchar);
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
                return NTV(heap);
            }
            return t(heap, x);
        },
        .CONSTRUCTOR => {
            const a = idType(heap, t(heap, x));
            return instantiate(heap, if (cs().ATNAMES != 0) repTRaw(heap, a, cs().ATNAMES) else a);
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
pub fn etypeAp(heap: *Heap, x: Word, env: Word, ngt: Word) errors.MiraError!Word {
    if (h(heap, x) == word.BADCASE or h(heap, x) == word.CONFERROR) {
        return NTV(heap);
    }
    var ft_val = try etype(heap, h(heap, x), env, ngt);
    var ft_root = heap.roots.root(rt.allocator, &ft_val);
    defer ft_root.deinit();
    var at = try etype(heap, t(heap, x), env, ngt);
    var at_root = heap.roots.root(rt.allocator, &at);
    defer at_root.deinit();
    var rt_ty = NTV(heap);
    var result_root = heap.roots.root(rt.allocator, &rt_ty);
    defer result_root.deinit();
    if (unify1(heap, ft_val, ap2(heap, arrow_t, at, rt_ty)) == 0) {
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
        return NTV(heap);
    }
    return rt_ty;
}

/// [etype] for a `.CONS` node: finds the chain's tail, unifies its type with
/// the list type, then unifies every head's type with the list's element
/// type, reporting the first mismatch found (checked tail-first, matching the
/// original C reducer's error-reporting order).
pub fn etypeCons(heap: *Heap, x: Word, env: Word, ngt: Word) errors.MiraError!Word {
    var elem_type = NTV(heap);
    var elem_root = heap.roots.root(rt.allocator, &elem_type);
    defer elem_root.deinit();
    var list_type = lt(heap, elem_type);
    var list_root = heap.roots.root(rt.allocator, &list_type);
    defer list_root.deinit();

    // 1. Find the tail of the CONS chain
    var cur = x;
    while (getTag(heap, cur) == .CONS) {
        cur = t(heap, cur);
    }
    const tail_expr = cur;

    // 2. Type check the tail
    var tail_type = try etype(heap, tail_expr, env, ngt);
    var tail_root = heap.roots.root(rt.allocator, &tail_type);
    defer tail_root.deinit();
    if (unify1(heap, list_type, tail_type) == 0) {
        // Find the last CONS node to report the error on
        var last_cons = x;
        while (t(heap, last_cons) != tail_expr) {
            last_cons = t(heap, last_cons);
        }
        const ht = try etype(heap, h(heap, last_cons), env, ngt);
        typeError(heap, "cons", "to", ht, tail_type);
        return NTV(heap);
    }

    // 3. Type check each head in the chain
    cur = x;
    while (getTag(heap, cur) == .CONS) {
        const ht = try etype(heap, h(heap, cur), env, ngt);
        if (unify1(heap, ht, elem_type) == 0) {
            const rt_ty = try etype(heap, t(heap, cur), env, ngt);
            typeError(heap, "cons", "to", ht, rt_ty);
            return NTV(heap);
        }
        cur = t(heap, cur);
    }
    return list_type;
}

/// [etype] for a `.LEXER` node: type-checks each alternative's grammar body
/// against the first alternative's type, restoring `cs.lineptr` (used for
/// error-location reporting) around each check.
pub fn etypeLexer(heap: *Heap, x: Word, env: Word, ngt: Word) errors.MiraError!Word {
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
            return NTV(heap);
        }
    }
    cs().lineptr = hold;
    return tf(heap, cs().ltchar, lt(heap, a));
}

/// [etype] for a `.ID` node: looks it up in the local type environment first
/// (`env`, generalizing on hit), then the global identifier table, reporting
/// undefined/wrongly-typed names.
pub fn etypeId(heap: *Heap, x: Word, env: Word, ngt: Word) errors.MiraError!Word {
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
        } else if (member(heap, Value.fromRaw(cs().ND), Value.fromRaw(x)) == 0) {
            if (cs().lineptr != 0) {
                sayhere(heap, cs().lineptr, 0);
            } else if (getTag(heap, cs().current_id) == .DATAPAIR) {
                locateInc(heap);
            }
            _ = word.print("undefined name \"{s}\"\n", .{getId(heap, x)});
            cs().ND = add1(heap, Value.fromRaw(x), Value.fromRaw(cs().ND)).toRaw();
        }
        return NTV(heap);
    }
    if (a == wrong_t) {
        return NTV(heap);
    }
    return instantiate(heap, if (cs().ATNAMES != 0) repTRaw(heap, a, cs().ATNAMES) else a);
}

/// [etype] for a `.LET` node: infers the bound expression's type against the
/// pattern, then the body's type in the extended environment.
pub fn etypeLet(heap: *Heap, x: Word, env: Word, ngt: Word) errors.MiraError!Word {
    var e: Word = undefined;
    const def = h(heap, x);
    const a = NTV(heap);
    e = try conforms(heap, dlhs(heap, def), a, env, cons(heap, a, ngt));
    cs().current_id = cons(heap, dlhs(heap, def), cs().current_id);
    const c_local = cs().lineptr;
    cs().lineptr = dval(heap, def);
    const unified = unify(heap, a, try etype(heap, dval(heap, def), env, ngt));
    cs().lineptr = c_local;
    cs().current_id = t(heap, cs().current_id);
    if (e == -1 or unified == 0) {
        return NTV(heap);
    }
    return try etype(heap, t(heap, x), e, ngt);
}

/// [etype] for a `.LETREC` node: assigns each definition a fresh type
/// variable (or its declared type, if any), extends the environment with all
/// of them (so mutual recursion type-checks), then checks each definition's
/// body against its assigned type -- explicitly-typed definitions are
/// checked for subsumption rather than plain unification.
pub fn etypeLetrec(heap: *Heap, x: Word, env: Word, ngt: Word) errors.MiraError!Word {
    var e = env;
    var s = NIL;
    var a = NIL;
    var c_local = ngt;
    var cur_d = h(heap, x);
    while (cur_d != NIL) {
        if (dtyp(heap, h(heap, cur_d)) == undef_t) {
            a = cons(heap, h(heap, cur_d), a);
            const b = NTV(heap);
            hp(heap, t(heap, h(heap, cur_d))).* = b;
            c_local = cons(heap, b, c_local);
            e = try conforms(heap, dlhs(heap, h(heap, cur_d)), b, e, c_local);
        } else {
            hp(heap, t(heap, h(heap, cur_d))).* = try metaTcheck(heap, dtyp(heap, h(heap, cur_d)));
            s = cons(heap, h(heap, cur_d), s);
            e = cons(heap, cons(heap, dlhs(heap, h(heap, cur_d)), dtyp(heap, h(heap, cur_d))), e);
        }
        cur_d = t(heap, cur_d);
    }
    if (e == -1) {
        return NTV(heap);
    }
    var success = true;
    var cur_a = a;
    while (cur_a != NIL) {
        cs().current_id = cons(heap, dlhs(heap, h(heap, cur_a)), cs().current_id);
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
        cs().current_id = cons(heap, dlhs(heap, h(heap, cur_s)), cs().current_id);
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
        return NTV(heap);
    }
    return try etype(heap, t(heap, x), e, ngt);
}

/// [etype] for a `.TRIES` node (a `%include`/grammar alternative chain):
/// unifies every alternative's type with the first, reporting a mismatch at
/// the first alternative that disagrees.
pub fn etypeTries(heap: *Heap, x: Word, env: Word, ngt: Word) errors.MiraError!Word {
    const hold = cs().lineptr;
    const a = NTV(heap);
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
        return NTV(heap);
    }
    return a;
}

/// [etype] for an `.ATOM` node: single-byte atoms are characters; otherwise
/// this is one of the built-in SK-family combinators or primitive operators,
/// each with a fixed (possibly polymorphic, via fresh `NTV(heap)` type
/// variables) type -- effectively a static type table for the whole
/// combinator/operator vocabulary.
pub fn etypeAtom(heap: *Heap, x: Word) Word {
    if (word.fitsInByte(x)) {
        return char_t;
    }
    switch (x) {
        word.S => {
            const a = NTV(heap);
            const b = NTV(heap);
            const c_local = NTV(heap);
            const d = tf3(heap, tf2(heap, a, b, c_local), tf(heap, a, b), a, c_local);
            return d;
        },
        word.K => {
            const a = NTV(heap);
            const b = NTV(heap);
            return tf2(heap, a, b, a);
        },
        word.Y => {
            const a = NTV(heap);
            return tf(heap, tf(heap, a, a), a);
        },
        word.C => {
            const a = NTV(heap);
            const b = NTV(heap);
            const c_local = NTV(heap);
            return tf3(heap, tf2(heap, a, b, c_local), b, a, c_local);
        },
        word.B => {
            const a = NTV(heap);
            const b = NTV(heap);
            const c_local = NTV(heap);
            return tf3(heap, tf(heap, a, b), tf(heap, c_local, a), c_local, b);
        },
        word.FORCE, word.G_UNIT, word.G_RULE, word.I => {
            const a = NTV(heap);
            return tf(heap, a, a);
        },
        word.G_ZERO => {
            return NTV(heap);
        },
        word.HD => {
            const a = NTV(heap);
            return tf(heap, lt(heap, a), a);
        },
        word.TL => {
            const a = lt(heap, NTV(heap));
            return tf(heap, a, a);
        },
        word.BODY => {
            const a = NTV(heap);
            const b = NTV(heap);
            return tf(heap, ap(heap, a, b), a);
        },
        word.LAST => {
            const a = NTV(heap);
            const b = NTV(heap);
            return tf(heap, ap(heap, a, b), b);
        },
        word.S_p => {
            const a = NTV(heap);
            const b = NTV(heap);
            const c_local = lt(heap, b);
            return tf3(heap, tf(heap, a, b), tf(heap, a, c_local), a, c_local);
        },
        word.U, word.U_ => {
            const a = NTV(heap);
            const b = NTV(heap);
            const c_local = lt(heap, a);
            return tf2(heap, tf2(heap, a, c_local, b), c_local, b);
        },
        word.Uf => {
            const a = NTV(heap);
            const b = NTV(heap);
            const c_local = NTV(heap);
            return tf2(heap, tf2(heap, tf(heap, a, b), a, c_local), b, c_local);
        },
        word.COND => {
            const a = NTV(heap);
            return tf3(heap, bool_t, a, a, a);
        },
        word.EQ, word.GR, word.GRE, word.NEQ => {
            const a = NTV(heap);
            return tf2(heap, a, a, bool_t);
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
            const a = lt(heap, NTV(heap));
            return tf2(heap, a, a, a);
        },
        word.STEP => {
            return cs().tstep;
        },
        word.STEPUNTIL => {
            return cs().tstepuntil;
        },
        word.MAP => {
            const a = NTV(heap);
            const b = NTV(heap);
            return tf2(heap, tf(heap, a, b), lt(heap, a), lt(heap, b));
        },
        word.FLATMAP => {
            const a = NTV(heap);
            const b = lt(heap, NTV(heap));
            return tf2(heap, tf(heap, a, b), lt(heap, a), b);
        },
        word.FILTER => {
            const a = NTV(heap);
            const b = lt(heap, a);
            return tf2(heap, tf(heap, a, bool_t), b, b);
        },
        word.ZIP => {
            const a = NTV(heap);
            const b = NTV(heap);
            return tf2(heap, lt(heap, a), lt(heap, b), lt(heap, pairType(heap, a, b)));
        },
        word.FOLDL => {
            const a = NTV(heap);
            const b = NTV(heap);
            return tf3(heap, tf2(heap, a, b, a), a, lt(heap, b), a);
        },
        word.FOLDL1 => {
            const a = NTV(heap);
            return tf2(heap, tf2(heap, a, a, a), lt(heap, a), a);
        },
        word.LIST_LAST => {
            const a = NTV(heap);
            return tf(heap, lt(heap, a), a);
        },
        word.FOLDR => {
            const a = NTV(heap);
            const b = NTV(heap);
            return tf3(heap, tf2(heap, a, b, b), b, lt(heap, a), b);
        },
        word.MATCHINT, word.MATCH => {
            const a = NTV(heap);
            const b = NTV(heap);
            return tf3(heap, a, b, a, b);
        },
        word.TRY => {
            const a = NTV(heap);
            return tf2(heap, a, a, a);
        },
        word.DROP, word.TAKE => {
            const a = lt(heap, NTV(heap));
            return tf2(heap, num_t, a, a);
        },
        word.SUBSCRIPT => {
            const a = NTV(heap);
            return tf2(heap, num_t, lt(heap, a), a);
        },
        word.P => {
            const a = NTV(heap);
            const b = lt(heap, a);
            return tf2(heap, a, b, b);
        },
        word.B_p => {
            const a = NTV(heap);
            const b = NTV(heap);
            const c_local = lt(heap, a);
            return tf3(heap, a, tf(heap, b, c_local), b, c_local);
        },
        word.C_p => {
            const a = NTV(heap);
            const b = NTV(heap);
            const c_local = lt(heap, b);
            return tf3(heap, tf(heap, a, b), c_local, a, c_local);
        },
        word.S1 => {
            const a = NTV(heap);
            const b = NTV(heap);
            const c_local = NTV(heap);
            const d = NTV(heap);
            return tf4(heap, tf2(heap, a, b, c_local), tf(heap, d, a), tf(heap, d, b), d, c_local);
        },
        word.B1 => {
            const a = NTV(heap);
            const b = NTV(heap);
            const c_local = NTV(heap);
            const d = NTV(heap);
            return tf4(heap, tf(heap, a, b), tf(heap, c_local, a), tf(heap, d, c_local), d, b);
        },
        word.C1 => {
            const a = NTV(heap);
            const b = NTV(heap);
            const c_local = NTV(heap);
            const d = NTV(heap);
            return tf4(heap, tf2(heap, a, b, c_local), tf(heap, d, a), b, d, c_local);
        },
        word.SEQ => {
            const a = NTV(heap);
            const b = NTV(heap);
            return tf2(heap, a, b, b);
        },
        word.ITERATE1, word.ITERATE => {
            const a = NTV(heap);
            return tf2(heap, tf(heap, a, a), a, lt(heap, a));
        },
        word.EXEC => {
            if (cs().exec_t == 0) {
                const a = ap2(heap, comma_t, cs().ltchar, ap2(heap, comma_t, num_t, void_t));
                cs().exec_t = tf(heap, cs().ltchar, ap2(heap, comma_t, cs().ltchar, a));
            }
            return cs().exec_t;
        },
        word.READBIN, word.READ => {
            if (cs().read_t == 0) {
                cs().read_t = tf(heap, char_t, cs().ltchar);
            }
            return cs().read_t;
        },
        word.FILESTAT => {
            return genlstatType(heap).toRaw();
        },
        word.FILEMODE, word.GETENV, word.NB_STARTREAD, word.STARTREADBIN, word.STARTREAD => {
            return cs().tfstrstr;
        },
        word.GETARGS => {
            return tf(heap, char_t, lt(heap, cs().ltchar));
        },
        word.SHOWHEX, word.SHOWOCT, word.SHOWNUM => {
            return tf(heap, num_t, cs().ltchar);
        },
        word.SHOWFLOAT, word.SHOWSCALED => {
            return tf2(heap, num_t, num_t, cs().ltchar);
        },
        word.NUMVAL => {
            return tf(heap, cs().ltchar, num_t);
        },
        word.INTEGER => {
            return tf(heap, num_t, bool_t);
        },
        word.CODE => {
            return tf(heap, char_t, num_t);
        },
        word.DECODE => {
            return tf(heap, num_t, char_t);
        },
        word.LENGTH => {
            return tf(heap, lt(heap, NTV(heap)), num_t);
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
            const a = lt(heap, NTV(heap));
            return a;
        },
        word.NILS => {
            return cs().ltchar;
        },
        word.MKSTRICT => {
            const a = NTV(heap);
            return tf(heap, char_t, tf(heap, a, a));
        },
        word.G_ALT => {
            const a = NTV(heap);
            return tf2(heap, a, a, a);
        },
        word.G_ERROR => {
            const a = NTV(heap);
            return tf2(heap, a, tf(heap, lt(heap, cs().bnf_t), a), a);
        },
        word.G_OPT, word.G_STAR => {
            const a = NTV(heap);
            return tf(heap, a, lt(heap, a));
        },
        word.G_FBSTAR => {
            const a = NTV(heap);
            const b = tf(heap, a, a);
            return tf(heap, b, b);
        },
        word.G_SYMB => {
            return cs().tfstrstr;
        },
        word.G_ANY => {
            return cs().ltchar;
        },
        word.G_SUCHTHAT => {
            return tf(heap, tf(heap, cs().ltchar, bool_t), cs().ltchar);
        },
        word.G_END => {
            return lt(heap, cs().bnf_t);
        },
        word.G_STATE => {
            return t(heap, h(heap, t(heap, cs().bnf_t)));
        },
        word.G_SEQ => {
            const a = NTV(heap);
            const b = NTV(heap);
            return tf2(heap, a, tf(heap, a, b), b);
        },
        word.G_CLOSE => {
            const a = NTV(heap);
            if (script_store.store().col_fn != 0) {
                if (script_store.store().col_fn == -1) {
                    cs().TYPERRS += 1;
                } else {
                    checkcolfn(heap);
                }
            }
            return tf3(heap, cs().ltchar, a, lt(heap, cs().bnf_t), a);
        },
        word.OFFSIDE => {
            return cs().ltchar;
        },
        word.FAIL, word.CONFERROR, word.BADCASE, UNDEF => {
            return NTV(heap);
        },
        word.ERROR => {
            return tf(heap, cs().ltchar, NTV(heap));
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
    const f = tf(heap, t(heap, h(heap, t(heap, cs().bnf_t))), num_t);
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
    cs().bnf_t = ap2(heap, comma_t, cs().ltchar, ap2(heap, comma_t, cs().bnf_t, void_t));
}
