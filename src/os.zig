//! os.zig (renamed from main_clib.zig, Phase 2 step 5, docs/GO_PORT_PLAN.md)
//! — the Zig-native C-standard-library/OS shim. Implements the
//! `fork`/`wait`/`errno`/signals/rlimits/`sscanf` surface the C-ported
//! interpreter calls, layered over `std` and the raw OS syscalls, so the binary
//! links no external libc. This is the project's irreducible FFI boundary (the
//! few remaining `extern fn`s are the OS syscall floor). `printf`/`fopen`/
//! `getc` and the rest of stdio live in `stream.zig`, re-exported from here
//! (and from `word.zig`) unchanged; the value-vocabulary constants re-exported
//! here (`CONS`/`AP`/combinator codes/…) are a much older consolidation this
//! rename didn't revisit.

const word_mod = @import("graph/word.zig");
const std = @import("std");
const builtin = @import("builtin");
const os_scanf = @import("os_scanf.zig");
pub const sscanf = os_scanf.sscanf;
pub const fscanf = os_scanf.fscanf;
const rt = @import("runtime/runtime_state.zig");
const heap_mod = @import("graph/heap.zig");
const print_mod = @import("graph/print.zig");
const dump_mod = @import("graph/dump.zig");
const dump_load_mod = @import("graph/dump_load.zig");
const lex_mod = @import("parser/lex.zig");
const reduce_mod = @import("eval/reduce_rt.zig");
const repl_mod = @import("session/repl.zig");
const trans_mod = @import("semantics/lower.zig");
const infer_mod = @import("semantics/infer.zig");
const depend_mod = @import("semantics/depend.zig");
const unify_mod = @import("semantics/unify.zig");
const type_errors_mod = @import("semantics/type_errors.zig");

pub var env_slice: [:null]const ?[*:0]const u8 = &[_:null]?[*:0]const u8{};

// Syscall return-value helper: converts platform-specific return types to c_int.
// - usize (raw Linux kernel): bitcast to signed isize, then truncate to c_int
// - Any other integer (c_int, pid_t/i32, etc.): direct intCast (safe for small values)
inline fn syscallResult(rc: anytype) c_int {
    if (comptime @TypeOf(rc) == usize) {
        return @truncate(@as(isize, @bitCast(rc)));
    }
    return @intCast(rc);
}

const WaitStatusType = c_int;

// Word types
pub const word = word_mod.Word;
pub const unicode = word_mod.Unicode;

// Definitions from data.h / combs.h
pub const pnlim: c_int = 1024;
pub const BUFSIZE: c_int = 1024;
pub const Word = word_mod.Word;

