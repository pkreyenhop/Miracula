//! semantics/lower_front.zig — expression helpers + bracket abstraction (docs/GO_PORT_PLAN.md P4).

const std = @import("std");
const word = @import("../graph/word.zig");
const os = @import("../os.zig");
const compiler_state = @import("../compiler/compiler_state.zig");
const cs = compiler_state.cs;
const match = @import("match.zig");
const Word = i64;
const Value = @import("../graph/value.zig").Value;
const GENERATOR: Word = 0;
const GUARD: Word = 1;
const REPEAT: Word = 2;
const bool_t = word.bool_t;
const num_t = word.num_t;
const char_t = word.char_t;
const CMBASE = word.CMBASE;
const S: Word = CMBASE + 0;
const K: Word = CMBASE + 1;
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
const G_ALT: Word = CMBASE + 97;
const G_SEQ: Word = CMBASE + 106;
const G_UNIT: Word = CMBASE + 108;
const BADCASE: Word = CMBASE + 132;
const CONFERROR: Word = CMBASE + 133;
const FAIL: Word = CMBASE + 135;
const NIL = word.NIL;
const NILS = word.NILS;
const CONST = word.CONST;
const heap_mod = @import("../graph/heap.zig");
const Heap = heap_mod.Heap;
const print_mod = @import("../graph/print.zig");
const depend = @import("depend.zig");
const rt = @import("../runtime/runtime_state.zig");
const out = print_mod.outTerm;
const member = depend.member;
const UNION = depend.UNION;

const lower_prims = @import("lower_prims.zig");
const getStdout = lower_prims.getStdout;
const getTag = lower_prims.getTag;
const h = lower_prims.h;
const hp = lower_prims.hp;
const t = lower_prims.t;
const tp = lower_prims.tp;
const appHead = lower_prims.appHead;
const cons = lower_prims.cons;
const pair = lower_prims.pair;
const constructor = lower_prims.constructor;
const lambda = lower_prims.lambda;
const ap = lower_prims.ap;
const ap2 = lower_prims.ap2;
const ap3 = lower_prims.ap3;
const getId = lower_prims.getId;
const idWho = lower_prims.idWho;
const idVal = lower_prims.idVal;
const isConstructor = lower_prims.isConstructor;
const isVariable = lower_prims.isVariable;
const isNPlusKPattern = lower_prims.isNPlusKPattern;
const isArrowType = lower_prims.isArrowType;
const isListType = lower_prims.isListType;
const isTypeVariable = lower_prims.isTypeVariable;
const isCompoundType = lower_prims.isCompoundType;
const typeArity = lower_prims.typeArity;
const getTypeVariable = lower_prims.getTypeVariable;
const mkindex = lower_prims.mkindex;
const dlhs = lower_prims.dlhs;
const setDlhs = lower_prims.setDlhs;
const dval = lower_prims.dval;
const setDval = lower_prims.setDval;

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

/// Collect the identifiers bound by pattern/definition `x`.
pub fn getIds(heap: *Heap, x: Word) Word {
    if (word.isAtom(x)) {
        return NIL;
    }
    if (h(heap, x) == CONST or isConstructor(heap, x)) {
        return NIL;
    }
    if (getTag(heap, x) == .ID) {
        return cons(heap, x, NIL);
    }
    if (isNPlusKPattern(heap, x)) {
        return getIds(heap, t(heap, x));
    }
    return UNION(heap, Value.fromRaw(getIds(heap, h(heap, x))), Value.fromRaw(getIds(heap, t(heap, x)))).toRaw();
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
        return member(heap, Value.fromRaw(cs().SGC), Value.fromRaw(x));
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
        qq = cons(heap, cons(heap, GENERATOR, cons(heap, h(heap, t(heap, q)), rhs)), qq);
        q = t(heap, t(heap, q));
    }
    return cons(heap, q, qq);
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
        return ap(heap, K, ap(heap, t(heap, x), t(heap, y)));
    }
    if (a and y == I) {
        return t(heap, x);
    }
    const b1 = getTag(heap, y) == .AP and getTag(heap, h(heap, y)) == .AP and h(heap, h(heap, y)) == B;
    if (a) {
        if (b1) {
            return ap3(heap, B1, t(heap, x), t(heap, h(heap, y)), t(heap, y));
        }
        if (getTag(heap, t(heap, x)) == .AP and getTag(heap, h(heap, t(heap, x))) == .AP and h(heap, h(heap, t(heap, x))) == COND) {
            return ap3(heap, COND, t(heap, h(heap, t(heap, x))), ap(heap, K, t(heap, t(heap, x))), y);
        }
        return ap2(heap, B, t(heap, x), y);
    }
    const a1 = getTag(heap, x) == .AP and getTag(heap, h(heap, x)) == .AP and h(heap, h(heap, x)) == B;
    if (b) {
        if (a1) {
            if (getTag(heap, t(heap, h(heap, x))) == .AP and h(heap, t(heap, h(heap, x))) == COND) {
                return ap3(heap, COND, t(heap, t(heap, h(heap, x))), t(heap, x), y);
            }
            return ap3(heap, C1, t(heap, h(heap, x)), t(heap, x), t(heap, y));
        }
        return ap2(heap, C, x, t(heap, y));
    }
    if (a1) {
        if (getTag(heap, t(heap, h(heap, x))) == .AP and h(heap, t(heap, h(heap, x))) == COND) {
            return ap3(heap, COND, t(heap, t(heap, h(heap, x))), t(heap, x), y);
        }
        return ap3(heap, S1, t(heap, h(heap, x)), t(heap, x), y);
    }
    return ap2(heap, S, x, y);
}

