//! testutil.zig — the shared unit-test harness.
//!
//! The project's test convention is "one inline `test` per function". Stateful
//! functions need a working interpreter (a heap, the dictionary, `primenv`); graph
//! tests need to build small combinator graphs and assert how they reduce. Without
//! a shared harness every such test repeats ~20 lines of setup. This module is that
//! harness: a one-time `freshInterp()`, a handful of graph **builders**, and a
//! handful of reduction-aware **assertions** — so a per-function test is two or
//! three readable lines that double as documentation.
//!
//! Usage from a module's inline tests:
//! ```zig
//! const t = @import("../../testutil.zig");   // path relative to the test file
//! test "numplus: adds two ints" {
//!     t.freshInterp();
//!     try t.expectInt(5, t.ap2(word.PLUS, t.int(2), t.int(3)));
//! }
//! ```
//!
//! Pure leaf functions (Tier A: `word`/`big`/`strtab` classifiers and the like)
//! need no interpreter and should *not* import this — test them with literal
//! inputs. The harness is for Tier B/C (heap/graph/stateful) tests, whose modules
//! already pull in the runtime.
//!
//! This file is test-only: it is referenced from `main.zig`'s comptime test block
//! so its own self-tests run under `main-tests`, but none of its functions are
//! emitted into the `mira` executable (nothing there references them).

const std = @import("std");
const word = @import("runtime/word.zig");
const heap = @import("runtime/heap.zig");
const big = @import("runtime/big.zig");
const reduce = @import("runtime/reducer/reduce.zig");
const interp = @import("runtime/interp.zig");
const lex = @import("parser/lex.zig");
const setup = @import("compiler/setup.zig");

const Word = word.Word;

// ── Interpreter setup ───────────────────────────────────────────────────────

var ready = false;

/// Bring the global interpreter to a usable state for a test: a pristine `Interp`
/// (`interp.reset()`), a fresh dictionary, and the full `miraSetup()` (heap,
/// `primenv`, interned strings). Idempotent — safe to call at the top of every
/// test; the heavyweight init runs once per test binary. This is the proven
/// `reduce_test` recipe, promoted to the shared harness.
///
/// Note: it gives a *working* interpreter, not per-test isolation. State a test
/// mutates (e.g. new identifiers declared into `primenv`) persists to later tests
/// in the same binary, so name fixtures uniquely. True isolation needs a hard
/// `interp.reset()` (which reallocates the heap — see the plan's Phase 5 note).
pub fn freshInterp() void {
    if (ready) return;
    interp.reset();
    lex.setupdic();
    setup.miraSetup();
    ready = true;
}

// ── Graph builders ──────────────────────────────────────────────────────────

/// A boxed integer node (bignum), the value `n`.
pub fn int(n: i64) Word {
    return big.fromInt(heap.heap(), @intCast(n));
}

/// Apply `f` to `x`: the heap node `(f x)`.
pub fn ap(x: Word, y: Word) Word {
    return reduce.ap(heap.heap(), x, y);
}

/// Apply `f` to two arguments: `((f x) y)`.
pub fn ap2(f: Word, x: Word, y: Word) Word {
    return reduce.ap2(heap.heap(), f, x, y);
}

/// A cons cell `(head : tail)`.
pub fn cons(x: Word, y: Word) Word {
    return reduce.cons(heap.heap(), x, y);
}

/// A proper list of the given nodes, terminated by `NIL`: `a : b : … : NIL`.
pub fn list(items: []const Word) Word {
    var result: Word = word.NIL;
    var i = items.len;
    while (i > 0) {
        i -= 1;
        result = reduce.cons(heap.heap(), items[i], result);
    }
    return result;
}

/// A Miranda string: the cons-list of the bytes of `s` (each a char node).
pub fn str(s: []const u8) Word {
    var result: Word = word.NIL;
    var i = s.len;
    while (i > 0) {
        i -= 1;
        result = reduce.cons(heap.heap(), heap.stoChar(s[i]), result);
    }
    return result;
}

