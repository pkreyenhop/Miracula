//! strtab.zig — interned string table for node-stored identifier and pathname
//! strings (Track B1 / R6, step 2).
//!
//! Step 1 funnelled every read/write of a node-stored string through three
//! accessors in `word.zig` (`strOf`/`strOfMut`/`strBits`) that cast a `[*:0]`
//! pointer to/from a `Word`. Step 2 moves the accessors here and swaps the
//! representation: a node now stores a `StrId` (a table index) instead of a raw
//! pointer, and the bytes live once in a process-lifetime arena. Interning
//! de-dups by content, so equal names share one `StrId` — which is what keeps
//! the re-intern-then-compare pattern (`member(list, strBits(getId(x)))`)
//! working now that `getId` no longer returns a stable pointer.
//!
//! Encoding. A `StrId` is stored *negated* in the `Word` (`-index`, index >= 1).
//! Heap cell handles live in `[ATOMLIMIT, TOP())` and `heap.isptr` tests that
//! range; the old raw pointers were always *above* `TOP()`, so the GC's `mark`
//! skipped them wherever a string Word sat in a traced slot (a `CONS.hd` in
//! `exportfiles`, a `CONSTRUCTOR.tl`, …). A small positive index would fall
//! *inside* the cell range and be mis-followed as a handle. A negative Word is
//! below `ATOMLIMIT`, and even after `mark`'s `& ~tlptrbits` it becomes a value
//! far above `TOP()` — so `isptr` is false either way, preserving GC behaviour
//! at every slot without auditing each one. `Word` 0 stays the "no string"
//! sentinel (real ids are negative); resolving 0 yields "".

const std = @import("std");
const rt = @import("../runtime/runtime_state.zig");
const word = @import("word.zig");

const Word = word.Word;

/// Dense table index (1-based; slot 0 is the empty/sentinel string). The value
/// stored in a node is the *negation* of this — see the file header.
const StrId = u32;

/// Interned string table — folded into `interp.strtab` (shared-state plan) so
/// `interp.reset()` clears it. The arena can't default-construct (it needs an
/// allocator), so the table is *lazily* initialised on first use, gated by
/// `initialized`. A reset zeroes the struct (`initialized = false`), and the next
/// access re-inits — which is how a reset wipes all interned strings.
///
/// **Narrow substructure threading (Track SHARED_STATE, Phase 5 Tier 1,
/// 2026-07-01).** Every function here takes the `*StringTable` it operates on
/// as an explicit parameter instead of reaching the global `interp` singleton
/// ambiently. Callers still source that pointer from the (still-global,
/// Tier-3-deferred) singleton via the `table` convenience constant below.
pub const StringTable = struct {
    /// Owns the interned bytes; pointers into it are stable for the session.
    arena: std.heap.ArenaAllocator = undefined,
    /// index -> interned NUL-terminated slice. Slot 0 is "" (the sentinel).
    slices: std.ArrayList([:0]const u8) = .empty,
    /// content -> index, for de-dup. Keys are the arena-owned slices.
    dedup: std.StringHashMapUnmanaged(StrId) = .empty,
    initialized: bool = false,
};

/// Pointer to the string table held in `current_interp`. A convenience for
/// *callers* to obtain a `*StringTable` to pass in — this module's own
/// functions no longer read it ambiently.
pub inline fn table() *StringTable {
    return &@import("../session/interp.zig").current_interp.strtab;
}

/// Abort: the string table ran out of memory.
fn oom() noreturn {
    @panic("strtab: out of memory");
}

/// Lazily initialise `self` on first use.
fn ensureInit(self: *StringTable) void {
    if (!self.initialized) {
        self.arena = std.heap.ArenaAllocator.init(rt.allocator);
        self.slices = .empty;
        self.dedup = .empty;
        // Reserve index 0 as the empty/null sentinel so real ids are >= 1.
        self.slices.append(rt.allocator, "") catch oom();
        self.initialized = true;
    }
}

/// Intern `p` (a NUL-terminated C string) and return its id as a `Word` for
/// storage in a node. Equal content yields the same id; empty input yields the
/// 0 sentinel.
///
/// Tests: intern de-dups by content and resolves
pub fn strBits(self: *StringTable, p: anytype) Word {
    const span = if (@typeInfo(@TypeOf(p)) == .pointer and @typeInfo(@TypeOf(p)).pointer.size == .slice) p else std.mem.span(p);
    if (span.len == 0) return 0;
    ensureInit(self);
    if (self.dedup.get(span)) |id| return -@as(Word, id);
    const copy = self.arena.allocator().dupeSentinel(u8, span, 0) catch oom();
    const id: StrId = @intCast(self.slices.items.len);
    self.slices.append(rt.allocator, copy) catch oom();
    self.dedup.put(rt.allocator, copy, id) catch oom();
    return -@as(Word, id);
}