/// Combine two abstraction results building a cons, optimising the `K` cases.
pub fn liscomb(heap: *Heap, x: Word, y: Word) Word {
    const a = getTag(heap, x) == .AP and h(heap, x) == K;
    const b = getTag(heap, y) == .AP and h(heap, y) == K;
    if (a and b) {
        return ap(heap, K, cons(heap, t(heap, x), t(heap, y)));
    }
    if (a) {
        if (y == I) {
            return ap(heap, P, t(heap, x));
        }
        return ap2(heap, B_p, t(heap, x), y);
    }
    if (b) {
        return ap2(heap, C_p, x, t(heap, y));
    }
    return ap2(heap, S_p, x, y);
}

/// Bracket-abstract variable `x` out of expression `e` (Turner's algorithm).
pub fn abstract(heap: *Heap, input_x: Word, input_e: Word) Word {
    var x = input_x;
    var e = input_e;
    switch (getTag(heap, x)) {
        .ID => {
            if (isConstructor(heap, x)) {
                return if (member(heap, Value.fromRaw(cs().SGC), Value.fromRaw(x)) != 0) ap(heap, K, e) else ap2(heap, Ug, primconstr(heap, x), e);
            }
            return abstr(heap, x, e);
        },
        .CONS => {
            if (h(heap, x) == CONST) {
                if (getTag(heap, t(heap, x)) == .INT) {
                    return ap2(heap, MATCHINT, t(heap, x), e);
                }
                return ap2(heap, MATCH, if (t(heap, x) == NILS) NIL else t(heap, x), e);
            }
            return ap(heap, U_, abstract(heap, h(heap, x), abstract(heap, t(heap, x), e)));
        },
        .TCONS, .PAIR => return ap(heap, U, abstract(heap, h(heap, x), abstract(heap, t(heap, x), e))),
        .AP => {
            if (member(heap, Value.fromRaw(cs().SGC), Value.fromRaw(appHead(heap, x))) != 0) {
                return ap(heap, Uf, abstract(heap, h(heap, x), abstract(heap, t(heap, x), e)));
            }
            if (getTag(heap, h(heap, x)) == .AP and h(heap, h(heap, x)) == PLUS) {
                return ap2(heap, ATLEAST, t(heap, h(heap, x)), abstract(heap, t(heap, x), e));
            }
            while (getTag(heap, x) == .AP) {
                e = abstract(heap, t(heap, x), e);
                x = h(heap, x);
            }
        },
        else => {},
    }
    if (isConstructor(heap, x)) {
        return ap2(heap, Ug, primconstr(heap, x), e);
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
                return ap(heap, K, e);
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
            return ap(heap, K, e);
        },
    }
}

