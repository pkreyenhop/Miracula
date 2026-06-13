const std = @import("std");

const clib = @cImport({
    @cInclude("data.h");
    @cInclude("parser_bridge.h");
});

const Word = clib.word;

extern var listdiff_fn: Word;
extern var errs: Word;
extern var inbnf: Word;
extern var echoing: Word;

extern var hd: [*]Word;
extern var tl: [*]Word;
extern var tag: [*]u8;

inline fn h(x: Word) Word {
    return hd[@as(usize, @intCast(x)) * 2];
}
inline fn t(x: Word) Word {
    return tl[@as(usize, @intCast(x)) * 2];
}
inline fn tg(x: Word) u8 {
    return tag[@as(usize, @intCast(x))];
}
inline fn get_id(x: Word) [*:0]const u8 {
    return @ptrFromInt(@as(usize, @intCast(h(h(h(x))))));
}

// Native Zig shims for C macros to ensure 100% robust compilation and execution
inline fn ap(x: Word, y: Word) Word {
    return clib.make(clib.AP, x, y);
}
inline fn ap2(x: Word, y: Word, z: Word) Word {
    return ap(ap(x, y), z);
}
inline fn cons(x: Word, y: Word) Word {
    return clib.make(clib.CONS, x, y);
}
inline fn label(x: Word, y: Word) Word {
    return clib.make(clib.LABEL, x, y);
}

export fn parse_append(lhs: Word, rhs: Word) Word {
    return ap2(clib.APPEND, lhs, rhs);
}

export fn parse_append_pre(lhs: Word) Word {
    return ap(clib.APPEND, lhs);
}

export fn parse_cons(lhs: Word, rhs: Word) Word {
    return cons(lhs, rhs);
}

export fn parse_cons_pre(lhs: Word) Word {
    return ap(clib.P, lhs);
}

export fn parse_listdiff(lhs: Word, rhs: Word) Word {
    return ap2(listdiff_fn, lhs, rhs);
}

export fn parse_listdiff_pre(lhs: Word) Word {
    return ap(listdiff_fn, lhs);
}

export fn parse_or(lhs: Word, rhs: Word) Word {
    return ap2(clib.OR, lhs, rhs);
}

export fn parse_or_pre(lhs: Word) Word {
    return ap(clib.OR, lhs);
}

export fn parse_and(lhs: Word, rhs: Word) Word {
    return ap2(clib.AND, lhs, rhs);
}

export fn parse_and_pre(lhs: Word) Word {
    return ap(clib.AND, lhs);
}

export fn parse_neg(rhs: Word) Word {
    return ap(clib.NEG, rhs);
}

export fn parse_length(rhs: Word) Word {
    return ap(clib.LENGTH, rhs);
}

export fn parse_plus(lhs: Word, rhs: Word) Word {
    return ap2(clib.PLUS, lhs, rhs);
}

export fn parse_plus_pre(lhs: Word) Word {
    return ap(clib.PLUS, lhs);
}

export fn parse_minus(lhs: Word, rhs: Word) Word {
    return ap2(clib.MINUS, lhs, rhs);
}

export fn parse_minus_pre(lhs: Word) Word {
    return ap(clib.MINUS, lhs);
}

export fn parse_times(lhs: Word, rhs: Word) Word {
    return ap2(clib.TIMES, lhs, rhs);
}

export fn parse_times_pre(lhs: Word) Word {
    return ap(clib.TIMES, lhs);
}

export fn parse_fdiv(lhs: Word, rhs: Word) Word {
    return ap2(clib.FDIV, lhs, rhs);
}

export fn parse_fdiv_pre(lhs: Word) Word {
    return ap(clib.FDIV, lhs);
}

export fn parse_intdiv(lhs: Word, rhs: Word) Word {
    return ap2(clib.INTDIV, lhs, rhs);
}

export fn parse_intdiv_pre(lhs: Word) Word {
    return ap(clib.INTDIV, lhs);
}

export fn parse_mod(lhs: Word, rhs: Word) Word {
    return ap2(clib.MOD, lhs, rhs);
}

export fn parse_mod_pre(lhs: Word) Word {
    return ap(clib.MOD, lhs);
}

export fn parse_power(lhs: Word, rhs: Word) Word {
    return ap2(clib.POWER, lhs, rhs);
}

