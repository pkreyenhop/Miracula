const std = @import("std");
const clib = @import("../runtime/c_abi.zig");
const main = @import("../main.zig");

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

export var fileq: Word = NIL;
export var margstack: Word = NIL;
export var col: Word = 0;
export var tok_start_col: Word = 0;
export var vergstack: Word = NIL;
export var line_no: Word = 0;
export var litstack: Word = NIL;
export var linostack: Word = NIL;
export var c: Word = ' ';
export var common_stdin: Word = 0;
export var common_stdinb: Word = 0;
export var cook_stdin: Word = 0;

export var blankerr: c_int = 0;
export var gvars: Word = NIL;
export var lexvar: Word = 0;
export var namebucket: [128]Word = std.mem.zeroes([128]Word);
export var nextpn: Word = 0;
export var pnvec: ?[*]Word = null;

export var dic: ?[*]u8 = null;
export var dicp: [*:0]u8 = undefined;
export var dicq: [*:0]u8 = undefined;

export var insertdepth: Word = -1;
export var lmargin: Word = 0;
export var echostack: Word = NIL;
var lverge: Word = 0;
var prefixbase: ?[*]u8 = null;
var prefixlimit: Word = 1024;
var prefix: Word = 0;
export var prefixstack: Word = NIL;
var lastline: Word = 0;
var lastc: Word = 0;
var litmain: Word = 0;
var literate: Word = 0;
var brct: Word = 0;
var rawch: c_int = 0;
var errch: c_int = 0;
var inprelude: c_int = 1;
var sl: Word = 100;
var pn_lim: Word = 200;
var atnl: Word = 1;

export var inbnf: Word = 0;
export var inlex: Word = 0;
extern var files: Word;
extern var SYNERR: Word;
export var sreds: Word = 0;
export var exportfiles: Word = NIL;
export var inexplist: Word = 0;
extern var compiling: c_int;
extern var s_out: ?*clib.FILE;
extern var current_file: Word;
extern var errs: Word;
extern var errline: Word;
extern var ltchar: Word;

extern var TABSTRS: Word;
extern var SGC: Word;
extern var newtyps: Word;
extern var showchain: Word;
extern var algshfns: Word;
extern var rv_script: Word;
export var idsused: Word = NIL;
export var ARGC: c_int = 0;
export var ARGV: [*]?[*:0]u8 = undefined;
export var yylval: Word = NIL;
extern var commandmode: Word;

extern fn make(t_tag: u8, x: Word, y: Word) Word;
extern fn mallocfail(s: [*:0]const u8) void;
extern fn bigscan(s: [*:0]const u8) Word;
extern fn bigxscan(s: [*:0]const u8, limit: [*:0]const u8) Word;
extern fn bigoscan(s: [*:0]const u8, limit: [*:0]const u8) Word;
extern fn sto_dbl(d: f64) Word;
extern fn sto_id(s: [*:0]const u8) Word;
extern fn sto_char(ch: Word) Word;
extern fn fm_time(path: [*:0]const u8) Word;
extern fn append1(list: Word, el: Word) Word;
extern fn genlstat_t() Word;
extern fn acterror() void;
extern fn syntax(s: [*:0]const u8) void;
extern fn reset() void;
extern fn is_char(x: Word) c_int;

export fn mira_lex_setup_string(source: [*:0]const u8) void {
    const len = std.mem.len(source);
    const f = clib.fmemopen(@ptrCast(@constCast(source)), len, "r") orelse return;
    fileq = cons(make(STRCONS, @intCast(@intFromPtr(f)), NIL), fileq);
    insertdepth += 1;
    main.rs.s_in = f;
}

export fn mira_lex_cleanup() void {
    if (main.rs.s_in) |f| {
        const is_stdio = (f == getStdin()) or (f == getStdout()) or (f == getStderr());
        if (!is_stdio) {
            _ = clib.fclose(f);
            main.rs.s_in = null;
        }
    }
}

