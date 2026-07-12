//! value.zig — the typed object model (Phase 5, docs/ZIG_NATIVE_PLAN.md §4.3).
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
    const word = @import("word.zig");

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

const Word = @import("word.zig").Word;
