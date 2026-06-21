const std = @import("std");
const word = @import("word.zig");
const platform = @import("../io/platform.zig");
const clib = @import("c_abi.zig");
const main = @import("../main.zig");
const heap = @import("heap.zig");

const Word = c_long;
const NIL: Word = word.CMBASE + 138;
const NILS: Word = word.CMBASE + 139;
const ATOMLIMIT: Word = word.CMBASE + 141;
const FST = word.HD;
const MAXDIGIT = 0x7fff;
const SIGNBIT = 0x10000000;

extern var hd: [*]Word;
extern var tl: [*]Word;
extern var tag: [*]u8;

extern var compiling: c_int;
extern var errs: Word;

extern var nogcs: c_long;
extern var claims: c_long;
extern var cellcount: i64;

export var stdinuse: Word = 0;
export var outfilq: Word = NIL;
export var waiting: Word = NIL;
export var s_out: ?*word.FILE = null;
export var errtrap: Word = 0;
export var cycles: i64 = 0;

const sto_char = heap.sto_char;
extern fn fromUTF8(f: ?*word.FILE) Word;
extern fn parseline(x: Word, f: ?*word.FILE, y: Word) Word;
extern fn reduce(e: Word) Word;
const charname = heap.charname;

inline fn h(x: Word) Word {
    if (x < ATOMLIMIT) return 0;
    return hd[@as(usize, @intCast(x)) * 2];
}

inline fn t(x: Word) Word {
    if (x < ATOMLIMIT) return 0;
    return tl[@as(usize, @intCast(x)) * 2];
}

inline fn hp(x: Word) *Word {
    return &hd[@as(usize, @intCast(x)) * 2];
}

inline fn tp(x: Word) *Word {
    return &tl[@as(usize, @intCast(x)) * 2];
}

inline fn abnormal(x: Word) bool {
    return x < 0;
}

inline fn isptr(x: Word) bool {
    return x >= ATOMLIMIT;
}

inline fn lh(x: Word) Word {
    if (tag[@as(usize, @intCast(h(x)))] == word.STRCONS) {
        return t(h(x));
    } else {
        return h(x);
    }
}

inline fn force_dbl(x: Word) f64 {
    if (tag[@as(usize, @intCast(x))] == word.INT) {
        return clib.bigtodbl(x);
    } else {
        return clib.get_dbl(x);
    }
}

inline fn fsign(x: f64) c_int {
    if (x < 0.0) return -1;
    if (x > 0.0) return 1;
    return 0;
}

inline fn sign(x: c_long) c_int {
    if (x < 0) return -1;
    if (x > 0) return 1;
    return 0;
}

inline fn cons(x: Word, y: Word) Word {
    return clib.make(word.CONS, x, y);
}

inline fn ap(x: Word, y: Word) Word {
    return clib.make(word.AP, x, y);
}

inline fn ap2(f: Word, x: Word, y: Word) Word {
    return ap(ap(f, x), y);
}

inline fn datapair(x: Word, y: Word) Word {
    return clib.make(word.DATAPAIR, x, y);
}

inline fn digit0(x: Word) Word {
    return h(x) & MAXDIGIT;
}

inline fn stosmallint(x: Word) Word {
    const val = if (x < 0) SIGNBIT | (-x) else x;
    return clib.make(word.INT, val, 0);
}

const reduce_ctx = extern struct {
    e: Word,
    s: Word,
    hold: Word,
    arg1: Word,
    arg2: Word,
    arg3: Word,
};

const reduce_action = enum(c_int) {
    REDUCE_NOT_HANDLED = 0,
    REDUCE_NEXT = 1,
    REDUCE_DONE = 2,
    REDUCE_RETURN = 3,
};

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

inline fn rewrite_to_value(expr: *Word, value: Word) void {
    hd[@as(usize, @intCast(expr.*)) * 2] = word.I;
    expr.* = value;
    tl[@as(usize, @intCast(expr.*)) * 2] = value;
}

inline fn rewrite_to_nil(expr: *Word) void {
    rewrite_to_value(expr, NIL);
}

inline fn setcell(e: Word, t_val: u8, a: Word, b: Word) void {
    tag[@as(usize, @intCast(e))] = t_val;
    hd[@as(usize, @intCast(e)) * 2] = a;
    tl[@as(usize, @intCast(e)) * 2] = b;
}

