//! depend.zig (split from compiler/types.zig, Phase 4 step 3,
//! docs/ZIG_NATIVE_PLAN.md) — generic sorted-set operations, topological
//! sort/mutually-recursive-group collapse for ordering definitions
//! (`tsort`/`msc`), and free-variable dependency computation (`deps`,
//! built on `rembvars`). `compDeps` (the type-checker's own per-definition
//! dependency pass, which also drives `metaTcheck`/`sayhere`) stays in
//! `infer.zig` -- it's tightly coupled to the type-checking driver, not a
//! reusable dependency-analysis primitive like the functions here.

const std = @import("std");
const word = @import("../graph/word.zig");
const heap_mod = @import("../graph/heap.zig");
const Heap = heap_mod.Heap;
const tu = @import("../testutil.zig"); // unit-test harness (test builds only)
const lex_mod = @import("../parser/lex.zig");
const isconstrname = lex_mod.isconstrname;
const infer = @import("infer.zig");
const getId = infer.getId;

const Word = word.Word;
const CMBASE = word.CMBASE;
const NIL = word.NIL;
const PLUS: Word = CMBASE + 54;
const CONST = word.CONST;

const reverse = heap_mod.reverse;
const shunt = heap_mod.shunt;

/// The node tag of cell `x`.
inline fn getTag(heap: *Heap, x: Word) word.NodeTag {
    return heap.getTag(x);
}

/// Head (`hd`) of cell `x`.
fn h(heap: *Heap, x: Word) Word {
    return heap.h(x);
}

/// Pointer to the head field of cell `x`.
fn hp(heap: *Heap, x: Word) *Word {
    return heap.hp(x);
}

/// Tail (`tl`) of cell `x`.
fn t(heap: *Heap, x: Word) Word {
    return heap.t(x);
}

/// Pointer to the tail field of cell `x`.
fn tp(heap: *Heap, x: Word) *Word {
    return heap.tp(x);
}

/// Allocate a `CONS` cell `(x . y)`.
fn cons(heap: *Heap, x: Word, y: Word) Word {
    return heap_mod.make(heap, .CONS, x, y);
}

/// Whether `x` names a data constructor.
fn isConstructor(heap: *Heap, x: Word) bool {
    return getTag(heap, x) == .ID and isconstrname(getId(heap, x));
}

/// Remove element `e` from set `ss` (in place via the pointer).
///
/// Tests: remove1: removes an element in place, reports hit/miss
pub fn remove1(heap: *Heap, e: Word, ss: *Word) Word {
    var p = ss;
    while (p.* != NIL and h(heap, p.*) < e) {
        p = tp(heap, p.*);
    }
    if (p.* == NIL or h(heap, p.*) != e) {
        return 0;
    }
    p.* = t(heap, p.*);
    return 1;
}

test "remove1: removes an element in place, reports hit/miss" {
    tu.freshInterp();
    var s = tu.list(&[_]Word{ 1000, 2000, 3000 });
    try std.testing.expectEqual(@as(Word, 1), remove1(heap_mod.heap(), 2000, &s));
    try tu.expectWords(&[_]Word{ 1000, 3000 }, s);
    try std.testing.expectEqual(@as(Word, 0), remove1(heap_mod.heap(), 5000, &s)); // miss
}

/// Set difference `s1 \ s2`.
///
/// Tests: setdiff: s1 minus s2
pub fn setdiff(heap: *Heap, s1_input: Word, s2_input: Word) Word {
    var s1 = s1_input;
    var s2 = s2_input;
    var ss1 = &s1;
    while (ss1.* != NIL and s2 != NIL) {
        if (h(heap, ss1.*) == h(heap, s2)) {
            ss1.* = t(heap, ss1.*);
        } else if (h(heap, ss1.*) < h(heap, s2)) {
            ss1 = tp(heap, ss1.*);
        } else {
            s2 = t(heap, s2);
        }
    }
    return s1;
}

test "setdiff: s1 minus s2" {
    tu.freshInterp();
    try tu.expectWords(&[_]Word{ 1000, 3000 }, setdiff(heap_mod.heap(), tu.list(&[_]Word{ 1000, 2000, 3000 }), tu.list(&[_]Word{2000})));
}