pub const AP = @intFromEnum(word_mod.NodeTag.AP);
pub const APPEND = word_mod.APPEND;
pub const ARCTAN_FN = word_mod.ARCTAN_FN;
pub const CODE = word_mod.CODE;
pub const CONS = @intFromEnum(word_mod.NodeTag.CONS);
pub const CONST = word_mod.CONST;
pub const CONSTRUCTOR = @intFromEnum(word_mod.NodeTag.CONSTRUCTOR);
pub const COS_FN = word_mod.COS_FN;
pub const DATAPAIR = @intFromEnum(word_mod.NodeTag.DATAPAIR);
pub const DBL_MAX = std.math.floatMax(f64);
pub const DECODE = word_mod.DECODE;
pub const DROP = word_mod.DROP;
pub const ENTIER_FN = word_mod.ENTIER_FN;
pub const EOF = -1;
pub const ERROR = word_mod.ERROR;
pub const EVAL = word_mod.EVAL;
pub const EXEC = word_mod.EXEC;
pub const EXPORT = word_mod.EXPORT;
pub const EXP_FN = word_mod.EXP_FN;
pub const Stream = word_mod.Stream;
pub const FILEINFO = @intFromEnum(word_mod.NodeTag.FILEINFO);
pub const FILEMODE = word_mod.FILEMODE;
pub const FILESTAT = word_mod.FILESTAT;
pub const FILTER = word_mod.FILTER;
pub const FOLDL = word_mod.FOLDL;
pub const FOLDL1 = word_mod.FOLDL1;
pub const FOLDR = word_mod.FOLDR;
pub const FORCE = word_mod.FORCE;
pub const FREE = word_mod.FREE;
pub const free_t = word_mod.free_t;
pub const GETENV = word_mod.GETENV;
pub const HD = word_mod.HD;
pub const I = word_mod.I;
pub const ID = @intFromEnum(word_mod.NodeTag.ID);
pub const INTEGER = word_mod.INTEGER;
pub const LABEL = @intFromEnum(word_mod.NodeTag.LABEL);
pub const LIST_LAST = word_mod.LIST_LAST;
pub const LOG10_FN = word_mod.LOG10_FN;
pub const LOG_FN = word_mod.LOG_FN;
pub const MAP = word_mod.MAP;
pub const MERGE = word_mod.MERGE;
pub const NUMVAL = word_mod.NUMVAL;
pub const OFFSIDE = word_mod.OFFSIDE;
pub const O_RDONLY: c_int = 0;
pub const O_WRONLY: c_int = @intCast(@as(u32, @bitCast(std.posix.O{ .ACCMODE = .WRONLY })));
pub const O_CREAT: c_int = @intCast(@as(u32, @bitCast(std.posix.O{ .CREAT = true })));
pub const O_TRUNC: c_int = @intCast(@as(u32, @bitCast(std.posix.O{ .TRUNC = true })));
pub const PLUS = word_mod.PLUS;
pub const READ = word_mod.READ;
pub const READBIN = word_mod.READBIN;
pub const RLIMIT_STACK: c_int = @intCast(@intFromEnum(std.posix.rlimit_resource.STACK));
pub const SEQ = word_mod.SEQ;
pub const SHOWFLOAT = word_mod.SHOWFLOAT;
pub const SHOWHEX = word_mod.SHOWHEX;
pub const SHOWNUM = word_mod.SHOWNUM;
pub const SHOWOCT = word_mod.SHOWOCT;
pub const SHOWSCALED = word_mod.SHOWSCALED;
pub const SIGBUS: c_int = @intCast(@intFromEnum(std.posix.SIG.BUS));
pub const SIGFPE: c_int = @intCast(@intFromEnum(std.posix.SIG.FPE));
pub const SIGINT: c_int = @intCast(@intFromEnum(std.posix.SIG.INT));
pub const SIGSEGV: c_int = @intCast(@intFromEnum(std.posix.SIG.SEGV));
pub const SIGTERM: c_int = @intCast(@intFromEnum(std.posix.SIG.TERM));
pub const SIN_FN = word_mod.SIN_FN;
pub const SQRT_FN = word_mod.SQRT_FN;
pub const STARTREAD = word_mod.STARTREAD;
pub const STARTREADBIN = word_mod.STARTREADBIN;
pub const STDOUT_FILENO: c_int = std.posix.STDOUT_FILENO;
pub const STRCONS = @intFromEnum(word_mod.NodeTag.STRCONS);
pub const TAKE = word_mod.TAKE;
pub const TIOCGWINSZ: c_ulong = if (builtin.os.tag == .macos) 0x40087468 else 0x5413;
pub const TL = word_mod.TL;
pub const UNDEF = word_mod.UNDEF;
pub const UNION = depend_mod.UNION;
pub const VALUE = word_mod.VALUE;
pub const XVERSION = 83;
pub const ZIP = word_mod.ZIP;
pub const abstract_t = word_mod.abstract_t;
pub const placeholder_t = word_mod.placeholder_t;
pub const add1 = depend_mod.add1;
pub const addextn = lex_mod.addextn;
pub const adjustPrefix = lex_mod.adjustPrefix;
pub const algebraic_t = word_mod.algebraic_t;
pub fn ap(heap: *heap_mod.Heap, x: Word, y: Word) Word {
    return make(heap, .AP, x, y);
}
pub fn ap2(heap: *heap_mod.Heap, x: Word, y: Word, z: Word) Word {
    return ap(heap, ap(heap, x, y), z);
}
pub const append1 = heap_mod.append1;
pub const bool_t = word_mod.bool_t;
pub const char_t = word_mod.char_t;
pub const checktypes = infer_mod.checktypes;
pub const codegen = trans_mod.codegen;
pub fn cons(heap: *heap_mod.Heap, x: Word, y: Word) Word {
    return make(heap, .CONS, x, y);
}
pub fn datapair(heap: *heap_mod.Heap, x: Word, y: Word) Word {
    return make(heap, .DATAPAIR, x, y);
}
pub const deps = depend_mod.deps;
pub const dumpScript = dump_mod.dumpScript;
pub const findid = lex_mod.findid;
pub const gc = heap_mod.gc;
pub const gcpatch = heap_mod.gcpatch;
pub const getHere = heap_mod.getHere;
pub const getaka = heap_mod.getaka;
pub const geterrlin = dump_mod.geterrlin;
pub const getstring = reduce_mod.getstring;
pub const instantiate = unify_mod.instantiate;
pub const intersection = depend_mod.intersection;
pub const make = heap_mod.make;
pub const keep = lex_mod.keep;
pub const loadScript = dump_load_mod.loadScript;
pub const makeId = lex_mod.makeId;
pub const mallocfail = heap_mod.mallocfail;
pub const setdiff = depend_mod.setdiff;
pub const makePn = lex_mod.makePn;
pub fn make_typ(heap: *heap_mod.Heap, a: Word, shf: Word, class: Word, info: Word) Word {
    return cons(heap, cons(heap, a, shf), cons(heap, class, info));
}
pub const member = depend_mod.member;
pub const mkprivate = lex_mod.mkprivate;
pub const mkshow = trans_mod.mkshow;
pub const num_t = word_mod.num_t;
pub const obey = repl_mod.obey;
pub const okdump = dump_mod.okdump;
pub const okid = lex_mod.okid;
pub const openfile = lex_mod.openfile;
pub const out = print_mod.outTerm;
pub const outHere = reduce_mod.outHere;
pub const outPattern = type_errors_mod.outPattern;
pub const outType = type_errors_mod.outType;
pub const output = reduce_mod.output;
pub const outstats = reduce_mod.outstats;
pub const printlist = infer_mod.printlist;
pub const process = repl_mod.process;
pub const rdline = lex_mod.rdline;
pub fn readvals(heap: *heap_mod.Heap, x: Word, y: Word) Word {
    return make(heap, .STARTREADVALS, x, y);
}
pub const reportType = type_errors_mod.reportType;
pub const resetheap = heap_mod.resetheap;
pub const sayhere = type_errors_mod.sayhere;
pub const setprefix = dump_mod.setprefix;
pub const setupdic = lex_mod.setupdic;
pub const EDOM = 33;
pub const ERANGE = 34;