export fn parse_power_pre(lhs: Word) Word {
    return ap(clib.POWER, lhs);
}

export fn parse_b(lhs: Word, rhs: Word) Word {
    return ap2(clib.B, lhs, rhs);
}

export fn parse_b_pre(lhs: Word) Word {
    return ap(clib.B, lhs);
}

export fn parse_subscript(lhs: Word, rhs: Word) Word {
    return ap2(clib.SUBSCRIPT, rhs, lhs);
}

export fn parse_subscript_pre(lhs: Word) Word {
    return ap2(clib.C, clib.SUBSCRIPT, lhs);
}

export fn parse_comb_arg(lhs: Word, rhs: Word) Word {
    return ap(lhs, rhs);
}

export fn parse_infix(op_val: Word, lhs: Word, rhs: Word) Word {
    return ap2(op_val, lhs, rhs);
}

export fn parse_infix_pre(op_val: Word, lhs: Word) Word {
    return ap(op_val, lhs);
}

export fn parse_compose(x: Word) Word {
    var y = h(x);
    if (h(y) == clib.OTHERWISE) {
        y = t(y); // OTHERWISE was just a marker - lose it
    } else {
        if (tg(y) == clib.LABEL) {
            y = label(h(y), ap(t(y), clib.FAIL));
        } else {
            y = ap(y, clib.FAIL); // if all guards false result is FAIL
        }
    }
    var current_x = t(x);
    if (current_x != clib.NIL) {
        while (t(current_x) != clib.NIL) {
            y = label(h(h(current_x)), ap(t(h(current_x)), y));
            current_x = t(current_x);
        }
        y = ap(h(current_x), y);
        // first alternative has no label - label of enclosing rhs applies
    }
    return y;
}

export fn parse_rhs_cases_where(cases_val: Word, ldefs_val: Word) Word {
    return clib.block(ldefs_val, parse_compose(cases_val), 0);
}

export fn parse_rhs_exp_where(exp_val: Word, ldefs_val: Word) Word {
    return clib.block(ldefs_val, exp_val, 0);
}

export fn parse_rhs_cases(cases_val: Word) Word {
    return parse_compose(cases_val);
}

export fn parse_case_first(exp_val: Word, cond_val: Word) Word {
    return cons(ap2(clib.COND, cond_val, exp_val), clib.NIL);
}

export fn parse_case_otherwise_first(exp_val: Word) Word {
    return cons(ap(clib.OTHERWISE, exp_val), clib.NIL);
}

export fn parse_case_add(cases_val: Word, alt_val: Word) Word {
    if (h(h(cases_val)) == clib.OTHERWISE) {
        clib.syntax("\"otherwise\" must be last case\n");
    }
    return cons(alt_val, cases_val);
}

export fn parse_alt_obsolete(here_val: Word, exp_val: Word) Word {
    errs = here_val;
    clib.syntax("obsolete syntax, \", otherwise\" missing\n");
    return ap(clib.OTHERWISE, label(here_val, exp_val));
}

export fn parse_alt_cond(here_val: Word, exp_val: Word, cond_val: Word) Word {
    return label(here_val, ap2(clib.COND, cond_val, exp_val));
}

export fn parse_alt_otherwise(here_val: Word, exp_val: Word) Word {
    return ap(clib.OTHERWISE, label(here_val, exp_val));
}

export fn parse_liste_first(exp_val: Word) Word {
    return cons(exp_val, clib.NIL);
}

export fn parse_liste_next(liste_val: Word, exp_val: Word) Word {
    return cons(exp_val, liste_val);
}

export fn parse_names_add(names_val: Word, name_val: Word) Word {
    if (clib.member(names_val, name_val) != 0) {
        _ = clib.printf("%ssyntax error: repeated identifier \"%s\" in %s list\n",
            if (echoing != 0) @as([*:0]const u8, "\n") else @as([*:0]const u8, ""),
            get_id(name_val),
            if (inbnf != 0) @as([*:0]const u8, "bnf") else @as([*:0]const u8, "attribute")
        );
        clib.acterror();
    }
    return if (inbnf != 0) clib.add1(name_val, names_val) else cons(name_val, names_val);
}

export fn parse_nil() Word {
    return clib.NIL;
}