/// Add element `e` to set `s` (if not already present).
///
/// Tests: add1: inserts in sorted order without duplicates
pub fn add1(heap: *Heap, e: Word, s_input: Word) Word {
    var s = s_input;
    if (s == NIL or e < h(heap, s)) {
        return cons(heap, e, s);
    }
    if (e == h(heap, s)) {
        return s;
    }
    while (t(heap, s) != NIL and e > h(heap, t(heap, s))) {
        s = t(heap, s);
    }
    if (t(heap, s) == NIL) {
        tp(heap, s).* = cons(heap, e, NIL);
    } else if (e != h(heap, t(heap, s))) {
        tp(heap, s).* = cons(heap, e, t(heap, s));
    }
    return s_input;
}

test "add1: inserts in sorted order without duplicates" {
    tu.freshInterp();
    try tu.expectWords(&[_]Word{ 1000, 2000, 3000 }, add1(heap_mod.heap(), 2000, tu.list(&[_]Word{ 1000, 3000 })));
    // already present → unchanged
    try tu.expectWords(&[_]Word{ 1000, 2000, 3000 }, add1(heap_mod.heap(), 2000, tu.list(&[_]Word{ 1000, 2000, 3000 })));
}

/// Prepend element `e` to set `s` (no membership check).
pub fn newadd1(heap: *Heap, e: Word, s_input: Word) Word {
    var s = s_input;
    const cs = @import("../compiler/compiler_state.zig").cs;
    cs().NEW = 1;
    if (s == NIL or e < h(heap, s)) {
        return cons(heap, e, s);
    }
    if (e == h(heap, s)) {
        cs().NEW = 0;
        return s;
    }
    while (t(heap, s) != NIL and e > h(heap, t(heap, s))) {
        s = t(heap, s);
    }
    if (t(heap, s) == NIL) {
        tp(heap, s).* = cons(heap, e, NIL);
    } else if (e != h(heap, t(heap, s))) {
        tp(heap, s).* = cons(heap, e, t(heap, s));
    } else {
        cs().NEW = 0;
    }
    return s_input;
}

/// Set union of `s1` and `s2`.
///
/// Tests: UNION: sorted set union
pub fn UNION(heap: *Heap, s1_input: Word, s2_input: Word) Word {
    var s1 = s1_input;
    var s2 = s2_input;
    var ss = &s1;
    while (ss.* != NIL and s2 != NIL) {
        if (h(heap, ss.*) == h(heap, s2)) {
            ss = tp(heap, ss.*);
            s2 = t(heap, s2);
        } else if (h(heap, ss.*) < h(heap, s2)) {
            ss = tp(heap, ss.*);
        } else {
            ss.* = cons(heap, h(heap, s2), ss.*);
            ss = tp(heap, ss.*);
            s2 = t(heap, s2);
        }
    }
    if (ss.* == NIL) {
        while (s2 != NIL) {
            ss.* = cons(heap, h(heap, s2), ss.*);
            ss = tp(heap, ss.*);
            s2 = t(heap, s2);
        }
    }
    return s1;
}

test "UNION: sorted set union" {
    tu.freshInterp();
    try tu.expectWords(&[_]Word{ 1000, 2000, 3000 }, UNION(heap_mod.heap(), tu.list(&[_]Word{ 1000, 3000 }), tu.list(&[_]Word{ 2000, 3000 })));
}

/// Set intersection of `s1` and `s2`.
///
/// Tests: intersection: common elements
pub fn intersection(heap: *Heap, s1_input: Word, s2_input: Word) Word {
    var s1 = s1_input;
    var s2 = s2_input;
    var r: Word = NIL;
    while (s1 != NIL and s2 != NIL) {
        if (h(heap, s1) == h(heap, s2)) {
            r = cons(heap, h(heap, s1), r);
            s1 = t(heap, s1);
            s2 = t(heap, s2);
        } else if (h(heap, s1) < h(heap, s2)) {
            s1 = t(heap, s1);
        } else {
            s2 = t(heap, s2);
        }
    }
    return reverse(r);
}

test "intersection: common elements" {
    tu.freshInterp();
    try tu.expectWords(&[_]Word{ 2000, 3000 }, intersection(heap_mod.heap(), tu.list(&[_]Word{ 1000, 2000, 3000 }), tu.list(&[_]Word{ 2000, 3000, 4000 })));
}

/// Whether `x` is a member of set `s`.
///
/// Tests: member: set membership (1/0)
pub fn member(heap: *Heap, s_input: Word, x: Word) Word {
    var s = s_input;
    while (s != NIL and x != h(heap, s)) {
        s = t(heap, s);
    }
    return if (s != NIL) 1 else 0;
}