export fn mira_lex_setup_file(filename: [*:0]const u8) c_int {
    if (openfile(filename) == 0) return 0;
    main.rs.s_in = @ptrFromInt(@as(usize, @intCast(h(h(fileq)))));
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

fn getStdout() ?*clib.FILE {
    const T = @TypeOf(clib.stdout);
    if (comptime @typeInfo(T) == .@"fn") {
        return clib.stdout();
    } else if (comptime @typeInfo(T) == .pointer and @typeInfo(@typeInfo(T).pointer.child) == .@"fn") {
        return clib.stdout();
    } else {
        return clib.stdout;
    }
}

fn getStdin() ?*clib.FILE {
    const T = @TypeOf(clib.stdin);
    if (comptime @typeInfo(T) == .@"fn") {
        return clib.stdin();
    } else if (comptime @typeInfo(T) == .pointer and @typeInfo(@typeInfo(T).pointer.child) == .@"fn") {
        return clib.stdin();
    } else {
        return clib.stdin;
    }
}

fn getStderr() ?*clib.FILE {
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
    return clib.strcmp(dicp, s) == 0;
}

fn ovflocheck() void {
    const d_ptr = @as(usize, @intFromPtr(dicq));
    const start_ptr = @as(usize, @intFromPtr(dic));
    if (d_ptr - start_ptr > @as(usize, @intCast(main.rs.DICSPACE))) {
        dicovflo();
    }
}

export fn dicovflo() void {
    _ = clib.fprintf(getStderr().?, "\npanic: dictionary overflow\n", .{.{}});
    clib.exit(1);
}

export fn setupdic() void {
    const space = main.rs.DICSPACE;
    if (dic == null) {
        const ptr = clib.malloc(@intCast(space)) orelse {
            mallocfail("dictionary");
            unreachable;
        };
        dic = @ptrCast(ptr);

        const base_ptr = clib.malloc(@intCast(prefixlimit)) orelse {
            mallocfail("prefixbase");
            unreachable;
        };
        prefixbase = @ptrCast(base_ptr);
    }
    dicp = @ptrCast(dic.?);
    dicq = @ptrCast(dic.?);
    prefixbase.?[0] = 0;
    prefix = 0;
    @memset(&namebucket, 0);
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
    dicq = dicp; // uses top of dictionary as temporary work space
    while (ch == ' ' or ch == '\t') {
        ch = clib.getchar();
    }
    if (ch == '~') {
        dicq[0] = @intCast(ch);
        dicq += 1;
        ch = clib.getchar();
        while (clib.isalnum(ch) != 0 or ch == '-' or ch == '_' or ch == '.') {
            dicq[0] = @intCast(ch);
            dicq += 1;
            ch = clib.getchar();
        }
        dicq[0] = 0;
        if (gethome(dicp + 1)) |h_dir| {
            _ = clib.strcpy(dicp, h_dir);
            dicq = dicp + clib.strlen(dicp);
        }
    }
    while (ch != clib.EOF and clib.isspace(ch) == 0) {
        dicq[0] = @intCast(ch);
        dicq += 1;
        if (ch == '%') {
            const idx = @as(usize, @intFromPtr(dicq)) - @as(usize, @intFromPtr(dicp));
            if (idx >= 2 and (dicq - 2)[0] == '\\') {
                (dicq - 2)[0] = '%';
                dicq -= 1;
            } else {
                dicq -= 1;
                _ = clib.strcpy(dicq, main.rs.current_script.?);
                dicq += clib.strlen(main.rs.current_script.?);
            }
        }
        ch = clib.getchar();
    }
    dicq[0] = 0;
    dicq += 1;
    ovflocheck();
    while (ch == ' ' or ch == '\t') {
        ch = clib.getchar();
    }
    if (getStdin()) |stdin_file| {
        _ = clib.ungetc(ch, stdin_file);
    }
    if (dicp[0] == 0) {
        return null;
    }
    return dicp;
}

export fn addextn(b: Word, s_input: [*:0]u8) [*:0]u8 {
    var s = s_input;
    var n: Word = @intCast(clib.strlen(s));
    if (s[0] == '<' and s[@intCast(n - 1)] == '>') {
        var miralen: usize = 0;
        if (miralen == 0) {
            miralen = clib.strlen(main.rs.miralib.?);
        }
        _ = clib.strcpy(&main.rs.linebuf[0], main.rs.miralib.?);
        main.rs.linebuf[miralen] = '/';
        _ = clib.strcpy(&main.rs.linebuf[miralen + 1], s + 1);
        _ = clib.strcpy(dicp, &main.rs.linebuf[0]);
        s = dicp;
        n = n + @as(Word, @intCast(miralen)) - 1;
        dicq = dicp + @as(usize, @intCast(n + 1));
        (dicq - 1)[0] = 0; // overwrites '>'
        ovflocheck();
    } else if (s[0] == '"' and s[@intCast(n - 1)] == '"') {
        dicq = dicp;
        var p = s + 1;
        while (p[0] != 0) {
            dicq[0] = p[0];
            dicq += 1;
            p += 1;
        }
        (dicq - 1)[0] = 0; // overwrites '"'
        s = dicp;
        n = n - 2;
    }
    if (b == 0 or clib.strcmp(s + @as(usize, @intCast(n - 2)), ".m") == 0) {
        return s;
    }
    if (s == dicp) {
        dicq -= 1;
    } else {
        dicq = dicp;
        var p = s;
        while (p[0] != 0) {
            dicq[0] = p[0];
            dicq += 1;
            p += 1;
        }
        dicq[0] = 0;
    }
    if (clib.strcmp(dicq - 2, ".x") == 0) {
        dicq -= 2;
    } else if ((dicq - 1)[0] == '.') {
        dicq -= 1;
    }
    _ = clib.strcpy(dicq, ".m");
    dicq += 3;
    ovflocheck();
    return dicp;
}

fn spaces(n_input: Word) void {
    var n = n_input;
    while (n > 0) : (n -= 1) {
        _ = clib.putchar(' ');
    }
}

fn litname(s: [*:0]const u8) bool {
    const n = clib.strlen(s);
    return n >= 6 and clib.strcmp(s + n - 6, ".lit.m") == 0;
}

fn getch() c_int {
    if (main.rs.s_in == null) {
        return clib.EOF;
    }
    var ch = clib.getc(main.rs.s_in);
    if (ch == clib.EOF and atnl == 0 and t(fileq) == NIL) {
        atnl = 1;
        return '\n';
    }
    if (atnl != 0) {
        if ((line_no == 0 and commandmode == 0) or (main.rs.magic != 0 and line_no == 1 and litstack == NIL)) {
            const is_lit = (ch == '>') or litname(get_fil(current_file));
            literate = if (is_lit) 1 else 0;
            litmain = literate;
        }
        if (literate != 0) {
            var i: Word = 0;
            while (ch != clib.EOF and ch != '>') {
                _ = clib.ungetc(ch, main.rs.s_in);
                line_no += 1;
                _ = clib.fgets(dicp, 250, main.rs.s_in);
                if (i == 0 and line_no > 1) {
                    chblank(dicp);
                }
                i += 1;
                if (main.rs.echoing != 0) {
                    spaces(lverge);
                    _ = clib.fputs(dicp, getStdout());
                }
                ch = clib.getc(main.rs.s_in);
            }
            if ((i > 1 or (line_no == 1 and i == 1)) and ch != clib.EOF) {
                chblank(dicp);
            }
            if (ch == '>') {
                if (main.rs.echoing != 0) {
                    _ = clib.putchar(ch);
                    spaces(lverge);
                }
                ch = clib.getc(main.rs.s_in);
            }
        }
        atnl = 0;
        col = lverge + literate;
        if (commandmode == 0 and ch != clib.EOF) {
            line_no += 1;
        }
    }
    if (main.rs.echoing != 0 and ch != clib.EOF) {
        _ = clib.putchar(ch);
        if (ch == '\n' and literate == 0) {
            if (litmain != 0) {
                _ = clib.putchar('>');
                spaces(lverge);
            } else {
                spaces(lverge);
            }
        }
    }
    if (ch == '\t') {
        col = (@divTrunc(col - lverge, 8) + 1) * 8 + lverge;
    } else {
        col += 1;
    }
    if (ch == '\n') {
        atnl = 1;
    }
    return ch;
}

export fn chblank(s_input: [*:0]u8) void {
    var s = s_input;
    while (s[0] == ' ' or s[0] == '\t') {
        s += 1;
    }
    if (s[0] == '\n') {
        return;
    }
    syntax("formal text not delimited by blank line\n");
    blankerr = 1;
    reset(); // easiest way to recover is to pretend it was an interrupt
}

const UMAX: Word = 0x10ffff;

fn getlitch() Word {
    const ch: Word = c;
    rawch = @intCast(ch);
    if (ch == '\n') {
        return ch; // always an error
    }
    if (main.rs.UTF8 != 0 and ch > 127) {
        const ch1 = getch();
        c = ch1;
        if ((ch & 0xe0) == 0xc0) { // 2 bytes
            if ((ch1 & 0xc0) != 0x80) {
                return -5; // not valid main.rs.UTF8
            }
            c = getch();
            return sto_char(((ch & 0x1f) << 6) | (ch1 & 0x3f));
        }
        const ch2 = getch();
        c = ch2;
        if ((ch & 0xf0) == 0xe0) { // 3 bytes
            if ((ch1 & 0xc0) != 0x80 or (ch2 & 0xc0) != 0x80) {
                return -5; // not valid main.rs.UTF8
            }
            c = getch();
            return sto_char(((ch & 0xf) << 12) | ((ch1 & 0x3f) << 6) | (ch2 & 0x3f));
        }
        const ch3 = getch();
        c = ch3;
        if ((ch & 0xf8) == 0xf0) { // 4 bytes
            if ((ch1 & 0xc0) != 0x80 or (ch2 & 0xc0) != 0x80 or (ch3 & 0xc0) != 0x80) {
                return -5; // not valid main.rs.UTF8
            }
            c = getch();
            return ((ch & 7) << 18) | ((ch1 & 0x3f) << 12) | ((ch2 & 0x3f) << 6) | (ch3 & 0x3f);
        }
        return -5;
    }
    if (ch != '\\') {
        c = getch();
        return ch;
    }
    const escaped_ch = getch();
    c = getch();
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
            if (clib.isxdigit(@intCast(c)) != 0) {
                var value: c_uint = 0;
                const N: usize = if (escaped_ch == 'x') 4 else 6;
                var hold = std.mem.zeroes([8]u8);
                var count: usize = 0;
                var xch = c;
                while (clib.isxdigit(@intCast(xch)) != 0 and count < N) {
                    hold[count] = @intCast(xch);
                    count += 1;
                    xch = getch();
                }
                hold[count] = 0;
                _ = clib.sscanf(&hold[0], "%x", .{&value});
                c = xch;
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
                var xch = c;
                while (xch >= '0' and xch <= '9' and count < N) {
                    n = (10 * n) + xch - '0';
                    count += 1;
                    xch = getch();
                }
                c = xch;
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
            _ = clib.printf("!%s", .{.{&rdline_linebuf}});
        }
        while (ch != '\n' and ch != clib.EOF) {
            ch = clib.getchar();
        }
        return @ptrCast(&rdline_linebuf);
    }
    if (ch == '!') {
        expansion = 1;
        p = @ptrCast(&rdline_linebuf[clib.strlen(&rdline_linebuf) - 1]); // p now points at old '\n'
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
            _ = clib.fprintf(getStderr().?, "sorry, !command too long (limit=%d chars): %s...\n", .{.{@as(c_int, 1024), &rdline_linebuf}});
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
                _ = clib.strncpy(p - 1, main.rs.current_script.?, remaining);
                p = @ptrCast(&rdline_linebuf[clib.strlen(&rdline_linebuf)]);
                expansion = 1;
            }
        }
    }
    p[0] = 0;
    if (expansion != 0) {
        _ = clib.printf("!%s", .{.{&rdline_linebuf}});
    }
    return @ptrCast(&rdline_linebuf);
}

