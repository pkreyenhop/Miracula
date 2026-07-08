//! match.zig (split from compiler/trans.zig, Phase 4 step 3,
//! docs/ZIG_NATIVE_PLAN.md) — pattern-match compilation: `scanpattern`
//! (compiles a pattern against a scrutinee into `TRY`-guarded bindings),
//! `genlhs` (canonicalises a definition's left-hand-side pattern), and
//! `transtries` (translates an id's pattern-match alternatives into a
//! `TRIES` chain, codegen-ing each alternative). `lower.zig`'s `declare`
//! and `codegen` call into this file; `transtries` calls back into
//! `lower.zig`'s `codegen` to compile each alternative -- a genuine
//! two-way dependency inherent to the algorithm, not an accident of the
//! split. The small graph accessors below are duplicated from `lower.zig`
//! rather than imported, matching this codebase's existing convention
//! (`eval/combinators/*.zig` each redeclare their own too) -- cheaper and
//! lower-risk than threading `pub`-and-prefix through every one-line helper.

const std = @import("std");
const word = @import("../graph/word.zig");
const strtab = @import("../graph/strtab.zig");
const types_mod = @import("depend.zig");
const setup = @import("../compiler/setup.zig");
const lex = @import("../parser/lex.zig");
const lex_state = @import("../parser/lex_state.zig");
const ls = lex_state.ls;
const heap_mod = @import("../graph/heap.zig");
const Heap = heap_mod.Heap;
const big = @import("../graph/bignum.zig");
const lower = @import("lower.zig");

const Word = i64;
const CMBASE = word.CMBASE;
const TRY: Word = CMBASE + 40;
const PLUS: Word = CMBASE + 54;
const BADCASE: Word = CMBASE + 132;
const True = word.True;
const False = word.False;
const NIL = word.NIL;
const NILS = word.NILS;
const CONST = word.CONST;

const member = types_mod.member;
const isnat = big.isNat;
const isconstrname = lex.isconstrname;
const syntax = setup.syntax;

const make = heap_mod.make;
const shunt = heap_mod.shunt;

/// The node tag of cell `x`.
inline fn getTag(heap: *Heap, x: Word) word.NodeTag {
    return heap.getTag(x);
}

/// Head (`hd`) of cell `x`.
fn h(heap: *Heap, x: Word) Word {
    return heap.h(x);
}

/// Pointer to the tail field of cell `x`.
fn tp(heap: *Heap, x: Word) *Word {
    return heap.tp(x);
}

/// Tail (`tl`) of cell `x`.
fn t(heap: *Heap, x: Word) Word {
    return heap.t(x);
}

/// Allocate a `CONS` cell `(x . y)`.
fn cons(heap: *Heap, x: Word, y: Word) Word {
    return make(heap, .CONS, x, y);
}

/// Allocate an `AP` cell `(x y)`.
fn ap(heap: *Heap, x: Word, y: Word) Word {
    return make(heap, .AP, x, y);
}

/// Allocate `((x y) z)`.
fn ap2(heap: *Heap, x: Word, y: Word, z: Word) Word {
    return ap(heap, ap(heap, x, y), z);
}

/// Allocate a `LAMBDA` cell `(x . y)`.
fn lambda(heap: *Heap, x: Word, y: Word) Word {
    return make(heap, .LAMBDA, x, y);
}

/// Allocate a `DATAPAIR` cell.
fn datapair(heap: *Heap, x: Word, y: Word) Word {
    return make(heap, .DATAPAIR, x, y);
}

/// Whether `x` names a data constructor.
fn isConstructor(heap: *Heap, x: Word) bool {
    return getTag(heap, x) == .ID and isconstrname(lower.getId(heap, x));
}

/// Whether `x` is an `n+k` pattern.
fn isNPlusKPattern(heap: *Heap, x: Word) bool {
    return getTag(heap, x) == .AP and getTag(heap, h(heap, x)) == .AP and h(heap, h(heap, x)) == PLUS;
}

/// Whether `x` is a char value.
fn isChar(x: Word) bool {
    return 0 <= x and x <= 255;
}

/// Compile pattern `p` against scrutinee `x` into `e`, with `fail` as the no-match continuation.
pub fn scanpattern(heap: *Heap, p: Word, x: Word, e: Word, fail: Word) Word {
    if (h(heap, x) == CONST or isConstructor(heap, x)) {
        return NIL;
    }
    if (getTag(heap, x) == .ID) {
        const binding = cons(heap, x, ap2(heap, TRY, ap(heap, lambda(heap, p, x), e), fail));
        return cons(heap, binding, NIL);
    }
    if (isNPlusKPattern(heap, x)) {
        return scanpattern(heap, p, t(heap, x), e, fail);
    }
    return shunt(scanpattern(heap, p, h(heap, x), e, fail), scanpattern(heap, p, t(heap, x), e, fail));
}

/// Generate the canonical left-hand-side pattern from definition head `x`.
pub fn genlhs(heap: *Heap, x: Word) Word {
    switch (getTag(heap, x)) {
        .AP => {
            if (getTag(heap, h(heap, x)) == .AP and h(heap, h(heap, x)) == PLUS and isnat(heap, t(heap, x))) {
                return ap2(heap, PLUS, t(heap, x), genlhs(heap, t(heap, h(heap, x))));
            }
            const hold = genlhs(heap, h(heap, x));
            return make(heap, .AP, hold, genlhs(heap, t(heap, x)));
        },
        .CONS, .TCONS, .PAIR => {
            const hold = genlhs(heap, h(heap, x));
            return make(heap, getTag(heap, x), hold, genlhs(heap, t(heap, x)));
        },
        .ID => {
            if (member(heap, ls().idsused, x) != 0) {
                return cons(heap, CONST, x);
            }
            if (!isConstructor(heap, x)) {
                ls().idsused = cons(heap, x, ls().idsused);
            }
            return x;
        },
        .INT => return cons(heap, CONST, x),
        .DOUBLE => {
            syntax("floating point literal in pattern\n") catch {};
            return heap.nill;
        },
        .ATOM => {
            if (x == True or x == False or x == NILS or x == NIL or isChar(x)) {
                return cons(heap, CONST, x);
            }
        },
        else => {},
    }
    syntax("illegal form on left of <-\n") catch {};
    return heap.nill;
}

/// Translate the pattern-match alternatives `x` of an id into a `TRIES` chain.
pub fn transtries(heap: *Heap, id: Word, input_x: Word) Word {
    var x = input_x;
    var info: Word = 0;
    var earliest: Word = 0;
    var r: Word = undefined;
    if (lower.fallible(heap, h(heap, x)) != 0) {
        const oldn = if (getTag(heap, id) == .ID) datapair(heap, @as(Word, strtab.strBits(strtab.table(), lower.getId(heap, id))), 0) else 0;
        info = cons(heap, oldn, 0);
        r = ap(heap, BADCASE, info);
        if (x == NIL) {
            std.debug.print("Internal error: `earliest' is used uninitialised in transtries(heap, )\nPlease report it to miranda@groups.io\n", .{});
        }
    } else {
        earliest = h(heap, x);
        r = lower.codegen(heap, earliest);
        x = t(heap, x);
    }
    while (x != NIL) {
        earliest = h(heap, x);
        r = ap2(heap, TRY, lower.codegen(heap, earliest), r);
        x = t(heap, x);
    }
    if (info != 0) {
        tp(heap, info).* = h(heap, earliest);
    }
    return r;
}