inline fn rewrite_to_cons(e: Word, hd_value: Word, tl_value: Word) void {
    setcell(e, word.CONS, hd_value, tl_value);
}

export fn reduce_badcase_error(arg_info: Word) void {
    const subject = h(arg_info);
    word.printErr("\nprogram error: missing case in definition", .{});
    if (subject != 0) {
        word.printErr(" of {s}", .{std.mem.span(getstring(subject, null).?)});
    }
    _ = word.putc('\n', getStderr().?);
    out_here(getStderr().?, t(arg_info), 1);
    outstats();
    clib.exit(1);
}

export fn reduce_conf_error(arg_info: Word) void {
    word.printErr("\nprogram error: lhs of definition doesn't match rhs\n", .{});
    out_here(getStderr().?, t(arg_info), 1);
    outstats();
    clib.exit(1);
}

export fn reduce_parse_close_error(arg1: Word, arg3: Word) void {
    word.printErr("\nPARSE OF {s}FAILS WITH UNEXPECTED ", .{std.mem.span(getstring(arg1, null).?)});
    const arg3_reduced = reduce(t(g_residue(arg3)));
    if (arg3_reduced == NIL) {
        word.printErr("END OF INPUT\n", .{});
        outstats();
        clib.exit(1);
    }
    var hold_val = clib.make(word.AP, FST, h(arg3_reduced));
    hold_val = reduce(hold_val);
    word.printErr("TOKEN \"", .{});
    if (hold_val == word.OFFSIDE) {
        word.printErr("offside", .{});
    }
    const p = getstring(hold_val, null);
    if (p) |ptr| {
        var i: usize = 0;
        while (ptr[i] != 0) : (i += 1) {
            word.printErr("{s}", .{charname(ptr[i])});
        }
    }
    word.printErr("\"\n", .{});
    outstats();
    clib.exit(1);
}

export fn reduce_stream_read(ctx: *reduce_ctx, op: Word) reduce_action {
    const lastarg = t(ctx.e);
    switch (op) {
        word.READBIN => {
            // UPLEFT
            ctx.hold = ctx.s;
            ctx.s = h(ctx.s);
            hp(ctx.hold).* = ctx.e;
            ctx.e = ctx.hold;

            if (lastarg == 0) {
                if (stdinuse == '-') {
                    stdin_error(':');
                }
                if (stdinuse != 0) {
                    rewrite_to_nil(&ctx.e);
                    return .REDUCE_DONE;
                }
                stdinuse = ':';
                tp(ctx.e).* = @intCast(@intFromPtr(getStdin().?));
            }
            const hold_char = clib.getc(@ptrFromInt(@as(usize, @intCast(t(ctx.e)))));
            if (hold_char == clib.EOF) {
                _ = word.fclose(@ptrFromInt(@as(usize, @intCast(t(ctx.e)))));
                rewrite_to_nil(&ctx.e);
                return .REDUCE_DONE;
            }
            rewrite_to_cons(ctx.e, hold_char, clib.make(word.AP, word.READBIN, t(ctx.e)));
            return .REDUCE_DONE;
        },
        word.READ => {
            // UPLEFT
            ctx.hold = ctx.s;
            ctx.s = h(ctx.s);
            hp(ctx.hold).* = ctx.e;
            ctx.e = ctx.hold;

            if (lastarg == 0) {
                if (stdinuse == ':') {
                    stdin_error('-');
                }
                if (stdinuse != 0) {
                    rewrite_to_nil(&ctx.e);
                    return .REDUCE_DONE;
                }
                stdinuse = '-';
                tp(ctx.e).* = @intCast(@intFromPtr(getStdin().?));
            }
            const hold_char = if (main.rs.UTF8 != 0) sto_char(fromUTF8(@ptrFromInt(@as(usize, @intCast(t(ctx.e)))))) else clib.getc(@ptrFromInt(@as(usize, @intCast(t(ctx.e)))));
            if (hold_char == clib.EOF) {
                _ = word.fclose(@ptrFromInt(@as(usize, @intCast(t(ctx.e)))));
                rewrite_to_nil(&ctx.e);
                return .REDUCE_DONE;
            }
            rewrite_to_cons(ctx.e, hold_char, clib.make(word.AP, word.READ, t(ctx.e)));
            return .REDUCE_DONE;
        },
        word.READVALS => {
            // GETARG(arg1)
            ctx.hold = ctx.s;
            ctx.s = h(ctx.s);
            hp(ctx.hold).* = ctx.e;
            ctx.e = ctx.hold;
            ctx.arg1 = t(ctx.e);

            if (abnormal(ctx.s)) return .REDUCE_DONE;

            // UPLEFT
            ctx.hold = ctx.s;
            ctx.s = h(ctx.s);
            hp(ctx.hold).* = ctx.e;
            ctx.e = ctx.hold;

            const val = parseline(h(ctx.arg1), @ptrFromInt(@as(usize, @intCast(lastarg))), t(ctx.arg1));
            if (val == clib.EOF) {
                _ = word.fclose(@ptrFromInt(@as(usize, @intCast(lastarg))));
                rewrite_to_nil(&ctx.e);
                return .REDUCE_DONE;
            }
            ctx.arg2 = clib.make(word.AP, h(ctx.e), lastarg);
            rewrite_to_cons(ctx.e, val, ctx.arg2);
            return .REDUCE_DONE;
        },
        else => return .REDUCE_NOT_HANDLED,
    }
}

