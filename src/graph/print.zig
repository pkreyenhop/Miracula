//! print.zig (split from runtime/heap.zig, Phase 4 step 3,
//! docs/GoReady.md) — term/type printing: `outTerm`/`outSubterm`/
//! `outAtom` (readable dumps of a graph value, used for debug output and
//! error messages) and `charname`/`outReal` (the char-escape and
//! double-formatting helpers they call).

const std = @import("std");
const word = @import("word.zig");
const strtab = @import("strtab.zig");
const combinator = @import("combinator.zig");
const big = @import("bignum.zig");
const big_fmt = @import("bignum_fmt.zig");
const setup = @import("../compiler/setup.zig");
const heap_mod = @import("heap.zig");
const Heap = heap_mod.Heap;
const tu = @import("../testutil.zig"); // unit-test harness (test builds only)

const Word = i64;

const getDbl = heap_mod.getDbl;
const getId = heap_mod.getId;
const rest = heap_mod.rest;
const getsmallint = heap_mod.getsmallint;
const bigtostr = big_fmt.toDecimalList;

/// A printable name/escape for char `ch`.
///
/// Tests: charname: escapes control chars, passes printables through
pub fn charname(heap: *Heap, ch: Word) [*:0]const u8 {
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
                const text = std.fmt.bufPrintSentinel(&heap.charname_buffer, "\\{d}", .{ch}, 0) catch unreachable;
                break :blk text.ptr;
            }
            heap.charname_buffer[0] = @intCast(ch);
            heap.charname_buffer[1] = 0;
            break :blk @as([*:0]const u8, @ptrCast(heap.charname_buffer[0..].ptr));
        },
    };
}

