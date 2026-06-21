const std = @import("std");
const word = @import("../runtime/word.zig");
const clib = @import("../runtime/c_abi.zig");
const lex_state = @import("lex_state.zig");
const ls = &lex_state.ls;
const main = @import("../main.zig");
const heap = @import("../runtime/heap.zig");
const rt = @import("../runtime/runtime_state.zig");

const Word = c_long;
const CMBASE: Word = 306;
const NIL: Word = CMBASE + 138;
const NILS: Word = CMBASE + 139;
const UNDEF: Word = CMBASE + 140;
const ATOMLIMIT: Word = CMBASE + 141;

const AP: u8 = 9;
const LAMBDA: u8 = 10;
const CONS: u8 = 11;
const STRCONS: u8 = 7;
const ID: u8 = 8;
const False: Word = CMBASE + 136;
const True: Word = CMBASE + 137;

extern var hd: [*]Word;
extern var tl: [*]Word;
extern var tag: [*]u8;

var lverge: Word = 0;
var prefixbase: ?[*]u8 = null;
var prefixlimit: Word = 1024;
var prefix: Word = 0;
var lastline: Word = 0;
var lastc: Word = 0;
var litmain: Word = 0;
var literate: Word = 0;
var brct: Word = 0;
var rawch: i32 = 0;
var errch: i32 = 0;
var inprelude: bool = true;
var sl: Word = 100;
var pn_lim: Word = 200;
var atnl: Word = 1;

extern var files: Word;
extern var SYNERR: Word;
extern var compiling: c_int;
extern var s_out: ?*word.FILE;
extern var current_file: Word;
extern var errs: Word;
extern var errline: Word;

extern var commandmode: Word;

const make = heap.make;
const mallocPanic = heap.mallocPanic;
extern fn bigscan(s: [*:0]const u8) Word;
extern fn bigxscan(s: [*:0]const u8, limit: [*:0]const u8) Word;
extern fn bigoscan(s: [*:0]const u8, limit: [*:0]const u8) Word;
const sto_dbl = heap.sto_dbl;
const sto_id = heap.sto_id;
const sto_char = heap.sto_char;
extern fn fm_time(path: [*:0]const u8) Word;
const append1 = heap.append1;
extern fn genlstat_t() Word;
extern fn acterror() void;
extern fn syntax(s: [*:0]const u8) void;
extern fn reset() void;
const is_char = heap.is_char;

export fn mira_lex_setup_string(source: [*:0]const u8) void {
    const len = std.mem.len(source);
    const f = word.fmemopen(@ptrCast(@constCast(source)), len, "r") orelse return;
    ls.fileq = cons(make(STRCONS, @intCast(@intFromPtr(f)), NIL), ls.fileq);
    ls.insertdepth += 1;
    main.rs.s_in = f;
}

export fn mira_lex_cleanup() void {
    if (main.rs.s_in) |f| {
        const is_stdio = (f == getStdin()) or (f == getStdout()) or (f == getStderr());
        if (!is_stdio) {
            _ = word.fclose(f);
            main.rs.s_in = null;
        }
    }
}

export fn mira_lex_setup_file(filename: [*:0]const u8) c_int {
    if (openfile(filename) == 0) return 0;
    main.rs.s_in = @ptrFromInt(@as(usize, @intCast(h(h(ls.fileq)))));
    return 1;
}

const FILEINFO: u8 = 3;
const TVAR: u8 = 4;
const STARTREADVALS: u8 = 15;

fn fileinfo(file: Word, line: Word) Word {
    return make(FILEINFO, file, line);
}

fn make_fil(path: [*:0]const u8, time: Word, share: Word, defs: Word) Word {
    return cons(cons(fileinfo(@intCast(@intFromPtr(path)), time), cons(share, NIL)), defs);
}

fn readvals(x: Word, y: Word) Word {
    return make(STARTREADVALS, x, y);
}

fn mktvar(n: Word) Word {
    return make(TVAR, 0, n);
}

fn getStdout() ?*word.FILE {
    const T = @TypeOf(clib.stdout);
    if (comptime @typeInfo(T) == .@"fn") {
        return clib.stdout();
    } else if (comptime @typeInfo(T) == .pointer and @typeInfo(@typeInfo(T).pointer.child) == .@"fn") {
        return clib.stdout();
    } else {
        return clib.stdout;
    }
}

fn getStdin() ?*word.FILE {
    const T = @TypeOf(clib.stdin);
    if (comptime @typeInfo(T) == .@"fn") {
        return clib.stdin();
    } else if (comptime @typeInfo(T) == .pointer and @typeInfo(@typeInfo(T).pointer.child) == .@"fn") {
        return clib.stdin();
    } else {
        return clib.stdin;
    }
}

fn getStderr() ?*word.FILE {
    const T = @TypeOf(clib.stderr);
    if (comptime @typeInfo(T) == .@"fn") {
        return clib.stderr();
    } else if (comptime @typeInfo(T) == .pointer and @typeInfo(@typeInfo(T).pointer.child) == .@"fn") {
        return clib.stderr();
    } else {
        return clib.stderr;
    }
}

fn h(x: Word) Word {
    if (x < ATOMLIMIT) return 0;
    return hd[@as(usize, @intCast(x)) * 2];
}

fn hp(x: Word) *Word {
    std.debug.assert(x >= ATOMLIMIT);
    return &hd[@as(usize, @intCast(x)) * 2];
}

fn t(x: Word) Word {
    if (x < ATOMLIMIT) return 0;
    return tl[@as(usize, @intCast(x)) * 2];
}

fn tp(x: Word) *Word {
    std.debug.assert(x >= ATOMLIMIT);
    return &tl[@as(usize, @intCast(x)) * 2];
}

fn cons(x: Word, y: Word) Word {
    return make(CONS, x, y);
}

fn isconstructor(x: Word) bool {
    return tag[@intCast(x)] == ID and isconstrname(get_id(x)) != 0;
}

fn get_id(x: Word) [*:0]u8 {
    return @ptrCast(@as([*]u8, @ptrFromInt(@as(usize, @intCast(h(h(h(x))))))));
}