export fn getstring(x: Word, cmd: ?[*:0]const u8) ?[*:0]u8 {
    var curr_x = x;
    const x1 = x;
    var n: usize = 0;
    const buf_size = 1024;
    while (tag[@as(usize, @intCast(curr_x))] == word.CONS and n < buf_size) {
        n += 1;
        hp(curr_x).* = reduce(h(curr_x));
        tp(curr_x).* = reduce(t(curr_x));
        curr_x = t(curr_x);
    }
    curr_x = x1;
    var p_idx: usize = 0;
    while (tag[@as(usize, @intCast(curr_x))] == word.CONS and n > 0) {
        n -= 1;
        main.rs.linebuf[p_idx] = @intCast(h(curr_x));
        p_idx += 1;
        curr_x = t(curr_x);
    }
    main.rs.linebuf[p_idx] = 0;
    p_idx += 1;
    if (p_idx > buf_size) {
        if (cmd) |cmd_str| {
            word.printErr("\n{s}, argument string too long (limit={} chars): {s}...\n", .{cmd_str, @as(c_int, buf_size), &main.rs.linebuf});
            outstats();
            clib.exit(1);
        } else {
            return @ptrCast(&main.rs.linebuf);
        }
    }
    return @ptrCast(&main.rs.linebuf);
}

export fn initclock() void {}

export fn outstats() void {
    if (main.rs.atcount == 0) {
        return;
    }
    var buffer: clib.struct_tms = undefined;
    _ = clib.times(&buffer);
    word.printErr("||", .{});
    word.printErr("reductions = {}, cells claimed = {}, ", .{cycles, cellcount + claims});
    const clk_tck = @as(f64, @floatFromInt(clib.sysconf(clib._SC_CLK_TCK)));
    word.printErr("no of gc's = {}, cpu = {d:.2}\n", .{nogcs, @as(f64, @floatFromInt(buffer.tms_utime)) / clk_tck});
}

export fn out_here(f: ?*word.FILE, h_val: Word, nl: c_int) void {
    if (tag[@as(usize, @intCast(h_val))] != word.FILEINFO) {
        word.printErr("(impossible event in outhere)\n", .{});
        return;
    }
    _ = word.fprintf(f.?, "(line %3ld of \"%s\")", .{.{ t(h_val), @as([*:0]const u8, @ptrCast(@as(*anyopaque, @ptrFromInt(@as(usize, @intCast(h(h_val))))))) }});
    if (nl != 0) {
        _ = word.putc('\n', f.?);
    } else {
        _ = word.putc(' ', f.?);
    }
    if (compiling != 0 and errs == 0) {
        errs = h_val;
    }
}

fn stdname(c_val: c_int) [*:0]const u8 {
    return if (c_val == ':') "$:-" else if (c_val == '-') "$-" else "$+";
}

pub fn stdin_error(c_val: c_int) void {
    if (stdinuse == c_val) {
        word.printErr("program error: duplicate use of {s}\n", .{stdname(c_val)});
    } else {
        word.printErr("program error: simultaneous use of {s} and {s}\n", .{stdname(c_val), stdname(@intCast(stdinuse))});
    }
    outstats();
    clib.exit(1);
}

