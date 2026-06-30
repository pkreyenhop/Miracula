//! lex.zig — the legacy hand-written lexer and identifier dictionary.
//!
//! `yylex` is the production token scanner that feeds the Yacc-style grammar:
//! it recognises names, numerals (decimal/hex/octal), strings, char classes,
//! and operators, applies the offside `layout` rule, and processes `%`
//! `directive`s. Owns the identifier dictionary (`setupdic`/`makeId`/`findid`/
//! `keep`), the private-name machinery (`makePn`/`mkprivate`), and the literate-
//! script margin handling. `convArgs`/`strConv` build Miranda values for the
//! runtime.

const std = @import("std");
const word = @import("../runtime/word.zig");
const errors = @import("../runtime/errors.zig");
const strtab = @import("../runtime/strtab.zig");
const lex_state = @import("lex_state.zig");
const ls = lex_state.ls;
const cs = @import("../compiler/compiler_state.zig").cs;
const heap = @import("../runtime/heap.zig");
const rt = @import("../runtime/runtime_state.zig");
const setup = @import("../compiler/setup.zig");
const types = @import("../compiler/types.zig");
const repl = @import("../driver/repl.zig");
const files = @import("../io/files.zig");
const big = @import("../runtime/big.zig");
const main_clib = @import("../runtime/main_clib.zig");
const core_state = @import("../runtime/core_state.zig");
const tu = @import("../testutil.zig"); // unit-test harness (test builds only)

const Word = i64;
const CMBASE = word.CMBASE;
const NIL = word.NIL;
const NILS = word.NILS;
const UNDEF = word.UNDEF;

const False = word.False;
const True = word.True;

const make = heap.make;
const mallocPanic = heap.mallocPanic;
const bigscan = big.scanDecimal;
const bigxscan = big.scanHex;
const bigoscan = big.scanOctal;
const stoDbl = heap.stoDbl;
const stoId = heap.stoId;
const stoChar = heap.stoChar;
const fileMtime = files.fileMtime;
const append1 = heap.append1;
const genlstatType = types.genlstatType;
const acterror = setup.acterror;
const syntax = setup.syntax;
const reset = repl.reset;
const isChar = heap.isChar;

/// Point the lexer at the in-memory `source` string.
pub fn setupString(source: [*:0]const u8) void {
    const len = std.mem.len(source);
    const f = word.fmemopen(@ptrCast(@constCast(source)), len, "r") orelse return;
    // FILE* handle stored in the cell (read back via @ptrFromInt below);
    // this is a FILE-handle-in-cell cast, not a node string — out of B1 scope.
    ls.fileq = cons(make(.STRCONS, @as(Word, @intCast(@intFromPtr(f))), NIL), ls.fileq);
    ls.insertdepth += 1;
    rt.rs.s_in = f;
}

/// Tear down the lexer's string/file setup.
pub fn cleanup() void {
    if (rt.rs.s_in) |f| {
        const is_stdio = (f == getStdin()) or (f == getStdout()) or (f == getStderr());
        if (!is_stdio) {
            _ = word.fclose(f);
            rt.rs.s_in = null;
        }
    }
}

/// Open `filename` and point the lexer at it; returns 0 on failure.
pub fn setupFile(filename: [*:0]const u8) c_int {
    if (openfile(filename) == 0) return 0;
    rt.rs.s_in = @ptrFromInt(@as(usize, @intCast(h(h(ls.fileq)))));
    return 1;
}

/// Allocate a `FILEINFO` cell `(file . line)`.
fn fileinfo(file: Word, line: Word) Word {
    return make(.FILEINFO, file, line);
}

/// Build a file record `(path, time, share, defs)`.
fn makeFil(path: [*:0]const u8, time: Word, share: Word, defs: Word) Word {
    return cons(cons(fileinfo(strtab.strBits(path), time), cons(share, NIL)), defs);
}

/// Allocate a `STARTREADVALS` node.
fn readvals(x: Word, y: Word) Word {
    return make(.STARTREADVALS, x, y);
}

/// Make a type-variable node with index `n`.
fn mktvar(n: Word) Word {
    return make(.TVAR, 0, n);
}

/// The standard-output `FILE` handle.
fn getStdout() ?*word.FILE {
    const T = @TypeOf(main_clib.stdout);
    if (comptime @typeInfo(T) == .@"fn") {
        return main_clib.stdout();
    } else if (comptime @typeInfo(T) == .pointer and @typeInfo(@typeInfo(T).pointer.child) == .@"fn") {
        return main_clib.stdout();
    } else {
        return main_clib.stdout;
    }
}

/// The standard-input `FILE` handle.
fn getStdin() ?*word.FILE {
    const T = @TypeOf(main_clib.stdin);
    if (comptime @typeInfo(T) == .@"fn") {
        return main_clib.stdin();
    } else if (comptime @typeInfo(T) == .pointer and @typeInfo(@typeInfo(T).pointer.child) == .@"fn") {
        return main_clib.stdin();
    } else {
        return main_clib.stdin;
    }
}

/// The standard-error `FILE` handle.
fn getStderr() ?*word.FILE {
    const T = @TypeOf(main_clib.stderr);
    if (comptime @typeInfo(T) == .@"fn") {
        return main_clib.stderr();
    } else if (comptime @typeInfo(T) == .pointer and @typeInfo(@typeInfo(T).pointer.child) == .@"fn") {
        return main_clib.stderr();
    } else {
        return main_clib.stderr;
    }
}

/// The node tag of cell `x`.
inline fn getTag(x: Word) word.NodeTag {
    return heap.heap.getTag(x);
}

/// Head (`hd`) of cell `x`.
fn h(x: Word) Word {
    return heap.heap.h(x);
}

/// Pointer to the head field of cell `x`.
fn hp(x: Word) *Word {
    return heap.heap.hp(x);
}

/// Tail (`tl`) of cell `x`.
fn t(x: Word) Word {
    return heap.heap.t(x);
}

/// Pointer to the tail field of cell `x`.
fn tp(x: Word) *Word {
    return heap.heap.tp(x);
}

/// Allocate a `CONS` cell `(x . y)`.
fn cons(x: Word, y: Word) Word {
    return make(.CONS, x, y);
}

/// Whether `x` names a data constructor.
fn isconstructor(x: Word) bool {
    return getTag(x) == .ID and isconstrname(getId(x));
}

/// The interned name text of id `x`.
fn getId(x: Word) [*:0]const u8 {
    return strtab.strOf(h(h(h(x))));
}

/// The path string of file record `x`.
fn getFil(x: Word) [*:0]const u8 {
    return strtab.strOf(h(h(h(x))));
}

/// Whether the current token text equals `s`.
fn is(s: [*:0]const u8) bool {
    return std.mem.eql(u8, std.mem.span(@as([*:0]u8, @ptrCast(ls.dicp))), std.mem.span(s));
}

/// Abort if the dictionary buffer has overflowed.
fn ovflocheck() void {
    const d_ptr = @as(usize, @intFromPtr(ls.dicq));
    const start_ptr = @as(usize, @intFromPtr(ls.dic));
    if (d_ptr - start_ptr > @as(usize, @intCast(rt.rs.DICSPACE))) {
        dicovflo();
    }
}

/// Handle dictionary overflow (report and abort).
pub fn dicovflo() void {
    errors.fatal("\npanic: dictionary overflow\n", .{.{}});
}

/// Allocate and initialise the identifier dictionary.
pub fn setupdic() void {
    const space = rt.rs.DICSPACE;
    if (ls.dic == null) {
        const dict_slice = rt.allocator.alloc(u8, @intCast(space)) catch mallocPanic("dictionary");
        ls.dic = dict_slice.ptr;

        const base_slice = rt.allocator.alloc(u8, @intCast(ls.prefixlimit)) catch mallocPanic("ls.prefixbase");
        ls.prefixbase = base_slice.ptr;
    }
    ls.dicp = @ptrCast(ls.dic.?);
    ls.dicq = @ptrCast(ls.dic.?);
    ls.prefixbase.?[0] = 0;
    ls.prefix = 0;
    @memset(&ls.namebucket, 0);
}

/// Resolve a `~`-relative path `n` against ``.
fn gethome(n: [*:0]const u8) ?[*:0]const u8 {
    if (n[0] == 0) {
        if (main_clib.getenv("HOME")) |h_dir| {
            return h_dir;
        }
        return null;
    }
    return null;
}

