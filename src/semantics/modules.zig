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
const word = @import("../graph/word.zig");
const directives = @import("../syntax/directives.zig");
const source_mod = @import("../syntax/source.zig");
const lexer_mod = @import("../syntax/lexer.zig");
const layout_mod = @import("../syntax/layout.zig");
const parser_mod = @import("../syntax/parser.zig");
const ast = @import("../syntax/ast.zig");
const codegen = @import("../parser/codegen.zig");
const lex = @import("../parser/lex.zig");
const heap_mod = @import("../graph/heap.zig");
const symbols = @import("symbols.zig");
const rt = @import("../runtime/runtime_state.zig");
const config_state = @import("../session/config_state.zig");

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

// ---------------------------------------------------------------------------
// The harder half: actually loading, compiling, and binding an `%include`d
// file (docs/ZIG_NATIVE_PLAN.md Phase 1 step 5, landed 2026-07-06 — after
// step 7's production cutover, per the user's own direction, so this is
// built against the native pipeline rather than the legacy one about to be
// replaced).
// ---------------------------------------------------------------------------

/// Resolved, absolute paths of files currently being `%include`d — cycle
/// detection: a file that tries to `%include` itself, directly or
/// transitively, is a compile error, not infinite recursion.
pub const IncludingStack = std.StringHashMapUnmanaged(void);

pub const ModuleError = error{
    IncludeCycle,
    IncludeCompileFailed,
};

/// The identifier a definition's LHS `Expr` introduces — `f` for both
/// `f = ...` (`.name`) and `f x y = ...` (nested `.application`, the
/// innermost `.func`). `null` for LHS shapes that don't name a single
/// identifier (destructuring patterns, operator definitions) — not yet
/// part of any export set, a known gap matching this step's scope (no
/// shipped fixture defines a top-level operator or destructures at the top
/// level).
fn defName(lhs: ast.Expr) ?[]const u8 {
    return switch (lhs) {
        .name => |n| n.text,
        .cname => |n| n.text,
        .application => |a| defName(a.func.*),
        .typed => |t| defName(t.expr.*),
        else => null,
    };
}

/// Every name `script` defines at its own top level. `.definition` items
/// only, for now — type declarations/specs aren't yet part of any export
/// set (a known gap; no shipped `%include` fixture exports a type).
/// Caller frees the result.
pub fn collectTopLevelNames(gpa: std.mem.Allocator, script: ast.Script) ![][]const u8 {
    var names: std.ArrayList([]const u8) = .empty;
    errdefer names.deinit(gpa);
    for (script.items) |item| {
        if (item == .definition) {
            if (defName(item.definition.lhs)) |n| try names.append(gpa, n);
        }
    }
    return names.toOwnedSlice(gpa);
}

/// Resolve an `%include`'s path: `<...>`-form is relative to `miralib`
/// (`config_state.config().miralib`); `"..."`-form is relative to the including file's
/// own directory (`base_dir`). Appends `.m` if the path has no extension
/// already (matching legacy's `addextn`). Caller frees the result.
fn resolveIncludePath(gpa: std.mem.Allocator, path: []const u8, from_miralib: bool, base_dir: []const u8) ![]u8 {
    const dir: []const u8 = if (from_miralib)
        (if (config_state.config().miralib) |m| std.mem.span(m) else ".")
    else
        base_dir;
    const has_ext = std.mem.indexOfScalar(u8, std.fs.path.basename(path), '.') != null;
    const with_ext = if (has_ext) path else try std.fmt.allocPrint(gpa, "{s}.m", .{path});
    defer if (!has_ext) gpa.free(with_ext);
    return std.fs.path.join(gpa, &.{ dir, with_ext });
}

/// Tokenize/layout/parse `text` as a standalone unit — shared by full-file
/// compilation and the `%include` bindings-block pre-pass (which builds a
/// small synthetic snippet, not a whole file — see `compileBindings`).
/// Caller must have already appended a trailing newline if needed; the
/// returned `ast.Script`'s memory lives in `arena_alloc` (an arena — call
/// sites don't free the intermediate tokens/AST individually).
fn parseSnippet(arena_alloc: std.mem.Allocator, text: []const u8) !ast.Script {
    var src = try source_mod.Source.fromBytes(arena_alloc, text);
    const tok_result = try lexer_mod.tokenizeWithDirectives(arena_alloc, &src);
    const laid_out = try layout_mod.applyLayout(arena_alloc, tok_result.tokens);
    var p = parser_mod.Parser.initWithDirectives(arena_alloc, laid_out, tok_result.directives);
    const script = try parser_mod.parseScript(&p);
    if (p.diagnostics.items.len > 0) return ModuleError.IncludeCompileFailed;
    return script;
}

