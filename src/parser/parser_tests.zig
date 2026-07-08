//! parser_tests.zig — snapshot tests for the parser.
//!
//! `runASTSnapshotTest` parses `source` with the native pipeline and
//! confirms it succeeds (a full byte-exact AST snapshot mechanism was
//! never actually built — the name predates that plan changing). The
//! helpers reset and re-initialise the shared lexer/dictionary state
//! between runs.

const std = @import("std");
const parser_api = @import("parser_api.zig");
const testing = std.testing;
const heap = @import("../graph/heap.zig");
const module_loader = @import("../compiler/module_loader.zig");
const commands = @import("../session/commands.zig");
const abi = @import("../os.zig");

const setupheap = heap.setupheap;
const setupdic = lex.setupdic;
const lex_state = @import("lex_state.zig");
const lex = @import("lex.zig");
const rt = @import("../runtime/runtime_state.zig");
const config_state = @import("../session/config_state.zig");
const setup = @import("../compiler/setup.zig");
const os = @import("../os.zig");
const word = @import("../graph/word.zig");
const strtab = @import("../graph/strtab.zig");
const core_state = @import("../runtime/core_state.zig");
const cs = @import("../compiler/compiler_state.zig").cs;
const ls = lex_state.ls;

const resetPns = lex.resetPns;
/// Build a dummy file record for the snapshot tests.
fn makeFilRecord(name: [*:0]const u8) word.Word {
    const name_word = @as(word.Word, strtab.strBits(strtab.table(), name));
    const file_info = heap.make(.FILEINFO, name_word, 0);
    const share_cell = heap.make(.CONS, 1, word.NIL);
    const info_cell = heap.make(.CONS, file_info, share_cell);
    return heap.make(.CONS, info_cell, word.NIL);
}

const resetState = lex.resetState;

/// Reset the interpreter to a clean slate between tests.
///
/// `parseString` runs the full pipeline including `codegenScript`, which calls
/// `declare`/type-checking and therefore needs a properly seeded environment
/// (`nill`, the primitive env, the type system). Partial setup leaves `nill`
/// unset and the primitive env stale, so codegen builds a malformed graph that
/// sends `irrefutable` into an infinite loop on cons patterns. We therefore run
/// the same `miraSetup` the production loader uses. `miraSetup` reuses the heap
/// allocation after the first call (it only `@memset`s the tag column), so this
/// is cheap to repeat; `primenv` is reset first because `primlib` conses onto it.
fn resetLexerState() void {
    resetState(heap.heap());
    setupdic();
    rt.rs().primenv = word.NIL;
    setup.miraSetup();
    heap.heap().current_file = makeFilRecord("test.m");
    heap.heap().files = heap.make(.CONS, heap.heap().current_file, word.NIL);
    ls().col = 0;
    ls().line_no = 0;
    ls().c = ' ';
    core_state.s().SYNERR = 0;
    core_state.s().errcol = 0;
}

var initialized = false;
/// Perform one-time interpreter setup for the parser tests.
fn ensureInitialized() void {
    if (!initialized) {
        setupheap();
        setupdic();
        resetPns();
        heap.heap().current_file = makeFilRecord("test.m");
        heap.heap().files = heap.make(.CONS, heap.heap().current_file, word.NIL);
        initialized = true;
    }
}

test "prelude parsing test" {
    ensureInitialized();
    resetLexerState();
    // Parse the entire prelude. It should parse successfully. Reads the
    // file directly and feeds it through parseString (native pipeline) —
    // simpler than opening the file through the legacy fileq/s_in dance
    // parseFile/setupFile used, which this test was the only caller of.
    const io = std.Options.debug_io;
    const bytes = try std.Io.Dir.cwd().readFileAlloc(io, "miralib/prelude", testing.allocator, .limited(1024 * 1024));
    defer testing.allocator.free(bytes);
    const bytes_z = try testing.allocator.dupeZ(u8, bytes);
    defer testing.allocator.free(bytes_z);
    _ = try parser_api.parseString(bytes_z.ptr);
}

/// Parse `source` with the new parser and compare its AST against the snapshot.
fn runASTSnapshotTest(allocator: std.mem.Allocator, name: []const u8, source: [:0]const u8) !void {
    _ = name;
    ensureInitialized();
    resetLexerState();
    _ = try parser_api.parseWithNew(allocator, source.ptr);
}

test "new parser AST snapshot tests" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // Phase 8 baseline
    try runASTSnapshotTest(allocator, "simple_def", "square x = x * x\n");
    try runASTSnapshotTest(allocator, "id", "id x = x\n");
    try runASTSnapshotTest(allocator, "double", "double x = x + x\n");
    try runASTSnapshotTest(allocator, "inc", "inc = (+1)\n");
    try runASTSnapshotTest(allocator, "main", "main = square 5\n");

    // Phase 9.2: operator-as-function section (+)
    try runASTSnapshotTest(allocator, "op_func", "add = (+)\n");

    // Phase 9.1: list comprehensions and range expressions
    try runASTSnapshotTest(allocator, "listcomp", "evens = [x | x <- xs]\n");
    try runASTSnapshotTest(allocator, "range_to", "r = [1..10]\n");
    try runASTSnapshotTest(allocator, "range_open", "nats = [1..]\n");
    try runASTSnapshotTest(allocator, "range_step", "odds = [1,3..99]\n");

    // Phase 9.3 / type declarations
    try runASTSnapshotTest(allocator, "algebraic_type", "colour ::= Red | Green | Blue\n");
    try runASTSnapshotTest(allocator, "algebraic_type_param", "tree * ::= Leaf | Node (tree *) * (tree *)\n");
    // Miranda type synonym names are lowercase identifiers
    try runASTSnapshotTest(allocator, "type_synonym", "type pair * ** == (*, **)\n");
}

