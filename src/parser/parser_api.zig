//! parser_api.zig — the entry points that drive parsing.
//!
//! Bridges the REPL/loader to both pipelines: `parseCurrent`/`parseString` run
//! the legacy lexer + grammar (the production path that feeds `evaluateRepl`),
//! while `parseWithNew` runs the new Zig lexer→parser→codegen pipeline. Also
//! re-exports the lexer string setup (`lexSetupString`/`lexCleanup`).

const std = @import("std");
const heap = @import("../runtime/heap.zig");
const options = @import("version_options");

const word = @import("../runtime/word.zig");
const rt = @import("../runtime/runtime_state.zig");
const core = @import("../runtime/core_state.zig");
const compiler_state = @import("../compiler/compiler_state.zig");

const lex_bridge = @import("lex_bridge.zig");
const parser_mod = @import("parser.zig");
const codegen = @import("codegen.zig");
const repl = @import("../driver/repl.zig");
const lex = @import("lex.zig");
const setupString = lex.setupString;
const cleanup = lex.cleanup;
const setupFile = lex.setupFile;
// Forks like the original C evaluate(): compiling=0 only in child; parent's heap is safe.
const evaluateRepl = repl.evaluateRepl;
/// Errors the parse entry points can return.
pub const ParseError = error{
    SyntaxError,
    ParseFailed,
};

/// The outcome of a successful parse.
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
    if (options.is_strict) {
        if (rt.rs.current_script) |script_name| {
            validateUtf8File(script_name) catch |err| {
                core.s.SYNERR = 1;
                return err;
            };
        }
    }
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
        if (options.is_strict or @import("builtin").mode == .Debug) {
            heap.heap.validate();
            p.validate();
            rt.rs.validate();
        }
        if (!p.ts.check(.eof) and !p.ts.check(.offside)) {
            // Trailing tokens after the expression — treat as syntax error.
            core.s.SYNERR = 1;
            _ = word.print("syntax error - unexpected token\n", .{.{}});
            return ParseError.SyntaxError;
        }
        const expr_word = codegen.codegenExpr(alloc, expr);
        if (options.is_strict or @import("builtin").mode == .Debug) {
            heap.heap.validate();
            p.validate();
            rt.rs.validate();
        }
        rt.rs.lastexp = expr_word; // anchor as GC root before typeOf() inside evaluateRepl() can trigger GC
        evaluateRepl(heap.heap, core.s, compiler_state.cs, expr_word);
        // Child prints newline before exit(0); parent returns here.
        return .success;
    }

    const script = parser_mod.parseScript(&p) catch return ParseError.ParseFailed;
    if (options.is_strict or @import("builtin").mode == .Debug) {
        heap.heap.validate();
        p.validate();
        rt.rs.validate();
    }

    if (!@import("builtin").is_test) {
        for (p.diagnostics.items) |d| {
            std.debug.print("{d}:{d}: {s}\n", .{ d.span.line, d.span.col, d.message });
        }
    }
    if (p.diagnostics.items.len > 0) {
        core.s.SYNERR = 1;
        core.s.errline = @intCast(p.diagnostics.items[0].span.line);
        core.s.errcol = @intCast(p.diagnostics.items[0].span.col);
        return ParseError.SyntaxError;
    }

    codegen.codegenScript(alloc, script);
    if (options.is_strict or @import("builtin").mode == .Debug) {
        heap.heap.validate();
        p.validate();
        rt.rs.validate();
    }
    return .success;
}
fn validateUtf8File(filename: [*:0]const u8) ParseError!void {
    const io = std.Options.debug_io;
    const dir = std.Io.Dir.cwd();
    const file = dir.openFile(io, std.mem.span(filename), .{}) catch return ParseError.ParseFailed;
    defer file.close(io);

    const file_len = file.length(io) catch return ParseError.ParseFailed;
    if (file_len > 10 * 1024 * 1024) return ParseError.ParseFailed;

    const alloc = std.heap.page_allocator;
    const file_bytes = alloc.alloc(u8, @intCast(file_len)) catch return ParseError.ParseFailed;
    defer alloc.free(file_bytes);

    _ = file.readPositionalAll(io, file_bytes, 0) catch return ParseError.ParseFailed;

    if (!std.unicode.utf8ValidateSlice(file_bytes)) {
        std.debug.print("UTF-8 validation failed for file: {s}\n", .{filename});
        return ParseError.ParseFailed;
    }
}

/// Parses a script file by filename.
pub fn parseFile(filename: [*:0]const u8) ParseError!ParseResult {
    if (options.is_strict) {
        try validateUtf8File(filename);
    }
    if (setupFile(heap.heap, filename) == 0) {
        return ParseError.ParseFailed;
    }
    return parseCurrentNew();
}

/// Parses a source string.
pub fn parseString(source: [*:0]const u8) ParseError!ParseResult {
    if (options.is_strict) {
        const source_slice = std.mem.span(source);
        if (!std.unicode.utf8ValidateSlice(source_slice)) {
            std.debug.print("UTF-8 validation failed for source string\n", .{});
            core.s.SYNERR = 1;
            return ParseError.ParseFailed;
        }
    }
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    _ = try parseWithNew(arena.allocator(), source);
    return .success;
}

/// Point the legacy lexer at the in-memory `source` string (wraps `lex.setupString`).
pub fn lexSetupString(source: [*:0]const u8) void {
    setupString(source);
}

/// Tear down the lexer's string setup (wraps `lex.cleanup`).
pub fn lexCleanup() void {
    cleanup();
}

/// Result of parsing with the new Zig pipeline.
pub const NewParseResult = struct {
    /// No-op cleanup — the result owns no heap memory of its own.
    pub fn deinit(_: *NewParseResult) void {}
};

/// Parse a Miranda source string through the Zig lexer bridge + recursive-descent parser.
/// Uses an arena so all intermediate allocations are freed on return.
/// On parse errors, diagnostics are printed to stderr and SYNERR is set.
pub fn parseWithNew(gpa: std.mem.Allocator, source: [*:0]const u8) ParseError!NewParseResult {
    if (options.is_strict) {
        const source_slice = std.mem.span(source);
        if (!std.unicode.utf8ValidateSlice(source_slice)) {
            std.debug.print("UTF-8 validation failed for source string\n", .{});
            core.s.SYNERR = 1;
            return ParseError.ParseFailed;
        }
    }
    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    const alloc = arena.allocator();

    const source_span: [:0]const u8 = std.mem.span(source);
    const tokens = lex_bridge.tokenize(alloc, source_span) catch return ParseError.ParseFailed;

    var p = parser_mod.Parser.init(alloc, tokens);
    const script = parser_mod.parseScript(&p) catch return ParseError.ParseFailed;
    if (options.is_strict or @import("builtin").mode == .Debug) {
        heap.heap.validate();
        p.validate();
        rt.rs.validate();
    }

    // Report accumulated diagnostics before the arena is freed.
    if (!@import("builtin").is_test) {
        for (p.diagnostics.items) |d| {
            std.debug.print("{d}:{d}: {s}\n", .{ d.span.line, d.span.col, d.message });
        }
    }
    if (p.diagnostics.items.len > 0) {
        core.s.SYNERR = 1;
        core.s.errline = @intCast(p.diagnostics.items[0].span.line);
        core.s.errcol = @intCast(p.diagnostics.items[0].span.col);
        return ParseError.ParseFailed;
    }

    codegen.codegenScript(alloc, script);
    if (options.is_strict or @import("builtin").mode == .Debug) {
        heap.heap.validate();
        p.validate();
        rt.rs.validate();
    }

    return NewParseResult{};
}
