//! reducer/spine.zig — an explicit, heap-growable spine stack: a candidate
//! replacement for in-graph pointer reversal (B2 option (b), "repivot the
//! hard core" — see `docs/REMAINING_WORK_PLAN.md` Phase 2).
//!
//! ## Why this exists
//!
//! `reduce()`'s spine walk (`reduce_core.zig`'s `downLeft`/`downRight`/
//! `upLeft`/`upRight`) has no separate stack: it threads the return path
//! through the graph itself, temporarily overwriting a cell's own `hd` or
//! `tl` field with a "previous stack top" pointer (tagged with `tlptrbits` in
//! its top two bits) and restoring it on the way back. That is why every
//! `hd`/`tl`/`getTag` access in the hot loop masks `& ~tlptrbits`, and why a
//! future tagged `Value` (B2 option (a)) competes for the same high bits.
//!
//! This module replaces that encoding with an explicit stack of frames, kept
//! separate from the graph. Tracing every read/write the four primitives
//! perform shows exactly one write per call is a *real* graph mutation
//! (writing back a reduced value so sharing still works); every other
//! read/write is pure bookkeeping for "what's below this frame". Moving that
//! bookkeeping into an explicit `Frame` means a cell's `hd`/`tl` hold a real
//! graph value at every instant, and no access anywhere needs `& ~tlptrbits`.
//!
//! **Key correctness property: `downRight` does not push a new frame.** It
//! *re-tags* the existing top frame (the one `downLeft` pushed for the same
//! cell) from "entered via hd" to "entered via tl" — both halves of visiting
//! one `AP` cell (its head, then its tail) share one frame. `upRight` mirrors
//! this: it does not pop — it writes back the reduced tail and flips the
//! frame back to "via hd", leaving it as the top frame. Only `upLeft` pops.
//!
//! ## Status: additive and inert
//!
//! This module is **not** wired into `reduce()`. It exists to develop and
//! validate the replacement primitives in isolation before any cutover. A
//! live cutover would additionally need to migrate the *other* direct
//! consumers of the raw spine encoding found during the Phase-2
//! investigation — beyond the two files already flagged as lock-step
//! duplicates of each other (`reducer/reduce.zig`, `reducer/reduce_core.zig`):
//!   * `combinators.zig`'s `handleTRY`/`handleFAIL` — TRY/FAIL backtracking
//!     walks the existing spine in bulk via raw `ctx.s`/`hdGet`/`tlptrbit`
//!     manipulation, not just the four primitives.
//!   * `runtime/reduce.zig`'s `streamRead` (a `pub export fn` — part of the
//!     C-ABI surface) inlines its own "UPLEFT" using *unmasked* `h`/`hp`,
//!     relying silently on that particular frame having been pushed by a pure
//!     `downLeft` chain (never `downRight`).
//! Each of these needs its own migration and validation; none are touched
//! here, and none are exercised by this module's tests.

const std = @import("std");
const heap = @import("../heap.zig");
const tu = @import("../../testutil.zig"); // unit-test harness (test builds only)

pub const Word = i64;

/// One frame of the explicit spine: the cell descended into (`node`), and
/// whether focus is currently inside it via `tl` (`via_tl`) or via `hd`.
/// Mirrors what pointer-reversal borrows from the cell's own field plus the
/// `tlptrbit` tag — but kept out of the graph.
pub const Frame = struct {
    node: Word,
    via_tl: bool,
};

