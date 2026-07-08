//! print.zig (split from runtime/heap.zig, Phase 4 step 3,
//! docs/ZIG_NATIVE_PLAN.md) — term/type printing: `outTerm`/`outSubterm`/
//! `outAtom` (readable dumps of a graph value, used for debug output and
//! error messages) and `charname`/`outReal` (the char-escape and
//! double-formatting helpers they call).

const std = @import("std");
const word = @import("word.zig");
const strtab = @import("strtab.zig");
const combinator = @import("combinator.zig");
const big = @import("bignum.zig");
const setup = @import("../compiler/setup.zig");
const heap_mod = @import("heap.zig");
const Heap = heap_mod.Heap;
const tu = @import("../testutil.zig"); // unit-test harness (test builds only)

const Word = i64;

const heap = heap_mod.heap;
const h = heap_mod.h;
const t = heap_mod.t;
const getTag = heap_mod.getTag;
const getDbl = heap_mod.getDbl;
const getId = heap_mod.getId;
const rest = heap_mod.rest;
const getsmallint = heap_mod.getsmallint;
const dlhs = heap_mod.dlhs;
const dval = heap_mod.dval;
const TOP = heap_mod.TOP;
const bigtostr = big.toDecimalList;

/// A printable name/escape for char `ch`.
///
/// Tests: charname: escapes control chars, passes printables through
pub fn charname(ch: Word) [*:0]const u8 {
    return switch (ch) {
        '\n' => "\\n",
        '\t' => "\\t",
        '\x08' => "\\b",
        '\x0c' => "\\f",
        '\r' => "\\r",
        '\\' => "\\\\",
        '\'' => "\\'",
        '"' => "\\\"",
        else => blk: {
            if (ch < 32 or ch > 126) {
                const text = std.fmt.bufPrintSentinel(&heap().charname_buffer, "\\{d}", .{ch}, 0) catch unreachable;
                break :blk text.ptr;
            }
            heap().charname_buffer[0] = @intCast(ch);
            heap().charname_buffer[1] = 0;
            break :blk @as([*:0]const u8, @ptrCast(heap().charname_buffer[0..].ptr));
        },
    };
}

test "charname: escapes control chars, passes printables through" {
    tu.freshInterp();
    try std.testing.expectEqualStrings("\\n", std.mem.span(charname('\n')));
    try std.testing.expectEqualStrings("\\t", std.mem.span(charname('\t')));
    try std.testing.expectEqualStrings("\\\\", std.mem.span(charname('\\')));
    try std.testing.expectEqualStrings("A", std.mem.span(charname('A')));
    try std.testing.expectEqualStrings("\\7", std.mem.span(charname(7))); // bell → \7
}

/// Print double `value` to `file`.
pub fn outReal(file: ?*word.Stream, value: f64) void {
    const magnitude = if (value < 0) -value else value;
    if (magnitude >= 1000.0 or magnitude <= 0.001) {
        _ = word.fprint(file, "{d}", .{value});
    } else {
        _ = word.fprint(file, "{d}", .{value});
    }
}

/// The interned name text for a private-name payload `val`.
pub fn castPtr(val: Word) [*:0]const u8 {
    return strtab.strOf(strtab.table(), val);
}

/// Print cell `x` to `file` in readable form (debug/diagnostic dump).
pub fn outTerm(file: ?*word.Stream, x_val: Word) void {
    var x = x_val;
    if (x < 0 or x > TOP()) {
        _ = word.fprint(file, "<{d}>", .{x});
        return;
    }
    if (getTag(x) == .LAMBDA) {
        _ = word.fprint(file, "$(", .{.{}});
        outTerm(file, h(x));
        _ = word.putc(')', file);
        outTerm(file, t(x));
    } else {
        while (getTag(x) == .CONS) {
            outSubterm(file, h(x));
            _ = word.putc(':', file);
            x = t(x);
        }
        outSubterm(file, x);
    }
}

/// Helper for `outTerm`: print one sub-term.
pub fn outSubterm(file: ?*word.Stream, x: Word) void {
    if (x < 0 or x > TOP()) {
        _ = word.fprint(file, "<{d}>", .{x});
        return;
    }
    if (getTag(x) == .AP) {
        outSubterm(file, h(x));
        _ = word.putc(' ', file);
        outAtom(file, t(x));
    } else {
        outAtom(file, x);
    }
}

