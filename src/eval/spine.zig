//! eval/spine.zig — an explicit, heap-growable spine stack, replacing the
//! reduction engine's in-graph pointer reversal.
//!
//! ## Why this exists
//!
//! The old encoding had no separate stack: it threaded the return path
//! through the graph itself, temporarily overwriting a cell's own `hd` or
//! `tl` field with a "previous stack top" pointer (tagged with `tlptrbits` in
//! its top two bits) and restoring it on the way back. That is why every
//! `hd`/`tl`/`getTag` access in the hot loop had to mask `& ~tlptrbits`, and
//! why a future tagged `Value` (B2 option (a)) would have competed for the
//! same high bits.
//!
//! `Spine` replaces that encoding with an explicit stack of frames, kept
//! separate from the graph. Tracing every read/write the four original
//! primitives (`downLeft`/`downRight`/`upLeft`/`upRight`) performed showed
//! exactly one write per call was a *real* graph mutation (writing back a
//! reduced value so sharing still works); every other read/write was pure
//! bookkeeping for "what's below this frame". Moving that bookkeeping into an
//! explicit `Frame` means a cell's `hd`/`tl` hold a real graph value at every
//! instant, and no access anywhere needs `& ~tlptrbits`.
//!
//! **Key correctness property: `downRight` does not push a new frame.** It
//! *re-tags* the existing top frame (the one `downLeft` pushed for the same
//! cell) from "entered via hd" to "entered via tl" — both halves of visiting
//! one `AP` cell (its head, then its tail) share one frame. `upRight` mirrors
//! this: it does not pop — it writes back the reduced tail and flips the
//! frame back to "via hd", leaving it as the top frame. Only `upLeft` pops.
//!
//! ## Status: live
//!
//! `reduce_core.zig`'s `downLeft`/`downRight`/`upLeft`/`upRight` (and
//! `combinators.zig`'s `handleTRY`/`handleFAIL`, which manipulate the spine
//! directly rather than through those four) now run on `Spine` for real.
//! This rests on a shadow-validation pass done before the cutover: an opt-in
//! mode drove a `Spine` in lockstep with the (then still live) pointer
//! reversal for the whole run of the golden corpus plus a curated set of
//! `miralib/ex/` programs — 51 checks, zero mismatches (2026-07-01,
//! `71c47ae`..`c617ae2`). See that history for the derivation and the safety
//! bug it caught (an earlier version of the shadow performed real writes and
//! could corrupt the live program once desynced — fixed by making it
//! read-only before ever running it against anything live).

const std = @import("std");
const builtin = @import("builtin");
const heap = @import("../graph/heap.zig");
const value = @import("../graph/value.zig");
const tu = @import("../testutil.zig"); // unit-test harness (test builds only)

pub const Word = i64;
/// The typed graph value (Phase 5, docs/GO_PORT_PLAN.md §4.3, step 4):
/// `Frame.node` and every `Spine` method below carry this instead of a bare
/// `Word`. Callers not yet migrated (`reduce_core.zig`'s four wrappers,
/// `combinators.zig`'s `handleTRY`/`handleFAIL`) convert at the boundary via
/// `Value.fromRaw`/`.toRaw()` — this file is the first real (non-additive)
/// consumer of the typed surface `graph/value.zig` built in steps 1-3.
pub const Value = value.Value;

/// One frame of the explicit spine: the cell descended into (`node`), and
/// whether focus is currently inside it via `tl` (`via_tl`) or via `hd`.
/// Mirrors what pointer-reversal used to borrow from the cell's own field
/// plus the `tlptrbit` tag — but kept out of the graph.
pub const Frame = struct {
    node: Value,
    via_tl: bool,
};

/// One pooled, previously-`deinit`ed frame buffer, tagged with the allocator
/// it was allocated from. The tag matters: unit tests call `Spine.init` with
/// `std.testing.allocator` (a leak/mismatch-detecting allocator, distinct
/// from `rt.allocator` the live interpreter uses) — pooling buffers without
/// tracking their origin would let a buffer allocated by one get freed by the
/// other, which is undefined behaviour and exactly what `testing.allocator`
/// exists to catch.
pub const PooledBuffer = struct {
    allocator: std.mem.Allocator,
    frames: std.ArrayList(Frame),
};

