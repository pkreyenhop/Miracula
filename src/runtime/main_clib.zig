const word_mod = @import("word.zig");
const std = @import("std");
const builtin = @import("builtin");
const rt = @import("runtime_state.zig");

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

// jmp_buf/sigjmp_buf: opaque buffers large enough for all supported platforms.
// setjmp/longjmp/sigsetjmp/siglongjmp live in libSystem on macOS and libc on Linux.
pub const jmp_buf = extern struct { __opaque: [512]u8 align(16) = [_]u8{0} ** 512 };
pub const sigjmp_buf = extern struct { __opaque: [520]u8 align(16) = [_]u8{0} ** 520 };
pub extern fn setjmp(env: *anyopaque) c_int;
pub extern fn longjmp(env: *anyopaque, val: c_int) noreturn;
pub const sigsetjmp = if (builtin.os.tag == .macos)
    struct {
        extern fn sigsetjmp(env: *anyopaque, savemask: c_int) c_int;
    }.sigsetjmp
else
    struct {
        extern fn __sigsetjmp(env: *anyopaque, savemask: c_int) c_int;
    }.__sigsetjmp;
pub extern fn siglongjmp(env: *anyopaque, val: c_int) noreturn;

// Definitions from data.h / combs.h
pub const pnlim: c_int = 1024;
pub const BUFSIZE: c_int = 1024;
pub const Word = word_mod.Word;

pub const AP = word_mod.AP;
pub const APPEND = word_mod.APPEND;
pub const ARCTAN_FN = word_mod.ARCTAN_FN;
pub const CODE = word_mod.CODE;
pub const CONS = word_mod.CONS;
pub const CONST = word_mod.CONST;
pub const CONSTRUCTOR = word_mod.CONSTRUCTOR;
pub const COS_FN = word_mod.COS_FN;
pub const DATAPAIR = word_mod.DATAPAIR;
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
pub const FILE = word_mod.FILE;
pub const FILEINFO = word_mod.FILEINFO;
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
pub const ID = word_mod.ID;
pub const INTEGER = word_mod.INTEGER;
pub const LABEL = word_mod.LABEL;
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
pub const STRCONS = word_mod.STRCONS;
pub const TAKE = word_mod.TAKE;
pub const TIOCGWINSZ: c_ulong = if (builtin.os.tag == .macos) 0x40087468 else 0x5413;
pub const TL = word_mod.TL;
pub const UNDEF = word_mod.UNDEF;
pub extern fn UNION(s1: word, s2: word) word;
pub const VALUE = word_mod.VALUE;
pub const XVERSION = 83;
pub const ZIP = word_mod.ZIP;
pub const abstract_t = word_mod.abstract_t;
pub const placeholder_t = word_mod.placeholder_t;
pub extern fn add1(e: word, s: word) word;
pub extern fn addextn(b: word, s: [*:0]u8) [*:0]u8;
pub extern fn adjust_prefix(f: [*:0]u8) void;
pub const algebraic_t = word_mod.algebraic_t;
pub fn ap(x: Word, y: Word) Word {
    return make(AP, x, y);
}
pub fn ap2(x: Word, y: Word, z: Word) Word {
    return ap(ap(x, y), z);
}
pub extern fn append1(x: word, y: word) word;
pub const bool_t = word_mod.bool_t;
pub const char_t = word_mod.char_t;
pub extern fn checktypes() void;
pub extern fn codegen(x: word) word;
pub fn cons(x: Word, y: Word) Word {
    return make(word_mod.CONS, x, y);
}
pub fn datapair(x: Word, y: Word) Word {
    return make(DATAPAIR, x, y);
}
pub extern fn deps(x: word) word;
pub extern fn dump_script(files: word, f: ?*FILE) void;
pub extern fn findid(p: [*:0]const u8) word;
pub extern fn gc() void;
pub extern fn gcpatch() void;
pub extern fn get_here(x: Word) Word;
pub extern fn getaka(x: Word) [*:0]const u8;
pub extern fn geterrlin(t_ptr: [*:0]const u8) Word;
pub extern fn getstring(x: word, cmd: ?[*:0]const u8) [*:0]const u8;
pub extern fn instantiate(t: word) word;
pub extern fn intersection(s1: word, s2: word) word;
pub extern fn make(t: u8, x: word, y: word) word;
pub extern fn keep(p: [*:0]u8) [*:0]u8;
pub extern fn load_script(f: ?*FILE, src: [*:0]u8, aliases: word, params: word, main: word) word;
pub extern fn make_id(p: [*:0]const u8) word;
pub extern fn mallocfail(s: [*:0]const u8) void;
pub extern fn setdiff(s1: word, s2: word) word;
pub extern fn make_pn(val: word) word;
pub extern var cmbnms: [*][*:0]u8;
pub fn make_typ(a: Word, shf: Word, class: Word, info: Word) Word {
    return cons(cons(a, shf), cons(class, info));
}
pub extern fn member(s: word, x: word) word;
pub extern fn mkprivate(x: word) void;
pub extern fn mkshow(s: word, p: word, t: word) word;
pub const num_t = word_mod.num_t;
pub extern fn obey(x: Word) void;
pub extern fn okdump(t: [*:0]u8) c_int;
pub extern fn okid(ch: c_int) c_int;
pub extern fn openfile(n: [*:0]const u8) c_int;
pub extern fn out(f: ?*FILE, x: word) void;
pub extern fn out_here(f: ?*FILE, h: word, nl: word) void;
pub extern fn out_pattern(f: ?*FILE, x: word) void;
pub extern fn out_type(t: word) void;
pub extern fn output(e: word) void;
pub extern fn outstats() void;
pub extern fn printlist(title: [*:0]const u8, l: word) void;
pub extern fn process() word;
pub extern fn rdline() [*:0]u8;
pub fn readvals(x: Word, y: Word) Word {
    return make(word_mod.STARTREADVALS, x, y);
}
pub extern fn report_type(x: word) void;
pub extern fn resetheap() void;
pub extern fn sayhere(h_val: Word, nl: Word) void;
pub extern fn setprefix(p: [*:0]u8) void;
pub extern fn setupdic() void;
// sigjmp_buf, sigsetjmp, siglongjmp are declared above with the jmp_buf family.
pub const EDOM = 33;
pub const ERANGE = 34;