pub const stoDbl = heap_mod.stoDbl;
pub fn strcons(heap: *heap_mod.Heap, x: Word, y: Word) Word {
    return make(heap, .STRCONS, x, y);
}
pub const struct_winsize = extern struct {
    ws_row: c_ushort,
    ws_col: c_ushort,
    ws_xpixel: c_ushort,
    ws_ypixel: c_ushort,
};
pub const struct_rlimit = extern struct {
    rlim_cur: u64,
    rlim_max: u64,
};
pub const subsumes = unify_mod.subsumes;
pub const synonym_t = word_mod.synonym_t;
pub const time_t = c_long;
pub const token = lex_mod.token;
pub const trueheapsize = heap_mod.trueheapsize;
pub const typeOf = infer_mod.typeOf;
pub const type_t = word_mod.type_t;
pub const typesfirst = depend_mod.typesfirst;
pub const undef_t = word_mod.undef_t;
pub const void_t = word_mod.void_t;
pub const wrong_t = word_mod.wrong_t;

// Std streams + stdio now live in word.zig (R1.5/R1.6 consolidation); re-export
// them so existing `clib.*` callers resolve to the single shared source.
pub const std_in = &word_mod.fio.std_in;
pub const std_out = &word_mod.fio.std_out;
pub const std_err = &word_mod.fio.std_err;

pub const stdin = word_mod.stdin;
pub const stdout = word_mod.stdout;
pub const stderr = word_mod.stderr;

