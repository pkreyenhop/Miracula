const Word = c_long;

const CONS: u8 = 11;
const CMBASE: Word = 306;
const NIL: Word = CMBASE + 138;

extern var hd: [*]Word;
extern var tl: [*]Word;
extern var NEW: Word;

extern fn make(t: u8, x: Word, y: Word) Word;
extern fn reverse(x: Word) Word;

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

export fn remove1(e: Word, ss: *Word) Word {
    var p = ss;
    while (p.* != NIL and h(p.*) < e) {
        p = tp(p.*);
    }
    if (p.* == NIL or h(p.*) != e) {
        return 0;
    }
    p.* = t(p.*);
    return 1;
}

export fn setdiff(s1_input: Word, s2_input: Word) Word {
    var s1 = s1_input;
    var s2 = s2_input;
    var ss1 = &s1;
    while (ss1.* != NIL and s2 != NIL) {
        if (h(ss1.*) == h(s2)) {
            ss1.* = t(ss1.*);
        } else if (h(ss1.*) < h(s2)) {
            ss1 = tp(ss1.*);
        } else {
            s2 = t(s2);
        }
    }
    return s1;
}

export fn add1(e: Word, s_input: Word) Word {
    var s = s_input;
    if (s == NIL or e < h(s)) {
        return cons(e, s);
    }
    if (e == h(s)) {
        return s;
    }
    while (t(s) != NIL and e > h(t(s))) {
        s = t(s);
    }
    if (t(s) == NIL) {
        tp(s).* = cons(e, NIL);
    } else if (e != h(t(s))) {
        tp(s).* = cons(e, t(s));
    }
    return s_input;
}

export fn newadd1(e: Word, s_input: Word) Word {
    var s = s_input;
    NEW = 1;
    if (s == NIL or e < h(s)) {
        return cons(e, s);
    }
    if (e == h(s)) {
        NEW = 0;
        return s;
    }
    while (t(s) != NIL and e > h(t(s))) {
        s = t(s);
    }
    if (t(s) == NIL) {
        tp(s).* = cons(e, NIL);
    } else if (e != h(t(s))) {
        tp(s).* = cons(e, t(s));
    } else {
        NEW = 0;
    }
    return s_input;
}

export fn UNION(s1_input: Word, s2_input: Word) Word {
    var s1 = s1_input;
    var s2 = s2_input;
    var ss = &s1;
    while (ss.* != NIL and s2 != NIL) {
        if (h(ss.*) == h(s2)) {
            ss = tp(ss.*);
            s2 = t(s2);
        } else if (h(ss.*) < h(s2)) {
            ss = tp(ss.*);
        } else {
            ss.* = cons(h(s2), ss.*);
            ss = tp(ss.*);
            s2 = t(s2);
        }
    }
    if (ss.* == NIL) {
        while (s2 != NIL) {
            ss.* = cons(h(s2), ss.*);
            ss = tp(ss.*);
            s2 = t(s2);
        }
    }
    return s1;
}

export fn intersection(s1_input: Word, s2_input: Word) Word {
    var s1 = s1_input;
    var s2 = s2_input;
    var r: Word = NIL;
    while (s1 != NIL and s2 != NIL) {
        if (h(s1) == h(s2)) {
            r = cons(h(s1), r);
            s1 = t(s1);
            s2 = t(s2);
        } else if (h(s1) < h(s2)) {
            s1 = t(s1);
        } else {
            s2 = t(s2);
        }
    }
    return reverse(r);
}

export fn member(s_input: Word, x: Word) Word {
    var s = s_input;
    while (s != NIL and x != h(s)) {
        s = t(s);
    }
    return if (s != NIL) 1 else 0;
}
