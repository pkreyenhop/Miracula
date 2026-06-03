const std = @import("std");

const c = @cImport({
    @cInclude("stdlib.h");
    @cInclude("stdio.h");
});

const Word = c_long;
const GENERATOR: Word = 0;
const GUARD: Word = 1;
const REPEAT: Word = 2;
const bool_t: Word = 1;
const num_t: Word = 2;
const char_t: Word = 3;
const list_t: Word = 4;
const comma_t: Word = 5;
const arrow_t: Word = 6;
const void_t: Word = 7;
const ATOM: u8 = 0;
const DOUBLE: u8 = 1;
const DATAPAIR: u8 = 2;
const TVAR: u8 = 4;
const INT: u8 = 5;
const CONSTRUCTOR: u8 = 6;
const STRCONS: u8 = 7;
const ID: u8 = 8;
const AP: u8 = 9;
const LAMBDA: u8 = 10;
const CONS: u8 = 11;
const TRIES: u8 = 12;
const LABEL: u8 = 13;
const SHOW: u8 = 14;
const LET: u8 = 16;
const LETREC: u8 = 17;
const SHARE: u8 = 18;
const LEXER: u8 = 19;
const PAIR: u8 = 20;
const TCONS: u8 = 22;
const CMBASE: Word = 306;
const S: Word = CMBASE + 0;
const K: Word = CMBASE + 1;
const Y: Word = CMBASE + 2;
const C: Word = CMBASE + 3;
const B: Word = CMBASE + 4;
const I: Word = CMBASE + 6;
const S_p: Word = CMBASE + 11;
const COND: Word = CMBASE + 16;
const APPEND: Word = CMBASE + 23;
const MAP: Word = CMBASE + 27;
const FLATMAP: Word = CMBASE + 31;
const FILTER: Word = CMBASE + 32;
const TRY: Word = CMBASE + 40;
const SUBSCRIPT: Word = CMBASE + 41;
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
const False: Word = CMBASE + 136;
const True: Word = CMBASE + 137;
const NIL: Word = CMBASE + 138;
const NILS: Word = CMBASE + 139;
const UNDEF: Word = CMBASE + 140;
const wrong_t: Word = 8;
const CONST: Word = 268;

extern var hd: [*]Word;
extern var tl: [*]Word;
extern var tag: [*]u8;
extern var current_id: Word;
extern var SGC: Word;
extern var ND: Word;
extern var concat: Word;
extern var diagonalise: Word;
extern var echoing: Word;
extern var errs: Word;
extern var idsused: Word;
extern var lfrule: c_int;
extern var nill: Word;
extern var polyshowerror: c_int;
extern var primenv: Word;
extern var showabstract: Word;
extern var showbool: Word;
extern var showchar: Word;
extern var showfunction: Word;
extern var showlist: Word;
extern var showpair: Word;
extern var showparen: Word;
extern var shownum1: Word;
extern var showstring: Word;
extern var showvoid: Word;
extern var showwhat: Word;
extern var speclocs: Word;
extern var was_poly: Word;

extern fn make(t: u8, x: Word, y: Word) Word;
extern fn reverse(x: Word) Word;
extern fn shunt(x: Word, y: Word) Word;
extern fn member(s: Word, x: Word) Word;
extern fn UNION(s1: Word, s2: Word) Word;
extern fn add1(e: Word, s: Word) Word;
extern fn abstract(x: Word, e: Word) Word;
extern fn codegen(x: Word) Word;
extern fn isnat(x: Word) c_int;
extern fn isconstrname(a: [*:0]const u8) c_int;
extern fn mkgvar(i: Word) Word;
extern fn out_type(t: Word) void;
extern fn redtvars(t: Word) Word;
extern fn sayhere(here: Word, nl: Word) void;
extern fn strcmp(a: [*:0]const u8, b: [*:0]const u8) c_int;
extern fn syntax(s: [*:0]const u8) void;
extern fn acterror() void;

fn h(x: Word) Word {
    return hd[@as(usize, @intCast(x)) * 2];
}

fn hp(x: Word) *Word {
    return &hd[@as(usize, @intCast(x)) * 2];
}

fn t(x: Word) Word {
    return tl[@as(usize, @intCast(x)) * 2];
}

