//! semantics/lower_sort.zig — relation/topological-sort helpers (docs/GoReady.md P4).

const std = @import("std");
const word = @import("../graph/word.zig");
const os = @import("../os.zig");
const Word = i64;
const Value = @import("../graph/value.zig").Value;
const NIL = word.NIL;
const heap_mod = @import("../graph/heap.zig");
const Heap = heap_mod.Heap;
const depend = @import("depend.zig");
const reverse = heap_mod.reverse;
const shunt = heap_mod.shunt;
const member = depend.member;
const UNION = depend.UNION;

const lower_prims = @import("lower_prims.zig");
const h = lower_prims.h;
const t = lower_prims.t;
const tp = lower_prims.tp;
const cons = lower_prims.cons;

/// Transitive closure of relation `r`.
pub fn tclos(heap: *Heap, r: Word) Word {
    var r1 = r;
    while (r1 != NIL) : (r1 = t(heap, r1)) {
        var x = less1(heap, t(heap, h(heap, r1)), h(heap, h(heap, r1)));
        while (x != NIL) {
            x = imageless(heap, r, x, t(heap, h(heap, r1)));
            tp(heap, h(heap, r1)).* = UNION(heap, Value.fromRaw(t(heap, h(heap, r1))), Value.fromRaw(x)).toRaw();
        }
    }
    return r;
}

/// The image (successors) of `x` under relation `r`.
pub fn getrel(heap: *Heap, input_r: Word, x: Word) Word {
    var r = input_r;
    while (r != NIL and h(heap, h(heap, r)) != x) r = t(heap, r);
    return if (r == NIL) NIL else t(heap, h(heap, r));
}

/// The inverse image (predecessors) of `x` under relation `r`.
pub fn invgetrel(heap: *Heap, input_r: Word, x: Word) Word {
    var r = input_r;
    while (r != NIL and member(heap, Value.fromRaw(t(heap, h(heap, r))), Value.fromRaw(x)) == 0) r = t(heap, r);
    if (r == NIL) {
        std.debug.print("impossible event in invgetrel\n", .{});
        os.exit(1);
    }
    return h(heap, h(heap, r));
}

/// The image of `y` under `r`, excluding `z`.
pub fn imageless(heap: *Heap, input_r: Word, input_y: Word, z: Word) Word {
    var r = input_r;
    var y = input_y;
    var i: Word = NIL;
    while (r != NIL and y != NIL) {
        if (h(heap, h(heap, r)) == h(heap, y)) {
            i = UNION(heap, Value.fromRaw(i), Value.fromRaw(less(heap, t(heap, h(heap, r)), z))).toRaw();
            r = t(heap, r);
            y = t(heap, y);
        } else if (h(heap, h(heap, r)) < h(heap, y)) {
            r = t(heap, r);
        } else {
            y = t(heap, y);
        }
    }
    return i;
}

/// Whether `x` should sort before `y`.
pub fn less(heap: *Heap, input_x: Word, input_y: Word) Word {
    var x = input_x;
    var y = input_y;
    var r: Word = NIL;
    while (x != NIL and y != NIL) {
        if (h(heap, x) == h(heap, y)) {
            x = t(heap, x);
            y = t(heap, y);
        } else if (h(heap, x) < h(heap, y)) {
            r = cons(heap, h(heap, x), r);
            x = t(heap, x);
        } else {
            y = t(heap, y);
        }
    }
    return shunt(r, x);
}

/// The elements of `x` that sort before `a`.
pub fn less1(heap: *Heap, input_x: Word, a: Word) Word {
    var x = input_x;
    var r: Word = NIL;
    while (x != NIL and h(heap, x) != a) {
        r = cons(heap, h(heap, x), r);
        x = t(heap, x);
    }
    return shunt(r, if (x == NIL) NIL else t(heap, x));
}

/// Sort list `x`.
///
/// Tests: sort: orders a Word list ascending
pub fn sort(heap: *Heap, input_x: Word) Word {
    var x = input_x;
    var a: Word = NIL;
    var b: Word = NIL;
    if (x == NIL or t(heap, x) == NIL) return x;
    while (x != NIL) {
        const hold = a;
        a = cons(heap, h(heap, x), b);
        b = hold;
        x = t(heap, x);
    }
    a = sort(heap, a);
    b = sort(heap, b);
    while (a != NIL and b != NIL) {
        if (h(heap, a) < h(heap, b)) {
            x = cons(heap, h(heap, a), x);
            a = t(heap, a);
        } else {
            x = cons(heap, h(heap, b), x);
            b = t(heap, b);
        }
    }
    if (a == NIL) a = b;
    while (a != NIL) {
        x = cons(heap, h(heap, a), x);
        a = t(heap, a);
    }
    return reverse(x);
}

/// Topologically sort relation `x`.
pub fn sortrel(heap: *Heap, input_x: Word) Word {
    var x = input_x;
    var a: Word = NIL;
    var b: Word = NIL;
    if (x == NIL or t(heap, x) == NIL) return x;
    while (x != NIL) {
        const hold = a;
        a = cons(heap, h(heap, x), b);
        b = hold;
        x = t(heap, x);
    }
    a = sortrel(heap, a);
    b = sortrel(heap, b);
    while (a != NIL and b != NIL) {
        if (h(heap, h(heap, a)) < h(heap, h(heap, b))) {
            x = cons(heap, h(heap, a), x);
            a = t(heap, a);
        } else {
            x = cons(heap, h(heap, b), x);
            b = t(heap, b);
        }
    }
    if (a == NIL) a = b;
    while (a != NIL) {
        x = cons(heap, h(heap, a), x);
        a = t(heap, a);
    }
    return reverse(x);
}