test "member: set membership (1/0)" {
    tu.freshInterp();
    const s = tu.list(&[_]Word{ 1000, 2000, 3000 });
    try std.testing.expectEqual(@as(Word, 1), member(heap_mod.heap(), s, 2000));
    try std.testing.expectEqual(@as(Word, 0), member(heap_mod.heap(), s, 5000));
}

const type_t: Word = 10;

/// The type field of id `x`.
fn idType(heap: *Heap, x: Word) Word {
    return t(heap, h(heap, x));
}

/// Reorder a definition list so type declarations come first.
pub fn typesfirst(heap: *Heap, input_x: Word) Word {
    var x = input_x;
    var y = &x;
    var z: Word = NIL;
    while (y.* != NIL) {
        if (idType(heap, h(heap, y.*)) == type_t) {
            z = cons(heap, h(heap, y.*), z);
            y.* = t(heap, y.*);
        } else {
            y = tp(heap, y.*);
        }
    }
    return shunt(z, x);
}

/// Topologically sort dependency graph `g` (for definition ordering).
pub fn tsort(heap: *Heap, g_input: Word) Word {
    var NP = NIL; // NP is set of elements with no predecessor
    var g1 = g_input;
    var r = NIL; // r is result
    var g = NIL;
    while (g1 != NIL) {
        if (t(heap, h(heap, g1)) == NIL) {
            NP = cons(heap, h(heap, h(heap, g1)), NP);
        } else {
            g = cons(heap, h(heap, g1), g);
        }
        g1 = t(heap, g1);
    }
    while (NP != NIL) {
        var D = NIL; // ids to be removed from range of g
        while (NP != NIL) {
            r = cons(heap, h(heap, NP), r);
            if (getTag(heap, h(heap, NP)) == .ID) {
                D = add1(heap, h(heap, NP), D);
            } else {
                D = UNION(heap, D, h(heap, NP));
            }
            NP = t(heap, NP);
        }
        g1 = g;
        g = NIL;
        while (g1 != NIL) {
            const rhs = setdiff(heap, t(heap, h(heap, g1)), D);
            if (rhs == NIL) {
                NP = cons(heap, h(heap, h(heap, g1)), NP);
            } else {
                tp(heap, h(heap, g1)).* = rhs;
                g = cons(heap, h(heap, g1), g);
            }
            g1 = t(heap, g1);
        }
    }
    if (g != NIL) {
        _ = word.printErr("error: impossible event in tsort\n", .{});
    }
    return reverse(r);
}

/// Collapse mutually-recursive groups in relation `R` (companion to `tsort`).
pub fn msc(heap: *Heap, R_input: Word) Word {
    var R1 = R_input;
    while (R1 != NIL) {
        var r = tp(heap, h(heap, R1)); // word *r = &tl(hd(R1))
        const l = h(heap, h(heap, R1)); // word l = hd(hd(R1))
        if (remove1(heap, l, r) != 0) {
            hp(heap, h(heap, R1)).* = cons(heap, l, NIL); // hd(hd(R1)) = cons(heap, l, NIL)
            while (r.* != NIL) {
                const n = h(heap, r.*);
                var R2 = tp(heap, R1); // word *R2 = &tl(R1)
                while (R2.* != NIL and h(heap, h(heap, R2.*)) != n) {
                    R2 = tp(heap, R2.*);
                }
                if (R2.* != NIL and member(heap, t(heap, h(heap, R2.*)), l) != 0) {
                    r.* = t(heap, r.*); // *r = tl(*r)
                    R2.* = t(heap, R2.*); // *R2 = tl(*R2)
                    hp(heap, h(heap, R1)).* = add1(heap, n, h(heap, h(heap, R1)));
                } else {
                    r = tp(heap, r.*);
                }
            }
        }
        R1 = t(heap, R1);
    }
    return R_input;
}

/// Remove the variables bound by pattern `p` from set `x`.
pub fn rembvars(heap: *Heap, x_in: Word, p_in: Word) Word {
    var x = x_in;
    var p = p_in;
    while (true) {
        switch (getTag(heap, p)) {
            .ID => {
                _ = remove1(heap, p, &x);
                return x;
            },
            .CONS => {
                if (h(heap, p) == CONST) {
                    return x;
                }
                x = rembvars(heap, x, h(heap, p));
                p = t(heap, p);
            },
            .AP => {
                if (getTag(heap, h(heap, p)) == .AP and h(heap, h(heap, p)) == PLUS) {
                    p = t(heap, p);
                } else {
                    x = rembvars(heap, x, h(heap, p));
                    p = t(heap, p);
                }
            },
            .PAIR, .TCONS => {
                x = rembvars(heap, x, h(heap, p));
                p = t(heap, p);
            },
            else => {
                _ = word.printErr("impossible event in rembvars\n", .{});
                return x;
            },
        }
    }
}