export fn setlmargin() void {
    margstack = cons(lmargin, margstack);
    if (lmargin < col) {
        lmargin = col;
    }
}

export fn unsetlmargin() void {
    if (margstack == NIL) {
        return;
    }
    lmargin = h(margstack);
    margstack = t(margstack);
}

fn errclass(val: Word, string_flag: Word) void {
    const s: [*:0]const u8 = if (string_flag == 2) "char class" else if (string_flag != 0) "string" else "char const";
    if (val == -2) {
        _ = clib.printf("\\x with no xdigits in %s\n", .{.{s}});
    } else if (val == -3) {
        _ = clib.printf("\\hexadecimal escape out of range in %s\n", .{.{s}});
    } else if (val == -4) {
        _ = clib.printf("\\decimal escape out of range in %s\n", .{.{s}});
    } else if (val == -5) {
        _ = clib.printf("unrecognised character in %s(main.rs.UTF8 error)\n", .{.{s}});
    } else if (val == -6) {
        _ = clib.printf("unrecognised escape \\%c in %s\n", .{.{errch, s}});
    } else if (val == -7) {
        _ = clib.printf("illegal use of \\& in char const\n", .{.{}});
    } else {
        _ = clib.printf("unknown error in %s\n", .{.{s}});
    }
    acterror();
}

inline fn tryCh(x: Word, y: c_int) ?c_int {
    if (c == x) {
        c = getch();
        return y;
    }
    return null;
}

