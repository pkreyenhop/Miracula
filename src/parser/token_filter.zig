const std = @import("std");

const clib = @cImport({
    @cInclude("data.h");
    @cInclude("parser_bridge.h");
});

extern var yylval: clib.word;
extern var line_no: clib.word;
extern var col: clib.word;
extern var dicp: [*:0]u8;
extern fn yylex() c_int;

pub const TokenId = enum(u32) {
    eof = 0,
    value = 257,
    eval = 258,
    where = 259,
    @"if" = 260,
    to = 261,
    leftarrow = 262,
    coloncolon = 263,
    colon2eq = 264,
    typevar = 265,
    name = 266,
    cname = 267,
    const_val = 268,
    dollars = 269,
    offside = 270,
    elseq = 271,
    abstype = 272,
    with = 273,
    diag = 274,
    eqeq = 275,
    free = 276,
    include = 277,
    export_val = 278,
    type = 279,
    otherwise = 280,
    showsym = 281,
    pathname = 282,
    bnf = 283,
    lex = 284,
    endir = 285,
    errorsy = 286,
    endsy = 287,
    emptysy = 288,
    readvalsy = 289,
    lexdef = 290,
    charclass = 291,
    anticharclass = 292,
    lbegin = 293,
    arrow = 294,
    plusplus = 295,
    minusminus = 296,
    dotdot = 297,
    vel = 298,
    ge = 299,
    ne = 300,
    le = 301,
    rem = 302,
    div = 303,
    infixname = 304,
    infixcname = 305,
    
    // Single characters
    plus = '+',
    minus = '-',
    times = '*',
    slash = '/',
    equals = '=',
    lparen = '(',
    rparen = ')',
    lbracket = '[',
    rbracket = ']',
    comma = ',',
    semicolon = ';',
    dollar = '$',
    hash = '#',
    
    _,
};

pub const Token = struct {
    id: TokenId,
    value: clib.word,
    text: []const u8,
    line: usize,
    column: usize,
};

pub const TokenFilter = struct {
    allocator: std.mem.Allocator,
    peeked: ?Token = null,

    pub fn init(allocator: std.mem.Allocator) TokenFilter {
        return .{
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *TokenFilter) void {
        if (self.peeked) |tok| {
            self.allocator.free(tok.text);
        }
    }

extern var hd: [*]clib.word;
extern var tag: [*]u8;

inline fn h(x: clib.word) clib.word {
    return hd[@as(usize, @intCast(x)) * 2];
}

inline fn get_id(x: clib.word) [*:0]const u8 {
    return @ptrFromInt(@as(usize, @intCast(h(h(h(x))))));
}

    /// Retrieve the next raw token from the lexer.
    fn nextRawToken(self: *TokenFilter) !Token {
        const tid_int = yylex();
        const tid: TokenId = @enumFromInt(@as(u32, @intCast(tid_int)));
        
        var text: []const u8 = "";
        switch (tid) {
            .name, .cname, .infixname, .infixcname => {
                const text_ptr = get_id(yylval);
                const text_len = std.mem.len(text_ptr);
                text = try self.allocator.dupe(u8, text_ptr[0..text_len]);
            },
            .const_val => {
                const text_ptr = dicp;
                const text_len = std.mem.len(text_ptr);
                text = try self.allocator.dupe(u8, text_ptr[0..text_len]);
            },
            else => {
                const val = @intFromEnum(tid);
                if (val < 256) {
                    const char_buf = try self.allocator.alloc(u8, 1);
                    char_buf[0] = @intCast(val);
                    text = char_buf;
                } else {
                    const text_ptr = dicp;
                    const text_len = std.mem.len(text_ptr);
                    text = try self.allocator.dupe(u8, text_ptr[0..text_len]);
                }
            }
        }

        return Token{
            .id = tid,
            .value = yylval,
            .text = text,
            .line = @intCast(line_no),
            .column = @intCast(col),
        };
    }

    /// Peeks at the next token.
    pub fn peek(self: *TokenFilter) !Token {
        if (self.peeked) |tok| {
            return tok;
        }
        const tok = try self.nextRawToken();
        self.peeked = tok;
        return tok;
    }

    /// Advances the stream and returns the next token.
    pub fn next(self: *TokenFilter) !Token {
        if (self.peeked) |tok| {
            self.peeked = null;
            return tok;
        }
        return try self.nextRawToken();
    }
    
    /// Frees resources associated with a token.
    pub fn freeToken(self: *TokenFilter, token: Token) void {
        self.allocator.free(token.text);
    }
};