/// A small free-list of previously-used frame buffers, reused by `Spine.init`
/// instead of allocating fresh every time (see `init`'s doc for why this
/// matters). Grows only up to the maximum number of `reduce()` calls ever
/// concurrently nested (each `deinit` returns one buffer; each `init` takes
/// one back) — not the number of calls made, which is unbounded. Pool
/// bookkeeping itself always allocates via `std.heap.page_allocator`,
/// independent of whichever allocator a given `Spine` uses for its frames.
///
/// Owned by `reduce.EvalState` (`ctx.eval.spine_buffer_pool`) rather than a
/// module global, per the shared-state plan's Phase 6 sweep — passed in
/// explicitly since `Spine.init`/`deinit` have no `self` yet to hang it off.
pub const BufferPool = std.ArrayList(PooledBuffer);
const pool_allocator = std.heap.page_allocator;

/// An explicit, growable spine stack. One per `reduce()` invocation — and
/// `reduce()` is recursive (see `force()` and the strict-operator handlers),
/// so each nested call owns its own `Spine`, exactly like each invocation
/// used to own its own private `ReductionCtx.s` chain.
///
/// Deliberately growable, not fixed-capacity: pointer reversal had *no* depth
/// bound (the "stack" was the heap itself), so a fixed-size array here would
/// silently turn long lazy spines (e.g. `length [1..1000000]`) from "works"
/// into "crashes". Preserving that property is the point of using
/// `std.ArrayList` rather than a `[N]Frame` register file.
pub const Spine = struct {
    frames: std.ArrayList(Frame),
    allocator: std.mem.Allocator,
    /// Links every currently-registered `Spine` into `gc_roots_head` (see the
    /// "GC roots" section below), in `reduce()`'s own call-stack nesting
    /// order. GC-root bookkeeping only; unrelated to the spine's own
    /// traversal semantics.
    next: ?*Spine = null,

    /// An empty spine backed by `allocator`. Callers that keep it alive
    /// across a possible GC point (any `reduce()` call does) must also
    /// `register` it — seed `ReductionCtx.spine` does this, see `reduce()`.
    ///
    /// Reuses a previously-`deinit`ed frame buffer from `buffer_pool` when one
    /// is available, instead of always starting from `std.ArrayList`'s empty
    /// (zero-capacity) state. `reduce()` is called *extremely* frequently —
    /// once per forced argument/nested strict evaluation, not just once per
    /// top-level expression — and most of those calls need only a handful of
    /// frames. Without reuse, every single one of those calls pays a fresh
    /// allocator round-trip for its first `append`, something pointer
    /// reversal never had to do (it borrowed graph cells, not the allocator).
    /// Measured: without this, a workload dominated by many short-lived
    /// `reduce()` calls (`#(take 3000 primes)`) was ~15x slower than the
    /// pre-cutover pointer-reversal build; with it, back in the same range
    /// (small workloads were already *faster* than pointer reversal even
    /// before this — fewer total memory writes per traversal step, see the
    /// module doc — this specifically closes the gap for the
    /// many-small-calls shape that regressed).
    pub fn init(allocator: std.mem.Allocator, pool: *BufferPool) Spine {
        // Pooling is skipped under `zig build test`: `std.testing.allocator`
        // does not offer the same "one stable, process-wide instance" lifetime
        // guarantee `rt.allocator` does in the real interpreter (reusing a
        // buffer across two *separate test functions'* allocator instances
        // corrupted the allocator's own bookkeeping -- caught by the leak/
        // bucket-mismatch assertions `std.testing.allocator` exists to catch).
        // Unit tests don't need the perf win; correctness there matters more.
        if (!builtin.is_test) {
            for (pool.items, 0..) |pooled, i| {
                if (std.meta.eql(pooled.allocator, allocator)) {
                    const frames = pooled.frames;
                    _ = pool.swapRemove(i);
                    return .{ .frames = frames, .allocator = allocator };
                }
            }
        }
        return .{ .frames = .empty, .allocator = allocator };
    }

    /// Return the frame storage to `pool` for reuse by a later `init`
    /// with the *same* allocator, instead of freeing it (skipped under test --
    /// see `init`). Callers that `register`ed this `Spine` must `unregister`
    /// it first.
    pub fn deinit(self: *Spine, pool: *BufferPool) void {
        self.frames.clearRetainingCapacity();
        if (builtin.is_test) {
            self.frames.deinit(self.allocator);
            return;
        }
        pool.append(pool_allocator, .{ .allocator = self.allocator, .frames = self.frames }) catch {
            // Pool itself is out of memory (rare -- it only grows to the
            // maximum concurrent reduce() nesting depth ever seen): just
            // free this buffer for real rather than leaking it.
            self.frames.deinit(self.allocator);
        };
    }

    /// Register this spine as a GC-root source: every `Frame.node` it holds
    /// is treated as reachable (see `markAllRoots`) for as long as it stays
    /// registered. Must be unregistered, in the exact reverse order of
    /// registration, before this `Spine` is destroyed — guaranteed by normal
    /// call-stack nesting (a nested `reduce()` call's spine is always
    /// registered after, and unregistered before, its caller's).
    pub fn register(self: *Spine, roots_head: *?*Spine) void {
        self.next = roots_head.*;
        roots_head.* = self;
    }

    /// Unregister this spine. Must currently be the registry head (see
    /// `register`'s nesting requirement).
    pub fn unregister(self: *Spine, roots_head: *?*Spine) void {
        std.debug.assert(roots_head.* == self);
        roots_head.* = self.next;
    }

    /// True when no frame remains — the replacement for the old
    /// `ctx.s == word.BACKSTOP` bottom-of-spine *equality* check (used by
    /// `reduce()`'s own part-3 loop to detect true exhaustion).
    pub inline fn isEmpty(self: *const Spine) bool {
        return self.frames.items.len == 0;
    }

    /// True when there is no frame left to walk through on the *current
    /// argument-accumulation chain* — the replacement for the old
    /// `abnormal(ctx.s)` (`ctx.s < 0`) guard used by the guarded traversal
    /// wrappers (`reduce_core.downright`/`upleft`, and transitively `getarg`)
    /// and by `combinators.handleTRY`/`handleFAIL`'s own loops. `abnormal` is
    /// true both when the spine is truly empty (`BACKSTOP`, sign bit set)
    /// *and* when the top frame is a real, non-empty one that happens to be
    /// tagged `via_tl=true` (also sign-bit set, since `tlptrbit` is the same
    /// bit) — every one of these call sites relies on that coincidence to
    /// stop at the boundary of an outer, already-`downRight`'d ancestor (a
    /// different context they must not reach into), not just at true
    /// emptiness. Missing this distinction (using plain `isEmpty()` instead)
    /// silently changes behaviour wherever the next frame happens to be
    /// via_tl=true: `combinators.handleTRY`/`handleFAIL` loop one iteration
    /// too many (found via differential comparison against the pre-cutover
    /// build on `firstel (x:xs) = x`), while `downright`/`upleft` themselves
    /// wrongly proceed to pop/descend into a frame they should have refused
    /// (found the same way on `colour ::= Red | Green | Blue`).
    pub inline fn atArgumentChainBoundary(self: *const Spine) bool {
        if (self.isEmpty()) return true;
        return self.frames.items[self.frames.items.len - 1].via_tl;
    }

    /// How many frames are on the spine (test/diagnostic use).
    pub fn depth(self: *const Spine) usize {
        return self.frames.items.len;
    }

    inline fn top(self: *Spine) *Frame {
        return &self.frames.items[self.frames.items.len - 1];
    }

    pub inline fn downLeft(self: *Spine, e: Value) Value {
        const len = self.frames.items.len;
        if (len < self.frames.capacity) {
            self.frames.items.len = len + 1;
            self.frames.items[len] = .{ .node = e, .via_tl = false };
        } else {
            self.frames.append(self.allocator, .{ .node = e, .via_tl = false }) catch heap.mallocPanic("spine");
        }
        return Value.fromRaw(heap.hCell(e.toRaw()));
    }

    /// Descend into the top frame's tail, having just finished reducing its
    /// head to `reduced_head`. Writes back the reduced head (the one real
    /// graph mutation here) and re-tags the *existing* top frame rather than
    /// pushing a new one.
    pub inline fn downRight(self: *Spine, heap_ptr: *heap.Heap, reduced_head: Value) Value {
        const f = self.top();
        heap.hp(heap_ptr, f.node.toRaw()).* = reduced_head.toRaw();
        f.via_tl = true;
        return Value.fromRaw(heap.tCell(f.node.toRaw()));
    }

    /// [downRight] guarded by spine-empty; `null` instead of descending when
    /// the spine is exhausted.
    pub inline fn downright(self: *Spine, heap_ptr: *heap.Heap, reduced_head: Value) ?Value {
        if (self.isEmpty()) return null;
        return self.downRight(heap_ptr, reduced_head);
    }

    /// Ascend out of the head: pop the top frame, write back the now-reduced
    /// value `reduced` into it, focus becomes the popped frame's cell.
    pub inline fn upLeft(self: *Spine, heap_ptr: *heap.Heap, reduced: Value) Value {
        const f = self.frames.pop().?;
        heap.hp(heap_ptr, f.node.toRaw()).* = reduced.toRaw();
        return f.node;
    }

    /// [upLeft] guarded by spine-empty.
    pub inline fn upleft(self: *Spine, heap_ptr: *heap.Heap, reduced: Value) ?Value {
        if (self.isEmpty()) return null;
        return self.upLeft(heap_ptr, reduced);
    }

    /// Ascend out of the tail: write back the now-reduced tail `reduced`,
    /// re-tag the still-top (*not popped*) frame back to "via hd", focus
    /// becomes the already-correct reduced head written by the matching
    /// `downRight`.
    pub inline fn upRight(self: *Spine, heap_ptr: *heap.Heap, reduced: Value) Value {
        const f = self.top();
        heap.tp(heap_ptr, f.node.toRaw()).* = reduced.toRaw();
        f.via_tl = false;
        return Value.fromRaw(heap.hCell(f.node.toRaw()));
    }

    /// Pop a frame and return just its node, with *no* write-back. For
    /// `combinators.handleFAIL`, which poisons the popped node directly
    /// (`FAIL` propagation) instead of writing back a normally-reduced value
    /// the way `upLeft` does. `null` once the spine is exhausted.
    pub fn popNodeOnly(self: *Spine) ?Value {
        const f = self.frames.pop() orelse return null;
        return f.node;
    }

    /// Push a frame directly, bypassing the read `downLeft` normally does.
    /// For the one call site (`combinators.handleTRY`'s tail) that fabricates
    /// a spine frame out of a cell it already holds, rather than descending
    /// into one via the normal `downLeft`.
    pub fn pushRaw(self: *Spine, node: Value, via_tl: bool) void {
        self.frames.append(self.allocator, .{ .node = node, .via_tl = via_tl }) catch heap.mallocPanic("spine");
    }

    /// Drop every frame. For the one call site (`combinators.handleFAIL`)
    /// that walks the *entire* spine down to empty in one bulk operation
    /// distinct from an ordinary `upLeft` pop.
    pub fn drainAll(self: *Spine) void {
        self.frames.clearRetainingCapacity();
    }
};