export fn fn_error(s: [*:0]const u8) void {
    word.printErr("\nprogram error: {s}\n", .{s});
    outstats();
    clib.exit(1);
}

export fn getenv_error(a: [*:0]const u8) void {
    word.printErr("program error: getenv({s}): illegal characters in result string\n", .{a});
    outstats();
    clib.exit(1);
}

export fn subs_error() void {
    fn_error("subscript out of range");
}

export fn div_error() void {
    fn_error("attempt to divide by zero");
}

export fn math_error(s: [*:0]const u8) void {
    const err_val = platform.getErrno();
    const err_type: [*:0]const u8 = if (err_val == clib.EDOM) "domain " else if (err_val == clib.ERANGE) "range " else "";
    word.printErr("\nmath function {s}error ({s})\n", .{err_type, s});
    outstats();
    clib.exit(1);
}

export fn int_error(s: [*:0]const u8) void {
    word.printErr("\nprogram error: fractional number where integer expected ({s})\n", .{s});
    outstats();
    clib.exit(1);
}

export fn numplus(x: Word, y: Word) Word {
    if (tag[@as(usize, @intCast(x))] == word.DOUBLE) {
        return clib.sto_dbl(clib.get_dbl(x) + force_dbl(y));
    }
    if (tag[@as(usize, @intCast(y))] == word.DOUBLE) {
        return clib.sto_dbl(clib.bigtodbl(x) + clib.get_dbl(y));
    }
    return clib.bigplus(x, y);
}

export fn g_residue(toks2: Word) Word {
    var curr_toks2 = toks2;
    var toks1 = NIL;
    if (tag[@as(usize, @intCast(curr_toks2))] != word.CONS) {
        if (tag[@as(usize, @intCast(curr_toks2))] == word.AP and h(curr_toks2) == word.I and t(curr_toks2) == NIL) {
            return cons(NIL, NIL);
        }
        return cons(NIL, curr_toks2);
    }
    while (tag[@as(usize, @intCast(t(curr_toks2)))] == word.CONS) {
        toks1 = cons(h(curr_toks2), toks1);
        curr_toks2 = t(curr_toks2);
    }
    if (t(curr_toks2) == NIL or (tag[@as(usize, @intCast(t(curr_toks2)))] == word.AP and h(t(curr_toks2)) == word.I and t(t(curr_toks2)) == NIL)) {
        toks1 = cons(h(curr_toks2), toks1);
        return cons(ap(word.DESTREV, toks1), NIL);
    }
    return cons(ap(word.DESTREV, toks1), t(curr_toks2));
}

export fn memclass(c_val: c_int, x_val: Word) c_int {
    var x = x_val;
    while (x != NIL) {
        if (h(x) == word.DOTDOT) {
            x = t(x);
            if (h(x) <= c_val and c_val <= h(t(x))) {
                return 1;
            }
            x = t(x);
        } else if (c_val == h(x)) {
            return 1;
        }
        x = t(x);
    }
    return 0;
}

export fn lexfail(x_val: Word) void {
    var x = x_val;
    var i: i32 = 24;
    word.printErr("\nLEX FAILS WITH UNRECOGNISED INPUT: \"", .{});
    while (i > 0 and x != NIL and 0 <= lh(x) and lh(x) <= 255) {
        i -= 1;
        word.printErr("{s}", .{charname(@intCast(lh(x)))});
        x = t(x);
    }
    word.printErr("{s}\"\n", .{if (x == NIL) @as([*:0]const u8, "") else "..."});
    outstats();
    clib.exit(1);
}

export fn lexstate(x: Word) Word {
    const val = h(h(x));
    return cons(clib.sto_int(val >> 8), stosmallint(val & 255));
}

export fn piperrmess(pid: Word) Word {
    return clib.str_conv(if (pid == -1) "cannot create process\n" else "cannot open pipe\n");
}

