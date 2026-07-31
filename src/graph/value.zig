//! value.zig — the typed object model (Phase 5, docs/GoReady.md §4.3).
//!
//! Step 1: `Comb`, an exhaustive enum of every combinator/named-atom code,
//! generated at comptime directly from `combinator.cmbnms` so it can never
//! drift out of lock-step with the numbering `word.zig`'s `S`/`PLUS`/`NIL`/…
//! constants (and every reducer dispatch table) already depends on. Later
//! steps in this file build `Value`/`CellRef`/`Kind` on top of it; until then
//! `Comb` has no callers — it exists to be validated against the numbering it
//! must match before anything is migrated onto it.

const std = @import("std");
const combinator = @import("combinator.zig");
const word = @import("word.zig");
const heap_mod = @import("heap.zig");
const big = @import("bignum.zig");
const big_fmt = @import("bignum_fmt.zig");
const Word = word.Word;
const Heap = heap_mod.Heap;

/// Every combinator and named atom (`S`, `PLUS`, …, `False`/`True`/`NIL`/
/// `NILS`/`UNDEF`), numbered `0..140` in the same order as
/// `combinator.cmbnms`'s indices `0..cmbnms.len - 2` — `cmbnms`'s trailing
/// `null` is its own end sentinel, not a combinator, so it isn't a member
/// here. A `Comb`'s numeric value plus `word.CMBASE` is exactly the `Word`
/// value the old code used for that combinator.
pub const Comb: type = blk: {
    @setEvalBranchQuota(10_000);
    const raw_names = combinator.cmbnms;
    var names: [raw_names.len - 1][]const u8 = undefined;
    var values: [raw_names.len - 1]u16 = undefined;
    for (raw_names[0 .. raw_names.len - 1], 0..) |name, i| {
        names[i] = std.mem.span(name.?);
        values[i] = i;
    }
    break :blk @Enum(u16, .exhaustive, &names, &values);
};

// Tests: Comb: generated enum matches cmbnms's order, count, and word.zig's numbering
test "Comb: generated enum matches cmbnms's order, count, and word.zig's numbering" {
    // 141 named combinators (cmbnms.len - 1 for the trailing null sentinel).
    try std.testing.expectEqual(@as(usize, combinator.cmbnms.len - 1), @typeInfo(Comb).@"enum".fields.len);

    // Spot-check across the numbering: first, a mid-table entry, and the
    // trailing four non-combinator named atoms the plan calls out by name.
    try std.testing.expectEqual(@as(u16, 0), @intFromEnum(Comb.S));
    try std.testing.expectEqual(@as(Word, word.S), word.CMBASE + @intFromEnum(Comb.S));
    try std.testing.expectEqual(@as(Word, word.PLUS), word.CMBASE + @intFromEnum(Comb.PLUS));
    try std.testing.expectEqual(@as(Word, word.False), word.CMBASE + @intFromEnum(Comb.False));
    try std.testing.expectEqual(@as(Word, word.True), word.CMBASE + @intFromEnum(Comb.True));
    try std.testing.expectEqual(@as(Word, word.NIL), word.CMBASE + @intFromEnum(Comb.NIL));
    try std.testing.expectEqual(@as(Word, word.NILS), word.CMBASE + @intFromEnum(Comb.NILS));
    try std.testing.expectEqual(@as(Word, word.UNDEF), word.CMBASE + @intFromEnum(Comb.UNDEF));

    // The last member is UNDEF, one below ATOMLIMIT (word.zig's own comment:
    // "ATOMLIMIT = CMBASE + 141", and UNDEF = CMBASE + 140).
    try std.testing.expectEqual(@as(Word, word.ATOMLIMIT - 1), word.CMBASE + @intFromEnum(Comb.UNDEF));
}