fn get_fil(x: Word) [*:0]const u8 {
    return @ptrCast(@as([*]u8, @ptrFromInt(@as(usize, @intCast(h(h(h(x))))))));
}

fn is(s: [*:0]const u8) bool {
    return std.mem.eql(u8, std.mem.span(@as([*:0]u8, @ptrCast(ls.dicp))), std.mem.span(s));
}

fn ovflocheck() void {
    const d_ptr = @as(usize, @intFromPtr(ls.dicq));
    const start_ptr = @as(usize, @intFromPtr(ls.dic));
    if (d_ptr - start_ptr > @as(usize, @intCast(main.rs.DICSPACE))) {
        dicovflo();
    }
}

export fn dicovflo() void {
    main.fatal("\npanic: dictionary overflow\n", .{.{}});
}

export fn setupdic() void {
    const space = main.rs.DICSPACE;
    if (ls.dic == null) {
        const dict_slice = rt.allocator.alloc(u8, @intCast(space)) catch mallocPanic("dictionary");
        ls.dic = dict_slice.ptr;

        const base_slice = rt.allocator.alloc(u8, @intCast(prefixlimit)) catch mallocPanic("prefixbase");
        prefixbase = base_slice.ptr;
    }
    ls.dicp = @ptrCast(ls.dic.?);
    ls.dicq = @ptrCast(ls.dic.?);
    prefixbase.?[0] = 0;
    prefix = 0;
    @memset(&ls.namebucket, 0);
}

fn gethome(n: [*:0]const u8) ?[*:0]const u8 {
    if (n[0] == 0) {
        if (clib.getenv("HOME")) |h_dir| {
            return h_dir;
        }
        return null;
    }
    return null;
}

export fn token() ?[*:0]u8 {
    var ch = clib.getchar();
    ls.dicq = ls.dicp; // uses top of dictionary as temporary work space
    while (ch == ' ' or ch == '\t') {
        ch = clib.getchar();
    }
    if (ch == '~') {
        ls.dicq[0] = @intCast(ch);
        ls.dicq += 1;
        ch = clib.getchar();
        while (clib.isalnum(ch) != 0 or ch == '-' or ch == '_' or ch == '.') {
            ls.dicq[0] = @intCast(ch);
            ls.dicq += 1;
            ch = clib.getchar();
        }
        ls.dicq[0] = 0;
        if (gethome(ls.dicp + 1)) |h_dir| {
            _ = word.strcpy(ls.dicp, h_dir);
            ls.dicq = ls.dicp + word.strlen(ls.dicp);
        }
    }
    while (ch != clib.EOF and clib.isspace(ch) == 0) {
        ls.dicq[0] = @intCast(ch);
        ls.dicq += 1;
        if (ch == '%') {
            const idx = @as(usize, @intFromPtr(ls.dicq)) - @as(usize, @intFromPtr(ls.dicp));
            if (idx >= 2 and (ls.dicq - 2)[0] == '\\') {
                (ls.dicq - 2)[0] = '%';
                ls.dicq -= 1;
            } else {
                ls.dicq -= 1;
                _ = word.strcpy(ls.dicq, main.rs.current_script.?);
                ls.dicq += word.strlen(main.rs.current_script.?);
            }
        }
        ch = clib.getchar();
    }
    ls.dicq[0] = 0;
    ls.dicq += 1;
    ovflocheck();
    while (ch == ' ' or ch == '\t') {
        ch = clib.getchar();
    }
    if (getStdin()) |stdin_file| {
        _ = clib.ungetc(ch, stdin_file);
    }
    if (ls.dicp[0] == 0) {
        return null;
    }
    return ls.dicp;
}

