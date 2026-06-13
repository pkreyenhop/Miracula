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
extern var files: clib.word;
extern fn reset_pns() void;

fn make_fil_record(name: [*:0]const u8) clib.word {
    const name_word = @as(clib.word, @intCast(@intFromPtr(name)));
    const file_info = clib.make(clib.FILEINFO, name_word, 0);
    const share_cell = clib.make(clib.CONS, 1, clib.NIL);
    const info_cell = clib.make(clib.CONS, file_info, share_cell);
    return clib.make(clib.CONS, info_cell, clib.NIL);
}

extern fn reset_state() void;
extern var col: clib.word;
extern var line_no: clib.word;
extern var c: clib.word;
extern var SYNERR: clib.word;

fn resetLexerState() void {
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
}

var initialized = false;
fn ensureInitialized() void {
    if (!initialized) {
        setupheap();
        setupdic();
        reset_pns();
        current_file = make_fil_record("test.m");
        files = clib.make(clib.CONS, current_file, clib.NIL);
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
    std.debug.print("--- SNAPSHOT TEST START: {s} ---\n", .{name});
    std.debug.print("[{s}] captureTokenStream starting...\n", .{name});
    const tokens = try captureTokenStream(allocator, source);
    defer allocator.free(tokens);
    std.debug.print("[{s}] captureTokenStream done.\n", .{name});

    // Parse result
    var parse_res: []const u8 = "SUCCESS";
    resetLexerState();
    std.debug.print("[{s}] parseString (1) starting...\n", .{name});
    _ = parser_api.parseString(source) catch {
        parse_res = "SYNTAX_ERROR";
    };
    std.debug.print("[{s}] parseString (1) done: {s}.\n", .{ name, parse_res });

    var diag = std.array_list.Managed(u8).init(allocator);
    defer diag.deinit();
    try diag.print("PARSE_RESULT: {s}\n\nTOKENS:\n{s}", .{ parse_res, tokens });

    // Snapshot path
    const snapshot_dir = "tests/parser/snapshots";
    const path = try std.fmt.allocPrint(allocator, "{s}/{s}.snapshot", .{ snapshot_dir, name });
    defer allocator.free(path);

    const update = (clib.getenv("UPDATE_SNAPSHOTS") != null);

    if (update) {
        std.debug.print("[{s}] writing snapshot...\n", .{name});
        try std.Io.Dir.cwd().createDirPath(testing.io, snapshot_dir);
        const file = try std.Io.Dir.cwd().createFile(testing.io, path, .{});
        defer file.close(testing.io);
        try file.writeStreamingAll(testing.io, diag.items);
    } else {
        std.debug.print("[{s}] comparing snapshot...\n", .{name});
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
        std.debug.print("[{s}] expectError starting...\n", .{name});
        // Assert it fails parsing
        try testing.expectError(parser_api.ParseError.SyntaxError, parser_api.parseString(source));
        std.debug.print("[{s}] expectError done.\n", .{name});
    } else {
        std.debug.print("[{s}] parseString (2) starting...\n", .{name});
        // Assert it succeeds parsing
        _ = try parser_api.parseString(source);
        std.debug.print("[{s}] parseString (2) done.\n", .{name});
    }
    std.debug.print("--- SNAPSHOT TEST END: {s} ---\n", .{name});
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
    resetLexerState();
    // Parse the entire prelude. It should parse successfully.
    _ = try parser_api.parseFile("miralib/prelude");
}

fn runASTSnapshotTest(allocator: std.mem.Allocator, name: []const u8, source: [:0]const u8) !void {
    ensureInitialized();
    resetLexerState();

    var res = try parser_api.parseWithNew(allocator, source);
    defer res.deinit();
    const module = res.module;
    
    var ast_str = std.array_list.Managed(u8).init(allocator);
    defer ast_str.deinit();
    
    const ASTWriter = struct {
        list: *std.array_list.Managed(u8),

        pub fn print(self: @This(), comptime fmt: []const u8, args: anytype) !void {
            try self.list.print(fmt, args);
        }

        pub fn writeAll(self: @This(), bytes: []const u8) !void {
            try self.list.appendSlice(bytes);
        }
    };
    const writer = ASTWriter{ .list = &ast_str };
    for (module.definitions, 0..) |def, i| {
        if (i > 0) try writer.writeAll("\n");
        const ast = @import("ast.zig");
        try ast.formatDefinition(def, writer);
    }
    try writer.writeAll("\n");

    const snapshot_dir = "tests/parser/new_parser";
    const path = try std.fmt.allocPrint(allocator, "{s}/{s}.snapshot", .{ snapshot_dir, name });
    defer allocator.free(path);

    const update = (clib.getenv("UPDATE_SNAPSHOTS") != null);

    if (update) {
        try std.Io.Dir.cwd().createDirPath(testing.io, snapshot_dir);
        const file = try std.Io.Dir.cwd().createFile(testing.io, path, .{});
        defer file.close(testing.io);
        try file.writeStreamingAll(testing.io, ast_str.items);
    } else {
        const file = std.Io.Dir.cwd().openFile(testing.io, path, .{}) catch |err| {
            std.debug.print("\nAST Snapshot file not found: {s}. Run with UPDATE_SNAPSHOTS=1 to create.\n", .{path});
            return err;
        };
        defer file.close(testing.io);
        var buf: [4096]u8 = undefined;
        const amt = try file.readPositionalAll(testing.io, &buf, 0);
        const expected = buf[0..amt];
        try testing.expectEqualStrings(expected, ast_str.items);
    }
}

test "new parser AST snapshot tests" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    try runASTSnapshotTest(allocator, "simple_def", "square x = x * x\n");
    try runASTSnapshotTest(allocator, "id", "id x = x\n");
    try runASTSnapshotTest(allocator, "double", "double x = x + x\n");
    try runASTSnapshotTest(allocator, "inc", "inc = (+1)\n");
    try runASTSnapshotTest(allocator, "main", "main = square 5\n");
}