/// A heap-cell handle — the typed replacement for a `Word >= ATOMLIMIT`.
/// `enum(u32)` rather than a bare integer so it "cannot be confused with a
/// count" (§4.3): a cell count and a cell reference are both small positive
/// numbers, and mixing them up silently is exactly the kind of bug a distinct
/// type exists to rule out at compile time. The numeric value is the raw
/// heap-array index unchanged (`Heap.h`/`.t`/`.getTag` already subscript
/// their column arrays with the cell's `Word` directly), so `of`/`toWord` are
/// free — no offset, no arithmetic, just a reinterpretation of the same bits.
pub const CellRef = enum(u32) {
    _,

    /// Wrap a raw cell-index `Word` (`>= ATOMLIMIT`) as a `CellRef`.
    pub inline fn of(x: Word) CellRef {
        std.debug.assert(x >= word.ATOMLIMIT);
        return @enumFromInt(@as(u32, @intCast(x)));
    }

    /// The raw `Word` this `CellRef` denotes (`@intFromEnum`, widened back to `Word`).
    pub inline fn toWord(self: CellRef) Word {
        return @intFromEnum(self);
    }
};

test "CellRef.of / .toWord: round-trip a cell-index Word through the handle enum" {
    const r = CellRef.of(word.ATOMLIMIT + 1000);
    try std.testing.expectEqual(@as(Word, word.ATOMLIMIT + 1000), r.toWord());
}

/// The role of a `Value`, recovered from its bits — the `Comb`/`CellRef`-typed
/// successor to `word.classify`'s `Value{ .imm / .atom / .ref }`. Only two of
/// the three roles change name (`.atom` → `.comb`, `.ref` → `.cell`): after
/// Phase 1 the lexer/parser token codes (257..305) never appear in a live
/// reduced graph (they're consumed entirely during parsing), so every atom a
/// runtime `Value` actually holds is a `Comb` member — combinators and the
/// three named atoms `NIL`/`NILS`/`UNDEF` alike.
///
/// `.imm` is deliberately still a bare `u8`, not split into `char`/`small`
/// variants: a bare `0..255` `Value` is a Latin-1 char *or* a small int/index,
/// and nothing in the bits themselves says which — Miranda's static type
/// system picks the interpretation, the same ambiguity `word.classify`'s own
/// doc comment already calls out. A full `char` reader that also covers
/// non-Latin-1 code points needs the *cell's* tag (`UNICODE` vs bare), which
/// means dereferencing the heap — that belongs to the typed heap accessors
/// (step 3/4 of this phase), not to this file's raw, heap-independent `Kind`.
pub const Kind = union(enum) {
    imm: u8,
    comb: Comb,
    cell: CellRef,
};

/// The interpreter's tagged graph value, retyped from a bare `Word` (§4.3).
/// `packed struct(u64)` over a single `raw: i64` field is bit-for-bit
/// identical to the `Word` it replaces — same size, same layout, so `.x`
/// dump files and the reducer's hot-path bit tricks are untouched; only the
/// *type* changes, from "any `i64`" to "a `Value`, read through `kind()`".
///
/// `fromRaw`/`toRaw` are the escape hatch for this migration window (§4.3
/// step 2): call sites not yet converted keep passing bare `Word`s through
/// `fromRaw` on the way in and `toRaw` on the way out. The `toRaw` count
/// across the codebase is this phase's ratchet metric — it should fall
/// toward zero as steps 3/4 convert the heap API and its callers, leaving
/// `Word` alive only inside `dump.zig`'s wire format.
pub const Value = packed struct(u64) {
    raw: i64,

    /// Wrap a raw `Word` as a `Value` — the migration-window escape hatch.
    pub inline fn fromRaw(x: Word) Value {
        return .{ .raw = x };
    }

    /// The raw `Word` this `Value` denotes — the migration-window escape hatch.
    pub inline fn toRaw(self: Value) Word {
        return self.raw;
    }

    /// A bare Latin-1 char or small int/index (`0..255`).
    pub inline fn imm(x: u8) Value {
        return .{ .raw = x };
    }

    /// A combinator or named atom (`S`, `PLUS`, …, `NIL`, `NILS`, `UNDEF`).
    pub inline fn comb(c: Comb) Value {
        return .{ .raw = word.CMBASE + @as(Word, @intFromEnum(c)) };
    }

    /// A heap-cell handle.
    pub inline fn cell(r: CellRef) Value {
        return .{ .raw = r.toWord() };
    }

    /// Recover this `Value`'s role — see `Kind`'s doc comment for why `.imm`
    /// stays a single ambiguous `u8` rather than a separate `char`/`small`.
    pub inline fn kind(self: Value) Kind {
        if (self.raw >= word.ATOMLIMIT) return .{ .cell = CellRef.of(self.raw) };
        if (word.isLatin1Char(self.raw)) return .{ .imm = @intCast(self.raw) };
        return .{ .comb = @enumFromInt(@as(u16, @intCast(self.raw - word.CMBASE))) };
    }
};