// --- GC roots ----------------------------------------------------------------
//
// The old in-graph pointer-reversal encoding kept every ancestor on the spine
// reachable "for free": the spine chain was threaded through real cells' own
// `hd`/`tl` fields, so the heap's conservative C-stack scan (`Heap.bases`,
// which finds `ReductionCtx.e`/`.s` simply because they were Word-sized slots
// on the Zig call stack) would find `ctx.s`, then `mark()`'s own hd/tl walk
// would follow the chain the rest of the way -- no separate root-enumeration
// needed.
//
// An explicit `Spine`'s `frames` buffer breaks that: it is a *separate* heap
// allocation (via `std.ArrayList`), not a Word sitting on the C stack, and
// not reachable through any cell's `hd`/`tl`. The conservative scanner finds
// `ctx.spine.frames.items.ptr` (a real memory address) as a stack-local Word,
// but `Heap.isptr` rejects it immediately (`x < self.TOP()` fails for any
// real pointer, which is astronomically larger than the heap's cell count)
// -- so `mark()` silently does nothing with it. Without an explicit fix, a
// cell reachable *only* via a `Frame.node` (not otherwise reachable through
// the graph or another root at that instant) could be collected out from
// under a paused reduction. This is exactly the "unblocks B3's precise GC
// roots" upside the original B2 audit noted for repivoting to a spine stack
// -- here realised as a requirement, not just a future opportunity.
//
// Fix: every live `Spine` links itself into `gc_roots_head` (`register`/
// `unregister`, above), and `Heap.bases` calls `markAllRoots` to mark every
// frame's `node` directly, alongside its existing root marking.