/// Read the next whitespace-delimited token into the dictionary buffer.
pub fn token() ?[*:0]u8 {
    var ch = main_clib.getchar();
    ls.dicq = ls.dicp; // uses top of dictionary as temporary work space
    while (ch == ' ' or ch == '\t') {
        ch = main_clib.getchar();
    }
    if (ch == '~') {
        ls.dicq[0] = @intCast(ch);
        ls.dicq += 1;
        ch = main_clib.getchar();
        while (word.isalnum(ch) or ch == '-' or ch == '_' or ch == '.') {
            ls.dicq[0] = @intCast(ch);
            ls.dicq += 1;
            ch = main_clib.getchar();
        }
        ls.dicq[0] = 0;
        if (gethome(ls.dicp + 1)) |h_dir| {
            _ = word.strcpy(ls.dicp, h_dir);
            ls.dicq = ls.dicp + word.strlen(ls.dicp);
        }
    }
    while (ch != main_clib.EOF and !word.isspace(ch)) {
        ls.dicq[0] = @intCast(ch);
        ls.dicq += 1;
        if (ch == '%') {
            const idx = @as(usize, @intFromPtr(ls.dicq)) - @as(usize, @intFromPtr(ls.dicp));
            if (idx >= 2 and (ls.dicq - 2)[0] == '\\') {
                (ls.dicq - 2)[0] = '%';
                ls.dicq -= 1;
            } else {
                ls.dicq -= 1;
                _ = word.strcpy(ls.dicq, rt.rs.current_script.?);
                ls.dicq += word.strlen(rt.rs.current_script.?);
            }
        }
        ch = main_clib.getchar();
    }
    ls.dicq[0] = 0;
    ls.dicq += 1;
    ovflocheck();
    while (ch == ' ' or ch == '\t') {
        ch = main_clib.getchar();
    }
    if (getStdin()) |stdin_file| {
        _ = main_clib.ungetc(ch, stdin_file);
    }
    if (ls.dicp[0] == 0) {
        return null;
    }
    return ls.dicp;
}

/// Append the Miranda source extension to name `s` (flag `b` selects the variant).
pub fn addextn(b: Word, s_input: [*:0]u8) [*:0]u8 {
    var s = s_input;
    var n: Word = @intCast(word.strlen(s));
    if (s[0] == '<' and s[@intCast(n - 1)] == '>') {
        var miralen: usize = 0;
        if (miralen == 0) {
            miralen = word.strlen(rt.rs.miralib.?);
        }
        _ = word.strcpy(&rt.rs.linebuf[0], rt.rs.miralib.?);
        rt.rs.linebuf[miralen] = '/';
        _ = word.strcpy(&rt.rs.linebuf[miralen + 1], s + 1);
        _ = word.strcpy(ls.dicp, &rt.rs.linebuf[0]);
        s = ls.dicp;
        n = n + @as(Word, @intCast(miralen)) - 1;
        ls.dicq = ls.dicp + @as(usize, @intCast(n + 1));
        (ls.dicq - 1)[0] = 0; // overwrites '>'
        ovflocheck();
    } else if (s[0] == '"' and s[@intCast(n - 1)] == '"') {
        ls.dicq = ls.dicp;
        var p = s + 1;
        while (p[0] != 0) {
            ls.dicq[0] = p[0];
            ls.dicq += 1;
            p += 1;
        }
        (ls.dicq - 1)[0] = 0; // overwrites '"'
        s = ls.dicp;
        n = n - 2;
    }
    if (b == 0 or (n >= 2 and std.mem.eql(u8, std.mem.span(s + @as(usize, @intCast(n - 2))), ".m"))) {
        return s;
    }
    if (s == ls.dicp) {
        ls.dicq -= 1;
    } else {
        ls.dicq = ls.dicp;
        var p = s;
        while (p[0] != 0) {
            ls.dicq[0] = p[0];
            ls.dicq += 1;
            p += 1;
        }
        ls.dicq[0] = 0;
    }
    if (std.mem.eql(u8, std.mem.span(ls.dicq - 2), ".x")) {
        ls.dicq -= 2;
    } else if ((ls.dicq - 1)[0] == '.') {
        ls.dicq -= 1;
    }
    _ = word.strcpy(ls.dicq, ".m");
    ls.dicq += 3;
    ovflocheck();
    return ls.dicp;
}

/// Emit `n` spaces (for listings).
fn spaces(n_input: Word) void {
    var n = n_input;
    while (n > 0) : (n -= 1) {
        _ = word.putchar(' ');
    }
}

/// Whether `s` names a literate script.
fn litname(s: [*:0]const u8) bool {
    const n = word.strlen(s);
    return n >= 6 and std.mem.eql(u8, std.mem.span(s + @as(usize, @intCast(n - 6))), ".lit.m");
}

/// Read the next raw input character.
fn getch() c_int {
    if (rt.rs.s_in == null) {
        return main_clib.EOF;
    }
    var ch = main_clib.getc(rt.rs.s_in);
    if (ch == main_clib.EOF and ls.atnl == 0 and t(ls.fileq) == NIL) {
        ls.atnl = 1;
        return '\n';
    }
    if (ls.atnl != 0) {
        if ((ls.line_no == 0 and core_state.s.commandmode == 0) or (rt.rs.magic and ls.line_no == 1 and ls.litstack == NIL)) {
            const is_lit = (ch == '>') or litname(getFil(heap.heap.current_file));
            ls.literate = if (is_lit) 1 else 0;
            ls.litmain = ls.literate;
        }
        if (ls.literate != 0) {
            var i: Word = 0;
            while (ch != main_clib.EOF and ch != '>') {
                _ = main_clib.ungetc(ch, rt.rs.s_in);
                ls.line_no += 1;
                _ = word.fgets(ls.dicp, 250, rt.rs.s_in);
                if (i == 0 and ls.line_no > 1) {
                    chblank(ls.dicp);
                }
                i += 1;
                if (rt.rs.echoing != 0) {
                    spaces(ls.lverge);
                    _ = main_clib.fputs(ls.dicp, getStdout());
                }
                ch = main_clib.getc(rt.rs.s_in);
            }
            if ((i > 1 or (ls.line_no == 1 and i == 1)) and ch != main_clib.EOF) {
                chblank(ls.dicp);
            }
            if (ch == '>') {
                if (rt.rs.echoing != 0) {
                    _ = word.putchar(ch);
                    spaces(ls.lverge);
                }
                ch = main_clib.getc(rt.rs.s_in);
            }
        }
        ls.atnl = 0;
        ls.col = ls.lverge + ls.literate;
        if (core_state.s.commandmode == 0 and ch != main_clib.EOF) {
            ls.line_no += 1;
        }
    }
    if (rt.rs.echoing != 0 and ch != main_clib.EOF) {
        _ = word.putchar(ch);
        if (ch == '\n' and ls.literate == 0) {
            if (ls.litmain != 0) {
                _ = word.putchar('>');
                spaces(ls.lverge);
            } else {
                spaces(ls.lverge);
            }
        }
    }
    if (ch == '\t') {
        ls.col = (@divTrunc(ls.col - ls.lverge, 8) + 1) * 8 + ls.lverge;
    } else {
        ls.col += 1;
    }
    if (ch == '\n') {
        ls.atnl = 1;
    }
    return ch;
}

/// Blank out the characters of `s` (comment them) for listing.
pub fn chblank(s_input: [*:0]u8) void {
    var s = s_input;
    while (s[0] == ' ' or s[0] == '\t') {
        s += 1;
    }
    if (s[0] == '\n') {
        return;
    }
    syntax("formal text not delimited by blank line\n");
    ls.blankerr = 1;
    reset(); // easiest way to recover is to pretend it was an interrupt
}

const UMAX: Word = 0x10ffff;

