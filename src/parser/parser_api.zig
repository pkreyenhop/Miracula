const std = @import("std");

const clib = @cImport({
    @cInclude("parser_bridge.h");
    @cInclude("data.h");
});

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

/// Stub return type for parseWithNew — Phase 8 will populate this properly.
pub const NewParseResult = struct {
    pub fn deinit(_: *NewParseResult) void {}
};

/// Phase 8 stub: returns ParseFailed until the Zig lexer bridge is wired.
pub fn parseWithNew(_: std.mem.Allocator, _: [*:0]const u8) ParseError!NewParseResult {
    return ParseError.ParseFailed;
}