/// Helper for `outTerm`: print one sub-term.
pub fn outAtom(file: ?*word.Stream, x_val: Word) void {
    var x = x_val;
    if (x < 0 or x > TOP()) {
        _ = word.fprint(file, "<{d}>", .{x});
        return;
    }
    const tag_val = getTag(x);
    if (tag_val == .INT) {
        if (rest(x) != 0) {
            x = bigtostr(heap(), x);
            while (x != 0) {
                _ = word.putc(@intCast(h(x)), file);
                x = t(x);
            }
        } else {
            _ = word.fprint(file, "{d}", .{getsmallint(x)});
        }
        return;
    }
    if (tag_val == .DOUBLE) {
        outReal(file, getDbl(x));
        return;
    }
    if (tag_val == .ID) {
        _ = word.fprint(file, "{s}", .{getId(x)});
        return;
    }
    if (word.fitsInByte(x)) {
        _ = word.fprint(file, "'{s}'", .{charname(x)});
        return;
    }
    if (tag_val == .UNICODE) {
        _ = word.fprint(file, "'{x}'", .{h(x)});
        return;
    }
    if (tag_val == .ATOM) {
        const str: [*:0]const u8 = if (x < word.CMBASE)
            @ptrCast(setup.yysterm[@intCast(x - 256)])
        else if (x == word.True)
            "True"
        else if (x == word.False)
            "False"
        else if (x == word.NIL)
            "[]"
        else if (x == word.NILS)
            "\"\""
        else
            @ptrCast(combinator.cmbnms[@intCast(x - word.CMBASE)]);
        _ = word.fprint(file, "{s}", .{str});
        return;
    }
    if (tag_val == .TCONS or tag_val == .PAIR) {
        _ = word.fprint(file, "(", .{.{}});
        while (getTag(x) == .TCONS) {
            outTerm(file, h(x));
            _ = word.putc(',', file);
            x = t(x);
        }
        outTerm(file, h(x));
        _ = word.putc(',', file);
        outTerm(file, t(x));
        _ = word.putc(')', file);
        return;
    }
    if (tag_val == .TRIES) {
        _ = word.fprint(file, "TRIES(", .{.{}});
        outTerm(file, h(x));
        _ = word.putc(',', file);
        outTerm(file, t(x));
        _ = word.putc(')', file);
        return;
    }
    if (tag_val == .LABEL) {
        _ = word.fprint(file, "LABEL(", .{.{}});
        outTerm(file, h(x));
        _ = word.putc(',', file);
        outTerm(file, t(x));
        _ = word.putc(')', file);
        return;
    }
    if (tag_val == .SHOW) {
        _ = word.fprint(file, "SHOW(", .{.{}});
        outTerm(file, h(x));
        _ = word.putc(',', file);
        outTerm(file, t(x));
        _ = word.putc(')', file);
        return;
    }
    if (tag_val == .STARTREADVALS) {
        _ = word.fprint(file, "READVALS(", .{.{}});
        outTerm(file, h(x));
        _ = word.putc(',', file);
        outTerm(file, t(x));
        _ = word.putc(')', file);
        return;
    }
    if (tag_val == .LET) {
        _ = word.fprint(file, "(LET ", .{.{}});
        outTerm(file, dlhs(h(x)));
        _ = word.fprint(file, "=", .{.{}});
        outTerm(file, dval(h(x)));
        _ = word.fprint(file, ";IN ", .{.{}});
        outTerm(file, t(x));
        _ = word.fprint(file, ")", .{.{}});
        return;
    }
    if (tag_val == .LETREC) {
        const body = t(x);
        _ = word.fprint(file, "(LETREC ", .{.{}});
        x = h(x);
        while (x != word.NIL) {
            outTerm(file, dlhs(h(x)));
            _ = word.fprint(file, "=", .{.{}});
            outTerm(file, dval(h(x)));
            _ = word.fprint(file, ";", .{.{}});
            x = t(x);
        }
        _ = word.fprint(file, "IN ", .{.{}});
        outTerm(file, body);
        _ = word.fprint(file, ")", .{.{}});
        return;
    }
    if (tag_val == .DATAPAIR) {
        _ = word.fprint(file, "DATAPAIR({s},{d})", .{ castPtr(h(x)), t(x) });
        return;
    }
    if (tag_val == .FILEINFO) {
        _ = word.fprint(file, "FILEINFO({s},{d})", .{ castPtr(h(x)), t(x) });
        return;
    }
    if (tag_val == .CONSTRUCTOR) {
        _ = word.fprint(file, "CONSTRUCTOR({d})", .{h(x)});
        return;
    }
    if (tag_val == .STRCONS) {
        _ = word.fprint(file, "<${d}>", .{h(x)});
        return;
    }
    if (tag_val == .SHARE) {
        _ = word.fprint(file, "(SHARE:", .{.{}});
        outTerm(file, h(x));
        _ = word.fprint(file, ")", .{.{}});
        return;
    }
    if (tag_val != .CONS and tag_val != .AP and tag_val != .LAMBDA) {
        _ = word.fprint(file, "<{d}|tag={d}>", .{ x, @intFromEnum(tag_val) });
        return;
    }
    _ = word.putc(')', file);
}