// File pool + IO implementations now live in word.zig; re-export them.
pub const fopen = word_mod.fopen;
pub const fclose = word_mod.fclose;
pub const fileno = word_mod.fileno;
pub const setbuf = word_mod.setbuf;
pub const getc = word_mod.getc;
pub const getchar = word_mod.getchar;
pub const putc = word_mod.putc;
pub const fputc = word_mod.fputc;
pub const putchar = word_mod.putchar;
pub const ungetc = word_mod.ungetc;

pub export fn fromUTF8(fil: ?*Stream) c_ulong {
    const c0 = getc(fil);
    if (c0 == EOF) return std.math.maxInt(c_ulong);
    if (c0 <= 0x7f) return @intCast(c0);
    if ((c0 & 0xe0) == 0xc0) {
        const c1 = getc(fil);
        if (c1 == EOF or (c1 & 0xc0) != 0x80) return std.math.maxInt(c_ulong);
        return @intCast(((c0 & 0x1f) << 6) | (c1 & 0x3f));
    }
    if ((c0 & 0xf0) == 0xe0) {
        const c1 = getc(fil);
        if (c1 == EOF or (c1 & 0xc0) != 0x80) return std.math.maxInt(c_ulong);
        const c2 = getc(fil);
        if (c2 == EOF or (c2 & 0xc0) != 0x80) return std.math.maxInt(c_ulong);
        return @intCast(((c0 & 0x0f) << 12) | ((c1 & 0x3f) << 6) | (c2 & 0x3f));
    }
    if ((c0 & 0xf8) == 0xf0) {
        const c1 = getc(fil);
        if (c1 == EOF or (c1 & 0xc0) != 0x80) return std.math.maxInt(c_ulong);
        const c2 = getc(fil);
        if (c2 == EOF or (c2 & 0xc0) != 0x80) return std.math.maxInt(c_ulong);
        const c3 = getc(fil);
        if (c3 == EOF or (c3 & 0xc0) != 0x80) return std.math.maxInt(c_ulong);
        return @intCast(((c0 & 0x07) << 18) | ((c1 & 0x3f) << 12) | ((c2 & 0x3f) << 6) | (c3 & 0x3f));
    }
    return std.math.maxInt(c_ulong);
}

pub fn outUTF8(u: c_ulong, fil: ?*Stream) void {
    if (u <= 0x7f) {
        _ = putc(@intCast(u), fil);
    } else if (u <= 0x7ff) {
        _ = putc(@intCast(0xc0 | ((u & 0x7c0) >> 6)), fil);
        _ = putc(@intCast(0x80 | (u & 0x3f)), fil);
    } else if (u <= 0xffff) {
        _ = putc(@intCast(0xe0 | ((u & 0xf000) >> 12)), fil);
        _ = putc(@intCast(0x80 | ((u & 0x0fc0) >> 6)), fil);
        _ = putc(@intCast(0x80 | (u & 0x3f)), fil);
    } else if (u <= 0x10ffff) {
        _ = putc(@intCast(0xf0 | ((u & 0x1c0000) >> 18)), fil);
        _ = putc(@intCast(0x80 | ((u & 0x03f000) >> 12)), fil);
        _ = putc(@intCast(0x80 | ((u & 0x000fc0) >> 6)), fil);
        _ = putc(@intCast(0x80 | (u & 0x3f)), fil);
    }
}

pub const fgets = word_mod.fgets;

// POSIX wrappers
pub fn fork() c_int {
    return @intCast(std.c.fork());
}

pub fn wait(status: ?*c_int) c_int {
    var raw_status: WaitStatusType = 0;
    const pid = std.posix.system.waitpid(-1, &raw_status, 0);
    if (status) |s| {
        s.* = raw_status;
    }
    return syscallResult(pid);
}

pub fn open(path: [*:0]const u8, flags: c_int, mode: c_uint) c_int {
    const fd = std.posix.openatZ(std.posix.AT.FDCWD, path, @bitCast(flags), @intCast(mode)) catch return -1;
    return @intCast(fd);
}

