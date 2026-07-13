//! semantics/symbols.zig — the identifier dictionary as an allocator-backed
//! hash map (docs/ZIG_NATIVE_PLAN.md Phase 1 step 6), replacing
//! `parser/lex.zig`'s `makeId`/`findid`/`name()` (a fixed-size hash-bucket
//! array — the lex state's `namebucket` field — chained through cons cells on
//! the heap) and `makePn`/`stoPn`/`resetPns` (a manually `realloc`ed
//! private-name vector — the lex state's `pnvec` field).
//!
//! **What doesn't change:** identifiers are still represented on the heap
//! exactly as they are today — an `ID` cell wrapping a `STRCONS` cell whose
//! `hd` is a `strtab`-interned `StrId` (`heap.stoId`/`heap.getId`). This
//! module only replaces the *lookup structure* (how a name maps to its `ID`
//! node) and the *private-name allocation* (how a compiler-synthesized name
//! maps to its node) — the heap encoding downstream code
//! (`codegen.zig`/`trans.zig`/`types.zig`) already understands is untouched.
//!
//! **`SymbolTable.intern`** is `makeId`+`findid`+`name()` combined: find the
//! existing `ID` node for `name` if one exists (matching `findid`), else
//! build a fresh one via `heap.stoId` and remember it (matching `makeId`).
//! The map's key is the `ID` node's own interned string (via `heap.getId`,
//! which resolves through `strtab` — permanent, stable storage), so this
//! table owns no string memory of its own beyond the temporary NUL-terminated
//! copy `heap.stoId` needs.
//!
//! **`PrivateNames`** replaces the fixed-growth-by-400, manually-`realloc`ed
//! the lex state's `pnvec` field with a plain `std.ArrayList`. A private name is a raw
//! `STRCONS` cell tagging an index and a value (`make(.STRCONS, index, val)`)
//! — it never goes through `strtab` at all, since compiler-synthesized names
//! have no user-typed text (see `makePn`/`stoPn` in `lex.zig`).
//!
//! Not yet wired into `codegen.zig`/`trans.zig`'s identifier lookups, or into
//! `syntax/lexer.zig` — additive and independently tested, same as every
//! other `syntax/`/`semantics/` file landed so far in this phase.
//!
//! Tests: SymbolTable.intern/find, PrivateNames.make/get — one test per
//! behaviour, cross-checked against `lex.zig`'s existing `makeId`/`findid`
//! test where the same interpreter state is safe to share.

const std = @import("std");
const word = @import("../graph/word.zig");
const heap_mod = @import("../graph/heap.zig");
const strtab = @import("../graph/strtab.zig");

const Word = word.Word;
const Value = @import("../graph/value.zig").Value;

/// Pointer to the singleton `SymbolTable` inside `current_interp` (so
/// `interp.reset()` clears it, same convention as `heap.heap()`/`core_state.s()`).
/// Accessed as `symbols.syms().X`. (Named `syms`, not `table`, to avoid
/// colliding with `strtab.table()`.)
pub inline fn syms() *SymbolTable {
    return &@import("../session/interp.zig").current_interp.symbols;
}