/// Compile an `%include`'s bindings block (`{elem==num; zero=0; add=+}`) —
/// a semicolon-separated list of type-synonym (`name==type`) and value
/// (`name=expr`) bindings, in the library's own abbreviated grammar (no
/// `type` keyword for the synonym form; a bare operator symbol like `+` on
/// a value binding's RHS is accepted unparenthesized, unlike ordinary
/// Miranda expression syntax). Reduces each clause to ordinary top-level
/// syntax (`type {lhs} == {rhs}`, or `{lhs} = ({rhs})` — wrapping the RHS in
/// parens handles the bare-operator case, e.g. `add=+` -> `add = (+)`,
/// `(+)` already being ordinary `op_func` syntax) and compiles it through
/// the normal pipeline, so `elem`/`zero`/`add` are bound in the shared
/// symbol table exactly like any other top-level definition — the
/// including library's own later references to them (compiled next, by
/// `processOneInclude`) resolve to these bindings via the same lookup
/// mechanism everything else uses.
fn compileBindings(heap: *heap_mod.Heap, arena_alloc: std.mem.Allocator, bindings_text: []const u8) !void {
    var it = std.mem.splitScalar(u8, bindings_text, ';');
    while (it.next()) |raw_clause| {
        const clause = std.mem.trim(u8, raw_clause, " \t\r\n");
        if (clause.len == 0) continue;
        const snippet: []const u8 = if (std.mem.indexOf(u8, clause, "==")) |eq_pos| blk: {
            const lhs = std.mem.trim(u8, clause[0..eq_pos], " \t");
            const rhs = std.mem.trim(u8, clause[eq_pos + 2 ..], " \t");
            break :blk try std.fmt.allocPrint(arena_alloc, "type {s} == {s}\n", .{ lhs, rhs });
        } else if (std.mem.indexOfScalar(u8, clause, '=')) |eq_pos| blk: {
            const lhs = std.mem.trim(u8, clause[0..eq_pos], " \t");
            const rhs = std.mem.trim(u8, clause[eq_pos + 1 ..], " \t");
            break :blk try std.fmt.allocPrint(arena_alloc, "{s} = ({s})\n", .{ lhs, rhs });
        } else continue; // malformed clause -- skip rather than guess
        const script = try parseSnippet(arena_alloc, snippet);
        codegen.codegenScript(heap, arena_alloc, script);
    }
}

/// Determine `script`'s export set (its own `%export` directive, or the
/// default "everything" if absent), resolve `aliases` against it, hide
/// (permanently, for the rest of the process — see `lex.mkprivate`'s own
/// doc comment on why `%export`'s hiding needs to be a *live* dictionary
/// operation here, unlike `dump.zig`'s dump-time-only privatise/publicise)
/// every one of `script`'s own top-level names that ends up not visible,
/// and `symbols.zig`-`bind` every alias name that isn't already the name
/// its target was compiled under.
fn applyExportsAndAliases(heap: *heap_mod.Heap, gpa: std.mem.Allocator, script: ast.Script, aliases: []const Alias) !void {
    const own_names = try collectTopLevelNames(gpa, script);
    defer gpa.free(own_names);

    var export_parts: []const ExportPart = &.{};
    var parsed_parts: ?[]ExportPart = null;
    defer if (parsed_parts) |pp| gpa.free(pp);
    for (script.items) |item| {
        if (item == .directive and item.directive == .export_list) {
            parsed_parts = try parseExportParts(gpa, item.directive.export_list.parts_text);
            export_parts = parsed_parts.?;
        }
    }

    var file_exports: std.StringHashMapUnmanaged([]const []const u8) = .{};
    defer file_exports.deinit(gpa);
    var exported_set = try resolveExports(gpa, own_names, export_parts, &file_exports);
    defer exported_set.deinit(gpa);

    var exports_map: std.StringHashMapUnmanaged(Word) = .{};
    defer exports_map.deinit(gpa);
    var eit = exported_set.keyIterator();
    while (eit.next()) |k| {
        if (symbols.syms().find(k.*)) |id| try exports_map.put(gpa, k.*, id);
    }

    var visible = try applyAliases(gpa, &exports_map, aliases);
    defer visible.deinit(gpa);

    // Bind every alias name that isn't already the name its id resolves
    // under (a rename's "new" half; the "old" half is handled by the hide
    // pass below, since applyAliases already dropped it from `visible`).
    var vit = visible.iterator();
    while (vit.next()) |entry| {
        if (symbols.syms().find(entry.key_ptr.*)) |existing| {
            if (existing == entry.value_ptr.*) continue; // already bound under this name
        }
        try symbols.syms().bind(gpa, entry.key_ptr.*, entry.value_ptr.*);
    }

    // Hide every one of this script's own top-level names that didn't
    // survive into `visible` under its original spelling (not exported at
    // all, or exported but renamed/suppressed by an alias).
    var to_hide: Word = word.NIL;
    for (own_names) |n| {
        if (visible.contains(n)) continue;
        if (symbols.syms().find(n)) |id| to_hide = heap_mod.cons(heap, id, to_hide);
    }
    if (to_hide != word.NIL) lex.mkprivate(heap, to_hide);
}