/// Read the next character, honouring literate-script `>` margins.
fn getlitch() Word {
    const ch: Word = ls.c;
    ls.rawch = @intCast(ch);
    if (ch == '\n') {
        return ch; // always an error
    }
    if (rt.rs.UTF8 != 0 and ch > 127) {
        const ch1 = getch();
        ls.c = ch1;
        if ((ch & 0xe0) == 0xc0) { // 2 bytes
            if ((ch1 & 0xc0) != 0x80) {
                return -5; // not valid rt.rs.UTF8
            }
            ls.c = getch();
            return stoChar(((ch & 0x1f) << 6) | (ch1 & 0x3f));
        }
        const ch2 = getch();
        ls.c = ch2;
        if ((ch & 0xf0) == 0xe0) { // 3 bytes
            if ((ch1 & 0xc0) != 0x80 or (ch2 & 0xc0) != 0x80) {
                return -5; // not valid rt.rs.UTF8
            }
            ls.c = getch();
            return stoChar(((ch & 0xf) << 12) | ((ch1 & 0x3f) << 6) | (ch2 & 0x3f));
        }
        const ch3 = getch();
        ls.c = ch3;
        if ((ch & 0xf8) == 0xf0) { // 4 bytes
            if ((ch1 & 0xc0) != 0x80 or (ch2 & 0xc0) != 0x80 or (ch3 & 0xc0) != 0x80) {
                return -5; // not valid rt.rs.UTF8
            }
            ls.c = getch();
            return ((ch & 7) << 18) | ((ch1 & 0x3f) << 12) | ((ch2 & 0x3f) << 6) | (ch3 & 0x3f);
        }
        return -5;
    }
    if (ch != '\\') {
        ls.c = getch();
        return ch;
    }
    const escaped_ch = getch();
    ls.c = getch();
    switch (escaped_ch) {
        '\n' => return getlitch(),
        'a' => return '\x07',
        'b' => return '\x08',
        'f' => return '\x0c',
        'n' => return '\n',
        'r' => return '\r',
        't' => return '\t',
        'v' => return '\x0b',
        'X', 'x' => {
            if (word.isxdigit(ls.c)) {
                var value: c_uint = 0;
                const N: usize = if (escaped_ch == 'x') 4 else 6;
                var hold = std.mem.zeroes([8]u8);
                var count: usize = 0;
                var xch = ls.c;
                while (word.isxdigit(xch) and count < N) {
                    hold[count] = @intCast(xch);
                    count += 1;
                    xch = getch();
                }
                hold[count] = 0;
                _ = main_clib.sscanf(&hold[0], "%x", .{&value});
                ls.c = xch;
                return if (value > UMAX) -3 else stoChar(@intCast(value));
            } else {
                return -2;
            }
        },
        else => {
            if (escaped_ch >= '0' and escaped_ch <= '9') {
                var n: Word = escaped_ch - '0';
                var count: usize = 1;
                const N: usize = 3;
                var xch = ls.c;
                while (xch >= '0' and xch <= '9' and count < N) {
                    n = (10 * n) + xch - '0';
                    count += 1;
                    xch = getch();
                }
                ls.c = xch;
                return stoChar(n);
            }
            if (escaped_ch == '\'' or escaped_ch == '"' or escaped_ch == '\\' or escaped_ch == '`') {
                return escaped_ch;
            }
            if (escaped_ch == '&') {
                return -7;
            }
            ls.errch = if (escaped_ch <= 255) @intCast(escaped_ch) else '?';
            return -6;
        },
    }
}

/// Read a whole input line into a buffer.
pub fn rdline() ?[*:0]u8 {
    var p: [*]u8 = &ls.rdline_linebuf;
    var ch = main_clib.getchar();
    var expansion: Word = 0;
    while (ch == ' ' or ch == '\t') {
        ch = main_clib.getchar();
    }
    if (ch == '\n' or (ch == '!' and ls.rdline_linebuf[0] == 0)) {
        if (ls.rdline_linebuf[0] != 0) {
            word.print("!{s}", .{@as([*:0]const u8, @ptrCast(&ls.rdline_linebuf))});
        }
        while (ch != '\n' and ch != main_clib.EOF) {
            ch = main_clib.getchar();
        }
        return @ptrCast(&ls.rdline_linebuf);
    }
    if (ch == '!') {
        expansion = 1;
        p = @ptrCast(&ls.rdline_linebuf[word.strlen(&ls.rdline_linebuf) - 1]); // p now points at old '\n'
    } else {
        if (getStdin()) |stdin_file| {
            _ = main_clib.ungetc(ch, stdin_file);
        }
    }
    while (true) {
        ch = main_clib.getchar();
        p[0] = @intCast(ch);
        p += 1;
        if (ch == '\n' or ch == main_clib.EOF) {
            break;
        }
        const offset = @as(usize, @intFromPtr(p)) - @as(usize, @intFromPtr(&ls.rdline_linebuf));
        if (offset >= 1024) {
            p[0] = 0;
            word.printErr("sorry, !command too long (limit={} chars): {s}...\n", .{ @as(c_int, 1024), @as([*:0]const u8, @ptrCast(&ls.rdline_linebuf)) });
            while (true) {
                ch = main_clib.getchar();
                if (ch == '\n' or ch == main_clib.EOF) {
                    break;
                }
            }
            return null;
        }
        if ((p - 1)[0] == '%') {
            if (@intFromPtr(p) > @intFromPtr(&ls.rdline_linebuf[1]) and (p - 2)[0] == '\\') {
                (p - 2)[0] = '%';
                p -= 1;
            } else {
                const remaining = 1024 - (@as(usize, @intFromPtr(p - 1)) - @as(usize, @intFromPtr(&ls.rdline_linebuf)));
                _ = word.strncpy(p - 1, rt.rs.current_script.?, remaining);
                p = @ptrCast(&ls.rdline_linebuf[word.strlen(&ls.rdline_linebuf)]);
                expansion = 1;
            }
        }
    }
    p[0] = 0;
    if (expansion != 0) {
        word.print("!{s}", .{@as([*:0]const u8, @ptrCast(&ls.rdline_linebuf))});
    }
    return @ptrCast(&ls.rdline_linebuf);
}

/// Begin enforcing the literate-script left margin.
pub fn setlmargin() void {
    ls.margstack = cons(ls.lmargin, ls.margstack);
    if (ls.lmargin < ls.col) {
        ls.lmargin = ls.col;
    }
}

/// Stop enforcing the literate-script left margin.
pub fn unsetlmargin() void {
    if (ls.margstack == NIL) {
        return;
    }
    ls.lmargin = h(ls.margstack);
    ls.margstack = t(ls.margstack);
}

/// Report a bad character class in a string / char-class literal.
fn errclass(val: Word, string_flag: Word) void {
    const s: [*:0]const u8 = if (string_flag == 2) "char class" else if (string_flag != 0) "string" else "char const";
    if (val == -2) {
        word.print("\\x with no xdigits in {s}\n", .{s});
    } else if (val == -3) {
        word.print("\\hexadecimal escape out of range in {s}\n", .{s});
    } else if (val == -4) {
        word.print("\\decimal escape out of range in {s}\n", .{s});
    } else if (val == -5) {
        word.print("unrecognised character in {s}(rt.rs.UTF8 error)\n", .{s});
    } else if (val == -6) {
        word.print("unrecognised escape \\{c} in {s}\n", .{ @as(u8, @intCast(ls.errch)), s });
    } else if (val == -7) {
        word.print("illegal use of \\& in char const\n", .{});
    } else {
        word.print("unknown error in {s}\n", .{s});
    }
    acterror();
}

/// Lookahead: if the next char is `y`, consume it and yield `x`, else null.
inline fn tryCh(x: Word, y: c_int) ?c_int {
    if (ls.c == x) {
        ls.c = getch();
        return y;
    }
    return null;
}