test "Value: fromRaw/toRaw round-trip and kind() matches word.classify's roles" {
    // Immediates (0..255): chars / small-ints / indices.
    try std.testing.expectEqual(Kind{ .imm = 0 }, Value.fromRaw(0).kind());
    try std.testing.expectEqual(Kind{ .imm = 65 }, Value.fromRaw(65).kind());
    try std.testing.expectEqual(Kind{ .imm = 255 }, Value.fromRaw(255).kind());
    try std.testing.expectEqual(@as(Value, Value.imm(65)), Value.fromRaw(65));

    // Combinators and named atoms.
    try std.testing.expectEqual(Kind{ .comb = .S }, Value.fromRaw(word.S).kind());
    try std.testing.expectEqual(Kind{ .comb = .PLUS }, Value.fromRaw(word.PLUS).kind());
    try std.testing.expectEqual(Kind{ .comb = .NIL }, Value.fromRaw(word.NIL).kind());
    try std.testing.expectEqual(Kind{ .comb = .UNDEF }, Value.fromRaw(word.UNDEF).kind());
    try std.testing.expectEqual(@as(Value, Value.comb(.PLUS)), Value.fromRaw(word.PLUS));

    // Heap-cell handles.
    const cr = CellRef.of(word.ATOMLIMIT + 1000);
    try std.testing.expectEqual(Kind{ .cell = cr }, Value.fromRaw(word.ATOMLIMIT + 1000).kind());
    try std.testing.expectEqual(@as(Value, Value.cell(cr)), Value.fromRaw(word.ATOMLIMIT + 1000));

    // toRaw is the exact inverse of fromRaw for every role above.
    try std.testing.expectEqual(@as(Word, 65), Value.fromRaw(65).toRaw());
    try std.testing.expectEqual(@as(Word, word.PLUS), Value.fromRaw(word.PLUS).toRaw());
    try std.testing.expectEqual(@as(Word, word.ATOMLIMIT + 1000), Value.fromRaw(word.ATOMLIMIT + 1000).toRaw());
}

// ── Step 3: typed heap-graph accessors ──────────────────────────────────────
//
// The `Value`-typed successors of `Heap.h`/`.t`/`.cons`/`.make`/`.getTag`/
// `.setTag` and `eval/reduce_core.zig`'s `ap`. These *coexist* with the
// existing `Word`-typed methods for the length of this phase — exactly like
// Phase 1's native `syntax/` pipeline coexisted with the legacy lexer until
// its own final deletion step (docs/GoReady.md, "no parallel
// half-migrations" only means a shim must be gone by the *end* of the phase
// that introduced it, not immediately). Callers migrate onto these one
// subsystem at a time (step 4); `Heap.h`/`.t`/`.cons`/`.make` themselves are
// only renamed/removed once nothing references the `Word` form anymore.
//
// `apOf` is defined here rather than imported from `eval/reduce_core.zig`'s
// `ap` to keep `graph/` a leaf layer (docs/GoReady.md §4.1: `graph`
// may import nothing outside itself) — `ap` is just `make(.AP, x, y)`, so
// there's nothing in `eval/` this actually needs.

/// Head of a cons cell, typed.
pub inline fn hOf(heap_ptr: *Heap, x: Value) Value {
    return Value.fromRaw(heap_ptr.h(x.toRaw()));
}

/// Tail of a cons cell, typed.
pub inline fn tOf(heap_ptr: *Heap, x: Value) Value {
    return Value.fromRaw(heap_ptr.t(x.toRaw()));
}

/// Allocate a tagged cell, typed.
pub inline fn makeOf(heap_ptr: *Heap, tag: word.NodeTag, x: Value, y: Value) Value {
    return Value.fromRaw(heap_ptr.make(tag, x.toRaw(), y.toRaw()));
}