/// The dependency set of definition `x`.
pub fn deps(heap: *Heap, x_in: Word) Word {
    var x = x_in;
    var d = NIL;
    while (true) {
        switch (getTag(heap, x)) {
            .AP, .TCONS, .PAIR, .CONS => {
                d = UNION(heap, d, deps(heap, h(heap, x)));
                x = t(heap, x);
            },
            .ID => {
                return if (isConstructor(heap, x)) d else add1(heap, x, d);
            },
            .LAMBDA => {
                return rembvars(heap, UNION(heap, d, deps(heap, t(heap, x))), h(heap, x));
            },
            .LET => {
                d = rembvars(heap, UNION(heap, d, deps(heap, t(heap, x))), h(heap, h(heap, x)));
                return UNION(heap, d, deps(heap, t(heap, t(heap, h(heap, x)))));
            },
            .LETREC => {
                d = UNION(heap, d, deps(heap, t(heap, x)));
                var y = h(heap, x);
                while (y != NIL) {
                    d = UNION(heap, d, deps(heap, t(heap, t(heap, h(heap, y)))));
                    y = t(heap, y);
                }
                y = h(heap, x);
                while (y != NIL) {
                    d = rembvars(heap, d, h(heap, h(heap, y)));
                    y = t(heap, y);
                }
                return d;
            },
            .LEXER => {
                var lex_x = x;
                while (lex_x != NIL) {
                    d = UNION(heap, d, deps(heap, t(heap, t(heap, h(heap, lex_x)))));
                    lex_x = t(heap, lex_x);
                }
                return d;
            },
            .TRIES, .LABEL => {
                x = t(heap, x);
            },
            .SHARE => {
                x = h(heap, x);
            },
            else => return d,
        }
    }
}

/// Renumber type variables across a list of definitions.
pub fn redtfr(heap: *Heap, x_in: Word) void {
    var x = x_in;
    while (x != NIL) {
        tp(heap, t(heap, h(heap, x))).* = idType(heap, h(heap, h(heap, x)));
        x = t(heap, x);
    }
}

/// Sort a list of identifiers alphabetically by name.
pub fn alfasort(x_val: Word) Word {
    var x = x_val;
    var a = NIL;
    var b = NIL;
    var hold = NIL;
    if (x == NIL) {
        return NIL;
    }
    if (heap_mod.t(heap_mod.heap(), x) == NIL) {
        return if (heap_mod.getTag(heap_mod.heap(), heap_mod.h(heap_mod.heap(), x)) != .ID) NIL else x;
    }
    while (x != NIL) {
        if (heap_mod.getTag(heap_mod.heap(), heap_mod.h(heap_mod.heap(), x)) == .ID) {
            hold = a;
            a = heap_mod.cons(heap_mod.heap(), heap_mod.h(heap_mod.heap(), x), b);
            b = hold;
        }
        x = heap_mod.t(heap_mod.heap(), x);
    }
    a = alfasort(a);
    b = alfasort(b);
    x = NIL;
    while (a != NIL and b != NIL) {
        if (std.mem.order(u8, std.mem.span(heap_mod.getId(heap_mod.h(heap_mod.heap(), a))), std.mem.span(heap_mod.getId(heap_mod.h(heap_mod.heap(), b)))) == .lt) {
            x = heap_mod.cons(heap_mod.heap(), heap_mod.h(heap_mod.heap(), a), x);
            a = heap_mod.t(heap_mod.heap(), a);
        } else {
            x = heap_mod.cons(heap_mod.heap(), heap_mod.h(heap_mod.heap(), b), x);
            b = heap_mod.t(heap_mod.heap(), b);
        }
    }
    if (a == NIL) {
        a = b;
    }
    while (a != NIL) {
        x = heap_mod.cons(heap_mod.heap(), heap_mod.h(heap_mod.heap(), a), x);
        a = heap_mod.t(heap_mod.heap(), a);
    }
    return reverse(x);
}