test "intern de-dups by content and resolves" {
    deinit(table());
    defer deinit(table());

    const foo1 = strBits(table(), @as([*:0]const u8, "foo"));
    const foo2 = strBits(table(), @as([*:0]const u8, "foo"));
    const bar = strBits(table(), @as([*:0]const u8, "bar"));

    try std.testing.expectEqual(foo1, foo2); // dedup: same content -> same id
    try std.testing.expect(foo1 != bar);
    try std.testing.expect(foo1 < 0); // real ids are negative (out of ptr range)

    try std.testing.expectEqualStrings("foo", strOf(table(), foo1));
    try std.testing.expectEqualStrings("bar", strOf(table(), bar));
}

/// Resolve an id `Word` (as stored in a node) back to its NUL-terminated bytes.
/// The 0 sentinel and any non-id Word resolve to "".
///
/// Tests: empty interns to the 0 sentinel and 0 resolves to empty
pub fn strOf(self: *StringTable, handle: Word) [:0]const u8 {
    if (handle >= 0) return "";
    ensureInit(self);
    const id: usize = @intCast(-handle);
    if (id >= self.slices.items.len) return "";
    return self.slices.items[id];
}

test "empty interns to the 0 sentinel and 0 resolves to empty" {
    deinit(table());
    defer deinit(table());

    try std.testing.expectEqual(@as(Word, 0), strBits(table(), @as([*:0]const u8, "")));
    try std.testing.expectEqualStrings("", strOf(table(), 0));
    // A real string never collides with the sentinel.
    try std.testing.expect(strBits(table(), @as([*:0]const u8, "x")) != 0);
}

/// Re-intern the string identified by `handle` with its first byte privatised
/// (high bit set), returning the new id `Word`. The lexer uses this to hide
/// prelude identifiers: under the old pointer representation it mutated the
/// stored bytes in place (`getId(..)[0] += 128`); interned bytes are immutable
/// and shared, so a privatised name must be a fresh entry instead. Empty input
/// is returned unchanged.
///
/// Tests: privatize re-interns with the first byte high-bit set
pub fn privatize(self: *StringTable, handle: Word) Word {
    const cur = strOf(self, handle);
    if (cur.len == 0) return handle;
    ensureInit(self);
    const scratch = self.arena.allocator().dupeSentinel(u8, cur, 0) catch oom();
    scratch[0] +%= 128;
    return strBits(self, @as([*:0]const u8, scratch.ptr));
}

test "privatize re-interns with the first byte high-bit set" {
    deinit(table());
    defer deinit(table());

    const foo = strBits(table(), @as([*:0]const u8, "foo"));
    const priv = privatize(table(), foo);
    try std.testing.expect(priv != foo); // a fresh entry, not an in-place mutation
    const bytes = strOf(table(), priv);
    try std.testing.expectEqual(@as(u8, 'f' + 128), bytes[0]);
    try std.testing.expectEqualStrings("oo", bytes[1..]);
    try std.testing.expectEqual(@as(Word, 0), privatize(table(), 0)); // empty unchanged
}

/// Release all interned storage. For test teardown / a clean shutdown; the
/// session normally keeps the table for its whole lifetime.
///
/// Tests: deinit clears the table so the next use re-inits fresh
pub fn deinit(self: *StringTable) void {
    if (self.initialized) {
        self.dedup.deinit(rt.allocator);
        self.slices.deinit(rt.allocator);
        self.arena.deinit();
        self.initialized = false;
    }
}

test "deinit clears the table so the next use re-inits fresh" {
    deinit(table());
    const a = strBits(table(), @as([*:0]const u8, "alpha"));
    try std.testing.expectEqualStrings("alpha", strOf(table(), a));
    deinit(table());
    // After deinit the table is empty, so the old handle no longer resolves.
    try std.testing.expectEqualStrings("", strOf(table(), a));
    // A fresh intern restarts ids, so "beta" reclaims the first id that "alpha" had.
    const b = strBits(table(), @as([*:0]const u8, "beta"));
    try std.testing.expectEqual(a, b);
    deinit(table());
}
