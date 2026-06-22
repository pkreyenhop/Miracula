const std = @import("std");
const word = @import("../runtime/word.zig");
const shim = @import("../runtime/c_abi.zig");
const main = @import("../main.zig");

const compiler_state = @import("compiler_state.zig");
const cs = &compiler_state.cs;
const abi = struct {
    pub const printf = shim.printf;
    pub const fprintf = shim.fprintf;
    pub const putchar = shim.putchar;
    pub const FILE = shim.FILE;
    pub const stderr = shim.stderr;
    pub const stdout = shim.stdout;
    pub const Y = word.Y;

    pub const G_ERROR = word.G_ERROR;
    pub const G_UNIT = word.G_UNIT;
    pub const G_RULE = word.G_RULE;
    pub const G_ZERO = word.G_ZERO;
    pub const G_ALT = word.G_ALT;
    pub const G_OPT = word.G_OPT;
    pub const G_STAR = word.G_STAR;
    pub const G_FBSTAR = word.G_FBSTAR;
    pub const G_SYMB = word.G_SYMB;
    pub const G_ANY = word.G_ANY;
    pub const G_SUCHTHAT = word.G_SUCHTHAT;
    pub const G_END = word.G_END;
    pub const G_STATE = word.G_STATE;
    pub const G_SEQ = word.G_SEQ;
    pub const G_CLOSE = word.G_CLOSE;
    pub const PLUS = word.PLUS;
    pub const MINUS = word.MINUS;
    pub const TIMES = word.TIMES;
    pub const INTDIV = word.INTDIV;
    pub const FDIV = word.FDIV;
    pub const MOD = word.MOD;
    pub const POWER = word.POWER;
    pub const S = word.S;
    pub const K = word.K;
    pub const I = word.I;
    pub const C = word.C;
    pub const B = word.B;
    pub const HD = word.HD;
    pub const TL = word.TL;
    pub const BODY = word.BODY;
    pub const LAST = word.LAST;
    pub const S_p = word.S_p;
    pub const Ug = word.Ug;
    pub const COND = word.COND;
    pub const NEG = word.NEG;
    pub const NOT = word.NOT;
    pub const STEP = word.STEP;
    pub const STEPUNTIL = word.STEPUNTIL;
    pub const SUBSCRIPT = word.SUBSCRIPT;
    pub const S1 = word.S1;
    pub const SEQ = word.SEQ;
    pub const FILEMODE = word.FILEMODE;
    pub const GETENV = word.GETENV;
    pub const NB_STARTREAD = word.NB_STARTREAD;
    pub const STARTREADBIN = word.STARTREADBIN;
    pub const STARTREAD = word.STARTREAD;
    pub const GETARGS = word.GETARGS;
    pub const SHOWHEX = word.SHOWHEX;
    pub const SHOWOCT = word.SHOWOCT;
    pub const SHOWNUM = word.SHOWNUM;
    pub const SHOWFLOAT = word.SHOWFLOAT;
    pub const SHOWSCALED = word.SHOWSCALED;
    pub const ENTIER_FN = word.ENTIER_FN;
    pub const ARCTAN_FN = word.ARCTAN_FN;
    pub const EXP_FN = word.EXP_FN;
    pub const SIN_FN = word.SIN_FN;
    pub const COS_FN = word.COS_FN;
    pub const SQRT_FN = word.SQRT_FN;
    pub const LOG_FN = word.LOG_FN;
    pub const LOG10_FN = word.LOG10_FN;
    pub const FORCE = word.FORCE;
    pub const EQ = word.EQ;
    pub const GR = word.GR;
    pub const GRE = word.GRE;
    pub const NEQ = word.NEQ;
    pub const P = word.P;
    pub const U = word.U;
    pub const U_ = word.U_;
    pub const Uf = word.Uf;
    pub const MERGE = word.MERGE;
    pub const APPEND = word.APPEND;
    pub const MAP = word.MAP;
    pub const FLATMAP = word.FLATMAP;
    pub const BADCASE = word.BADCASE;
    pub const CONFERROR = word.CONFERROR;
    pub const CB = word.CB;
    pub const AND = word.AND;
    pub const OR = word.OR;
    pub const GENSEQ = word.GENSEQ;
    pub const ZIP = word.ZIP;
    pub const TAKE = word.TAKE;
    pub const DROP = word.DROP;
    pub const FILTER = word.FILTER;
    pub const FOLDL = word.FOLDL;
    pub const FOLDL1 = word.FOLDL1;
    pub const LIST_LAST = word.LIST_LAST;
    pub const FOLDR = word.FOLDR;
    pub const MATCH = word.MATCH;
    pub const MATCHINT = word.MATCHINT;
    pub const TRY = word.TRY;
    pub const ATLEAST = word.ATLEAST;
    pub const B_p = word.B_p;
    pub const C_p = word.C_p;
    pub const B1 = word.B1;
    pub const C1 = word.C1;
    pub const ITERATE = word.ITERATE;
    pub const ITERATE1 = word.ITERATE1;
    pub const CODE = word.CODE;
    pub const DECODE = word.DECODE;
    pub const LENGTH = word.LENGTH;
    pub const FILESTAT = word.FILESTAT;
    pub const WAIT = word.WAIT;
    pub const INTEGER = word.INTEGER;
    pub const NUMVAL = word.NUMVAL;
    pub const READBIN = word.READBIN;
    pub const Ush = word.Ush;
    pub const Ush1 = word.Ush1;
    pub const KI = word.KI;
    pub const False = word.False;
    pub const True = word.True;
    pub const EXEC = word.EXEC;
    pub const NILS = word.NILS;
    pub const MKSTRICT = word.MKSTRICT;
    pub const OFFSIDE = word.OFFSIDE;
    pub const ERROR = word.ERROR;
    pub const FAIL = word.FAIL;
    pub const READ = word.READ;
};

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

const make = main.heap.make;
const reverse = main.heap.reverse;
const getspecloc = trans_mod.getspecloc;
const codegen = trans_mod.codegen;
const findid = lex_mod.findid;
const mktuple = trans_mod.mktuple;
const tclos = trans_mod.tclos;
const sortrel = trans_mod.sortrel;
const genshfns = trans_mod.genshfns;
const alfasort = main.heap.alfasort;
const readoption = main.readoption;
const out = main.heap.out;
const is_char = main.heap.is_char;
const charname = main.heap.charname;
const size = main.heap.size;
const same = trans_mod.same;
const get_dbl = main.heap.get_dbl;
const lastlink = trans_mod.lastlink;
const trans_mod = @import("trans.zig");
const lex_mod = @import("../parser/lex.zig");
const isconstrname = lex_mod.isconstrname;

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

fn cons(x: Word, y: Word) Word {
    return make(CONS, x, y);
}