/// Maps identifier text to its heap `ID` node, first-seen-wins (matching
/// `lex.zig`'s dictionary: the same node is returned for every later lookup
/// of an already-interned name, so identity comparisons on `ID` nodes stay
/// valid). The map owns no string memory of its own — keys are `heap.getId`'s
/// stable, `strtab`-owned bytes.
pub const SymbolTable = struct {
    table: std.StringHashMapUnmanaged(Word) = .{},

    pub fn deinit(self: *SymbolTable, gpa: std.mem.Allocator) void {
        self.table.deinit(gpa);
        self.* = undefined;
    }

    /// Find-or-create: intern `name` as an `ID` heap node. Matches `lex.zig`'s
    /// `name()` — repeated calls with the same text return the same node.
    ///
    /// **Not** a match for `makeId` — see `createFresh` for that. (An earlier
    /// attempt at this migration used `intern` for `makeId` too and broke
    /// prelude/stdenv bootstrap; see `createFresh`'s doc comment.)
    pub fn intern(self: *SymbolTable, gpa: std.mem.Allocator, name: []const u8) !Value {
        if (self.table.get(name)) |id| return Value.fromRaw(id);
        const name_z = try gpa.dupeZ(u8, name);
        defer gpa.free(name_z);
        const id = heap_mod.stoId(name_z);
        const stable_name = std.mem.span(heap_mod.getId(id));
        try self.table.put(gpa, stable_name, id);
        return Value.fromRaw(id);
    }

    /// Look up `name` without creating it. Matches `lex.zig`'s `findid`:
    /// returns `null` (not `NIL`) for "not present" — callers translate to
    /// whatever sentinel their own heap-value convention needs.
    pub fn find(self: *const SymbolTable, name: []const u8) ?Value {
        return if (self.table.get(name)) |id| Value.fromRaw(id) else null;
    }

    /// Intern `name` as a *fresh* `ID` node, unconditionally — creates a new
    /// heap cell and overwrites any existing dictionary entry for `name`,
    /// rather than reusing one. Matches `lex.zig`'s `makeId`.
    ///
    /// **Not find-or-create** — verified empirically (not just by inspection):
    /// `compiler/setup.zig`'s `predef`/`primdef` call this repeatedly for
    /// overlapping names across `privlib()` (prelude bootstrap) and `stdlib()`
    /// (stdenv bootstrap) — e.g. "error"/"code"/"decode"/"drop"/"foldr"/
    /// "shownum"/"take" are each `predef`'d once in each stage — deliberately
    /// creating a *new* cell that shadows the previous one for name lookup,
    /// not reusing it. A find-or-create version silently merges these into
    /// one cell, corrupting prelude/stdenv bootstrap (garbled dump/undump
    /// round trip — every golden test failing).
    ///
    /// `name` need not outlive this call — a NUL-terminated copy is made for
    /// `heap.stoId`'s benefit and freed before returning; `stoId` interns its
    /// own permanent copy via `strtab` immediately, same as `intern`.
    pub fn createFresh(self: *SymbolTable, gpa: std.mem.Allocator, name: []const u8) !Value {
        const name_z = try gpa.dupeZ(u8, name);
        defer gpa.free(name_z);
        const id = heap_mod.stoId(name_z);
        const stable_name = std.mem.span(heap_mod.getId(id));
        try self.table.put(gpa, stable_name, id);
        return Value.fromRaw(id);
    }

    /// Number of distinct identifiers interned so far.
    pub fn count(self: *const SymbolTable) usize {
        return self.table.count();
    }

    /// Rebind an already-interned `name` to a different `ID` node, without
    /// interning a new name. Used by `compiler/dump.zig`'s `%export`
    /// dump-time hiding (`privatise`/`publicise`): the *node* a name's
    /// dictionary entry points to changes (swapped for a private-name node
    /// while writing a `.x` file, swapped back after), the name itself
    /// doesn't. A no-op (silently) if `name` isn't present — callers own
    /// verifying that invariant, matching the legacy bucket-chain code's own
    /// "if not found, do nothing" fallthrough.
    pub fn rebind(self: *SymbolTable, gpa: std.mem.Allocator, name: []const u8, new_id: Value) !void {
        if (!self.table.contains(name)) return;
        try self.table.put(gpa, name, new_id.toRaw());
    }

    /// Bind `name` to `id`, unconditionally — inserts a new entry or
    /// overwrites an existing one, whether or not `name` was interned
    /// before. Used for `%include` aliasing (`syntax/directives.zig`'s
    /// `Alias.rename`): the alias name (e.g. `mike_f` in `%include "mike"
    /// mike_f/f`) usually isn't interned yet, unlike `rebind`'s
    /// requirement, and this isn't a *node* changing identity for a name
    /// that already resolves there (`rebind`'s job) — it's introducing a
    /// brand new *name* for an existing node.
    ///
    /// `name` need not outlive this call (interned into `strtab`
    /// immediately, same as `createFresh`) — callers may pass a
    /// transient/arena-backed slice (e.g. straight out of a `Source`'s
    /// bytes) safely.
    pub fn bind(self: *SymbolTable, gpa: std.mem.Allocator, name: []const u8, id: Value) !void {
        const name_z = try gpa.dupeZ(u8, name);
        defer gpa.free(name_z);
        const bits = strtab.strBits(strtab.table(), name_z.ptr);
        const stable_name = std.mem.span(strtab.strOf(strtab.table(), bits));
        try self.table.put(gpa, stable_name, id.toRaw());
    }
};