fn tp(x: Word) *Word {
    return &tl[@as(usize, @intCast(x)) * 2];
}

fn cons(x: Word, y: Word) Word {
    return make(CONS, x, y);
}

fn pair(x: Word, y: Word) Word {
    return make(PAIR, x, y);
}

fn datapair(x: Word, y: Word) Word {
    return make(DATAPAIR, x, y);
}

fn lambda(x: Word, y: Word) Word {
    return make(LAMBDA, x, y);
}

fn ap(x: Word, y: Word) Word {
    return make(AP, x, y);
}

fn ap2(x: Word, y: Word, z: Word) Word {
    return ap(ap(x, y), z);
}

fn ap3(w: Word, x: Word, y: Word, z: Word) Word {
    return ap(ap2(w, x, y), z);
}

fn getId(x: Word) [*:0]const u8 {
    return @ptrFromInt(@as(usize, @intCast(h(h(h(x))))));
}

fn idWho(x: Word) Word {
    return t(h(h(x)));
}

fn setIdType(x: Word, value: Word) void {
    tp(h(x)).* = value;
}

fn setIdVal(x: Word, value: Word) void {
    tp(x).* = value;
}

fn isConstructor(x: Word) bool {
    return tag[@intCast(x)] == ID and isconstrname(getId(x)) != 0;
}

fn isVariable(x: Word) bool {
    return tag[@intCast(x)] == ID and isconstrname(getId(x)) == 0;
}

fn isNPlusKPattern(x: Word) bool {
    return tag[@intCast(x)] == AP and tag[@intCast(h(x))] == AP and h(h(x)) == PLUS;
}

fn isArrowType(x: Word) bool {
    return tag[@intCast(x)] == AP and tag[@intCast(h(x))] == AP and h(h(x)) == arrow_t;
}

fn isListType(x: Word) bool {
    return tag[@intCast(x)] == AP and h(x) == list_t;
}

fn isTypeVariable(x: Word) bool {
    return tag[@intCast(x)] == TVAR;
}

fn isCompoundType(x: Word) bool {
    return tag[@intCast(x)] == AP;
}

fn isChar(x: Word) bool {
    return 0 <= x and x <= 255;
}

fn typeArity(x: Word) Word {
    return h(h(t(x)));
}

fn typeShowFn(x: Word) Word {
    return t(h(t(x)));
}

fn typeClass(x: Word) Word {
    return h(t(t(x)));
}

fn getTypeVariable(x: Word) Word {
    return t(x);
}

fn mkindex(i: Word) Word {
    return if (i < 256) i else make(INT, i, 0);
}

fn dlhs(d: Word) Word {
    return h(d);
}

fn setDlhs(d: Word, value: Word) void {
    hp(d).* = value;
}

fn dval(d: Word) Word {
    return t(t(d));
}

fn setDval(d: Word, value: Word) void {
    tp(t(d)).* = value;
}

export fn primconstr(input_x: Word) Word {
    var x = t(h(input_x));
    while (tag[@intCast(x)] != CONSTRUCTOR) {
        x = t(x);
    }
    return x;
}

