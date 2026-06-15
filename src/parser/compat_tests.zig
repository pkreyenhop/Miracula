//! Phase 12 – Differential Validation
//!
//! For each test case, parse with the legacy YACC parser and the new Zig
//! pipeline; capture `fil_defs(hd(files))` from both; compare strings.
//! A failing test means the new codegen emits different heap structure
//! than the legacy parser — a bug to investigate.

const std = @import("std");
const testing = std.testing;
const parser_api = @import("parser_api.zig");
const heap_compare = @import("heap_compare.zig");

const clib = @cImport({
    @cInclude("parser_bridge.h");
    @cInclude("data.h");
});

extern fn setupheap() void;
extern fn setupdic() void;
extern fn reset_pns() void;
extern fn reset_state() void;
extern var current_file: clib.word;
extern var files: clib.word;
extern var col: clib.word;
extern var line_no: clib.word;
extern var c: clib.word;
extern var SYNERR: clib.word;
extern var lmargin: clib.word;

fn make_fil_record(name: [*:0]const u8) clib.word {
    const name_word = @as(clib.word, @intCast(@intFromPtr(name)));
    const file_info = clib.make(clib.FILEINFO, name_word, 0);
    const share_cell = clib.make(clib.CONS, 1, clib.NIL);
    const info_cell = clib.make(clib.CONS, file_info, share_cell);
    return clib.make(clib.CONS, info_cell, clib.NIL);
}

// Each test runs in a forked process with clean globals, so the heap
// and dictionary must be initialised before the first `reset_state()` call.
var initialized = false;

fn ensureInit() void {
    if (!initialized) {
        setupheap();
        setupdic();
        reset_pns();
        current_file = make_fil_record("test.m");
        files = clib.make(clib.CONS, current_file, clib.NIL);
        initialized = true;
    }
}

fn resetHeap() void {
    ensureInit();
    reset_state();
    setupheap();
    setupdic();
    reset_pns();
    current_file = make_fil_record("test.m");
    files = clib.make(clib.CONS, current_file, clib.NIL);
    col = 0;
    line_no = 0;
    c = ' ';
    SYNERR = 0;
    lmargin = 0;
}

/// Parse `source` with the legacy YACC parser and return the serialized env.
/// Caller owns the returned slice.
fn legacyEnv(gpa: std.mem.Allocator, source: [*:0]const u8) ![]u8 {
    resetHeap();
    _ = try parser_api.parseWithLegacy(source);
    return heap_compare.captureEnv(gpa);
}

/// Parse `source` with the new Zig pipeline and return the serialized env.
/// Caller owns the returned slice.
fn newEnv(gpa: std.mem.Allocator, source: [*:0]const u8) ![]u8 {
    resetHeap();
    _ = try parser_api.parseWithNew(gpa, source);
    return heap_compare.captureEnv(gpa);
}

// ─── Tests ────────────────────────────────────────────────────────────────────

test "compat: identity function" {
    const gpa = testing.allocator;
    const source = "id x = x\n";

    const legacy = try legacyEnv(gpa, source);
    defer gpa.free(legacy);

    const new = try newEnv(gpa, source);
    defer gpa.free(new);

    testing.expectEqualStrings(legacy, new) catch |err| {
        std.debug.print("\n=== compat: identity function ===\nLEGACY:\n{s}\nNEW:\n{s}\n", .{ legacy, new });
        return err;
    };
}

test "compat: simple constant" {
    const gpa = testing.allocator;
    const source = "answer = 42\n";

    const legacy = try legacyEnv(gpa, source);
    defer gpa.free(legacy);

    const new = try newEnv(gpa, source);
    defer gpa.free(new);

    testing.expectEqualStrings(legacy, new) catch |err| {
        std.debug.print("\n=== compat: simple constant ===\nLEGACY:\n{s}\nNEW:\n{s}\n", .{ legacy, new });
        return err;
    };
}

test "compat: two-arg function" {
    const gpa = testing.allocator;
    const source = "add x y = x + y\n";

    const legacy = try legacyEnv(gpa, source);
    defer gpa.free(legacy);

    const new = try newEnv(gpa, source);
    defer gpa.free(new);

    testing.expectEqualStrings(legacy, new) catch |err| {
        std.debug.print("\n=== compat: two-arg function ===\nLEGACY:\n{s}\nNEW:\n{s}\n", .{ legacy, new });
        return err;
    };
}

test "compat: pattern match" {
    const gpa = testing.allocator;
    const source = "sum [] = 0\nsum (x:xs) = x + sum xs\n";

    const legacy = try legacyEnv(gpa, source);
    defer gpa.free(legacy);

    const new = try newEnv(gpa, source);
    defer gpa.free(new);

    testing.expectEqualStrings(legacy, new) catch |err| {
        std.debug.print("\n=== compat: pattern match ===\nLEGACY:\n{s}\nNEW:\n{s}\n", .{ legacy, new });
        return err;
    };
}

test "compat: algebraic type" {
    const gpa = testing.allocator;
    const source = "tree ::= Leaf | Node tree tree\n";

    const legacy = try legacyEnv(gpa, source);
    defer gpa.free(legacy);

    const new = try newEnv(gpa, source);
    defer gpa.free(new);

    testing.expectEqualStrings(legacy, new) catch |err| {
        std.debug.print("\n=== compat: algebraic type ===\nLEGACY:\n{s}\nNEW:\n{s}\n", .{ legacy, new });
        return err;
    };
}

test "compat: constructor pattern in LHS" {
    const gpa = testing.allocator;
    const source = "foo ::= Bar\ncount Bar = 0\n";

    const legacy = try legacyEnv(gpa, source);
    defer gpa.free(legacy);

    const new = try newEnv(gpa, source);
    defer gpa.free(new);

    testing.expectEqualStrings(legacy, new) catch |err| {
        std.debug.print("\n=== compat: constructor pattern ===\nLEGACY:\n{s}\nNEW:\n{s}\n", .{ legacy, new });
        return err;
    };
}

test "compat: type signature" {
    const gpa = testing.allocator;
    const source = "f :: num -> num\nf x = x + 1\n";

    const legacy = try legacyEnv(gpa, source);
    defer gpa.free(legacy);

    const new = try newEnv(gpa, source);
    defer gpa.free(new);

    testing.expectEqualStrings(legacy, new) catch |err| {
        std.debug.print("\n=== compat: type signature ===\nLEGACY:\n{s}\nNEW:\n{s}\n", .{ legacy, new });
        return err;
    };
}

test "compat: multiline where clause" {
    const gpa = testing.allocator;
    // One where-def on a separate indented line (simpler case to start).
    const source = "f x = g x\n      where\n        g y = y + 1\n";

    const legacy = try legacyEnv(gpa, source);
    defer gpa.free(legacy);

    const new = try newEnv(gpa, source);
    defer gpa.free(new);

    testing.expectEqualStrings(legacy, new) catch |err| {
        std.debug.print("\n=== compat: multiline where clause ===\nLEGACY:\n{s}\nNEW:\n{s}\n", .{ legacy, new });
        return err;
    };
}