pub fn close(fd: c_int) c_int {
    return syscallResult(std.posix.system.close(@intCast(fd)));
}

pub fn read(fd: c_int, buf: ?*anyopaque, count: usize) isize {
    if (buf == null) return -1;
    const slice = @as([*]u8, @ptrCast(buf.?))[0..count];
    const bytes_read = std.posix.read(fd, slice) catch return -1;
    return @intCast(bytes_read);
}

pub fn write(fd: c_int, buf: ?*const anyopaque, count: usize) isize {
    if (buf == null) return -1;
    const rc = std.posix.system.write(fd, @ptrCast(buf.?), count);
    return @intCast(rc);
}

pub fn ioctl(fd: c_int, request: c_ulong, window: *struct_winsize) c_int {
    return syscallResult(std.posix.system.ioctl(@intCast(fd), @intCast(request), @intFromPtr(window)));
}

pub fn unlink(path: [*:0]const u8) c_int {
    return syscallResult(std.posix.system.unlink(path));
}

pub fn exit(status: c_int) noreturn {
    std.process.exit(@intCast(status));
}

pub fn abort() noreturn {
    std.process.exit(134);
}

pub fn perror(s: [*:0]const u8) void {
    const msg = std.mem.span(s);
    std.debug.print("{s}: error\n", .{msg});
}

pub fn isatty(fd: c_int) c_int {
    return std.c.isatty(fd);
}

pub fn getcwd(buf: [*]u8, size: usize) ?[*]u8 {
    return std.c.getcwd(buf, size);
}

pub fn chdir(path: [*:0]const u8) c_int {
    return std.c.chdir(path);
}

pub fn getenv(name: ?*const anyopaque) ?[*:0]u8 {
    if (name == null) return null;
    const name_str = std.mem.span(@as([*:0]const u8, @ptrCast(name.?)));
    if (std.process.Environ.getPosix(rt.environ, name_str)) |val| {
        return @ptrCast(@constCast(val.ptr));
    }
    return null;
}

pub fn system(cmd: ?*const anyopaque) c_int {
    if (cmd == null) return 1;
    const cmd_str = @as([*:0]const u8, @ptrCast(cmd.?));

    const argv = [_][]const u8{ "/bin/sh", "-c", std.mem.span(cmd_str) };
    var child = std.process.spawn(rt.io, .{
        .argv = &argv,
        .stdin = .inherit,
        .stdout = .inherit,
        .stderr = .inherit,
    }) catch return -1;
    const term = child.wait(rt.io) catch return -1;
    switch (term) {
        .exited => |code| return @intCast(code),
        .signal => |sig| return @intCast(@intFromEnum(sig)),
        .stopped => |sig| return @intCast(@intFromEnum(sig)),
        .unknown => |val| return @intCast(val),
    }
}

pub fn getrlimit(resource: c_int, rlp: *struct_rlimit) c_int {
    const res: std.posix.rlimit_resource = @enumFromInt(resource);
    const lim = std.posix.getrlimit(res) catch return -1;
    rlp.rlim_cur = @intCast(lim.cur);
    rlp.rlim_max = @intCast(lim.max);
    return 0;
}

pub fn setrlimit(resource: c_int, rlp: *const struct_rlimit) c_int {
    const res: std.posix.rlimit_resource = @enumFromInt(resource);
    const lim = std.posix.rlimit{ .cur = @intCast(rlp.rlim_cur), .max = @intCast(rlp.rlim_max) };
    std.posix.setrlimit(res, lim) catch return -1;
    return 0;
}

pub fn dup2(oldfd: c_int, newfd: c_int) c_int {
    const rc = std.posix.system.dup2(oldfd, newfd);
    if (rc < 0) return -1;
    return newfd;
}