/// Mark every frame's `node` across every currently-registered spine as a GC
/// root. Called from `Heap.bases` alongside its other root marking, passing
/// the registry head owned by `reduce.EvalState` (`ev.gc_roots_head`) —
/// mirrors `reduce()`'s own call-stack nesting: the innermost active call's
/// spine is always the head.
pub fn markAllRoots(roots_head: ?*Spine, mark_fn: *const fn (Word) void) void {
    var s = roots_head;
    while (s) |sp| {
        for (sp.frames.items) |f| {
            mark_fn(f.node.toRaw());
        }
        s = sp.next;
    }
}

const testing = std.testing;

test "downLeft: pushes a frame and reads hd without mutating the cell" {
    tu.freshInterp();
    const e = heap.cons(heap.heap(), 111, 222);
    var pool: BufferPool = .empty;
    var spine = Spine.init(testing.allocator, &pool);
    defer spine.deinit(&pool);

    const focus = spine.downLeft(Value.fromRaw(e));

    try testing.expectEqual(@as(Word, 111), focus.toRaw());
    try testing.expectEqual(@as(usize, 1), spine.depth());
    // `e` itself must be untouched -- no borrowed bookkeeping in the cell.
    try testing.expectEqual(@as(Word, 111), heap.h(heap.heap(), e));
    try testing.expectEqual(@as(Word, 222), heap.t(heap.heap(), e));
}