/// Allocate a `CONS` cell `(x . y)`, typed.
pub inline fn consOf(heap_ptr: *Heap, x: Value, y: Value) Value {
    return Value.fromRaw(heap_ptr.cons(x.toRaw(), y.toRaw()));
}

/// Allocate an application cell `(x y)`, typed.
pub inline fn apOf(heap_ptr: *Heap, x: Value, y: Value) Value {
    return makeOf(heap_ptr, .AP, x, y);
}

/// The node tag of a cell, typed.
pub inline fn tagOf(heap_ptr: *Heap, x: Value) word.NodeTag {
    return heap_ptr.getTag(x.toRaw());
}

/// Set the node tag of a cell, typed.
pub inline fn setTagOf(heap_ptr: *Heap, x: Value, tag: word.NodeTag) void {
    heap_ptr.setTag(x.toRaw(), tag);
}

test "typed heap-graph accessors: consOf/makeOf/apOf build cells that hOf/tOf/tagOf read back" {
    const tu = @import("../testutil.zig");
    tu.freshInterp();
    const heap_ptr = heap_mod.heap();

    // consOf: a CONS cell, read back through hOf/tOf/tagOf.
    const true_val = Value.comb(.True);
    const nil_val = Value.comb(.NIL);
    const cell_val = consOf(heap_ptr, true_val, nil_val);
    try std.testing.expectEqual(word.NodeTag.CONS, tagOf(heap_ptr, cell_val));
    try std.testing.expectEqual(true_val, hOf(heap_ptr, cell_val));
    try std.testing.expectEqual(nil_val, tOf(heap_ptr, cell_val));

    // apOf: an AP cell with the same head/tail.
    const a = apOf(heap_ptr, true_val, nil_val);
    try std.testing.expectEqual(word.NodeTag.AP, tagOf(heap_ptr, a));
    try std.testing.expectEqual(true_val, hOf(heap_ptr, a));
    try std.testing.expectEqual(nil_val, tOf(heap_ptr, a));

    // makeOf + setTagOf: build a PAIR cell, then retag it to LABEL in place.
    const p = makeOf(heap_ptr, .PAIR, Value.imm(1), Value.imm(2));
    try std.testing.expectEqual(word.NodeTag.PAIR, tagOf(heap_ptr, p));
    setTagOf(heap_ptr, p, .LABEL);
    try std.testing.expectEqual(word.NodeTag.LABEL, tagOf(heap_ptr, p));
    try std.testing.expectEqual(Value.imm(1), hOf(heap_ptr, p));
    try std.testing.expectEqual(Value.imm(2), tOf(heap_ptr, p));

    // These agree exactly with the existing Word-typed API on the same cells
    // (the whole point of "coexist, don't diverge" during the migration).
    try std.testing.expectEqual(heap_ptr.h(cell_val.toRaw()), hOf(heap_ptr, cell_val).toRaw());
    try std.testing.expectEqual(heap_ptr.t(cell_val.toRaw()), tOf(heap_ptr, cell_val).toRaw());
    try std.testing.expectEqual(heap_ptr.getTag(cell_val.toRaw()), tagOf(heap_ptr, cell_val));
}

// ── Step 3b: typed payload accessors ────────────────────────────────────────
//
// `intVal`/`dblVal` (and their `Value`-constructing counterparts) are the
// typed readers for the two numeric cell payloads named in §4.3. Both wrap
// existing, already-correct, already-tested functions unchanged
// (`bignum.zig`'s `toInt`/`fromInt`, `heap.zig`'s `getDbl`/`stoDbl`/`setdbl`)
// rather than reimplementing their bit tricks — `stoDbl`/`setdbl`'s `fpdatum`
// extern-union split is exactly the kind of GC-adjacent bit-level code this
// project's own working notes flag as fragile, and it isn't touched here;
// retiring it for a plain `@bitCast` (as §4.3 suggests, since `Word` is
// unconditionally 8 bytes now — the union's 4-byte-`Word` branch is dead)
// is a real simplification, but a separate, focused edit for whenever a
// caller actually migrates onto `dblVal`/`dblOf` (step 4), not bundled here.

