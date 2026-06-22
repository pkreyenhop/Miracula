const std = @import("std");
const word = @import("../runtime/word.zig");

const shim = @import("../runtime/c_abi.zig");
const main = @import("../main.zig");

const compiler_state = @import("compiler_state.zig");
const cs = &compiler_state.cs;
const abi = struct {
    pub const printf = shim.printf;
    pub const putchar = shim.putchar;
    pub const FILE = shim.FILE;
    pub const stdout = shim.stdout;
    pub const exit = shim.exit;
};

const lex_state = @import("../parser/lex_state.zig");
const ls = &lex_state.ls;

fn getStdout() ?*word.FILE {
    return shim.stdout();
}

const Word = i64;
const GENERATOR: Word = 0;
const GUARD: Word = 1;
const REPEAT: Word = 2;
const undef_t: Word = 0;
const bool_t: Word = 1;
const num_t: Word = 2;
const char_t: Word = 3;
const list_t: Word = 4;
const comma_t: Word = 5;
const arrow_t: Word = 6;
const void_t: Word = 7;
const type_t: Word = 10;
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
const STARTREADVALS: u8 = 15;
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
const False: Word = CMBASE + 136;
const True: Word = CMBASE + 137;
const NIL: Word = CMBASE + 138;
const NILS: Word = CMBASE + 139;
const UNDEF: Word = CMBASE + 140;
const wrong_t: Word = 8;
const placeholder_t: Word = 3;
const algebraic_t: Word = 0;
const synonym_t: Word = 1;
const abstract_t: Word = 2;
const CONST: Word = 268;
const ATOMLIMIT: Word = CMBASE + 141;

// NIL

// NIL

// NIL

// NIL

extern fn make(t: u8, x: Word, y: Word) Word;
extern fn append1(x: Word, y: Word) Word;
extern fn reverse(x: Word) Word;
extern fn shunt(x: Word, y: Word) Word;
extern fn member(s: Word, x: Word) Word;
extern fn UNION(s1: Word, s2: Word) Word;
extern fn add1(e: Word, s: Word) Word;
extern fn deps(x: Word) Word;
extern fn intersection(s1: Word, s2: Word) Word;
extern fn isnat(x: Word) c_int;
extern fn isconstrname(a: [*:0]const u8) c_int;
extern fn make_pn(val: Word) Word;
extern fn mkgvar(i: Word) Word;
extern fn out(file: ?*word.FILE, x: Word) void;
extern fn out_type(t: Word) void;
extern fn redtvars(t: Word) Word;
extern fn sayhere(here: Word, nl: Word) void;
extern fn setdiff(s1: Word, s2: Word) Word;
extern fn strcmp(a: [*:0]const u8, b: [*:0]const u8) c_int;
extern fn syntax(s: [*:0]const u8) void;
extern fn acterror() void;
extern fn msc(r: Word) Word;
extern fn tsort(g: Word) Word;

inline fn getTag(x: Word) u8 {
    return main.heap.heap.getTag(x);
}

fn h(x: Word) Word {
    return main.heap.heap.h(x);
}

fn hp(x: Word) *Word {
    return main.heap.heap.hp(x);
}

fn t(x: Word) Word {
    return main.heap.heap.t(x);
}

fn tp(x: Word) *Word {
    return main.heap.heap.tp(x);
}