test "downLeft/upLeft round trip: writes back the reduced head and pops" {
    tu.freshInterp();
    const e = heap.cons(heap.heap(), 111, 222);
    var pool: BufferPool = .empty;
    var spine = Spine.init(testing.allocator, &pool);
    defer spine.deinit(&pool);

    _ = spine.downLeft(Value.fromRaw(e));
    const focus = spine.upLeft(heap.heap(), Value.fromRaw(999)); // pretend the head reduced to 999

    try testing.expectEqual(e, focus.toRaw());
    try testing.expect(spine.isEmpty());
    try testing.expectEqual(@as(Word, 999), heap.h(heap.heap(), e));
    try testing.expectEqual(@as(Word, 222), heap.t(heap.heap(), e)); // tl untouched
}

test "downLeft/downRight/upRight/upLeft: full visit of one AP cell" {
    tu.freshInterp();
    const e = heap.cons(heap.heap(), 111, 222);
    var pool: BufferPool = .empty;
    var spine = Spine.init(testing.allocator, &pool);
    defer spine.deinit(&pool);

    // Visit the head: focus -> 111.
    var focus = spine.downLeft(Value.fromRaw(e));
    try testing.expectEqual(@as(Word, 111), focus.toRaw());

    // Head reduced to 'H'; descend into the tail: focus -> 222 (pristine).
    focus = spine.downRight(heap.heap(), Value.fromRaw('H'));
    try testing.expectEqual(@as(Word, 222), focus.toRaw());
    try testing.expectEqual(@as(Word, 'H'), heap.h(heap.heap(), e)); // real write-back already happened
    try testing.expectEqual(@as(usize, 1), spine.depth()); // still one frame -- not pushed again

    // Tail reduced to 'T'; ascend back: focus -> the already-written head 'H'.
    focus = spine.upRight(heap.heap(), Value.fromRaw('T'));
    try testing.expectEqual(@as(Word, 'H'), focus.toRaw());
    try testing.expectEqual(@as(Word, 'T'), heap.t(heap.heap(), e)); // real write-back of the tail
    try testing.expectEqual(@as(usize, 1), spine.depth()); // upRight does not pop

    // Finally leave the cell: pop with the (possibly further-rewritten) head.
    focus = spine.upLeft(heap.heap(), Value.fromRaw('H'));
    try testing.expectEqual(e, focus.toRaw());
    try testing.expect(spine.isEmpty());
    try testing.expectEqual(@as(Word, 'H'), heap.h(heap.heap(), e));
    try testing.expectEqual(@as(Word, 'T'), heap.t(heap.heap(), e));
}