pub fn remove1(e: Word, ss: *Word) Word {
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

pub export fn setdiff(s1_input: Word, s2_input: Word) Word {
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

pub export fn add1(e: Word, s_input: Word) Word {
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

pub fn newadd1(e: Word, s_input: Word) Word {
    var s = s_input;
    cs.NEW = 1;
    if (s == NIL or e < h(s)) {
        return cons(e, s);
    }
    if (e == h(s)) {
        cs.NEW = 0;
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
        cs.NEW = 0;
    }
    return s_input;
}

pub export fn UNION(s1_input: Word, s2_input: Word) Word {
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

pub export fn intersection(s1_input: Word, s2_input: Word) Word {
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

pub export fn member(s_input: Word, x: Word) Word {
    var s = s_input;
    while (s != NIL and x != h(s)) {
        s = t(s);
    }
    return if (s != NIL) 1 else 0;
}

const type_t: Word = 10;
const shunt = main.heap.shunt;

fn idType(x: Word) Word {
    return t(h(x));
}

pub export fn typesfirst(input_x: Word) Word {
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

fn getStderr() ?*word.FILE {
    const T = @TypeOf(abi.stderr);
    if (comptime @typeInfo(T) == .@"fn") {
        return abi.stderr();
    } else if (comptime @typeInfo(T) == .pointer and @typeInfo(@typeInfo(T).pointer.child) == .@"fn") {
        return abi.stderr();
    } else {
        return abi.stderr;
    }
}

pub export fn tsort(g_input: Word) Word {
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
            if (getTag(h(NP)) == ID) {
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
        _ = word.printErr("error: impossible event in tsort\n", .{});
    }
    return reverse(r);
}

pub export fn msc(R_input: Word) Word {
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
    return getTag(type_node) == AP;
}
fn isvar_t(type_node: Word) bool {
    return getTag(type_node) == TVAR;
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

pub fn sterilise(t_val: Word) void {
    if (getTag(t_val) == AP) {
        hp(t_val).* = list_t;
        tp(t_val).* = num_t;
    }
}

fn metaTcheck(t_val: Word) main.MiraError!Word {
    var tn = t_val;
    var i: Word = 0;
    while (iscompound_t(tn)) {
        tp(tn).* = try metaTcheck(t(tn));
        i += 1;
        tn = h(tn);
    }
    if (getTag(tn) != STRCONS) {
        if (getTag(tn) != ID) {
            if (i > 0 and (isvar_t(tn) or tn == bool_t or tn == num_t or tn == char_t)) {
                cs.TYPERRS += 1;
                if (getTag(cs.current_id) == DATAPAIR) {
                    locate_inc();
                    _ = word.print("badly formed type \"", .{});
                    out_type(t_val);
                    _ = word.print("\" in binding for \"{s}\"\n", .{@as([*:0]const u8, @ptrFromInt(@as(usize, @intCast(h(cs.current_id)))))});
                    _ = word.print("(", .{});
                    out_type(tn);
                    _ = word.print(" has zero arity)\n", .{});
                } else {
                    _ = word.print("badly formed type \"", .{});
                    out_type(t_val);
                    const msg: [*:0]const u8 = if (idType(cs.current_id) == type_t) "== binding" else "specification";
                    _ = word.print("\" in {s} for \"{s}\"\n", .{ msg, getId(cs.current_id) });
                    _ = word.print("(", .{});
                    out_type(tn);
                    _ = word.print(" has zero arity)\n", .{});
                    sayhere(getspecloc(cs.current_id), 1);
                }
                sterilise(t_val);
            }
            return t_val;
        } else if (idType(tn) == undef_t and idVal(tn) == UNDEF) {
            cs.TYPERRS += 1;
            if (member(cs.NT, tn) == 0) {
                if (getTag(cs.current_id) == DATAPAIR) {
                    locate_inc();
                }
                _ = word.print("undeclared typename \"{s}\" ", .{getId(tn)});
                if (getTag(cs.current_id) == DATAPAIR) {
                    _ = word.print("in binding for {s}\n", .{@as([*:0]const u8, @ptrFromInt(@as(usize, @intCast(h(cs.current_id)))))});
                } else {
                    sayhere(getspecloc(cs.current_id), 1);
                }
                cs.NT = add1(tn, cs.NT);
            }
            return t_val;
        } else if (idType(tn) != type_t or t_arity(tn) != i) {
            cs.TYPERRS += 1;
            if (getTag(cs.current_id) == DATAPAIR) {
                locate_inc();
                _ = word.print("badly formed type \"", .{});
                out_type(t_val);
                _ = word.print("\" in binding for \"{s}\"\n", .{@as([*:0]const u8, @ptrFromInt(@as(usize, @intCast(h(cs.current_id)))))});
            } else {
                _ = word.print("badly formed type \"", .{});
                out_type(t_val);
                const msg: [*:0]const u8 = if (idType(cs.current_id) == type_t) "== binding" else "specification";
                _ = word.print("\" in {s} for \"{s}\"\n", .{ msg, getId(cs.current_id) });
            }
            if (idType(tn) != type_t) {
                _ = word.print("({s} not defined as typename)\n", .{getId(tn)});
            } else {
                _ = word.print("(typename {s} has arity {d})\n", .{ getId(tn), t_arity(tn) });
            }
            if (getTag(cs.current_id) != DATAPAIR) {
                sayhere(getspecloc(cs.current_id), 1);
            }
            sterilise(t_val);
            return t_val;
        }
    }

    if (t_class(tn) != synonym_t) {
        return t_val;
    }
    if (member(cs.meta_pending, tn) != 0) {
        cs.TYPERRS += 1; // report cycle
        if (getTag(cs.current_id) == DATAPAIR) {
            locate_inc();
        }
        const suffix: [*:0]const u8 = if (cs.meta_pending == NIL) "" else "s";
        _ = word.print("error: cycle in type \"==\" definition{s} ", .{suffix});
        printelement(cs.meta_pending);
        _ = word.print("\n", .{});
        if (getTag(cs.current_id) != DATAPAIR) {
            sayhere(idWho(tn), 1);
        }
        return error.TypeCheckAbort;
    }
    cs.meta_pending = cons(tn, cs.meta_pending);
    tn = NIL;
    var cur_t = t_val;
    while (iscompound_t(cur_t)) {
        tn = cons(t(cur_t), tn);
        cur_t = h(cur_t);
    }
    const res = try metaTcheck(ap_subst(t_info(cur_t), tn));
    cs.meta_pending = t(cs.meta_pending);
    return res;
}

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
    const res = mktvar(cs.tvcount);
    cs.tvcount += 1;
    return res;
}

pub fn clear_SUBST() Word {
    fixshows();
    @memset(&cs.SUBST, 0);
    cs.tvcount = 1;
    return 0;
}

pub fn fixshows() void {
    while (cs.showchain != NIL) {
        tp(h(cs.showchain)).* = subst(t(h(cs.showchain)));
        cs.showchain = t(cs.showchain);
    }
}

pub fn lookup(tv: Word) Word {
    var h_val = cs.SUBST[hashval(tv)];
    while (h_val != 0) {
        if (eqtvar(h(h(h_val)), tv)) {
            return t(h(h_val));
        }
        h_val = t(h_val);
    }
    return tv;
}

pub fn addsubst(tv: Word, term: Word) void {
    const hv = hashval(tv);
    cs.SUBST[hv] = cons(cons(tv, term), cs.SUBST[hv]);
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

pub fn subst(term: Word) Word {
    return walktype(term, ult);
}

var NGT: Word = 0;

export fn lmap(tv: Word) Word {
    if (non_generic(tv) != 0) {
        return tv;
    }
    var l = cs.localtvmap;
    while (l != NIL) {
        if (h(h(l)) == tv) {
            return t(h(l));
        }
        l = t(l);
    }
    const new_var = NTV();
    cs.localtvmap = cons(cons(tv, new_var), cs.localtvmap);
    return new_var;
}

pub fn linst(term: Word, ngt: Word) Word {
    cs.localtvmap = NIL;
    NGT = ngt;
    return walktype(term, lmap);
}

pub fn non_generic(tv: Word) c_int {
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
    var m: *Word = &cs.tvmap;
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

pub export fn instantiate(term: Word) Word {
    cs.tvmap = NIL;
    return walktype(term, mapup);
}

pub fn ap_subst(term: Word, args: Word) Word {
    cs.tvmap = args;
    const r = walktype(term, mapup);
    cs.tvmap = NIL;
    return r;
}

export fn mapdown(tv: Word) Word {
    var m: *Word = &cs.tvmap;
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

pub export fn redtvars(term: Word) Word {
    cs.tvmap = NIL;
    return walktype(term, mapdown);
}

pub fn occurs(tv: Word, t_val: Word) c_int {
    var term = t_val;
    while (iscompound_t(term)) {
        if (occurs(tv, t(term)) != 0) {
            return 1;
        }
        term = h(term);
    }
    return if (tv == term) 1 else 0;
}

pub export fn ispoly(t_val: Word) c_int {
    var term = t_val;
    while (iscompound_t(term)) {
        if (ispoly(t(term)) != 0) {
            return 1;
        }
        term = h(term);
    }
    return if (isvar_t(term)) 1 else 0;
}

fn getStdout() ?*word.FILE {
    const T = @TypeOf(abi.stdout);
    if (comptime @typeInfo(T) == .@"fn") {
        return abi.stdout();
    } else if (comptime @typeInfo(T) == .pointer and @typeInfo(@typeInfo(T).pointer.child) == .@"fn") {
        return abi.stdout();
    } else {
        return abi.stdout;
    }
}

pub fn locate(s: [*:0]const u8) void {
    cs.TYPERRS += 1;
    if (cs.TYPERRS == 1 or cs.lastloc != cs.current_id) {
        if (cs.current_id != 0) {
            if (getTag(cs.current_id) == DATAPAIR) {
                locate_inc();
                _ = word.print("{s} in binding for {s}\n", .{ s, @as([*:0]const u8, @ptrFromInt(@as(usize, @intCast(h(cs.current_id))))) });
                return;
            }
            var x = cs.current_id;
            _ = word.print("{s} in definition of ", .{s});
            while (getTag(x) == CONS) {
                if (getTag(t(x)) == ID and member(main.rs.fnts, t(x)) != 0) {
                    _ = word.print("nonterminal ", .{});
                    x = h(x);
                } else {
                    out_formal1(getStdout().?, h(x));
                    _ = word.print(", subdef of ", .{});
                    x = t(x);
                }
            }
            _ = word.print("{s}", .{getId(x)});
            _ = word.print("\n", .{});
        } else {
            _ = word.print("{s} in expression\n", .{s});
        }
    }
    if (cs.lineptr != 0) {
        sayhere(cs.lineptr, 0);
    } else if (cs.current_id != 0 and idWho(cs.current_id) != NIL) {
        sayhere(idWho(cs.current_id), 0);
    }
    cs.lastloc = cs.current_id;
}

pub fn rhs_here(r: Word) Word {
    if (getTag(r) == LABEL) {
        return h(r);
    }
    if (getTag(r) == TRIES) {
        return h(h(lastlink(t(r))));
    }
    return 0;
}

pub export fn sayhere(h_val: Word, nl: Word) void {
    var h_node = h_val;
    if (getTag(h_node) != FILEINFO) {
        h_node = rhs_here(h_node);
        if (getTag(h_node) != FILEINFO) {
            _ = word.printErr("(impossible event in sayhere)\n", .{});
            return;
        }
    }
    const h_str = @as([*:0]const u8, @ptrFromInt(@as(usize, @intCast(h(h_node)))));
    const eq = std.mem.eql(u8, std.mem.span(h_str), std.mem.span(main.rs.current_script.?));
    const prefix: [*:0]const u8 = if (eq) "" else "%insert file ";
    word.print("(line {d:>3} of {s}\"{s}\")", .{ t(h_node), prefix, h_str });
    if (nl != 0) {
        _ = word.print("\n", .{});
    } else {
        _ = word.print(" ", .{});
    }
    if (eq) {
        if (main.errline == 0) {
            main.errline = t(h_node);
        }
    } else {
        if (main.errs == 0) {
            main.errs = h_node;
        }
    }
}

pub export fn report_type(x: Word) void {
    _ = word.print("{s}", .{getId(x)});
    if (idType(x) == type_t) {
        const arity = t_arity(x);
        if (arity > 5) {
            _ = word.print("(arity {d})", .{arity});
        } else {
            var i: Word = 1;
            while (i <= arity) : (i += 1) {
                _ = word.print(" ", .{});
                var j: Word = 0;
                while (j < i) : (j += 1) {
                    _ = word.print("*", .{});
                }
            }
        }
    }
    _ = word.print(" :: ", .{});
    out_type(idType(x));
}

pub fn type_error(a: [*:0]const u8, b: [*:0]const u8, t1_val: Word, t2_val: Word) void {
    var t1 = redtvars(ap(subst(t1_val), subst(t2_val)));
    const t2 = t(t1);
    t1 = h(t1);
    locate("type error");
    _ = word.print("cannot {s} ", .{a});
    out_type(t1);
    _ = word.print(" {s} ", .{b});
    out_type(t2);
    _ = word.print("\n", .{});
}

pub fn type_error1(x: Word) void {
    locate("type error");
    _ = word.print("typename used as identifier ({s})\n", .{getId(x)});
}

pub fn type_error2(x: Word) void {
    if (main.compiling != 0) {
        return;
    }
    cs.TYPERRS += 1;
    _ = word.print("undefined name - {s}\n", .{getId(x)});
}

pub fn type_error3(x: Word) void {
    locate("error");
    _ = word.print("constructor \"{s}\" used at wrong arity in formal\n", .{getId(x)});
}

pub fn type_error4(x: Word) void {
    locate("error");
    _ = word.print("illegal object \"", .{});
    out_pattern(getStdout().?, x);
    _ = word.print("\" as head of formal\n", .{});
}

pub fn type_error5(x: Word) void {
    locate("error");
    _ = word.print("undeclared constructor \"", .{});
    out_pattern(getStdout().?, x);
    _ = word.print("\" in formal\n", .{});
    cs.ND = add1(x, cs.ND);
}

pub fn type_error6(x: Word, f: Word, a: Word) void {
    cs.TYPERRS += 1;
    _ = word.print("incorrect declaration ", .{});
    sayhere(cs.lineptr, 1);
    _ = word.print("specified, {s} :: ", .{getId(x)});
    out_type(f);
    _ = word.print("\n", .{});
    _ = word.print("inferred,  {s} :: ", .{getId(x)});
    out_type(redtvars(subst(a)));
    _ = word.print("\n", .{});
}

pub fn type_error7(a: Word, b: Word) void {
    locate("type error");
    _ = word.print("\nrhs of lex rule :: ", .{});
    out_type(redtvars(subst(b)));
    _ = word.print("\n type expected  :: ", .{});
    out_type(redtvars(subst(a)));
    _ = word.print("\n", .{});
}

pub fn type_error8(t1_val: Word, t2_val: Word) void {
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
    _ = word.print("cannot unify{s} ", .{prefix});
    out_type(t1);
    const infix: [*:0]const u8 = if (big) "\nwith\n  " else " with ";
    _ = word.print("{s}", .{infix});
    out_type(t2);
    _ = word.print("\n", .{});
}

const comma_t: Word = 5;
const arrow_t: Word = 6;
const void_t: Word = 7;
const wrong_t: Word = 8;

fn isarrow_t(t_val: Word) bool {
    return getTag(t_val) == AP and getTag(h(t_val)) == AP and h(h(t_val)) == arrow_t;
}
fn iscomma_t(t_val: Word) bool {
    return getTag(t_val) == AP and getTag(h(t_val)) == AP and h(h(t_val)) == comma_t;
}
fn islist_t(t_val: Word) bool {
    return getTag(t_val) == AP and h(t_val) == list_t;
}

pub export fn out_type(t_val: Word) void {
    var type_node = t_val;
    while (isarrow_t(type_node)) {
        out_type1(t(h(type_node)));
        _ = word.print("->", .{});
        type_node = t(type_node);
    }
    out_type1(type_node);
}

pub fn out_type1(t_val: Word) void {
    var type_node = t_val;
    if (iscompound_t(type_node) and !iscomma_t(type_node) and !islist_t(type_node) and !isarrow_t(type_node)) {
        out_type1(h(type_node));
        _ = word.print(" ", .{});
        type_node = t(type_node);
    }
    out_type2(type_node);
}

pub fn out_type2(t_val: Word) void {
    if (islist_t(t_val)) {
        _ = word.print("[", .{});
        out_type(t(t_val));
        _ = word.print("]", .{});
    } else if (iscompound_t(t_val)) {
        _ = word.print("(", .{});
        out_typel(t_val);
        if (iscomma_t(t_val) and t(t_val) == void_t) {
            _ = word.print(",", .{});
        }
        _ = word.print(")", .{});
    } else {
        switch (t_val) {
            bool_t => {
                _ = word.print("bool", .{});
            },
            num_t => {
                _ = word.print("num", .{});
            },
            char_t => {
                _ = word.print("char", .{});
            },
            wrong_t => {
                _ = word.print("WRONG", .{});
            },
            undef_t => {
                _ = word.print("UNKNOWN", .{});
            },
            void_t => {
                _ = word.print("()", .{});
            },
            type_t => {
                _ = word.print("type", .{});
            },
            else => {
                if (getTag(t_val) == ID) {
                    _ = word.print("{s}", .{getId(t_val)});
                } else if (isvar_t(t_val)) {
                    var n = gettvar(t_val);
                    if (n > 0 and n < 7) {
                        while (n > 0) : (n -= 1) {
                            _ = word.print("*", .{});
                        }
                    } else {
                        _ = word.print("{d}", .{n});
                    }
                } else if (getTag(t_val) == STRCONS) {
                    const pn_val_node = pn_val(t_val);
                    if (getTag(pn_val_node) == ID) {
                        _ = word.print("{s}", .{getId(pn_val_node)});
                    } else if (std.mem.eql(u8, std.mem.span(@as([*:0]const u8, @ptrFromInt(@as(usize, @intCast(h(t(t_info(t_val)))))))), std.mem.span(main.rs.current_script.?))) {
                        _ = word.print("{s}", .{@as([*:0]const u8, @ptrFromInt(@as(usize, @intCast(h(h(t_info(t_val)))))))});
                    } else {
                        _ = word.print("`{s}@{s}'", .{ @as([*:0]const u8, @ptrFromInt(@as(usize, @intCast(h(h(t_info(t_val))))))), @as([*:0]const u8, @ptrFromInt(@as(usize, @intCast(h(t(t_info(t_val))))))) });
                    }
                } else {
                    _ = word.print("<BADLY FORMED TYPE:{d},{d},{d}>", .{ getTag(t_val), h(t_val), t(t_val) });
                }
            },
        }
    }
}

pub fn out_typel(t_val: Word) void {
    var type_node = t_val;
    while (iscomma_t(type_node)) {
        out_type(t(h(type_node)));
        type_node = t(type_node);
        if (iscomma_t(type_node)) {
            _ = word.print(",", .{});
        } else if (type_node != void_t) {
            _ = word.print("<>", .{});
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

pub fn tail(x_in: Word) Word {
    var x = x_in;
    allchars = 1;
    while (getTag(x) == CONS) {
        const char_res = is_char(h(x));
        allchars = if (char_res != 0) allchars & 1 else 0;
        x = t(x);
    }
    return x;
}

pub fn out_formal1(f: *word.FILE, x_in: Word) void {
    var x = x_in;
    if (h(x) == CONST) {
        x = t(x);
    }
    if (x == NIL) {
        _ = (f).print("[]", .{});
    } else if (getTag(x) == CONS and tail(x) == NIL) {
        if (allchars != 0) {
            _ = (f).print("\"", .{});
            while (x != NIL) {
                _ = (f).print("{s}", .{charname(h(x))});
                x = t(x);
            }
            _ = (f).print("\"", .{});
        } else {
            _ = (f).print("[", .{});
            while (x != main.nill and x != NIL) {
                out_pattern(f, h(x));
                x = t(x);
                if (x != main.nill and x != NIL) {
                    _ = (f).print(",", .{});
                }
            }
            _ = (f).print("]", .{});
        }
    } else if (getTag(x) == AP or getTag(x) == CONS) {
        _ = (f).print("(", .{});
        out_pattern(f, x);
        _ = (f).print(")", .{});
    } else if (getTag(x) == TCONS or getTag(x) == PAIR) {
        _ = (f).print("(", .{});
        while (getTag(x) == TCONS) {
            out_pattern(f, h(x));
            x = t(x);
            _ = (f).print(",", .{});
        }
        out_pattern(f, h(x));
        _ = (f).print(",", .{});
        out_pattern(f, t(x));
        _ = (f).print(")", .{});
    } else if ((getTag(x) == INT and neg(x) != 0) or (getTag(x) == DOUBLE and get_dbl(x) < 0)) {
        _ = (f).print("(", .{});
        out(f, x);
        _ = (f).print(")", .{});
    } else {
        out(f, x);
    }
}

pub export fn out_pattern(f: *word.FILE, x: Word) void {
    if (getTag(x) == CONS) {
        if (h(x) == CONST and (getTag(t(x)) == INT or getTag(t(x)) == DOUBLE)) {
            out(f, t(x));
        } else if (h(x) != CONST and tail(x) != NIL) {
            out_formal(f, h(x));
            _ = (f).print(":", .{});
            out_pattern(f, t(x));
        } else {
            out_formal(f, x);
        }
    } else {
        out_formal(f, x);
    }
}

pub fn out_formal(f: *word.FILE, x: Word) void {
    if (getTag(x) != AP) {
        out_formal1(f, x);
    } else if (getTag(h(x)) == AP and h(h(x)) == PLUS) {
        out_formal(f, t(x));
        _ = (f).print("+", .{});
        out(f, t(h(x)));
    } else {
        out_formal(f, h(x));
        _ = (f).print(" ", .{});
        out_formal1(f, t(x));
    }
}

const CONST: Word = 268;

fn isConstructor(x: Word) bool {
    return getTag(x) == ID and isconstrname(getId(x)) != 0;
}

pub fn rembvars(x_in: Word, p_in: Word) Word {
    var x = x_in;
    var p = p_in;
    while (true) {
        switch (getTag(p)) {
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
                if (getTag(h(p)) == AP and h(h(p)) == PLUS) {
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
                _ = word.printErr("impossible event in rembvars\n", .{});
                return x;
            },
        }
    }
}

pub export fn deps(x_in: Word) Word {
    var x = x_in;
    var d = NIL;
    while (true) {
        switch (getTag(x)) {
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

fn compDeps(n: Word) main.MiraError!void {
    var rhs = NIL;
    var r: Word = 0;
    if (idType(n) == type_t) {
        switch (t_class(n)) {
            algebraic_t => {
                r = t_info(n);
                while (r != NIL) {
                    cs.current_id = h(r);
                    tp(h(h(r))).* = redtvars(try metaTcheck(idType(h(r))));
                    r = t(r);
                }
            },
            synonym_t => {
                cs.current_id = n;
                tp(t(t(n))).* = try metaTcheck(t_info(n));
            },
            abstract_t => {
                if (t_info(n) == undef_t) {
                    _ = word.print("error: script contains no binding for abstract typename \"{s}\"\n", .{getId(n)});
                    sayhere(idWho(n), 1);
                    cs.TYPERRS += 1;
                } else {
                    cs.current_id = n;
                    tp(t(t(n))).* = try metaTcheck(t_info(n));
                }
            },
            else => {},
        }
        cs.current_id = 0;
        return;
    }
    if (getTag(t(n)) == CONSTRUCTOR) {
        return;
    }
    if (idType(n) != undef_t) {
        cs.current_id = n;
        if (getTag(idType(n)) == CONS) {
            if (t(n) == UNDEF) {
                cs.SBND = add1(n, cs.SBND);
            }
            tp(h(n)).* = redtvars(try metaTcheck(h(idType(n))));
            cs.current_id = 0;
            return;
        }
        tp(h(n)).* = redtvars(try metaTcheck(idType(n)));
        cs.current_id = 0;
    }
    if (t(n) == FREE) {
        return;
    }
    if (t(n) == UNDEF) {
        cs.SBND = add1(n, cs.SBND);
        return;
    }
    r = deps(t(n));
    while (r != NIL) {
        if (t(h(r)) != UNDEF and idType(h(r)) == undef_t) {
            rhs = add1(h(r), rhs);
        }
        r = t(r);
    }
    cs.R = cons(cons(n, rhs), cs.R);
}

const algebraic_t: Word = 0;
const FREE: Word = 276;

pub fn redtfr(x_in: Word) void {
    var x = x_in;
    while (x != NIL) {
        tp(t(h(x))).* = idType(h(h(x)));
        x = t(x);
    }
}

pub fn printelement(x: Word) void {
    if (getTag(x) != CONS) {
        out(getStdout().?, x);
        return;
    }
    _ = word.print("(", .{});
    var cur = x;
    while (cur != NIL) {
        out(getStdout().?, h(cur));
        cur = t(cur);
        if (cur != NIL) {
            _ = word.print(" ", .{});
        }
    }
    _ = word.print(")", .{});
}

pub export fn printlist(title: [*:0]const u8, l_in: Word) void {
    var l = l_in;
    _ = word.print("{s}", .{title});
    while (l != NIL) {
        printelement(h(l));
        l = t(l);
        if (l != NIL) {
            _ = word.print(",", .{});
        }
    }
    _ = word.print(";\n", .{});
}

fn id_who(x: Word) Word {
    return t(h(h(x)));
}

fn the_val(x: Word) Word {
    return t(x);
}

fn resetSubst() void {
    cs.current_id = if (cs.tvcount >= @as(Word, @intCast(hashsize))) clear_SUBST() else 0;
}

pub fn locate_inc() void {
    if (cs.lasthereinc == cs.hereinc) {
        return;
    }
    _ = word.print("incorrect %include directive ", .{});
    cs.lasthereinc = cs.hereinc;
    sayhere(cs.hereinc, 1);
}

pub fn cyclic_abstr(atnames: Word) Word {
    var x = atnames;
    var y = NIL;
    while (x != NIL) {
        y = ap(y, t_info(h(x)));
        x = t(x);
    }
    x = atnames;
    while (x != NIL) {
        if (occurs(h(x), y) != 0) {
            _ = word.print("illegal type abstraction: cycle in \"==\" binding{s} ", .{if (t(atnames) == NIL) @as([*:0]const u8, "") else @as([*:0]const u8, "s")});
            printelement(atnames);
            _ = word.putchar('\n');
            sayhere(id_who(h(x)), 1);
            cs.TYPERRS += 1;
            return 1;
        }
        x = t(x);
    }
    return 0;
}

pub fn txchange(ids_in: Word, x_in: Word) void {
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

pub fn rep_t1(T: Word, L: Word) Word {
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

pub fn rep_t(T: Word, L: Word) Word {
    const t_val = rep_t1(T, L);
    return if (t_val == T) t_val else redtvars(t_val);
}

pub fn fix_type(t_val: Word) Word {
    var t_node = t_val;
    switch (getTag(t_node)) {
        AP, CONS => {
            tp(t_node).* = fix_type(t(t_node));
            hp(t_node).* = fix_type(h(t_node));
            return t_node;
        },
        STRCONS => {
            while (getTag(pn_val(t_node)) != CONS) {
                t_node = pn_val(t_node);
            }
            return t_node;
        },
        else => {
            return t_node;
        },
    }
}

fn abstrCheck(x_in: Word) main.MiraError!void {
    var x = x_in;
    const rtypes = t(h(x));
    const sigids = t(x);
    cs.ATNAMES = h(h(x));
    txchange(sigids, rtypes); // install representation types
    x = sigids;
    while (x != NIL) {
        const oldte = cs.TYPERRS;
        cs.current_id = h(x);
        const t_val = subst(try etype(idVal(h(x)), NIL, NIL));
        if (subsumes(t_val, instantiate(idType(h(x)))) == 0) {
            cs.TYPERRS += 1;
            _ = word.print("abstype implementation error\n", .{});
            _ = word.print("\"{s}\" is bound to value of type: ", .{getId(h(x))});
            out_type(redtvars(t_val));
            _ = word.print("\ntype expected: ", .{});
            out_type(idType(h(x)));
            _ = word.putchar('\n');
            sayhere(id_who(h(x)), 1);
        }
        if (cs.TYPERRS > oldte) {
            tp(h(h(x))).* = wrong_t;
            tp(h(x)).* = UNDEF;
            cs.ND = add1(h(x), cs.ND);
        }
        resetSubst();
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
    cs.ATNAMES = 0;
}

fn abstrMcheck(tabstrs_in: Word) main.MiraError!void {
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
                rtypes = cons(try metaTcheck(t_val), rtypes);
            }
            sigids = t(sigids);
        }
        rtypes = reverse(rtypes);
        hp(h(tabstrs)).* = cons(h(h(tabstrs)), rtypes);
        tabstrs = t(tabstrs);
    }
}

fn mcheckfbs() main.MiraError!void {
    var ff: Word = undefined;
    var formals: Word = undefined;
    var n: Word = undefined;
    cs.lasthereinc = 0;
    ff = cs.FBS;
    while (ff != NIL) {
        cs.hereinc = h(h(cs.FBS));
        formals = t(h(ff));
        while (formals != NIL) {
            const t_val = t(t(h(formals)));
            if (t_val != type_t) {
                formals = t(formals);
                continue;
            }
            cs.current_id = h(t(h(formals))); // nb datapair(orig,0) not id
            tp(t(t(h(h(formals))))).* = try metaTcheck(t_info(h(h(formals))));
            cs.current_id = 0;
            formals = t(formals);
        }
        if (cs.TYPERRS != 0) {
            return; // to avoid misleading error messages
        }
        formals = t(h(ff));
        while (formals != NIL) {
            const t_val = t(t(h(formals)));
            if (t_val == type_t) {
                formals = t(formals);
                continue;
            }
            cs.current_id = h(t(h(formals))); // nb datapair(orig,0) not id
            tp(t(h(formals))).* = redtvars(try metaTcheck(t_val));
            cs.current_id = 0;
            formals = t(formals);
        }
        ff = t(ff);
    }
    if (cs.TYPERRS != 0) {
        return;
    }
    ff = t(main.files);
    while (ff != NIL) {
        formals = t(h(ff));
        while (formals != NIL) {
            n = h(formals);
            if (getTag(n) == ID) {
                if (idType(n) == type_t) {
                    if (t_class(n) == synonym_t) {
                        tp(t(t(n))).* = try metaTcheck(t_info(n));
                    }
                } else {
                    tp(h(n)).* = redtvars(try metaTcheck(idType(n)));
                }
            }
            formals = t(formals);
        }
        ff = t(ff);
    }
}

pub fn checkfbs() void {
    const oldte = cs.TYPERRS;
    var formals: Word = undefined;
    cs.lasthereinc = 0;
    while (cs.FBS != NIL) {
        cs.hereinc = h(h(cs.FBS));
        formals = t(h(cs.FBS));
        while (formals != NIL) {
            var t_val: Word = undefined;
            const t1 = fix_type(t(t(h(formals))));
            if (t1 == type_t) {
                formals = t(formals);
                continue;
            }
            cs.current_id = h(t(h(formals))); // nb datapair(orig,0) not id
            t_val = subst(etype(the_val(h(h(formals))), NIL, NIL) catch return);
            if (subsumes(t_val, instantiate(t1)) == 0) {
                cs.TYPERRS += 1;
                locate_inc();
                _ = word.print("binding for parameter `{s}' has wrong type\n", .{@as([*:0]const u8, @ptrFromInt(@as(usize, @intCast(h(cs.current_id)))))});
                _ = word.print("required :: ", .{});
                out_type(t(t(h(formals))));
                _ = word.print("\n  actual :: ", .{});
                out_type(redtvars(t_val));
                _ = word.putchar('\n');
            }
            tp(t(h(h(formals)))).* = codegen(the_val(h(h(formals))));
            formals = t(formals);
        }
        cs.FBS = t(cs.FBS);
    }
    if (cs.TYPERRS > oldte) { // badly typed parameter bindings, so give up
        cs.TABSTRS = NIL;
        cs.NT = NIL;
        cs.R = NIL;
        _ = word.printErr("compilation abandoned\n", .{});
        main.SYNERR = 1;
    }
    resetSubst();
}

pub export fn genlstat_t() Word {
    if (cs.filestat_t == 0) {
        cs.filestat_t = tf(cs.ltchar, pair_t(pair_t(num_t, num_t), num_t));
    }
    return cs.filestat_t;
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

pub fn subsu1(t1_in: Word, t2: Word, T2: Word) Word {
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

pub export fn subsumes(t1: Word, t2: Word) Word {
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

fn conforms(p: Word, t_val: Word, e_in: Word, ngt: Word) main.MiraError!Word {
    var e = e_in;
    if (e == -1) {
        return -1;
    }
    if (getTag(p) == ID and !isConstructor(p)) {
        return cons(cons(p, t_val), e);
    }
    if (h(p) == CONST) {
        _ = unify(try etype(t(p), e, ngt), t_val);
        return e;
    }
    if (getTag(p) == CONS) {
        const at = NTV();
        if (unify(lt(at), t_val) == 0) {
            return -1;
        }
        return try conforms(t(p), t_val, try conforms(h(p), at, e, ngt), ngt);
    }
    if (getTag(p) == TCONS) {
        const at = NTV();
        const bt = NTV();
        if (unify(ap2(comma_t, at, bt), t_val) == 0) {
            return -1;
        }
        return try conforms(t(p), bt, try conforms(h(p), at, e, ngt), ngt);
    }
    if (getTag(p) == PAIR) {
        const at = NTV();
        const bt = NTV();
        if (unify(ap2(comma_t, at, ap2(comma_t, bt, void_t)), t_val) == 0) {
            return -1;
        }
        return try conforms(t(p), bt, try conforms(h(p), at, e, ngt), ngt);
    }
    if (getTag(p) == AP and getTag(h(p)) == AP and h(h(p)) == word.PLUS) { // n+k pattern
        if (unify(num_t, t_val) == 0) {
            return 1;
        }
        return try conforms(t(p), num_t, e, ngt);
    }
    {
        var p_args = NIL;
        var pt: Word = undefined;
        var cur_p = p;
        while (getTag(cur_p) == AP) {
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
        pt = instantiate(if (cs.ATNAMES != 0) rep_t(idType(cur_p), cs.ATNAMES) else idType(cur_p));
        while (p_args != NIL and isarrow_t(pt)) {
            e = try conforms(h(p_args), t(h(pt)), e, ngt);
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

fn etype(x: Word, env: Word, ngt: Word) main.MiraError!Word {
    switch (getTag(x)) {
        AP => {
            if (h(x) == word.BADCASE or h(x) == word.CONFERROR) {
                return NTV();
            }
            const ft_val = try etype(h(x), env, ngt);
            const at = try etype(t(x), env, ngt);
            const rt = NTV();
            if (unify1(ft_val, ap2(arrow_t, at, rt)) == 0) {
                const ft = subst(ft_val);
                if (isarrow_t(ft)) {
                    if (getTag(h(x)) == AP and h(h(x)) == word.G_ERROR) {
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
            const elem_type = NTV();
            const list_type = lt(elem_type);

            // 1. Find the tail of the CONS chain
            var cur = x;
            while (getTag(cur) == CONS) {
                cur = t(cur);
            }
            const tail_expr = cur;

            // 2. Type check the tail
            const tail_type = try etype(tail_expr, env, ngt);
            if (unify1(list_type, tail_type) == 0) {
                // Find the last CONS node to report the error on
                var last_cons = x;
                while (t(last_cons) != tail_expr) {
                    last_cons = t(last_cons);
                }
                const ht = try etype(h(last_cons), env, ngt);
                type_error("cons", "to", ht, tail_type);
                return NTV();
            }

            // 3. Type check each head in the chain
            cur = x;
            while (getTag(cur) == CONS) {
                const ht = try etype(h(cur), env, ngt);
                if (unify1(ht, elem_type) == 0) {
                    const rt = try etype(t(cur), env, ngt);
                    type_error("cons", "to", ht, rt);
                    return NTV();
                }
                cur = t(cur);
            }
            return list_type;
        },
        LEXER => {
            const hold = cs.lineptr;
            cs.lineptr = h(t(t(h(x))));
            tp(t(h(x))).* = t(t(t(h(x))));
            const a = try etype(t(t(h(x))), env, ngt);
            var cur_x = x;
            while (true) {
                cur_x = t(cur_x);
                if (cur_x == NIL) break;
                cs.lineptr = h(t(t(h(cur_x))));
                tp(t(h(cur_x))).* = t(t(t(h(cur_x))));
                const b = try etype(t(t(h(cur_x))), env, ngt);
                if (unify1(a, b) == 0) {
                    type_error7(a, b);
                    cs.lineptr = hold;
                    return NTV();
                }
            }
            cs.lineptr = hold;
            return tf(cs.ltchar, lt(a));
        },
        TCONS => {
            return ap2(comma_t, try etype(h(x), env, ngt), try etype(t(x), env, ngt));
        },
        PAIR => {
            return ap2(comma_t, try etype(h(x), env, ngt), ap2(comma_t, try etype(t(x), env, ngt), void_t));
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
                if (main.commandmode != 0) {
                    type_error2(x);
                } else if (member(cs.ND, x) == 0) {
                    if (cs.lineptr != 0) {
                        sayhere(cs.lineptr, 0);
                    } else if (getTag(cs.current_id) == DATAPAIR) {
                        locate_inc();
                    }
                    _ = word.print("undefined name \"{s}\"\n", .{getId(x)});
                    cs.ND = add1(x, cs.ND);
                }
                return NTV();
            }
            if (a == wrong_t) {
                return NTV();
            }
            return instantiate(if (cs.ATNAMES != 0) rep_t(a, cs.ATNAMES) else a);
        },
        LAMBDA => {
            const a = NTV();
            const b = NTV();
            const d = cons(a, ngt);
            const c_local = try conforms(h(x), a, env, d);
            if (c_local == -1 or unify(b, try etype(t(x), c_local, d)) == 0) {
                return NTV();
            }
            return tf(a, b);
        },
        LET => {
            var e: Word = undefined;
            const def = h(x);
            const a = NTV();
            e = try conforms(dlhs(def), a, env, cons(a, ngt));
            cs.current_id = cons(dlhs(def), cs.current_id);
            const c_local = cs.lineptr;
            cs.lineptr = dval(def);
            const unified = unify(a, try etype(dval(def), env, ngt));
            cs.lineptr = c_local;
            cs.current_id = t(cs.current_id);
            if (e == -1 or unified == 0) {
                return NTV();
            }
            return try etype(t(x), e, ngt);
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
                    e = try conforms(dlhs(h(cur_d)), b, e, c_local);
                } else {
                    hp(t(h(cur_d))).* = try metaTcheck(dtyp(h(cur_d)));
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
                cs.current_id = cons(dlhs(h(cur_a)), cs.current_id);
                const hold = cs.lineptr;
                cs.lineptr = dval(h(cur_a));
                if (unify(dtyp(h(cur_a)), try etype(dval(h(cur_a)), e, c_local)) == 0) {
                    success = false;
                }
                cs.lineptr = hold;
                cs.current_id = t(cs.current_id);
                cur_a = t(cur_a);
            }
            var cur_s = s;
            while (cur_s != NIL) {
                cs.current_id = cons(dlhs(h(cur_s)), cs.current_id);
                const hold = cs.lineptr;
                cs.lineptr = dval(h(cur_s));
                const ety = try etype(dval(h(cur_s)), e, ngt);
                if (subsumes(ety, linst(dtyp(h(cur_s)), ngt)) == 0) {
                    success = false;
                    type_error6(dlhs(h(cur_s)), dtyp(h(cur_s)), ety);
                }
                cs.lineptr = hold;
                cs.current_id = t(cs.current_id);
                cur_s = t(cur_s);
            }
            if (!success) {
                return NTV();
            }
            return try etype(t(x), e, ngt);
        },
        TRIES => {
            const hold = cs.lineptr;
            const a = NTV();
            var cur_x = t(x);
            while (cur_x != NIL) {
                cs.lineptr = h(h(cur_x));
                if (unify(a, try etype(t(h(cur_x)), env, ngt)) == 0) {
                    break;
                }
                cur_x = t(cur_x);
            }
            cs.lineptr = hold;
            if (cur_x != NIL) {
                return NTV();
            }
            return a;
        },
        LABEL => {
            const hold = cs.lineptr;
            cs.lineptr = h(x);
            const ty = try etype(t(x), env, ngt);
            cs.lineptr = hold;
            return ty;
        },
        STARTREADVALS => {
            if (t(x) == 0) {
                hp(x).* = cs.lineptr;
                tp(x).* = NTV();
                cs.showchain = cons(x, cs.showchain);
            }
            return tf(cs.ltchar, lt(t(x)));
        },
        SHOW => {
            hp(x).* = cs.lineptr;
            cs.showchain = cons(x, cs.showchain);
            tp(x).* = NTV();
            return tf(t(x), cs.ltchar);
        },
        SHARE => {
            if (t(x) == undef_t) {
                const hold = cs.TYPERRS;
                tp(x).* = subst(try etype(h(x), env, ngt));
                if (cs.TYPERRS > hold) {
                    hp(x).* = UNDEF;
                    tp(x).* = wrong_t;
                }
            }
            if (t(x) == wrong_t) {
                cs.TYPERRS += 1;
                return NTV();
            }
            return t(x);
        },
        CONSTRUCTOR => {
            const a = idType(t(x));
            return instantiate(if (cs.ATNAMES != 0) rep_t(a, cs.ATNAMES) else a);
        },
        UNICODE => {
            return char_t;
        },
        ATOM => {
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
                    return cs.tfnum;
                },
                word.AND, word.OR => {
                    return cs.tfbool2;
                },
                word.NOT => {
                    return cs.tfbool;
                },
                word.MERGE, word.APPEND => {
                    const a = lt(NTV());
                    return tf2(a, a, a);
                },
                word.STEP => {
                    return cs.tstep;
                },
                word.STEPUNTIL => {
                    return cs.tstepuntil;
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
                    return tf2(lt(a), lt(b), lt(pair_t(a, b)));
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
                    if (cs.exec_t == 0) {
                        const a = ap2(comma_t, cs.ltchar, ap2(comma_t, num_t, void_t));
                        cs.exec_t = tf(cs.ltchar, ap2(comma_t, cs.ltchar, a));
                    }
                    return cs.exec_t;
                },
                word.READBIN, word.READ => {
                    if (cs.read_t == 0) {
                        cs.read_t = tf(char_t, cs.ltchar);
                    }
                    return cs.read_t;
                },
                word.FILESTAT => {
                    return genlstat_t();
                },
                word.FILEMODE, word.GETENV, word.NB_STARTREAD, word.STARTREADBIN, word.STARTREAD => {
                    return cs.tfstrstr;
                },
                word.GETARGS => {
                    return tf(char_t, lt(cs.ltchar));
                },
                word.SHOWHEX, word.SHOWOCT, word.SHOWNUM => {
                    return tf(num_t, cs.ltchar);
                },
                word.SHOWFLOAT, word.SHOWSCALED => {
                    return tf2(num_t, num_t, cs.ltchar);
                },
                word.NUMVAL => {
                    return tf(cs.ltchar, num_t);
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
                    return cs.tfnumnum;
                },
                word.MINUS, word.PLUS, word.TIMES, word.INTDIV, word.FDIV, word.MOD, word.POWER => {
                    return cs.tfnum2;
                },
                word.True, word.False => {
                    return bool_t;
                },
                NIL => {
                    const a = lt(NTV());
                    return a;
                },
                word.NILS => {
                    return cs.ltchar;
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
                    return tf2(a, tf(lt(cs.bnf_t), a), a);
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
                    return cs.tfstrstr;
                },
                word.G_ANY => {
                    return cs.ltchar;
                },
                word.G_SUCHTHAT => {
                    return tf(tf(cs.ltchar, bool_t), cs.ltchar);
                },
                word.G_END => {
                    return lt(cs.bnf_t);
                },
                word.G_STATE => {
                    return t(h(t(cs.bnf_t)));
                },
                word.G_SEQ => {
                    const a = NTV();
                    const b = NTV();
                    return tf2(a, tf(a, b), b);
                },
                word.G_CLOSE => {
                    const a = NTV();
                    if (main.rs.col_fn != 0) {
                        if (main.rs.col_fn == -1) {
                            cs.TYPERRS += 1;
                        } else {
                            checkcolfn();
                        }
                    }
                    return tf3(cs.ltchar, a, lt(cs.bnf_t), a);
                },
                word.OFFSIDE => {
                    return cs.ltchar;
                },
                word.FAIL, word.CONFERROR, word.BADCASE, UNDEF => {
                    return NTV();
                },
                word.ERROR => {
                    return tf(cs.ltchar, NTV());
                },
                else => {
                    _ = word.print("do not know type of ", .{});
                    out(getStdout().?, x);
                    _ = word.putchar('\n');
                    return wrong_t;
                },
            }
        },
        else => {
            _ = word.print("unexpected tag in etype ", .{});
            out(getStdout().?, getTag(x));
            _ = word.putchar('\n');
            return wrong_t;
        },
    }
}

pub fn checkcolfn() void {
    const t_val = idType(main.rs.col_fn);
    const f = tf(t(h(t(cs.bnf_t))), num_t);
    if (t_val == undef_t or t_val == wrong_t or subsumes(instantiate(t_val), f) != 0) {
        main.rs.col_fn = 0;
        return;
    }
    _ = word.print("`bnftokenindentation' has wrong type for use in offside rule\n", .{});
    _ = word.print("type required :: ", .{});
    out_type(f);
    _ = word.putchar('\n');
    _ = word.print("  actual type :: ", .{});
    out_type(t_val);
    _ = word.putchar('\n');
    sayhere(getspecloc(main.rs.col_fn), 1);
    cs.TYPERRS += 1;
    main.rs.col_fn = -1;
}

pub fn genbnft() void {
    const bnftokenstate = findid("bnftokenstate");
    if (bnftokenstate != NIL and idType(bnftokenstate) == type_t) {
        if (t_arity(bnftokenstate) == 0) {
            cs.bnf_t = if (t_class(bnftokenstate) == synonym_t) t_info(bnftokenstate) else bnftokenstate;
        } else {
            _ = word.print("warning - bnftokenstate has arity>0 (ignored by parser)\n", .{});
            cs.bnf_t = void_t;
        }
    } else {
        cs.bnf_t = void_t;
    }
    cs.bnf_t = ap2(comma_t, cs.ltchar, ap2(comma_t, cs.bnf_t, void_t));
}

pub fn checktype(x: Word) Word {
    cs.TYPERRS = 0;
    _ = etype(x, NIL, NIL) catch return 0;
    resetSubst();
    return if (cs.TYPERRS == 0) 1 else 0;
}

pub export fn type_of(x: Word) Word {
    cs.TYPERRS = 0;
    var t_val = redtvars(subst(etype(x, NIL, NIL) catch return wrong_t));
    fixshows();
    if (cs.TYPERRS > 0) {
        t_val = wrong_t;
    }
    return t_val;
}

fn inferType(x: Word) void {
    if (getTag(x) == ID) {
        var t_val: Word = undefined;
        const oldte = cs.TYPERRS;
        cs.current_id = x;
        if (idType(x) != undef_t) {
            t_val = subst(etype(idVal(x), NIL, NIL) catch return);
            if (subsumes(t_val, instantiate(idType(x))) == 0) {
                type_error8(idType(x), t_val);
            }
        } else {
            t_val = subst(etype(idVal(x), NIL, NIL) catch return);
        }
        if (cs.TYPERRS > oldte) {
            tp(h(x)).* = wrong_t;
            tp(x).* = UNDEF;
            cs.ND = add1(x, cs.ND);
        } else if (idType(x) == undef_t) {
            tp(h(x)).* = redtvars(t_val);
        }
        resetSubst();
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
            oldte = cs.TYPERRS;
            cs.current_id = h(x1);
            _ = unify(t(idType(h(x1))), etype(idVal(h(x1)), NIL, ngt) catch return);
            if (cs.TYPERRS > oldte) {
                tp(h(h(x1))).* = wrong_t;
                tp(h(x1)).* = UNDEF;
                cs.ND = add1(h(x1), cs.ND);
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
        resetSubst();
    }
    cs.current_id = 0;
}

pub export fn tsetup() void {
    cs.tfnum = tf(num_t, num_t);
    cs.tfbool = tf(bool_t, bool_t);
    cs.tfnum2 = tf(num_t, cs.tfnum);
    cs.tfbool2 = tf(bool_t, cs.tfbool);
    cs.ltchar = lt(char_t);
    cs.tfstrstr = tf(cs.ltchar, cs.ltchar);
    cs.tfnumnum = tf(num_t, num_t);
    cs.tstep = tf2(num_t, num_t, lt(num_t));
    cs.tstepuntil = tf(num_t, cs.tstep);
}

pub export fn checktypes() void {
    cs.ATNAMES = 0;
    cs.TYPERRS = 0;
    cs.NT = NIL;
    cs.R = NIL;
    cs.SBND = NIL;
    cs.ND = NIL;
    outer: {
        if (main.rs.rfl != NIL) {
            readoption();
        }
        var s = reverse(t(h(main.files)));
        while (s != NIL) {
            compDeps(h(s)) catch break :outer;
            s = t(s);
        }
        cs.R = tclos(sortrel(cs.R));
        if (cs.FBS != NIL) {
            mcheckfbs() catch break :outer;
        }
        abstrMcheck(cs.TABSTRS) catch break :outer;
    }
    if (cs.TYPERRS != 0) {
        cs.TABSTRS = NIL;
        cs.NT = NIL;
        cs.R = NIL;
        _ = word.printErr("typecheck cannot proceed - compilation abandoned\n", .{});
        main.SYNERR = 1;
        return;
    }
    if (main.rs.freeids != NIL) {
        redtfr(main.rs.freeids);
    }
    genshfns();
    if (main.rs.fnts != NIL) {
        genbnft();
    }
    cs.R = msc(cs.R);
    var s = tsort(cs.R);
    cs.NT = NIL;
    cs.R = NIL;
    while (s != NIL) {
        inferType(h(s));
        s = t(s);
    }
    checkfbs();
    while (cs.TABSTRS != NIL) {
        abstrCheck(h(cs.TABSTRS)) catch {};
        cs.TABSTRS = t(cs.TABSTRS);
    }
    if (cs.SBND != NIL) {
        printlist("SPECIFIED BUT NOT DEFINED: ", alfasort(cs.SBND));
        cs.SBND = NIL;
    }
    fixshows();
    cs.lastloc = 0;
}
