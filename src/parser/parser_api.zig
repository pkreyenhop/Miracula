const std = @import("std");
const ast = @import("ast.zig");
const Parser = @import("parser.zig").Parser;
const TokenFilter = @import("token_filter.zig").TokenFilter;
const Diagnostics = @import("diagnostics.zig").Diagnostics;

pub const ParseError = error{
    SyntaxError,
    ParseFailed,
};

pub const ParseResult = enum {
    success,
};

const clib = @cImport({
    @cInclude("parser_bridge.h");
    @cInclude("data.h");
});

extern var hd: [*]clib.word;
extern var fileq: clib.word;
extern fn openfile(n: [*:0]const u8) c_int;
extern var SYNERR: clib.word;

inline fn h(x: clib.word) clib.word {
    return hd[@as(usize, @intCast(x)) * 2];
}

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
            var parser = Parser.init(std.heap.page_allocator);
            defer parser.deinit();
            _ = parser.parseModule() catch |err| {
                if (err == error.SyntaxError) {
                    return ParseError.SyntaxError;
                }
                return ParseError.ParseFailed;
            };
            if (parser.diags.has_errors) {
                return ParseError.SyntaxError;
            }
            return .success;
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
            var res = try parseWithNewFile(std.heap.page_allocator, filename);
            res.deinit();
            return .success;
        },
    }
}

/// Parses a script string.
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
            var res = try parseWithNew(std.heap.page_allocator, source);
            res.deinit();
            return .success;
        },
    }
}

/// Sets up lexer state for a string.
pub fn lexSetupString(source: [*:0]const u8) void {
    clib.mira_lex_setup_string(source);
}

/// Cleans up the lexer state.
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

pub const NewParseResult = struct {
    module: ast.Module,
    arena: std.heap.ArenaAllocator,

    pub fn deinit(self: *NewParseResult) void {
        self.arena.deinit();
    }
};

pub fn parseWithNew(allocator: std.mem.Allocator, source: [*:0]const u8) ParseError!NewParseResult {
    lexSetupString(source);
    defer lexCleanup();

    var arena = std.heap.ArenaAllocator.init(allocator);
    errdefer arena.deinit();

    var parser = Parser{
        .arena = arena,
        .filter = TokenFilter.init(arena.allocator()),
        .diags = Diagnostics.init(allocator),
    };
    defer parser.diags.deinit();

    const module = parser.parseModule() catch |err| {
        if (err == error.SyntaxError) {
            return ParseError.SyntaxError;
        }
        return ParseError.ParseFailed;
    };
    if (parser.diags.has_errors) {
        return ParseError.SyntaxError;
    }

    return NewParseResult{
        .module = module,
        .arena = parser.arena,
    };
}

pub fn parseWithNewFile(allocator: std.mem.Allocator, filename: [*:0]const u8) ParseError!NewParseResult {
    if (openfile(filename) == 0) {
        return ParseError.ParseFailed;
    }
    clib.s_in = @as(?*clib.FILE, @ptrFromInt(@as(usize, @intCast(h(h(fileq))))));

    var arena = std.heap.ArenaAllocator.init(allocator);
    errdefer arena.deinit();

    var parser = Parser{
        .arena = arena,
        .filter = TokenFilter.init(arena.allocator()),
        .diags = Diagnostics.init(allocator),
    };
    defer parser.diags.deinit();

    const module = parser.parseModule() catch |err| {
        if (err == error.SyntaxError) {
            return ParseError.SyntaxError;
        }
        return ParseError.ParseFailed;
    };
    if (parser.diags.has_errors) {
        return ParseError.SyntaxError;
    }

    return NewParseResult{
        .module = module,
        .arena = parser.arena,
    };
}