/// The main lexer: scan and return the next token id (yacc-style).
pub fn yylex() c_int {
    if (core_state.s.SYNERR != 0) {
        return word.END;
    }
    layout();
    ls.tok_start_col = ls.col;
    if (ls.c == '\n') {
        return word.END;
    }
    if (ls.col < ls.lmargin) {
        if (ls.c == '=' and (ls.margstack == NIL or ls.col >= h(ls.margstack))) {
            ls.c = getch();
            return word.ELSEQ;
        }
        return word.OFFSIDE;
    }
    if (ls.c == ';') {
        ls.c = getch();
        layout();
        if (ls.c == '=' and (ls.margstack == NIL or ls.col >= h(ls.margstack))) {
            ls.c = getch();
            return word.ELSEQ;
        }
        return ';';
    }
    if (word.isalpha(ls.c)) {
        kollect(okid);
        if (ls.inlex == 1) {
            layout();
            ls.yylval = name();
            return if (ls.c == '=') word.LEXDEF else if (isconstructor(ls.yylval)) word.CNAME else word.NAME;
        }
        if (ls.inbnf == 1) {
            (ls.dicq - 1)[0] = ' ';
            ls.dicq[0] = 0;
            ls.dicq += 1;
        }
        return @intCast(identifier(0));
    }
    if ((ls.c >= '0' and ls.c <= '9') or (ls.c == '.' and peekdig())) {
        if (ls.c == '0' and word.tolower(peekch()) == 'x') {
            hexnumeral();
        } else if (ls.c == '0' and word.tolower(peekch()) == 'o') {
            _ = getch();
            ls.c = getch();
            octnumeral();
        } else {
            numeral();
        }
        return word.CONST;
    }
    if (ls.c == '%' and core_state.s.commandmode == 0) {
        return @intCast(directive());
    }
    if (ls.c == '\'') {
        ls.c = getch();
        ls.yylval = getlitch();
        if (ls.yylval < 0) {
            errclass(ls.yylval, 0);
            return word.CONST;
        }
        if (!isChar(ls.yylval)) {
            const prefix_str: [*:0]const u8 = if (rt.rs.echoing != 0) "\n" else "";
            word.printErr("{s}impossible event while reading char const ('\\{}')\n", .{ prefix_str, ls.yylval });
            acterror();
        }
        if (ls.rawch == '\n' or ls.c != '\'') {
            syntax("improperly terminated char const\n");
        } else {
            ls.c = getch();
        }
        return word.CONST;
    }
    if (ls.inexplist != 0 and (ls.c == '"' or ls.c == '<')) {
        if (pathname() == null) {
            syntax("badly formed pathname in %export list\n");
        } else {
            ls.exportfiles = cons(strtab.strBits(addextn(1, ls.dicp)), ls.exportfiles);
            _ = keep(ls.dicp);
        }
        return word.PATHNAME;
    }
    if (ls.inlex == 1 and ls.c == '`') {
        return if (charclass() != 0) word.ANTICHARCLASS else word.CHARCLASS;
    }
    if (ls.c == '"') {
        string();
        if (ls.yylval == NIL) {
            ls.yylval = NILS;
        }
        return word.CONST;
    }
    if (ls.inbnf == 2) {
        if (ls.c == '[') {
            ls.brct += 1;
        } else if (ls.c == ']') {
            ls.brct -= 1;
        } else if (ls.c == '|' and ls.brct == 0) {
            return word.OFFSIDE;
        }
    }
    if (ls.c == main_clib.EOF) {
        if (ls.fileq == NIL) {
            ls.c = 0;
            return word.END;
        }
        if (t(ls.fileq) == NIL and ls.margstack != NIL) {
            return word.OFFSIDE;
        }
        const file_ptr: ?*word.FILE = @ptrFromInt(@as(usize, @intCast(h(h(ls.fileq)))));
        _ = word.fclose(file_ptr);
        ls.fileq = t(ls.fileq);
        ls.insertdepth -= 1;
        if (ls.fileq != NIL and h(ls.echostack) != 0) {
            if (ls.literate != 0) {
                _ = word.putchar('>');
                spaces(ls.lverge);
            }
            word.print("<end of insert>", .{});
        }
        rt.rs.s_in = if (ls.fileq == NIL) getStdin() else @ptrFromInt(@as(usize, @intCast(h(h(ls.fileq)))));
        ls.c = ' ';
        if (ls.fileq == NIL) {
            ls.c = 0;
            ls.col = 0;
            ls.lmargin = 0;
            ls.lverge = 0;
            ls.atnl = 1;
            rt.rs.echoing = rt.rs.verbosity & rt.rs.listing;
            ls.lastline = ls.line_no;
            ls.line_no = 0;
            ls.literate = 0;
            ls.litmain = 0;
            return word.END;
        }
        heap.heap.current_file = t(h(ls.fileq));
        ls.prefix = h(ls.prefixstack);
        ls.prefixstack = t(ls.prefixstack);
        rt.rs.echoing = h(ls.echostack);
        ls.echostack = t(ls.echostack);
        ls.lverge = h(ls.vergstack);
        ls.vergstack = t(ls.vergstack);
        ls.literate = h(ls.litstack);
        ls.litstack = t(ls.litstack);
        ls.line_no = h(ls.linostack);
        ls.linostack = t(ls.linostack);
        return yylex();
    }
    ls.lastc = ls.c;
    ls.c = getch();
    switch (ls.lastc) {
        '_' => {
            if (ls.c == ' ') {
                ls.c = getch();
                if (ls.c == '<') {
                    ls.c = getch();
                    return word.LE;
                }
                if (ls.c == '>') {
                    ls.c = getch();
                    return word.GE;
                }
                if (ls.c == '%' and core_state.s.commandmode == 0) {
                    return @intCast(directive());
                }
                if (word.isalpha(ls.c)) {
                    kollect(okulid);
                    if (ls.dicp[1] == '_' and ls.dicp[2] == ' ') {
                        return @intCast(identifier(1));
                    }
                }
                syntax("illegal use of underlining\n");
                return '_';
            }
            return @intCast(ls.lastc);
        },
        '-' => {
            if (tryCh('>', word.ARROW)) |ret| return ret;
            if (tryCh('-', word.MINUSMINUS)) |ret| return ret;
            return @intCast(ls.lastc);
        },
        '<' => {
            if (tryCh('-', word.LEFTARROW)) |ret| return ret;
            if (tryCh('=', word.LE)) |ret| return ret;
            return @intCast(ls.lastc);
        },
        '=' => {
            if (ls.c == '>') {
                syntax("unexpected symbol =>\n");
                return '=';
            }
            if (tryCh('=', word.EQEQ)) |ret| return ret;
            return @intCast(ls.lastc);
        },
        '+' => {
            if (tryCh('+', word.PLUSPLUS)) |ret| return ret;
            return @intCast(ls.lastc);
        },
        '.' => {
            if (ls.c == '.') {
                ls.c = getch();
                return word.DOTDOT;
            }
            return @intCast(ls.lastc);
        },
        '\\' => {
            if (tryCh('/', word.VEL)) |ret| return ret;
            return @intCast(ls.lastc);
        },
        '>' => {
            if (tryCh('=', word.GE)) |ret| return ret;
            return @intCast(ls.lastc);
        },
        '~' => {
            if (tryCh('=', word.NE)) |ret| return ret;
            return @intCast(ls.lastc);
        },
        '&' => {
            if (ls.c == '>') {
                ls.c = getch();
                if (ls.c == '>') {
                    ls.yylval = 1;
                } else {
                    ls.yylval = 0;
                    _ = main_clib.ungetc(@intCast(ls.c), rt.rs.s_in);
                }
                ls.c = ' ';
                return word.TO;
            }
            return @intCast(ls.lastc);
        },
        '/' => {
            if (tryCh('/', word.DIAG)) |ret| return ret;
            return @intCast(ls.lastc);
        },
        '*' => {
            if (ls.c == '*') {
                ls.c = getch();
                return @intCast(collectstars());
            }
            return @intCast(ls.lastc);
        },
        ':' => {
            if (ls.c == ':') {
                ls.c = getch();
                if (ls.c == '=') {
                    ls.c = getch();
                    return word.COLON2EQ;
                }
                return word.COLONCOLON;
            }
            return @intCast(ls.lastc);
        },
        '$' => {
            if (word.isalpha(ls.c)) {
                kollect(okid);
                const t_val = identifier(0);
                return if (t_val == word.NAME) word.INFIXNAME else if (t_val == word.CNAME) word.INFIXCNAME else '$';
            }
            if (ls.c >= '1' and ls.c <= '9') {
                var n: Word = 0;
                while (ls.c >= '0' and ls.c <= '9' and n < 1000000) {
                    n = (10 * n) + ls.c - '0';
                    ls.c = getch();
                }
                if (n > ls.sreds) {
                    word.print("{s}syntax error: illegal symbol ${}{s}\n", .{ if (rt.rs.echoing != 0) @as([*:0]const u8, "\n") else "", n, if (n >= 1000000) @as([*:0]const u8, "...") else "" });
                    acterror();
                } else {
                    ls.yylval = mkgvar(n);
                    return word.NAME;
                }
            }
            if (ls.c == '-') {
                if (core_state.s.compiling == 0) {
                    syntax("unexpected symbol $-\n");
                } else {
                    ls.c = getch();
                    ls.yylval = ls.common_stdin;
                    return word.CONST;
                }
            }
            if (ls.c == ':') {
                ls.c = getch();
                if (ls.c != '-') {
                    syntax("unexpected symbol $:\n");
                } else {
                    if (core_state.s.compiling == 0) {
                        syntax("unexpected symbol $:-\n");
                    } else {
                        ls.c = getch();
                        ls.yylval = ls.common_stdinb;
                        return word.CONST;
                    }
                }
            }
            if (ls.c == '+') {
                if (core_state.s.compiling == 0) {
                    syntax("unexpected symbol $+\n");
                } else {
                    ls.c = getch();
                    if (core_state.s.commandmode != 0) {
                        ls.yylval = ls.cook_stdin;
                    } else {
                        ls.yylval = make(.CONS, readvals(0, 0), word.OFFSIDE);
                    }
                    return word.CONST;
                }
            }
            if (ls.c == '$') {
                if (ls.inlex != 2 and (core_state.s.commandmode == 0 or core_state.s.compiling == 0)) {
                    syntax("unexpected symbol $$\n");
                } else {
                    ls.c = getch();
                    if (ls.inlex != 0) {
                        ls.yylval = mklexvar(0);
                        return word.NAME;
                    }
                    return word.DOLLARS;
                }
            }
            if (ls.c == '#') {
                if (ls.inlex != 2) {
                    syntax("unexpected symbol $#\n");
                } else {
                    ls.c = getch();
                    ls.yylval = mklexvar(1);
                    return word.NAME;
                }
            }
            if (ls.c == '*') {
                ls.c = getch();
                ls.yylval = make(.AP, word.GETARGS, 0);
                return word.CONST;
            }
            if (ls.c == '0') {
                syntax("illegal symbol $0\n");
            }
            return @intCast(ls.lastc);
        },
        else => return @intCast(ls.lastc),
    }
}