test "charname: escapes control chars, passes printables through" {
    tu.freshInterp();
    try std.testing.expectEqualStrings("\\n", std.mem.span(charname(heap_mod.heap(), '\n')));
    try std.testing.expectEqualStrings("\\t", std.mem.span(charname(heap_mod.heap(), '\t')));
    try std.testing.expectEqualStrings("\\\\", std.mem.span(charname(heap_mod.heap(), '\\')));
    try std.testing.expectEqualStrings("A", std.mem.span(charname(heap_mod.heap(), 'A')));
    try std.testing.expectEqualStrings("\\7", std.mem.span(charname(heap_mod.heap(), 7))); // bell → \7
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
pub fn outTerm(heap: *Heap, file: ?*word.Stream, x_val: Word) void {
    var x = x_val;
    if (x < 0 or x > heap.TOP()) {
        _ = word.fprint(file, "<{d}>", .{x});
        return;
    }
    if (heap.getTag(x) == .LAMBDA) {
        _ = word.fprint(file, "$(", .{.{}});
        outTerm(heap, file, heap.h(x));
        _ = word.putc(')', file);
        outTerm(heap, file, heap.t(x));
    } else {
        while (heap.getTag(x) == .CONS) {
            outSubterm(heap, file, heap.h(x));
            _ = word.putc(':', file);
            x = heap.t(x);
        }
        outSubterm(heap, file, x);
    }
}

/// Helper for `outTerm`: print one sub-term.
pub fn outSubterm(heap: *Heap, file: ?*word.Stream, x: Word) void {
    if (x < 0 or x > heap.TOP()) {
        _ = word.fprint(file, "<{d}>", .{x});
        return;
    }
    if (heap.getTag(x) == .AP) {
        outSubterm(heap, file, heap.h(x));
        _ = word.putc(' ', file);
        outAtom(heap, file, heap.t(x));
    } else {
        outAtom(heap, file, x);
    }
}

/// Helper for `outTerm`: print one sub-term.
pub fn outAtom(heap: *Heap, file: ?*word.Stream, x_val: Word) void {
    var x = x_val;
    if (x < 0 or x > heap.TOP()) {
        _ = word.fprint(file, "<{d}>", .{x});
        return;
    }
    const tag_val = heap.getTag(x);
    if (tag_val == .INT) {
        if (rest(x) != 0) {
            x = bigtostr(heap, x);
            while (x != 0) {
                _ = word.putc(@intCast(heap.h(x)), file);
                x = heap.t(x);
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
        _ = word.fprint(file, "'{s}'", .{charname(heap, x)});
        return;
    }
    if (tag_val == .UNICODE) {
        _ = word.fprint(file, "'{x}'", .{heap.h(x)});
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
        while (heap.getTag(x) == .TCONS) {
            outTerm(heap, file, heap.h(x));
            _ = word.putc(',', file);
            x = heap.t(x);
        }
        outTerm(heap, file, heap.h(x));
        _ = word.putc(',', file);
        outTerm(heap, file, heap.t(x));
        _ = word.putc(')', file);
        return;
    }
    if (tag_val == .TRIES) {
        _ = word.fprint(file, "TRIES(", .{.{}});
        outTerm(heap, file, heap.h(x));
        _ = word.putc(',', file);
        outTerm(heap, file, heap.t(x));
        _ = word.putc(')', file);
        return;
    }
    if (tag_val == .LABEL) {
        _ = word.fprint(file, "LABEL(", .{.{}});
        outTerm(heap, file, heap.h(x));
        _ = word.putc(',', file);
        outTerm(heap, file, heap.t(x));
        _ = word.putc(')', file);
        return;
    }
    if (tag_val == .SHOW) {
        _ = word.fprint(file, "SHOW(", .{.{}});
        outTerm(heap, file, heap.h(x));
        _ = word.putc(',', file);
        outTerm(heap, file, heap.t(x));
        _ = word.putc(')', file);
        return;
    }
    if (tag_val == .STARTREADVALS) {
        _ = word.fprint(file, "READVALS(", .{.{}});
        outTerm(heap, file, heap.h(x));
        _ = word.putc(',', file);
        outTerm(heap, file, heap.t(x));
        _ = word.putc(')', file);
        return;
    }
    if (tag_val == .LET) {
        _ = word.fprint(file, "(LET ", .{.{}});
        outTerm(heap, file, heap.h(heap.h(x)));
        _ = word.fprint(file, "=", .{.{}});
        outTerm(heap, file, heap.t(heap.t(heap.h(x))));
        _ = word.fprint(file, ";IN ", .{.{}});
        outTerm(heap, file, heap.t(x));
        _ = word.fprint(file, ")", .{.{}});
        return;
    }
    if (tag_val == .LETREC) {
        const body = heap.t(x);
        _ = word.fprint(file, "(LETREC ", .{.{}});
        x = heap.h(x);
        while (x != word.NIL) {
            outTerm(heap, file, heap.h(heap.h(x)));
            _ = word.fprint(file, "=", .{.{}});
            outTerm(heap, file, heap.t(heap.t(heap.h(x))));
            _ = word.fprint(file, ";", .{.{}});
            x = heap.t(x);
        }
        _ = word.fprint(file, "IN ", .{.{}});
        outTerm(heap, file, body);
        _ = word.fprint(file, ")", .{.{}});
        return;
    }
    if (tag_val == .DATAPAIR) {
        _ = word.fprint(file, "DATAPAIR({s},{d})", .{ castPtr(heap.h(x)), heap.t(x) });
        return;
    }
    if (tag_val == .FILEINFO) {
        _ = word.fprint(file, "FILEINFO({s},{d})", .{ castPtr(heap.h(x)), heap.t(x) });
        return;
    }
    if (tag_val == .CONSTRUCTOR) {
        _ = word.fprint(file, "CONSTRUCTOR({d})", .{heap.h(x)});
        return;
    }
    if (tag_val == .STRCONS) {
        _ = word.fprint(file, "<${d}>", .{heap.h(x)});
        return;
    }
    if (tag_val == .SHARE) {
        _ = word.fprint(file, "(SHARE:", .{.{}});
        outTerm(heap, file, heap.h(x));
        _ = word.fprint(file, ")", .{.{}});
        return;
    }
    if (tag_val != .CONS and tag_val != .AP and tag_val != .LAMBDA) {
        _ = word.fprint(file, "<{d}|tag={d}>", .{ x, @intFromEnum(tag_val) });
        return;
    }
    _ = word.putc(')', file);
}