pub fn execl(path: [*:0]const u8, args: anytype) c_int {
    const ArgsType = @TypeOf(args);
    const fields = std.meta.fields(ArgsType);

    var argv: [fields.len:null]?[*:0]const u8 = [_:null]?[*:0]const u8{null} ** fields.len;
    inline for (fields, 0..) |field, idx| {
        const val = @field(args, field.name);
        const T = @TypeOf(val);
        argv[idx] = if (comptime T == [*:0]const u8 or T == [*:0]u8)
            val
        else if (comptime T == ?[*:0]const u8 or T == ?[*:0]u8)
            val
        else
            @as([*:0]const u8, @ptrCast(val));
    }

    const envp = env_slice.ptr;
    _ = std.posix.system.execve(path, &argv, envp);
    return -1;
}

// C-string implementations
pub fn strlen(s: ?*const anyopaque) usize {
    if (s == null) return 0;
    const ptr = @as([*:0]const u8, @ptrCast(s.?));
    return std.mem.span(ptr).len;
}

pub fn strcmp(a: ?*const anyopaque, b: ?*const anyopaque) c_int {
    if (a == null or b == null) return 0;
    const sa = std.mem.span(@as([*:0]const u8, @ptrCast(a.?)));
    const sb = std.mem.span(@as([*:0]const u8, @ptrCast(b.?)));
    const order = std.mem.order(u8, sa, sb);
    return switch (order) {
        .lt => -1,
        .eq => 0,
        .gt => 1,
    };
}

pub fn strncmp(a: ?*const anyopaque, b: ?*const anyopaque, n: usize) c_int {
    if (a == null or b == null or n == 0) return 0;
    const sa_all = std.mem.span(@as([*:0]const u8, @ptrCast(a.?)));
    const sb_all = std.mem.span(@as([*:0]const u8, @ptrCast(b.?)));
    const sa = sa_all[0..@min(sa_all.len, n)];
    const sb = sb_all[0..@min(sb_all.len, n)];
    const order = std.mem.order(u8, sa, sb);
    return switch (order) {
        .lt => -1,
        .eq => 0,
        .gt => 1,
    };
}

pub fn strcpy(dst: ?*anyopaque, src: ?*const anyopaque) ?*anyopaque {
    if (dst == null or src == null) return dst;
    const d = @as([*]u8, @ptrCast(dst.?));
    const s = @as([*:0]const u8, @ptrCast(src.?));
    var i: usize = 0;
    while (s[i] != 0) : (i += 1) {
        d[i] = s[i];
    }
    d[i] = 0;
    return dst;
}

pub fn strncat(dst: ?*anyopaque, src: ?*const anyopaque, n: usize) ?*anyopaque {
    if (dst == null or src == null or n == 0) return dst;
    const d = @as([*]u8, @ptrCast(dst.?));
    const s = @as([*:0]const u8, @ptrCast(src.?));
    var d_len: usize = 0;
    while (d[d_len] != 0) : (d_len += 1) {}
    var i: usize = 0;
    while (i < n and s[i] != 0) : (i += 1) {
        d[d_len + i] = s[i];
    }
    d[d_len + i] = 0;
    return dst;
}

pub fn strchr(s: ?*const anyopaque, c_val: c_int) ?[*:0]u8 {
    if (s == null) return null;
    const ptr = @as([*:0]u8, @ptrCast(@constCast(@as([*:0]const u8, @ptrCast(s.?)))));
    const ch = @as(u8, @intCast(c_val));
    var i: usize = 0;
    while (true) {
        if (ptr[i] == ch) {
            return @ptrCast(ptr + i);
        }
        if (ptr[i] == 0) break;
        i += 1;
    }
    return null;
}

pub fn strrchr(s: ?*const anyopaque, c_val: c_int) ?[*:0]u8 {
    if (s == null) return null;
    const ptr = @as([*:0]u8, @ptrCast(@constCast(@as([*:0]const u8, @ptrCast(s.?)))));
    const ch = @as(u8, @intCast(c_val));
    var last: ?[*:0]u8 = null;
    var i: usize = 0;
    while (true) {
        if (ptr[i] == ch) {
            last = @ptrCast(ptr + i);
        }
        if (ptr[i] == 0) break;
        i += 1;
    }
    return last;
}