/// Apply the offside (layout) rule, inserting virtual block tokens.
pub fn layout() void {
    while (true) {
        if (ls.c == ' ' or (ls.c == '\n' and core_state.s.commandmode == 0) or ls.c == '\t') {
            ls.c = getch();
            continue;
        }
        if (ls.c == main_clib.EOF and core_state.s.commandmode != 0) {
            ls.c = '\n';
            return;
        }
        if ((ls.c == '|' and peekch() == '|') or (ls.col == 1 and ls.line_no == 1 and ls.c == '#' and peekch() == '!')) {
            ls.c = getch();
            while (ls.c != '\n' and ls.c != main_clib.EOF) {
                ls.c = getch();
            }
            if (ls.c == main_clib.EOF and core_state.s.commandmode == 0) {
                return;
            }
            ls.c = '\n';
            continue;
        }
        break;
    }
}

/// Collect a run of `*`s naming a type variable.
fn collectstars() Word {
    var n: Word = 2;
    while (ls.c == '*') {
        ls.c = getch();
        n += 1;
    }
    ls.yylval = mktvar(n);
    return word.TYPEVAR;
}

/// Make a grammar-variable node with index `i`.
pub fn mkgvar(i_input: Word) Word {
    var i = i_input;
    var p = &ls.gvars;
    while (i > 1) {
        if (p.* == NIL) {
            p.* = cons(stoId("gvar"), NIL);
        }
        p = tp(p.*);
        i -= 1;
    }
    if (p.* == NIL) {
        p.* = cons(stoId("gvar"), NIL);
    }
    return h(p.*);
}

/// Make a lexer-variable node with index `i`.
pub fn mklexvar(i: Word) Word {
    if (ls.lexvar == 0) {
        ls.lexvar = cons(stoId("ls.lexvar"), stoId("ls.lexvar"));
        tp(h(ls.lexvar)).* = cs.ltchar;
        tp(t(ls.lexvar)).* = genlstatType();
    }
    return if (i != 0) t(ls.lexvar) else h(ls.lexvar);
}

/// Build the command-line argument list as a Miranda list value.
pub fn convArgs() Word {
    var i = ls.ARGC;
    var x = NIL;
    if (i == 0) {
        return NIL;
    }
    i -= 1;
    while (i > 0) {
        x = cons(strConv(ls.ARGV[@intCast(i)].?), x);
        i -= 1;
    }
    x = cons(strConv(ls.ARGV[0].?), x);
    return x;
}

/// Convert C-string `s` to a Miranda char list.
///
/// Tests: strConv: a C string becomes a Miranda char list
pub fn strConv(s: [*:0]const u8) Word {
    var x = NIL;
    var i = word.strlen(s);
    while (i > 0) {
        i -= 1;
        x = cons(s[i], x);
    }
    return x;
}

test "strConv: a C string becomes a Miranda char list" {
    tu.freshInterp();
    try tu.expectStr("hello", strConv("hello"));
    try tu.expectStr("", strConv(""));
}

/// Scan a `<...>` or quoted pathname token.
pub fn pathname() ?[*:0]u8 {
    layout();
    if (ls.c == '<') {
        const hold = ls.dicp;
        ls.c = getch();
        _ = word.strcpy(ls.dicp, rt.rs.miralib.?);
        ls.dicp += word.strlen(rt.rs.miralib.?);
        ls.dicp[0] = '/';
        ls.dicp += 1;
        kollect(okpath);
        ls.dicp = hold;
        if (ls.c != '>') {
            return null;
        }
        ls.c = ' ';
        return ls.dicp;
    }
    if (ls.c != '"') {
        return null;
    }
    ls.c = getch();
    if (ls.c == '~') {
        const hold = ls.dicp;
        ls.dicp[0] = @intCast(ls.c);
        ls.dicp += 1;
        ls.c = getch();
        while (word.isalnum(ls.c) or ls.c == '-' or ls.c == '_' or ls.c == '.') {
            ls.dicp[0] = @intCast(ls.c);
            ls.dicp += 1;
            ls.c = getch();
        }
        ls.dicp[0] = 0;
        if (gethome(hold + 1)) |h_dir| {
            _ = word.strcpy(hold, h_dir);
            ls.dicp = hold + word.strlen(hold);
        } else {
            _ = word.strcpy(&rt.rs.linebuf[0], hold);
            _ = word.strcpy(hold, ls.prefixbase.? + @as(usize, @intCast(ls.prefix)));
            ls.dicp = hold + word.strlen(ls.prefixbase.? + @as(usize, @intCast(ls.prefix)));
            _ = word.strcpy(ls.dicp, &rt.rs.linebuf[0]);
            ls.dicp += word.strlen(ls.dicp);
        }
        kollect(okpath);
        ls.dicp = hold;
    } else if (ls.c == '/') {
        kollect(okpath);
    } else {
        const hold = ls.dicp;
        _ = word.strcpy(ls.dicp, ls.prefixbase.? + @as(usize, @intCast(ls.prefix)));
        ls.dicp += word.strlen(ls.prefixbase.? + @as(usize, @intCast(ls.prefix)));
        kollect(okpath);
        ls.dicp = hold;
    }
    if (ls.c != '"') {
        return null;
    }
    ls.c = ' ';
    return ls.dicp;
}

/// Adjust the stored library path prefix for `f`.
pub fn adjustPrefix(f: [*:0]const u8) void {
    ls.prefixstack = cons(ls.prefix, ls.prefixstack);
    ls.prefix += @as(Word, @intCast(word.strlen(ls.prefixbase.? + @as(usize, @intCast(ls.prefix))))) + 1;
    while (@as(usize, @intCast(ls.prefix)) + word.strlen(f) >= @as(usize, @intCast(ls.prefixlimit))) {
        const old_limit = ls.prefixlimit;
        ls.prefixlimit += 1024;
        const old_slice = ls.prefixbase.?[0..@intCast(old_limit)];
        const new_slice = rt.allocator.realloc(old_slice, @intCast(ls.prefixlimit)) catch mallocPanic("ls.prefixbase");
        ls.prefixbase = new_slice.ptr;
    }
    _ = word.strcpy(ls.prefixbase.? + @as(usize, @intCast(ls.prefix)), f);
    const g = word.rindex(ls.prefixbase.? + @as(usize, @intCast(ls.prefix)), '/');
    if (g) |gp| {
        gp[1] = 0;
    } else {
        (ls.prefixbase.? + @as(usize, @intCast(ls.prefix)))[0] = 0;
    }
}

/// Whether the next input char is a digit (without consuming).
pub fn peekdig() bool {
    if (rt.rs.s_in == null) return false;
    const ch = main_clib.getc(rt.rs.s_in);
    _ = main_clib.ungetc(ch, rt.rs.s_in);
    return ch >= '0' and ch <= '9';
}

/// Peek the next input char without consuming it.
pub fn peekch() c_int {
    if (rt.rs.s_in == null) return main_clib.EOF;
    const ch = main_clib.getc(rt.rs.s_in);
    _ = main_clib.ungetc(ch, rt.rs.s_in);
    return ch;
}

/// Open source file `n` for reading; returns 0 on failure.
pub fn openfile(n: [*:0]const u8) c_int {
    const f = word.fopen(n, "r") orelse return 0;
    // FILE* handle stored in the cell (read back via @ptrFromInt below);
    // this is a FILE-handle-in-cell cast, not a node string — out of B1 scope.
    ls.fileq = cons(make(.STRCONS, @as(Word, @intCast(@intFromPtr(f))), NIL), ls.fileq);
    ls.insertdepth += 1;
    return 1;
}

/// Scan an identifier beginning with char `s`; returns its token id.
fn identifier(s: c_int) c_int {
    if (ls.inbnf == 1) {
        if (is("empty ") or is("e_ m_ p_ t_ y")) {
            return word.EMPTYSY;
        }
        if (is("end ") or is("e_ n_ d")) {
            return word.ENDSY;
        }
        if (is("error ") or is("e_ r_ r_ o_ r")) {
            return word.ERRORSY;
        }
        if (is("where ") or is("w_ h_ e_ r_ e")) {
            return word.WHERE;
        }
    } else {
        switch (ls.dicp[0]) {
            'a' => {
                if (is("abstype") or is("a_ b_ s_ t_ y_ p_ e")) {
                    return word.ABSTYPE;
                }
            },
            'd' => {
                if (is("div") or is("d_ i_ v")) {
                    return word.DIV;
                }
            },
            'F' => {
                if (is("False")) {
                    ls.yylval = False;
                    return word.CONST;
                }
            },
            'i' => {
                if (is("if") or is("i_ f")) {
                    return word.IF;
                }
            },
            'm' => {
                if (is("mod") or is("m_ o_ d")) {
                    return word.REM;
                }
            },
            'o' => {
                if (is("otherwise") or is("o_ t_ h_ e_ r_ w_ i_ s_ e")) {
                    return word.OTHERWISE;
                }
            },
            'r' => {
                if (is("readvals") or is("r_ e_ a_ d_ v_ a_ l_ s")) {
                    return word.READVALSY;
                }
            },
            's' => {
                if (is("show") or is("s_ h_ o_ w")) {
                    return word.SHOWSYM;
                }
            },
            'T' => {
                if (is("True")) {
                    ls.yylval = True;
                    return word.CONST;
                }
            },
            't' => {
                if (is("type") or is("t_ y_ p_ e")) {
                    return word.TYPE;
                }
            },
            'w' => {
                if (is("where") or is("w_ h_ e_ r_ e")) {
                    return word.WHERE;
                }
                if (is("with") or is("w_ i_ t_ h")) {
                    return word.WITH;
                }
            },
            else => {},
        }
    }
    if (s != 0) {
        syntax("illegal use of underlining\n");
        return '_';
    }
    ls.yylval = name();
    if (core_state.s.commandmode != 0 and rt.rs.lastid == 0 and h(ls.yylval) != 0) {
        if (t(h(ls.yylval)) != 0) {
            rt.rs.lastid = ls.yylval;
        }
    }
    return if (isconstructor(ls.yylval)) word.CNAME else word.NAME;
}