/// A compiler-synthesized ("private") name: an index-tagged `STRCONS` cell,
/// never `strtab`-interned (it has no user-typed text). Replaces `lex.zig`'s
/// manually-`realloc`ed private-name vector (the lex state's `pnvec` field,
/// grown in fixed +400 chunks) with a plain growable list.
pub const PrivateNames = struct {
    table: std.ArrayList(Word) = .empty,

    pub fn deinit(self: *PrivateNames, gpa: std.mem.Allocator) void {
        self.table.deinit(gpa);
        self.* = undefined;
    }

    /// Allocate a fresh private-name node holding `val`. Matches `lex.zig`'s
    /// `makePn`: the node's index is its position (`nextpn` there, `items.len`
    /// here) at allocation time.
    pub fn make(self: *PrivateNames, heap: *heap_mod.Heap, gpa: std.mem.Allocator, val: Value) !Value {
        const idx = self.table.items.len;
        const node = heap_mod.make(heap, .STRCONS, @intCast(idx), val.toRaw());
        try self.table.append(gpa, node);
        return Value.fromRaw(node);
    }

    /// The private name at index `n`, allocating placeholder nodes
    /// (`val = UNDEF`) up to and including `n` if it hasn't been made yet.
    /// Matches `lex.zig`'s `stoPn` (used when a private name is referenced —
    /// e.g. during dump/undump — before `make` has been called for it).
    pub fn get(self: *PrivateNames, heap: *heap_mod.Heap, gpa: std.mem.Allocator, n: usize) !Value {
        while (self.table.items.len <= n) {
            const idx = self.table.items.len;
            try self.table.append(gpa, heap_mod.make(heap, .STRCONS, @intCast(idx), word.UNDEF));
        }
        return Value.fromRaw(self.table.items[n]);
    }

    /// Number of private names allocated so far.
    pub fn count(self: *const PrivateNames) usize {
        return self.table.items.len;
    }
};

const tu = @import("../testutil.zig");

test "SymbolTable.intern: repeated interning of the same name returns the same ID node" {
    tu.freshInterp();
    var st: SymbolTable = .{};
    defer st.deinit(std.testing.allocator);
    const a = try st.intern(std.testing.allocator, "zzsymfoo");
    const b = try st.intern(std.testing.allocator, "zzsymfoo");
    try std.testing.expectEqual(a, b);
}

test "SymbolTable.intern: distinct names get distinct ID nodes" {
    tu.freshInterp();
    var st: SymbolTable = .{};
    defer st.deinit(std.testing.allocator);
    const a = try st.intern(std.testing.allocator, "zzsymbar1");
    const b = try st.intern(std.testing.allocator, "zzsymbar2");
    try std.testing.expect(a != b);
}

test "SymbolTable.find: absent name is null, present name matches intern's result" {
    tu.freshInterp();
    var st: SymbolTable = .{};
    defer st.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(?Value, null), st.find("zzsymabsent"));
    const id = try st.intern(std.testing.allocator, "zzsympresent");
    try std.testing.expectEqual(@as(?Value, id), st.find("zzsympresent"));
}

test "SymbolTable.intern: the ID node round-trips through heap.getId" {
    tu.freshInterp();
    var st: SymbolTable = .{};
    defer st.deinit(std.testing.allocator);
    const id = try st.intern(std.testing.allocator, "zzsymroundtrip");
    try std.testing.expectEqualStrings("zzsymroundtrip", std.mem.span(heap_mod.getId(id.toRaw())));
}

test "SymbolTable.count: tracks the number of distinct interned names" {
    tu.freshInterp();
    var st: SymbolTable = .{};
    defer st.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 0), st.count());
    _ = try st.intern(std.testing.allocator, "zzsymcount1");
    _ = try st.intern(std.testing.allocator, "zzsymcount2");
    _ = try st.intern(std.testing.allocator, "zzsymcount1"); // repeat, not a new entry
    try std.testing.expectEqual(@as(usize, 2), st.count());
}

test "SymbolTable.createFresh: repeated calls with the same name yield distinct nodes" {
    tu.freshInterp();
    var st: SymbolTable = .{};
    defer st.deinit(std.testing.allocator);
    const a = try st.createFresh(std.testing.allocator, "zzsymfresh");
    const b = try st.createFresh(std.testing.allocator, "zzsymfresh");
    try std.testing.expect(a != b);
}