/// The integer stored in an `INT`-tagged (arbitrary-precision bignum) `Value`.
/// `i64`, not the wider C-style return type `bignum.toInt` itself still
/// uses — matching this file's other signatures and not introducing a new
/// C-style integer type at this API (the scorecard tracks those toward zero
/// outside `os.zig`; the cast at this one boundary is free, since both
/// representations are 64-bit on every real target).
pub inline fn intVal(heap_ptr: *Heap, v: Value) i64 {
    return @intCast(big.toInt(heap_ptr, v.toRaw()));
}

/// Box the integer `n` as a fresh `INT`-tagged `Value` (always boxed —
/// Miranda's integers are arbitrary-precision, so there's no bare-immediate
/// small-int representation the way there is for chars).
pub inline fn intOf(heap_ptr: *Heap, n: i64) Value {
    return Value.fromRaw(big.fromInt(heap_ptr, n));
}

/// The `f64` stored in a `DOUBLE`-tagged `Value`.
pub inline fn dblVal(v: Value) f64 {
    return heap_mod.getDbl(v.toRaw());
}

/// Box `r` as a fresh `DOUBLE`-tagged `Value`.
pub inline fn dblOf(r: f64) word.ReduceError!Value {
    return Value.fromRaw(try heap_mod.stoDbl(r));
}

/// Overwrite the `f64` stored in an existing `DOUBLE`-tagged `Value` in place.
pub inline fn setDblOf(v: Value, r: f64) word.ReduceError!void {
    try heap_mod.setdbl(v.toRaw(), r);
}

test "intVal/intOf and dblVal/dblOf/setDblOf: typed numeric payload accessors" {
    const tu = @import("../testutil.zig");
    tu.freshInterp();
    const heap_ptr = heap_mod.heap();

    // Every integer boxes as an INT (bignum digit-chain) cell — Miranda's
    // integers are arbitrary-precision, so there's no bare-immediate
    // small-int shortcut here (unlike chars, which do have one; see
    // Value.imm/Kind's doc comment). intVal reads the same integer back out
    // regardless of magnitude.
    const small = intOf(heap_ptr, 42);
    try std.testing.expectEqual(word.NodeTag.INT, tagOf(heap_ptr, small));
    try std.testing.expectEqual(@as(i64, 42), intVal(heap_ptr, small));

    const big_int = intOf(heap_ptr, 1_000_000);
    try std.testing.expectEqual(word.NodeTag.INT, tagOf(heap_ptr, big_int));
    try std.testing.expectEqual(@as(i64, 1_000_000), intVal(heap_ptr, big_int));

    // DOUBLE cells: construct, read, then overwrite in place.
    const d = try dblOf(3.14);
    try std.testing.expectEqual(word.NodeTag.DOUBLE, tagOf(heap_ptr, d));
    try std.testing.expectEqual(@as(f64, 3.14), dblVal(d));
    try setDblOf(d, -2.5);
    try std.testing.expectEqual(@as(f64, -2.5), dblVal(d));

    // Non-finite results are rejected, matching the wrapped functions' own
    // FloatOverflow contract.
    try std.testing.expectError(error.FloatOverflow, dblOf(std.math.inf(f64)));
}

// `asFileNode`/`fileNodeOf` and `asIdentifier`/`identifierOf` bridge `Value`
// to the *existing* `Heap.FileNode`/`Heap.Identifier` domain wrappers — the
// "fileInfo"/"idInfo" typed payload accessors §4.3 names. Those wrappers
// already existed before this phase (heap.zig's "Domain types (C2)" seam,
// each a single-field struct carrying semantic intent over a raw `Word`), so
// there is no new accessor logic to write here, only a `Value`-typed way in
// and out for callers migrating onto `Value` who need to reach them.
pub inline fn asFileNode(v: Value) heap_mod.FileNode {
    return .{ .word = v.toRaw() };
}

pub inline fn fileNodeOf(n: heap_mod.FileNode) Value {
    return Value.fromRaw(n.word);
}