export fn yylex() c_int {
    if (SYNERR != 0) {
        return clib.END;
    }
    layout();
    tok_start_col = col;
    if (c == '\n') {
        return clib.END;
    }
    if (col < lmargin) {
        if (c == '=' and (margstack == NIL or col >= h(margstack))) {
            c = getch();
            return clib.ELSEQ;
        }
        return clib.OFFSIDE;
    }
    if (c == ';') {
        c = getch();
        layout();
        if (c == '=' and (margstack == NIL or col >= h(margstack))) {
            c = getch();
            return clib.ELSEQ;
        }
        return ';';
    }
    if (clib.isalpha(@intCast(c)) != 0) {
        kollect(okid);
        if (inlex == 1) {
            layout();
            yylval = name();
            return if (c == '=') clib.LEXDEF else if (isconstructor(yylval)) clib.CNAME else clib.NAME;
        }
        if (inbnf == 1) {
            (dicq - 1)[0] = ' ';
            dicq[0] = 0;
            dicq += 1;
        }
        return @intCast(identifier(0));
    }
    if ((c >= '0' and c <= '9') or (c == '.' and peekdig() != 0)) {
        if (c == '0' and clib.tolower(@intCast(peekch())) == 'x') {
            hexnumeral();
        } else if (c == '0' and clib.tolower(@intCast(peekch())) == 'o') {
            _ = getch();
            c = getch();
            octnumeral();
        } else {
            numeral();
        }
        return clib.CONST;
    }
    if (c == '%' and commandmode == 0) {
        return @intCast(directive());
    }
    if (c == '\'') {
        c = getch();
        yylval = getlitch();
        if (yylval < 0) {
            errclass(yylval, 0);
            return clib.CONST;
        }
        if (is_char(yylval) == 0) {
            const prefix_str: [*:0]const u8 = if (main.rs.echoing != 0) "\n" else "";
            _ = clib.fprintf(getStderr().?, "%simpossible event while reading char const ('\\%lu')\n", .{.{prefix_str, yylval}});
            acterror();
        }
        if (rawch == '\n' or c != '\'') {
            syntax("improperly terminated char const\n");
        } else {
            c = getch();
        }
        return clib.CONST;
    }
    if (inexplist != 0 and (c == '"' or c == '<')) {
        if (pathname() == null) {
            syntax("badly formed pathname in %export list\n");
        } else {
            exportfiles = cons(@intCast(@intFromPtr(addextn(1, dicp))), exportfiles);
            _ = keep(dicp);
        }
        return clib.PATHNAME;
    }
    if (inlex == 1 and c == '`') {
        return if (charclass() != 0) clib.ANTICHARCLASS else clib.CHARCLASS;
    }
    if (c == '"') {
        string();
        if (yylval == NIL) {
            yylval = NILS;
        }
        return clib.CONST;
    }
    if (inbnf == 2) {
        if (c == '[') {
            brct += 1;
        } else if (c == ']') {
            brct -= 1;
        } else if (c == '|' and brct == 0) {
            return clib.OFFSIDE;
        }
    }
    if (c == clib.EOF) {
        if (fileq == NIL) {
            c = 0;
            return clib.END;
        }
        if (t(fileq) == NIL and margstack != NIL) {
            return clib.OFFSIDE;
        }
        const file_ptr: ?*clib.FILE = @ptrFromInt(@as(usize, @intCast(h(h(fileq)))));
        _ = clib.fclose(file_ptr);
        fileq = t(fileq);
        insertdepth -= 1;
        if (fileq != NIL and h(echostack) != 0) {
            if (literate != 0) {
                _ = clib.putchar('>');
                spaces(lverge);
            }
            _ = clib.printf("<end of insert>", .{.{}});
        }
        main.rs.s_in = if (fileq == NIL) getStdin() else @ptrFromInt(@as(usize, @intCast(h(h(fileq)))));
        c = ' ';
        if (fileq == NIL) {
            c = 0;
            col = 0;
            lmargin = 0;
            lverge = 0;
            atnl = 1;
            main.rs.echoing = main.rs.verbosity & main.rs.listing;
            lastline = line_no;
            line_no = 0;
            literate = 0;
            litmain = 0;
            return clib.END;
        }
        current_file = t(h(fileq));
        prefix = h(prefixstack);
        prefixstack = t(prefixstack);
        main.rs.echoing = h(echostack);
        echostack = t(echostack);
        lverge = h(vergstack);
        vergstack = t(vergstack);
        literate = h(litstack);
        litstack = t(litstack);
        line_no = h(linostack);
        linostack = t(linostack);
        return yylex();
    }
    lastc = c;
    c = getch();
    switch (lastc) {
        '_' => {
            if (c == ' ') {
                c = getch();
                if (c == '<') {
                    c = getch();
                    return clib.LE;
                }
                if (c == '>') {
                    c = getch();
                    return clib.GE;
                }
                if (c == '%' and commandmode == 0) {
                    return @intCast(directive());
                }
                if (clib.isalpha(@intCast(c)) != 0) {
                    kollect(okulid);
                    if (dicp[1] == '_' and dicp[2] == ' ') {
                        return @intCast(identifier(1));
                    }
                }
                syntax("illegal use of underlining\n");
                return '_';
            }
            return @intCast(lastc);
        },
        '-' => {
            if (tryCh('>', clib.ARROW)) |ret| return ret;
            if (tryCh('-', clib.MINUSMINUS)) |ret| return ret;
            return @intCast(lastc);
        },
        '<' => {
            if (tryCh('-', clib.LEFTARROW)) |ret| return ret;
            if (tryCh('=', clib.LE)) |ret| return ret;
            return @intCast(lastc);
        },
        '=' => {
            if (c == '>') {
                syntax("unexpected symbol =>\n");
                return '=';
            }
            if (tryCh('=', clib.EQEQ)) |ret| return ret;
            return @intCast(lastc);
        },
        '+' => {
            if (tryCh('+', clib.PLUSPLUS)) |ret| return ret;
            return @intCast(lastc);
        },
        '.' => {
            if (c == '.') {
                c = getch();
                return clib.DOTDOT;
            }
            return @intCast(lastc);
        },
        '\\' => {
            if (tryCh('/', clib.VEL)) |ret| return ret;
            return @intCast(lastc);
        },
        '>' => {
            if (tryCh('=', clib.GE)) |ret| return ret;
            return @intCast(lastc);
        },
        '~' => {
            if (tryCh('=', clib.NE)) |ret| return ret;
            return @intCast(lastc);
        },
        '&' => {
            if (c == '>') {
                c = getch();
                if (c == '>') {
                    yylval = 1;
                } else {
                    yylval = 0;
                    _ = clib.ungetc(@intCast(c), main.rs.s_in);
                }
                c = ' ';
                return clib.TO;
            }
            return @intCast(lastc);
        },
        '/' => {
            if (tryCh('/', clib.DIAG)) |ret| return ret;
            return @intCast(lastc);
        },
        '*' => {
            if (c == '*') {
                c = getch();
                return @intCast(collectstars());
            }
            return @intCast(lastc);
        },
        ':' => {
            if (c == ':') {
                c = getch();
                if (c == '=') {
                    c = getch();
                    return clib.COLON2EQ;
                }
                return clib.COLONCOLON;
            }
            return @intCast(lastc);
        },
        '$' => {
            if (clib.isalpha(@intCast(c)) != 0) {
                kollect(okid);
                const t_val = identifier(0);
                return if (t_val == clib.NAME) clib.INFIXNAME else if (t_val == clib.CNAME) clib.INFIXCNAME else '$';
            }
            if (c >= '1' and c <= '9') {
                var n: Word = 0;
                while (c >= '0' and c <= '9' and n < 1000000) {
                    n = (10 * n) + c - '0';
                    c = getch();
                }
                if (n > sreds) {
                    _ = clib.printf("%ssyntax error: illegal symbol $%ld%s\n", .{.{if (main.rs.echoing != 0) @as([*:0]const u8, "\n") else "", n, if (n >= 1000000) @as([*:0]const u8, "...") else ""}});
                    acterror();
                } else {
                    yylval = mkgvar(n);
                    return clib.NAME;
                }
            }
            if (c == '-') {
                if (compiling == 0) {
                    syntax("unexpected symbol $-\n");
                } else {
                    c = getch();
                    yylval = common_stdin;
                    return clib.CONST;
                }
            }
            if (c == ':') {
                c = getch();
                if (c != '-') {
                    syntax("unexpected symbol $:\n");
                } else {
                    if (compiling == 0) {
                        syntax("unexpected symbol $:-\n");
                    } else {
                        c = getch();
                        yylval = common_stdinb;
                        return clib.CONST;
                    }
                }
            }
            if (c == '+') {
                if (compiling == 0) {
                    syntax("unexpected symbol $+\n");
                } else {
                    c = getch();
                    if (commandmode != 0) {
                        yylval = cook_stdin;
                    } else {
                        yylval = make(CONS, readvals(0, 0), clib.OFFSIDE);
                    }
                    return clib.CONST;
                }
            }
            if (c == '$') {
                if (inlex != 2 and (commandmode == 0 or compiling == 0)) {
                    syntax("unexpected symbol $$\n");
                } else {
                    c = getch();
                    if (inlex != 0) {
                        yylval = mklexvar(0);
                        return clib.NAME;
                    }
                    return clib.DOLLARS;
                }
            }
            if (c == '#') {
                if (inlex != 2) {
                    syntax("unexpected symbol $#\n");
                } else {
                    c = getch();
                    yylval = mklexvar(1);
                    return clib.NAME;
                }
            }
            if (c == '*') {
                c = getch();
                yylval = make(AP, clib.GETARGS, 0);
                return clib.CONST;
            }
            if (c == '0') {
                syntax("illegal symbol $0\n");
            }
            return @intCast(lastc);
        },
        else => return @intCast(lastc),
    }
}