test "SymbolTable.createFresh: the newest call wins subsequent find lookups" {
    tu.freshInterp();
    var st: SymbolTable = .{};
    defer st.deinit(std.testing.allocator);
    _ = try st.createFresh(std.testing.allocator, "zzsymshadow");
    const b = try st.createFresh(std.testing.allocator, "zzsymshadow");
    try std.testing.expectEqual(@as(?Value, b), st.find("zzsymshadow"));
}

test "PrivateNames.make: each call allocates a fresh, index-tagged node" {
    tu.freshInterp();
    var pns: PrivateNames = .{};
    defer pns.deinit(std.testing.allocator);
    const n0 = try pns.make(heap_mod.heap(), std.testing.allocator, Value.fromRaw(word.UNDEF));
    const n1 = try pns.make(heap_mod.heap(), std.testing.allocator, Value.fromRaw(word.UNDEF));
    try std.testing.expect(n0 != n1);
    try std.testing.expectEqual(@as(usize, 2), pns.count());
}

test "PrivateNames.get: allocates placeholders up to index n, then is stable" {
    tu.freshInterp();
    var pns: PrivateNames = .{};
    defer pns.deinit(std.testing.allocator);
    const n5_first = try pns.get(heap_mod.heap(), std.testing.allocator, 5);
    try std.testing.expectEqual(@as(usize, 6), pns.count()); // indices 0..5
    const n5_again = try pns.get(heap_mod.heap(), std.testing.allocator, 5);
    try std.testing.expectEqual(n5_first, n5_again);
}

test "PrivateNames.get after make: pre-existing indices are not reallocated" {
    tu.freshInterp();
    var pns: PrivateNames = .{};
    defer pns.deinit(std.testing.allocator);
    const made = try pns.make(heap_mod.heap(), std.testing.allocator, Value.fromRaw(word.UNDEF)); // index 0
    const fetched = try pns.get(heap_mod.heap(), std.testing.allocator, 0);
    try std.testing.expectEqual(made, fetched);
}

test "SymbolTable.rebind: changes an existing name's node without re-interning" {
    tu.freshInterp();
    var st: SymbolTable = .{};
    defer st.deinit(std.testing.allocator);
    const original = try st.intern(std.testing.allocator, "zzsymrebind");
    try st.rebind(std.testing.allocator, "zzsymrebind", Value.fromRaw(999));
    try std.testing.expectEqual(@as(?Value, Value.fromRaw(999)), st.find("zzsymrebind"));
    try std.testing.expectEqual(@as(usize, 1), st.count()); // no new entry
    _ = original;
}

test "SymbolTable.rebind: a no-op for a name that was never interned" {
    tu.freshInterp();
    var st: SymbolTable = .{};
    defer st.deinit(std.testing.allocator);
    try st.rebind(std.testing.allocator, "zzsymneverexisted", Value.fromRaw(42));
    try std.testing.expectEqual(@as(?Value, null), st.find("zzsymneverexisted"));
    try std.testing.expectEqual(@as(usize, 0), st.count());
}

test "SymbolTable.bind: introduces a brand new name for an existing id" {
    tu.freshInterp();
    var st: SymbolTable = .{};
    defer st.deinit(std.testing.allocator);
    const id = try st.createFresh(std.testing.allocator, "zzsymoriginal");
    try st.bind(std.testing.allocator, "zzsymalias", id);
    try std.testing.expectEqual(@as(?Value, id), st.find("zzsymalias"));
    try std.testing.expectEqual(@as(?Value, id), st.find("zzsymoriginal")); // unaffected
}

test "SymbolTable.bind: overwrites an existing name's binding" {
    tu.freshInterp();
    var st: SymbolTable = .{};
    defer st.deinit(std.testing.allocator);
    _ = try st.createFresh(std.testing.allocator, "zzsymtarget");
    try st.bind(std.testing.allocator, "zzsymtarget", Value.fromRaw(777));
    try std.testing.expectEqual(@as(?Value, Value.fromRaw(777)), st.find("zzsymtarget"));
}

test "SymbolTable.bind: name survives even if the caller's buffer is freed" {
    tu.freshInterp();
    var st: SymbolTable = .{};
    defer st.deinit(std.testing.allocator);
    {
        const transient = try std.testing.allocator.dupe(u8, "zzsymtransient");
        defer std.testing.allocator.free(transient);
        try st.bind(std.testing.allocator, transient, Value.fromRaw(55));
    }
    try std.testing.expectEqual(@as(?Value, Value.fromRaw(55)), st.find("zzsymtransient"));
}