/// Bracket-abstract a list of variables `x` from `e`.
pub fn abstrlist(heap: *Heap, x_input: Word, e: Word) Word {
    switch (getTag(heap, e)) {
        .TCONS, .PAIR, .CONS => return liscomb(heap, abstrlist(heap, x_input, h(heap, e)), abstrlist(heap, x_input, t(heap, e))),
        .AP => {
            if (h(heap, e) == BADCASE or h(heap, e) == CONFERROR) {
                return ap(heap, K, e);
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
                return ap(heap, K, e);
            }
            return ap(heap, SUBSCRIPT, mkindex(i));
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
    setDval(heap, d, ap2(heap, TRY, ap(heap, lambda(heap, dlhs(heap, d), ids), dval(heap, d)), ap(heap, CONFERROR, cons(heap, dlhs(heap, d), hereInfo(heap, dval(heap, d))))));
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
    setDval(heap, d, ap2(heap, TRY, ap(heap, lambda(heap, dlhs(heap, d), ids), dval(heap, d)), ap(heap, CONFERROR, cons(heap, dlhs(heap, d), hereInfo(heap, dval(heap, d))))));
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
        hold = cons(heap, h(heap, qq), hold);
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
            e = ap(heap, rt.rs().concat, e);
        }
    }
    return if (e == g1) ap2(heap, APPEND, NIL, e) else e;
}

/// Translate a ZF comprehension body `e` over qualifiers `qq`.
pub fn transzf(heap: *Heap, e_input: Word, qq_input: Word, conc: Word) Word {
    var e = e_input;
    const qq = qq_input;
    if (qq == NIL) {
        return cons(heap, e, NIL);
    }
    const q = h(heap, qq);
    if (h(heap, q) == GUARD) {
        return ap3(heap, COND, t(heap, q), transzf(heap, e, t(heap, qq), conc), NIL);
    }
    if (t(heap, qq) == NIL) {
        if (h(heap, t(heap, q)) == e and isVariable(heap, e)) {
            return t(heap, t(heap, q));
        }
        if (irrefutable(heap, h(heap, t(heap, q))) != 0) {
            return ap2(heap, MAP, lambda(heap, h(heap, t(heap, q)), e), t(heap, t(heap, q)));
        }
        return ap2(heap, FLATMAP, lambda(heap, h(heap, t(heap, q)), cons(heap, e, NIL)), t(heap, t(heap, q)));
    }
    const q2 = h(heap, t(heap, qq));
    if (h(heap, q2) == GUARD) {
        if (conc == rt.rs().concat) {
            tp(heap, t(heap, q)).* = ap2(heap, FILTER, lambda(heap, h(heap, t(heap, q)), t(heap, q2)), t(heap, t(heap, q)));
            tp(heap, qq).* = t(heap, t(heap, qq));
            return transzf(heap, e, qq, conc);
        }
        e = ap3(heap, COND, t(heap, q2), cons(heap, e, NIL), NIL);
        tp(heap, qq).* = t(heap, t(heap, qq));
        return transzf(heap, e, qq, conc);
    }
    return ap(heap, conc, transzf(heap, transzf(heap, e, t(heap, qq), conc), cons(heap, q, NIL), conc));
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
        hp(heap, x).* = ap(heap, G_SEQ, a);
        tp(heap, x).* = ap2(heap, G_ALT, b, G_UNIT);
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
        hp(heap, x).* = ap(heap, G_SEQ, a);
        tp(heap, x).* = leftfactor(heap, ap2(heap, G_ALT, b, rhs));
        cs().lfrule += 1;
        return x;
    }
    if (rhs != G_ALT) {
        return x;
    }
    rhs = t(heap, h(heap, d));
    if (same(heap, a, rhs) != 0) {
        d = t(heap, d);
        hp(heap, x).* = ap(heap, G_ALT, ap2(heap, G_SEQ, a, ap2(heap, G_ALT, b, G_UNIT)));
        tp(heap, x).* = d;
        cs().lfrule += 1;
        return leftfactor(heap, x);
    }
    if (getTag(heap, rhs) == .AP and getTag(heap, h(heap, rhs)) == .AP and h(heap, h(heap, rhs)) == G_SEQ and same(heap, a, t(heap, h(heap, rhs))) != 0) {
        rhs = t(heap, rhs);
        d = t(heap, d);
        hp(heap, x).* = ap(heap, G_ALT, ap2(heap, G_SEQ, a, leftfactor(heap, ap2(heap, G_ALT, b, rhs))));
        tp(heap, x).* = d;
        cs().lfrule += 1;
        return leftfactor(heap, x);
    }
    return x;
}