pub inline fn asIdentifier(v: Value) heap_mod.Identifier {
    return .{ .word = v.toRaw() };
}

pub inline fn identifierOf(id: heap_mod.Identifier) Value {
    return Value.fromRaw(id.word);
}

test "asFileNode/fileNodeOf and asIdentifier/identifierOf: bridge to the existing domain wrappers" {
    const w: Word = 42;
    try std.testing.expectEqual(w, asFileNode(Value.fromRaw(w)).word);
    try std.testing.expectEqual(@as(Value, Value.fromRaw(w)), fileNodeOf(.{ .word = w }));
    try std.testing.expectEqual(w, asIdentifier(Value.fromRaw(w)).word);
    try std.testing.expectEqual(@as(Value, Value.fromRaw(w)), identifierOf(.{ .word = w }));
}

// `strId` (a string-table index, stored *negated* in a `Word` — see
// `strtab.zig`'s own file header) is deliberately **not** given a `Value`
// integration. It never appears as a general reducer `Value`: it lives only
// in specific known payload slots of specific cell kinds (a `CONS.hd` in
// `exportfiles`, a `CONSTRUCTOR.tl`, an `ID`/`STRCONS` cell's string field),
// each already read by a typed accessor that knows the cell's tag going in.
// `Value.kind()` explicitly documents that negative `Word`s (marked spine
// words, sentinels) are "not values — mask them off first"; forcing a
// `strid` branch into `Kind`'s general classification would blur that
// boundary for no real gain. `strtab.zig`'s own `strBits`/`strOf` are
// already the right typed accessors for this payload and are untouched.

// ── Step 4 (bignum): typed wrappers over the arbitrary-precision arithmetic ─
//
// `bignum.zig`'s own functions stay `Word`-in/`Word`-out — that file's
// digit-chain implementation (`digitPtr`/`restPtr`, raw `*Word` cell
// mutation, carry/borrow logic) is exactly the kind of delicate, bit-level
// code this project is careful not to touch as a drive-by in a type-
// migration pass (matching the same caution `dblVal`'s doc comment already
// applies to `heap.zig`'s `fpdatum` trick). These wrappers are the `Value`
// in/out boundary callers use instead — the same pattern as `intVal`/
// `intOf` above (which already wrap `bignum.toInt`/`.fromInt`), extended to
// the rest of `bignum.zig`'s public API.

/// True when boxed integer `x` is non-negative.
pub inline fn isNatVal(heap_ptr: *Heap, x: Value) bool {
    return big.isNat(heap_ptr, x.toRaw());
}

/// `-x` for boxed integer `x`.
pub inline fn negateVal(heap_ptr: *Heap, x: Value) Value {
    return Value.fromRaw(big.negate(heap_ptr, x.toRaw()));
}

/// `x + y` for boxed integers.
pub inline fn addVal(heap_ptr: *Heap, x: Value, y: Value) Value {
    return Value.fromRaw(big.add(heap_ptr, x.toRaw(), y.toRaw()));
}

/// `x - y` for boxed integers.
pub inline fn subVal(heap_ptr: *Heap, x: Value, y: Value) Value {
    return Value.fromRaw(big.sub(heap_ptr, x.toRaw(), y.toRaw()));
}

/// Three-way comparison of boxed integers `x`/`y` (negative/zero/positive).
pub inline fn cmpVal(heap_ptr: *Heap, x: Value, y: Value) i32 {
    return big.cmp(heap_ptr, x.toRaw(), y.toRaw());
}

/// `x * y` for boxed integers.
pub inline fn mulVal(heap_ptr: *Heap, x: Value, y: Value) Value {
    return Value.fromRaw(big.mul(heap_ptr, x.toRaw(), y.toRaw()));
}

/// `x div y` (integer division) for boxed integers.
pub inline fn divVal(heap_ptr: *Heap, self: *big.Bignum, x: Value, y: Value) Value {
    return Value.fromRaw(big.div(heap_ptr, self, x.toRaw(), y.toRaw()));
}

/// `x mod y` (remainder) for boxed integers.
pub inline fn modVal(heap_ptr: *Heap, self: *big.Bignum, x: Value, y: Value) Value {
    return Value.fromRaw(big.mod(heap_ptr, self, x.toRaw(), y.toRaw()));
}

