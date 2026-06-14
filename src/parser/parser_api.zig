const std = @import("std");

const clib = @cImport({
    @cInclude("parser_bridge.h");
    @cInclude("data.h");
});

const lex_bridge = @import("lex_bridge.zig");
const parser_mod = @import("parser.zig");
const codegen = @import("codegen.zig");

extern var SYNERR: clib.word;

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
            // Phase 8: wire the Zig parser here once the lexer bridge is ready.
            return ParseError.ParseFailed;
        },
    }
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
            // Phase 8: wire the Zig parser here once the lexer bridge is ready.
            return ParseError.ParseFailed;
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
pub fn parseWithNew(gpa: std.mem.Allocator, source: [*:0]const u8) ParseError!NewParseResult {
    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    const alloc = arena.allocator();

    const source_span: [:0]const u8 = std.mem.span(source);
    const tokens = lex_bridge.tokenize(alloc, source_span) catch return ParseError.ParseFailed;

    var p = parser_mod.Parser.init(alloc, tokens);
    const script = parser_mod.parseScript(&p) catch return ParseError.ParseFailed;

    codegen.codegenScript(alloc, script);

    return NewParseResult{};
}