fn appHead(input_x: Word) Word {
    var x = input_x;
    while (getTag(x) == AP) {
        x = h(x);
    }
    return x;
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

fn constructor(n: Word, x: Word) Word {
    return make(CONSTRUCTOR, n, x);
}

fn lambda(x: Word, y: Word) Word {
    return make(LAMBDA, x, y);
}

fn share(x: Word, y: Word) Word {
    return make(SHARE, x, y);
}

fn tries(x: Word, y: Word) Word {
    return make(TRIES, x, y);
}

fn let(x: Word, y: Word) Word {
    return make(LET, x, y);
}

fn letrec(x: Word, y: Word) Word {
    return make(LETREC, x, y);
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

fn setIdWho(x: Word, value: Word) void {
    tp(h(h(x))).* = value;
}

fn idType(x: Word) Word {
    return t(h(x));
}

fn idVal(x: Word) Word {
    return t(x);
}

fn setIdType(x: Word, value: Word) void {
    tp(h(x)).* = value;
}

fn setIdVal(x: Word, value: Word) void {
    tp(x).* = value;
}

fn makeTyp(arity: Word, showfn: Word, class: Word, info: Word) Word {
    return cons(cons(arity, showfn), cons(class, info));
}

fn addToEnv(x: Word) void {
    const current_file_defs = h(main.files);
    if (current_file_defs >= ATOMLIMIT) {
        
        tp(current_file_defs).* = cons(x, tp(current_file_defs).*);
    }
}

fn isConstructor(x: Word) bool {
    return getTag(x) == ID and isconstrname(getId(x)) != 0;
}

fn isVariable(x: Word) bool {
    return getTag(x) == ID and isconstrname(getId(x)) == 0;
}

fn isNPlusKPattern(x: Word) bool {
    return getTag(x) == AP and getTag(h(x)) == AP and h(h(x)) == PLUS;
}

fn isArrowType(x: Word) bool {
    return getTag(x) == AP and getTag(h(x)) == AP and h(h(x)) == arrow_t;
}

fn isListType(x: Word) bool {
    return getTag(x) == AP and h(x) == list_t;
}

fn isTypeVariable(x: Word) bool {
    return getTag(x) == TVAR;
}

fn isCompoundType(x: Word) bool {
    return getTag(x) == AP;
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

fn setTypeClass(x: Word, value: Word) void {
    hp(t(t(x))).* = value;
}

fn typeInfo(x: Word) Word {
    return t(t(t(x)));
}

fn setTypeInfo(x: Word, value: Word) void {
    tp(t(t(x))).* = value;
}

fn getTypeVariable(x: Word) Word {
    return t(x);
}

fn mkindex(i: Word) Word {
    return if (word.fitsInByte(i)) i else make(INT, i, 0);
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

pub fn primconstr(input_x: Word) Word {
    var x = t(input_x); // idVal(x) = CONSTRUCTOR cell (or MKSTRICT wrapper for strict ctors)
    while (getTag(x) != CONSTRUCTOR) {
        x = t(x);
    }
    return x;
}

pub fn memb(input_l: Word, x: Word) Word {
    var l = input_l;
    if (getTag(x) == TVAR) {
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
    const x_tag = getTag(x);
    const y_tag = getTag(y);
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

pub fn get_ids(x: Word) Word {
    if (word.isAtom(x)) {
        return NIL;
    }
    if (h(x) == CONST or isConstructor(x)) {
        return NIL;
    }
    if (getTag(x) == ID) {
        return cons(x, NIL);
    }
    if (isNPlusKPattern(x)) {
        return get_ids(t(x));
    }
    return UNION(get_ids(h(x)), get_ids(t(x)));
}

export fn mktuple(input_x: Word) Word {
    var x = input_x;
    if (word.isAtom(x)) {
        return NIL;
    }
    if (h(x) == CONST or isConstructor(x)) {
        return NIL;
    }
    if (getTag(x) == ID) {
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
    if (word.isAtom(x)) {
        return 0;
    }
    if (getTag(x) == CONS) {
        return 0;
    }
    if (isConstructor(x)) {
        return member(cs.SGC, x);
    }
    if (getTag(x) == ID) {
        return 1;
    }
    if (isNPlusKPattern(x)) {
        return 0;
    }
    return if (irrefutable(h(x)) != 0 and irrefutable(t(x)) != 0) 1 else 0;
}

pub fn fallible(input_e: Word) Word {
    var e = input_e;
    while (true) {
        const e_tag = getTag(e);
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
        } else if (e_tag == AP and getTag(h(e)) == AP and getTag(h(h(e))) == AP and h(h(h(e))) == COND) {
            e = t(e);
        } else {
            return if (e == FAIL) 1 else 0;
        }
    }
}

pub fn here_inf(rhs: Word) Word {
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

pub fn fixrepeats(input_qq: Word) Word {
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

pub fn abshfnck(t_type: Word, f_input: Word) Word {
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

pub fn combine(x: Word, y: Word) Word {
    const a = getTag(x) == AP and h(x) == K;
    const b = getTag(y) == AP and h(y) == K;
    if (a and b) {
        return ap(K, ap(t(x), t(y)));
    }
    if (a and y == I) {
        return t(x);
    }
    const b1 = getTag(y) == AP and getTag(h(y)) == AP and h(h(y)) == B;
    if (a) {
        if (b1) {
            return ap3(B1, t(x), t(h(y)), t(y));
        }
        if (getTag(t(x)) == AP and getTag(h(t(x))) == AP and h(h(t(x))) == COND) {
            return ap3(COND, t(h(t(x))), ap(K, t(t(x))), y);
        }
        return ap2(B, t(x), y);
    }
    const a1 = getTag(x) == AP and getTag(h(x)) == AP and h(h(x)) == B;
    if (b) {
        if (a1) {
            if (getTag(t(h(x))) == AP and h(t(h(x))) == COND) {
                return ap3(COND, t(t(h(x))), t(x), y);
            }
            return ap3(C1, t(h(x)), t(x), t(y));
        }
        return ap2(C, x, t(y));
    }
    if (a1) {
        if (getTag(t(h(x))) == AP and h(t(h(x))) == COND) {
            return ap3(COND, t(t(h(x))), t(x), y);
        }
        return ap3(S1, t(h(x)), t(x), y);
    }
    return ap2(S, x, y);
}

pub fn liscomb(x: Word, y: Word) Word {
    const a = getTag(x) == AP and h(x) == K;
    const b = getTag(y) == AP and h(y) == K;
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

pub fn abstract(input_x: Word, input_e: Word) Word {
    var x = input_x;
    var e = input_e;
    switch (getTag(x)) {
        ID => {
            if (isConstructor(x)) {
                return if (member(cs.SGC, x) != 0) ap(K, e) else ap2(Ug, primconstr(x), e);
            }
            return abstr(x, e);
        },
        CONS => {
            if (h(x) == CONST) {
                if (getTag(t(x)) == INT) {
                    return ap2(MATCHINT, t(x), e);
                }
                return ap2(MATCH, if (t(x) == NILS) NIL else t(x), e);
            }
            return ap(U_, abstract(h(x), abstract(t(x), e)));
        },
        TCONS, PAIR => return ap(U, abstract(h(x), abstract(t(x), e))),
        AP => {
            if (member(cs.SGC, appHead(x)) != 0) {
                return ap(Uf, abstract(h(x), abstract(t(x), e)));
            }
            if (getTag(h(x)) == AP and h(h(x)) == PLUS) {
                return ap2(ATLEAST, t(h(x)), abstract(t(x), e));
            }
            while (getTag(x) == AP) {
                e = abstract(t(x), e);
                x = h(x);
            }
        },
        else => {},
    }
    if (isConstructor(x)) {
        return ap2(Ug, primconstr(x), e);
    }
    _ = word.print("error in declaration of \"{s}\", undeclared constructor in pattern: ", .{getId(cs.current_id)});
    const stdout_val = getStdout();
    out(stdout_val, x);
    _ = word.print("\n", .{});
    return NIL;
}

pub fn abstr(x: Word, e: Word) Word {
    switch (getTag(e)) {
        TCONS, PAIR, CONS => return liscomb(abstr(x, h(e)), abstr(x, t(e))),
        AP => {
            if (h(e) == BADCASE or h(e) == CONFERROR) {
                return ap(K, e);
            }
            return combine(abstr(x, h(e)), abstr(x, t(e)));
        },
        LAMBDA, LET, LETREC, TRIES, LABEL, SHOW, LEXER, SHARE => {
            std.debug.print("impossible event in abstr (main.tag={d})\n", .{getTag(e)});
            abi.exit(1);
        },
        else => {
            if (x == e or (isTypeVariable(x) and isTypeVariable(e) and getTypeVariable(x) == getTypeVariable(e))) {
                return I;
            }
            return ap(K, e);
        },
    }
}

pub fn abstrlist(x_input: Word, e: Word) Word {
    switch (getTag(e)) {
        TCONS, PAIR, CONS => return liscomb(abstrlist(x_input, h(e)), abstrlist(x_input, t(e))),
        AP => {
            if (h(e) == BADCASE or h(e) == CONFERROR) {
                return ap(K, e);
            }
            return combine(abstrlist(x_input, h(e)), abstrlist(x_input, t(e)));
        },
        LAMBDA, LET, LETREC, TRIES, LABEL, SHOW, LEXER, SHARE => {
            std.debug.print("impossible event in abstrlist (main.tag={d})\n", .{getTag(e)});
            abi.exit(1);
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

pub fn scanpattern(p: Word, x: Word, e: Word, fail: Word) Word {
    if (h(x) == CONST or isConstructor(x)) {
        return NIL;
    }
    if (getTag(x) == ID) {
        const binding = cons(x, ap2(TRY, ap(lambda(p, x), e), fail));
        return cons(binding, NIL);
    }
    if (isNPlusKPattern(x)) {
        return scanpattern(p, t(x), e, fail);
    }
    return shunt(scanpattern(p, h(x), e, fail), scanpattern(p, t(x), e, fail));
}

pub fn mklazy(d: Word) Word {
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

pub fn new_mklazy(d: Word) Word {
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
    e = transzf(e, hold, if (diag != 0) main.rs.diagonalise else main.rs.concat);
    if (diag != 0) {
        while (r != 0) {
            r -= 1;
            e = ap(main.rs.concat, e);
        }
    }
    return if (e == g1) ap2(APPEND, NIL, e) else e;
}

pub fn transzf(e_input: Word, qq_input: Word, conc: Word) Word {
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
        if (conc == main.rs.concat) {
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
    var s = cs.speclocs;
    while (s != NIL and h(h(s)) != x) {
        s = t(s);
    }
    return if (s == NIL) idWho(x) else t(h(s));
}

pub fn transtypeid(x: Word) Word {
    const n = getId(x);
    if (strcmp(n, "bool") == 0) return bool_t;
    if (strcmp(n, "num") == 0) return num_t;
    if (strcmp(n, "char") == 0) return char_t;
    return x;
}

export fn genlhs(x: Word) Word {
    switch (getTag(x)) {
        AP => {
            if (getTag(h(x)) == AP and h(h(x)) == PLUS and isnat(t(x)) != 0) {
                return ap2(PLUS, t(x), genlhs(t(h(x))));
            }
            const hold = genlhs(h(x));
            return make(AP, hold, genlhs(t(x)));
        },
        CONS, TCONS, PAIR => {
            const hold = genlhs(h(x));
            return make(getTag(x), hold, genlhs(t(x)));
        },
        ID => {
            if (member(ls.idsused, x) != 0) {
                return cons(CONST, x);
            }
            if (!isConstructor(x)) {
                ls.idsused = cons(x, ls.idsused);
            }
            return x;
        },
        INT => return cons(CONST, x),
        DOUBLE => {
            syntax("floating point literal in pattern\n");
            return main.nill;
        },
        ATOM => {
            if (x == True or x == False or x == NILS or x == NIL or isChar(x)) {
                return cons(CONST, x);
            }
        },
        else => {},
    }
    syntax("illegal form on left of <-\n");
    return main.nill;
}

pub fn leftfactor(x: Word) Word {
    var a: Word = undefined;
    var b: Word = undefined;
    var rhs = t(h(x));
    var d: Word = undefined;
    if (getTag(rhs) == AP and getTag(h(rhs)) == AP and h(h(rhs)) == G_SEQ) {
        a = t(h(rhs));
        b = t(rhs);
    } else {
        return x;
    }
    d = t(x);
    if (same(a, d) != 0) {
        hp(x).* = ap(G_SEQ, a);
        tp(x).* = ap2(G_ALT, b, G_UNIT);
        cs.lfrule += 1;
        return x;
    }
    if (getTag(d) == AP and getTag(h(d)) == AP) {
        rhs = h(h(d));
    } else {
        return x;
    }
    if (rhs == G_SEQ and same(a, t(h(d))) != 0) {
        rhs = t(d);
        hp(x).* = ap(G_SEQ, a);
        tp(x).* = leftfactor(ap2(G_ALT, b, rhs));
        cs.lfrule += 1;
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
        cs.lfrule += 1;
        return leftfactor(x);
    }
    if (getTag(rhs) == AP and getTag(h(rhs)) == AP and h(h(rhs)) == G_SEQ and same(a, t(h(rhs))) != 0) {
        rhs = t(rhs);
        d = t(d);
        hp(x).* = ap(G_ALT, ap2(G_SEQ, a, leftfactor(ap2(G_ALT, b, rhs))));
        tp(x).* = d;
        cs.lfrule += 1;
        return leftfactor(x);
    }
    return x;
}

pub fn translet(d: Word, e: Word) Word {
    const x = mklazy(d);
    return ap(abstract(dlhs(x), codegen(e)), codegen(dval(x)));
}

pub fn transletrec(input_dd: Word, e: Word) Word {
    var dd = input_dd;
    var lhs: Word = NIL;
    var rhs: Word = NIL;
    var pn: Word = 1;
    while (dd != NIL) : (dd = t(dd)) {
        var x = h(dd);
        if (getTag(dlhs(x)) == ID) {
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

pub fn transtries(id: Word, input_x: Word) Word {
    var x = input_x;
    var info: Word = 0;
    var earliest: Word = 0;
    var r: Word = undefined;
    if (fallible(h(x)) != 0) {
        const oldn = if (getTag(id) == ID) datapair(@as(Word, @intCast(@intFromPtr(getId(id)))), 0) else 0;
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

pub fn makeshow(here: Word, type_node: Word) Word {
    cs.was_poly = 0;
    const f = mkshow(0, 0, type_node);
    if (here != 0 and cs.was_poly != 0) {
        _ = word.print("type error in definition of {s}\n", .{getId(cs.current_id)});
        sayhere(here, 0);
        _ = word.print(" use of \"show\" at polymorphic type ", .{});
        out_type(redtvars(type_node));
        _ = word.putchar('\n');
        setIdType(cs.current_id, wrong_t);
        setIdVal(cs.current_id, UNDEF);
        cs.polyshowerror = 1;
        cs.ND = add1(cs.current_id, cs.ND);
        cs.was_poly = 0;
    }
    return f;
}

export fn mkshow(s: Word, p: Word, input_t: Word) Word {
    var args: Word = NIL;
    var type_node = input_t;
    while (getTag(type_node) == AP) {
        args = cons(t(type_node), args);
        type_node = h(type_node);
    }
    switch (type_node) {
        num_t => return if (p != 0) main.rs.shownum1 else SHOWNUM,
        bool_t => return main.rs.showbool,
        char_t => return main.rs.showchar,
        list_t => {
            if (h(args) == char_t) {
                return main.rs.showstring;
            }
            return ap(main.rs.showlist, mkshow(s, 0, h(args)));
        },
        comma_t => return ap(main.rs.showparen, ap2(main.rs.showpair, mkshow(s, 0, h(args)), mkshowt(s, h(t(args))))),
        void_t => return main.rs.showvoid,
        arrow_t => return main.rs.showfunction,
        else => {
            if (getTag(type_node) == ID) {
                var r = typeShowFn(type_node);
                if (r == 0) {
                    return main.rs.showabstract;
                }
                if (r == main.rs.showwhat) {
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
                cs.was_poly = 1;
                return main.rs.showwhat;
            }
            if (getTag(type_node) == STRCONS) {
                _ = word.print("warning - mkshow applied to suppressed type\n", .{});
                return main.rs.showwhat;
            }
            _ = word.print("impossible event in mkshow (", .{});
            out_type(type_node);
            _ = word.print(")\n", .{});
            return main.rs.showwhat;
        },
    }
}

pub fn mkshowt(s: Word, type_tuple: Word) Word {
    if (t(type_tuple) == void_t) {
        return mkshow(s, 0, t(h(type_tuple)));
    }
    return ap2(main.rs.showpair, mkshow(s, 0, t(h(type_tuple))), mkshowt(s, t(type_tuple)));
}

fn nclchk(n: Word, p: Word, hr: Word) c_int {
    if (h(p) == CONST) {
        return 0;
    }
    if (getTag(p) == ID) {
        if (n != p) {
            return 0;
        }
        if (main.rs.echoing != 0) {
            _ = word.putchar('\n');
        }
        main.errs = hr;
        _ = word.print("syntax error: conflicting definitions of \"{s}\" in where clause\n", .{getId(n)});
        acterror();
        return 1;
    }
    if (getTag(p) == AP and h(p) == PLUS) {
        return 0;
    }
    if (nclchk(n, h(p), hr) != 0) {
        return 1;
    }
    return nclchk(n, t(p), hr);
}

pub fn nclashcheck(n: Word, input_dd: Word, hr: Word) void {
    var dd = input_dd;
    while (dd != NIL and nclchk(n, dlhs(h(dd)), hr) == 0) {
        dd = t(dd);
    }
}

pub fn respec_error(x: Word) void {
    if (main.rs.echoing != 0) {
        _ = word.putchar('\n');
    }
    const suffix: [*:0]const u8 = if (member(main.rs.primenv, x) != 0) " (in standard environment)" else "";
    _ = word.print("syntax error: type of \"{s}\" already declared{s}\n", .{ getId(x), suffix });
    acterror();
}

pub fn nameclash(x: Word) void {
    if (main.rs.echoing != 0) {
        _ = word.putchar('\n');
    }
    const suffix: [*:0]const u8 = if (member(main.rs.primenv, x) != 0) " (in standard environment)" else "";
    _ = word.print("syntax error: nameclash, \"{s}\" already defined{s}\n", .{ getId(x), suffix });
    acterror();
}

export fn declconstr(x: Word, n: Word, constr_type: Word) void {
    setIdVal(x, constructor(n, x));
    if ((n >> 16) != 0) {
        syntax("algebraic type has too many constructors\n");
        return;
    }
    if (idType(x) != undef_t) {
        main.errs = idWho(x);
        respec_error(x);
        return;
    }
    addToEnv(x);
    setIdType(x, constr_type);
}

export fn specify(input_x: Word, spec_type: Word, here: Word) void {
    var x = input_x;
    if (getTag(x) != ID and spec_type != type_t) {
        main.errs = here;
        syntax("incorrect use of ::\n");
        return;
    }
    if (spec_type == type_t) {
        var arity: Word = 0;
        while (getTag(x) == AP) {
            arity += 1;
            x = h(x);
        }
        if (!(idVal(x) == UNDEF and idType(x) == undef_t)) {
            main.errs = here;
            nameclash(x);
            return;
        }
        setIdType(x, type_t);
        if (idWho(x) == NIL) {
            setIdWho(x, here);
        }
        setIdVal(x, makeTyp(arity, main.rs.showwhat, placeholder_t, NIL));
        addToEnv(x);
        cs.newtyps = add1(x, cs.newtyps);
        return;
    }
    if (idType(x) != undef_t) {
        main.errs = here;
        respec_error(x);
        return;
    }
    setIdType(x, spec_type);
    if (idWho(x) == NIL) {
        setIdWho(x, here);
    } else {
        cs.speclocs = cons(cons(x, here), cs.speclocs);
    }
    if (idVal(x) == UNDEF) {
        addToEnv(x);
    }
}

fn arityCheck(type_name: Word, arity: Word, here: Word) void {
    if (typeArity(type_name) != arity) {
        const prefix: [*:0]const u8 = if (main.rs.echoing != 0) "\n" else "";
        _ = word.print("{s}syntax error: wrong number of parameters for typename \"{s}\" ({d} expected)\n", .{
            prefix,
            getId(type_name),
            typeArity(type_name),
        });
        main.errs = here;
        acterror();
    }
}

export fn decl_type(input_tf: Word, type_class: Word, info: Word, here: Word) void {
    var tf = input_tf;
    var arity: Word = 0;
    while (getTag(tf) == AP) {
        arity += 1;
        tf = h(tf);
    }
    if (type_class == synonym_t and idType(tf) == type_t and typeClass(tf) == abstract_t and typeInfo(tf) == undef_t) {
        arityCheck(tf, arity, here);
        setIdWho(tf, here);
        setTypeInfo(tf, info);
        return;
    }
    if (type_class == abstract_t and idType(tf) == type_t and typeClass(tf) == synonym_t) {
        arityCheck(tf, arity, here);
        setTypeClass(tf, abstract_t);
        return;
    }
    if (idVal(tf) != UNDEF) {
        main.errs = here;
        nameclash(tf);
        return;
    }
    if (type_class != synonym_t) {
        cs.newtyps = add1(tf, cs.newtyps);
    }
    setIdVal(tf, makeTyp(arity, if (type_class == algebraic_t) make_pn(UNDEF) else 0, type_class, info));
    if (idType(tf) != undef_t) {
        main.errs = here;
        respec_error(tf);
        return;
    }
    addToEnv(tf);
    setIdWho(tf, here);
    setIdType(tf, type_t);
}

fn decl1(x: Word, e: Word) void {
    if (idVal(x) != UNDEF and main.rs.lastname != x) {
        main.errs = h(e);
        nameclash(x);
        return;
    }
    if (idVal(x) == UNDEF) {
        setIdVal(x, tries(x, cons(e, NIL)));
        if (idWho(x) != NIL) {
            cs.speclocs = cons(cons(x, idWho(x)), cs.speclocs);
        }
        setIdWho(x, h(e));
        if (idType(x) == undef_t) {
            addToEnv(x);
        }
    } else if (fallible(h(t(idVal(x)))) == 0) {
        const prefix: [*:0]const u8 = if (main.rs.echoing != 0) "\n" else "";
        main.errs = h(e);
        _ = word.print("{s}syntax error: unreachable case in defn of \"{s}\"\n", .{ prefix, getId(x) });
        acterror();
    } else {
        tp(idVal(x)).* = cons(e, t(idVal(x)));
    }
}

export fn declare(x: Word, e: Word) void {
    if (getTag(x) == ID and !isConstructor(x)) {
        decl1(x, e);
        return;
    }
    var bindings = scanpattern(x, x, share(tries(x, cons(e, NIL)), undef_t), ap(CONFERROR, cons(x, h(e))));
    if (bindings == NIL) {
        main.errs = h(e);
        syntax("illegal lhs for definition\n");
        return;
    }
    main.rs.lastname = 0;
    while (bindings != NIL) {
        const binding = h(bindings);
        const name = h(binding);
        if (idVal(name) != UNDEF) {
            main.errs = h(e);
            nameclash(name);
            return;
        }
        setIdVal(name, t(binding));
        if (idWho(name) != NIL) {
            cs.speclocs = cons(cons(name, idWho(name)), cs.speclocs);
        }
        setIdWho(name, h(e));
        if (idType(name) == undef_t) {
            addToEnv(name);
        }
        bindings = t(bindings);
    }
}

export fn block(input_defs: Word, input_e: Word, keep: Word) Word {
    var defs = input_defs;
    var e = input_e;
    var ids: Word = NIL;
    var deftoids: Word = NIL;
    var g: Word = NIL;
    if (main.SYNERR != 0) {
        return NIL;
    }
    var d = defs;
    while (d != NIL) : (d = t(d)) {
        const x = get_ids(dlhs(h(d)));
        ids = UNION(ids, x);
        deftoids = cons(cons(h(d), x), deftoids);
    }
    defs = sort(defs);
    d = defs;
    while (d != NIL) : (d = t(d)) {
        var x = intersection(deps(dval(h(d))), ids);
        var y: Word = NIL;
        while (x != NIL) : (x = t(x)) {
            y = add1(invgetrel(deftoids, h(x)), y);
        }
        g = cons(cons(h(d), add1(h(d), y)), g);
    }
    g = reverse(g);
    g = tclos(g);
    {
        var x = intersection(deps(e), ids);
        var y: Word = NIL;
        while (x != NIL) : (x = t(x)) {
            d = invgetrel(deftoids, h(x));
            if (member(y, d) == 0) {
                y = UNION(y, getrel(g, d));
            }
        }
        defs = setdiff(defs, y);
        if (defs != NIL) {
            main.rs.detrop = append1(main.rs.detrop, defs);
        }
        if (keep != 0) {
            return letrec(y, e);
        }
    }
    g = msc(g);
    g = tsort(g);
    g = reverse(g);
    while (g != NIL) : (g = t(g)) {
        if (t(h(g)) == NIL and intersection(get_ids(dlhs(h(h(g)))), deps(dval(h(h(g))))) == NIL) {
            e = let(h(h(g)), e);
        } else {
            e = letrec(h(g), e);
        }
    }
    return e;
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

pub fn getrel(input_r: Word, x: Word) Word {
    var r = input_r;
    while (r != NIL and h(h(r)) != x) r = t(r);
    return if (r == NIL) NIL else t(h(r));
}

pub fn invgetrel(input_r: Word, x: Word) Word {
    var r = input_r;
    while (r != NIL and member(t(h(r)), x) == 0) r = t(r);
    if (r == NIL) {
        std.debug.print("impossible event in invgetrel\n", .{});
        abi.exit(1);
    }
    return h(h(r));
}

pub fn imageless(input_r: Word, input_y: Word, z: Word) Word {
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

pub fn less(input_x: Word, input_y: Word) Word {
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

pub fn less1(input_x: Word, a: Word) Word {
    var x = input_x;
    var r: Word = NIL;
    while (x != NIL and h(x) != a) {
        r = cons(h(x), r);
        x = t(x);
    }
    return shunt(r, if (x == NIL) NIL else t(x));
}

pub fn sort(input_x: Word) Word {
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

const Ush: Word = CMBASE + 93;
const Ush1: Word = CMBASE + 94;
const LEX_RPT: Word = CMBASE + 112;
const LEX_RPT1: Word = CMBASE + 113;
const LEX_TRY: Word = CMBASE + 114;
const LEX_TRY1: Word = CMBASE + 116;

extern fn mklexvar(i: Word) Word;
extern fn ispoly(t_val: Word) c_int;

fn isarrow_t(type_node: Word) bool {
    return getTag(type_node) == AP and getTag(h(type_node)) == AP and h(h(type_node)) == arrow_t;
}
fn iscomma_t(type_node: Word) bool {
    return getTag(type_node) == AP and getTag(h(type_node)) == AP and h(h(type_node)) == comma_t;
}
fn islist_t(type_node: Word) bool {
    return getTag(type_node) == AP and h(type_node) == list_t;
}
fn isvar_t(type_node: Word) bool {
    return getTag(type_node) == TVAR;
}
fn iscompound_t(type_node: Word) bool {
    return getTag(type_node) == AP;
}

fn t_showfn(x: Word) Word {
    return t(h(t(x)));
}
fn t_class(x: Word) Word {
    return h(t(t(x)));
}
fn t_info(x: Word) Word {
    return t(t(t(x)));
}

fn isconstructor(x: Word) bool {
    return getTag(x) == ID and isconstrname(getId(x)) != 0;
}
fn isvariable(x: Word) bool {
    return getTag(x) == ID and isconstrname(getId(x)) == 0;
}

fn get_pn(x: Word) Word {
    return h(x);
}
fn pn_val(x: Word) Word {
    return t(x);
}

fn sui_generis(k: Word) bool {
    return member(cs.SGC, k) != 0;
}

pub export fn codegen(x: Word) Word {
    switch (getTag(x)) {
        AP => {
            if (main.commandmode != 0 // beware of corrupting lastexp
            and x != ls.cook_stdin and x != ls.common_stdin and x != ls.common_stdinb) { // but share $+ $-
                return make(AP, codegen(h(x)), codegen(t(x)));
            }
            if (getTag(h(x)) == AP and h(h(x)) == APPEND and t(h(x)) == NIL) {
                return codegen(t(x)); // post typecheck reversal of HR bug fix
            }
            hp(x).* = codegen(h(x));
            tp(x).* = codegen(t(x));
            // otherwise do in situ
            return if (getTag(h(x)) == AP and h(h(x)) == G_ALT) leftfactor(x) else x;
        },
        TCONS, PAIR => {
            return make(CONS, codegen(h(x)), codegen(t(x)));
        },
        CONS => {
            if (main.commandmode != 0) {
                return make(CONS, codegen(h(x)), codegen(t(x)));
            }
            // otherwise do in situ (see declare)
            hp(x).* = codegen(h(x));
            tp(x).* = codegen(t(x));
            return x;
        },
        LAMBDA => {
            return abstract(h(x), codegen(t(x)));
        },
        LET => {
            return translet(h(x), t(x));
        },
        LETREC => {
            return transletrec(h(x), t(x));
        },
        TRIES => {
            return transtries(h(x), t(x));
        },
        LABEL => {
            return codegen(t(x));
        },
        SHOW => {
            return makeshow(h(x), t(x));
        },
        LEXER => {
            var r: Word = NIL;
            var uses_state: Word = 0;
            var cur_x = x;
            while (cur_x != NIL) {
                var rule = abstr(mklexvar(0), codegen(t(t(h(cur_x)))));
                rule = abstr(mklexvar(1), rule);
                if (!(getTag(rule) == AP and h(rule) == K)) {
                    uses_state = 1;
                }
                r = cons(cons(h(h(cur_x)), // start condition stuff
                    cons(ap(h(t(h(cur_x))), NIL), // matcher []
                        rule)), r);
                cur_x = t(cur_x);
            }
            if (uses_state == 0) { // strip off (K -) from each rule
                var cur_y = r;
                while (cur_y != NIL) {
                    tp(t(h(cur_y))).* = t(t(t(h(cur_y))));
                    cur_y = t(cur_y);
                }
                r = ap(LEX_RPT, ap(LEX_TRY, r));
            } else {
                r = ap(LEX_RPT1, ap(LEX_TRY1, r));
            }
            return ap(r, 0); // 0 startcond
        },
        STARTREADVALS => {
            if (ispoly(t(x)) != 0) {
                const name_str: [*:0]const u8 = if (ls.cook_stdin != 0 and x == h(ls.cook_stdin)) "$+" else "readvals or $+";
                _ = word.print("type error - {s} used at polymorphic type :: [", .{name_str});
                out_type(redtvars(t(x)));
                _ = word.print("]\n", .{});
                cs.polyshowerror = 1;
                if (cs.current_id != 0) {
                    cs.ND = add1(cs.current_id, cs.ND);
                    setIdType(cs.current_id, wrong_t);
                    setIdVal(cs.current_id, UNDEF);
                }
                if (h(x) != 0) {
                    sayhere(h(x), 1);
                }
            }
            if (main.commandmode != 0) {
                main.rs.rv_expr = 1;
            } else {
                cs.rv_script = 1;
            }
            return x;
        },
        SHARE => {
            if (t(x) != -1) { // arbitrary flag for already visited
                hp(x).* = codegen(h(x));
                tp(x).* = -1;
            }
            return h(x);
        },
        else => {
            if (x == NILS) {
                return NIL;
            }
            return x; // identifier, private name, or constant
        },
    }
}

export fn genshfns() void {
    var s = cs.newtyps;
    while (s != NIL) {
        if (t_class(h(s)) == algebraic_t) {
            var f: Word = 0;
            var r = t_info(h(s)); // r is list of constructors
            const ush = if (t(r) == NIL and member(cs.SGC, h(r)) != 0) Ush1 else Ush;
            while (r != NIL) {
                var type_var = idType(h(r));
                var k = idVal(h(r));
                while (getTag(k) != CONSTRUCTOR) {
                    k = t(k); // lawful and !'d constructors
                }
                // k now holds constructor(i,main.hd(r))
                while (isarrow_t(type_var)) {
                    k = ap(k, mkshow(1, 1, t(h(type_var))));
                    type_var = t(type_var);
                }
                k = ap(ush, k);
                while (iscompound_t(type_var)) {
                    k = abstr(t(type_var), k);
                    type_var = h(type_var);
                }
                // see kahrs.bug.m (this is the fix)
                if (f != 0) {
                    f = ap2(TRY, k, f);
                } else {
                    f = k;
                }
                r = t(r);
            }
            // f ~= 0, placeholder types dealt with in specify()
            tp(t_showfn(h(s))).* = f;
            cs.algshfns = cons(t_showfn(h(s)), cs.algshfns);
        } else if (t_class(h(s)) == abstract_t) {
            if (t_showfn(h(s)) != 0) {
                if (abshfnck(h(s), idType(t_showfn(h(s)))) == 0) {
                    _ = word.print("warning - \"{s}\" has type inappropriate for a show-function\n", .{getId(t_showfn(h(s)))});
                    tp(t_showfn(h(s))).* = 0;
                }
            }
        }
        s = t(s);
    }
}