pub fn strstr(haystack: ?*const anyopaque, needle: ?*const anyopaque) ?[*:0]u8 {
    if (haystack == null or needle == null) return null;
    const h_str = std.mem.span(@as([*:0]const u8, @ptrCast(haystack.?)));
    const n_str = std.mem.span(@as([*:0]const u8, @ptrCast(needle.?)));
    if (n_str.len == 0) return @ptrCast(@constCast(@as([*:0]const u8, @ptrCast(haystack.?))));

    const idx = std.mem.find(u8, h_str, n_str) orelse return null;
    const ptr = @as([*:0]u8, @ptrCast(@constCast(@as([*:0]const u8, @ptrCast(haystack.?)))));
    return @ptrCast(ptr + idx);
}

inline fn safeChar(ch: c_int) ?u8 {
    return if (ch >= 0 and ch <= 255) @intCast(ch) else null;
}

pub fn isalpha(ch: c_int) c_int {
    return if (safeChar(ch)) |b| (if (std.ascii.isAlphabetic(b)) @as(c_int, 1) else 0) else 0;
}

pub fn isalnum(ch: c_int) c_int {
    return if (safeChar(ch)) |b| (if (std.ascii.isAlphanumeric(b)) @as(c_int, 1) else 0) else 0;
}

pub fn isdigit(ch: c_int) c_int {
    return if (safeChar(ch)) |b| (if (std.ascii.isDigit(b)) @as(c_int, 1) else 0) else 0;
}

pub fn isxdigit(ch: c_int) c_int {
    return if (safeChar(ch)) |b| (if (std.ascii.isHex(b)) @as(c_int, 1) else 0) else 0;
}

pub fn isspace(ch: c_int) c_int {
    return if (safeChar(ch)) |b| (if (std.ascii.isWhitespace(b)) @as(c_int, 1) else 0) else 0;
}

pub fn tolower(ch: c_int) c_int {
    return if (safeChar(ch)) |b| @intCast(std.ascii.toLower(b)) else ch;
}

pub const struct_tms = extern struct {
    tms_utime: c_long,
    tms_stime: c_long,
    tms_cutime: c_long,
    tms_cstime: c_long,
};

pub fn fputs(s: [*:0]const u8, file: ?*Stream) c_int {
    const len = strlen(s);
    _ = fwrite(s, 1, len, file);
    return 0;
}

pub const fread = word_mod.fread;
pub const fwrite = word_mod.fwrite;

pub fn pipe(fds: *[2]c_int) c_int {
    return syscallResult(std.posix.system.pipe(fds));
}

pub fn strncpy(dst: ?*anyopaque, src: ?*const anyopaque, n: usize) ?*anyopaque {
    if (dst == null or src == null or n == 0) return dst;
    const d = @as([*]u8, @ptrCast(dst.?));
    const s = @as([*:0]const u8, @ptrCast(src.?));
    var i: usize = 0;
    var src_ended = false;
    while (i < n) : (i += 1) {
        if (!src_ended) {
            d[i] = s[i];
            if (s[i] == 0) src_ended = true;
        } else {
            d[i] = 0;
        }
    }
    return dst;
}

pub const struct_tm = extern struct {
    tm_sec: c_int,
    tm_min: c_int,
    tm_hour: c_int,
    tm_mday: c_int,
    tm_mon: c_int,
    tm_year: c_int,
    tm_wday: c_int,
    tm_yday: c_int,
    tm_isdst: c_int,
};

pub fn localtime(timer: *const time_t) ?*struct_tm {
    _ = timer;
    return null;
}

pub const fdopen = word_mod.fdopen;

pub const clock_t = c_long;

pub fn times(buf: *struct_tms) clock_t {
    const C = struct {
        extern fn times(buf: *struct_tms) clock_t;
    };
    return C.times(buf);
}

pub fn sysconf(name: c_int) c_long {
    return std.c.sysconf(name);
}

pub const _SC_CLK_TCK = if (builtin.os.tag == .macos) @as(c_int, 3) else @as(c_int, 2);

pub fn rindex(s: ?*const anyopaque, c_val: c_int) ?[*:0]u8 {
    return strrchr(s, c_val);
}

pub fn geteuid() c_uint {
    return std.posix.system.geteuid();
}

pub fn getegid() c_uint {
    return std.posix.system.getegid();
}