export fn layout() void {
    while (true) {
        if (c == ' ' or (c == '\n' and commandmode == 0) or c == '\t') {
            c = getch();
            continue;
        }
        if (c == clib.EOF and commandmode != 0) {
            c = '\n';
            return;
        }
        if ((c == '|' and peekch() == '|') or (col == 1 and line_no == 1 and c == '#' and peekch() == '!')) {
            c = getch();
            while (c != '\n' and c != clib.EOF) {
                c = getch();
            }
            if (c == clib.EOF and commandmode == 0) {
                return;
            }
            c = '\n';
            continue;
        }
        break;
    }
}

fn collectstars() Word {
    var n: Word = 2;
    while (c == '*') {
        c = getch();
        n += 1;
    }
    yylval = mktvar(n);
    return clib.TYPEVAR;
}

export fn mkgvar(i_input: Word) Word {
    var i = i_input;
    var p = &gvars;
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
    if (lexvar == 0) {
        lexvar = cons(sto_id("lexvar"), sto_id("lexvar"));
        tp(h(lexvar)).* = ltchar;
        tp(t(lexvar)).* = genlstat_t();
    }
    return if (i != 0) t(lexvar) else h(lexvar);
}

export fn conv_args() Word {
    var i = ARGC;
    var x = NIL;
    if (i == 0) {
        return NIL;
    }
    i -= 1;
    while (i > 0) {
        x = cons(str_conv(ARGV[@intCast(i)].?), x);
        i -= 1;
    }
    x = cons(str_conv(ARGV[0].?), x);
    return x;
}

export fn str_conv(s: [*:0]const u8) Word {
    var x = NIL;
    var i = clib.strlen(s);
    while (i > 0) {
        i -= 1;
        x = cons(s[i], x);
    }
    return x;
}

export fn pathname() ?[*:0]u8 {
    layout();
    if (c == '<') {
        const hold = dicp;
        c = getch();
        _ = clib.strcpy(dicp, main.rs.miralib.?);
        dicp += clib.strlen(main.rs.miralib.?);
        dicp[0] = '/';
        dicp += 1;
        kollect(okpath);
        dicp = hold;
        if (c != '>') {
            return null;
        }
        c = ' ';
        return dicp;
    }
    if (c != '"') {
        return null;
    }
    c = getch();
    if (c == '~') {
        const hold = dicp;
        dicp[0] = @intCast(c);
        dicp += 1;
        c = getch();
        while (clib.isalnum(@intCast(c)) != 0 or c == '-' or c == '_' or c == '.') {
            dicp[0] = @intCast(c);
            dicp += 1;
            c = getch();
        }
        dicp[0] = 0;
        if (gethome(hold + 1)) |h_dir| {
            _ = clib.strcpy(hold, h_dir);
            dicp = hold + clib.strlen(hold);
        } else {
            _ = clib.strcpy(&main.rs.linebuf[0], hold);
            _ = clib.strcpy(hold, prefixbase.? + @as(usize, @intCast(prefix)));
            dicp = hold + clib.strlen(prefixbase.? + @as(usize, @intCast(prefix)));
            _ = clib.strcpy(dicp, &main.rs.linebuf[0]);
            dicp += clib.strlen(dicp);
        }
        kollect(okpath);
        dicp = hold;
    } else if (c == '/') {
        kollect(okpath);
    } else {
        const hold = dicp;
        _ = clib.strcpy(dicp, prefixbase.? + @as(usize, @intCast(prefix)));
        dicp += clib.strlen(prefixbase.? + @as(usize, @intCast(prefix)));
        kollect(okpath);
        dicp = hold;
    }
    if (c != '"') {
        return null;
    }
    c = ' ';
    return dicp;
}

export fn adjust_prefix(f: [*:0]const u8) void {
    prefixstack = cons(prefix, prefixstack);
    prefix += @as(Word, @intCast(clib.strlen(prefixbase.? + @as(usize, @intCast(prefix))))) + 1;
    while (@as(usize, @intCast(prefix)) + clib.strlen(f) >= @as(usize, @intCast(prefixlimit))) {
        prefixlimit += 1024;
        const new_ptr = clib.realloc(prefixbase, @intCast(prefixlimit)) orelse {
            mallocfail("prefixbase");
            unreachable;
        };
        prefixbase = @ptrCast(new_ptr);
    }
    _ = clib.strcpy(prefixbase.? + @as(usize, @intCast(prefix)), f);
    const g = clib.rindex(prefixbase.? + @as(usize, @intCast(prefix)), '/');
    if (g) |gp| {
        gp[1] = 0;
    } else {
        (prefixbase.? + @as(usize, @intCast(prefix)))[0] = 0;
    }
}

export fn peekdig() c_int {
    if (main.rs.s_in == null) return 0;
    const ch = clib.getc(main.rs.s_in);
    _ = clib.ungetc(ch, main.rs.s_in);
    return if (ch >= '0' and ch <= '9') 1 else 0;
}

export fn peekch() c_int {
    if (main.rs.s_in == null) return clib.EOF;
    const ch = clib.getc(main.rs.s_in);
    _ = clib.ungetc(ch, main.rs.s_in);
    return ch;
}

export fn openfile(n: [*:0]const u8) c_int {
    const f = clib.fopen(n, "r") orelse return 0;
    fileq = cons(make(STRCONS, @intCast(@intFromPtr(f)), NIL), fileq);
    insertdepth += 1;
    return 1;
}

