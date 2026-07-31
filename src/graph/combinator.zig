//! combinator.zig — the combinator/named-atom code → printed-name table.

const std = @import("std");
const word = @import("word.zig");
const generated = @import("combinator_generated.zig");

/// Combinator (and named-atom) code → printed name, indexed by `code - CMBASE`;
/// the reducer's graph printer uses it to name a combinator atom. Generated from
/// the historical `gencdecs` output. Order is significant — it must stay in
/// lock-step with the code numbering in `word.zig` (`S` = CMBASE+0,
/// `PLUS` = CMBASE+54, …, `NIL` = CMBASE+138). The trailing `null` (slot 141) is
/// the end sentinel; a new combinator is appended before it with a matching
/// `word.zig` constant at the same offset.
///
/// Tests: cmbnms aligns with the combinator codes in word.zig
pub const cmbnms = generated.cmbnms;
pub const Comb = generated.Comb;
pub const count = generated.count;

test "cmbnms aligns with the combinator codes in word.zig" {
    // Spot-check the table's order against the code numbering it mirrors.
    try std.testing.expectEqualStrings("S", std.mem.span(cmbnms[@intCast(word.S - word.CMBASE)].?));
    try std.testing.expectEqualStrings("PLUS", std.mem.span(cmbnms[@intCast(word.PLUS - word.CMBASE)].?));
    try std.testing.expectEqualStrings("True", std.mem.span(cmbnms[@intCast(word.True - word.CMBASE)].?));
    try std.testing.expectEqualStrings("NIL", std.mem.span(cmbnms[@intCast(word.NIL - word.CMBASE)].?));
}
