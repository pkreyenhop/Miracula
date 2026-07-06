//! semantics/modules.zig — `%include`/`%export` semantics
//! (docs/ZIG_NATIVE_PLAN.md Phase 1 step 5), built on `syntax/directives.zig`'s
//! structured `Directive` values.
//!
//! **Scope of this increment:** the two *pure* transformations the manual
//! (docs/man/mira.man.ms §27) specifies, independent of actually compiling
//! anything — `resolveExports` (what a script exports, given its top-level
//! names and an `%export` directive's parts) and `applyAliases` (how an
//! `%include`'s alias list modifies the included script's export set before
//! it becomes visible). Both operate on plain name/`Word` maps, not real
//! compiled scripts, so both are fully testable without a heap or parser —
//! confirmed against the manual's own worked examples where possible.
//!
//! **Deliberately not done here** (the harder half of step 5, needing real
//! integration with the existing compiler, not just data transformation):
//! actually loading and compiling an `%include`d file, extracting its real
//! export set from a real heap, binding the result into the including
//! script's identifier scope (`semantics/symbols.zig`, not yet wired into
//! `codegen.zig`/`trans.zig` either), cycle detection across a chain of
//! `%include`s, and free-binding substitution (`%free`'s `{ signature }` —
//! still raw text in `Directive.free.spec_text`, needing an expression/type
//! parser `syntax/` doesn't have yet). `dependOn`/`resolveExports`'s `.file`
//! case (`%export "liba" "libb"` — re-exporting an included file's exports
//! wholesale) is implemented at the data-transformation level but its input
//! (another file's real export set) is a caller-supplied stub in tests, not
//! a real compilation result.
//!
//! Tests: resolveExports / applyAliases — one test per manual rule quoted in
//! their doc comments.

const std = @import("std");
const word = @import("../runtime/word.zig");
const directives = @import("../syntax/directives.zig");

const Word = word.Word;
const Alias = directives.Alias;

/// One item in an `%export` directive's parts list (manual §27/3).
pub const ExportPart = union(enum) {
    /// `+` — every top-level identifier of the current script.
    all,
    /// A bare identifier or constructor name.
    name: []const u8,
    /// `-identifier` — subtract a name, overriding any positive occurrence
    /// regardless of ordering (manual: "A negative occurrence... overrides
    /// any number of positive occurrences").
    exclude: []const u8,
    /// `"fileid"` — re-export everything exported from that `%include`d file.
    file: []const u8,
};

/// Parse `%export`'s raw parts text (`Directive.export_list.parts_text`)
/// into structured parts. Caller frees the result.
pub fn parseExportParts(gpa: std.mem.Allocator, text: []const u8) ![]ExportPart {
    var out: std.ArrayList(ExportPart) = .empty;
    errdefer out.deinit(gpa);
    var i: usize = 0;
    while (i < text.len) {
        while (i < text.len and (text[i] == ' ' or text[i] == '\t')) i += 1;
        if (i >= text.len) break;
        if (text[i] == '+') {
            try out.append(gpa, .all);
            i += 1;
        } else if (text[i] == '-') {
            i += 1;
            const start = i;
            while (i < text.len and text[i] != ' ' and text[i] != '\t') i += 1;
            try out.append(gpa, .{ .exclude = text[start..i] });
        } else if (text[i] == '"') {
            i += 1;
            const start = i;
            while (i < text.len and text[i] != '"') i += 1;
            try out.append(gpa, .{ .file = text[start..i] });
            if (i < text.len) i += 1; // the closing '"'
        } else {
            const start = i;
            while (i < text.len and text[i] != ' ' and text[i] != '\t') i += 1;
            try out.append(gpa, .{ .name = text[start..i] });
        }
    }
    return out.toOwnedSlice(gpa);
}