test "a chain of AP cells unwinds and rewinds in LIFO order" {
    tu.freshInterp();
    const head_atom: Word = 42;
    const e2 = heap.cons(heap.heap(), head_atom, 'c'); // innermost: hd = the "head atom"
    const e1 = heap.cons(heap.heap(), e2, 'b');
    const e0 = heap.cons(heap.heap(), e1, 'a'); // outermost

    var pool: BufferPool = .empty;
    var spine = Spine.init(testing.allocator, &pool);
    defer spine.deinit(&pool);

    // Unwind: downLeft(e0) -> e1, downLeft(e1) -> e2, downLeft(e2) -> head_atom.
    var focus = spine.downLeft(Value.fromRaw(e0));
    try testing.expectEqual(e1, focus.toRaw());
    focus = spine.downLeft(focus);
    try testing.expectEqual(e2, focus.toRaw());
    focus = spine.downLeft(focus);
    try testing.expectEqual(head_atom, focus.toRaw());
    try testing.expectEqual(@as(usize, 3), spine.depth());

    // Walk back up, writing a distinguishable marker at each level -- exactly
    // the shape repeated `upLeft` calls take in the real loop.
    focus = spine.upLeft(heap.heap(), Value.fromRaw(1000));
    try testing.expectEqual(e2, focus.toRaw());
    try testing.expectEqual(@as(Word, 1000), heap.h(heap.heap(), e2));

    focus = spine.upLeft(heap.heap(), Value.fromRaw(1001));
    try testing.expectEqual(e1, focus.toRaw());
    try testing.expectEqual(@as(Word, 1001), heap.h(heap.heap(), e1));

    focus = spine.upLeft(heap.heap(), Value.fromRaw(1002));
    try testing.expectEqual(e0, focus.toRaw());
    try testing.expectEqual(@as(Word, 1002), heap.h(heap.heap(), e0));

    try testing.expect(spine.isEmpty());
}

test "guarded downright/upleft report exhaustion instead of underflowing" {
    tu.freshInterp();
    var pool: BufferPool = .empty;
    var spine = Spine.init(testing.allocator, &pool);
    defer spine.deinit(&pool);

    try testing.expectEqual(@as(?Value, null), spine.upleft(heap.heap(), Value.fromRaw(0)));
    try testing.expectEqual(@as(?Value, null), spine.downright(heap.heap(), Value.fromRaw(0)));

    const e = heap.cons(heap.heap(), 1, 2);
    _ = spine.downLeft(Value.fromRaw(e));
    try testing.expect(spine.upleft(heap.heap(), Value.fromRaw(7)) != null);
    try testing.expect(spine.isEmpty());
}