// ── Assertions (reduce, then check) ─────────────────────────────────────────

/// Assert that the reduced WHNF of `node` is the heap value `expected`.
pub fn expectReducesTo(expected: Word, node: Word) !void {
    try std.testing.expectEqual(expected, reduce.reduce(node));
}

/// Assert that `node` (reduced) is a node of tag `tag`.
pub fn expectTag(tag: word.NodeTag, node: Word) !void {
    try std.testing.expectEqual(tag, heap.getTag(reduce.reduce(node)));
}

/// Assert that `node` reduces to the integer `expected`.
pub fn expectInt(expected: i64, node: Word) !void {
    const r = reduce.reduce(node);
    try std.testing.expect(heap.getTag(r) == .INT);
    try std.testing.expectEqual(expected, @as(i64, @intCast(big.toInt(heap.heap(), r))));
}

/// Assert that `node` reduces to a proper list whose elements reduce, in order,
/// to the integers `expected` (and that the list ends in `NIL`).
pub fn expectList(expected: []const i64, node: Word) !void {
    var cur = reduce.reduce(node);
    for (expected) |e| {
        try std.testing.expect(heap.getTag(cur) == .CONS);
        try expectInt(e, heap.h(cur));
        cur = reduce.reduce(heap.t(cur));
    }
    try std.testing.expectEqual(@as(Word, word.NIL), cur);
}

/// Assert that `node` is a cons-list whose *raw* heads (no reduction) equal
/// `expected`, ending in `NIL` — for the type checker's `Word`-set lists, whose
/// elements are bare comparable `Word`s rather than reducible thunks.
pub fn expectWords(expected: []const Word, node: Word) !void {
    var cur = node;
    for (expected) |e| {
        try std.testing.expect(heap.getTag(cur) == .CONS);
        try std.testing.expectEqual(e, heap.h(cur));
        cur = heap.t(cur);
    }
    try std.testing.expectEqual(@as(Word, word.NIL), cur);
}

/// Assert that `node` reduces to a Miranda string (a char cons-list) whose bytes
/// equal `expected`. Each element is reduced and taken as a byte.
pub fn expectStr(expected: []const u8, node: Word) !void {
    var buf: [256]u8 = undefined;
    var len: usize = 0;
    var cur = reduce.reduce(node);
    while (heap.getTag(cur) == .CONS) {
        buf[len] = @intCast(reduce.reduce(heap.h(cur)));
        len += 1;
        cur = reduce.reduce(heap.t(cur));
    }
    try std.testing.expectEqualStrings(expected, buf[0..len]);
}

// ── Self-tests (also the canonical usage examples) ──────────────────────────

test "freshInterp: provides a working reducer" {
    freshInterp();
    // A trivial reduction proves the heap + combinators are live.
    try expectReducesTo(word.NIL, ap(word.I, word.NIL));
}

test "int + ap2: builds and reduces arithmetic" {
    freshInterp();
    try expectInt(5, ap2(word.PLUS, int(2), int(3)));
}

test "expectTag: classifies a reduced node" {
    freshInterp();
    try expectTag(.INT, ap2(word.TIMES, int(6), int(7)));
}

test "list + expectList: builds and walks a proper list" {
    freshInterp();
    try expectList(&.{ 1, 2, 3 }, list(&.{ int(1), int(2), int(3) }));
}

test "str: builds a Miranda string as a char list" {
    freshInterp();
    const s = str("hi");
    try std.testing.expect(heap.getTag(s) == .CONS);
    try std.testing.expectEqual(@as(Word, 'h'), heap.h(s));
    try std.testing.expectEqual(@as(Word, 'i'), heap.h(heap.t(s)));
    try std.testing.expectEqual(@as(Word, word.NIL), heap.t(heap.t(s)));
}

test "expectStr: matches a char list against bytes" {
    freshInterp();
    try expectStr("hello", str("hello"));
    try expectStr("", str(""));
}