/// Resolve the set of names a script exports.
///
/// `top_level_names`: every name defined at this script's own top level.
/// `parts`: the parsed `%export` directive, or `&.{}` if the script has no
/// `%export` directive at all — the manual's default is then exactly `+`
/// (every top-level name, nothing acquired via `%include`).
/// `file_exports`: resolves a `.file` part's quoted fileid to that file's own
/// already-resolved export set (a real caller would have compiled it first;
/// tests here supply a fixed map).
///
/// Caller frees the returned map (`.deinit(gpa)`).
pub fn resolveExports(
    gpa: std.mem.Allocator,
    top_level_names: []const []const u8,
    parts: []const ExportPart,
    file_exports: *const std.StringHashMapUnmanaged([]const []const u8),
) !std.StringHashMapUnmanaged(void) {
    var included: std.StringHashMapUnmanaged(void) = .{};
    errdefer included.deinit(gpa);
    var excluded: std.StringHashMapUnmanaged(void) = .{};
    defer excluded.deinit(gpa);

    const effective: []const ExportPart = if (parts.len == 0) &.{.all} else parts;
    for (effective) |part| {
        switch (part) {
            .all => for (top_level_names) |n| try included.put(gpa, n, {}),
            .name => |n| try included.put(gpa, n, {}),
            .exclude => |n| try excluded.put(gpa, n, {}),
            .file => |f| if (file_exports.get(f)) |names| {
                for (names) |n| try included.put(gpa, n, {});
            },
        }
    }
    var it = excluded.keyIterator();
    while (it.next()) |k| _ = included.remove(k.*);
    return included;
}

/// Apply an `%include`'s alias list to the included script's exports,
/// producing the name -> `ID` node mapping actually visible in the
/// including script (manual §27/3: `new/old` renames, `-old` suppresses;
/// anything not mentioned "will be accepted unchanged").
///
/// Caller frees the returned map (`.deinit(gpa)`).
pub fn applyAliases(
    gpa: std.mem.Allocator,
    exports: *const std.StringHashMapUnmanaged(Word),
    aliases: []const Alias,
) !std.StringHashMapUnmanaged(Word) {
    var result: std.StringHashMapUnmanaged(Word) = .{};
    errdefer result.deinit(gpa);
    var it = exports.iterator();
    while (it.next()) |entry| try result.put(gpa, entry.key_ptr.*, entry.value_ptr.*);

    for (aliases) |a| {
        switch (a) {
            .suppress => |name| _ = result.remove(name),
            .rename => |r| {
                if (result.fetchRemove(r.old)) |kv| {
                    try result.put(gpa, r.new, kv.value);
                }
            },
        }
    }
    return result;
}

fn expectPartsEqual(gpa: std.mem.Allocator, expected: []const ExportPart, text: []const u8) !void {
    const parts = try parseExportParts(gpa, text);
    defer gpa.free(parts);
    try std.testing.expectEqual(expected.len, parts.len);
    for (expected, parts) |e, p| {
        try std.testing.expectEqual(std.meta.activeTag(e), std.meta.activeTag(p));
        switch (e) {
            .all => {},
            .name => |n| try std.testing.expectEqualStrings(n, p.name),
            .exclude => |n| try std.testing.expectEqualStrings(n, p.exclude),
            .file => |n| try std.testing.expectEqualStrings(n, p.file),
        }
    }
}

test "parseExportParts: '+' -flooby (manual's own example)" {
    try expectPartsEqual(std.testing.allocator, &.{ .all, .{ .exclude = "flooby" } }, "+ -flooby");
}

test "parseExportParts: bare names" {
    try expectPartsEqual(std.testing.allocator, &.{ .{ .name = "matmult" }, .{ .name = "matadd" } }, "matmult matadd");
}

test "parseExportParts: quoted fileids (manual's libc.m example)" {
    try expectPartsEqual(std.testing.allocator, &.{ .{ .file = "liba" }, .{ .file = "libb" } }, "\"liba\" \"libb\"");
}

