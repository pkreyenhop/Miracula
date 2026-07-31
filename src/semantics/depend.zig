//! depend.zig (split from compiler/types.zig, Phase 4 step 3,
//! docs/GoReady.md) — generic sorted-set operations, topological
//! sort/mutually-recursive-group collapse for ordering definitions
//! (`tsort`/`msc`), and free-variable dependency computation (`deps`,
//! built on `rembvars`). `compDeps` (the type-checker's own per-definition
//! dependency pass, which also drives `metaTcheck`/`sayhere`) stays in
//! `infer.zig` -- it's tightly coupled to the type-checking driver, not a
//! reusable dependency-analysis primitive like the functions here.
//!
//! Phase 5 step 4e: every public function is `Value`-typed at its
//! boundary; each has a private `*Raw` twin (unchanged `Word`-based logic,
//! internal cross-calls stay within the `Raw` family so no wrapping noise
//! leaks into the bodies below) plus a thin public wrapper that converts
//! at the edge. This mirrors the rename+wrapper pattern used for
//! `reduce_rt.zig`'s `gResidue`/`force` in Phase 5 step 4d.

const std = @import("std");
const word = @import("../graph/word.zig");
const heap_mod = @import("../graph/heap.zig");
const Heap = heap_mod.Heap;
const tu = @import("../testutil.zig"); // unit-test harness (test builds only)
const lex_mod = @import("../parser/lex.zig");
const isconstrname = lex_mod.isconstrname;
const infer = @import("infer.zig");
const getId = infer.getId;
const value_mod = @import("../graph/value.zig");
const Value = value_mod.Value;

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
fn remove1Raw(heap: *Heap, e: Word, ss: *Word) Word {
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

/// Remove element `e` from set `ss` (in place via the pointer).
///
/// Tests: remove1: removes an element in place, reports hit/miss
pub fn remove1(heap: *Heap, e: Value, ss: *Value) Word {
    var raw = ss.toRaw();
    const r = remove1Raw(heap, e.toRaw(), &raw);
    ss.* = Value.fromRaw(raw);
    return r;
}

test "remove1: removes an element in place, reports hit/miss" {
    tu.freshInterp();
    var s = Value.fromRaw(tu.list(&[_]Word{ 1000, 2000, 3000 }));
    try std.testing.expectEqual(@as(Word, 1), remove1(heap_mod.heap(), Value.fromRaw(2000), &s));
    try tu.expectWords(&[_]Word{ 1000, 3000 }, s.toRaw());
    try std.testing.expectEqual(@as(Word, 0), remove1(heap_mod.heap(), Value.fromRaw(5000), &s)); // miss
}

/// Set difference `s1 \ s2`.
fn setdiffRaw(heap: *Heap, s1_input: Word, s2_input: Word) Word {
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

/// Set difference `s1 \ s2`.
///
/// Tests: setdiff: s1 minus s2
pub fn setdiff(heap: *Heap, s1_input: Value, s2_input: Value) Value {
    return Value.fromRaw(setdiffRaw(heap, s1_input.toRaw(), s2_input.toRaw()));
}

test "setdiff: s1 minus s2" {
    tu.freshInterp();
    try tu.expectWords(&[_]Word{ 1000, 3000 }, setdiff(heap_mod.heap(), Value.fromRaw(tu.list(&[_]Word{ 1000, 2000, 3000 })), Value.fromRaw(tu.list(&[_]Word{2000}))).toRaw());
}

/// Add element `e` to set `s` (if not already present).
fn add1Raw(heap: *Heap, e: Word, s_input: Word) Word {
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

/// Add element `e` to set `s` (if not already present).
///
/// Tests: add1: inserts in sorted order without duplicates
pub fn add1(heap: *Heap, e: Value, s_input: Value) Value {
    return Value.fromRaw(add1Raw(heap, e.toRaw(), s_input.toRaw()));
}

test "add1: inserts in sorted order without duplicates" {
    tu.freshInterp();
    try tu.expectWords(&[_]Word{ 1000, 2000, 3000 }, add1(heap_mod.heap(), Value.fromRaw(2000), Value.fromRaw(tu.list(&[_]Word{ 1000, 3000 }))).toRaw());
    // already present → unchanged
    try tu.expectWords(&[_]Word{ 1000, 2000, 3000 }, add1(heap_mod.heap(), Value.fromRaw(2000), Value.fromRaw(tu.list(&[_]Word{ 1000, 2000, 3000 }))).toRaw());
}

/// Prepend element `e` to set `s` (no membership check).
fn newadd1Raw(heap: *Heap, e: Word, s_input: Word) Word {
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

/// Prepend element `e` to set `s` (no membership check).
pub fn newadd1(heap: *Heap, e: Value, s_input: Value) Value {
    return Value.fromRaw(newadd1Raw(heap, e.toRaw(), s_input.toRaw()));
}

/// Set union of `s1` and `s2`.
fn UNIONRaw(heap: *Heap, s1_input: Word, s2_input: Word) Word {
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

/// Set union of `s1` and `s2`.
///
/// Tests: UNION: sorted set union
pub fn UNION(heap: *Heap, s1_input: Value, s2_input: Value) Value {
    return Value.fromRaw(UNIONRaw(heap, s1_input.toRaw(), s2_input.toRaw()));
}

test "UNION: sorted set union" {
    tu.freshInterp();
    try tu.expectWords(&[_]Word{ 1000, 2000, 3000 }, UNION(heap_mod.heap(), Value.fromRaw(tu.list(&[_]Word{ 1000, 3000 })), Value.fromRaw(tu.list(&[_]Word{ 2000, 3000 }))).toRaw());
}

/// Set intersection of `s1` and `s2`.
fn intersectionRaw(heap: *Heap, s1_input: Word, s2_input: Word) Word {
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

/// Set intersection of `s1` and `s2`.
///
/// Tests: intersection: common elements
pub fn intersection(heap: *Heap, s1_input: Value, s2_input: Value) Value {
    return Value.fromRaw(intersectionRaw(heap, s1_input.toRaw(), s2_input.toRaw()));
}

test "intersection: common elements" {
    tu.freshInterp();
    try tu.expectWords(&[_]Word{ 2000, 3000 }, intersection(heap_mod.heap(), Value.fromRaw(tu.list(&[_]Word{ 1000, 2000, 3000 })), Value.fromRaw(tu.list(&[_]Word{ 2000, 3000, 4000 }))).toRaw());
}

/// Whether `x` is a member of set `s`.
fn memberRaw(heap: *Heap, s_input: Word, x: Word) Word {
    var s = s_input;
    while (s != NIL and x != h(heap, s)) {
        s = t(heap, s);
    }
    return if (s != NIL) 1 else 0;
}

/// Whether `x` is a member of set `s`.
///
/// Tests: member: set membership (1/0)
pub fn member(heap: *Heap, s_input: Value, x: Value) Word {
    return memberRaw(heap, s_input.toRaw(), x.toRaw());
}

test "member: set membership (1/0)" {
    tu.freshInterp();
    const s = Value.fromRaw(tu.list(&[_]Word{ 1000, 2000, 3000 }));
    try std.testing.expectEqual(@as(Word, 1), member(heap_mod.heap(), s, Value.fromRaw(2000)));
    try std.testing.expectEqual(@as(Word, 0), member(heap_mod.heap(), s, Value.fromRaw(5000)));
}

const type_t: Word = 10;

/// The type field of id `x`.
fn idType(heap: *Heap, x: Word) Word {
    return t(heap, h(heap, x));
}

/// Reorder a definition list so type declarations come first.
fn typesfirstRaw(heap: *Heap, input_x: Word) Word {
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

/// Reorder a definition list so type declarations come first.
pub fn typesfirst(heap: *Heap, input_x: Value) Value {
    return Value.fromRaw(typesfirstRaw(heap, input_x.toRaw()));
}

/// Topologically sort dependency graph `g` (for definition ordering).
fn tsortRaw(heap: *Heap, g_input: Word) Word {
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
                D = add1Raw(heap, h(heap, NP), D);
            } else {
                D = UNIONRaw(heap, D, h(heap, NP));
            }
            NP = t(heap, NP);
        }
        g1 = g;
        g = NIL;
        while (g1 != NIL) {
            const rhs = setdiffRaw(heap, t(heap, h(heap, g1)), D);
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

/// Topologically sort dependency graph `g` (for definition ordering).
pub fn tsort(heap: *Heap, g_input: Value) Value {
    return Value.fromRaw(tsortRaw(heap, g_input.toRaw()));
}

/// Collapse mutually-recursive groups in relation `R` (companion to `tsort`).
fn mscRaw(heap: *Heap, R_input: Word) Word {
    var R1 = R_input;
    while (R1 != NIL) {
        var r = tp(heap, h(heap, R1)); // word *r = &tl(hd(R1))
        const l = h(heap, h(heap, R1)); // word l = hd(hd(R1))
        if (remove1Raw(heap, l, r) != 0) {
            hp(heap, h(heap, R1)).* = cons(heap, l, NIL); // hd(hd(R1)) = cons(heap, l, NIL)
            while (r.* != NIL) {
                const n = h(heap, r.*);
                var R2 = tp(heap, R1); // word *R2 = &tl(R1)
                while (R2.* != NIL and h(heap, h(heap, R2.*)) != n) {
                    R2 = tp(heap, R2.*);
                }
                if (R2.* != NIL and memberRaw(heap, t(heap, h(heap, R2.*)), l) != 0) {
                    r.* = t(heap, r.*); // *r = tl(*r)
                    R2.* = t(heap, R2.*); // *R2 = tl(*R2)
                    hp(heap, h(heap, R1)).* = add1Raw(heap, n, h(heap, h(heap, R1)));
                } else {
                    r = tp(heap, r.*);
                }
            }
        }
        R1 = t(heap, R1);
    }
    return R_input;
}

/// Collapse mutually-recursive groups in relation `R` (companion to `tsort`).
pub fn msc(heap: *Heap, R_input: Value) Value {
    return Value.fromRaw(mscRaw(heap, R_input.toRaw()));
}

/// Remove the variables bound by pattern `p` from set `x`.
fn rembvarsRaw(heap: *Heap, x_in: Word, p_in: Word) Word {
    var x = x_in;
    var p = p_in;
    while (true) {
        switch (getTag(heap, p)) {
            .ID => {
                _ = remove1Raw(heap, p, &x);
                return x;
            },
            .CONS => {
                if (h(heap, p) == CONST) {
                    return x;
                }
                x = rembvarsRaw(heap, x, h(heap, p));
                p = t(heap, p);
            },
            .AP => {
                if (getTag(heap, h(heap, p)) == .AP and h(heap, h(heap, p)) == PLUS) {
                    p = t(heap, p);
                } else {
                    x = rembvarsRaw(heap, x, h(heap, p));
                    p = t(heap, p);
                }
            },
            .PAIR, .TCONS => {
                x = rembvarsRaw(heap, x, h(heap, p));
                p = t(heap, p);
            },
            else => {
                _ = word.printErr("impossible event in rembvars\n", .{});
                return x;
            },
        }
    }
}

/// Remove the variables bound by pattern `p` from set `x`.
pub fn rembvars(heap: *Heap, x_in: Value, p_in: Value) Value {
    return Value.fromRaw(rembvarsRaw(heap, x_in.toRaw(), p_in.toRaw()));
}

/// The dependency set of definition `x`.
fn depsRaw(heap: *Heap, x_in: Word) Word {
    var x = x_in;
    var d = NIL;
    while (true) {
        switch (getTag(heap, x)) {
            .AP, .TCONS, .PAIR, .CONS => {
                d = UNIONRaw(heap, d, depsRaw(heap, h(heap, x)));
                x = t(heap, x);
            },
            .ID => {
                return if (isConstructor(heap, x)) d else add1Raw(heap, x, d);
            },
            .LAMBDA => {
                return rembvarsRaw(heap, UNIONRaw(heap, d, depsRaw(heap, t(heap, x))), h(heap, x));
            },
            .LET => {
                d = rembvarsRaw(heap, UNIONRaw(heap, d, depsRaw(heap, t(heap, x))), h(heap, h(heap, x)));
                return UNIONRaw(heap, d, depsRaw(heap, t(heap, t(heap, h(heap, x)))));
            },
            .LETREC => {
                d = UNIONRaw(heap, d, depsRaw(heap, t(heap, x)));
                var y = h(heap, x);
                while (y != NIL) {
                    d = UNIONRaw(heap, d, depsRaw(heap, t(heap, t(heap, h(heap, y)))));
                    y = t(heap, y);
                }
                y = h(heap, x);
                while (y != NIL) {
                    d = rembvarsRaw(heap, d, h(heap, h(heap, y)));
                    y = t(heap, y);
                }
                return d;
            },
            .LEXER => {
                var lex_x = x;
                while (lex_x != NIL) {
                    d = UNIONRaw(heap, d, depsRaw(heap, t(heap, t(heap, h(heap, lex_x)))));
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

/// The dependency set of definition `x`.
pub fn deps(heap: *Heap, x_in: Value) Value {
    return Value.fromRaw(depsRaw(heap, x_in.toRaw()));
}

/// Renumber type variables across a list of definitions.
fn redtfrRaw(heap: *Heap, x_in: Word) void {
    var x = x_in;
    while (x != NIL) {
        tp(heap, t(heap, h(heap, x))).* = idType(heap, h(heap, h(heap, x)));
        x = t(heap, x);
    }
}

/// Renumber type variables across a list of definitions.
pub fn redtfr(heap: *Heap, x_in: Value) void {
    redtfrRaw(heap, x_in.toRaw());
}

/// Sort a list of identifiers alphabetically by name.
fn alfasortRaw(heap: *Heap, x_val: Word) Word {
    var x = x_val;
    var a = NIL;
    var b = NIL;
    var hold = NIL;
    if (x == NIL) {
        return NIL;
    }
    if (heap_mod.t(heap, x) == NIL) {
        return if (heap_mod.getTag(heap, heap_mod.h(heap, x)) != .ID) NIL else x;
    }
    while (x != NIL) {
        if (heap_mod.getTag(heap, heap_mod.h(heap, x)) == .ID) {
            hold = a;
            a = heap_mod.cons(heap, heap_mod.h(heap, x), b);
            b = hold;
        }
        x = heap_mod.t(heap, x);
    }
    a = alfasortRaw(heap, a);
    b = alfasortRaw(heap, b);
    x = NIL;
    while (a != NIL and b != NIL) {
        if (std.mem.order(u8, heap_mod.getId(heap_mod.h(heap, a)), heap_mod.getId(heap_mod.h(heap, b))) == .lt) {
            x = heap_mod.cons(heap, heap_mod.h(heap, a), x);
            a = heap_mod.t(heap, a);
        } else {
            x = heap_mod.cons(heap, heap_mod.h(heap, b), x);
            b = heap_mod.t(heap, b);
        }
    }
    if (a == NIL) {
        a = b;
    }
    while (a != NIL) {
        x = heap_mod.cons(heap, heap_mod.h(heap, a), x);
        a = heap_mod.t(heap, a);
    }
    return reverse(x);
}

/// Sort a list of identifiers alphabetically by name.
pub fn alfasort(heap: *Heap, x_val: Value) Value {
    return Value.fromRaw(alfasortRaw(heap, x_val.toRaw()));
}
