//! strtab.zig — interned string table for node-stored identifier and pathname
//! strings (Track B1 / R6, step 2).
//!
//! Step 1 funnelled every read/write of a node-stored string through three
//! accessors in `word.zig` (`strOf`/`strOfMut`/`strBits`) that cast a `[*:0]`
//! pointer to/from a `Word`. Step 2 moves the accessors here and swaps the
//! representation: a node now stores a `StrId` (a table index) instead of a raw
//! pointer, and the bytes live once in a process-lifetime arena. Interning
//! de-dups by content, so equal names share one `StrId` — which is what keeps
//! the re-intern-then-compare pattern (`member(list, strBits(get_id(x)))`)
//! working now that `get_id` no longer returns a stable pointer.
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
const rt = @import("runtime_state.zig");
const word = @import("word.zig");

const Word = word.Word;

/// Dense table index (1-based; slot 0 is the empty/sentinel string). The value
/// stored in a node is the *negation* of this — see the file header.
const StrId = u32;

const Table = struct {
    /// Owns the interned bytes; pointers into it are stable for the session.
    arena: std.heap.ArenaAllocator,
    /// index -> interned NUL-terminated slice. Slot 0 is "" (the sentinel).
    slices: std.ArrayList([:0]const u8) = .empty,
    /// content -> index, for de-dup. Keys are the arena-owned slices.
    dedup: std.StringHashMapUnmanaged(StrId) = .empty,
};

var table: ?Table = null;

fn oom() noreturn {
    @panic("strtab: out of memory");
}

fn get() *Table {
    if (table == null) {
        table = .{ .arena = std.heap.ArenaAllocator.init(rt.allocator) };
        // Reserve index 0 as the empty/null sentinel so real ids are >= 1.
        table.?.slices.append(rt.allocator, "") catch oom();
    }
    return &table.?;
}

/// Intern `p` (a NUL-terminated C string) and return its id as a `Word` for
/// storage in a node. Equal content yields the same id; empty input yields the
/// 0 sentinel.
pub fn strBits(p: anytype) Word {
    const span = std.mem.span(p);
    if (span.len == 0) return 0;
    const t = get();
    if (t.dedup.get(span)) |id| return -@as(Word, id);
    const copy = t.arena.allocator().dupeZ(u8, span) catch oom();
    const id: StrId = @intCast(t.slices.items.len);
    t.slices.append(rt.allocator, copy) catch oom();
    t.dedup.put(rt.allocator, copy, id) catch oom();
    return -@as(Word, id);
}

/// Resolve an id `Word` (as stored in a node) back to its NUL-terminated bytes.
/// The 0 sentinel and any non-id Word resolve to "".
pub fn strOf(handle: Word) [*:0]const u8 {
    if (handle >= 0) return "";
    const t = get();
    const id: usize = @intCast(-handle);
    if (id >= t.slices.items.len) return "";
    return t.slices.items[id].ptr;
}

/// Re-intern the string identified by `handle` with its first byte privatised
/// (high bit set), returning the new id `Word`. The lexer uses this to hide
/// prelude identifiers: under the old pointer representation it mutated the
/// stored bytes in place (`get_id(..)[0] += 128`); interned bytes are immutable
/// and shared, so a privatised name must be a fresh entry instead. Empty input
/// is returned unchanged.
pub fn privatize(handle: Word) Word {
    const cur = std.mem.span(strOf(handle));
    if (cur.len == 0) return handle;
    const t = get();
    const scratch = t.arena.allocator().dupeZ(u8, cur) catch oom();
    scratch[0] +%= 128;
    return strBits(@as([*:0]const u8, scratch.ptr));
}

/// Release all interned storage. For test teardown / a clean shutdown; the
/// session normally keeps the table for its whole lifetime.
pub fn deinit() void {
    if (table) |*t| {
        t.dedup.deinit(rt.allocator);
        t.slices.deinit(rt.allocator);
        t.arena.deinit();
        table = null;
    }
}

test "intern de-dups by content and resolves" {
    deinit();
    defer deinit();

    const foo1 = strBits(@as([*:0]const u8, "foo"));
    const foo2 = strBits(@as([*:0]const u8, "foo"));
    const bar = strBits(@as([*:0]const u8, "bar"));

    try std.testing.expectEqual(foo1, foo2); // dedup: same content -> same id
    try std.testing.expect(foo1 != bar);
    try std.testing.expect(foo1 < 0); // real ids are negative (out of ptr range)

    try std.testing.expectEqualStrings("foo", std.mem.span(strOf(foo1)));
    try std.testing.expectEqualStrings("bar", std.mem.span(strOf(bar)));
}

test "empty interns to the 0 sentinel and 0 resolves to empty" {
    deinit();
    defer deinit();

    try std.testing.expectEqual(@as(Word, 0), strBits(@as([*:0]const u8, "")));
    try std.testing.expectEqualStrings("", std.mem.span(strOf(0)));
    // A real string never collides with the sentinel.
    try std.testing.expect(strBits(@as([*:0]const u8, "x")) != 0);
}