export fn compare(arg_a: Word, arg_b: Word) c_int {
    var a = arg_a;
    var b = arg_b;
    while (true) {
        const tag_a = tag[@as(usize, @intCast(a))];
        const tag_b = tag[@as(usize, @intCast(b))];
        switch (tag_a) {
            word.DOUBLE => {
                if (tag_b == word.DOUBLE) {
                    return fsign(clib.get_dbl(a) - clib.get_dbl(b));
                } else {
                    return fsign(clib.get_dbl(a) - clib.bigtodbl(b));
                }
            },
            word.INT => {
                if (tag_b == word.INT) {
                    return clib.bigcmp(a, b);
                } else {
                    return fsign(clib.bigtodbl(a) - clib.get_dbl(b));
                }
            },
            word.UNICODE => {
                return sign(clib.get_char(a) - clib.get_char(b));
            },
            word.ATOM => {
                if (tag_b == word.UNICODE) {
                    return sign(clib.get_char(a) - clib.get_char(b));
                }
                if ((word.S <= a and a <= word.ERROR) or (word.S <= b and b <= word.ERROR)) {
                    fn_error("attempt to compare functions");
                }
                if (tag_b == word.ATOM) {
                    return sign(a - b);
                }
                return -1;
            },
            word.CONSTRUCTOR => {
                if (tag_b == word.CONSTRUCTOR) {
                    return sign(h(a) - h(b));
                } else {
                    return -1;
                }
            },
            word.CONS, word.AP => {
                if (tag_a == tag_b) {
                    hp(a).* = reduce(h(a));
                    hp(b).* = reduce(h(b));
                    const temp = compare(h(a), h(b));
                    if (temp != 0) {
                        return temp;
                    }
                    tp(a).* = reduce(t(a));
                    a = t(a);
                    tp(b).* = reduce(t(b));
                    b = t(b);
                    continue;
                } else if (word.S <= b and b <= word.ERROR) {
                    fn_error("attempt to compare functions");
                } else {
                    return 1;
                }
            },
            else => {
                word.printErr("\nghastly error in compare\n", .{});
            },
        }
        return 0;
    }
}

export fn force(x_val: Word) void {
    var x = x_val;
    switch (tag[@as(usize, @intCast(x))]) {
        word.AP => {
            var curr_h = h(x);
            while (tag[@as(usize, @intCast(curr_h))] == word.AP) {
                curr_h = h(curr_h);
            }
            if (word.S <= curr_h and curr_h <= word.ERROR) {
                return;
            }
            while (tag[@as(usize, @intCast(x))] == word.AP) {
                tp(x).* = reduce(t(x));
                force(t(x));
                x = h(x);
            }
            return;
        },
        word.CONS => {
            while (tag[@as(usize, @intCast(x))] == word.CONS) {
                hp(x).* = reduce(h(x));
                force(h(x));
                tp(x).* = reduce(t(x));
                x = t(x);
            }
        },
        else => {},
    }
}

export fn head(x_val: Word) Word {
    var x = x_val;
    while (tag[@as(usize, @intCast(x))] == word.AP) {
        x = h(x);
    }
    return x;
}

pub fn apfile(f: Word) void {
    var p = outfilq;
    const fil = getstring(f, "Appendfile");
    while (p != NIL and word.strcmp(@as([*:0]const u8, @ptrFromInt(@as(usize, @intCast(h(h(p)))))), fil) != 0) {
        p = t(p);
    }
    if (p == NIL) {
        const s = word.fopen(fil, "a");
        if (s == null) {
            word.printErr("\nAppendfile: cannot write to \"{s}\"\n", .{std.mem.span(fil.?)});
        } else {
            outfilq = cons(datapair(@intCast(@intFromPtr(clib.keep(fil.?))), @intCast(@intFromPtr(s.?))), outfilq);
        }
    }
}

pub fn closefile(f: Word) void {
    var p = &outfilq;
    const fil = getstring(f, "Closefile");
    while (p.* != NIL and word.strcmp(@as([*:0]const u8, @ptrFromInt(@as(usize, @intCast(h(h(p.*)))))), fil) != 0) {
        p = tp(p.*);
    }
    if (p.* != NIL) {
        _ = word.fclose(@ptrFromInt(@as(usize, @intCast(t(h(p.*))))));
        p.* = t(p.*);
    }
}