/// Handle a `%`-directive (`%include`/`%export`/`%free`/`%list`/...).
pub fn directive() Word {
    const holdcol = ls.col - 1;
    const holdlin = ls.line_no;
    ls.c = getch();
    if (ls.c == '%') {
        ls.c = getch();
        return word.ENDIR;
    }
    kollect(okulid);
    const first_char = if (ls.dicp[0] == '_' and ls.dicp[1] == ' ') ls.dicp[2] else ls.dicp[0];
    switch (first_char) {
        'b' => {
            if (is("begin") or is("_^Hb_^He_^Hg_^Hi_^Hn")) {
                if (ls.inlex != 0) {
                    return word.LBEGIN;
                }
            }
            if (is("bnf") or is("_^Hb_^Hn_^Hf")) {
                setlmargin();
                ls.col = holdcol + 4;
                return word.BNF;
            }
        },
        'e' => {
            if (is("export") or is("_ e_ x_ p_ o_ r_ t")) {
                if (rt.rs.magic) {
                    syntax("%export directive not permitted in \"-exp\" script\n");
                }
                return word.EXPORT;
            }
        },
        'f' => {
            if (is("free") or is("_ f_ r_ e_ e")) {
                if (rt.rs.magic) {
                    syntax("%free directive not permitted in \"-exp\" script\n");
                }
                return word.FREE;
            }
        },
        'i' => {
            if (is("include") or is("_ i_ n_ c_ l_ u_ d_ e")) {
                if (core_state.s.SYNERR == 0) {
                    layout();
                    setlmargin();
                }
                if (pathname() == null) {
                    syntax("bad pathname after %include\n");
                } else {
                    ls.yylval = make(.STRCONS, strtab.strBits(addextn(1, ls.dicp)), fileinfo(strtab.strBits(getFil(heap.heap.current_file)), holdlin));
                    _ = keep(ls.dicp);
                }
                return word.INCLUDE;
            }
            if (is("insert") or is("_ i_ n_ s_ e_ r_ t")) {
                const f = pathname();
                if (f == null) {
                    syntax("bad pathname after %insert\n");
                } else if (ls.insertdepth < 12 and openfile(f.?) != 0) {
                    adjustPrefix(f.?);
                    ls.vergstack = cons(ls.lverge, ls.vergstack);
                    ls.echostack = cons(rt.rs.echoing, ls.echostack);
                    ls.litstack = cons(ls.literate, ls.litstack);
                    ls.linostack = make(.STRCONS, ls.line_no, ls.linostack);
                    ls.line_no = 0;
                    ls.atnl = 1;
                    _ = keep(ls.dicp);
                    heap.heap.current_file = makeFil(f.?, fileMtime(f.?), 0, NIL);
                    heap.heap.files = append1(heap.heap.files, cons(heap.heap.current_file, NIL));
                    tp(h(ls.fileq)).* = heap.heap.current_file;
                    rt.rs.s_in = @ptrFromInt(@as(usize, @intCast(h(h(ls.fileq)))));
                    const is_lit = (peekch() == '>') or litname(f.?);
                    ls.literate = if (is_lit) 1 else 0;
                    ls.col = holdcol;
                    ls.lverge = holdcol;
                    if (rt.rs.echoing != 0) {
                        _ = word.putchar('\n');
                        if (ls.literate == 0) {
                            if (ls.litmain != 0) {
                                _ = word.putchar('>');
                                spaces(holdcol);
                            } else {
                                spaces(holdcol);
                            }
                        }
                    }
                    ls.c = getch();
                } else {
                    const toomany = (ls.insertdepth >= 12);
                    const prefix_str: [*:0]const u8 = if (rt.rs.echoing != 0) "\n" else "";
                    word.print("{s}%insert error - cannot open \"{s}\"\n", .{ prefix_str, f.? });
                    _ = keep(ls.dicp);
                    if (toomany) {
                        word.print("too many nested %insert directives (limit={})\n", .{ls.insertdepth});
                    } else {
                        heap.heap.files = append1(heap.heap.files, cons(makeFil(f.?, 0, 0, NIL), NIL));
                    }
                    acterror();
                }
                return yylex();
            }
        },
        'l' => {
            if (is("lex") or is("_^Hl_^He_^Hx")) {
                if (ls.inlex != 0) {
                    syntax("nested %lex not permitted\n");
                }
                return word.LEX;
            }
            if (is("list") or is("_ l_ i_ s_ t")) {
                rt.rs.echoing = rt.rs.verbosity;
                return yylex();
            }
        },
        'n' => {
            if (is("nolist") or is("_ n_ o_ l_ i_ s_ t")) {
                rt.rs.echoing = 0;
                return yylex();
            }
        },
        else => {},
    }
    if (rt.rs.echoing != 0) {
        _ = word.putchar('\n');
    }
    word.print("syntax error: unknown directive \"%{s}\"\n", .{ls.dicp});
    acterror();
    return word.END;
}

/// Collect input characters while predicate `f` holds, into the dictionary.
fn kollect(f: fn (c_int) bool) void {
    ls.dicq = ls.dicp;
    while (f(@intCast(ls.c))) {
        ls.dicq[0] = @intCast(ls.c);
        ls.dicq += 1;
        ls.c = getch();
    }
    ls.dicq[0] = 0;
    ls.dicq += 1;
    ovflocheck();
}

/// Intern token text `p` into permanent dictionary storage.
pub fn keep(p: [*:0]u8) [*:0]u8 {
    if (p == ls.dicp) {
        ls.dicp = ls.dicq;
    } else {
        _ = word.strcpy(ls.dicp, p);
        const ret = ls.dicp;
        ls.dicp = ls.dicp + word.strlen(ls.dicp) + 1;
        ls.dicq = ls.dicp;
        dicCheck();
        return ret;
    }
    return p;
}

/// Extend the dictionary buffer when it nears full.
pub fn dicCheck() void {
    ovflocheck();
}

/// Scan a decimal numeral literal.
pub fn numeral() void {
    var nflag: Word = 1;
    ls.dicq = ls.dicp;
    while (ls.c >= '0' and ls.c <= '9') {
        ls.dicq[0] = @intCast(ls.c);
        ls.dicq += 1;
        ls.c = getch();
    }
    if (ls.c == '.' and peekdig()) {
        ls.dicq[0] = @intCast(ls.c);
        ls.dicq += 1;
        ls.c = getch();
        nflag = 0;
        while (ls.c >= '0' and ls.c <= '9') {
            ls.dicq[0] = @intCast(ls.c);
            ls.dicq += 1;
            ls.c = getch();
        }
    }
    if (ls.c == 'e') {
        var np: Word = 0;
        ls.dicq[0] = @intCast(ls.c);
        ls.dicq += 1;
        ls.c = getch();
        nflag = 0;
        if (ls.c == '+') {
            ls.c = getch();
        } else if (ls.c == '-') {
            ls.dicq[0] = @intCast(ls.c);
            ls.dicq += 1;
            ls.c = getch();
        }
        if (ls.c < '0' or ls.c > '9') {
            syntax("badly formed floating point number\n");
        }
        while (ls.c == '0') {
            ls.dicq[0] = @intCast(ls.c);
            ls.dicq += 1;
            ls.c = getch();
        }
        while (ls.c >= '0' and ls.c <= '9') {
            np += 1;
            ls.dicq[0] = @intCast(ls.c);
            ls.dicq += 1;
            ls.c = getch();
        }
        if (nflag == 0 and np > 3) {
            syntax("floating point number out of range\n");
            return;
        }
    }
    ovflocheck();
    if (nflag != 0) {
        ls.dicq[0] = 0;
        ls.yylval = bigscan(ls.dicp);
    } else {
        var r: f64 = 0.0;
        const len = @as(usize, @intFromPtr(ls.dicq)) - @as(usize, @intFromPtr(ls.dicp));
        if (len > 60) {
            syntax("illegal floating point constant (too many digits)\n");
            return;
        }
        ls.dicq[0] = '\n';
        ls.dicq[1] = 0;
        _ = main_clib.sscanf(ls.dicp, "%lf", .{&r});
        ls.yylval = stoDbl(r);
    }
}

