const std = @import("std");
const c = @cImport({
    @cInclude("stdlib.h");
    @cInclude("stdio.h");
    @cInclude("setjmp.h");
    @cInclude("data.h");
    @cInclude("combs.h");
});

const Word = c_long;
const CMBASE: Word = 306;
const NIL: Word = CMBASE + 138;
const ATOMLIMIT: Word = CMBASE + 141;

extern var hd: [*]Word;
extern var tl: [*]Word;
extern var tag: [*]u8;
export var NEW: Word = 0;
export var TYPERRS: Word = 0;
export var current_id: Word = 0;
export var NT: Word = 306 + 138; // CMBASE + 138 is NIL
export var ND: Word = 306 + 138; // CMBASE + 138 is NIL
extern var fnts: Word;
export var lineptr: Word = 0;
extern var current_script: [*:0]const u8;
extern var errs: Word;
extern var errline: Word;
extern var nill: Word;
extern var compiling: c_int;
extern var commandmode: Word;

export var R: Word = 306 + 138; // CMBASE + 138 is NIL
export var SBND: Word = 306 + 138; // CMBASE + 138 is NIL
export var FBS: Word = 306 + 138; // CMBASE + 138 is NIL
export var ATNAMES: Word = 0;
extern var files: Word;
extern var SYNERR: Word;
export var TABSTRS: Word = 306 + 138; // CMBASE + 138 is NIL
export var bnf_t: Word = 0;

extern var freeids: Word;
extern var rfl: Word;
extern var col_fn: Word;

extern fn make(t: u8, x: Word, y: Word) Word;
extern fn reverse(x: Word) Word;
extern fn getspecloc(x_node: Word) Word;
extern fn codegen(x: Word) Word;
extern fn findid(s: [*:0]const u8) Word;
extern fn mktuple(x: Word) Word;
extern fn tclos(r: Word) Word;
extern fn sortrel(x: Word) Word;
extern fn genshfns() void;
extern fn alfasort(x: Word) Word;
extern fn readoption() void;
export var env1: c.jmp_buf = undefined;
export fn types_abort() noreturn {
    c.longjmp(&env1[0], 1);
}
extern fn out(f: *c.FILE, x: Word) void;
extern fn is_char(x: Word) c_int;
extern fn charname(ch: Word) [*:0]const u8;
extern fn size(x: Word) Word;
extern fn same(x: Word, y: Word) Word;
extern fn get_dbl(x: Word) f64;
extern fn lastlink(x: Word) Word;
extern fn isconstrname(s: [*:0]const u8) c_int;

fn h(x: Word) Word {
    if (x < ATOMLIMIT) return 0;
    return hd[@as(usize, @intCast(x)) * 2];
}

fn hp(x: Word) *Word {
    std.debug.assert(x >= ATOMLIMIT);
    return &hd[@as(usize, @intCast(x)) * 2];
}

fn t(x: Word) Word {
    if (x < ATOMLIMIT) return 0;
    return tl[@as(usize, @intCast(x)) * 2];
}