/// An explicit, growable spine stack. One per `reduce()` invocation — and
/// `reduce()` is recursive (see `force()` and the strict-operator handlers),
/// so each nested call would own its own `Spine`, exactly like each
/// invocation today owns its own private `ReductionCtx.s` chain.
///
/// Deliberately growable, not fixed-capacity: pointer reversal has *no* depth
/// bound (the "stack" is the heap itself), so a fixed-size array here would
/// silently turn long lazy spines (e.g. `length [1..1000000]`) from "works"
/// into "crashes". Preserving that property is the point of using
/// `std.ArrayList` rather than a `[N]Frame` register file.
pub const Spine = struct {
    frames: std.ArrayList(Frame),
    allocator: std.mem.Allocator,

    /// An empty spine backed by `allocator`.
    pub fn init(allocator: std.mem.Allocator) Spine {
        return .{ .frames = .empty, .allocator = allocator };
    }

    /// Release the frame storage.
    pub fn deinit(self: *Spine) void {
        self.frames.deinit(self.allocator);
    }

    /// True when no frame remains — the replacement for `ctx.s == word.BACKSTOP`.
    pub fn isEmpty(self: *const Spine) bool {
        return self.frames.items.len == 0;
    }

    /// How many frames are on the spine (test/diagnostic use).
    pub fn depth(self: *const Spine) usize {
        return self.frames.items.len;
    }

    fn top(self: *Spine) *Frame {
        return &self.frames.items[self.frames.items.len - 1];
    }

    /// Descend into `e`'s head: push a frame for `e`, focus becomes `hd(e)`.
    /// Pure bookkeeping plus a read — `e` itself is never mutated. Mirrors
    /// `reduce_core.downLeft`.
    pub fn downLeft(self: *Spine, e: Word) Word {
        self.frames.append(self.allocator, .{ .node = e, .via_tl = false }) catch heap.mallocPanic("spine");
        return heap.h(e);
    }

    /// Descend into the top frame's tail, having just finished reducing its
    /// head to `reduced_head`. Writes back the reduced head (the one real
    /// graph mutation here) and re-tags the *existing* top frame rather than
    /// pushing a new one. Mirrors `reduce_core.downRight`.
    pub fn downRight(self: *Spine, reduced_head: Word) Word {
        const f = self.top();
        heap.hp(f.node).* = reduced_head;
        f.via_tl = true;
        return heap.t(f.node);
    }

    /// [downRight] guarded by spine-empty; `null` instead of descending when
    /// the spine is exhausted. Mirrors `reduce_core.downright`.
    pub fn downright(self: *Spine, reduced_head: Word) ?Word {
        if (self.isEmpty()) return null;
        return self.downRight(reduced_head);
    }

    /// Ascend out of the head: pop the top frame, write back the now-reduced
    /// value `reduced` into it, focus becomes the popped frame's cell.
    /// Mirrors `reduce_core.upLeft`.
    pub fn upLeft(self: *Spine, reduced: Word) Word {
        const f = self.frames.pop().?;
        heap.hp(f.node).* = reduced;
        return f.node;
    }

    /// [upLeft] guarded by spine-empty. Mirrors `reduce_core.upleft`.
    pub fn upleft(self: *Spine, reduced: Word) ?Word {
        if (self.isEmpty()) return null;
        return self.upLeft(reduced);
    }

    /// Ascend out of the tail: write back the now-reduced tail `reduced`,
    /// re-tag the still-top (*not popped*) frame back to "via hd", focus
    /// becomes the already-correct reduced head written by the matching
    /// `downRight`. Mirrors `reduce_core.upRight`.
    pub fn upRight(self: *Spine, reduced: Word) Word {
        const f = self.top();
        heap.tp(f.node).* = reduced;
        f.via_tl = false;
        return heap.h(f.node);
    }

    /// Push a frame directly, bypassing the read `downLeft` normally does.
    /// For the one call site (`combinators.handleTRY`'s tail) that fabricates
    /// a spine frame out of a cell it already holds, rather than descending
    /// into one via the normal `downLeft`.
    pub fn pushRaw(self: *Spine, node: Word, via_tl: bool) void {
        self.frames.append(self.allocator, .{ .node = node, .via_tl = via_tl }) catch heap.mallocPanic("spine");
    }

    /// Drop every frame. For the one call site (`combinators.handleFAIL`)
    /// that walks the *entire* spine down to empty in one bulk operation
    /// distinct from an ordinary `upLeft` pop.
    pub fn drainAll(self: *Spine) void {
        self.frames.clearRetainingCapacity();
    }
};