/// Scan a hexadecimal numeral literal.
pub fn hexnumeral() void {
    ls.dicq = ls.dicp;
    ls.dicq[0] = @intCast(ls.c); // 0
    ls.dicq += 1;
    ls.c = getch();
    ls.dicq[0] = @intCast(ls.c); // x
    ls.dicq += 1;
    ls.c = getch();
    if (!word.isxdigit(ls.c) and ls.c != '.') {
        syntax("malformed hex number\n");
    }
    while (ls.c == '0' and word.isxdigit(peekch())) {
        ls.c = getch(); // skip zeros before first nonzero digit
    }
    while (word.isxdigit(ls.c)) {
        ls.dicq[0] = @intCast(ls.c);
        ls.dicq += 1;
        ls.c = getch();
    }
    ovflocheck();
    if (ls.c == '.' or word.tolower(ls.c) == 'p') {
        var d: f64 = 0.0;
        if (ls.c == '.') {
            ls.dicq[0] = @intCast(ls.c);
            ls.dicq += 1;
            ls.c = getch();
            while (word.isxdigit(ls.c)) {
                ls.dicq[0] = @intCast(ls.c);
                ls.dicq += 1;
                ls.c = getch();
            }
        }
        if (ls.c == 'p') {
            ls.dicq[0] = @intCast(ls.c);
            ls.dicq += 1;
            ls.c = getch();
            if (ls.c == '+' or ls.c == '-') {
                ls.dicq[0] = @intCast(ls.c);
                ls.dicq += 1;
                ls.c = getch();
            }
            if (ls.c < '0' or ls.c > '9') {
                syntax("malformed hex float\n");
            }
            while (ls.c >= '0' and ls.c <= '9') {
                ls.dicq[0] = @intCast(ls.c);
                ls.dicq += 1;
                ls.c = getch();
            }
        }
        ovflocheck();
        ls.dicq[0] = 0;
        const len = @as(usize, @intFromPtr(ls.dicq)) - @as(usize, @intFromPtr(ls.dicp));
        if (len > 60 or main_clib.sscanf(ls.dicp, "%lf", .{&d}) != 1) {
            syntax("malformed hex float\n");
        } else {
            ls.yylval = stoDbl(d);
        }
        return;
    }
    ls.dicq[0] = 0;
    ls.yylval = bigxscan(ls.dicp + 2, ls.dicq);
}

/// Scan an octal numeral literal.
pub fn octnumeral() void {
    ls.dicq = ls.dicp;
    if (ls.c < '0' or ls.c > '9') {
        syntax("malformed octal number\n");
    }
    while (ls.c == '0' and peekch() >= '0' and peekch() <= '9') {
        ls.c = getch();
    }
    while (ls.c >= '0' and ls.c <= '7') {
        ls.dicq[0] = @intCast(ls.c);
        ls.dicq += 1;
        ls.c = getch();
    }
    if (ls.c >= '0' and ls.c <= '9') {
        syntax("illegal digit in octal number\n");
    }
    ovflocheck();
    ls.dicq[0] = 0;
    ls.yylval = bigoscan(ls.dicp, ls.dicq);
}

/// The filename associated with node `x`.
pub fn getfname(x: Word) Word {
    const p = getId(x);
    ls.dicq = ls.dicp;
    var i: usize = 0;
    while (true) {
        ls.dicq[i] = p[i];
        if (p[i] == 0) {
            break;
        }
        i += 1;
    }
    ls.dicq += i + 1;
    const len = @as(usize, @intFromPtr(ls.dicq)) - @as(usize, @intFromPtr(ls.dicp));
    if (len < 3) {
        errors.fatal("impossible event in getfname\n", .{.{}});
    }
    (ls.dicq - 2)[0] = 0;
    ovflocheck();
    return name();
}

/// Scan a name token, returning its dictionary `ID` node.
pub fn name() Word {
    const h_idx = @as(usize, @intCast(hash(ls.dicp)));
    var q = ls.namebucket[h_idx];
    while (q != 0 and !is(getId(h(q)))) {
        q = t(q);
    }
    if (q == 0) {
        q = stoId(ls.dicp);
        ls.namebucket[h_idx] = cons(q, ls.namebucket[h_idx]);
        _ = keep(ls.dicp);
    } else {
        q = h(q);
    }
    return q;
}

/// Intern name `n` as an `ID` node (inserting if new).
///
/// Tests: makeId / findid: intern then look up a dictionary name
pub fn makeId(n: [*:0]const u8) Word {
    const h_idx = @as(usize, @intCast(hash(n)));
    const x = stoId(if (ls.inprelude) keep(@constCast(n)) else n);
    ls.namebucket[h_idx] = cons(x, ls.namebucket[h_idx]);
    return x;
}

/// Look up name `n` in the dictionary (NIL if absent).
///
/// Tests: makeId / findid: intern then look up a dictionary name
pub fn findid(n: [*:0]const u8) Word {
    const h_idx = @as(usize, @intCast(hash(n)));
    var q = ls.namebucket[h_idx];
    while (q != 0 and !std.mem.eql(u8, std.mem.span(n), std.mem.span(getId(h(q))))) {
        q = t(q);
    }
    return if (q != 0) h(q) else NIL;
}

test "makeId / findid: intern then look up a dictionary name" {
    tu.freshInterp();
    const id = makeId("zzqunique");
    try std.testing.expectEqual(id, findid("zzqunique"));
    try std.testing.expectEqual(@as(Word, NIL), findid("zznotthere"));
}

/// Fill `out` with interned identifiers that are in scope (have a type) and whose
/// name starts with `prefix`. Returns the number written (capped at `out.len`).
/// Backs the REPL's tab completion; the returned pointers are into the permanent
/// dictionary storage, so they stay valid.
pub fn completeIds(prefix: []const u8, out: [][*:0]const u8) usize {
    var n: usize = 0;
    for (ls.namebucket) |bucket| {
        var q = bucket;
        while (q != 0) : (q = t(q)) {
            if (n >= out.len) return n;
            const idnode = h(q);
            if (heap.idType(idnode) == word.undef_t) continue; // not (yet) in scope
            const id_name = getId(idnode);
            if (std.mem.startsWith(u8, std.mem.span(id_name), prefix)) {
                out[n] = id_name;
                n += 1;
            }
        }
    }
    return n;
}

/// Reset the private-name table.
pub fn resetPns() void {
    ls.nextpn = 0;
    if (ls.pnvec == null) {
        const slice = rt.allocator.alloc(Word, @intCast(ls.pn_lim)) catch mallocPanic("ls.pnvec");
        ls.pnvec = slice.ptr;
    }
}

/// Make a private-name node for value `val`.
pub fn makePn(val: Word) Word {
    if (ls.nextpn == ls.pn_lim) {
        const old_lim = ls.pn_lim;
        ls.pn_lim += 400;
        const old_slice = ls.pnvec.?[0..@intCast(old_lim)];
        const slice = rt.allocator.realloc(old_slice, @intCast(ls.pn_lim)) catch mallocPanic("ls.pnvec");
        ls.pnvec = slice.ptr;
    }
    ls.pnvec.?[@intCast(ls.nextpn)] = make(.STRCONS, ls.nextpn, val);
    const ret = ls.pnvec.?[@intCast(ls.nextpn)];
    ls.nextpn += 1;
    return ret;
}

/// Allocate/store a private name `n`.
pub fn stoPn(n: Word) Word {
    if (n >= ls.pn_lim) {
        const old_lim = ls.pn_lim;
        while (ls.pn_lim <= n) {
            ls.pn_lim += 400;
        }
        const old_slice = ls.pnvec.?[0..@intCast(old_lim)];
        const slice = rt.allocator.realloc(old_slice, @intCast(ls.pn_lim)) catch mallocPanic("ls.pnvec");
        ls.pnvec = slice.ptr;
    }
    while (ls.nextpn <= n) {
        ls.pnvec.?[@intCast(ls.nextpn)] = make(.STRCONS, ls.nextpn, UNDEF);
        ls.nextpn += 1;
    }
    return ls.pnvec.?[@intCast(n)];
}

/// Re-intern id `x` under a private name (for `%export` hiding).
pub fn mkprivate(x_input: Word) void {
    var x = x_input;
    while (x != NIL) {
        // h(x) is an ID node; its name's StrId lives in the STRCONS node's hd.
        // Interned bytes are immutable, so re-intern the privatised form and
        // store the new id back, rather than mutating the bytes in place.
        const strcons = h(h(h(x)));
        hp(strcons).* = strtab.privatize(h(strcons));
        x = t(x);
    }
    ls.inprelude = false;
}