/// `x ^ y` (integer exponentiation) for boxed integers.
pub inline fn powVal(heap_ptr: *Heap, x: Value, y: Value) Value {
    return Value.fromRaw(big.pow(heap_ptr, x.toRaw(), y.toRaw()));
}

/// Boxed integer `x` as an `f64`.
pub inline fn toFloatVal(heap_ptr: *Heap, x: Value) f64 {
    return big.toFloat(heap_ptr, x.toRaw());
}

/// Box `f64` `r` as an arbitrary-precision integer (truncating).
pub inline fn fromFloatVal(heap_ptr: *Heap, r: f64) Value {
    return Value.fromRaw(big.fromFloat(heap_ptr, r));
}

/// Natural log of boxed integer `x`.
pub inline fn lnVal(heap_ptr: *Heap, self: *big.Bignum, x: Value) f64 {
    return big.ln(heap_ptr, self, x.toRaw());
}

/// Base-10 log of boxed integer `x`.
pub inline fn log10Val(heap_ptr: *Heap, self: *big.Bignum, x: Value) f64 {
    return big.log10(heap_ptr, self, x.toRaw());
}

/// Parse a Miranda char-list `x` (in the given `base`) as a boxed integer.
pub inline fn parseStringVal(heap_ptr: *Heap, x: Value, base: i32) Value {
    return Value.fromRaw(big_fmt.parseString(heap_ptr, x.toRaw(), base));
}

/// Boxed integer `x` as a Miranda char-list of decimal digits.
pub inline fn toDecimalListVal(heap_ptr: *Heap, x: Value) Value {
    return Value.fromRaw(big_fmt.toDecimalList(heap_ptr, x.toRaw()));
}

/// Boxed integer `x` as a Miranda char-list of hex digits.
pub inline fn toHexListVal(heap_ptr: *Heap, x: Value) Value {
    return Value.fromRaw(big_fmt.toHexList(heap_ptr, x.toRaw()));
}

/// Boxed integer `x` as a Miranda char-list of octal digits.
pub inline fn toOctalListVal(heap_ptr: *Heap, x: Value) Value {
    return Value.fromRaw(big_fmt.toOctalList(heap_ptr, x.toRaw()));
}

test "bignum Value wrappers: typed in/out over bignum.zig's unchanged Word API" {
    const tu = @import("../testutil.zig");
    tu.freshInterp();
    const heap_ptr = heap_mod.heap();

    const a = intOf(heap_ptr, 6);
    const b = intOf(heap_ptr, 7);
    try std.testing.expect(isNatVal(heap_ptr, a));
    try std.testing.expectEqual(@as(i64, 42), intVal(heap_ptr, mulVal(heap_ptr, a, b)));
    try std.testing.expectEqual(@as(i64, 13), intVal(heap_ptr, addVal(heap_ptr, a, b)));
    try std.testing.expectEqual(@as(i64, -1), intVal(heap_ptr, subVal(heap_ptr, a, b)));
    try std.testing.expectEqual(@as(i64, -6), intVal(heap_ptr, negateVal(heap_ptr, a)));
    try std.testing.expect(cmpVal(heap_ptr, a, b) < 0);
    try std.testing.expectEqual(@as(f64, 6.0), toFloatVal(heap_ptr, a));
    try std.testing.expectEqual(@as(i64, 6), intVal(heap_ptr, fromFloatVal(heap_ptr, 6.9)));

    const bn = big.bn();
    const q = divVal(heap_ptr, bn, intOf(heap_ptr, 20), intOf(heap_ptr, 6));
    try std.testing.expectEqual(@as(i64, 3), intVal(heap_ptr, q));
    const r = modVal(heap_ptr, bn, intOf(heap_ptr, 20), intOf(heap_ptr, 6));
    try std.testing.expectEqual(@as(i64, 2), intVal(heap_ptr, r));
    try std.testing.expectEqual(@as(i64, 64), intVal(heap_ptr, powVal(heap_ptr, intOf(heap_ptr, 2), intOf(heap_ptr, 6))));
}