export fn memb(input_l: Word, x: Word) Word {
    var l = input_l;
    if (tag[@intCast(x)] == TVAR) {
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

export fn same(x: Word, y: Word) Word {
    if (x == y) {
        return 1;
    }
    const x_tag = tag[@intCast(x)];
    const y_tag = tag[@intCast(y)];
    if (x_tag == ATOM or y_tag == ATOM or x_tag != y_tag) {
        return 0;
    }
    if (x_tag < INT) {
        return if (h(x) == h(y) and t(x) == t(y)) 1 else 0;
    }
    if (x_tag > STRCONS) {
        return if (same(h(x), h(y)) != 0 and same(t(x), t(y)) != 0) 1 else 0;
    }
    return if (h(x) == h(y) and same(t(x), t(y)) != 0) 1 else 0;
}

export fn get_ids(x: Word) Word {
    if (h(x) == CONST or isConstructor(x)) {
        return NIL;
    }
    if (tag[@intCast(x)] == ID) {
        return cons(x, NIL);
    }
    if (isNPlusKPattern(x)) {
        return get_ids(t(x));
    }
    return UNION(get_ids(h(x)), get_ids(t(x)));
}

export fn mktuple(input_x: Word) Word {
    var x = input_x;
    if (h(x) == CONST or isConstructor(x)) {
        return NIL;
    }
    if (tag[@intCast(x)] == ID) {
        return x;
    }
    if (isNPlusKPattern(x)) {
        return mktuple(t(x));
    }
    const y = mktuple(t(x));
    x = mktuple(h(x));
    return if (x == NIL) y else if (y == NIL) x else pair(x, y);
}

export fn irrefutable(x: Word) Word {
    if (tag[@intCast(x)] == CONS) {
        return 0;
    }
    if (isConstructor(x)) {
        return member(SGC, x);
    }
    if (tag[@intCast(x)] == ID) {
        return 1;
    }
    if (isNPlusKPattern(x)) {
        return 0;
    }
    return if (irrefutable(h(x)) != 0 and irrefutable(t(x)) != 0) 1 else 0;
}

export fn fallible(input_e: Word) Word {
    var e = input_e;
    while (true) {
        const e_tag = tag[@intCast(e)];
        if (e_tag == LABEL) {
            e = t(e);
            continue;
        }
        if (e_tag == LETREC or e_tag == LET) {
            e = t(e);
        } else if (e_tag == LAMBDA) {
            if (irrefutable(h(e)) != 0) {
                e = t(e);
            } else {
                return 1;
            }
        } else if (e_tag == AP and tag[@intCast(h(e))] == AP and tag[@intCast(h(h(e)))] == AP and h(h(h(e))) == COND) {
            e = t(e);
        } else {
            return if (e == FAIL) 1 else 0;
        }
    }
}

export fn here_inf(rhs: Word) Word {
    var x = t(rhs);
    while (t(x) != NIL) {
        x = t(x);
    }
    return h(h(x));
}

export fn lastlink(input_x: Word) Word {
    var x = input_x;
    while (t(x) != NIL) {
        x = t(x);
    }
    return x;
}

export fn fixrepeats(input_qq: Word) Word {
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

export fn abshfnck(t_type: Word, f_input: Word) Word {
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

export fn combine(x: Word, y: Word) Word {
    const a = tag[@intCast(x)] == AP and h(x) == K;
    const b = tag[@intCast(y)] == AP and h(y) == K;
    if (a and b) {
        return ap(K, ap(t(x), t(y)));
    }
    if (a and y == I) {
        return t(x);
    }
    const b1 = tag[@intCast(y)] == AP and tag[@intCast(h(y))] == AP and h(h(y)) == B;
    if (a) {
        if (b1) {
            return ap3(B1, t(x), t(h(y)), t(y));
        }
        if (tag[@intCast(t(x))] == AP and tag[@intCast(h(t(x)))] == AP and h(h(t(x))) == COND) {
            return ap3(COND, t(h(t(x))), ap(K, t(t(x))), y);
        }
        return ap2(B, t(x), y);
    }
    const a1 = tag[@intCast(x)] == AP and tag[@intCast(h(x))] == AP and h(h(x)) == B;
    if (b) {
        if (a1) {
            if (tag[@intCast(t(h(x)))] == AP and h(t(h(x))) == COND) {
                return ap3(COND, t(t(h(x))), t(x), y);
            }
            return ap3(C1, t(h(x)), t(x), t(y));
        }
        return ap2(C, x, t(y));
    }
    if (a1) {
        if (tag[@intCast(t(h(x)))] == AP and h(t(h(x))) == COND) {
            return ap3(COND, t(t(h(x))), t(x), y);
        }
        return ap3(S1, t(h(x)), t(x), y);
    }
    return ap2(S, x, y);
}

export fn liscomb(x: Word, y: Word) Word {
    const a = tag[@intCast(x)] == AP and h(x) == K;
    const b = tag[@intCast(y)] == AP and h(y) == K;
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

export fn abstr(x: Word, e: Word) Word {
    switch (tag[@intCast(e)]) {
        TCONS, PAIR, CONS => return liscomb(abstr(x, h(e)), abstr(x, t(e))),
        AP => {
            if (h(e) == BADCASE or h(e) == CONFERROR) {
                return ap(K, e);
            }
            return combine(abstr(x, h(e)), abstr(x, t(e)));
        },
        LAMBDA, LET, LETREC, TRIES, LABEL, SHOW, LEXER, SHARE => {
            std.debug.print("impossible event in abstr (tag={d})\n", .{tag[@intCast(e)]});
            c.exit(1);
        },
        else => {
            if (x == e or (isTypeVariable(x) and isTypeVariable(e) and getTypeVariable(x) == getTypeVariable(e))) {
                return I;
            }
            return ap(K, e);
        },
    }
}

export fn abstrlist(x_input: Word, e: Word) Word {
    switch (tag[@intCast(e)]) {
        TCONS, PAIR, CONS => return liscomb(abstrlist(x_input, h(e)), abstrlist(x_input, t(e))),
        AP => {
            if (h(e) == BADCASE or h(e) == CONFERROR) {
                return ap(K, e);
            }
            return combine(abstrlist(x_input, h(e)), abstrlist(x_input, t(e)));
        },
        LAMBDA, LET, LETREC, TRIES, LABEL, SHOW, LEXER, SHARE => {
            std.debug.print("impossible event in abstrlist (tag={d})\n", .{tag[@intCast(e)]});
            c.exit(1);
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

export fn scanpattern(p: Word, x: Word, e: Word, fail: Word) Word {
    if (h(x) == CONST or isConstructor(x)) {
        return NIL;
    }
    if (tag[@intCast(x)] == ID) {
        const binding = cons(x, ap2(TRY, ap(lambda(p, x), e), fail));
        return cons(binding, NIL);
    }
    if (isNPlusKPattern(x)) {
        return scanpattern(p, t(x), e, fail);
    }
    return shunt(scanpattern(p, h(x), e, fail), scanpattern(p, t(x), e, fail));
}

export fn mklazy(d: Word) Word {
    if (irrefutable(dlhs(d)) != 0) {
        return d;
    }
    const ids = mktuple(dlhs(d));
    if (ids == NIL) {
        std.debug.print("impossible event in mklazy\n", .{});
        return d;
    }
    setDval(d, ap2(TRY, ap(lambda(dlhs(d), ids), dval(d)), ap(CONFERROR, cons(dlhs(d), here_inf(dval(d))))));
    setDlhs(d, ids);
    return d;
}

export fn new_mklazy(d: Word) Word {
    const ids = get_ids(dlhs(d));
    if (ids == NIL) {
        std.debug.print("impossible event in new_mklazy\n", .{});
        return d;
    }
    setDval(d, ap2(TRY, ap(lambda(dlhs(d), ids), dval(d)), ap(CONFERROR, cons(dlhs(d), here_inf(dval(d))))));
    setDlhs(d, ids);
    return d;
}

export fn compzf(input_e: Word, input_qq: Word, diag: Word) Word {
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
    e = transzf(e, hold, if (diag != 0) diagonalise else concat);
    if (diag != 0) {
        while (r != 0) {
            r -= 1;
            e = ap(concat, e);
        }
    }
    return if (e == g1) ap2(APPEND, NIL, e) else e;
}

export fn transzf(e_input: Word, qq_input: Word, conc: Word) Word {
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
        if (conc == concat) {
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

export fn getspecloc(x: Word) Word {
    var s = speclocs;
    while (s != NIL and h(h(s)) != x) {
        s = t(s);
    }
    return if (s == NIL) idWho(x) else t(h(s));
}

export fn transtypeid(x: Word) Word {
    const n = getId(x);
    if (strcmp(n, "bool") == 0) return bool_t;
    if (strcmp(n, "num") == 0) return num_t;
    if (strcmp(n, "char") == 0) return char_t;
    return x;
}

export fn genlhs(x: Word) Word {
    switch (tag[@intCast(x)]) {
        AP => {
            if (tag[@intCast(h(x))] == AP and h(h(x)) == PLUS and isnat(t(x)) != 0) {
                return ap2(PLUS, t(x), genlhs(t(h(x))));
            }
            const hold = genlhs(h(x));
            return make(AP, hold, genlhs(t(x)));
        },
        CONS, TCONS, PAIR => {
            const hold = genlhs(h(x));
            return make(tag[@intCast(x)], hold, genlhs(t(x)));
        },
        ID => {
            if (member(idsused, x) != 0) {
                return cons(CONST, x);
            }
            if (!isConstructor(x)) {
                idsused = cons(x, idsused);
            }
            return x;
        },
        INT => return cons(CONST, x),
        DOUBLE => {
            syntax("floating point literal in pattern\n");
            return nill;
        },
        ATOM => {
            if (x == True or x == False or x == NILS or x == NIL or isChar(x)) {
                return cons(CONST, x);
            }
        },
        else => {},
    }
    syntax("illegal form on left of <-\n");
    return nill;
}

export fn leftfactor(x: Word) Word {
    var a: Word = undefined;
    var b: Word = undefined;
    var rhs = t(h(x));
    var d: Word = undefined;
    if (tag[@intCast(rhs)] == AP and tag[@intCast(h(rhs))] == AP and h(h(rhs)) == G_SEQ) {
        a = t(h(rhs));
        b = t(rhs);
    } else {
        return x;
    }
    d = t(x);
    if (same(a, d) != 0) {
        hp(x).* = ap(G_SEQ, a);
        tp(x).* = ap2(G_ALT, b, G_UNIT);
        lfrule += 1;
        return x;
    }
    if (tag[@intCast(d)] == AP and tag[@intCast(h(d))] == AP) {
        rhs = h(h(d));
    } else {
        return x;
    }
    if (rhs == G_SEQ and same(a, t(h(d))) != 0) {
        rhs = t(d);
        hp(x).* = ap(G_SEQ, a);
        tp(x).* = leftfactor(ap2(G_ALT, b, rhs));
        lfrule += 1;
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
        lfrule += 1;
        return leftfactor(x);
    }
    if (tag[@intCast(rhs)] == AP and tag[@intCast(h(rhs))] == AP and h(h(rhs)) == G_SEQ and same(a, t(h(rhs))) != 0) {
        rhs = t(rhs);
        d = t(d);
        hp(x).* = ap(G_ALT, ap2(G_SEQ, a, leftfactor(ap2(G_ALT, b, rhs))));
        tp(x).* = d;
        lfrule += 1;
        return leftfactor(x);
    }
    return x;
}

export fn translet(d: Word, e: Word) Word {
    const x = mklazy(d);
    return ap(abstract(dlhs(x), codegen(e)), codegen(dval(x)));
}

export fn transletrec(input_dd: Word, e: Word) Word {
    var dd = input_dd;
    var lhs: Word = NIL;
    var rhs: Word = NIL;
    var pn: Word = 1;
    while (dd != NIL) : (dd = t(dd)) {
        var x = h(dd);
        if (tag[@intCast(dlhs(x))] == ID) {
            lhs = cons(dlhs(x), lhs);
            rhs = cons(codegen(dval(x)), rhs);
        } else {
            var i: Word = 0;
            const p = mkgvar(pn);
            pn += 1;
            x = new_mklazy(x);
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

export fn transtries(id: Word, input_x: Word) Word {
    var x = input_x;
    var info: Word = 0;
    var earliest: Word = 0;
    var r: Word = undefined;
    if (fallible(h(x)) != 0) {
        const oldn = if (tag[@intCast(id)] == ID) datapair(@as(Word, @intCast(@intFromPtr(getId(id)))), 0) else 0;
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

export fn makeshow(here: Word, type_node: Word) Word {
    was_poly = 0;
    const f = mkshow(0, 0, type_node);
    if (here != 0 and was_poly != 0) {
        _ = c.printf("type error in definition of %s\n", getId(current_id));
        sayhere(here, 0);
        _ = c.printf(" use of \"show\" at polymorphic type ");
        out_type(redtvars(type_node));
        _ = c.putchar('\n');
        setIdType(current_id, wrong_t);
        setIdVal(current_id, UNDEF);
        polyshowerror = 1;
        ND = add1(current_id, ND);
        was_poly = 0;
    }
    return f;
}

export fn mkshow(s: Word, p: Word, input_t: Word) Word {
    var args: Word = NIL;
    var type_node = input_t;
    while (tag[@intCast(type_node)] == AP) {
        args = cons(t(type_node), args);
        type_node = h(type_node);
    }
    switch (type_node) {
        num_t => return if (p != 0) shownum1 else SHOWNUM,
        bool_t => return showbool,
        char_t => return showchar,
        list_t => {
            if (h(args) == char_t) {
                return showstring;
            }
            return ap(showlist, mkshow(s, 0, h(args)));
        },
        comma_t => return ap(showparen, ap2(showpair, mkshow(s, 0, h(args)), mkshowt(s, h(t(args))))),
        void_t => return showvoid,
        arrow_t => return showfunction,
        else => {
            if (tag[@intCast(type_node)] == ID) {
                var r = typeShowFn(type_node);
                if (r == 0) {
                    return showabstract;
                }
                if (r == showwhat) {
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
                was_poly = 1;
                return showwhat;
            }
            if (tag[@intCast(type_node)] == STRCONS) {
                _ = c.printf("warning - mkshow applied to suppressed type\n");
                return showwhat;
            }
            _ = c.printf("impossible event in mkshow (");
            out_type(type_node);
            _ = c.printf(")\n");
            return showwhat;
        },
    }
}

export fn mkshowt(s: Word, type_tuple: Word) Word {
    if (t(type_tuple) == void_t) {
        return mkshow(s, 0, t(h(type_tuple)));
    }
    return ap2(showpair, mkshow(s, 0, t(h(type_tuple))), mkshowt(s, t(type_tuple)));
}

fn nclchk(n: Word, p: Word, hr: Word) c_int {
    if (h(p) == CONST) {
        return 0;
    }
    if (tag[@intCast(p)] == ID) {
        if (n != p) {
            return 0;
        }
        if (echoing != 0) {
            _ = c.putchar('\n');
        }
        errs = hr;
        _ = c.printf("syntax error: conflicting definitions of \"%s\" in where clause\n", getId(n));
        acterror();
        return 1;
    }
    if (tag[@intCast(p)] == AP and h(p) == PLUS) {
        return 0;
    }
    if (nclchk(n, h(p), hr) != 0) {
        return 1;
    }
    return nclchk(n, t(p), hr);
}

export fn nclashcheck(n: Word, input_dd: Word, hr: Word) void {
    var dd = input_dd;
    while (dd != NIL and nclchk(n, dlhs(h(dd)), hr) == 0) {
        dd = t(dd);
    }
}

export fn respec_error(x: Word) void {
    if (echoing != 0) {
        _ = c.putchar('\n');
    }
    const suffix: [*:0]const u8 = if (member(primenv, x) != 0) " (in standard environment)" else "";
    _ = c.printf("syntax error: type of \"%s\" already declared%s\n", getId(x), suffix);
    acterror();
}

export fn nameclash(x: Word) void {
    if (echoing != 0) {
        _ = c.putchar('\n');
    }
    const suffix: [*:0]const u8 = if (member(primenv, x) != 0) " (in standard environment)" else "";
    _ = c.printf("syntax error: nameclash, \"%s\" already defined%s\n", getId(x), suffix);
    acterror();
}

export fn tclos(r: Word) Word {
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

export fn getrel(input_r: Word, x: Word) Word {
    var r = input_r;
    while (r != NIL and h(h(r)) != x) r = t(r);
    return if (r == NIL) NIL else t(h(r));
}

export fn invgetrel(input_r: Word, x: Word) Word {
    var r = input_r;
    while (r != NIL and member(t(h(r)), x) == 0) r = t(r);
    if (r == NIL) {
        std.debug.print("impossible event in invgetrel\n", .{});
        c.exit(1);
    }
    return h(h(r));
}

export fn imageless(input_r: Word, input_y: Word, z: Word) Word {
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

export fn less(input_x: Word, input_y: Word) Word {
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

export fn less1(input_x: Word, a: Word) Word {
    var x = input_x;
    var r: Word = NIL;
    while (x != NIL and h(x) != a) {
        r = cons(h(x), r);
        x = t(x);
    }
    return shunt(r, if (x == NIL) NIL else t(x));
}

export fn sort(input_x: Word) Word {
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

export fn sortrel(input_x: Word) Word {
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