pub fn outf(e: Word) void {
    var p = outfilq;
    const f = getstring(t(h(e)), "Tofile");
    while (p != NIL and word.strcmp(@as([*:0]const u8, @ptrFromInt(@as(usize, @intCast(h(h(p)))))), f) != 0) {
        p = t(p);
    }
    if (p == NIL) {
        s_out = word.fopen(f, "w");
        if (s_out == null) {
            word.printErr("\nTofile: cannot write to \"{s}\"\n", .{std.mem.span(f.?)});
            s_out = getStdout();
            return;
        }
        if (clib.isatty(word.fileno(s_out.?)) != 0) {
            word.setbuf(s_out.?, null);
        }
        outfilq = cons(datapair(@intCast(@intFromPtr(clib.keep(f.?))), @intCast(@intFromPtr(s_out.?))), outfilq);
    } else {
        s_out = @ptrFromInt(@as(usize, @intCast(t(h(p)))));
    }
}

export fn print(arg_e: Word) void {
    var e = reduce(arg_e);
    while (tag[@as(usize, @intCast(e))] == word.CONS) {
        hp(e).* = reduce(h(e));
        if (clib.is_char(h(e)) == 0) {
            break;
        }
        const c = @as(u32, @intCast(clib.get_char(h(e))));
        if (main.rs.UTF8 != 0) {
            clib.outUTF8(c, s_out);
        } else if (c < 256) {
            _ = word.putc(@intCast(c), s_out.?);
        } else {
            word.printErr("\n warning: non Latin1 char {x} in print, ignored\n", .{c});
        }
        tp(e).* = reduce(t(e));
        e = t(e);
    }
    if (e == NIL) {
        return;
    }
    word.printErr("\nimpossible event in print\n", .{});
    _ = word.putc('<', getStderr().?);
    clib.out(getStderr().?, e);
    word.printErr(">\n", .{});
    clib.exit(1);
}

const Stdout = 0;
const Stderr = 1;
const Tofile = 2;
const Closefile = 3;
const Appendfile = 4;
const System = 5;
const Exit = 6;
const Stdoutb = 7;
const Tofileb = 8;
const Appendfileb = 9;

export fn output(arg_e: Word) void {
    var e = arg_e;
    const old_cstack = main.rs.cstack;
    main.rs.cstack = @ptrCast(&e);
    defer main.rs.cstack = old_cstack;

    e = reduce(e);
    while (tag[@as(usize, @intCast(e))] == word.CONS) {
        hp(e).* = reduce(h(e));
        switch (h(head(h(e)))) {
            Stdout => {
                print(t(h(e)));
            },
            Stdoutb => {
                main.rs.UTF8OUT = 0;
                print(t(h(e)));
                main.rs.UTF8OUT = main.rs.UTF8;
            },
            Stderr => {
                s_out = getStderr();
                print(t(h(e)));
                s_out = getStdout();
            },
            Tofile => {
                outf(h(e));
            },
            Tofileb => {
                main.rs.UTF8OUT = 0;
                outf(h(e));
                main.rs.UTF8OUT = main.rs.UTF8;
            },
            Closefile => {
                tp(h(e)).* = reduce(t(h(e)));
                closefile(t(h(e)));
            },
            Appendfile => {
                tp(h(e)).* = reduce(t(h(e)));
                apfile(t(h(e)));
            },
            Appendfileb => {
                main.rs.UTF8OUT = 0;
                tp(h(e)).* = reduce(t(h(e)));
                apfile(t(h(e)));
                main.rs.UTF8OUT = main.rs.UTF8;
            },
            System => {
                tp(h(e)).* = reduce(t(h(e)));
                const cmd = getstring(t(h(e)), "System");
                _ = clib.system(cmd);
            },
            Exit => {
                var n = reduce(t(h(e)));
                if (tag[@as(usize, @intCast(n))] == word.INT) {
                    n = digit0(n);
                } else {
                    int_error("Exit");
                }
                outstats();
                clib.exit(@intCast(n));
            },
            else => {
                word.printErr("\n<impossible event in output list: ", .{});
                clib.out(getStderr().?, h(e));
                word.printErr(">\n", .{});
            },
        }
        tp(e).* = reduce(t(e));
        e = t(e);
    }
    if (e == NIL) {
        return;
    }
    word.printErr("\nimpossible event in output\n", .{});
    _ = word.putc('<', getStderr().?);
    clib.out(getStderr().?, e);
    word.printErr(">\n", .{});
    clib.exit(1);
}

comptime {
    @setEvalBranchQuota(50000);
    _ = @import("reducer/reduce.zig");
    _ = @import("reducer/combinators.zig");
    _ = @import("reducer/ready.zig");
    _ = @import("reducer/io.zig");
    _ = @import("reducer/lex.zig");
}