/// Scan a string literal.
pub fn string() void {
    var p: Word = undefined;
    var ch: Word = undefined;
    var badch: Word = 0;
    ls.c = getch();
    ch = getlitch();
    ls.yylval = cons(NIL, NIL);
    p = ls.yylval;
    while (ch != main_clib.EOF and ls.rawch != '"' and ls.rawch != '\n') {
        if (ch == -7) {
            ch = getlitch();
        } else if (ch < 0) {
            badch = ch;
            break;
        } else {
            tp(p).* = cons(ch, NIL);
            p = t(p);
            ch = getlitch();
        }
    }
    ls.yylval = t(ls.yylval);
    if (badch != 0) {
        errclass(badch, 1);
    }
    if (ls.rawch == '\n') {
        syntax("non-escaped newline encountered inside string quotes\n");
    } else if (ch == main_clib.EOF) {
        if (rt.rs.echoing != 0) {
            _ = word.putchar('\n');
        }
        word.print("syntax error: script ends inside unclosed string quotes - \n", .{});
        word.print("    \"", .{});
        while (ls.yylval != NIL and ls.sl > 0) {
            _ = word.putchar(@intCast(h(ls.yylval)));
            ls.yylval = t(ls.yylval);
            ls.sl -= 1;
        }
        word.print("...\"\n", .{});
        acterror();
    }
}

/// Scan a character class `[...]`; returns its token id.
pub fn charclass() c_int {
    var p: Word = undefined;
    var ch: Word = undefined;
    var badch: Word = 0;
    var anti: c_int = 0;
    ls.c = getch();
    if (ls.c == '^') {
        anti = 1;
        ls.c = getch();
    }
    ch = getlitch();
    ls.yylval = cons(NIL, NIL);
    p = ls.yylval;
    while (ch != main_clib.EOF and ls.rawch != '`' and ls.rawch != '\n') {
        if (ch == -7) {
            ch = getlitch();
        } else if (ch < 0) {
            badch = ch;
            break;
        } else {
            if (ls.rawch == '-' and h(p) != NIL and h(p) != word.DOTDOT) {
                ch = word.DOTDOT;
            }
            tp(p).* = cons(ch, NIL);
            p = t(p);
            ch = getlitch();
        }
    }
    if (h(p) == word.DOTDOT) {
        hp(p).* = '-';
    }
    p = ls.yylval;
    while (t(p) != NIL) {
        if (h(t(p)) == word.DOTDOT) {
            hp(t(p)).* = h(p);
            hp(p).* = word.DOTDOT;
            if (h(t(p)) >= h(t(t(p)))) {
                syntax("illegal use of '-' in [charclass]\n");
            }
        }
        p = t(p);
    }
    ls.yylval = t(ls.yylval);
    if (badch != 0) {
        errclass(badch, 2);
    }
    if (ls.rawch == '\n') {
        syntax("non-escaped newline encountered in char class\n");
    } else if (ch == main_clib.EOF) {
        if (rt.rs.echoing != 0) {
            _ = word.putchar('\n');
        }
        word.print("syntax error: script ends inside unclosed char class brackets - \n", .{});
        word.print("    [", .{});
        while (ls.yylval != NIL and ls.sl > 0) {
            _ = word.putchar(@intCast(h(ls.yylval)));
            ls.yylval = t(ls.yylval);
            ls.sl -= 1;
        }
        word.print("...]\n", .{});
        acterror();
    }
    return anti;
}

/// Reset the lexer's per-line scanning state.
pub fn resetLex() void {
    if (core_state.s.commandmode == 0) {
        if (core_state.s.errs == 0) {
            core_state.s.errs = fileinfo(strtab.strBits(getFil(heap.heap.current_file)), ls.line_no);
        }
        const err_script_raw = @as(?[*:0]const u8, strtab.strOf(h(core_state.s.errs)));
        const err_script = err_script_raw orelse "test.m";
        const is_current = if (err_script_raw) |es|
            (if (rt.rs.current_script) |script| es == @as([*:0]const u8, @ptrCast(script)) else false)
        else
            true;
        if (!@import("builtin").is_test) {
            if (t(core_state.s.errs) == 0 and is_current) {
                word.printErr("error occurs at end of ", .{});
            } else {
                word.printErr("error found near line {} of ", .{t(core_state.s.errs)});
            }
            word.printErr("{s}file \"{s}\"\ncompilation abandoned\n", .{ if (is_current) @as([*:0]const u8, "") else "%insert ", err_script });
        }
        if (is_current) {
            core_state.s.errline = if (t(core_state.s.errs) == 0) ls.lastline else t(core_state.s.errs);
            core_state.s.errs = 0;
        } else {
            if (ls.linostack != NIL) {
                while (t(ls.linostack) != NIL) {
                    ls.linostack = t(ls.linostack);
                }
                core_state.s.errline = h(ls.linostack);
            } else {
                core_state.s.errline = ls.lastline;
            }
        }
    }
    resetState();
}

/// Reset the full lexer state (between sessions).
pub fn resetState() void {
    if (core_state.s.commandmode != 0) {
        while (ls.c != '\n' and ls.c != main_clib.EOF) {
            if (rt.rs.s_in) |sin| {
                ls.c = main_clib.getc(sin);
            } else {
                ls.c = main_clib.EOF;
            }
        }
    }
    while (ls.fileq != NIL) {
        const file_ptr: ?*word.FILE = @ptrFromInt(@as(usize, @intCast(h(h(ls.fileq)))));
        _ = word.fclose(file_ptr);
        ls.fileq = t(ls.fileq);
    }
    ls.insertdepth = -1;
    rt.rs.s_in = getStdin();
    ls.echostack = NIL;
    ls.idsused = NIL;
    ls.prefixstack = NIL;
    ls.litstack = NIL;
    ls.linostack = NIL;
    ls.vergstack = NIL;
    ls.margstack = NIL;
    ls.prefix = 0;
    ls.prefixbase.?[0] = 0;
    rt.rs.echoing = rt.rs.verbosity & rt.rs.listing;
    ls.brct = 0;
    ls.inbnf = 0;
    ls.sreds = 0;
    ls.inlex = 0;
    ls.inexplist = 0;
    core_state.s.commandmode = 0;
    ls.lverge = 0;
    ls.col = 0;
    ls.lmargin = 0;
    ls.atnl = 1;
    cs.rv_script = 0;
    cs.algshfns = NIL;
    cs.newtyps = NIL;
    cs.showchain = NIL;
    cs.SGC = NIL;
    cs.TABSTRS = NIL;
    ls.c = ' ';
    ls.line_no = 0;
    ls.litmain = 0;
    ls.literate = 0;
    core_state.s.errs = 0;
    core_state.s.errline = 0;
}

/// Hash identifier text into a dictionary bucket index.
fn hash(input: [*:0]const u8) c_int {
    var s = input;
    var h_val: c_int = s[0];
    if (h_val != 0) {
        s += 1;
        while (s[0] != 0) : (s += 1) {
            h_val ^= s[0];
        }
    }
    return h_val & 127;
}

/// Whether name `input` is a constructor name — begins uppercase (1/0).
///
/// Tests: identifier classification matches Miranda lexer rules
pub fn isconstrname(input: [*:0]const u8) bool {
    var s = input;
    if (s[0] == '$') s += 1;
    return std.ascii.isUpper(s[0]);
}

/// Whether char `ch` is valid within an identifier (1/0).
///
/// Tests: identifier classification matches Miranda lexer rules
pub fn okid(ch: c_int) bool {
    return ((ch >= 'a' and ch <= 'z') or
        (ch >= 'A' and ch <= 'Z') or
        (ch >= '0' and ch <= '9') or
        ch == '_' or
        ch == '\'');
}

/// Whether char `ch` can appear in an (upper/lower) identifier.
fn okulid(ch: c_int) bool {
    return ((ch >= 'a' and ch <= 'z') or
        (ch >= 'A' and ch <= 'Z') or
        (ch >= '0' and ch <= '9') or
        ch == '_' or
        ch == 0x08 or
        ch == '\'');
}

/// Whether char `ch` is valid within a pathname.
fn okpath(ch: c_int) bool {
    return ch != '"' and ch != '\n' and ch != '>';
}

test "hash matches xor into seven-bit bucket" {
    try std.testing.expectEqual(@as(c_int, 0), hash(""));
    try std.testing.expectEqual(@as(c_int, 'a'), hash("a"));
    try std.testing.expectEqual(@as(c_int, ('a' ^ 'b' ^ 'c') & 127), hash("abc"));
}

test "identifier classification matches Miranda lexer rules" {
    try std.testing.expect(isconstrname("Name"));
    try std.testing.expect(isconstrname("$Name"));
    try std.testing.expect(!(isconstrname("name")));
    try std.testing.expect(okid('a'));
    try std.testing.expect(okid('\''));
    try std.testing.expect(!(okid('-')));
    try std.testing.expect(okulid(0x08));
    try std.testing.expect(!(okulid('-')));
    try std.testing.expect(okpath('a'));
    try std.testing.expect(!(okpath('"')));
    try std.testing.expect(!(okpath('\n')));
    try std.testing.expect(!(okpath('>')));
}