pub extern fn sto_dbl(x: f64) word;
pub fn strcons(x: Word, y: Word) Word {
    return make(STRCONS, x, y);
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
pub extern fn subsumes(t1: word, t2: word) word;
pub const synonym_t = word_mod.synonym_t;
pub const time_t = c_long;
pub extern fn token() [*:0]u8;
pub extern fn trueheapsize() word;
pub extern fn type_of(x: word) word;
pub const type_t = word_mod.type_t;
pub extern fn typesfirst(x: word) word;
pub const undef_t = word_mod.undef_t;
pub const void_t = word_mod.void_t;
pub const wrong_t = word_mod.wrong_t;

// Std streams + stdio now live in word.zig (R1.5/R1.6 consolidation); re-export
// them so existing `clib.*` callers resolve to the single shared source.
pub const std_in = &word_mod.std_in;
pub const std_out = &word_mod.std_out;
pub const std_err = &word_mod.std_err;

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

pub export fn fromUTF8(fil: ?*FILE) c_ulong {
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

pub export fn outUTF8(u: c_ulong, fil: ?*FILE) void {
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

// Formatting helpers
fn formatArg(
    writer: anytype,
    val: anytype,
    specifier: u8,
    left_align: bool,
    zero_pad: bool,
    width: usize,
    precision: ?usize,
) !void {
    _ = precision;
    const T = @TypeOf(val);
    const is_int = comptime @typeInfo(T) == .int or @typeInfo(T) == .comptime_int;
    const is_float = comptime @typeInfo(T) == .float or @typeInfo(T) == .comptime_float;
    var buf: [128]u8 = undefined;
    var str: []const u8 = "";

    switch (specifier) {
        's' => {
            if (comptime T == ?[*:0]const u8 or T == ?[*:0]u8) {
                if (val) |p| {
                    str = std.mem.span(p);
                } else {
                    str = "(null)";
                }
            } else if (comptime T == [*:0]const u8 or T == [*:0]u8) {
                str = std.mem.span(val);
            } else if (comptime @typeInfo(T) == .pointer) {
                str = std.mem.span(@as([*:0]const u8, @ptrCast(val)));
            } else {
                str = "(invalid string type)";
            }
        },
        'c' => {
            if (comptime is_int) {
                buf[0] = @intCast(val);
            } else {
                buf[0] = '?';
            }
            str = buf[0..1];
        },
        'd', 'i' => {
            if (comptime is_int) {
                str = try std.fmt.bufPrint(&buf, "{d}", .{val});
            } else if (comptime is_float) {
                str = try std.fmt.bufPrint(&buf, "{d}", .{@as(i64, @intFromFloat(val))});
            } else {
                str = "0";
            }
        },
        'u' => {
            if (comptime is_int and @typeInfo(T).int.signedness == .signed) {
                const U = std.meta.Int(.unsigned, @typeInfo(T).int.bits);
                str = try std.fmt.bufPrint(&buf, "{d}", .{@as(U, @bitCast(val))});
            } else if (comptime is_int) {
                str = try std.fmt.bufPrint(&buf, "{d}", .{val});
            } else {
                str = "0";
            }
        },
        'x' => {
            if (comptime is_int) {
                str = try std.fmt.bufPrint(&buf, "{x}", .{val});
            } else {
                str = "0";
            }
        },
        'o' => {
            if (comptime is_int) {
                str = try std.fmt.bufPrint(&buf, "{o}", .{val});
            } else {
                str = "0";
            }
        },
        'f', 'g', 'e', 'a' => {
            if (comptime is_float) {
                str = try std.fmt.bufPrint(&buf, "{d}", .{val});
            } else if (comptime is_int) {
                str = try std.fmt.bufPrint(&buf, "{d}", .{@as(f64, @floatFromInt(val))});
            } else {
                str = "0.0";
            }
        },
        else => {
            str = "?INVALID_SPECIFIER?";
        },
    }

    if (str.len < width) {
        const pad_len = width - str.len;
        if (left_align) {
            try writer.writeAll(str);
            try writer.writeByteNTimes(' ', pad_len);
        } else if (zero_pad and (specifier == 'd' or specifier == 'i' or specifier == 'u' or specifier == 'x' or specifier == 'o' or specifier == 'f')) {
            var actual_str = str;
            if (str.len > 0 and str[0] == '-') {
                try writer.writeByte('-');
                actual_str = str[1..];
            }
            try writer.writeByteNTimes('0', pad_len);
            try writer.writeAll(actual_str);
        } else {
            try writer.writeByteNTimes(' ', pad_len);
            try writer.writeAll(str);
        }
    } else {
        try writer.writeAll(str);
    }
}

pub fn formatC(writer: anytype, format: [*:0]const u8, args: anytype) !void {
    const fmt = std.mem.span(format);
    // Transparently unwrap double-wrapped tuples: .{.{a,b}} → .{a,b}
    // This supports both the .{a,b} and .{.{a,b}} calling conventions.
    const unwrapped_args = blk: {
        const ArgsType = @TypeOf(args);
        const fs = std.meta.fields(ArgsType);
        if (comptime (fs.len == 1 and @typeInfo(fs[0].type) == .@"struct")) {
            break :blk @field(args, fs[0].name);
        }
        break :blk args;
    };
    const ArgsType = @TypeOf(unwrapped_args);
    const fields = std.meta.fields(ArgsType);

    var arg_idx: usize = 0;
    var i: usize = 0;

    while (i < fmt.len) {
        if (fmt[i] == '%') {
            i += 1;
            if (i >= fmt.len) break;
            if (fmt[i] == '%') {
                try writer.writeByte('%');
                i += 1;
                continue;
            }

            var left_align = false;
            var zero_pad = false;
            while (i < fmt.len) {
                if (fmt[i] == '-') {
                    left_align = true;
                    i += 1;
                } else if (fmt[i] == '0') {
                    zero_pad = true;
                    i += 1;
                } else {
                    break;
                }
            }

            var width: usize = 0;
            while (i < fmt.len and fmt[i] >= '0' and fmt[i] <= '9') {
                width = width * 10 + (fmt[i] - '0');
                i += 1;
            }

            var precision: ?usize = null;
            if (i < fmt.len and fmt[i] == '.') {
                i += 1;
                var prec_val: usize = 0;
                while (i < fmt.len and fmt[i] >= '0' and fmt[i] <= '9') {
                    prec_val = prec_val * 10 + (fmt[i] - '0');
                    i += 1;
                }
                precision = prec_val;
            }

            while (i < fmt.len and (fmt[i] == 'l' or fmt[i] == 'h' or fmt[i] == 'z' or fmt[i] == 'j' or fmt[i] == 't')) {
                i += 1;
            }

            if (i >= fmt.len) break;
            const spec = fmt[i];
            i += 1;

            if (arg_idx >= fields.len) {
                try writer.writeAll("%ERR_MISSING_ARG%");
                continue;
            }

            inline for (fields, 0..) |field, idx| {
                if (idx == arg_idx) {
                    const val = @field(unwrapped_args, field.name);
                    try formatArg(writer, val, spec, left_align, zero_pad, width, precision);
                }
            }
            arg_idx += 1;
        } else {
            const start = i;
            while (i < fmt.len and fmt[i] != '%') : (i += 1) {}
            try writer.writeAll(fmt[start..i]);
        }
    }
}

pub fn fprintf(file: ?*FILE, format: [*:0]const u8, args: anytype) c_int {
    const f = file orelse return -1;
    const CountingWriter = struct {
        file: *FILE,
        written: usize = 0,
        pub fn writeByte(self: *@This(), b: u8) !void {
            try self.file.writeByte(b);
            self.written += 1;
        }
        pub fn writeAll(self: *@This(), bytes: []const u8) !void {
            try self.file.writeAll(bytes);
            self.written += bytes.len;
        }
        pub fn writeByteNTimes(self: *@This(), b: u8, count: usize) !void {
            try self.file.writeByteNTimes(b, count);
            self.written += count;
        }
    };
    var cw = CountingWriter{ .file = f };
    formatC(&cw, format, args) catch return -1;
    return @intCast(cw.written);
}

pub const printf = word_mod.printf;

const BufferWriter = struct {
    buf: [*]u8,
    size: usize,
    pos: usize,

    pub const Error = error{NoSpace};

    pub fn writeByte(self: *@This(), b: u8) Error!void {
        if (self.pos >= self.size) return error.NoSpace;
        self.buf[self.pos] = b;
        self.pos += 1;
    }

    pub fn writeAll(self: *@This(), bytes: []const u8) Error!void {
        if (self.pos + bytes.len > self.size) return error.NoSpace;
        @memcpy(self.buf[self.pos .. self.pos + bytes.len], bytes);
        self.pos += bytes.len;
    }

    pub fn writeByteNTimes(self: *@This(), b: u8, count: usize) Error!void {
        if (self.pos + count > self.size) return error.NoSpace;
        @memset(self.buf[self.pos .. self.pos + count], b);
        self.pos += count;
    }
};

pub fn sprintf(buf: [*]u8, format: [*:0]const u8, args: anytype) c_int {
    var bw = BufferWriter{ .buf = buf, .size = 1024 * 1024, .pos = 0 };
    formatC(&bw, format, args) catch {};
    buf[bw.pos] = 0;
    return @intCast(bw.pos);
}

pub fn snprintf(buf: [*]u8, size: usize, format: [*:0]const u8, args: anytype) c_int {
    if (size == 0) return 0;
    var bw = BufferWriter{ .buf = buf, .size = size - 1, .pos = 0 };
    var total_written: usize = 0;
    const CountingWriter = struct {
        bw: *BufferWriter,
        total: *usize,
        pub const Error = error{NoSpace};
        pub fn writeByte(self: @This(), b: u8) Error!void {
            if (self.bw.pos < self.bw.size) {
                self.bw.buf[self.bw.pos] = b;
                self.bw.pos += 1;
            }
            self.total.* += 1;
        }
        pub fn writeAll(self: @This(), bytes: []const u8) Error!void {
            for (bytes) |b| {
                if (self.bw.pos < self.bw.size) {
                    self.bw.buf[self.bw.pos] = b;
                    self.bw.pos += 1;
                }
                self.total.* += 1;
            }
        }
        pub fn writeByteNTimes(self: @This(), b: u8, count: usize) Error!void {
            var i: usize = 0;
            while (i < count) : (i += 1) {
                try self.writeByte(b);
            }
        }
    };
    const cw = CountingWriter{ .bw = &bw, .total = &total_written };
    formatC(cw, format, args) catch {};
    buf[bw.pos] = 0;
    return @intCast(total_written);
}

// Scanning implementations
fn scanVal(str: []const u8, s_idx: *usize, spec: u8, width: ?usize, ptr: anytype) bool {
    const PtrType = @TypeOf(ptr);
    const ptr_info = @typeInfo(PtrType).pointer;
    const ChildType = ptr_info.child;
    const is_int_child = comptime @typeInfo(ChildType) == .int;
    const is_float_child = comptime @typeInfo(ChildType) == .float;
    const is_array_child = comptime @typeInfo(ChildType) == .array;
    const is_many_ptr = comptime ptr_info.size == .many or ptr_info.size == .c;

    switch (spec) {
        'c' => {
            if (s_idx.* >= str.len) return false;
            if (comptime is_int_child) {
                ptr.* = @intCast(str[s_idx.*]);
            } else {
                return false;
            }
            s_idx.* += 1;
            return true;
        },
        's' => {
            const start = s_idx.*;
            var end = start;
            const limit = if (width) |w| start + w else str.len;
            while (end < str.len and end < limit and !std.ascii.isWhitespace(str[end])) {
                end += 1;
            }
            if (end == start) return false;
            const scanned = str[start..end];
            if (comptime is_array_child) {
                const arr_len = @typeInfo(ChildType).array.len;
                if (scanned.len >= arr_len) return false;
                @memcpy(ptr[0..scanned.len], scanned);
                ptr[scanned.len] = 0;
            } else if (comptime is_many_ptr) {
                const buf: [*]u8 = @ptrCast(ptr);
                @memcpy(buf[0..scanned.len], scanned);
                buf[scanned.len] = 0;
            } else {
                return false;
            }
            s_idx.* = end;
            return true;
        },
        'd', 'i' => {
            if (comptime !is_int_child) return false;
            const start = s_idx.*;
            var end = start;
            if (end < str.len and (str[end] == '-' or str[end] == '+')) end += 1;
            while (end < str.len and str[end] >= '0' and str[end] <= '9') end += 1;
            if (end == start or (end == start + 1 and (str[start] == '-' or str[start] == '+'))) return false;
            const val = std.fmt.parseInt(ChildType, str[start..end], 10) catch return false;
            ptr.* = val;
            s_idx.* = end;
            return true;
        },
        'u' => {
            if (comptime !is_int_child) return false;
            const start = s_idx.*;
            var end = start;
            while (end < str.len and str[end] >= '0' and str[end] <= '9') end += 1;
            if (end == start) return false;
            const val = std.fmt.parseInt(ChildType, str[start..end], 10) catch return false;
            ptr.* = val;
            s_idx.* = end;
            return true;
        },
        'x' => {
            if (comptime !is_int_child) return false;
            const start = s_idx.*;
            var end = start;
            if (end + 1 < str.len and str[end] == '0' and (str[end + 1] == 'x' or str[end + 1] == 'X')) end += 2;
            const hex_start = end;
            while (end < str.len and ((str[end] >= '0' and str[end] <= '9') or
                (str[end] >= 'a' and str[end] <= 'f') or (str[end] >= 'A' and str[end] <= 'F'))) end += 1;
            if (end == hex_start) return false;
            const val = std.fmt.parseInt(ChildType, str[hex_start..end], 16) catch return false;
            ptr.* = val;
            s_idx.* = end;
            return true;
        },
        'f', 'g', 'e' => {
            if (comptime !is_float_child) return false;
            const start = s_idx.*;
            var end = start;
            if (end < str.len and (str[end] == '-' or str[end] == '+')) end += 1;
            var has_dot = false;
            while (end < str.len) {
                const sc = str[end];
                if (sc >= '0' and sc <= '9') {
                    end += 1;
                } else if (sc == '.' and !has_dot) {
                    has_dot = true;
                    end += 1;
                } else {
                    break;
                }
            }
            if (end == start) return false;
            const val = std.fmt.parseFloat(ChildType, str[start..end]) catch return false;
            ptr.* = val;
            s_idx.* = end;
            return true;
        },
        else => return false,
    }
}

pub fn sscanf(buf: ?*const anyopaque, format: [*:0]const u8, args: anytype) c_int {
    if (buf == null) return -1;
    const str = std.mem.span(@as([*:0]const u8, @ptrCast(buf.?)));

    const fmt = std.mem.span(format);
    const ArgsType = @TypeOf(args);
    const fields = std.meta.fields(ArgsType);

    var s_idx: usize = 0;
    var f_idx: usize = 0;
    var arg_idx: usize = 0;
    var parsed_count: c_int = 0;

    while (f_idx < fmt.len) {
        if (fmt[f_idx] == '%') {
            f_idx += 1;
            if (f_idx >= fmt.len) break;
            if (fmt[f_idx] == '%') {
                if (s_idx >= str.len or str[s_idx] != '%') return parsed_count;
                s_idx += 1;
                f_idx += 1;
                continue;
            }

            var suppress = false;
            if (fmt[f_idx] == '*') {
                suppress = true;
                f_idx += 1;
            }

            var width: ?usize = null;
            var w_val: usize = 0;
            var has_w = false;
            while (f_idx < fmt.len and fmt[f_idx] >= '0' and fmt[f_idx] <= '9') {
                w_val = w_val * 10 + (fmt[f_idx] - '0');
                has_w = true;
                f_idx += 1;
            }
            if (has_w) width = w_val;

            while (f_idx < fmt.len and (fmt[f_idx] == 'l' or fmt[f_idx] == 'h')) {
                f_idx += 1;
            }

            if (f_idx >= fmt.len) break;
            const spec = fmt[f_idx];
            f_idx += 1;

            if (spec != 'c') {
                while (s_idx < str.len and std.ascii.isWhitespace(str[s_idx])) {
                    s_idx += 1;
                }
            }

            if (s_idx >= str.len) {
                if (parsed_count == 0) return -1;
                return parsed_count;
            }

            if (suppress) {
                if (spec == 'c') {
                    s_idx += 1;
                } else {
                    while (s_idx < str.len and !std.ascii.isWhitespace(str[s_idx])) {
                        s_idx += 1;
                    }
                }
                continue;
            }

            if (arg_idx >= fields.len) return parsed_count;

            const success = inline for (fields, 0..) |field, idx| {
                if (idx == arg_idx) {
                    const ptr = @field(args, field.name);
                    break scanVal(str, &s_idx, spec, width, ptr);
                }
            } else false;

            if (!success) return parsed_count;
            parsed_count += 1;
            arg_idx += 1;
        } else if (std.ascii.isWhitespace(fmt[f_idx])) {
            f_idx += 1;
            while (s_idx < str.len and std.ascii.isWhitespace(str[s_idx])) {
                s_idx += 1;
            }
        } else {
            if (s_idx >= str.len or str[s_idx] != fmt[f_idx]) {
                return parsed_count;
            }
            s_idx += 1;
            f_idx += 1;
        }
    }

    return parsed_count;
}

fn scanValFromFile(f: *FILE, spec: u8, width: ?usize, ptr: anytype) bool {
    const PtrType = @TypeOf(ptr);
    const ptr_info = @typeInfo(PtrType).pointer;
    const ChildType = ptr_info.child;
    const is_int_child = comptime @typeInfo(ChildType) == .int;
    const is_float_child = comptime @typeInfo(ChildType) == .float;
    const is_array_child = comptime @typeInfo(ChildType) == .array;
    const is_many_ptr = comptime ptr_info.size == .many or ptr_info.size == .c;

    switch (spec) {
        'c' => {
            const ch = getc(f);
            if (ch == -1) return false;
            if (comptime is_int_child) {
                ptr.* = @intCast(ch);
            } else {
                return false;
            }
            return true;
        },
        's' => {
            var buf: [1024]u8 = undefined;
            var len: usize = 0;
            const limit = if (width) |w| w else buf.len;
            while (len < limit) {
                const ch = getc(f);
                if (ch == -1) break;
                if (std.ascii.isWhitespace(@intCast(ch))) {
                    _ = ungetc(ch, f);
                    break;
                }
                buf[len] = @intCast(ch);
                len += 1;
            }
            if (len == 0) return false;
            const scanned = buf[0..len];
            if (comptime is_array_child) {
                const arr_len = @typeInfo(ChildType).array.len;
                if (scanned.len >= arr_len) return false;
                @memcpy(ptr[0..scanned.len], scanned);
                ptr[scanned.len] = 0;
            } else if (comptime is_many_ptr) {
                const b: [*]u8 = @ptrCast(ptr);
                @memcpy(b[0..scanned.len], scanned);
                b[scanned.len] = 0;
            } else {
                return false;
            }
            return true;
        },
        'd', 'i' => {
            if (comptime !is_int_child) return false;
            var buf: [64]u8 = undefined;
            var len: usize = 0;
            const ch_first = getc(f);
            if (ch_first == -1) return false;
            if (ch_first == '-' or ch_first == '+') {
                buf[0] = @intCast(ch_first);
                len = 1;
            } else {
                _ = ungetc(ch_first, f);
            }
            while (len < buf.len) {
                const ch = getc(f);
                if (ch == -1) break;
                if (ch >= '0' and ch <= '9') {
                    buf[len] = @intCast(ch);
                    len += 1;
                } else {
                    _ = ungetc(ch, f);
                    break;
                }
            }
            if (len == 0 or (len == 1 and (buf[0] == '-' or buf[0] == '+'))) return false;
            const val = std.fmt.parseInt(ChildType, buf[0..len], 10) catch return false;
            ptr.* = val;
            return true;
        },
        'u' => {
            if (comptime !is_int_child) return false;
            var buf: [64]u8 = undefined;
            var len: usize = 0;
            while (len < buf.len) {
                const ch = getc(f);
                if (ch == -1) break;
                if (ch >= '0' and ch <= '9') {
                    buf[len] = @intCast(ch);
                    len += 1;
                } else {
                    _ = ungetc(ch, f);
                    break;
                }
            }
            if (len == 0) return false;
            const val = std.fmt.parseInt(ChildType, buf[0..len], 10) catch return false;
            ptr.* = val;
            return true;
        },
        'x' => {
            if (comptime !is_int_child) return false;
            var buf: [64]u8 = undefined;
            var len: usize = 0;
            const c1 = getc(f);
            if (c1 == '0') {
                const c2 = getc(f);
                if (c2 != 'x' and c2 != 'X') {
                    if (c2 != -1) _ = ungetc(c2, f);
                    _ = ungetc(c1, f);
                }
            } else {
                if (c1 != -1) _ = ungetc(c1, f);
            }
            while (len < buf.len) {
                const ch = getc(f);
                if (ch == -1) break;
                if ((ch >= '0' and ch <= '9') or (ch >= 'a' and ch <= 'f') or (ch >= 'A' and ch <= 'F')) {
                    buf[len] = @intCast(ch);
                    len += 1;
                } else {
                    _ = ungetc(ch, f);
                    break;
                }
            }
            if (len == 0) return false;
            const val = std.fmt.parseInt(ChildType, buf[0..len], 16) catch return false;
            ptr.* = val;
            return true;
        },
        'f', 'g', 'e' => {
            if (comptime !is_float_child) return false;
            var buf: [64]u8 = undefined;
            var len: usize = 0;
            const ch_first = getc(f);
            if (ch_first == -1) return false;
            if (ch_first == '-' or ch_first == '+') {
                buf[0] = @intCast(ch_first);
                len = 1;
            } else {
                _ = ungetc(ch_first, f);
            }
            var has_dot = false;
            while (len < buf.len) {
                const ch = getc(f);
                if (ch == -1) break;
                if (ch >= '0' and ch <= '9') {
                    buf[len] = @intCast(ch);
                    len += 1;
                } else if (ch == '.' and !has_dot) {
                    has_dot = true;
                    buf[len] = '.';
                    len += 1;
                } else {
                    _ = ungetc(ch, f);
                    break;
                }
            }
            if (len == 0) return false;
            const val = std.fmt.parseFloat(ChildType, buf[0..len]) catch return false;
            ptr.* = val;
            return true;
        },
        else => return false,
    }
}

pub fn fscanf(file: ?*FILE, format: [*:0]const u8, args: anytype) c_int {
    const f = file orelse return -1;
    const fmt = std.mem.span(format);
    const ArgsType = @TypeOf(args);
    const fields = std.meta.fields(ArgsType);

    var f_idx: usize = 0;
    var arg_idx: usize = 0;
    var parsed_count: c_int = 0;

    while (f_idx < fmt.len) {
        if (fmt[f_idx] == '%') {
            f_idx += 1;
            if (f_idx >= fmt.len) break;
            if (fmt[f_idx] == '%') {
                const ch = getc(f);
                if (ch != '%') {
                    if (ch != -1) _ = ungetc(ch, f);
                    return parsed_count;
                }
                f_idx += 1;
                continue;
            }

            var suppress = false;
            if (fmt[f_idx] == '*') {
                suppress = true;
                f_idx += 1;
            }

            var width: ?usize = null;
            var w_val: usize = 0;
            var has_w = false;
            while (f_idx < fmt.len and fmt[f_idx] >= '0' and fmt[f_idx] <= '9') {
                w_val = w_val * 10 + (fmt[f_idx] - '0');
                has_w = true;
                f_idx += 1;
            }
            if (has_w) width = w_val;

            while (f_idx < fmt.len and (fmt[f_idx] == 'l' or fmt[f_idx] == 'h')) {
                f_idx += 1;
            }

            if (f_idx >= fmt.len) break;
            const spec = fmt[f_idx];
            f_idx += 1;

            if (spec != 'c') {
                while (true) {
                    const ch = getc(f);
                    if (ch == -1) {
                        if (parsed_count == 0) return -1;
                        return parsed_count;
                    }
                    if (!std.ascii.isWhitespace(@intCast(ch))) {
                        _ = ungetc(ch, f);
                        break;
                    }
                }
            }

            if (suppress) {
                if (spec == 'c') {
                    _ = getc(f);
                } else {
                    while (true) {
                        const ch = getc(f);
                        if (ch == -1) break;
                        if (std.ascii.isWhitespace(@intCast(ch))) {
                            _ = ungetc(ch, f);
                            break;
                        }
                    }
                }
                continue;
            }

            if (arg_idx >= fields.len) return parsed_count;

            const success = inline for (fields, 0..) |field, idx| {
                if (idx == arg_idx) {
                    const ptr = @field(args, field.name);
                    break scanValFromFile(f, spec, width, ptr);
                }
            } else false;

            if (!success) return parsed_count;
            parsed_count += 1;
            arg_idx += 1;
        } else if (std.ascii.isWhitespace(fmt[f_idx])) {
            f_idx += 1;
            while (true) {
                const ch = getc(f);
                if (ch == -1) break;
                if (!std.ascii.isWhitespace(@intCast(ch))) {
                    _ = ungetc(ch, f);
                    break;
                }
            }
        } else {
            const ch = getc(f);
            if (ch == -1 or ch != fmt[f_idx]) {
                if (ch != -1) _ = ungetc(ch, f);
                return parsed_count;
            }
            f_idx += 1;
        }
    }

    return parsed_count;
}

// Memory implementations
pub fn malloc(size: usize) ?*anyopaque {
    if (size == 0) return null;
    const total_size = size + @sizeOf(usize);
    const bytes = std.heap.page_allocator.alloc(u8, total_size) catch return null;
    const len_ptr = @as(*usize, @ptrCast(@alignCast(&bytes[0])));
    len_ptr.* = total_size;
    return @ptrCast(&bytes[@sizeOf(usize)]);
}

pub fn free(ptr: ?*anyopaque) void {
    if (ptr) |p| {
        const u8_ptr = @as([*]u8, @ptrCast(p)) - @sizeOf(usize);
        const len_ptr = @as(*const usize, @ptrCast(@alignCast(u8_ptr)));
        const total_size = len_ptr.*;
        std.heap.page_allocator.free(u8_ptr[0..total_size]);
    }
}

// POSIX wrappers
pub fn fork() c_int {
    if (builtin.os.tag == .linux) {
        return @intCast(std.os.linux.fork());
    } else {
        const S = struct {
            extern fn fork() c_int;
        };
        return S.fork();
    }
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
    const C = struct {
        extern fn isatty(fd: c_int) c_int;
    };
    return C.isatty(fd);
}

pub fn getcwd(buf: [*]u8, size: usize) ?[*]u8 {
    const C = struct {
        extern fn getcwd(buf: [*]u8, size: usize) ?[*]u8;
    };
    return C.getcwd(buf, size);
}

pub fn chdir(path: [*:0]const u8) c_int {
    const C = struct {
        extern fn chdir(path: [*:0]const u8) c_int;
    };
    return C.chdir(path);
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

    var argv: [fields.len:null]?[*:0]const u8 = undefined;
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

pub fn strcat(dst: ?*anyopaque, src: ?*const anyopaque) ?*anyopaque {
    if (dst == null or src == null) return dst;
    const d = @as([*]u8, @ptrCast(dst.?));
    const s = @as([*:0]const u8, @ptrCast(src.?));
    var d_len: usize = 0;
    while (d[d_len] != 0) : (d_len += 1) {}
    var i: usize = 0;
    while (s[i] != 0) : (i += 1) {
        d[d_len + i] = s[i];
    }
    d[d_len + i] = 0;
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

    const idx = std.mem.indexOf(u8, h_str, n_str) orelse return null;
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

pub fn fputs(s: [*:0]const u8, file: ?*FILE) c_int {
    const len = strlen(s);
    _ = fwrite(s, 1, len, file);
    return 0;
}

pub const fmemopen = word_mod.fmemopen;

pub const fread = word_mod.fread;
pub const fwrite = word_mod.fwrite;

pub fn calloc(nmemb: usize, size: usize) ?*anyopaque {
    const total = nmemb * size;
    const ptr = malloc(total) orelse return null;
    @memset(@as([*]u8, @ptrCast(ptr))[0..total], 0);
    return ptr;
}

pub fn realloc(ptr: ?*anyopaque, size: usize) ?*anyopaque {
    if (ptr == null) return malloc(size);
    if (size == 0) {
        free(ptr);
        return null;
    }
    const u8_ptr = @as([*]u8, @ptrCast(ptr.?)) - @sizeOf(usize);
    const len_ptr = @as(*const usize, @ptrCast(@alignCast(u8_ptr)));
    const old_total_size = len_ptr.*;
    const old_data_size = old_total_size - @sizeOf(usize);
    const new_ptr = malloc(size) orelse return null;
    const copy_size = @min(old_data_size, size);
    @memcpy(@as([*]u8, @ptrCast(new_ptr))[0..copy_size], @as([*]const u8, @ptrCast(ptr.?))[0..copy_size]);
    free(ptr);
    return new_ptr;
}

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
    const C = struct {
        extern fn sysconf(name: c_int) c_long;
    };
    return C.sysconf(name);
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
