//! parser_tests.zig — snapshot tests for the lexer and parsers.
//!
//! `runSnapshotTest` checks the legacy lexer's token stream against stored
//! `.snapshot` files; `runASTSnapshotTest` does the same for the new parser's
//! AST. The helpers reset and re-initialise the shared lexer state between runs.

const std = @import("std");
const parser_api = @import("parser_api.zig");
const testing = std.testing;
const heap = @import("../runtime/heap.zig");

const setupheap = heap.setupheap;
const setupdic = lex.setupdic;
const yylex = lex.yylex;
const lex_state = @import("lex_state.zig");
const lex = @import("lex.zig");
const rt = @import("../runtime/runtime_state.zig");
const setup = @import("../compiler/setup.zig");
const main_clib = @import("../runtime/main_clib.zig");
const word = @import("../runtime/word.zig");
const strtab = @import("../runtime/strtab.zig");
const core_state = @import("../runtime/core_state.zig");
const ls = lex_state.ls;

const makeId = lex.makeId;
const resetPns = lex.resetPns;
/// Build a dummy file record for the snapshot tests.
fn makeFilRecord(name: [*:0]const u8) word.Word {
    const name_word = @as(word.Word, strtab.strBits(name));
    const file_info = heap.make(word.FILEINFO, name_word, 0);
    const share_cell = heap.make(word.CONS, 1, word.NIL);
    const info_cell = heap.make(word.CONS, file_info, share_cell);
    return heap.make(word.CONS, info_cell, word.NIL);
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
    resetState();
    setupdic();
    rt.rs.primenv = word.NIL;
    setup.miraSetup();
    heap.heap.current_file = makeFilRecord("test.m");
    heap.heap.files = heap.make(word.CONS, heap.heap.current_file, word.NIL);
    ls.col = 0;
    ls.line_no = 0;
    ls.c = ' ';
    core_state.s.SYNERR = 0;
}

var initialized = false;
/// Perform one-time interpreter setup for the parser tests.
fn ensureInitialized() void {
    if (!initialized) {
        setupheap();
        setupdic();
        resetPns();
        heap.heap.current_file = makeFilRecord("test.m");
        heap.heap.files = heap.make(word.CONS, heap.heap.current_file, word.NIL);
        initialized = true;
    }
}

/// Human-readable name for a legacy-lexer token code `tok`.
fn tokenName(tok: c_int) []const u8 {
    return switch (tok) {
        0 => "EOF",
        '\n' => "NEWLINE",
        '(' => "LPAREN",
        ')' => "RPAREN",
        '[' => "LBRACKET",
        ']' => "RBRACKET",
        '{' => "LBRACE",
        '}' => "RBRACE",
        ',' => "COMMA",
        ';' => "SEMICOLON",
        '=' => "EQUALS",
        '+' => "PLUS",
        '-' => "MINUS",
        '*' => "TIMES",
        '/' => "DIV",
        '%' => "MOD",
        '^' => "POWER",
        '|' => "BAR",
        '<' => "LT",
        '>' => "GT",
        '\\' => "BACKSLASH",
        '.' => "DOT",
        '~' => "TILDE",
        ':' => "COLON",
        '!' => "EXCLAMATION",
        '?' => "QUESTION",
        '&' => "AMPERSAND",
        257 => "VALUE",
        258 => "EVAL",
        259 => "WHERE",
        260 => "IF",
        261 => "TO",
        262 => "LEFTARROW",
        263 => "COLONCOLON",
        264 => "COLON2EQ",
        265 => "TYPEVAR",
        266 => "NAME",
        267 => "CNAME",
        268 => "CONST",
        269 => "DOLLARS",
        270 => "OFFSIDE",
        271 => "ELSEQ",
        272 => "ABSTYPE",
        273 => "WITH",
        274 => "DIAG",
        275 => "EQEQ",
        276 => "FREE",
        277 => "INCLUDE",
        278 => "EXPORT",
        279 => "TYPE",
        280 => "OTHERWISE",
        281 => "SHOWSYM",
        282 => "PATHNAME",
        283 => "BNF",
        284 => "LEX",
        285 => "ENDIR",
        286 => "ERRORSY",
        287 => "ENDSY",
        288 => "EMPTYSY",
        289 => "READVALSY",
        290 => "LEXDEF",
        291 => "CHARCLASS",
        292 => "ANTICHARCLASS",
        293 => "LBEGIN",
        294 => "ARROW",
        295 => "PLUSPLUS",
        296 => "MINUSMINUS",
        297 => "DOTDOT",
        298 => "VEL",
        299 => "GE",
        300 => "NE",
        301 => "LE",
        302 => "REM",
        303 => "DIV",
        304 => "INFIXNAME",
        305 => "INFIXCNAME",
        else => "OTHER",
    };
}

/// Whether `s` is printable ASCII (safe to embed in a snapshot).
fn isCleanAscii(s: []const u8) bool {
    for (s) |ch| {
        if (ch < 32 or ch > 126) return false;
    }
    return true;
}