test "resolveExports: no %export directive defaults to '+' (every top-level name)" {
    const gpa = std.testing.allocator;
    var file_exports: std.StringHashMapUnmanaged([]const []const u8) = .{};
    defer file_exports.deinit(gpa);
    var exported = try resolveExports(gpa, &.{ "f", "g" }, &.{}, &file_exports);
    defer exported.deinit(gpa);
    try std.testing.expect(exported.contains("f"));
    try std.testing.expect(exported.contains("g"));
    try std.testing.expectEqual(@as(u32, 2), exported.count());
}

test "resolveExports: '+ -flooby' exports everything except flooby" {
    const gpa = std.testing.allocator;
    var file_exports: std.StringHashMapUnmanaged([]const []const u8) = .{};
    defer file_exports.deinit(gpa);
    const parts = [_]ExportPart{ .all, .{ .exclude = "flooby" } };
    var exported = try resolveExports(gpa, &.{ "f", "flooby", "g" }, &parts, &file_exports);
    defer exported.deinit(gpa);
    try std.testing.expect(exported.contains("f"));
    try std.testing.expect(exported.contains("g"));
    try std.testing.expect(!exported.contains("flooby"));
}

test "resolveExports: a negative occurrence overrides positive ones regardless of order" {
    const gpa = std.testing.allocator;
    var file_exports: std.StringHashMapUnmanaged([]const []const u8) = .{};
    defer file_exports.deinit(gpa);
    // '-f f' (exclude written *before* the explicit include of the same name).
    const parts = [_]ExportPart{ .{ .exclude = "f" }, .{ .name = "f" } };
    var exported = try resolveExports(gpa, &.{"f"}, &parts, &file_exports);
    defer exported.deinit(gpa);
    try std.testing.expect(!exported.contains("f"));
}

test "resolveExports: a quoted fileid re-exports that file's whole export set" {
    const gpa = std.testing.allocator;
    var file_exports: std.StringHashMapUnmanaged([]const []const u8) = .{};
    defer file_exports.deinit(gpa);
    try file_exports.put(gpa, "liba", &.{ "a1", "a2" });
    try file_exports.put(gpa, "libb", &.{"b1"});
    const parts = [_]ExportPart{ .{ .file = "liba" }, .{ .file = "libb" } };
    var exported = try resolveExports(gpa, &.{}, &parts, &file_exports);
    defer exported.deinit(gpa);
    try std.testing.expectEqual(@as(u32, 3), exported.count());
    try std.testing.expect(exported.contains("a1"));
    try std.testing.expect(exported.contains("a2"));
    try std.testing.expect(exported.contains("b1"));
}

test "applyAliases: '-old' suppresses, unmentioned names pass through unchanged" {
    const gpa = std.testing.allocator;
    var exports: std.StringHashMapUnmanaged(Word) = .{};
    defer exports.deinit(gpa);
    try exports.put(gpa, "f", 1);
    try exports.put(gpa, "g", 2);
    const aliases = [_]Alias{.{ .suppress = "g" }};
    var visible = try applyAliases(gpa, &exports, &aliases);
    defer visible.deinit(gpa);
    try std.testing.expectEqual(@as(?Word, 1), visible.get("f"));
    try std.testing.expectEqual(@as(?Word, null), visible.get("g"));
}

test "applyAliases: 'new/old' renames (manual's mike_f/f example)" {
    const gpa = std.testing.allocator;
    var exports: std.StringHashMapUnmanaged(Word) = .{};
    defer exports.deinit(gpa);
    try exports.put(gpa, "f", 42);
    try exports.put(gpa, "g", 99);
    const aliases = [_]Alias{ .{ .suppress = "g" }, .{ .rename = .{ .new = "mike_f", .old = "f" } } };
    var visible = try applyAliases(gpa, &exports, &aliases);
    defer visible.deinit(gpa);
    try std.testing.expectEqual(@as(?Word, null), visible.get("f")); // renamed away
    try std.testing.expectEqual(@as(?Word, 42), visible.get("mike_f"));
    try std.testing.expectEqual(@as(?Word, null), visible.get("g")); // suppressed
    try std.testing.expectEqual(@as(u32, 1), visible.count());
}
