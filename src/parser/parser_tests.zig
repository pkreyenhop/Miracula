const std = @import("std");
const parser_api = @import("parser_api.zig");
const testing = std.testing;

extern fn setupheap() void;
extern fn setupdic() void;
extern fn yylex() c_int;
extern var dicp: [*:0]u8;
extern var yylval: clib.word;

const clib = @cImport({
    @cInclude("parser_bridge.h");
    @cInclude("data.h");
    @cInclude("y.tab.h");
});

extern fn make_id(n: [*:0]const u8) clib.word;
extern var current_file: clib.word;

extern fn reset_state() void;
extern var col: clib.word;
extern var line_no: clib.word;
extern var c: clib.word;
extern var SYNERR: clib.word;

fn resetLexerState() void {
    reset_state();
    setupheap();
    setupdic();
    current_file = make_id("test.m");
    col = 0;
    line_no = 0;
    c = ' ';
    SYNERR = 0;
}

var initialized = false;
fn ensureInitialized() void {
    if (!initialized) {
        setupheap();
        setupdic();
        current_file = make_id("test.m");
        initialized = true;
    }
}

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

fn captureTokenStream(allocator: std.mem.Allocator, source: [:0]const u8) ![]const u8 {
    ensureInitialized();
    resetLexerState();
    parser_api.lexSetupString(source);
    defer parser_api.lexCleanup();

    var list = std.array_list.Managed(u8).init(allocator);
    errdefer list.deinit();

    while (true) {
        const tok = yylex();
        if (tok == 0 or tok == clib.END) break;

        const name = tokenName(tok);
        const lexeme = std.mem.span(dicp);
        
        try list.print("{s}", .{name});
        if (lexeme.len > 0) {
            // For safety, only print clean ASCII lexemes
            var all_ascii = true;
            for (lexeme) |ch| {
                if (ch < 32 or ch > 126) {
                    all_ascii = false;
                    break;
                }
            }
            if (all_ascii) {
                try list.print("(\"{s}\")", .{lexeme});
            }
        }
        try list.print("\n", .{});
    }
    return try list.toOwnedSlice();
}

fn runSnapshotTest(allocator: std.mem.Allocator, name: []const u8, source: [:0]const u8, is_error: bool) !void {
    const tokens = try captureTokenStream(allocator, source);
    defer allocator.free(tokens);

    // Parse result
    var parse_res: []const u8 = "SUCCESS";
    resetLexerState();
    _ = parser_api.parseString(source) catch {
        parse_res = "SYNTAX_ERROR";
    };

    var diag = std.array_list.Managed(u8).init(allocator);
    defer diag.deinit();
    try diag.print("PARSE_RESULT: {s}\n\nTOKENS:\n{s}", .{ parse_res, tokens });

    // Snapshot path
    const snapshot_dir = "tests/parser/snapshots";
    const path = try std.fmt.allocPrint(allocator, "{s}/{s}.snapshot", .{ snapshot_dir, name });
    defer allocator.free(path);

    const update = (clib.getenv("UPDATE_SNAPSHOTS") != null);

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
        // Assert it fails parsing
        try testing.expectError(parser_api.ParseError.SyntaxError, parser_api.parseString(source));
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
    try runSnapshotTest(allocator, "lists", "[1,2,3]\n", false);

    // 4. List Comprehensions
    try runSnapshotTest(allocator, "list_comprehensions", "[x*x | x <- [1..10]]\n", false);

    // 5. Pattern Matching
    try runSnapshotTest(allocator, "pattern_matching", "sum [] = 0\nsum (x:xs) = x + sum xs\n", false);

    // 6. Type Definitions
    try runSnapshotTest(allocator, "type_definitions", "tree ::= Leaf num | Node tree tree\n", false);

    // 7. Nested Where Clauses
    try runSnapshotTest(allocator, "where_clauses", "f x = g x\n  where\n    g y = y + 1\n", false);

    // 8. Operator Sections
    try runSnapshotTest(allocator, "operator_sections", "(+1)\n(1+)\n", false);

    // 9. Layout Sensitive Cases
    try runSnapshotTest(allocator, "layout", "f x = x\n  where\n    g y = y\n    h z = z\n", false);
}

test "error snapshot tests" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // 1. Unexpected token
    try runSnapshotTest(allocator, "unexpected_token", "x = + * 2\n", true);

    // 2. Unterminated string
    try runSnapshotTest(allocator, "unterminated_string", "x = \"hello\n", true);

    // 3. Invalid operator
    try runSnapshotTest(allocator, "invalid_operator", "x = 1 @ 2\n", true);

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
    // Parse the entire prelude. It should parse successfully.
    _ = try parser_api.parseFile("miralib/prelude");
}