test "depth is unbounded: a very long spine does not overflow a fixed stack" {
    tu.freshInterp();
    // This is the property pointer-reversal used to get "for free" (the
    // stack was the heap, so it scaled with available memory, not a fixed
    // register file). A `Spine` must preserve it -- this is the whole reason
    // it is backed by a growable `std.ArrayList` rather than a small
    // fixed-size array.
    const depth_count = 200_000;
    var pool: BufferPool = .empty;
    var spine = Spine.init(testing.allocator, &pool);
    defer spine.deinit(&pool);

    var chain = heap.cons(heap.heap(), 0, 0);
    var i: usize = 0;
    while (i < depth_count) : (i += 1) {
        chain = heap.cons(heap.heap(), chain, @as(Word, @intCast(i)));
    }

    var focus = Value.fromRaw(chain);
    i = 0;
    while (i < depth_count) : (i += 1) {
        focus = spine.downLeft(focus);
    }
    try testing.expectEqual(@as(usize, depth_count), spine.depth());

    i = 0;
    while (i < depth_count) : (i += 1) {
        focus = spine.upLeft(heap.heap(), focus);
    }
    try testing.expect(spine.isEmpty());
}

test "pushRaw/drainAll: the handleTRY/handleFAIL primitives" {
    tu.freshInterp();
    var pool: BufferPool = .empty;
    var spine = Spine.init(testing.allocator, &pool);
    defer spine.deinit(&pool);

    const a = heap.cons(heap.heap(), 1, 2);
    const b = heap.cons(heap.heap(), 3, 4);
    spine.pushRaw(Value.fromRaw(a), false);
    spine.pushRaw(Value.fromRaw(b), true);
    try testing.expectEqual(@as(usize, 2), spine.depth());

    spine.drainAll();
    try testing.expect(spine.isEmpty());
}

test "register/unregister: markAllRoots visits every frame of every registered spine, nested LIFO" {
    tu.freshInterp();
    var pool: BufferPool = .empty;
    var roots_head: ?*Spine = null;
    var outer = Spine.init(testing.allocator, &pool);
    defer outer.deinit(&pool);
    const outer_node = heap.cons(heap.heap(), 1, 2);
    _ = outer.downLeft(Value.fromRaw(outer_node));
    outer.register(&roots_head);
    defer outer.unregister(&roots_head);

    var seen = std.ArrayList(Word).empty;
    defer seen.deinit(testing.allocator);
    const Collector = struct {
        var target: *std.ArrayList(Word) = undefined;
        fn collect(w: Word) void {
            target.append(testing.allocator, w) catch unreachable;
        }
    };
    Collector.target = &seen;

    markAllRoots(roots_head, Collector.collect);
    try testing.expectEqual(@as(usize, 1), seen.items.len);
    try testing.expectEqual(outer_node, seen.items[0]);

    // A nested spine (as a nested reduce() call would create) registers on
    // top and unregisters before the outer one -- exactly LIFO call-stack
    // nesting. markAllRoots must see both while the inner one is live.
    {
        var inner = Spine.init(testing.allocator, &pool);
        defer inner.deinit(&pool);
        const inner_node = heap.cons(heap.heap(), 5, 6);
        _ = inner.downLeft(Value.fromRaw(inner_node));
        inner.register(&roots_head);
        defer inner.unregister(&roots_head);

        seen.clearRetainingCapacity();
        markAllRoots(roots_head, Collector.collect);
        try testing.expectEqual(@as(usize, 2), seen.items.len);
        try testing.expect(std.mem.findScalar(Word, seen.items, outer_node) != null);
        try testing.expect(std.mem.findScalar(Word, seen.items, inner_node) != null);
    }

    // Back to just the outer spine after the inner one unregisters.
    seen.clearRetainingCapacity();
    markAllRoots(roots_head, Collector.collect);
    try testing.expectEqual(@as(usize, 1), seen.items.len);
    try testing.expectEqual(outer_node, seen.items[0]);
}