/// Fully resolve one `%include` directive: resolve its path, detect cycles,
/// read + `%insert`-splice + parse the target file, compile any bindings
/// block first (so the target's own free-variable references resolve to
/// them), recursively process the target's own `%include`s before its own
/// definitions (same order as the top level), compile the target's own
/// definitions, then apply its `%export`/alias visibility.
// Explicit (not inferred) error set: processOneInclude and processIncludes
// call each other, and Zig can't infer an error set across a
// recursive/mutual-recursion cycle (same issue as source.zig's
// spliceOneInsert/resolveInserts).
fn processOneInclude(heap: *heap_mod.Heap, gpa: std.mem.Allocator, inc: directives.Include, base_dir: []const u8, stack: *IncludingStack) anyerror!void {
    const resolved_path = try resolveIncludePath(gpa, inc.path, inc.from_miralib, base_dir);
    defer gpa.free(resolved_path);

    if (stack.contains(resolved_path)) return ModuleError.IncludeCycle;
    const stack_key = try gpa.dupe(u8, resolved_path);
    try stack.put(gpa, stack_key, {});
    defer {
        _ = stack.remove(stack_key);
        gpa.free(stack_key);
    }

    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    const arena_alloc = arena.allocator();

    const io = std.Options.debug_io;
    const src = try source_mod.Source.loadFile(arena_alloc, io, resolved_path);
    const inc_dir = std.fs.path.dirname(resolved_path) orelse ".";
    const spliced = try source_mod.Source.resolveInserts(arena_alloc, src.bytes, inc_dir, io, 0);
    var real_src = try source_mod.Source.init(arena_alloc, spliced, source_mod.Source.isLiterateName(resolved_path));

    const tok_result = try lexer_mod.tokenizeWithDirectives(arena_alloc, &real_src);
    const laid_out = try layout_mod.applyLayout(arena_alloc, tok_result.tokens);
    var p = parser_mod.Parser.initWithDirectives(arena_alloc, laid_out, tok_result.directives);
    const inc_script = try parser_mod.parseScript(&p);
    if (p.diagnostics.items.len > 0) return ModuleError.IncludeCompileFailed;

    if (inc.bindings_text.len > 0) {
        try compileBindings(heap, arena_alloc, inc.bindings_text);
    }

    try processIncludes(heap, gpa, inc_script, inc_dir, stack);
    codegen.codegenScript(heap, arena_alloc, inc_script);
    try applyExportsAndAliases(heap, gpa, inc_script, inc.aliases);
}

/// Process every `%include` directive in `script.items`, in source order,
/// before `script`'s own definitions are compiled (they may reference
/// names the includes bring into scope). Call this before `codegenScript`;
/// `%export` needs no equivalent call for `script` itself — its own
/// `%export` only has an observable effect on whoever `%include`s *it*
/// (`processOneInclude`'s `applyExportsAndAliases` call, made once per
/// include, handles that).
pub fn processIncludes(heap: *heap_mod.Heap, gpa: std.mem.Allocator, script: ast.Script, base_dir: []const u8, stack: *IncludingStack) anyerror!void {
    for (script.items) |item| {
        if (item == .directive and item.directive == .include) {
            try processOneInclude(heap, gpa, item.directive.include, base_dir, stack);
        }
    }
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