// --- Shadow-validation hooks -------------------------------------------------
//
// `active`, when non-null, names a `Spine` that the live pointer-reversal
// primitives (`reducer/reduce_core.zig`'s `downLeft`/`downRight`/`upLeft`/
// `upRight`, plus the direct spine manipulation in `combinators.handleTRY`/
// `handleFAIL` and `runtime/reduce.zig`'s `streamRead`) drive in lockstep,
// asserting their result matches what the live mechanism actually produced.
// This is how `spine_differential_test.zig` validates the new mechanism
// against thousands of real call sequences drawn from real program
// executions, instead of only the hand-built cases in this file's own tests.
//
// Default `null`: zero behavioural effect on the live interpreter or any
// existing test. Every `shadow*` helper below is a guarded no-op when `active`
// is `null` (the `orelse return null` short-circuits immediately), so the four
// primitives and the two backtracking handlers pay only a null check when
// validation is off.
pub var active: ?*Spine = null;

/// Call at the *start* of `reduce_core.downLeft`, before any real mutation:
/// drives the shadow and returns the value the live call is expected to
/// produce, for the caller to assert against once it has computed its own.
pub fn shadowDownLeft(e: Word) ?Word {
    const sh = active orelse return null;
    return sh.downLeft(e);
}

/// Call at the start of `reduce_core.downRight`, before any real mutation.
/// `reduced_head` is `ctx.e` at entry (the value about to be written back).
pub fn shadowDownRight(reduced_head: Word) ?Word {
    const sh = active orelse return null;
    if (sh.isEmpty()) return null; // desynced upstream (see shadowDesync) -- stop checking
    return sh.downRight(reduced_head);
}

/// Call at the start of `reduce_core.upLeft`, before any real mutation.
/// `reduced` is `ctx.e` at entry.
pub fn shadowUpLeft(reduced: Word) ?Word {
    const sh = active orelse return null;
    if (sh.isEmpty()) return null;
    return sh.upLeft(reduced);
}

/// Call at the start of `reduce_core.upRight`, before any real mutation.
/// `reduced` is `ctx.e` at entry.
pub fn shadowUpRight(reduced: Word) ?Word {
    const sh = active orelse return null;
    if (sh.isEmpty()) return null;
    return sh.upRight(reduced);
}

/// Mirror `combinators.handleTRY`'s raw fabricated frame (the one spot it
/// pushes a frame for a cell it already holds, instead of descending into it
/// via `downLeft`). `node`/`via_tl` are `handleTRY`'s `old_hd_e`/`true`.
pub fn shadowPushRaw(node: Word, via_tl: bool) void {
    const sh = active orelse return;
    sh.pushRaw(node, via_tl);
}

/// Mirror `combinators.handleFAIL`'s bulk drain of the entire spine.
pub fn shadowDrainAll() void {
    const sh = active orelse return;
    sh.drainAll();
}

const testing = std.testing;

test "downLeft: pushes a frame and reads hd without mutating the cell" {
    tu.freshInterp();
    const e = heap.cons(111, 222);
    var spine = Spine.init(testing.allocator);
    defer spine.deinit();

    const focus = spine.downLeft(e);

    try testing.expectEqual(@as(Word, 111), focus);
    try testing.expectEqual(@as(usize, 1), spine.depth());
    // `e` itself must be untouched -- no borrowed bookkeeping in the cell.
    try testing.expectEqual(@as(Word, 111), heap.h(e));
    try testing.expectEqual(@as(Word, 222), heap.t(e));
}

test "downLeft/upLeft round trip: writes back the reduced head and pops" {
    tu.freshInterp();
    const e = heap.cons(111, 222);
    var spine = Spine.init(testing.allocator);
    defer spine.deinit();

    _ = spine.downLeft(e);
    const focus = spine.upLeft(999); // pretend the head reduced to 999

    try testing.expectEqual(e, focus);
    try testing.expect(spine.isEmpty());
    try testing.expectEqual(@as(Word, 999), heap.h(e));
    try testing.expectEqual(@as(Word, 222), heap.t(e)); // tl untouched
}

