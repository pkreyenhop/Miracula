const std = @import("std");

const word = @import("../runtime/word.zig");
const main = @import("../main.zig");
const core = @import("../runtime/core_state.zig");

const lex_bridge = @import("lex_bridge.zig");
const parser_mod = @import("parser.zig");
const codegen = @import("codegen.zig");
const r7_repl = @import("../driver/repl.zig");
const r7_lex = @import("lex.zig");
const mira_lex_setup_string = r7_lex.mira_lex_setup_string;
const mira_lex_cleanup = r7_lex.mira_lex_cleanup;
const mira_lex_setup_file = r7_lex.mira_lex_setup_file;
// Forks like the original C evaluate(): compiling=0 only in child; parent's heap is safe.
const evaluateRepl = r7_repl.evaluateRepl;
pub const ParseError = error{
    SyntaxError,
    ParseFailed,
};

pub const ParseResult = enum {
    success,
};

/// Parses the currently active stream.
pub fn parseCurrent() ParseError!ParseResult {
    return parseCurrentNew();
}

/// Run the Zig pipeline on the currently active Miranda lex stream.
/// s_in must already be opened (e.g. by openfile() in lex.zig).
fn parseCurrentNew() ParseError!ParseResult {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const tokens = lex_bridge.tokenizeCurrent(alloc) catch return ParseError.ParseFailed;

    var p = parser_mod.Parser.init(alloc, tokens);

    // Command mode: the user typed an expression at the REPL prompt.
    // In the old YACC grammar this was handled by `EVAL exp { evaluate($2); }`.
    // We parse one expression, codegen it, then fork via evaluateRepl().
    if (core.s.commandmode != 0) {
        const expr = parser_mod.parseExpr(&p) catch |err| {
            core.s.SYNERR = 1;
            if (err == error.UnexpectedEof) {
                _ = word.print("syntax error - unexpected newline\n", .{.{}});
            } else {
                _ = word.print("syntax error - unexpected token\n", .{.{}});
            }
            return ParseError.SyntaxError;
        };
        if (!p.ts.check(.eof) and !p.ts.check(.offside)) {
            // Trailing tokens after the expression — treat as syntax error.
            core.s.SYNERR = 1;
            _ = word.print("syntax error - unexpected token\n", .{.{}});
            return ParseError.SyntaxError;
        }
        const expr_word = codegen.codegenExpr(alloc, expr);
        main.rs.lastexp = expr_word; // anchor as GC root before type_of() inside evaluateRepl() can trigger GC
        evaluateRepl(expr_word);
        // Child prints newline before exit(0); parent returns here.
        return .success;
    }

    const script = parser_mod.parseScript(&p) catch return ParseError.ParseFailed;

    for (p.diagnostics.items) |d| {
        std.debug.print("{d}:{d}: {s}\n", .{ d.span.line, d.span.col, d.message });
    }
    if (p.diagnostics.items.len > 0) {
        core.s.SYNERR = 1;
        return ParseError.SyntaxError;
    }

    codegen.codegenScript(alloc, script);
    return .success;
}

/// Parses a script file by filename.
pub fn parseFile(filename: [*:0]const u8) ParseError!ParseResult {
    if (mira_lex_setup_file(filename) == 0) {
        return ParseError.ParseFailed;
    }
    return parseCurrentNew();
}

/// Parses a source string.
pub fn parseString(source: [*:0]const u8) ParseError!ParseResult {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    _ = try parseWithNew(arena.allocator(), source);
    return .success;
}

pub fn lexSetupString(source: [*:0]const u8) void {
    mira_lex_setup_string(source);
}

pub fn lexCleanup() void {
    mira_lex_cleanup();
}

/// Result of parsing with the new Zig pipeline.
pub const NewParseResult = struct {
    pub fn deinit(_: *NewParseResult) void {}
};

/// Parse a Miranda source string through the Zig lexer bridge + recursive-descent parser.
/// Uses an arena so all intermediate allocations are freed on return.
/// On parse errors, diagnostics are printed to stderr and SYNERR is set.
pub fn parseWithNew(gpa: std.mem.Allocator, source: [*:0]const u8) ParseError!NewParseResult {
    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    const alloc = arena.allocator();

    const source_span: [:0]const u8 = std.mem.span(source);
    const tokens = lex_bridge.tokenize(alloc, source_span) catch return ParseError.ParseFailed;

    var p = parser_mod.Parser.init(alloc, tokens);
    const script = parser_mod.parseScript(&p) catch return ParseError.ParseFailed;

    // Report accumulated diagnostics before the arena is freed.
    for (p.diagnostics.items) |d| {
        std.debug.print("{d}:{d}: {s}\n", .{ d.span.line, d.span.col, d.message });
    }
    if (p.diagnostics.items.len > 0) {
        core.s.SYNERR = 1;
        return ParseError.ParseFailed;
    }

    codegen.codegenScript(alloc, script);

    return NewParseResult{};
}
