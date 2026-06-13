const std = @import("std");

pub const ParseError = error{
    SyntaxError,
    ParseFailed,
};

pub const ParseResult = enum {
    success,
};

const clib = @cImport({
    @cInclude("parser_bridge.h");
});

/// Parses the currently active stream.
pub fn parseCurrent() ParseError!ParseResult {
    const res = clib.mira_parse_current();
    if (res != 0) {
        return ParseError.SyntaxError;
    }
    return .success;
}

/// Parses a script file by filename.
pub fn parseFile(filename: [*:0]const u8) ParseError!ParseResult {
    const res = clib.mira_parse_file(filename);
    if (res != 0) {
        return ParseError.SyntaxError;
    }
    return .success;
}

/// Parses a script string.
pub fn parseString(source: [*:0]const u8) ParseError!ParseResult {
    const res = clib.mira_parse_string(source);
    if (res != 0) {
        return ParseError.SyntaxError;
    }
    return .success;
}

/// Sets up lexer state for a string.
pub fn lexSetupString(source: [*:0]const u8) void {
    clib.mira_lex_setup_string(source);
}

/// Cleans up the lexer state.
pub fn lexCleanup() void {
    clib.mira_lex_cleanup();
}