fn identifier(s: c_int) c_int {
    if (inbnf == 1) {
        if (is("empty ") or is("e_ m_ p_ t_ y")) {
            return clib.EMPTYSY;
        }
        if (is("end ") or is("e_ n_ d")) {
            return clib.ENDSY;
        }
        if (is("error ") or is("e_ r_ r_ o_ r")) {
            return clib.ERRORSY;
        }
        if (is("where ") or is("w_ h_ e_ r_ e")) {
            return clib.WHERE;
        }
    } else {
        switch (dicp[0]) {
            'a' => {
                if (is("abstype") or is("a_ b_ s_ t_ y_ p_ e")) {
                    return clib.ABSTYPE;
                }
            },
            'd' => {
                if (is("div") or is("d_ i_ v")) {
                    return clib.DIV;
                }
            },
            'F' => {
                if (is("False")) {
                    yylval = False;
                    return clib.CONST;
                }
            },
            'i' => {
                if (is("if") or is("i_ f")) {
                    return clib.IF;
                }
            },
            'm' => {
                if (is("mod") or is("m_ o_ d")) {
                    return clib.REM;
                }
            },
            'o' => {
                if (is("otherwise") or is("o_ t_ h_ e_ r_ w_ i_ s_ e")) {
                    return clib.OTHERWISE;
                }
            },
            'r' => {
                if (is("readvals") or is("r_ e_ a_ d_ v_ a_ l_ s")) {
                    return clib.READVALSY;
                }
            },
            's' => {
                if (is("show") or is("s_ h_ o_ w")) {
                    return clib.SHOWSYM;
                }
            },
            'T' => {
                if (is("True")) {
                    yylval = True;
                    return clib.CONST;
                }
            },
            't' => {
                if (is("type") or is("t_ y_ p_ e")) {
                    return clib.TYPE;
                }
            },
            'w' => {
                if (is("where") or is("w_ h_ e_ r_ e")) {
                    return clib.WHERE;
                }
                if (is("with") or is("w_ i_ t_ h")) {
                    return clib.WITH;
                }
            },
            else => {},
        }
    }
    if (s != 0) {
        syntax("illegal use of underlining\n");
        return '_';
    }
    yylval = name();
    if (commandmode != 0 and main.rs.lastid == 0 and h(yylval) != 0) {
        if (t(h(yylval)) != 0) {
            main.rs.lastid = yylval;
        }
    }
    return if (isconstructor(yylval)) clib.CNAME else clib.NAME;
}