export fn addextn(b: Word, s_input: [*:0]u8) [*:0]u8 {
    var s = s_input;
    var n: Word = @intCast(word.strlen(s));
    if (s[0] == '<' and s[@intCast(n - 1)] == '>') {
        var miralen: usize = 0;
        if (miralen == 0) {
            miralen = word.strlen(main.rs.miralib.?);
        }
        _ = word.strcpy(&main.rs.linebuf[0], main.rs.miralib.?);
        main.rs.linebuf[miralen] = '/';
        _ = word.strcpy(&main.rs.linebuf[miralen + 1], s + 1);
        _ = word.strcpy(ls.dicp, &main.rs.linebuf[0]);
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

fn spaces(n_input: Word) void {
    var n = n_input;
    while (n > 0) : (n -= 1) {
        _ = word.putchar(' ');
    }
}

fn litname(s: [*:0]const u8) bool {
    const n = word.strlen(s);
    return n >= 6 and std.mem.eql(u8, std.mem.span(s + @as(usize, @intCast(n - 6))), ".lit.m");
}

fn getch() c_int {
    if (main.rs.s_in == null) {
        return clib.EOF;
    }
    var ch = clib.getc(main.rs.s_in);
    if (ch == clib.EOF and atnl == 0 and t(ls.fileq) == NIL) {
        atnl = 1;
        return '\n';
    }
    if (atnl != 0) {
        if ((ls.line_no == 0 and commandmode == 0) or (main.rs.magic and ls.line_no == 1 and ls.litstack == NIL)) {
            const is_lit = (ch == '>') or litname(get_fil(current_file));
            literate = if (is_lit) 1 else 0;
            litmain = literate;
        }
        if (literate != 0) {
            var i: Word = 0;
            while (ch != clib.EOF and ch != '>') {
                _ = clib.ungetc(ch, main.rs.s_in);
                ls.line_no += 1;
                _ = word.fgets(ls.dicp, 250, main.rs.s_in);
                if (i == 0 and ls.line_no > 1) {
                    chblank(ls.dicp);
                }
                i += 1;
                if (main.rs.echoing != 0) {
                    spaces(lverge);
                    _ = clib.fputs(ls.dicp, getStdout());
                }
                ch = clib.getc(main.rs.s_in);
            }
            if ((i > 1 or (ls.line_no == 1 and i == 1)) and ch != clib.EOF) {
                chblank(ls.dicp);
            }
            if (ch == '>') {
                if (main.rs.echoing != 0) {
                    _ = word.putchar(ch);
                    spaces(lverge);
                }
                ch = clib.getc(main.rs.s_in);
            }
        }
        atnl = 0;
        ls.col = lverge + literate;
        if (commandmode == 0 and ch != clib.EOF) {
            ls.line_no += 1;
        }
    }
    if (main.rs.echoing != 0 and ch != clib.EOF) {
        _ = word.putchar(ch);
        if (ch == '\n' and literate == 0) {
            if (litmain != 0) {
                _ = word.putchar('>');
                spaces(lverge);
            } else {
                spaces(lverge);
            }
        }
    }
    if (ch == '\t') {
        ls.col = (@divTrunc(ls.col - lverge, 8) + 1) * 8 + lverge;
    } else {
        ls.col += 1;
    }
    if (ch == '\n') {
        atnl = 1;
    }
    return ch;
}

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

fn getlitch() Word {
    const ch: Word = ls.c;
    rawch = @intCast(ch);
    if (ch == '\n') {
        return ch; // always an error
    }
    if (main.rs.UTF8 != 0 and ch > 127) {
        const ch1 = getch();
        ls.c = ch1;
        if ((ch & 0xe0) == 0xc0) { // 2 bytes
            if ((ch1 & 0xc0) != 0x80) {
                return -5; // not valid main.rs.UTF8
            }
            ls.c = getch();
            return sto_char(((ch & 0x1f) << 6) | (ch1 & 0x3f));
        }
        const ch2 = getch();
        ls.c = ch2;
        if ((ch & 0xf0) == 0xe0) { // 3 bytes
            if ((ch1 & 0xc0) != 0x80 or (ch2 & 0xc0) != 0x80) {
                return -5; // not valid main.rs.UTF8
            }
            ls.c = getch();
            return sto_char(((ch & 0xf) << 12) | ((ch1 & 0x3f) << 6) | (ch2 & 0x3f));
        }
        const ch3 = getch();
        ls.c = ch3;
        if ((ch & 0xf8) == 0xf0) { // 4 bytes
            if ((ch1 & 0xc0) != 0x80 or (ch2 & 0xc0) != 0x80 or (ch3 & 0xc0) != 0x80) {
                return -5; // not valid main.rs.UTF8
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
            if (clib.isxdigit(@intCast(ls.c)) != 0) {
                var value: c_uint = 0;
                const N: usize = if (escaped_ch == 'x') 4 else 6;
                var hold = std.mem.zeroes([8]u8);
                var count: usize = 0;
                var xch = ls.c;
                while (clib.isxdigit(@intCast(xch)) != 0 and count < N) {
                    hold[count] = @intCast(xch);
                    count += 1;
                    xch = getch();
                }
                hold[count] = 0;
                _ = clib.sscanf(&hold[0], "%x", .{&value});
                ls.c = xch;
                return if (value > UMAX) -3 else sto_char(@intCast(value));
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
                return sto_char(n);
            }
            if (escaped_ch == '\'' or escaped_ch == '"' or escaped_ch == '\\' or escaped_ch == '`') {
                return escaped_ch;
            }
            if (escaped_ch == '&') {
                return -7;
            }
            errch = if (escaped_ch <= 255) @intCast(escaped_ch) else '?';
            return -6;
        },
    }
}

var rdline_linebuf: [1024]u8 = std.mem.zeroes([1024]u8);

export fn rdline() ?[*:0]u8 {
    var p: [*]u8 = &rdline_linebuf;
    var ch = clib.getchar();
    var expansion: Word = 0;
    while (ch == ' ' or ch == '\t') {
        ch = clib.getchar();
    }
    if (ch == '\n' or (ch == '!' and rdline_linebuf[0] == 0)) {
        if (rdline_linebuf[0] != 0) {
            word.print("!{s}", .{@as([*:0]const u8, @ptrCast(&rdline_linebuf))});
        }
        while (ch != '\n' and ch != clib.EOF) {
            ch = clib.getchar();
        }
        return @ptrCast(&rdline_linebuf);
    }
    if (ch == '!') {
        expansion = 1;
        p = @ptrCast(&rdline_linebuf[word.strlen(&rdline_linebuf) - 1]); // p now points at old '\n'
    } else {
        if (getStdin()) |stdin_file| {
            _ = clib.ungetc(ch, stdin_file);
        }
    }
    while (true) {
        ch = clib.getchar();
        p[0] = @intCast(ch);
        p += 1;
        if (ch == '\n' or ch == clib.EOF) {
            break;
        }
        const offset = @as(usize, @intFromPtr(p)) - @as(usize, @intFromPtr(&rdline_linebuf));
        if (offset >= 1024) {
            p[0] = 0;
            word.printErr("sorry, !command too long (limit={} chars): {s}...\n", .{@as(c_int, 1024), @as([*:0]const u8, @ptrCast(&rdline_linebuf))});
            while (true) {
                ch = clib.getchar();
                if (ch == '\n' or ch == clib.EOF) {
                    break;
                }
            }
            return null;
        }
        if ((p - 1)[0] == '%') {
            if (@intFromPtr(p) > @intFromPtr(&rdline_linebuf[1]) and (p - 2)[0] == '\\') {
                (p - 2)[0] = '%';
                p -= 1;
            } else {
                const remaining = 1024 - (@as(usize, @intFromPtr(p - 1)) - @as(usize, @intFromPtr(&rdline_linebuf)));
                _ = word.strncpy(p - 1, main.rs.current_script.?, remaining);
                p = @ptrCast(&rdline_linebuf[word.strlen(&rdline_linebuf)]);
                expansion = 1;
            }
        }
    }
    p[0] = 0;
    if (expansion != 0) {
        word.print("!{s}", .{@as([*:0]const u8, @ptrCast(&rdline_linebuf))});
    }
    return @ptrCast(&rdline_linebuf);
}

export fn setlmargin() void {
    ls.margstack = cons(ls.lmargin, ls.margstack);
    if (ls.lmargin < ls.col) {
        ls.lmargin = ls.col;
    }
}

export fn unsetlmargin() void {
    if (ls.margstack == NIL) {
        return;
    }
    ls.lmargin = h(ls.margstack);
    ls.margstack = t(ls.margstack);
}

fn errclass(val: Word, string_flag: Word) void {
    const s: [*:0]const u8 = if (string_flag == 2) "char class" else if (string_flag != 0) "string" else "char const";
    if (val == -2) {
        word.print("\\x with no xdigits in {s}\n", .{s});
    } else if (val == -3) {
        word.print("\\hexadecimal escape out of range in {s}\n", .{s});
    } else if (val == -4) {
        word.print("\\decimal escape out of range in {s}\n", .{s});
    } else if (val == -5) {
        word.print("unrecognised character in {s}(main.rs.UTF8 error)\n", .{s});
    } else if (val == -6) {
        word.print("unrecognised escape \\{c} in {s}\n", .{@as(u8, @intCast(errch)), s});
    } else if (val == -7) {
        word.print("illegal use of \\& in char const\n", .{});
    } else {
        word.print("unknown error in {s}\n", .{s});
    }
    acterror();
}

inline fn tryCh(x: Word, y: c_int) ?c_int {
    if (ls.c == x) {
        ls.c = getch();
        return y;
    }
    return null;
}

export fn yylex() c_int {
    if (SYNERR != 0) {
        return clib.END;
    }
    layout();
    ls.tok_start_col = ls.col;
    if (ls.c == '\n') {
        return clib.END;
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
    if (clib.isalpha(@intCast(ls.c)) != 0) {
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
    if ((ls.c >= '0' and ls.c <= '9') or (ls.c == '.' and peekdig() != 0)) {
        if (ls.c == '0' and clib.tolower(@intCast(peekch())) == 'x') {
            hexnumeral();
        } else if (ls.c == '0' and clib.tolower(@intCast(peekch())) == 'o') {
            _ = getch();
            ls.c = getch();
            octnumeral();
        } else {
            numeral();
        }
        return word.CONST;
    }
    if (ls.c == '%' and commandmode == 0) {
        return @intCast(directive());
    }
    if (ls.c == '\'') {
        ls.c = getch();
        ls.yylval = getlitch();
        if (ls.yylval < 0) {
            errclass(ls.yylval, 0);
            return word.CONST;
        }
        if (is_char(ls.yylval) == 0) {
            const prefix_str: [*:0]const u8 = if (main.rs.echoing != 0) "\n" else "";
            word.printErr("{s}impossible event while reading char const ('\\{}')\n", .{prefix_str, ls.yylval});
            acterror();
        }
        if (rawch == '\n' or ls.c != '\'') {
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
            ls.exportfiles = cons(@intCast(@intFromPtr(addextn(1, ls.dicp))), ls.exportfiles);
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
            brct += 1;
        } else if (ls.c == ']') {
            brct -= 1;
        } else if (ls.c == '|' and brct == 0) {
            return word.OFFSIDE;
        }
    }
    if (ls.c == clib.EOF) {
        if (ls.fileq == NIL) {
            ls.c = 0;
            return clib.END;
        }
        if (t(ls.fileq) == NIL and ls.margstack != NIL) {
            return word.OFFSIDE;
        }
        const file_ptr: ?*word.FILE = @ptrFromInt(@as(usize, @intCast(h(h(ls.fileq)))));
        _ = word.fclose(file_ptr);
        ls.fileq = t(ls.fileq);
        ls.insertdepth -= 1;
        if (ls.fileq != NIL and h(ls.echostack) != 0) {
            if (literate != 0) {
                _ = word.putchar('>');
                spaces(lverge);
            }
            word.print("<end of insert>", .{});
        }
        main.rs.s_in = if (ls.fileq == NIL) getStdin() else @ptrFromInt(@as(usize, @intCast(h(h(ls.fileq)))));
        ls.c = ' ';
        if (ls.fileq == NIL) {
            ls.c = 0;
            ls.col = 0;
            ls.lmargin = 0;
            lverge = 0;
            atnl = 1;
            main.rs.echoing = main.rs.verbosity & main.rs.listing;
            lastline = ls.line_no;
            ls.line_no = 0;
            literate = 0;
            litmain = 0;
            return clib.END;
        }
        current_file = t(h(ls.fileq));
        prefix = h(ls.prefixstack);
        ls.prefixstack = t(ls.prefixstack);
        main.rs.echoing = h(ls.echostack);
        ls.echostack = t(ls.echostack);
        lverge = h(ls.vergstack);
        ls.vergstack = t(ls.vergstack);
        literate = h(ls.litstack);
        ls.litstack = t(ls.litstack);
        ls.line_no = h(ls.linostack);
        ls.linostack = t(ls.linostack);
        return yylex();
    }
    lastc = ls.c;
    ls.c = getch();
    switch (lastc) {
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
                if (ls.c == '%' and commandmode == 0) {
                    return @intCast(directive());
                }
                if (clib.isalpha(@intCast(ls.c)) != 0) {
                    kollect(okulid);
                    if (ls.dicp[1] == '_' and ls.dicp[2] == ' ') {
                        return @intCast(identifier(1));
                    }
                }
                syntax("illegal use of underlining\n");
                return '_';
            }
            return @intCast(lastc);
        },
        '-' => {
            if (tryCh('>', word.ARROW)) |ret| return ret;
            if (tryCh('-', word.MINUSMINUS)) |ret| return ret;
            return @intCast(lastc);
        },
        '<' => {
            if (tryCh('-', word.LEFTARROW)) |ret| return ret;
            if (tryCh('=', word.LE)) |ret| return ret;
            return @intCast(lastc);
        },
        '=' => {
            if (ls.c == '>') {
                syntax("unexpected symbol =>\n");
                return '=';
            }
            if (tryCh('=', word.EQEQ)) |ret| return ret;
            return @intCast(lastc);
        },
        '+' => {
            if (tryCh('+', word.PLUSPLUS)) |ret| return ret;
            return @intCast(lastc);
        },
        '.' => {
            if (ls.c == '.') {
                ls.c = getch();
                return word.DOTDOT;
            }
            return @intCast(lastc);
        },
        '\\' => {
            if (tryCh('/', word.VEL)) |ret| return ret;
            return @intCast(lastc);
        },
        '>' => {
            if (tryCh('=', word.GE)) |ret| return ret;
            return @intCast(lastc);
        },
        '~' => {
            if (tryCh('=', word.NE)) |ret| return ret;
            return @intCast(lastc);
        },
        '&' => {
            if (ls.c == '>') {
                ls.c = getch();
                if (ls.c == '>') {
                    ls.yylval = 1;
                } else {
                    ls.yylval = 0;
                    _ = clib.ungetc(@intCast(ls.c), main.rs.s_in);
                }
                ls.c = ' ';
                return word.TO;
            }
            return @intCast(lastc);
        },
        '/' => {
            if (tryCh('/', word.DIAG)) |ret| return ret;
            return @intCast(lastc);
        },
        '*' => {
            if (ls.c == '*') {
                ls.c = getch();
                return @intCast(collectstars());
            }
            return @intCast(lastc);
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
            return @intCast(lastc);
        },
        '$' => {
            if (clib.isalpha(@intCast(ls.c)) != 0) {
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
                    word.print("{s}syntax error: illegal symbol ${}{s}\n", .{if (main.rs.echoing != 0) @as([*:0]const u8, "\n") else "", n, if (n >= 1000000) @as([*:0]const u8, "...") else ""});
                    acterror();
                } else {
                    ls.yylval = mkgvar(n);
                    return word.NAME;
                }
            }
            if (ls.c == '-') {
                if (compiling == 0) {
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
                    if (compiling == 0) {
                        syntax("unexpected symbol $:-\n");
                    } else {
                        ls.c = getch();
                        ls.yylval = ls.common_stdinb;
                        return word.CONST;
                    }
                }
            }
            if (ls.c == '+') {
                if (compiling == 0) {
                    syntax("unexpected symbol $+\n");
                } else {
                    ls.c = getch();
                    if (commandmode != 0) {
                        ls.yylval = ls.cook_stdin;
                    } else {
                        ls.yylval = make(CONS, readvals(0, 0), word.OFFSIDE);
                    }
                    return word.CONST;
                }
            }
            if (ls.c == '$') {
                if (ls.inlex != 2 and (commandmode == 0 or compiling == 0)) {
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
                ls.yylval = make(AP, word.GETARGS, 0);
                return word.CONST;
            }
            if (ls.c == '0') {
                syntax("illegal symbol $0\n");
            }
            return @intCast(lastc);
        },
        else => return @intCast(lastc),
    }
}

export fn layout() void {
    while (true) {
        if (ls.c == ' ' or (ls.c == '\n' and commandmode == 0) or ls.c == '\t') {
            ls.c = getch();
            continue;
        }
        if (ls.c == clib.EOF and commandmode != 0) {
            ls.c = '\n';
            return;
        }
        if ((ls.c == '|' and peekch() == '|') or (ls.col == 1 and ls.line_no == 1 and ls.c == '#' and peekch() == '!')) {
            ls.c = getch();
            while (ls.c != '\n' and ls.c != clib.EOF) {
                ls.c = getch();
            }
            if (ls.c == clib.EOF and commandmode == 0) {
                return;
            }
            ls.c = '\n';
            continue;
        }
        break;
    }
}

fn collectstars() Word {
    var n: Word = 2;
    while (ls.c == '*') {
        ls.c = getch();
        n += 1;
    }
    ls.yylval = mktvar(n);
    return word.TYPEVAR;
}

export fn mkgvar(i_input: Word) Word {
    var i = i_input;
    var p = &ls.gvars;
    while (i > 1) {
        if (p.* == NIL) {
            p.* = cons(sto_id("gvar"), NIL);
        }
        p = tp(p.*);
        i -= 1;
    }
    if (p.* == NIL) {
        p.* = cons(sto_id("gvar"), NIL);
    }
    return h(p.*);
}

export fn mklexvar(i: Word) Word {
    if (ls.lexvar == 0) {
        ls.lexvar = cons(sto_id("ls.lexvar"), sto_id("ls.lexvar"));
        tp(h(ls.lexvar)).* = main.cs.ltchar;
        tp(t(ls.lexvar)).* = genlstat_t();
    }
    return if (i != 0) t(ls.lexvar) else h(ls.lexvar);
}

export fn conv_args() Word {
    var i = ls.ARGC;
    var x = NIL;
    if (i == 0) {
        return NIL;
    }
    i -= 1;
    while (i > 0) {
        x = cons(str_conv(ls.ARGV[@intCast(i)].?), x);
        i -= 1;
    }
    x = cons(str_conv(ls.ARGV[0].?), x);
    return x;
}

export fn str_conv(s: [*:0]const u8) Word {
    var x = NIL;
    var i = word.strlen(s);
    while (i > 0) {
        i -= 1;
        x = cons(s[i], x);
    }
    return x;
}

pub fn pathname() ?[*:0]u8 {
    layout();
    if (ls.c == '<') {
        const hold = ls.dicp;
        ls.c = getch();
        _ = word.strcpy(ls.dicp, main.rs.miralib.?);
        ls.dicp += word.strlen(main.rs.miralib.?);
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
        while (clib.isalnum(@intCast(ls.c)) != 0 or ls.c == '-' or ls.c == '_' or ls.c == '.') {
            ls.dicp[0] = @intCast(ls.c);
            ls.dicp += 1;
            ls.c = getch();
        }
        ls.dicp[0] = 0;
        if (gethome(hold + 1)) |h_dir| {
            _ = word.strcpy(hold, h_dir);
            ls.dicp = hold + word.strlen(hold);
        } else {
            _ = word.strcpy(&main.rs.linebuf[0], hold);
            _ = word.strcpy(hold, prefixbase.? + @as(usize, @intCast(prefix)));
            ls.dicp = hold + word.strlen(prefixbase.? + @as(usize, @intCast(prefix)));
            _ = word.strcpy(ls.dicp, &main.rs.linebuf[0]);
            ls.dicp += word.strlen(ls.dicp);
        }
        kollect(okpath);
        ls.dicp = hold;
    } else if (ls.c == '/') {
        kollect(okpath);
    } else {
        const hold = ls.dicp;
        _ = word.strcpy(ls.dicp, prefixbase.? + @as(usize, @intCast(prefix)));
        ls.dicp += word.strlen(prefixbase.? + @as(usize, @intCast(prefix)));
        kollect(okpath);
        ls.dicp = hold;
    }
    if (ls.c != '"') {
        return null;
    }
    ls.c = ' ';
    return ls.dicp;
}

export fn adjust_prefix(f: [*:0]const u8) void {
    ls.prefixstack = cons(prefix, ls.prefixstack);
    prefix += @as(Word, @intCast(word.strlen(prefixbase.? + @as(usize, @intCast(prefix))))) + 1;
    while (@as(usize, @intCast(prefix)) + word.strlen(f) >= @as(usize, @intCast(prefixlimit))) {
        const old_limit = prefixlimit;
        prefixlimit += 1024;
        const old_slice = prefixbase.?[0..@intCast(old_limit)];
        const new_slice = rt.allocator.realloc(old_slice, @intCast(prefixlimit)) catch mallocPanic("prefixbase");
        prefixbase = new_slice.ptr;
    }
    _ = word.strcpy(prefixbase.? + @as(usize, @intCast(prefix)), f);
    const g = word.rindex(prefixbase.? + @as(usize, @intCast(prefix)), '/');
    if (g) |gp| {
        gp[1] = 0;
    } else {
        (prefixbase.? + @as(usize, @intCast(prefix)))[0] = 0;
    }
}

pub fn peekdig() c_int {
    if (main.rs.s_in == null) return 0;
    const ch = clib.getc(main.rs.s_in);
    _ = clib.ungetc(ch, main.rs.s_in);
    return if (ch >= '0' and ch <= '9') 1 else 0;
}

pub fn peekch() c_int {
    if (main.rs.s_in == null) return clib.EOF;
    const ch = clib.getc(main.rs.s_in);
    _ = clib.ungetc(ch, main.rs.s_in);
    return ch;
}

export fn openfile(n: [*:0]const u8) c_int {
    const f = word.fopen(n, "r") orelse return 0;
    ls.fileq = cons(make(STRCONS, @intCast(@intFromPtr(f)), NIL), ls.fileq);
    ls.insertdepth += 1;
    return 1;
}

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
    if (commandmode != 0 and main.rs.lastid == 0 and h(ls.yylval) != 0) {
        if (t(h(ls.yylval)) != 0) {
            main.rs.lastid = ls.yylval;
        }
    }
    return if (isconstructor(ls.yylval)) word.CNAME else word.NAME;
}

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
                if (main.rs.magic) {
                    syntax("%export directive not permitted in \"-exp\" script\n");
                }
                return word.EXPORT;
            }
        },
        'f' => {
            if (is("free") or is("_ f_ r_ e_ e")) {
                if (main.rs.magic) {
                    syntax("%free directive not permitted in \"-exp\" script\n");
                }
                return word.FREE;
            }
        },
        'i' => {
            if (is("include") or is("_ i_ n_ c_ l_ u_ d_ e")) {
                if (SYNERR == 0) {
                    layout();
                    setlmargin();
                }
                if (pathname() == null) {
                    syntax("bad pathname after %include\n");
                } else {
                    ls.yylval = make(STRCONS, @intCast(@intFromPtr(addextn(1, ls.dicp))), fileinfo(@intCast(@intFromPtr(get_fil(current_file))), holdlin));
                    _ = keep(ls.dicp);
                }
                return word.INCLUDE;
            }
            if (is("insert") or is("_ i_ n_ s_ e_ r_ t")) {
                const f = pathname();
                if (f == null) {
                    syntax("bad pathname after %insert\n");
                } else if (ls.insertdepth < 12 and openfile(f.?) != 0) {
                    adjust_prefix(f.?);
                    ls.vergstack = cons(lverge, ls.vergstack);
                    ls.echostack = cons(main.rs.echoing, ls.echostack);
                    ls.litstack = cons(literate, ls.litstack);
                    ls.linostack = make(STRCONS, ls.line_no, ls.linostack);
                    ls.line_no = 0;
                    atnl = 1;
                    _ = keep(ls.dicp);
                    current_file = make_fil(f.?, fm_time(f.?), 0, NIL);
                    files = append1(files, cons(current_file, NIL));
                    tp(h(ls.fileq)).* = current_file;
                    main.rs.s_in = @ptrFromInt(@as(usize, @intCast(h(h(ls.fileq)))));
                    const is_lit = (peekch() == '>') or litname(f.?);
                    literate = if (is_lit) 1 else 0;
                    ls.col = holdcol;
                    lverge = holdcol;
                    if (main.rs.echoing != 0) {
                        _ = word.putchar('\n');
                        if (literate == 0) {
                            if (litmain != 0) {
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
                    const prefix_str: [*:0]const u8 = if (main.rs.echoing != 0) "\n" else "";
                    word.print("{s}%insert error - cannot open \"{s}\"\n", .{prefix_str, f.?});
                    _ = keep(ls.dicp);
                    if (toomany) {
                        word.print("too many nested %insert directives (limit={})\n", .{ls.insertdepth});
                    } else {
                        files = append1(files, cons(make_fil(f.?, 0, 0, NIL), NIL));
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
                main.rs.echoing = main.rs.verbosity;
                return yylex();
            }
        },
        'n' => {
            if (is("nolist") or is("_ n_ o_ l_ i_ s_ t")) {
                main.rs.echoing = 0;
                return yylex();
            }
        },
        else => {},
    }
    if (main.rs.echoing != 0) {
        _ = word.putchar('\n');
    }
    word.print("syntax error: unknown directive \"%{s}\"\n", .{ls.dicp});
    acterror();
    return clib.END;
}

fn kollect(f: fn (c_int) callconv(.c) c_int) void {
    ls.dicq = ls.dicp;
    while (f(@intCast(ls.c)) != 0) {
        ls.dicq[0] = @intCast(ls.c);
        ls.dicq += 1;
        ls.c = getch();
    }
    ls.dicq[0] = 0;
    ls.dicq += 1;
    ovflocheck();
}

export fn keep(p: [*:0]u8) [*:0]u8 {
    if (p == ls.dicp) {
        ls.dicp = ls.dicq;
    } else {
        _ = word.strcpy(ls.dicp, p);
        const ret = ls.dicp;
        ls.dicp = ls.dicp + word.strlen(ls.dicp) + 1;
        ls.dicq = ls.dicp;
        dic_check();
        return ret;
    }
    return p;
}

export fn dic_check() void {
    ovflocheck();
}

pub fn numeral() void {
    var nflag: Word = 1;
    ls.dicq = ls.dicp;
    while (ls.c >= '0' and ls.c <= '9') {
        ls.dicq[0] = @intCast(ls.c);
        ls.dicq += 1;
        ls.c = getch();
    }
    if (ls.c == '.' and peekdig() != 0) {
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
        _ = clib.sscanf(ls.dicp, "%lf", .{&r});
        ls.yylval = sto_dbl(r);
    }
}

pub fn hexnumeral() void {
    ls.dicq = ls.dicp;
    ls.dicq[0] = @intCast(ls.c); // 0
    ls.dicq += 1;
    ls.c = getch();
    ls.dicq[0] = @intCast(ls.c); // x
    ls.dicq += 1;
    ls.c = getch();
    if (clib.isxdigit(@intCast(ls.c)) == 0 and ls.c != '.') {
        syntax("malformed hex number\n");
    }
    while (ls.c == '0' and clib.isxdigit(@intCast(peekch())) != 0) {
        ls.c = getch(); // skip zeros before first nonzero digit
    }
    while (clib.isxdigit(@intCast(ls.c)) != 0) {
        ls.dicq[0] = @intCast(ls.c);
        ls.dicq += 1;
        ls.c = getch();
    }
    ovflocheck();
    if (ls.c == '.' or clib.tolower(@intCast(ls.c)) == 'p') {
        var d: f64 = 0.0;
        if (ls.c == '.') {
            ls.dicq[0] = @intCast(ls.c);
            ls.dicq += 1;
            ls.c = getch();
            while (clib.isxdigit(@intCast(ls.c)) != 0) {
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
        if (len > 60 or clib.sscanf(ls.dicp, "%lf", .{&d}) != 1) {
            syntax("malformed hex float\n");
        } else {
            ls.yylval = sto_dbl(d);
        }
        return;
    }
    ls.dicq[0] = 0;
    ls.yylval = bigxscan(ls.dicp + 2, ls.dicq);
}

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

pub fn getfname(x: Word) Word {
    const p = get_id(x);
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
        main.fatal("impossible event in getfname\n", .{.{}});
    }
    (ls.dicq - 2)[0] = 0;
    ovflocheck();
    return name();
}

export fn name() Word {
    const h_idx = @as(usize, @intCast(hash(ls.dicp)));
    var q = ls.namebucket[h_idx];
    while (q != 0 and !is(get_id(h(q)))) {
        q = t(q);
    }
    if (q == 0) {
        q = sto_id(ls.dicp);
        ls.namebucket[h_idx] = cons(q, ls.namebucket[h_idx]);
        _ = keep(ls.dicp);
    } else {
        q = h(q);
    }
    return q;
}

export fn make_id(n: [*:0]const u8) Word {
    const h_idx = @as(usize, @intCast(hash(n)));
    const x = sto_id(if (inprelude) keep(@constCast(n)) else n);
    ls.namebucket[h_idx] = cons(x, ls.namebucket[h_idx]);
    return x;
}

export fn findid(n: [*:0]const u8) Word {
    const h_idx = @as(usize, @intCast(hash(n)));
    var q = ls.namebucket[h_idx];
    while (q != 0 and !std.mem.eql(u8, std.mem.span(n), std.mem.span(get_id(h(q))))) {
        q = t(q);
    }
    return if (q != 0) h(q) else NIL;
}

export fn reset_pns() void {
    ls.nextpn = 0;
    if (ls.pnvec == null) {
        const slice = rt.allocator.alloc(Word, @intCast(pn_lim)) catch mallocPanic("ls.pnvec");
        ls.pnvec = slice.ptr;
    }
}

export fn make_pn(val: Word) Word {
    if (ls.nextpn == pn_lim) {
        const old_lim = pn_lim;
        pn_lim += 400;
        const old_slice = ls.pnvec.?[0..@intCast(old_lim)];
        const slice = rt.allocator.realloc(old_slice, @intCast(pn_lim)) catch mallocPanic("ls.pnvec");
        ls.pnvec = slice.ptr;
    }
    ls.pnvec.?[@intCast(ls.nextpn)] = make(STRCONS, ls.nextpn, val);
    const ret = ls.pnvec.?[@intCast(ls.nextpn)];
    ls.nextpn += 1;
    return ret;
}

export fn sto_pn(n: Word) Word {
    if (n >= pn_lim) {
        const old_lim = pn_lim;
        while (pn_lim <= n) {
            pn_lim += 400;
        }
        const old_slice = ls.pnvec.?[0..@intCast(old_lim)];
        const slice = rt.allocator.realloc(old_slice, @intCast(pn_lim)) catch mallocPanic("ls.pnvec");
        ls.pnvec = slice.ptr;
    }
    while (ls.nextpn <= n) {
        ls.pnvec.?[@intCast(ls.nextpn)] = make(STRCONS, ls.nextpn, UNDEF);
        ls.nextpn += 1;
    }
    return ls.pnvec.?[@intCast(n)];
}

export fn mkprivate(x_input: Word) void {
    var x = x_input;
    while (x != NIL) {
        get_id(h(x))[0] += 128;
        x = t(x);
    }
    inprelude = false;
}

pub fn string() void {
    var p: Word = undefined;
    var ch: Word = undefined;
    var badch: Word = 0;
    ls.c = getch();
    ch = getlitch();
    ls.yylval = cons(NIL, NIL);
    p = ls.yylval;
    while (ch != clib.EOF and rawch != '"' and rawch != '\n') {
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
    if (rawch == '\n') {
        syntax("non-escaped newline encountered inside string quotes\n");
    } else if (ch == clib.EOF) {
        if (main.rs.echoing != 0) {
            _ = word.putchar('\n');
        }
        word.print("syntax error: script ends inside unclosed string quotes - \n", .{});
        word.print("    \"", .{});
        while (ls.yylval != NIL and sl > 0) {
            _ = word.putchar(@intCast(h(ls.yylval)));
            ls.yylval = t(ls.yylval);
            sl -= 1;
        }
        word.print("...\"\n", .{});
        acterror();
    }
}

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
    while (ch != clib.EOF and rawch != '`' and rawch != '\n') {
        if (ch == -7) {
            ch = getlitch();
        } else if (ch < 0) {
            badch = ch;
            break;
        } else {
            if (rawch == '-' and h(p) != NIL and h(p) != word.DOTDOT) {
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
    if (rawch == '\n') {
        syntax("non-escaped newline encountered in char class\n");
    } else if (ch == clib.EOF) {
        if (main.rs.echoing != 0) {
            _ = word.putchar('\n');
        }
        word.print("syntax error: script ends inside unclosed char class brackets - \n", .{});
        word.print("    [", .{});
        while (ls.yylval != NIL and sl > 0) {
            _ = word.putchar(@intCast(h(ls.yylval)));
            ls.yylval = t(ls.yylval);
            sl -= 1;
        }
        word.print("...]\n", .{});
        acterror();
    }
    return anti;
}

export fn reset_lex() void {
    if (commandmode == 0) {
        if (errs == 0) {
            errs = fileinfo(@intCast(@intFromPtr(get_fil(current_file))), ls.line_no);
        }
        const err_script_raw = @as(?[*:0]const u8, @ptrCast(@as(*anyopaque, @ptrFromInt(@as(usize, @intCast(h(errs)))))));
        const err_script = err_script_raw orelse "test.m";
        const is_current = if (err_script_raw) |es|
            (if (main.rs.current_script) |cs| es == @as([*:0]const u8, @ptrCast(cs)) else false)
        else
            true;
        if (t(errs) == 0 and is_current) {
            word.printErr("error occurs at end of ", .{});
        } else {
            word.printErr("error found near line {} of ", .{t(errs)});
        }
        word.printErr("{s}file \"{s}\"\ncompilation abandoned\n", .{if (is_current) @as([*:0]const u8, "") else "%insert ", err_script});
        if (is_current) {
            errline = if (t(errs) == 0) lastline else t(errs);
            errs = 0;
        } else {
            if (ls.linostack != NIL) {
                while (t(ls.linostack) != NIL) {
                    ls.linostack = t(ls.linostack);
                }
                errline = h(ls.linostack);
            } else {
                errline = lastline;
            }
        }
    }
    reset_state();
}

export fn reset_state() void {
    if (commandmode != 0) {
        while (ls.c != '\n' and ls.c != clib.EOF) {
            if (main.rs.s_in) |sin| {
                ls.c = clib.getc(sin);
            } else {
                ls.c = clib.EOF;
            }
        }
    }
    while (ls.fileq != NIL) {
        const file_ptr: ?*word.FILE = @ptrFromInt(@as(usize, @intCast(h(h(ls.fileq)))));
        _ = word.fclose(file_ptr);
        ls.fileq = t(ls.fileq);
    }
    ls.insertdepth = -1;
    main.rs.s_in = getStdin();
    ls.echostack = NIL;
    ls.idsused = NIL;
    ls.prefixstack = NIL;
    ls.litstack = NIL;
    ls.linostack = NIL;
    ls.vergstack = NIL;
    ls.margstack = NIL;
    prefix = 0;
    prefixbase.?[0] = 0;
    main.rs.echoing = main.rs.verbosity & main.rs.listing;
    brct = 0;
    ls.inbnf = 0;
    ls.sreds = 0;
    ls.inlex = 0;
    ls.inexplist = 0;
    commandmode = 0;
    lverge = 0;
    ls.col = 0;
    ls.lmargin = 0;
    atnl = 1;
    main.cs.rv_script = 0;
    main.cs.algshfns = NIL;
    main.cs.newtyps = NIL;
    main.cs.showchain = NIL;
    main.cs.SGC = NIL;
    main.cs.TABSTRS = NIL;
    ls.c = ' ';
    ls.line_no = 0;
    litmain = 0;
    literate = 0;
    errs = 0;
    errline = 0;
}

export fn hash(input: [*:0]const u8) callconv(.c) c_int {
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

export fn isconstrname(input: [*:0]const u8) callconv(.c) c_int {
    var s = input;
    if (s[0] == '$') s += 1;
    return if (std.ascii.isUpper(s[0])) 1 else 0;
}

export fn okid(ch: c_int) callconv(.c) c_int {
    return if ((ch >= 'a' and ch <= 'z') or
        (ch >= 'A' and ch <= 'Z') or
        (ch >= '0' and ch <= '9') or
        ch == '_' or
        ch == '\'') 1 else 0;
}

export fn okulid(ch: c_int) callconv(.c) c_int {
    return if ((ch >= 'a' and ch <= 'z') or
        (ch >= 'A' and ch <= 'Z') or
        (ch >= '0' and ch <= '9') or
        ch == '_' or
        ch == 0x08 or
        ch == '\'') 1 else 0;
}

export fn okpath(ch: c_int) callconv(.c) c_int {
    return if (ch != '"' and ch != '\n' and ch != '>') 1 else 0;
}

test "hash matches xor into seven-bit bucket" {
    try std.testing.expectEqual(@as(c_int, 0), hash(""));
    try std.testing.expectEqual(@as(c_int, 'a'), hash("a"));
    try std.testing.expectEqual(@as(c_int, ('a' ^ 'b' ^ 'c') & 127), hash("abc"));
}

test "identifier classification matches Miranda lexer rules" {
    try std.testing.expect(isconstrname("Name") == 1);
    try std.testing.expect(isconstrname("$Name") == 1);
    try std.testing.expect(isconstrname("name") == 0);
    try std.testing.expect(okid('a') == 1);
    try std.testing.expect(okid('\'') == 1);
    try std.testing.expect(okid('-') == 0);
    try std.testing.expect(okulid(0x08) == 1);
    try std.testing.expect(okulid('-') == 0);
    try std.testing.expect(okpath('a') == 1);
    try std.testing.expect(okpath('"') == 0);
    try std.testing.expect(okpath('\n') == 0);
    try std.testing.expect(okpath('>') == 0);
}