fn tp(x: Word) *Word {
    std.debug.assert(x >= ATOMLIMIT);
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

const type_t: Word = 10;
extern fn shunt(x: Word, y: Word) Word;

fn idType(x: Word) Word {
    return t(h(x));
}

export fn typesfirst(input_x: Word) Word {
    var x = input_x;
    var y = &x;
    var z: Word = NIL;
    while (y.* != NIL) {
        if (idType(h(y.*)) == type_t) {
            z = cons(h(y.*), z);
            y.* = t(y.*);
        } else {
            y = tp(y.*);
        }
    }
    return shunt(z, x);
}



fn getStderr() ?*c.FILE {
    const T = @TypeOf(c.stderr);
    if (comptime @typeInfo(T) == .@"fn") {
        return c.stderr();
    } else if (comptime @typeInfo(T) == .pointer and @typeInfo(@typeInfo(T).pointer.child) == .@"fn") {
        return c.stderr();
    } else {
        return c.stderr;
    }
}

export fn tsort(g_input: Word) Word {
    var NP = NIL; // NP is set of elements with no predecessor
    var g1 = g_input;
    var r = NIL; // r is result
    var g = NIL;
    while (g1 != NIL) {
        if (t(h(g1)) == NIL) {
            NP = cons(h(h(g1)), NP);
        } else {
            g = cons(h(g1), g);
        }
        g1 = t(g1);
    }
    while (NP != NIL) {
        var D = NIL; // ids to be removed from range of g
        while (NP != NIL) {
            r = cons(h(NP), r);
            if (tag[@intCast(h(NP))] == ID) {
                D = add1(h(NP), D);
            } else {
                D = UNION(D, h(NP));
            }
            NP = t(NP);
        }
        g1 = g;
        g = NIL;
        while (g1 != NIL) {
            const rhs = setdiff(t(h(g1)), D);
            if (rhs == NIL) {
                NP = cons(h(h(g1)), NP);
            } else {
                tp(h(g1)).* = rhs;
                g = cons(h(g1), g);
            }
            g1 = t(g1);
        }
    }
    if (g != NIL) {
        _ = c.fprintf(getStderr(), "error: impossible event in tsort\n");
    }
    return reverse(r);
}

export fn msc(R_input: Word) Word {
    var R1 = R_input;
    while (R1 != NIL) {
        var r = tp(h(R1)); // word *r = &tl(hd(R1))
        const l = h(h(R1)); // word l = hd(hd(R1))
        if (remove1(l, r) != 0) {
            hp(h(R1)).* = cons(l, NIL); // hd(hd(R1)) = cons(l, NIL)
            while (r.* != NIL) {
                const n = h(r.*);
                var R2 = tp(R1); // word *R2 = &tl(R1)
                while (R2.* != NIL and h(h(R2.*)) != n) {
                    R2 = tp(R2.*);
                }
                if (R2.* != NIL and member(t(h(R2.*)), l) != 0) {
                    r.* = t(r.*); // *r = tl(*r)
                    R2.* = t(R2.*); // *R2 = tl(*R2)
                    hp(h(R1)).* = add1(n, h(h(R1)));
                } else {
                    r = tp(r.*);
                }
            }
        }
        R1 = t(R1);
    }
    return R_input;
}

const ATOM: u8 = 0;
const DOUBLE: u8 = 1;
const DATAPAIR: u8 = 2;
const FILEINFO: u8 = 3;
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
const UNICODE: u8 = 21;
const TCONS: u8 = 22;

const undef_t: Word = 0;
const bool_t: Word = 1;
const num_t: Word = 2;
const char_t: Word = 3;
const list_t: Word = 4;
const synonym_t: Word = 1;
const abstract_t: Word = 2;
const UNDEF: Word = CMBASE + 140;

fn iscompound_t(type_node: Word) bool {
    return tag[@intCast(type_node)] == AP;
}
fn isvar_t(type_node: Word) bool {
    return tag[@intCast(type_node)] == TVAR;
}

fn t_arity(x: Word) Word {
    return h(h(t(x)));
}
fn t_class(x: Word) Word {
    return h(t(t(x)));
}
fn t_info(x: Word) Word {
    return t(t(t(x)));
}
fn t_showfn(x: Word) Word {
    return t(h(t(x)));
}

fn idVal(x: Word) Word {
    return t(x);
}
fn idWho(x: Word) Word {
    return t(h(h(x)));
}

fn getId(x: Word) [*:0]const u8 {
    return @ptrFromInt(@as(usize, @intCast(h(h(h(x))))));
}

export var meta_pending: Word = NIL;

export fn sterilise(t_val: Word) void {
    if (tag[@intCast(t_val)] == AP) {
        hp(t_val).* = list_t;
        tp(t_val).* = num_t;
    }
}

fn meta_tcheck(t_val: Word) Word {
    var tn = t_val;
    var i: Word = 0;
    while (iscompound_t(tn)) {
        tp(tn).* = meta_tcheck(t(tn));
        i += 1;
        tn = h(tn);
    }
    if (tag[@intCast(tn)] != STRCONS) {
        if (tag[@intCast(tn)] != ID) {
            if (i > 0 and (isvar_t(tn) or tn == bool_t or tn == num_t or tn == char_t)) {
                TYPERRS += 1;
                if (tag[@intCast(current_id)] == DATAPAIR) {
                    locate_inc();
                    _ = c.printf("badly formed type \"");
                    out_type(t_val);
                    _ = c.printf("\" in binding for \"%s\"\n", @as([*:0]const u8, @ptrFromInt(@as(usize, @intCast(h(current_id))))));
                    _ = c.printf("(");
                    out_type(tn);
                    _ = c.printf(" has zero arity)\n");
                } else {
                    _ = c.printf("badly formed type \"");
                    out_type(t_val);
                    const msg: [*:0]const u8 = if (idType(current_id) == type_t) "== binding" else "specification";
                    _ = c.printf("\" in %s for \"%s\"\n", msg, getId(current_id));
                    _ = c.printf("(");
                    out_type(tn);
                    _ = c.printf(" has zero arity)\n");
                    sayhere(getspecloc(current_id), 1);
                }
                sterilise(t_val);
            }
            return t_val;
        } else if (idType(tn) == undef_t and idVal(tn) == UNDEF) {
            TYPERRS += 1;
            if (member(NT, tn) == 0) {
                if (tag[@intCast(current_id)] == DATAPAIR) {
                    locate_inc();
                }
                _ = c.printf("undeclared typename \"%s\" ", getId(tn));
                if (tag[@intCast(current_id)] == DATAPAIR) {
                    _ = c.printf("in binding for %s\n", @as([*:0]const u8, @ptrFromInt(@as(usize, @intCast(h(current_id))))));
                } else {
                    sayhere(getspecloc(current_id), 1);
                }
                NT = add1(tn, NT);
            }
            return t_val;
        } else if (idType(tn) != type_t or t_arity(tn) != i) {
            TYPERRS += 1;
            if (tag[@intCast(current_id)] == DATAPAIR) {
                locate_inc();
                _ = c.printf("badly formed type \"");
                out_type(t_val);
                _ = c.printf("\" in binding for \"%s\"\n", @as([*:0]const u8, @ptrFromInt(@as(usize, @intCast(h(current_id))))));
            } else {
                _ = c.printf("badly formed type \"");
                out_type(t_val);
                const msg: [*:0]const u8 = if (idType(current_id) == type_t) "== binding" else "specification";
                _ = c.printf("\" in %s for \"%s\"\n", msg, getId(current_id));
            }
            if (idType(tn) != type_t) {
                _ = c.printf("(%s not defined as typename)\n", getId(tn));
            } else {
                _ = c.printf("(typename %s has arity %ld)\n", getId(tn), t_arity(tn));
            }
            if (tag[@intCast(current_id)] != DATAPAIR) {
                sayhere(getspecloc(current_id), 1);
            }
            sterilise(t_val);
            return t_val;
        }
    }

    if (t_class(tn) != synonym_t) {
        return t_val;
    }
    if (member(meta_pending, tn) != 0) {
        TYPERRS += 1; // report cycle
        if (tag[@intCast(current_id)] == DATAPAIR) {
            locate_inc();
        }
        const suffix: [*:0]const u8 = if (meta_pending == NIL) "" else "s";
        _ = c.printf("error: cycle in type \"==\" definition%s ", suffix);
        printelement(meta_pending);
        _ = c.printf("\n");
        if (tag[@intCast(current_id)] != DATAPAIR) {
            sayhere(idWho(tn), 1);
        }
        types_abort();
    }
    meta_pending = cons(tn, meta_pending);
    tn = NIL;
    var cur_t = t_val;
    while (iscompound_t(cur_t)) {
        tn = cons(t(cur_t), tn);
        cur_t = h(cur_t);
    }
    const res = meta_tcheck(ap_subst(t_info(cur_t), tn));
    meta_pending = t(meta_pending);
    return res;
}

export var SUBST: [hashsize]Word = [_]Word{0} ** hashsize;
export var tvmap: Word = NIL;
export var localtvmap: Word = NIL;
export var showchain: Word = NIL;

export var tvcount: Word = 1;

fn mktvar(i: Word) Word {
    return make(TVAR, 0, i);
}

fn gettvar(x: Word) Word {
    return t(x);
}

fn eqtvar(x: Word, y: Word) bool {
    return t(x) == t(y);
}

const hashsize: usize = 512;

fn hashval(x: Word) usize {
    return @intCast(@mod(gettvar(x), @as(Word, @intCast(hashsize))));
}

fn NTV() Word {
    const res = mktvar(tvcount);
    tvcount += 1;
    return res;
}

export fn clear_SUBST() Word {
    fixshows();
    @memset(&SUBST, 0);
    tvcount = 1;
    return 0;
}

export fn fixshows() void {
    while (showchain != NIL) {
        tp(h(showchain)).* = subst(t(h(showchain)));
        showchain = t(showchain);
    }
}

export fn lookup(tv: Word) Word {
    var h_val = SUBST[hashval(tv)];
    while (h_val != 0) {
        if (eqtvar(h(h(h_val)), tv)) {
            return t(h(h_val));
        }
        h_val = t(h_val);
    }
    return tv;
}

export fn addsubst(tv: Word, term: Word) void {
    const hv = hashval(tv);
    SUBST[hv] = cons(cons(tv, term), SUBST[hv]);
}

export fn ult(tv: Word) Word {
    const s = lookup(tv);
    return if (s == tv) tv else subst(s);
}

fn ap(x: Word, y: Word) Word {
    return make(AP, x, y);
}

fn walktype(term: Word, f: *const fn (Word) callconv(.c) Word) Word {
    if (isvar_t(term)) {
        return f(term);
    }
    if (iscompound_t(term)) {
        const h1 = walktype(h(term), f);
        const t1 = walktype(t(term), f);
        return if (h1 == h(term) and t1 == t(term)) term else ap(h1, t1);
    }
    return term;
}

export fn subst(term: Word) Word {
    return walktype(term, ult);
}

var NGT: Word = 0;

export fn lmap(tv: Word) Word {
    if (non_generic(tv) != 0) {
        return tv;
    }
    var l = localtvmap;
    while (l != NIL) {
        if (h(h(l)) == tv) {
            return t(h(l));
        }
        l = t(l);
    }
    const new_var = NTV();
    localtvmap = cons(cons(tv, new_var), localtvmap);
    return new_var;
}

export fn linst(term: Word, ngt: Word) Word {
    localtvmap = NIL;
    NGT = ngt;
    return walktype(term, lmap);
}

export fn non_generic(tv: Word) c_int {
    var x = NGT;
    while (x != NIL) {
        if (occurs(tv, subst(h(x))) != 0) {
            return 1;
        }
        x = t(x);
    }
    return 0;
}

export fn mapup(tv_in: Word) Word {
    var m: *Word = &tvmap;
    var tv = gettvar(tv_in);
    tv -= 1;
    while (tv > 0) : (tv -= 1) {
        m = tp(m.*);
    }
    if (m.* == NIL) {
        m.* = cons(NTV(), NIL);
    }
    return h(m.*);
}

export fn instantiate(term: Word) Word {
    tvmap = NIL;
    return walktype(term, mapup);
}

export fn ap_subst(term: Word, args: Word) Word {
    tvmap = args;
    const r = walktype(term, mapup);
    tvmap = NIL;
    return r;
}

export fn mapdown(tv: Word) Word {
    var m: *Word = &tvmap;
    var i: Word = 1;
    while (m.* != NIL and !eqtvar(h(m.*), tv)) {
        m = tp(m.*);
        i += 1;
    }
    if (m.* == NIL) {
        m.* = cons(tv, NIL);
    }
    return mktvar(i);
}

export fn redtvars(term: Word) Word {
    tvmap = NIL;
    return walktype(term, mapdown);
}

export fn occurs(tv: Word, t_val: Word) c_int {
    var term = t_val;
    while (iscompound_t(term)) {
        if (occurs(tv, t(term)) != 0) {
            return 1;
        }
        term = h(term);
    }
    return if (tv == term) 1 else 0;
}

export fn ispoly(t_val: Word) c_int {
    var term = t_val;
    while (iscompound_t(term)) {
        if (ispoly(t(term)) != 0) {
            return 1;
        }
        term = h(term);
    }
    return if (isvar_t(term)) 1 else 0;
}

fn getStdout() ?*c.FILE {
    const T = @TypeOf(c.stdout);
    if (comptime @typeInfo(T) == .@"fn") {
        return c.stdout();
    } else if (comptime @typeInfo(T) == .pointer and @typeInfo(@typeInfo(T).pointer.child) == .@"fn") {
        return c.stdout();
    } else {
        return c.stdout;
    }
}

export var lastloc: Word = 0;

export fn locate(s: [*:0]const u8) void {
    TYPERRS += 1;
    if (TYPERRS == 1 or lastloc != current_id) {
        if (current_id != 0) {
            if (tag[@intCast(current_id)] == DATAPAIR) {
                locate_inc();
                _ = c.printf("%s in binding for %s\n", s, @as([*:0]const u8, @ptrFromInt(@as(usize, @intCast(h(current_id))))));
                return;
            }
            var x = current_id;
            _ = c.printf("%s in definition of ", s);
            while (tag[@intCast(x)] == CONS) {
                if (tag[@intCast(t(x))] == ID and member(fnts, t(x)) != 0) {
                    _ = c.printf("nonterminal ");
                    x = h(x);
                } else {
                    out_formal1(getStdout().?, h(x));
                    _ = c.printf(", subdef of ");
                    x = t(x);
                }
            }
            _ = c.printf("%s", getId(x));
            _ = c.printf("\n");
        } else {
            _ = c.printf("%s in expression\n", s);
        }
    }
    if (lineptr != 0) {
        sayhere(lineptr, 0);
    } else if (current_id != 0 and idWho(current_id) != NIL) {
        sayhere(idWho(current_id), 0);
    }
    lastloc = current_id;
}

export fn rhs_here(r: Word) Word {
    if (tag[@intCast(r)] == LABEL) {
        return h(r);
    }
    if (tag[@intCast(r)] == TRIES) {
        return h(h(lastlink(t(r))));
    }
    return 0;
}

export fn sayhere(h_val: Word, nl: Word) void {
    var h_node = h_val;
    if (tag[@intCast(h_node)] != FILEINFO) {
        h_node = rhs_here(h_node);
        if (tag[@intCast(h_node)] != FILEINFO) {
            _ = c.fprintf(getStderr().?, "(impossible event in sayhere)\n");
            return;
        }
    }
    const h_str = @as([*:0]const u8, @ptrFromInt(@as(usize, @intCast(h(h_node)))));
    const eq = std.mem.eql(u8, std.mem.span(h_str), std.mem.span(current_script));
    const prefix: [*:0]const u8 = if (eq) "" else "%insert file ";
    _ = c.printf("(line %3ld of %s\"%s\")", t(h_node), prefix, h_str);
    if (nl != 0) {
        _ = c.printf("\n");
    } else {
        _ = c.printf(" ");
    }
    if (eq) {
        if (errline == 0) {
            errline = t(h_node);
        }
    } else {
        if (errs == 0) {
            errs = h_node;
        }
    }
}

export fn report_type(x: Word) void {
    _ = c.printf("%s", getId(x));
    if (idType(x) == type_t) {
        const arity = t_arity(x);
        if (arity > 5) {
            _ = c.printf("(arity %ld)", arity);
        } else {
            var i: Word = 1;
            while (i <= arity) : (i += 1) {
                _ = c.printf(" ");
                var j: Word = 0;
                while (j < i) : (j += 1) {
                    _ = c.printf("*");
                }
            }
        }
    }
    _ = c.printf(" :: ");
    out_type(idType(x));
}

export fn type_error(a: [*:0]const u8, b: [*:0]const u8, t1_val: Word, t2_val: Word) void {
    var t1 = redtvars(ap(subst(t1_val), subst(t2_val)));
    const t2 = t(t1);
    t1 = h(t1);
    locate("type error");
    _ = c.printf("cannot %s ", a);
    out_type(t1);
    _ = c.printf(" %s ", b);
    out_type(t2);
    _ = c.printf("\n");
}

export fn type_error1(x: Word) void {
    locate("type error");
    _ = c.printf("typename used as identifier (%s)\n", getId(x));
}

export fn type_error2(x: Word) void {
    if (compiling != 0) {
        return;
    }
    TYPERRS += 1;
    _ = c.printf("undefined name - %s\n", getId(x));
}

export fn type_error3(x: Word) void {
    locate("error");
    _ = c.printf("constructor \"%s\" used at wrong arity in formal\n", getId(x));
}

export fn type_error4(x: Word) void {
    locate("error");
    _ = c.printf("illegal object \"");
    out_pattern(getStdout().?, x);
    _ = c.printf("\" as head of formal\n");
}

export fn type_error5(x: Word) void {
    locate("error");
    _ = c.printf("undeclared constructor \"");
    out_pattern(getStdout().?, x);
    _ = c.printf("\" in formal\n");
    ND = add1(x, ND);
}

export fn type_error6(x: Word, f: Word, a: Word) void {
    TYPERRS += 1;
    _ = c.printf("incorrect declaration ");
    sayhere(lineptr, 1);
    _ = c.printf("specified, %s :: ", getId(x));
    out_type(f);
    _ = c.printf("\n");
    _ = c.printf("inferred,  %s :: ", getId(x));
    out_type(redtvars(subst(a)));
    _ = c.printf("\n");
}

export fn type_error7(a: Word, b: Word) void {
    locate("type error");
    _ = c.printf("\nrhs of lex rule :: ");
    out_type(redtvars(subst(b)));
    _ = c.printf("\n type expected  :: ");
    out_type(redtvars(subst(a)));
    _ = c.printf("\n");
}

export fn type_error8(t1_val: Word, t2_val: Word) void {
    var t1 = subst(t1_val);
    var t2 = subst(t2_val);
    if (same(h(t1), h(t2)) != 0) {
        t1 = t(t1);
        t2 = t(t2);
    }
    t1 = redtvars(ap(t1, t2));
    t2 = t(t1);
    t1 = h(t1);
    const big = size(t1) >= 10 or size(t2) >= 10;
    locate("type error");
    const prefix: [*:0]const u8 = if (big) "\n " else " ";
    _ = c.printf("cannot unify%s ", prefix);
    out_type(t1);
    const infix: [*:0]const u8 = if (big) "\nwith\n  " else " with ";
    _ = c.printf("%s", infix);
    out_type(t2);
    _ = c.printf("\n");
}

const comma_t: Word = 5;
const arrow_t: Word = 6;
const void_t: Word = 7;
const wrong_t: Word = 8;

fn isarrow_t(t_val: Word) bool {
    return tag[@intCast(t_val)] == AP and tag[@intCast(h(t_val))] == AP and h(h(t_val)) == arrow_t;
}
fn iscomma_t(t_val: Word) bool {
    return tag[@intCast(t_val)] == AP and tag[@intCast(h(t_val))] == AP and h(h(t_val)) == comma_t;
}
fn islist_t(t_val: Word) bool {
    return tag[@intCast(t_val)] == AP and h(t_val) == list_t;
}

export fn out_type(t_val: Word) void {
    var type_node = t_val;
    while (isarrow_t(type_node)) {
        out_type1(t(h(type_node)));
        _ = c.printf("->");
        type_node = t(type_node);
    }
    out_type1(type_node);
}

export fn out_type1(t_val: Word) void {
    var type_node = t_val;
    if (iscompound_t(type_node) and !iscomma_t(type_node) and !islist_t(type_node) and !isarrow_t(type_node)) {
        out_type1(h(type_node));
        _ = c.printf(" ");
        type_node = t(type_node);
    }
    out_type2(type_node);
}

export fn out_type2(t_val: Word) void {
    if (islist_t(t_val)) {
        _ = c.printf("[");
        out_type(t(t_val));
        _ = c.printf("]");
    } else if (iscompound_t(t_val)) {
        _ = c.printf("(");
        out_typel(t_val);
        if (iscomma_t(t_val) and t(t_val) == void_t) {
            _ = c.printf(",");
        }
        _ = c.printf(")");
    } else {
        switch (t_val) {
            bool_t => {
                _ = c.printf("bool");
            },
            num_t => {
                _ = c.printf("num");
            },
            char_t => {
                _ = c.printf("char");
            },
            wrong_t => {
                _ = c.printf("WRONG");
            },
            undef_t => {
                _ = c.printf("UNKNOWN");
            },
            void_t => {
                _ = c.printf("()");
            },
            type_t => {
                _ = c.printf("type");
            },
            else => {
                if (tag[@intCast(t_val)] == ID) {
                    _ = c.printf("%s", getId(t_val));
                } else if (isvar_t(t_val)) {
                    var n = gettvar(t_val);
                    if (n > 0 and n < 7) {
                        while (n > 0) : (n -= 1) {
                            _ = c.printf("*");
                        }
                    } else {
                        _ = c.printf("%ld", n);
                    }
                } else if (tag[@intCast(t_val)] == STRCONS) {
                    const pn_val_node = pn_val(t_val);
                    if (tag[@intCast(pn_val_node)] == ID) {
                        _ = c.printf("%s", getId(pn_val_node));
                    } else if (std.mem.eql(u8, std.mem.span(@as([*:0]const u8, @ptrFromInt(@as(usize, @intCast(h(t(t_info(t_val)))))))), std.mem.span(current_script))) {
                        _ = c.printf("%s", @as([*:0]const u8, @ptrFromInt(@as(usize, @intCast(h(h(t_info(t_val))))))));
                    } else {
                        _ = c.printf("`%s@%s'", @as([*:0]const u8, @ptrFromInt(@as(usize, @intCast(h(h(t_info(t_val))))))), @as([*:0]const u8, @ptrFromInt(@as(usize, @intCast(h(t(t_info(t_val))))))));
                    }
                } else {
                    _ = c.printf("<BADLY FORMED TYPE:%d,%ld,%ld>", tag[@intCast(t_val)], h(t_val), t(t_val));
                }
            },
        }
    }
}

export fn out_typel(t_val: Word) void {
    var type_node = t_val;
    while (iscomma_t(type_node)) {
        out_type(t(h(type_node)));
        type_node = t(type_node);
        if (iscomma_t(type_node)) {
            _ = c.printf(",");
        } else if (type_node != void_t) {
            _ = c.printf("<>");
        }
    }
    if (type_node == void_t) {
        return;
    }
    out_type(type_node);
}

fn pn_val(x: Word) Word {
    return t(x);
}

const PLUS: Word = CMBASE + 54;

fn neg(x: Word) Word {
    return h(x) & 0x10000000;
}

var allchars: Word = 0;

export fn tail(x_in: Word) Word {
    var x = x_in;
    allchars = 1;
    while (tag[@intCast(x)] == CONS) {
        const char_res = is_char(h(x));
        allchars = if (char_res != 0) allchars & 1 else 0;
        x = t(x);
    }
    return x;
}

export fn out_formal1(f: *c.FILE, x_in: Word) void {
    var x = x_in;
    if (h(x) == CONST) {
        x = t(x);
    }
    if (x == NIL) {
        _ = c.fprintf(f, "[]");
    } else if (tag[@intCast(x)] == CONS and tail(x) == NIL) {
        if (allchars != 0) {
            _ = c.fprintf(f, "\"");
            while (x != NIL) {
                _ = c.fprintf(f, "%s", charname(h(x)));
                x = t(x);
            }
            _ = c.fprintf(f, "\"");
        } else {
            _ = c.fprintf(f, "[");
            while (x != nill and x != NIL) {
                out_pattern(f, h(x));
                x = t(x);
                if (x != nill and x != NIL) {
                    _ = c.fprintf(f, ",");
                }
            }
            _ = c.fprintf(f, "]");
        }
    } else if (tag[@intCast(x)] == AP or tag[@intCast(x)] == CONS) {
        _ = c.fprintf(f, "(");
        out_pattern(f, x);
        _ = c.fprintf(f, ")");
    } else if (tag[@intCast(x)] == TCONS or tag[@intCast(x)] == PAIR) {
        _ = c.fprintf(f, "(");
        while (tag[@intCast(x)] == TCONS) {
            out_pattern(f, h(x));
            x = t(x);
            _ = c.fprintf(f, ",");
        }
        out_pattern(f, h(x));
        _ = c.fprintf(f, ",");
        out_pattern(f, t(x));
        _ = c.fprintf(f, ")");
    } else if ((tag[@intCast(x)] == INT and neg(x) != 0) or (tag[@intCast(x)] == DOUBLE and get_dbl(x) < 0)) {
        _ = c.fprintf(f, "(");
        out(f, x);
        _ = c.fprintf(f, ")");
    } else {
        out(f, x);
    }
}

export fn out_pattern(f: *c.FILE, x: Word) void {
    if (tag[@intCast(x)] == CONS) {
        if (h(x) == CONST and (tag[@intCast(t(x))] == INT or tag[@intCast(t(x))] == DOUBLE)) {
            out(f, t(x));
        } else if (h(x) != CONST and tail(x) != NIL) {
            out_formal(f, h(x));
            _ = c.fprintf(f, ":");
            out_pattern(f, t(x));
        } else {
            out_formal(f, x);
        }
    } else {
        out_formal(f, x);
    }
}

export fn out_formal(f: *c.FILE, x: Word) void {
    if (tag[@intCast(x)] != AP) {
        out_formal1(f, x);
    } else if (tag[@intCast(h(x))] == AP and h(h(x)) == PLUS) {
        out_formal(f, t(x));
        _ = c.fprintf(f, "+");
        out(f, t(h(x)));
    } else {
        out_formal(f, h(x));
        _ = c.fprintf(f, " ");
        out_formal1(f, t(x));
    }
}

const CONST: Word = 268;

fn isConstructor(x: Word) bool {
    return tag[@intCast(x)] == ID and isconstrname(getId(x)) != 0;
}

export fn rembvars(x_in: Word, p_in: Word) Word {
    var x = x_in;
    var p = p_in;
    while (true) {
        switch (tag[@intCast(p)]) {
            ID => {
                _ = remove1(p, &x);
                return x;
            },
            CONS => {
                if (h(p) == CONST) {
                    return x;
                }
                x = rembvars(x, h(p));
                p = t(p);
            },
            AP => {
                if (tag[@intCast(h(p))] == AP and h(h(p)) == PLUS) {
                    p = t(p);
                } else {
                    x = rembvars(x, h(p));
                    p = t(p);
                }
            },
            PAIR, TCONS => {
                x = rembvars(x, h(p));
                p = t(p);
            },
            else => {
                _ = c.fprintf(getStderr().?, "impossible event in rembvars\n");
                return x;
            },
        }
    }
}

export fn deps(x_in: Word) Word {
    var x = x_in;
    var d = NIL;
    while (true) {
        switch (tag[@intCast(x)]) {
            AP, TCONS, PAIR, CONS => {
                d = UNION(d, deps(h(x)));
                x = t(x);
            },
            ID => {
                return if (isConstructor(x)) d else add1(x, d);
            },
            LAMBDA => {
                return rembvars(UNION(d, deps(t(x))), h(x));
            },
            LET => {
                d = rembvars(UNION(d, deps(t(x))), h(h(x)));
                return UNION(d, deps(t(t(h(x)))));
            },
            LETREC => {
                d = UNION(d, deps(t(x)));
                var y = h(x);
                while (y != NIL) {
                    d = UNION(d, deps(t(t(h(y)))));
                    y = t(y);
                }
                y = h(x);
                while (y != NIL) {
                    d = rembvars(d, h(h(y)));
                    y = t(y);
                }
                return d;
            },
            LEXER => {
                var lex_x = x;
                while (lex_x != NIL) {
                    d = UNION(d, deps(t(t(h(lex_x)))));
                    lex_x = t(lex_x);
                }
                return d;
            },
            TRIES, LABEL => {
                x = t(x);
            },
            SHARE => {
                x = h(x);
            },
            else => return d,
        }
    }
}

export fn comp_deps(n: Word) void {
    var rhs = NIL;
    var r: Word = 0;
    if (idType(n) == type_t) {
        switch (t_class(n)) {
            algebraic_t => {
                r = t_info(n);
                while (r != NIL) {
                    current_id = h(r);
                    tp(h(h(r))).* = redtvars(meta_tcheck(idType(h(r))));
                    r = t(r);
                }
            },
            synonym_t => {
                current_id = n;
                tp(t(t(n))).* = meta_tcheck(t_info(n));
            },
            abstract_t => {
                if (t_info(n) == undef_t) {
                    _ = c.printf("error: script contains no binding for abstract typename \"%s\"\n", getId(n));
                    sayhere(idWho(n), 1);
                    TYPERRS += 1;
                } else {
                    current_id = n;
                    tp(t(t(n))).* = meta_tcheck(t_info(n));
                }
            },
            else => {},
        }
        current_id = 0;
        return;
    }
    if (tag[@intCast(t(n))] == CONSTRUCTOR) {
        return;
    }
    if (idType(n) != undef_t) {
        current_id = n;
        if (tag[@intCast(idType(n))] == CONS) {
            if (t(n) == UNDEF) {
                SBND = add1(n, SBND);
            }
            tp(h(n)).* = redtvars(meta_tcheck(h(idType(n))));
            current_id = 0;
            return;
        }
        tp(h(n)).* = redtvars(meta_tcheck(idType(n)));
        current_id = 0;
    }
    if (t(n) == FREE) {
        return;
    }
    if (t(n) == UNDEF) {
        SBND = add1(n, SBND);
        return;
    }
    r = deps(t(n));
    while (r != NIL) {
        if (t(h(r)) != UNDEF and idType(h(r)) == undef_t) {
            rhs = add1(h(r), rhs);
        }
        r = t(r);
    }
    R = cons(cons(n, rhs), R);
}

const algebraic_t: Word = 0;
const FREE: Word = 276;

export fn redtfr(x_in: Word) void {
    var x = x_in;
    while (x != NIL) {
        tp(t(h(x))).* = idType(h(h(x)));
        x = t(x);
    }
}

export fn printelement(x: Word) void {
    if (tag[@intCast(x)] != CONS) {
        out(getStdout().?, x);
        return;
    }
    _ = c.printf("(");
    var cur = x;
    while (cur != NIL) {
        out(getStdout().?, h(cur));
        cur = t(cur);
        if (cur != NIL) {
            _ = c.printf(" ");
        }
    }
    _ = c.printf(")");
}

export fn printlist(title: [*:0]const u8, l_in: Word) void {
    var l = l_in;
    _ = c.printf("%s", title);
    while (l != NIL) {
        printelement(h(l));
        l = t(l);
        if (l != NIL) {
            _ = c.printf(",");
        }
    }
    _ = c.printf(";\n");
}

var hereinc: Word = 0;
var lasthereinc: Word = 0;

fn id_who(x: Word) Word {
    return t(h(h(x)));
}

fn the_val(x: Word) Word {
    return t(x);
}


fn reset_SUBST() void {
    current_id = if (tvcount >= @as(Word, @intCast(hashsize))) clear_SUBST() else 0;
}

export fn locate_inc() void {
    if (lasthereinc == hereinc) {
        return;
    }
    _ = c.printf("incorrect %%include directive ");
    lasthereinc = hereinc;
    sayhere(hereinc, 1);
}

export fn cyclic_abstr(atnames: Word) Word {
    var x = atnames;
    var y = NIL;
    while (x != NIL) {
        y = ap(y, t_info(h(x)));
        x = t(x);
    }
    x = atnames;
    while (x != NIL) {
        if (occurs(h(x), y) != 0) {
            _ = c.printf("illegal type abstraction: cycle in \"==\" binding%s ", if (t(atnames) == NIL) @as([*:0]const u8, "") else @as([*:0]const u8, "s"));
            printelement(atnames);
            _ = c.putchar('\n');
            sayhere(id_who(h(x)), 1);
            TYPERRS += 1;
            return 1;
        }
        x = t(x);
    }
    return 0;
}

export fn txchange(ids_in: Word, x_in: Word) void {
    var ids = ids_in;
    var x = x_in;
    while (ids != NIL) {
        const t_val = idType(h(ids));
        tp(h(h(ids))).* = h(x);
        hp(x).* = t_val;
        ids = t(ids);
        x = t(x);
    }
}

export fn rep_t1(T: Word, L: Word) Word {
    var args = NIL;
    var t1 = T;
    var changed = false;
    while (iscompound_t(t1)) {
        const a = rep_t1(t(t1), L);
        if (a != t(t1)) {
            changed = true;
        }
        args = cons(a, args);
        t1 = h(t1);
    }
    if (member(L, t1) != 0) {
        return ap_subst(t_info(t1), args);
    }
    if (!changed) {
        return T;
    }
    while (args != NIL) {
        t1 = ap(t1, h(args));
        args = t(args);
    }
    return t1;
}

export fn rep_t(T: Word, L: Word) Word {
    const t_val = rep_t1(T, L);
    return if (t_val == T) t_val else redtvars(t_val);
}

export fn fix_type(t_val: Word) Word {
    var t_node = t_val;
    switch (tag[@intCast(t_node)]) {
        AP, CONS => {
            tp(t_node).* = fix_type(t(t_node));
            hp(t_node).* = fix_type(h(t_node));
            return t_node;
        },
        STRCONS => {
            while (tag[@intCast(pn_val(t_node))] != CONS) {
                t_node = pn_val(t_node);
            }
            return t_node;
        },
        else => {
            return t_node;
        },
    }
}

export fn abstr_check(x_in: Word) void {
    var x = x_in;
    const rtypes = t(h(x));
    const sigids = t(x);
    ATNAMES = h(h(x));
    txchange(sigids, rtypes); // install representation types
    x = sigids;
    while (x != NIL) {
        const oldte = TYPERRS;
        current_id = h(x);
        const t_val = subst(etype(idVal(h(x)), NIL, NIL));
        if (subsumes(t_val, instantiate(idType(h(x)))) == 0) {
            TYPERRS += 1;
            _ = c.printf("abstype implementation error\n");
            _ = c.printf("\"%s\" is bound to value of type: ", getId(h(x)));
            out_type(redtvars(t_val));
            _ = c.printf("\ntype expected: ");
            out_type(idType(h(x)));
            _ = c.putchar('\n');
            sayhere(id_who(h(x)), 1);
        }
        if (TYPERRS > oldte) {
            tp(h(h(x))).* = wrong_t;
            tp(h(x)).* = UNDEF;
            ND = add1(h(x), ND);
        }
        reset_SUBST();
        x = t(x);
    }
    // restore the abstract types - for "finger"
    x = sigids;
    var rt = rtypes;
    while (x != NIL) {
        if (idType(h(x)) != wrong_t) {
            tp(h(h(x))).* = h(rt);
        }
        x = t(x);
        rt = t(rt);
    }
    ATNAMES = 0;
}

export fn abstr_mcheck(tabstrs_in: Word) void {
    var tabstrs = tabstrs_in;
    while (tabstrs != NIL) {
        const atnames = h(h(tabstrs));
        var sigids = t(h(tabstrs));
        var rtypes = NIL;
        if (cyclic_abstr(atnames) != 0) {
            return;
        }
        while (sigids != NIL) {
            const t_val = idType(h(sigids));
            if (t_val == undef_t) {
                rtypes = cons(undef_t, rtypes);
            } else {
                rtypes = cons(meta_tcheck(t_val), rtypes);
            }
            sigids = t(sigids);
        }
        rtypes = reverse(rtypes);
        hp(h(tabstrs)).* = cons(h(h(tabstrs)), rtypes);
        tabstrs = t(tabstrs);
    }
}

export fn mcheckfbs() void {
    var ff: Word = undefined;
    var formals: Word = undefined;
    var n: Word = undefined;
    lasthereinc = 0;
    ff = FBS;
    while (ff != NIL) {
        hereinc = h(h(FBS));
        formals = t(h(ff));
        while (formals != NIL) {
            const t_val = t(t(h(formals)));
            if (t_val != type_t) {
                formals = t(formals);
                continue;
            }
            current_id = h(t(h(formals))); // nb datapair(orig,0) not id
            tp(t(t(h(h(formals))))).* = meta_tcheck(t_info(h(h(formals))));
            current_id = 0;
            formals = t(formals);
        }
        if (TYPERRS != 0) {
            return; // to avoid misleading error messages
        }
        formals = t(h(ff));
        while (formals != NIL) {
            const t_val = t(t(h(formals)));
            if (t_val == type_t) {
                formals = t(formals);
                continue;
            }
            current_id = h(t(h(formals))); // nb datapair(orig,0) not id
            tp(t(h(formals))).* = redtvars(meta_tcheck(t_val));
            current_id = 0;
            formals = t(formals);
        }
        ff = t(ff);
    }
    if (TYPERRS != 0) {
        return;
    }
    ff = t(files);
    while (ff != NIL) {
        formals = t(h(ff));
        while (formals != NIL) {
            n = h(formals);
            if (tag[@intCast(n)] == ID) {
                if (idType(n) == type_t) {
                    if (t_class(n) == synonym_t) {
                        tp(t(t(n))).* = meta_tcheck(t_info(n));
                    }
                } else {
                    tp(h(n)).* = redtvars(meta_tcheck(idType(n)));
                }
            }
            formals = t(formals);
        }
        ff = t(ff);
    }
}

export fn checkfbs() void {
    const oldte = TYPERRS;
    var formals: Word = undefined;
    lasthereinc = 0;
    while (FBS != NIL) {
        hereinc = h(h(FBS));
        formals = t(h(FBS));
        while (formals != NIL) {
            var t_val: Word = undefined;
            const t1 = fix_type(t(t(h(formals))));
            if (t1 == type_t) {
                formals = t(formals);
                continue;
            }
            current_id = h(t(h(formals))); // nb datapair(orig,0) not id
            t_val = subst(etype(the_val(h(h(formals))), NIL, NIL));
            if (subsumes(t_val, instantiate(t1)) == 0) {
                TYPERRS += 1;
                locate_inc();
                _ = c.printf("binding for parameter `%s' has wrong type\n", @as([*:0]const u8, @ptrFromInt(@as(usize, @intCast(h(current_id))))));
                _ = c.printf("required :: ");
                out_type(t(t(h(formals))));
                _ = c.printf("\n  actual :: ");
                out_type(redtvars(t_val));
                _ = c.putchar('\n');
            }
            tp(t(h(h(formals)))).* = codegen(the_val(h(h(formals))));
            formals = t(formals);
        }
        FBS = t(FBS);
    }
    if (TYPERRS > oldte) { // badly typed parameter bindings, so give up
        TABSTRS = NIL;
        NT = NIL;
        R = NIL;
        _ = c.printf("compilation abandoned\n");
        SYNERR = 1;
    }
    reset_SUBST();
}

export var tfnum: Word = 0;
export var tfbool: Word = 0;
export var tfbool2: Word = 0;
export var tfnum2: Word = 0;
export var tfstrstr: Word = 0;
export var tfnumnum: Word = 0;
export var ltchar: Word = 0;
export var tstep: Word = 0;
export var tstepuntil: Word = 0;
export var exec_t: Word = 0;
export var read_t: Word = 0;
export var filestat_t: Word = 0;

export fn genlstat_t() Word {
    if (filestat_t == 0) {
        filestat_t = tf(ltchar, pair_t(pair_t(num_t, num_t), num_t));
    }
    return filestat_t;
}

const bind_t: Word = 9;

fn bound_t(type_node: Word) bool {
    return iscompound_t(type_node) and h(type_node) == bind_t;
}

fn ap2(x: Word, y: Word, z: Word) Word {
    return ap(ap(x, y), z);
}

fn tf(a: Word, b: Word) Word {
    return ap2(arrow_t, a, b);
}

fn tf2(a: Word, b: Word, c_param: Word) Word {
    return tf(a, tf(b, c_param));
}

fn tf3(a: Word, b: Word, c_param: Word, d: Word) Word {
    return tf(a, tf2(b, c_param, d));
}

fn tf4(a: Word, b: Word, c_param: Word, d: Word, e: Word) Word {
    return tf(a, tf3(b, c_param, d, e));
}

fn lt(a: Word) Word {
    return ap(list_t, a);
}

fn pair_t(x: Word, y: Word) Word {
    return ap2(comma_t, x, ap2(comma_t, y, void_t));
}

fn dlhs(d: Word) Word {
    return h(d);
}

fn dtyp(d: Word) Word {
    return h(t(d));
}

fn dval(d: Word) Word {
    return t(t(d));
}


export fn subsu1(t1_in: Word, t2: Word, T2: Word) Word {
    const t1 = subst(t1_in);
    if (t1 == t2) {
        return 1;
    }
    if (isvar_t(t1) and occurs(t1, T2) == 0) {
        addsubst(t1, t2);
        return 1;
    }
    if (iscompound_t(t1) and iscompound_t(t2)) {
        return if (subsu1(h(t1), h(t2), T2) != 0 and subsu1(t(t1), t(t2), T2) != 0) 1 else 0;
    }
    return 0;
}

export fn subsumes(t1: Word, t2: Word) Word {
    if (t2 == wrong_t) {
        return 1;
    }
    return subsu1(t1, t2, t2);
}

fn unify1(t1_val: Word, t2_val: Word) c_int {
    const t1 = subst(t1_val);
    const t2 = subst(t2_val);
    if (t1 == t2) {
        return 1;
    }
    if (isvar_t(t1) and occurs(t1, t2) == 0) {
        addsubst(t1, t2);
        return 1;
    }
    if (isvar_t(t2) and occurs(t2, t1) == 0) {
        addsubst(t2, t1);
        return 1;
    }
    if (iscompound_t(t1) and iscompound_t(t2)) {
        return if (unify1(h(t1), h(t2)) != 0 and unify1(t(t1), t(t2)) != 0) 1 else 0;
    }
    return 0;
}

fn unify(t1_val: Word, t2_val: Word) c_int {
    const t1 = subst(t1_val);
    const t2 = subst(t2_val);
    if (t1 == t2) {
        return 1;
    }
    if (isvar_t(t1) and occurs(t1, t2) == 0) {
        addsubst(t1, t2);
        return 1;
    }
    if (isvar_t(t2) and occurs(t2, t1) == 0) {
        addsubst(t2, t1);
        return 1;
    }
    if (iscompound_t(t1) and iscompound_t(t2) and unify1(h(t1), h(t2)) != 0 and unify1(t(t1), t(t2)) != 0) {
        return 1;
    }
    type_error("unify", "with", t1, t2);
    return 0;
}

fn conforms(p: Word, t_val: Word, e_in: Word, ngt: Word) Word {
    var e = e_in;
    if (e == -1) {
        return -1;
    }
    if (tag[@intCast(p)] == ID and !isConstructor(p)) {
        return cons(cons(p, t_val), e);
    }
    if (h(p) == CONST) {
        _ = unify(etype(t(p), e, ngt), t_val);
        return e;
    }
    if (tag[@intCast(p)] == CONS) {
        const at = NTV();
        if (unify(lt(at), t_val) == 0) {
            return -1;
        }
        return conforms(t(p), t_val, conforms(h(p), at, e, ngt), ngt);
    }
    if (tag[@intCast(p)] == TCONS) {
        const at = NTV();
        const bt = NTV();
        if (unify(ap2(comma_t, at, bt), t_val) == 0) {
            return -1;
        }
        return conforms(t(p), bt, conforms(h(p), at, e, ngt), ngt);
    }
    if (tag[@intCast(p)] == PAIR) {
        const at = NTV();
        const bt = NTV();
        if (unify(ap2(comma_t, at, ap2(comma_t, bt, void_t)), t_val) == 0) {
            return -1;
        }
        return conforms(t(p), bt, conforms(h(p), at, e, ngt), ngt);
    }
    if (tag[@intCast(p)] == AP and tag[@intCast(h(p))] == AP and h(h(p)) == c.PLUS) { // n+k pattern
        if (unify(num_t, t_val) == 0) {
            return 1;
        }
        return conforms(t(p), num_t, e, ngt);
    }
    {
        var p_args = NIL;
        var pt: Word = undefined;
        var cur_p = p;
        while (tag[@intCast(cur_p)] == AP) {
            p_args = cons(t(cur_p), p_args);
            cur_p = h(cur_p);
        }
        if (!isConstructor(cur_p)) {
            type_error4(cur_p);
            return -1;
        }
        if (idType(cur_p) == undef_t) {
            type_error5(cur_p);
            return -1;
        }
        pt = instantiate(if (ATNAMES != 0) rep_t(idType(cur_p), ATNAMES) else idType(cur_p));
        while (p_args != NIL and isarrow_t(pt)) {
            e = conforms(h(p_args), t(h(pt)), e, ngt);
            pt = t(pt);
            p_args = t(p_args);
            if (e == -1) {
                return -1;
            }
        }
        if (p_args != NIL or isarrow_t(pt)) {
            type_error3(cur_p);
            return -1;
        }
        if (unify(pt, t_val) == 0) {
            return -1;
        }
        return e;
    }
}

fn etype(x: Word, env: Word, ngt: Word) Word {
    switch (tag[@intCast(x)]) {
        AP => {
            if (h(x) == c.BADCASE or h(x) == c.CONFERROR) {
                return NTV();
            }
            const ft_val = etype(h(x), env, ngt);
            const at = etype(t(x), env, ngt);
            const rt = NTV();
            if (unify1(ft_val, ap2(arrow_t, at, rt)) == 0) {
                const ft = subst(ft_val);
                if (isarrow_t(ft)) {
                    if (tag[@intCast(h(x))] == AP and h(h(x)) == c.G_ERROR) {
                        type_error8(at, t(h(ft)));
                    } else {
                        type_error("unify", "with", at, t(h(ft)));
                    }
                } else {
                    type_error("apply", "to", ft, at);
                }
                return NTV();
            }
            return rt;
        },
        CONS => {
            const ht = etype(h(x), env, ngt);
            const rt = etype(t(x), env, ngt);
            if (unify1(lt(ht), rt) == 0) {
                type_error("cons", "to", ht, rt);
                return NTV();
            }
            return rt;
        },
        LEXER => {
            const hold = lineptr;
            lineptr = h(t(t(h(x))));
            tp(t(h(x))).* = t(t(t(h(x))));
            const a = etype(t(t(h(x))), env, ngt);
            var cur_x = x;
            while (true) {
                cur_x = t(cur_x);
                if (cur_x == NIL) break;
                lineptr = h(t(t(h(cur_x))));
                tp(t(h(cur_x))).* = t(t(t(h(cur_x))));
                const b = etype(t(t(h(cur_x))), env, ngt);
                if (unify1(a, b) == 0) {
                    type_error7(a, b);
                    lineptr = hold;
                    return NTV();
                }
            }
            lineptr = hold;
            return tf(ltchar, lt(a));
        },
        TCONS => {
            return ap2(comma_t, etype(h(x), env, ngt), etype(t(x), env, ngt));
        },
        PAIR => {
            return ap2(comma_t, etype(h(x), env, ngt), ap2(comma_t, etype(t(x), env, ngt), void_t));
        },
        DOUBLE, INT => {
            return num_t;
        },
        ID => {
            var cur_env = env;
            while (cur_env != NIL) {
                if (h(h(cur_env)) == x) {
                    tp(h(cur_env)).* = subst(t(h(cur_env)));
                    return linst(t(h(cur_env)), ngt);
                }
                cur_env = t(cur_env);
            }
            const a = idType(x);
            if (bound_t(a)) {
                return t(a);
            }
            if (a == type_t) {
                type_error1(x);
            }
            if (a == undef_t) {
                if (commandmode != 0) {
                    type_error2(x);
                } else if (member(ND, x) == 0) {
                    if (lineptr != 0) {
                        sayhere(lineptr, 0);
                    } else if (tag[@intCast(current_id)] == DATAPAIR) {
                        locate_inc();
                    }
                    _ = c.printf("undefined name \"%s\"\n", getId(x));
                    ND = add1(x, ND);
                }
                return NTV();
            }
            if (a == wrong_t) {
                return NTV();
            }
            return instantiate(if (ATNAMES != 0) rep_t(a, ATNAMES) else a);
        },
        LAMBDA => {
            const a = NTV();
            const b = NTV();
            const d = cons(a, ngt);
            const c_local = conforms(h(x), a, env, d);
            if (c_local == -1 or unify(b, etype(t(x), c_local, d)) == 0) {
                return NTV();
            }
            return tf(a, b);
        },
        LET => {
            var e: Word = undefined;
            const def = h(x);
            const a = NTV();
            e = conforms(dlhs(def), a, env, cons(a, ngt));
            current_id = cons(dlhs(def), current_id);
            const c_local = lineptr;
            lineptr = dval(def);
            const unified = unify(a, etype(dval(def), env, ngt));
            lineptr = c_local;
            current_id = t(current_id);
            if (e == -1 or unified == 0) {
                return NTV();
            }
            return etype(t(x), e, ngt);
        },
        LETREC => {
            var e = env;
            var s = NIL;
            var a = NIL;
            var c_local = ngt;
            var cur_d = h(x);
            while (cur_d != NIL) {
                if (dtyp(h(cur_d)) == undef_t) {
                    a = cons(h(cur_d), a);
                    const b = NTV();
                    hp(t(h(cur_d))).* = b;
                    c_local = cons(b, c_local);
                    e = conforms(dlhs(h(cur_d)), b, e, c_local);
                } else {
                    hp(t(h(cur_d))).* = meta_tcheck(dtyp(h(cur_d)));
                    s = cons(h(cur_d), s);
                    e = cons(cons(dlhs(h(cur_d)), dtyp(h(cur_d))), e);
                }
                cur_d = t(cur_d);
            }
            if (e == -1) {
                return NTV();
            }
            var success = true;
            var cur_a = a;
            while (cur_a != NIL) {
                current_id = cons(dlhs(h(cur_a)), current_id);
                const hold = lineptr;
                lineptr = dval(h(cur_a));
                if (unify(dtyp(h(cur_a)), etype(dval(h(cur_a)), e, c_local)) == 0) {
                    success = false;
                }
                lineptr = hold;
                current_id = t(current_id);
                cur_a = t(cur_a);
            }
            var cur_s = s;
            while (cur_s != NIL) {
                current_id = cons(dlhs(h(cur_s)), current_id);
                const hold = lineptr;
                lineptr = dval(h(cur_s));
                const ety = etype(dval(h(cur_s)), e, ngt);
                if (subsumes(ety, linst(dtyp(h(cur_s)), ngt)) == 0) {
                    success = false;
                    type_error6(dlhs(h(cur_s)), dtyp(h(cur_s)), ety);
                }
                lineptr = hold;
                current_id = t(current_id);
                cur_s = t(cur_s);
            }
            if (!success) {
                return NTV();
            }
            return etype(t(x), e, ngt);
        },
        TRIES => {
            const hold = lineptr;
            const a = NTV();
            var cur_x = t(x);
            while (cur_x != NIL) {
                lineptr = h(h(cur_x));
                if (unify(a, etype(t(h(cur_x)), env, ngt)) == 0) {
                    break;
                }
                cur_x = t(cur_x);
            }
            lineptr = hold;
            if (cur_x != NIL) {
                return NTV();
            }
            return a;
        },
        LABEL => {
            const hold = lineptr;
            lineptr = h(x);
            const ty = etype(t(x), env, ngt);
            lineptr = hold;
            return ty;
        },
        STARTREADVALS => {
            if (t(x) == 0) {
                hp(x).* = lineptr;
                tp(x).* = NTV();
                showchain = cons(x, showchain);
            }
            return tf(ltchar, lt(t(x)));
        },
        SHOW => {
            hp(x).* = lineptr;
            showchain = cons(x, showchain);
            tp(x).* = NTV();
            return tf(t(x), ltchar);
        },
        SHARE => {
            if (t(x) == undef_t) {
                const hold = TYPERRS;
                tp(x).* = subst(etype(h(x), env, ngt));
                if (TYPERRS > hold) {
                    hp(x).* = UNDEF;
                    tp(x).* = wrong_t;
                }
            }
            if (t(x) == wrong_t) {
                TYPERRS += 1;
                return NTV();
            }
            return t(x);
        },
        CONSTRUCTOR => {
            const a = idType(t(x));
            return instantiate(if (ATNAMES != 0) rep_t(a, ATNAMES) else a);
        },
        UNICODE => {
            return char_t;
        },
        ATOM => {
            if (x < 256) {
                return char_t;
            }
            switch (x) {
                c.S => {
                    const a = NTV(); const b = NTV(); const c_local = NTV();
                    const d = tf3(tf2(a, b, c_local), tf(a, b), a, c_local);
                    return d;
                },
                c.K => {
                    const a = NTV(); const b = NTV();
                    return tf2(a, b, a);
                },
                c.Y => {
                    const a = NTV();
                    return tf(tf(a, a), a);
                },
                c.C => {
                    const a = NTV(); const b = NTV(); const c_local = NTV();
                    return tf3(tf2(a, b, c_local), b, a, c_local);
                },
                c.B => {
                    const a = NTV(); const b = NTV(); const c_local = NTV();
                    return tf3(tf(a, b), tf(c_local, a), c_local, b);
                },
                c.FORCE, c.G_UNIT, c.G_RULE, c.I => {
                    const a = NTV();
                    return tf(a, a);
                },
                c.G_ZERO => {
                    return NTV();
                },
                c.HD => {
                    const a = NTV();
                    return tf(lt(a), a);
                },
                c.TL => {
                    const a = lt(NTV());
                    return tf(a, a);
                },
                c.BODY => {
                    const a = NTV(); const b = NTV();
                    return tf(ap(a, b), a);
                },
                c.LAST => {
                    const a = NTV(); const b = NTV();
                    return tf(ap(a, b), b);
                },
                c.S_p => {
                    const a = NTV(); const b = NTV();
                    const c_local = lt(b);
                    return tf3(tf(a, b), tf(a, c_local), a, c_local);
                },
                c.U, c.U_ => {
                    const a = NTV(); const b = NTV();
                    const c_local = lt(a);
                    return tf2(tf2(a, c_local, b), c_local, b);
                },
                c.Uf => {
                    const a = NTV(); const b = NTV(); const c_local = NTV();
                    return tf2(tf2(tf(a, b), a, c_local), b, c_local);
                },
                c.COND => {
                    const a = NTV();
                    return tf3(bool_t, a, a, a);
                },
                c.EQ, c.GR, c.GRE, c.NEQ => {
                    const a = NTV();
                    return tf2(a, a, bool_t);
                },
                c.NEG => {
                    return tfnum;
                },
                c.AND, c.OR => {
                    return tfbool2;
                },
                c.NOT => {
                    return tfbool;
                },
                c.MERGE, c.APPEND => {
                    const a = lt(NTV());
                    return tf2(a, a, a);
                },
                c.STEP => {
                    return tstep;
                },
                c.STEPUNTIL => {
                    return tstepuntil;
                },
                c.MAP => {
                    const a = NTV();
                    const b = NTV();
                    return tf2(tf(a, b), lt(a), lt(b));
                },
                c.FLATMAP => {
                    const a = NTV(); const b = lt(NTV());
                    return tf2(tf(a, b), lt(a), b);
                },
                c.FILTER => {
                    const a = NTV();
                    const b = lt(a);
                    return tf2(tf(a, bool_t), b, b);
                },
                c.ZIP => {
                    const a = NTV();
                    const b = NTV();
                    return tf2(lt(a), lt(b), lt(pair_t(a, b)));
                },
                c.FOLDL => {
                    const a = NTV();
                    const b = NTV();
                    return tf3(tf2(a, b, a), a, lt(b), a);
                },
                c.FOLDL1 => {
                    const a = NTV();
                    return tf2(tf2(a, a, a), lt(a), a);
                },
                c.LIST_LAST => {
                    const a = NTV();
                    return tf(lt(a), a);
                },
                c.FOLDR => {
                    const a = NTV();
                    const b = NTV();
                    return tf3(tf2(a, b, b), b, lt(a), b);
                },
                c.MATCHINT, c.MATCH => {
                    const a = NTV(); const b = NTV();
                    return tf3(a, b, a, b);
                },
                c.TRY => {
                    const a = NTV();
                    return tf2(a, a, a);
                },
                c.DROP, c.TAKE => {
                    const a = lt(NTV());
                    return tf2(num_t, a, a);
                },
                c.SUBSCRIPT => {
                    const a = NTV();
                    return tf2(num_t, lt(a), a);
                },
                c.P => {
                    const a = NTV();
                    const b = lt(a);
                    return tf2(a, b, b);
                },
                c.B_p => {
                    const a = NTV(); const b = NTV();
                    const c_local = lt(a);
                    return tf3(a, tf(b, c_local), b, c_local);
                },
                c.C_p => {
                    const a = NTV(); const b = NTV();
                    const c_local = lt(b);
                    return tf3(tf(a, b), c_local, a, c_local);
                },
                c.S1 => {
                    const a = NTV(); const b = NTV(); const c_local = NTV(); const d = NTV();
                    return tf4(tf2(a, b, c_local), tf(d, a), tf(d, b), d, c_local);
                },
                c.B1 => {
                    const a = NTV(); const b = NTV(); const c_local = NTV(); const d = NTV();
                    return tf4(tf(a, b), tf(c_local, a), tf(d, c_local), d, b);
                },
                c.C1 => {
                    const a = NTV(); const b = NTV(); const c_local = NTV(); const d = NTV();
                    return tf4(tf2(a, b, c_local), tf(d, a), b, d, c_local);
                },
                c.SEQ => {
                    const a = NTV(); const b = NTV();
                    return tf2(a, b, b);
                },
                c.ITERATE1, c.ITERATE => {
                    const a = NTV();
                    return tf2(tf(a, a), a, lt(a));
                },
                c.EXEC => {
                    if (exec_t == 0) {
                        const a = ap2(comma_t, ltchar, ap2(comma_t, num_t, void_t));
                        exec_t = tf(ltchar, ap2(comma_t, ltchar, a));
                    }
                    return exec_t;
                },
                c.READBIN, c.READ => {
                    if (read_t == 0) {
                        read_t = tf(char_t, ltchar);
                    }
                    return read_t;
                },
                c.FILESTAT => {
                    return genlstat_t();
                },
                c.FILEMODE, c.GETENV, c.NB_STARTREAD, c.STARTREADBIN, c.STARTREAD => {
                    return tfstrstr;
                },
                c.GETARGS => {
                    return tf(char_t, lt(ltchar));
                },
                c.SHOWHEX, c.SHOWOCT, c.SHOWNUM => {
                    return tf(num_t, ltchar);
                },
                c.SHOWFLOAT, c.SHOWSCALED => {
                    return tf2(num_t, num_t, ltchar);
                },
                c.NUMVAL => {
                    return tf(ltchar, num_t);
                },
                c.INTEGER => {
                    return tf(num_t, bool_t);
                },
                c.CODE => {
                    return tf(char_t, num_t);
                },
                c.DECODE => {
                    return tf(num_t, char_t);
                },
                c.LENGTH => {
                    return tf(lt(NTV()), num_t);
                },
                c.ENTIER_FN, c.ARCTAN_FN, c.EXP_FN, c.SIN_FN, c.COS_FN, c.SQRT_FN, c.LOG_FN, c.LOG10_FN => {
                    return tfnumnum;
                },
                c.MINUS, c.PLUS, c.TIMES, c.INTDIV, c.FDIV, c.MOD, c.POWER => {
                    return tfnum2;
                },
                c.True, c.False => {
                    return bool_t;
                },
                NIL => {
                    const a = lt(NTV());
                    return a;
                },
                c.NILS => {
                    return ltchar;
                },
                c.MKSTRICT => {
                    const a = NTV();
                    return tf(char_t, tf(a, a));
                },
                c.G_ALT => {
                    const a = NTV();
                    return tf2(a, a, a);
                },
                c.G_ERROR => {
                    const a = NTV();
                    return tf2(a, tf(lt(bnf_t), a), a);
                },
                c.G_OPT, c.G_STAR => {
                    const a = NTV();
                    return tf(a, lt(a));
                },
                c.G_FBSTAR => {
                    const a = NTV();
                    const b = tf(a, a);
                    return tf(b, b);
                },
                c.G_SYMB => {
                    return tfstrstr;
                },
                c.G_ANY => {
                    return ltchar;
                },
                c.G_SUCHTHAT => {
                    return tf(tf(ltchar, bool_t), ltchar);
                },
                c.G_END => {
                    return lt(bnf_t);
                },
                c.G_STATE => {
                    return t(h(t(bnf_t)));
                },
                c.G_SEQ => {
                    const a = NTV();
                    const b = NTV();
                    return tf2(a, tf(a, b), b);
                },
                c.G_CLOSE => {
                    const a = NTV();
                    if (col_fn != 0) {
                        if (col_fn == -1) {
                            TYPERRS += 1;
                        } else {
                            checkcolfn();
                        }
                    }
                    return tf3(ltchar, a, lt(bnf_t), a);
                },
                c.OFFSIDE => {
                    return ltchar;
                },
                c.FAIL, c.CONFERROR, c.BADCASE, UNDEF => {
                    return NTV();
                },
                c.ERROR => {
                    return tf(ltchar, NTV());
                },
                else => {
                    _ = c.printf("do not know type of ");
                    out(getStdout().?, x);
                    _ = c.putchar('\n');
                    return wrong_t;
                },
            }
        },
        else => {
            _ = c.printf("unexpected tag in etype ");
            out(getStdout().?, tag[@intCast(x)]);
            _ = c.putchar('\n');
            return wrong_t;
        },
    }
}

export fn checkcolfn() void {
    const t_val = idType(col_fn);
    const f = tf(t(h(t(bnf_t))), num_t);
    if (t_val == undef_t or t_val == wrong_t or subsumes(instantiate(t_val), f) != 0) {
        col_fn = 0;
        return;
    }
    _ = c.printf("`bnftokenindentation' has wrong type for use in offside rule\n");
    _ = c.printf("type required :: ");
    out_type(f);
    _ = c.putchar('\n');
    _ = c.printf("  actual type :: ");
    out_type(t_val);
    _ = c.putchar('\n');
    sayhere(getspecloc(col_fn), 1);
    TYPERRS += 1;
    col_fn = -1;
}

export fn genbnft() void {
    const bnftokenstate = findid("bnftokenstate");
    if (bnftokenstate != NIL and idType(bnftokenstate) == type_t) {
        if (t_arity(bnftokenstate) == 0) {
            bnf_t = if (t_class(bnftokenstate) == synonym_t) t_info(bnftokenstate) else bnftokenstate;
        } else {
            _ = c.printf("warning - bnftokenstate has arity>0 (ignored by parser)\n");
            bnf_t = void_t;
        }
    } else {
        bnf_t = void_t;
    }
    bnf_t = ap2(comma_t, ltchar, ap2(comma_t, bnf_t, void_t));
}

export fn checktype(x: Word) Word {
    TYPERRS = 0;
    _ = etype(x, NIL, NIL);
    reset_SUBST();
    return if (TYPERRS == 0) 1 else 0;
}

export fn type_of(x: Word) Word {
    TYPERRS = 0;
    var t_val = redtvars(subst(etype(x, NIL, NIL)));
    fixshows();
    if (TYPERRS > 0) {
        t_val = wrong_t;
    }
    return t_val;
}

fn infer_type(x: Word) void {
    if (tag[@intCast(x)] == ID) {
        var t_val: Word = undefined;
        const oldte = TYPERRS;
        current_id = x;
        if (idType(x) != undef_t) {
            t_val = subst(etype(idVal(x), NIL, NIL));
            if (subsumes(t_val, instantiate(idType(x))) == 0) {
                type_error8(idType(x), t_val);
            }
        } else {
            t_val = subst(etype(idVal(x), NIL, NIL));
        }
        if (TYPERRS > oldte) {
            tp(h(x)).* = wrong_t;
            tp(x).* = UNDEF;
            ND = add1(x, ND);
        } else if (idType(x) == undef_t) {
            tp(h(x)).* = redtvars(t_val);
        }
        reset_SUBST();
    } else {
        var x1 = x;
        var oldte: Word = undefined;
        var ngt = NIL;
        while (x1 != NIL) {
            ngt = cons(NTV(), ngt);
            tp(h(h(x1))).* = ap(bind_t, h(ngt));
            x1 = t(x1);
        }
        x1 = x;
        while (x1 != NIL) {
            oldte = TYPERRS;
            current_id = h(x1);
            _ = unify(t(idType(h(x1))), etype(idVal(h(x1)), NIL, ngt));
            if (TYPERRS > oldte) {
                tp(h(h(x1))).* = wrong_t;
                tp(h(x1)).* = UNDEF;
                ND = add1(h(x1), ND);
            }
            x1 = t(x1);
        }
        x1 = x;
        while (x1 != NIL) {
            if (idType(h(x1)) != wrong_t) {
                tp(h(h(x1))).* = redtvars(ult(t(idType(h(x1)))));
            }
            x1 = t(x1);
        }
        reset_SUBST();
    }
    current_id = 0;
}


export fn tsetup() void {
    tfnum = tf(num_t, num_t);
    tfbool = tf(bool_t, bool_t);
    tfnum2 = tf(num_t, tfnum);
    tfbool2 = tf(bool_t, tfbool);
    ltchar = lt(char_t);
    tfstrstr = tf(ltchar, ltchar);
    tfnumnum = tf(num_t, num_t);
    tstep = tf2(num_t, num_t, lt(num_t));
    tstepuntil = tf(num_t, tstep);
}

export fn checktypes() void {
    ATNAMES = 0;
    TYPERRS = 0;
    NT = NIL;
    R = NIL;
    SBND = NIL;
    ND = NIL;
    if (c.setjmp(&env1[0]) == 1) {
        // jumped back on error
    } else {
        if (rfl != NIL) {
            readoption();
        }
        var s = reverse(t(h(files)));
        while (s != NIL) {
            comp_deps(h(s));
            s = t(s);
        }
        R = tclos(sortrel(R));
        if (FBS != NIL) {
            mcheckfbs();
        }
        abstr_mcheck(TABSTRS);
    }
    if (TYPERRS != 0) {
        TABSTRS = NIL;
        NT = NIL;
        R = NIL;
        _ = c.printf("typecheck cannot proceed - compilation abandoned\n");
        SYNERR = 1;
        return;
    }
    if (freeids != NIL) {
        redtfr(freeids);
    }
    genshfns();
    if (fnts != NIL) {
        genbnft();
    }
    R = msc(R);
    var s = tsort(R);
    NT = NIL;
    R = NIL;
    while (s != NIL) {
        infer_type(h(s));
        s = t(s);
    }
    checkfbs();
    while (TABSTRS != NIL) {
        abstr_check(h(TABSTRS));
        TABSTRS = t(TABSTRS);
    }
    if (SBND != NIL) {
        printlist("SPECIFIED BUT NOT DEFINED: ", alfasort(SBND));
        SBND = NIL;
    }
    fixshows();
    lastloc = 0;
}