export fn directive() Word {
    const holdcol = col - 1;
    const holdlin = line_no;
    c = getch();
    if (c == '%') {
        c = getch();
        return clib.ENDIR;
    }
    kollect(okulid);
    const first_char = if (dicp[0] == '_' and dicp[1] == ' ') dicp[2] else dicp[0];
    switch (first_char) {
        'b' => {
            if (is("begin") or is("_^Hb_^He_^Hg_^Hi_^Hn")) {
                if (inlex != 0) {
                    return clib.LBEGIN;
                }
            }
            if (is("bnf") or is("_^Hb_^Hn_^Hf")) {
                setlmargin();
                col = holdcol + 4;
                return clib.BNF;
            }
        },
        'e' => {
            if (is("export") or is("_ e_ x_ p_ o_ r_ t")) {
                if (main.rs.magic != 0) {
                    syntax("%export directive not permitted in \"-exp\" script\n");
                }
                return clib.EXPORT;
            }
        },
        'f' => {
            if (is("free") or is("_ f_ r_ e_ e")) {
                if (main.rs.magic != 0) {
                    syntax("%free directive not permitted in \"-exp\" script\n");
                }
                return clib.FREE;
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
                    yylval = make(STRCONS, @intCast(@intFromPtr(addextn(1, dicp))), fileinfo(@intCast(@intFromPtr(get_fil(current_file))), holdlin));
                    _ = keep(dicp);
                }
                return clib.INCLUDE;
            }
            if (is("insert") or is("_ i_ n_ s_ e_ r_ t")) {
                const f = pathname();
                if (f == null) {
                    syntax("bad pathname after %insert\n");
                } else if (insertdepth < 12 and openfile(f.?) != 0) {
                    adjust_prefix(f.?);
                    vergstack = cons(lverge, vergstack);
                    echostack = cons(main.rs.echoing, echostack);
                    litstack = cons(literate, litstack);
                    linostack = make(STRCONS, line_no, linostack);
                    line_no = 0;
                    atnl = 1;
                    _ = keep(dicp);
                    current_file = make_fil(f.?, fm_time(f.?), 0, NIL);
                    files = append1(files, cons(current_file, NIL));
                    tp(h(fileq)).* = current_file;
                    main.rs.s_in = @ptrFromInt(@as(usize, @intCast(h(h(fileq)))));
                    const is_lit = (peekch() == '>') or litname(f.?);
                    literate = if (is_lit) 1 else 0;
                    col = holdcol;
                    lverge = holdcol;
                    if (main.rs.echoing != 0) {
                        _ = clib.putchar('\n');
                        if (literate == 0) {
                            if (litmain != 0) {
                                _ = clib.putchar('>');
                                spaces(holdcol);
                            } else {
                                spaces(holdcol);
                            }
                        }
                    }
                    c = getch();
                } else {
                    const toomany = (insertdepth >= 12);
                    const prefix_str: [*:0]const u8 = if (main.rs.echoing != 0) "\n" else "";
                    _ = clib.printf("%s%%insert error - cannot open \"%s\"\n", .{.{prefix_str, f.?}});
                    _ = keep(dicp);
                    if (toomany) {
                        _ = clib.printf("too many nested %%insert directives (limit=%ld)\n", .{.{insertdepth}});
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
                if (inlex != 0) {
                    syntax("nested %lex not permitted\n");
                }
                return clib.LEX;
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
        _ = clib.putchar('\n');
    }
    _ = clib.printf("syntax error: unknown directive \"%%%s\"\n", .{.{dicp}});
    acterror();
    return clib.END;
}

fn kollect(f: fn (c_int) callconv(.c) c_int) void {
    dicq = dicp;
    while (f(@intCast(c)) != 0) {
        dicq[0] = @intCast(c);
        dicq += 1;
        c = getch();
    }
    dicq[0] = 0;
    dicq += 1;
    ovflocheck();
}

export fn keep(p: [*:0]u8) [*:0]u8 {
    if (p == dicp) {
        dicp = dicq;
    } else {
        _ = clib.strcpy(dicp, p);
        const ret = dicp;
        dicp = dicp + clib.strlen(dicp) + 1;
        dicq = dicp;
        dic_check();
        return ret;
    }
    return p;
}

export fn dic_check() void {
    ovflocheck();
}

export fn numeral() void {
    var nflag: Word = 1;
    dicq = dicp;
    while (c >= '0' and c <= '9') {
        dicq[0] = @intCast(c);
        dicq += 1;
        c = getch();
    }
    if (c == '.' and peekdig() != 0) {
        dicq[0] = @intCast(c);
        dicq += 1;
        c = getch();
        nflag = 0;
        while (c >= '0' and c <= '9') {
            dicq[0] = @intCast(c);
            dicq += 1;
            c = getch();
        }
    }
    if (c == 'e') {
        var np: Word = 0;
        dicq[0] = @intCast(c);
        dicq += 1;
        c = getch();
        nflag = 0;
        if (c == '+') {
            c = getch();
        } else if (c == '-') {
            dicq[0] = @intCast(c);
            dicq += 1;
            c = getch();
        }
        if (c < '0' or c > '9') {
            syntax("badly formed floating point number\n");
        }
        while (c == '0') {
            dicq[0] = @intCast(c);
            dicq += 1;
            c = getch();
        }
        while (c >= '0' and c <= '9') {
            np += 1;
            dicq[0] = @intCast(c);
            dicq += 1;
            c = getch();
        }
        if (nflag == 0 and np > 3) {
            syntax("floating point number out of range\n");
            return;
        }
    }
    ovflocheck();
    if (nflag != 0) {
        dicq[0] = 0;
        yylval = bigscan(dicp);
    } else {
        var r: f64 = 0.0;
        const len = @as(usize, @intFromPtr(dicq)) - @as(usize, @intFromPtr(dicp));
        if (len > 60) {
            syntax("illegal floating point constant (too many digits)\n");
            return;
        }
        dicq[0] = '\n';
        dicq[1] = 0;
        _ = clib.sscanf(dicp, "%lf", .{&r});
        yylval = sto_dbl(r);
    }
}

export fn hexnumeral() void {
    dicq = dicp;
    dicq[0] = @intCast(c); // 0
    dicq += 1;
    c = getch();
    dicq[0] = @intCast(c); // x
    dicq += 1;
    c = getch();
    if (clib.isxdigit(@intCast(c)) == 0 and c != '.') {
        syntax("malformed hex number\n");
    }
    while (c == '0' and clib.isxdigit(@intCast(peekch())) != 0) {
        c = getch(); // skip zeros before first nonzero digit
    }
    while (clib.isxdigit(@intCast(c)) != 0) {
        dicq[0] = @intCast(c);
        dicq += 1;
        c = getch();
    }
    ovflocheck();
    if (c == '.' or clib.tolower(@intCast(c)) == 'p') {
        var d: f64 = 0.0;
        if (c == '.') {
            dicq[0] = @intCast(c);
            dicq += 1;
            c = getch();
            while (clib.isxdigit(@intCast(c)) != 0) {
                dicq[0] = @intCast(c);
                dicq += 1;
                c = getch();
            }
        }
        if (c == 'p') {
            dicq[0] = @intCast(c);
            dicq += 1;
            c = getch();
            if (c == '+' or c == '-') {
                dicq[0] = @intCast(c);
                dicq += 1;
                c = getch();
            }
            if (c < '0' or c > '9') {
                syntax("malformed hex float\n");
            }
            while (c >= '0' and c <= '9') {
                dicq[0] = @intCast(c);
                dicq += 1;
                c = getch();
            }
        }
        ovflocheck();
        dicq[0] = 0;
        const len = @as(usize, @intFromPtr(dicq)) - @as(usize, @intFromPtr(dicp));
        if (len > 60 or clib.sscanf(dicp, "%lf", .{&d}) != 1) {
            syntax("malformed hex float\n");
        } else {
            yylval = sto_dbl(d);
        }
        return;
    }
    dicq[0] = 0;
    yylval = bigxscan(dicp + 2, dicq);
}

export fn octnumeral() void {
    dicq = dicp;
    if (c < '0' or c > '9') {
        syntax("malformed octal number\n");
    }
    while (c == '0' and peekch() >= '0' and peekch() <= '9') {
        c = getch();
    }
    while (c >= '0' and c <= '7') {
        dicq[0] = @intCast(c);
        dicq += 1;
        c = getch();
    }
    if (c >= '0' and c <= '9') {
        syntax("illegal digit in octal number\n");
    }
    ovflocheck();
    dicq[0] = 0;
    yylval = bigoscan(dicp, dicq);
}

export fn getfname(x: Word) Word {
    const p = get_id(x);
    dicq = dicp;
    var i: usize = 0;
    while (true) {
        dicq[i] = p[i];
        if (p[i] == 0) {
            break;
        }
        i += 1;
    }
    dicq += i + 1;
    const len = @as(usize, @intFromPtr(dicq)) - @as(usize, @intFromPtr(dicp));
    if (len < 3) {
        _ = clib.fprintf(getStderr().?, "impossible event in getfname\n", .{.{}});
        clib.exit(1);
    }
    (dicq - 2)[0] = 0;
    ovflocheck();
    return name();
}

export fn name() Word {
    const h_idx = @as(usize, @intCast(hash(dicp)));
    var q = namebucket[h_idx];
    while (q != 0 and !is(get_id(h(q)))) {
        q = t(q);
    }
    if (q == 0) {
        q = sto_id(dicp);
        namebucket[h_idx] = cons(q, namebucket[h_idx]);
        _ = keep(dicp);
    } else {
        q = h(q);
    }
    return q;
}

export fn make_id(n: [*:0]const u8) Word {
    const h_idx = @as(usize, @intCast(hash(n)));
    const x = sto_id(if (inprelude != 0) keep(@constCast(n)) else n);
    namebucket[h_idx] = cons(x, namebucket[h_idx]);
    return x;
}

export fn findid(n: [*:0]const u8) Word {
    const h_idx = @as(usize, @intCast(hash(n)));
    var q = namebucket[h_idx];
    while (q != 0 and clib.strcmp(n, get_id(h(q))) != 0) {
        q = t(q);
    }
    return if (q != 0) h(q) else NIL;
}

export fn reset_pns() void {
    nextpn = 0;
    if (pnvec == null) {
        const ptr = clib.malloc(@intCast(pn_lim * @sizeOf(Word))) orelse {
            mallocfail("pnvec");
            unreachable;
        };
        pnvec = @ptrCast(@alignCast(ptr));
    }
}

export fn make_pn(val: Word) Word {
    if (nextpn == pn_lim) {
        pn_lim += 400;
        const ptr = clib.realloc(pnvec, @intCast(pn_lim * @sizeOf(Word))) orelse {
            mallocfail("pnvec");
            unreachable;
        };
        pnvec = @ptrCast(@alignCast(ptr));
    }
    pnvec.?[@intCast(nextpn)] = make(STRCONS, nextpn, val);
    const ret = pnvec.?[@intCast(nextpn)];
    nextpn += 1;
    return ret;
}

export fn sto_pn(n: Word) Word {
    if (n >= pn_lim) {
        while (pn_lim <= n) {
            pn_lim += 400;
        }
        const ptr = clib.realloc(pnvec, @intCast(pn_lim * @sizeOf(Word))) orelse {
            mallocfail("pnvec");
            unreachable;
        };
        pnvec = @ptrCast(@alignCast(ptr));
    }
    while (nextpn <= n) {
        pnvec.?[@intCast(nextpn)] = make(STRCONS, nextpn, UNDEF);
        nextpn += 1;
    }
    return pnvec.?[@intCast(n)];
}

export fn mkprivate(x_input: Word) void {
    var x = x_input;
    while (x != NIL) {
        get_id(h(x))[0] += 128;
        x = t(x);
    }
    inprelude = 0;
}

export fn string() void {
    var p: Word = undefined;
    var ch: Word = undefined;
    var badch: Word = 0;
    c = getch();
    ch = getlitch();
    yylval = cons(NIL, NIL);
    p = yylval;
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
    yylval = t(yylval);
    if (badch != 0) {
        errclass(badch, 1);
    }
    if (rawch == '\n') {
        syntax("non-escaped newline encountered inside string quotes\n");
    } else if (ch == clib.EOF) {
        if (main.rs.echoing != 0) {
            _ = clib.putchar('\n');
        }
        _ = clib.printf("syntax error: script ends inside unclosed string quotes - \n", .{.{}});
        _ = clib.printf("    \"", .{.{}});
        while (yylval != NIL and sl > 0) {
            _ = clib.putchar(@intCast(h(yylval)));
            yylval = t(yylval);
            sl -= 1;
        }
        _ = clib.printf("...\"\n", .{.{}});
        acterror();
    }
}

export fn charclass() c_int {
    var p: Word = undefined;
    var ch: Word = undefined;
    var badch: Word = 0;
    var anti: c_int = 0;
    c = getch();
    if (c == '^') {
        anti = 1;
        c = getch();
    }
    ch = getlitch();
    yylval = cons(NIL, NIL);
    p = yylval;
    while (ch != clib.EOF and rawch != '`' and rawch != '\n') {
        if (ch == -7) {
            ch = getlitch();
        } else if (ch < 0) {
            badch = ch;
            break;
        } else {
            if (rawch == '-' and h(p) != NIL and h(p) != clib.DOTDOT) {
                ch = clib.DOTDOT;
            }
            tp(p).* = cons(ch, NIL);
            p = t(p);
            ch = getlitch();
        }
    }
    if (h(p) == clib.DOTDOT) {
        hp(p).* = '-';
    }
    p = yylval;
    while (t(p) != NIL) {
        if (h(t(p)) == clib.DOTDOT) {
            hp(t(p)).* = h(p);
            hp(p).* = clib.DOTDOT;
            if (h(t(p)) >= h(t(t(p)))) {
                syntax("illegal use of '-' in [charclass]\n");
            }
        }
        p = t(p);
    }
    yylval = t(yylval);
    if (badch != 0) {
        errclass(badch, 2);
    }
    if (rawch == '\n') {
        syntax("non-escaped newline encountered in char class\n");
    } else if (ch == clib.EOF) {
        if (main.rs.echoing != 0) {
            _ = clib.putchar('\n');
        }
        _ = clib.printf("syntax error: script ends inside unclosed char class brackets - \n", .{.{}});
        _ = clib.printf("    [", .{.{}});
        while (yylval != NIL and sl > 0) {
            _ = clib.putchar(@intCast(h(yylval)));
            yylval = t(yylval);
            sl -= 1;
        }
        _ = clib.printf("...]\n", .{.{}});
        acterror();
    }
    return anti;
}

export fn reset_lex() void {
    if (commandmode == 0) {
        if (errs == 0) {
            errs = fileinfo(@intCast(@intFromPtr(get_fil(current_file))), line_no);
        }
        const err_script_raw = @as(?[*:0]const u8, @ptrCast(@as(*anyopaque, @ptrFromInt(@as(usize, @intCast(h(errs)))))));
        const err_script = err_script_raw orelse "test.m";
        const is_current = if (err_script_raw) |es|
            (if (main.rs.current_script) |cs| es == @as([*:0]const u8, @ptrCast(cs)) else false)
            else true;
        if (t(errs) == 0 and is_current) {
            _ = clib.fprintf(getStderr().?, "error occurs at end of ", .{.{}});
        } else {
            _ = clib.fprintf(getStderr().?, "error found near line %ld of ", .{.{t(errs)}});
        }
        _ = clib.fprintf(getStderr().?, "%sfile \"%s\"\ncompilation abandoned\n", .{.{if (is_current) @as([*:0]const u8, "") else "%insert ", err_script}});
        if (is_current) {
            errline = if (t(errs) == 0) lastline else t(errs);
            errs = 0;
        } else {
            if (linostack != NIL) {
                while (t(linostack) != NIL) {
                    linostack = t(linostack);
                }
                errline = h(linostack);
            } else {
                errline = lastline;
            }
        }
    }
    reset_state();
}

export fn reset_state() void {
    if (commandmode != 0) {
        while (c != '\n' and c != clib.EOF) {
            if (main.rs.s_in) |sin| {
                c = clib.getc(sin);
            } else {
                c = clib.EOF;
            }
        }
    }
    while (fileq != NIL) {
        const file_ptr: ?*clib.FILE = @ptrFromInt(@as(usize, @intCast(h(h(fileq)))));
        _ = clib.fclose(file_ptr);
        fileq = t(fileq);
    }
    insertdepth = -1;
    main.rs.s_in = getStdin();
    echostack = NIL;
    idsused = NIL;
    prefixstack = NIL;
    litstack = NIL;
    linostack = NIL;
    vergstack = NIL;
    margstack = NIL;
    prefix = 0;
    prefixbase.?[0] = 0;
    main.rs.echoing = main.rs.verbosity & main.rs.listing;
    brct = 0;
    inbnf = 0;
    sreds = 0;
    inlex = 0;
    inexplist = 0;
    commandmode = 0;
    lverge = 0;
    col = 0;
    lmargin = 0;
    atnl = 1;
    rv_script = 0;
    algshfns = NIL;
    newtyps = NIL;
    showchain = NIL;
    SGC = NIL;
    TABSTRS = NIL;
    c = ' ';
    line_no = 0;
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