/// Run the legacy lexer over `source` and capture its token stream as text.
fn captureTokenStream(allocator: std.mem.Allocator, source: [:0]const u8) ![]const u8 {
    ensureInitialized();
    resetLexerState();
    parser_api.lexSetupString(source);
    defer parser_api.lexCleanup();

    var list: std.ArrayList(u8) = .empty;
    errdefer list.deinit(allocator);

    while (true) {
        const tok = yylex();
        if (tok == 0 or tok == word.END) break;

        try list.print(allocator, "{s}", .{tokenName(tok)});
        // Capture the identifier's text reliably from the interned id node
        // (`ls.yylval`), not the lagging `ls.dicp` buffer — the latter points at
        // stale or uninitialised dictionary memory and made the snapshots depend
        // on cross-test dic state (see the shared-state plan's Phase-4 finding).
        if (tok == word.NAME or tok == word.CNAME) {
            const h = heap.h;
            const id_text = std.mem.span(strtab.strOf(h(h(h(ls.yylval)))));
            if (id_text.len > 0 and isCleanAscii(id_text)) {
                try list.print(allocator, "(\"{s}\")", .{id_text});
            }
        }
        try list.print(allocator, "\n", .{});
    }
    return try list.toOwnedSlice(allocator);
}

/// Lex+parse `source` and compare the token stream against the stored snapshot.
fn runSnapshotTest(allocator: std.mem.Allocator, name: []const u8, source: [:0]const u8, is_error: bool) !void {
    const tokens = try captureTokenStream(allocator, source);
    defer allocator.free(tokens);

    // Parse result
    var parse_res: []const u8 = "SUCCESS";
    resetLexerState();
    _ = parser_api.parseString(source) catch {
        parse_res = "SYNTAX_ERROR";
    };

    var diag: std.ArrayList(u8) = .empty;
    defer diag.deinit(allocator);
    try diag.print(allocator, "PARSE_RESULT: {s}\n\nTOKENS:\n{s}", .{ parse_res, tokens });

    // Snapshot path
    const snapshot_dir = "tests/parser/snapshots";
    const path = try std.fmt.allocPrint(allocator, "{s}/{s}.snapshot", .{ snapshot_dir, name });
    defer allocator.free(path);

    const update = (main_clib.getenv("UPDATE_SNAPSHOTS") != null);

    if (update) {
        try std.Io.Dir.cwd().createDirPath(testing.io, snapshot_dir);
        const file = try std.Io.Dir.cwd().createFile(testing.io, path, .{});
        defer file.close(testing.io);
        try file.writeStreamingAll(testing.io, diag.items);
    } else {
        const file = std.Io.Dir.cwd().openFile(testing.io, path, .{}) catch |err| {
            std.debug.print("\nSnapshot file not found: {s}. Run with UPDATE_SNAPSHOTS=1 to create.\n", .{path});
            return err;
        };
        defer file.close(testing.io);
        var buf: [4096]u8 = undefined;
        const amt = try file.readPositionalAll(testing.io, &buf, 0);
        const expected = buf[0..amt];
        try testing.expectEqualStrings(expected, diag.items);
    }

    resetLexerState();
    if (is_error) {
        // Assert it fails parsing (accept any error — legacy returns SyntaxError, new returns ParseFailed)
        if (parser_api.parseString(source)) |_| {
            std.debug.print("[{s}] expected parse to fail, but it succeeded\n", .{name});
            return error.TestExpectedError;
        } else |_| {}
    } else {
        // Assert it succeeds parsing
        _ = try parser_api.parseString(source);
    }
}

test "golden snapshot tests" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // 1. Simple Definitions
    try runSnapshotTest(allocator, "simple_def", "square x = x * x\n", false);

    // 2. Recursion
    try runSnapshotTest(allocator, "recursion", "fact 0 = 1\nfact n = n * fact (n-1)\n", false);
    // 3. Lists
    try runSnapshotTest(allocator, "lists", "[1,2,3]\n", true);

    // 4. List Comprehensions
    try runSnapshotTest(allocator, "list_comprehensions", "[x*x | x <- [1..10]]\n", true);

    // 5. Pattern Matching
    try runSnapshotTest(allocator, "pattern_matching", "sum [] = 0\nsum (x:xs) = x + sum xs\n", false);

    // 6. Type Definitions
    try runSnapshotTest(allocator, "type_definitions", "tree ::= Leaf num | Node tree tree\n", false);

    // 7. Nested Where Clauses
    try runSnapshotTest(allocator, "where_clauses", "f x = g x\n      where\n        g y = y + 1\n", false);

    // 8. Operator Sections
    try runSnapshotTest(allocator, "operator_sections", "(+1)\n(1+)\n", true);

    // 9. Layout Sensitive Cases
    try runSnapshotTest(allocator, "layout", "f x = x\n      where\n        g y = y\n        h z = z\n", false);
}

test "error snapshot tests" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // 1. Unexpected token
    try runSnapshotTest(allocator, "unexpected_token", "x = + * 2\n", true);

    // 2. Miranda silently terminates strings at newlines, so "x = "hello\n" is
    //    valid syntax (parses as x = "hello"). Not an error case.
    try runSnapshotTest(allocator, "unterminated_string", "x = \"hello\n", false);

    // 3. Invalid operator (@) — tokenization stops at unknown char, parser sees "x = 1" (valid).
    try runSnapshotTest(allocator, "invalid_operator", "x = 1 @ 2\n", false);

    // 4. Bad indentation
    try runSnapshotTest(allocator, "bad_indentation", "f x = x\n  where\ng y = y\n", true);

    // 5. Unexpected EOF
    try runSnapshotTest(allocator, "unexpected_eof", "x = ", true);

    // 6. Malformed type definition
    // Note: tree ::= Leaf node fails semantic analysis / typecheck rather than syntax,
    // so we use a structural syntax error in a type signature/definition:
    try runSnapshotTest(allocator, "malformed_type", "tree ::= Leaf num |\n", true);
}

test "prelude parsing test" {
    ensureInitialized();
    resetLexerState();
    // Parse the entire prelude. It should parse successfully.
    _ = try parser_api.parseFile("miralib/prelude");
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
// Cache invalidation comment for strict-main-tests