test "downLeft/downRight/upRight/upLeft: full visit of one AP cell" {
    tu.freshInterp();
    const e = heap.cons(111, 222);
    var spine = Spine.init(testing.allocator);
    defer spine.deinit();

    // Visit the head: focus -> 111.
    var focus = spine.downLeft(e);
    try testing.expectEqual(@as(Word, 111), focus);

    // Head reduced to 'H'; descend into the tail: focus -> 222 (pristine).
    focus = spine.downRight('H');
    try testing.expectEqual(@as(Word, 222), focus);
    try testing.expectEqual(@as(Word, 'H'), heap.h(e)); // real write-back already happened
    try testing.expectEqual(@as(usize, 1), spine.depth()); // still one frame -- not pushed again

    // Tail reduced to 'T'; ascend back: focus -> the already-written head 'H'.
    focus = spine.upRight('T');
    try testing.expectEqual(@as(Word, 'H'), focus);
    try testing.expectEqual(@as(Word, 'T'), heap.t(e)); // real write-back of the tail
    try testing.expectEqual(@as(usize, 1), spine.depth()); // upRight does not pop

    // Finally leave the cell: pop with the (possibly further-rewritten) head.
    focus = spine.upLeft('H');
    try testing.expectEqual(e, focus);
    try testing.expect(spine.isEmpty());
    try testing.expectEqual(@as(Word, 'H'), heap.h(e));
    try testing.expectEqual(@as(Word, 'T'), heap.t(e));
}

test "a chain of AP cells unwinds and rewinds in LIFO order" {
    tu.freshInterp();
    const head_atom: Word = 42;
    const e2 = heap.cons(head_atom, 'c'); // innermost: hd = the "head atom"
    const e1 = heap.cons(e2, 'b');
    const e0 = heap.cons(e1, 'a'); // outermost

    var spine = Spine.init(testing.allocator);
    defer spine.deinit();

    // Unwind: downLeft(e0) -> e1, downLeft(e1) -> e2, downLeft(e2) -> head_atom.
    var focus = spine.downLeft(e0);
    try testing.expectEqual(e1, focus);
    focus = spine.downLeft(focus);
    try testing.expectEqual(e2, focus);
    focus = spine.downLeft(focus);
    try testing.expectEqual(head_atom, focus);
    try testing.expectEqual(@as(usize, 3), spine.depth());

    // Walk back up, writing a distinguishable marker at each level -- exactly
    // the shape repeated `upLeft` calls take in the real loop.
    focus = spine.upLeft(1000);
    try testing.expectEqual(e2, focus);
    try testing.expectEqual(@as(Word, 1000), heap.h(e2));

    focus = spine.upLeft(1001);
    try testing.expectEqual(e1, focus);
    try testing.expectEqual(@as(Word, 1001), heap.h(e1));

    focus = spine.upLeft(1002);
    try testing.expectEqual(e0, focus);
    try testing.expectEqual(@as(Word, 1002), heap.h(e0));

    try testing.expect(spine.isEmpty());
}

test "guarded downright/upleft report exhaustion instead of underflowing" {
    tu.freshInterp();
    var spine = Spine.init(testing.allocator);
    defer spine.deinit();

    try testing.expectEqual(@as(?Word, null), spine.upleft(0));
    try testing.expectEqual(@as(?Word, null), spine.downright(0));

    const e = heap.cons(1, 2);
    _ = spine.downLeft(e);
    try testing.expect(spine.upleft(7) != null);
    try testing.expect(spine.isEmpty());
}

test "depth is unbounded: a very long spine does not overflow a fixed stack" {
    tu.freshInterp();
    // This is the property pointer-reversal gets "for free" (the stack is the
    // heap, so it scales with available memory, not a fixed register file).
    // A `Spine` must preserve it -- this is the whole reason it is backed by
    // a growable `std.ArrayList` rather than a small fixed-size array.
    const depth_count = 200_000;
    var spine = Spine.init(testing.allocator);
    defer spine.deinit();

    var chain = heap.cons(0, 0);
    var i: usize = 0;
    while (i < depth_count) : (i += 1) {
        chain = heap.cons(chain, @as(Word, @intCast(i)));
    }

    var focus = chain;
    i = 0;
    while (i < depth_count) : (i += 1) {
        focus = spine.downLeft(focus);
    }
    try testing.expectEqual(@as(usize, depth_count), spine.depth());

    i = 0;
    while (i < depth_count) : (i += 1) {
        focus = spine.upLeft(focus);
    }
    try testing.expect(spine.isEmpty());
}
