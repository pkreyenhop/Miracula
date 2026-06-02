const std = @import("std");

const c = @cImport({
    @cInclude("stdlib.h");
});

const Word = c_long;
const GENERATOR: Word = 0;
const REPEAT: Word = 2;
const ATOM: u8 = 0;
const TVAR: u8 = 4;
const INT: u8 = 5;
const CONSTRUCTOR: u8 = 6;
const STRCONS: u8 = 7;
const ID: u8 = 8;
const AP: u8 = 9;
const LAMBDA: u8 = 10;
const CONS: u8 = 11;
const LABEL: u8 = 13;
const LET: u8 = 16;
const LETREC: u8 = 17;
const PAIR: u8 = 20;
const CMBASE: Word = 306;
const COND: Word = CMBASE + 16;
const PLUS: Word = CMBASE + 54;
const FAIL: Word = CMBASE + 135;
const NIL: Word = CMBASE + 138;
const CONST: Word = 268;

extern var hd: [*]Word;
extern var tl: [*]Word;
extern var tag: [*]u8;
extern var SGC: Word;

extern fn make(t: u8, x: Word, y: Word) Word;
extern fn reverse(x: Word) Word;
extern fn shunt(x: Word, y: Word) Word;
extern fn member(s: Word, x: Word) Word;
extern fn UNION(s1: Word, s2: Word) Word;
extern fn isconstrname(a: [*:0]const u8) c_int;

fn h(x: Word) Word {
    return hd[@as(usize, @intCast(x)) * 2];
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

fn getId(x: Word) [*:0]const u8 {
    return @ptrFromInt(@as(usize, @intCast(h(h(h(x))))));
}

fn isConstructor(x: Word) bool {
    return tag[@intCast(x)] == ID and isconstrname(getId(x)) != 0;
}

fn isNPlusKPattern(x: Word) bool {
    return tag[@intCast(x)] == AP and tag[@intCast(h(x))] == AP and h(h(x)) == PLUS;
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