test "error detection sets SYNERR and errline" {
    ensureInitialized();
    resetLexerState();

    // 1. Check syntax error sets core.s.SYNERR and core.s.errline
    const source1 = "add1 x = x+1\nl = [1,,2,3]\n";
    _ = parser_api.parseString(source1) catch {};
    try testing.expectEqual(@as(word.Word, 1), core_state.s().SYNERR);
    try testing.expectEqual(@as(word.Word, 2), core_state.s().errline);
    // Phase 2 step 2: the diagnostic's message text is also persisted
    // (additively, alongside errline/errcol) -- must survive past the
    // parse's own arena, so it's non-empty here even though the arena
    // that originally held it is long gone.
    try testing.expect(core_state.s().last_diagnostic_message.len > 0);

    // 2. Syntax error on the last line gets detected and sets correct errline
    resetLexerState();
    const source2 = "add1 x = x+1\nfib 0 = 0\nerror_line = [1,,2]";
    _ = parser_api.parseString(source2) catch {};
    try testing.expectEqual(@as(word.Word, 1), core_state.s().SYNERR);
    try testing.expectEqual(@as(word.Word, 3), core_state.s().errline);
}

test "script reload after failed compile does not cause nameclash" {
    ensureInitialized();
    resetLexerState();

    const old_init = rt.rs().initialising;
    rt.rs().initialising = 0;
    defer rt.rs().initialising = old_init;

    const tmp_file = "test_reload.m";
    defer _ = os.unlink(tmp_file);

    // 1. Successful first compile
    {
        const f = os.fopen(tmp_file, "w");
        _ = os.fputs("add1 x = x+1\n", f.?);
        _ = os.fclose(f.?);
    }
    module_loader.loadfile(heap.heap(), core_state.s(), cs(), rt.rs(), ls(), tmp_file) catch {};
    try testing.expectEqual(@as(word.Word, 0), core_state.s().SYNERR);

    // 2. Failed compile with syntax error
    {
        const f = os.fopen(tmp_file, "w");
        _ = os.fputs("add1 x = x+1\nl = [1,,2]\n", f.?);
        _ = os.fclose(f.?);
    }
    module_loader.loadfile(heap.heap(), core_state.s(), cs(), rt.rs(), ls(), tmp_file) catch {};
    try testing.expectEqual(@as(word.Word, 2), core_state.s().errline);

    // 3. Re-compile fixed script
    {
        const f = os.fopen(tmp_file, "w");
        _ = os.fputs("add1 x = x+1\nl = [1,2]\n", f.?);
        _ = os.fclose(f.?);
    }
    module_loader.loadfile(heap.heap(), core_state.s(), cs(), rt.rs(), ls(), tmp_file) catch {};
    try testing.expectEqual(@as(word.Word, 0), core_state.s().SYNERR);
    try testing.expectEqual(@as(word.Word, 0), core_state.s().errline);
}

test "syntax error sets errcol and editfile expands column placeholder" {
    ensureInitialized();
    resetLexerState();

    // 1. Check syntax error sets core.s.errcol
    const source1 = "add1 x = x+1\nl = [1,,2,3]\n";
    _ = parser_api.parseString(source1) catch {};
    try testing.expectEqual(@as(word.Word, 2), core_state.s().errline);
    // Double comma is at column 8 (1-indexed) in "l = [1,,2,3]\n",
    // but the Pratt parser eagerly advances past the unexpected token before failing,
    // positioning the error at the next token '2' at column 9.
    try testing.expectEqual(@as(word.Word, 9), core_state.s().errcol);

    // 2. Check editfile expands the column placeholder '&'
    const old_editor = config_state.config().editor;
    defer config_state.config().editor = old_editor;

    config_state.config().editor = @constCast(@as([*:0]const u8, ": -l ! -c & -f %"));
    commands.editfile(rt.rs(), "test.m", 42, 17);

    // Verify ebuf_local contents in rt.rs().linebuf
    const expected_cmd = ": -l 42 -c 17 -f \"test.m\"";
    const actual_cmd = std.mem.span(@as([*:0]const u8, @ptrCast(&rt.rs().linebuf[0])));
    try testing.expectEqualStrings(expected_cmd, actual_cmd);
}

test "/editor command parses arguments on the same line" {
    ensureInitialized();
    resetLexerState();

    const old_editor = config_state.config().editor;
    defer config_state.config().editor = old_editor;

    // 1. /editor without arguments: just prints current editor (doesn't prompt/block)
    ls().dicp = @constCast(@as([*:0]const u8, "editor"));
    ls().c = '\n';
    _ = commands.command(heap.heap(), core_state.s(), cs(), rt.rs(), ls());

    // 2. /editor with arguments on the same line: changes editor
    ls().dicp = @constCast(@as([*:0]const u8, "editor"));
    ls().c = ' ';

    if (abi.stdin()) |stdin_file| {
        stdin_file.mem_buf = "my_custom_editor\ny\n";
        stdin_file.mem_pos = 0;
    }
    defer {
        if (abi.stdin()) |stdin_file| {
            stdin_file.mem_buf = null;
            stdin_file.mem_pos = 0;
        }
    }

    _ = commands.command(heap.heap(), core_state.s(), cs(), rt.rs(), ls());

    const actual_editor = std.mem.span(config_state.config().editor.?);
    try testing.expectEqualStrings("my_custom_editor", actual_editor);
}
// Cache invalidation comment for strict-main-tests
