const std = @import("std");

const clib = @cImport({
    @cInclude("parser_bridge.h");
    @cInclude("data.h");
});

const lex_bridge = @import("lex_bridge.zig");
const parser_mod = @import("parser.zig");
const codegen = @import("codegen.zig");

extern var SYNERR: clib.word;
extern var commandmode: clib.word;

pub const ParseError = error{
    SyntaxError,
    ParseFailed,
};

pub const ParseResult = enum {
    success,
};

pub const ParserMode = enum {
    legacy,
    new,
};

pub var parser_mode: ParserMode = .legacy;

/// Parses the currently active stream.
pub fn parseCurrent() ParseError!ParseResult {
    switch (parser_mode) {
        .legacy => {
            const res = clib.mira_parse_current();
            if (res != 0 or SYNERR != 0) {
                return ParseError.SyntaxError;
            }
            return .success;
        },
        .new => {
            // REPL (commandmode != 0) stays on legacy: the interactive parser
            // uses Miranda's line-by-line protocol which the Zig pipeline does
            // not yet replicate.
            if (commandmode != 0) {
                const res = clib.mira_parse_current();
                if (res != 0 or SYNERR != 0) return ParseError.SyntaxError;
                return .success;
            }
            return parseCurrentNew();
        },
    }
}

/// Run the Zig pipeline on the currently active Miranda lex stream.
/// s_in must already be opened (e.g. by openfile() in lex.zig).
fn parseCurrentNew() ParseError!ParseResult {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const tokens = lex_bridge.tokenizeCurrent(alloc) catch return ParseError.ParseFailed;

    var p = parser_mod.Parser.init(alloc, tokens);
    const script = parser_mod.parseScript(&p) catch return ParseError.ParseFailed;

    for (p.diagnostics.items) |d| {
        std.debug.print("{d}:{d}: {s}\n", .{ d.span.line, d.span.col, d.message });
    }
    if (p.diagnostics.items.len > 0) {
        SYNERR = 1;
        return ParseError.SyntaxError;
    }

    codegen.codegenScript(alloc, script);
    return .success;
}

/// Parses a script file by filename.
pub fn parseFile(filename: [*:0]const u8) ParseError!ParseResult {
    switch (parser_mode) {
        .legacy => {
            const res = clib.mira_parse_file(filename);
            if (res != 0 or SYNERR != 0) {
                return ParseError.SyntaxError;
            }
            return .success;
        },
        .new => {
            // Phase 8: wire the Zig parser here once the lexer bridge is ready.
            return ParseError.ParseFailed;
        },
    }
}

/// Parses a source string.
pub fn parseString(source: [*:0]const u8) ParseError!ParseResult {
    switch (parser_mode) {
        .legacy => {
            const res = clib.mira_parse_string(source);
            if (res != 0 or SYNERR != 0) {
                return ParseError.SyntaxError;
            }
            return .success;
        },
        .new => {
            var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
            defer arena.deinit();
            _ = try parseWithNew(arena.allocator(), source);
            return .success;
        },
    }
}

pub fn lexSetupString(source: [*:0]const u8) void {
    clib.mira_lex_setup_string(source);
}

pub fn lexCleanup() void {
    clib.mira_lex_cleanup();
}

pub fn parseWithLegacy(source: [*:0]const u8) ParseError!ParseResult {
    const res = clib.mira_parse_string(source);
    if (res != 0 or SYNERR != 0) {
        return ParseError.SyntaxError;
    }
    return .success;
}

/// Result of parsing with the new Zig pipeline. Phase 10 will expose the AST.
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
        SYNERR = 1;
        return ParseError.ParseFailed;
    }

    codegen.codegenScript(alloc, script);

    return NewParseResult{};
}
