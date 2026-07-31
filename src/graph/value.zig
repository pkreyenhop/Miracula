//! value.zig — the typed object model (Phase 5, docs/GoReady.md §4.3).
//!
//! Step 1: `Comb`, an exhaustive enum of every combinator/named-atom code,
//! generated from `spec/combinators.json` so it can never drift out of
//! lock-step with the numbering `word.zig`'s `S`/`PLUS`/`NIL`/… constants.
//! Later
//! steps in this file build `Value`/`CellRef`/`Kind` on top of it; until then
//! `Comb` has no callers — it exists to be validated against the numbering it
//! must match before anything is migrated onto it.

const std = @import("std");
const combinator = @import("combinator.zig");
const word = @import("word.zig");
const Word = word.Word;

/// Every combinator and named atom (`S`, `PLUS`, …, `False`/`True`/`NIL`/
/// `NILS`/`UNDEF`), numbered `0..140` in the same order as
/// `combinator.cmbnms`'s indices `0..cmbnms.len - 2` — `cmbnms`'s trailing
/// `null` is its own end sentinel, not a combinator, so it isn't a member
/// here. A `Comb`'s numeric value plus `word.CMBASE` is exactly the `Word`
/// value the old code used for that combinator.
pub const Comb = combinator.Comb;

// Tests: Comb: generated enum matches cmbnms's order, count, and word.zig's numbering
test "Comb: generated enum matches cmbnms's order, count, and word.zig's numbering" {
    // 141 named combinators (cmbnms.len - 1 for the trailing null sentinel).
    try std.testing.expectEqual(@as(usize, combinator.cmbnms.len - 1), combinator.count);

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
