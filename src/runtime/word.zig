const std = @import("std");

pub const Word = c_long;
pub const Unicode = c_ulong;

pub const CMBASE: Word = 306;

// Sentinel values and limits
pub const NIL: Word = CMBASE + 138;
pub const NILS: Word = CMBASE + 139;
pub const UNDEF: Word = CMBASE + 140;
pub const ATOMLIMIT: Word = CMBASE + 141;
pub const OFFSIDE: Word = 270;

pub const VALUE: Word = 257;
pub const EVAL: Word = 258;
pub const WHERE: Word = 259;
pub const IF: Word = 260;
pub const TO: Word = 261;
pub const LEFTARROW: Word = 262;
pub const COLONCOLON: Word = 263;
pub const COLON2EQ: Word = 264;
pub const TYPEVAR: Word = 265;
pub const NAME: Word = 266;
pub const CNAME: Word = 267;
pub const CONST: Word = 268;
pub const DOLLARS: Word = 269;
pub const ELSEQ: Word = 271;
pub const ABSTYPE: Word = 272;
pub const WITH: Word = 273;
pub const DIAG: Word = 274;
pub const EQEQ: Word = 275;
pub const FREE: Word = 276;
pub const INCLUDE: Word = 277;
pub const EXPORT: Word = 278;
pub const TYPE: Word = 279;
pub const OTHERWISE: Word = 280;
pub const SHOWSYM: Word = 281;
pub const PATHNAME: Word = 282;
pub const BNF: Word = 283;
pub const LEX: Word = 284;
pub const ENDIR: Word = 285;
pub const ERRORSY: Word = 286;
pub const ENDSY: Word = 287;
pub const EMPTYSY: Word = 288;
pub const READVALSY: Word = 289;
pub const LEXDEF: Word = 290;
pub const CHARCLASS: Word = 291;
pub const ANTICHARCLASS: Word = 292;
pub const LBEGIN: Word = 293;
pub const ARROW: Word = 294;
pub const PLUSPLUS: Word = 295;
pub const MINUSMINUS: Word = 296;
pub const DOTDOT: Word = 297;
pub const VEL: Word = 298;
pub const GE: Word = 299;
pub const NE: Word = 300;
pub const LE: Word = 301;
pub const REM: Word = 302;
pub const DIV: Word = 303;
pub const INFIXNAME: Word = 304;
pub const INFIXCNAME: Word = 305;

// Cell tags
pub const ATOM: Word = 0;
pub const DOUBLE: Word = 1;
pub const DATAPAIR: Word = 2;
pub const FILEINFO: Word = 3;
pub const TVAR: Word = 4;
pub const INT: Word = 5;
pub const CONSTRUCTOR: Word = 6;
pub const STRCONS: Word = 7;
pub const ID: Word = 8;
pub const AP: Word = 9;
pub const LAMBDA: Word = 10;
pub const CONS: Word = 11;
pub const TRIES: Word = 12;
pub const LABEL: Word = 13;
pub const SHOW: Word = 14;
pub const STARTREADVALS: Word = 15;
pub const LET: Word = 16;
pub const LETREC: Word = 17;
pub const SHARE: Word = 18;
pub const LEXER: Word = 19;
pub const PAIR: Word = 20;
pub const UNICODE: Word = 21;
pub const TCONS: Word = 22;

// Combinator codes
pub const S: Word = CMBASE + 0;
pub const K: Word = CMBASE + 1;
pub const Y: Word = CMBASE + 2;
pub const C: Word = CMBASE + 3;
pub const B: Word = CMBASE + 4;
pub const CB: Word = CMBASE + 5;
pub const I: Word = CMBASE + 6;
pub const HD: Word = CMBASE + 7;
pub const TL: Word = CMBASE + 8;
pub const BODY: Word = CMBASE + 9;
pub const LAST: Word = CMBASE + 10;
pub const S_p: Word = CMBASE + 11;
pub const U: Word = CMBASE + 12;
pub const Uf: Word = CMBASE + 13;
pub const U_: Word = CMBASE + 14;
pub const Ug: Word = CMBASE + 15;
pub const COND: Word = CMBASE + 16;
pub const EQ: Word = CMBASE + 17;
pub const NEQ: Word = CMBASE + 18;
pub const NEG: Word = CMBASE + 19;
pub const AND: Word = CMBASE + 20;
pub const OR: Word = CMBASE + 21;
pub const NOT: Word = CMBASE + 22;
pub const APPEND: Word = CMBASE + 23;
pub const STEP: Word = CMBASE + 24;
pub const STEPUNTIL: Word = CMBASE + 25;
pub const GENSEQ: Word = CMBASE + 26;
pub const MAP: Word = CMBASE + 27;
pub const ZIP: Word = CMBASE + 28;
pub const TAKE: Word = CMBASE + 29;
pub const DROP: Word = CMBASE + 30;
pub const FLATMAP: Word = CMBASE + 31;
pub const FILTER: Word = CMBASE + 32;
pub const FOLDL: Word = CMBASE + 33;
pub const MERGE: Word = CMBASE + 34;
pub const FOLDL1: Word = CMBASE + 35;
pub const LIST_LAST: Word = CMBASE + 36;
pub const FOLDR: Word = CMBASE + 37;
pub const MATCH: Word = CMBASE + 38;
pub const MATCHINT: Word = CMBASE + 39;
pub const TRY: Word = CMBASE + 40;
pub const SUBSCRIPT: Word = CMBASE + 41;
pub const ATLEAST: Word = CMBASE + 42;
pub const P: Word = CMBASE + 43;
pub const B_p: Word = CMBASE + 44;
pub const C_p: Word = CMBASE + 45;
pub const S1: Word = CMBASE + 46;
pub const B1: Word = CMBASE + 47;
pub const C1: Word = CMBASE + 48;
pub const ITERATE: Word = CMBASE + 49;
pub const ITERATE1: Word = CMBASE + 50;
pub const SEQ: Word = CMBASE + 51;
pub const FORCE: Word = CMBASE + 52;
pub const MINUS: Word = CMBASE + 53;
pub const PLUS: Word = CMBASE + 54;
pub const TIMES: Word = CMBASE + 55;
pub const INTDIV: Word = CMBASE + 56;
pub const FDIV: Word = CMBASE + 57;
pub const MOD: Word = CMBASE + 58;
pub const GR: Word = CMBASE + 59;
pub const GRE: Word = CMBASE + 60;
pub const POWER: Word = CMBASE + 61;
pub const CODE: Word = CMBASE + 62;
pub const DECODE: Word = CMBASE + 63;
pub const LENGTH: Word = CMBASE + 64;
pub const ARCTAN_FN: Word = CMBASE + 65;
pub const EXP_FN: Word = CMBASE + 66;
pub const ENTIER_FN: Word = CMBASE + 67;
pub const LOG_FN: Word = CMBASE + 68;
pub const LOG10_FN: Word = CMBASE + 69;
pub const SIN_FN: Word = CMBASE + 70;
pub const COS_FN: Word = CMBASE + 71;
pub const SQRT_FN: Word = CMBASE + 72;
pub const FILEMODE: Word = CMBASE + 73;
pub const FILESTAT: Word = CMBASE + 74;
pub const GETENV: Word = CMBASE + 75;
pub const EXEC: Word = CMBASE + 76;
pub const WAIT: Word = CMBASE + 77;
pub const INTEGER: Word = CMBASE + 78;
pub const SHOWNUM: Word = CMBASE + 79;
pub const SHOWHEX: Word = CMBASE + 80;
pub const SHOWOCT: Word = CMBASE + 81;
pub const SHOWSCALED: Word = CMBASE + 82;
pub const SHOWFLOAT: Word = CMBASE + 83;
pub const NUMVAL: Word = CMBASE + 84;
pub const STARTREAD: Word = CMBASE + 85;
pub const STARTREADBIN: Word = CMBASE + 86;
pub const NB_STARTREAD: Word = CMBASE + 87;
pub const READVALS: Word = CMBASE + 88;
pub const NB_READ: Word = CMBASE + 89;
pub const READ: Word = CMBASE + 90;
pub const READBIN: Word = CMBASE + 91;
pub const GETARGS: Word = CMBASE + 92;
pub const Ush: Word = CMBASE + 93;
pub const Ush1: Word = CMBASE + 94;
pub const KI: Word = CMBASE + 95;
pub const G_ERROR: Word = CMBASE + 96;
pub const G_ALT: Word = CMBASE + 97;
pub const G_OPT: Word = CMBASE + 98;
pub const G_STAR: Word = CMBASE + 99;
pub const G_FBSTAR: Word = CMBASE + 100;
pub const G_SYMB: Word = CMBASE + 101;
pub const G_ANY: Word = CMBASE + 102;
pub const G_SUCHTHAT: Word = CMBASE + 103;
pub const G_END: Word = CMBASE + 104;
pub const G_STATE: Word = CMBASE + 105;
pub const G_SEQ: Word = CMBASE + 106;
pub const G_RULE: Word = CMBASE + 107;
pub const G_UNIT: Word = CMBASE + 108;
pub const G_ZERO: Word = CMBASE + 109;
pub const G_CLOSE: Word = CMBASE + 110;
pub const G_COUNT: Word = CMBASE + 111;
pub const LEX_RPT: Word = CMBASE + 112;
pub const LEX_RPT1: Word = CMBASE + 113;
pub const LEX_TRY: Word = CMBASE + 114;
pub const LEX_TRY_: Word = CMBASE + 115;
pub const LEX_TRY1: Word = CMBASE + 116;
pub const LEX_TRY1_: Word = CMBASE + 117;
pub const DESTREV: Word = CMBASE + 118;
pub const LEX_COUNT: Word = CMBASE + 119;
pub const LEX_COUNT0: Word = CMBASE + 120;
pub const LEX_FAIL: Word = CMBASE + 121;
pub const LEX_STRING: Word = CMBASE + 122;
pub const LEX_CLASS: Word = CMBASE + 123;
pub const LEX_CHAR: Word = CMBASE + 124;
pub const LEX_DOT: Word = CMBASE + 125;
pub const LEX_SEQ: Word = CMBASE + 126;
pub const LEX_OR: Word = CMBASE + 127;
pub const LEX_RCONTEXT: Word = CMBASE + 128;
pub const LEX_STAR: Word = CMBASE + 129;
pub const LEX_OPT: Word = CMBASE + 130;
pub const MKSTRICT: Word = CMBASE + 131;
pub const BADCASE: Word = CMBASE + 132;
pub const CONFERROR: Word = CMBASE + 133;
pub const ERROR: Word = CMBASE + 134;
pub const FAIL: Word = CMBASE + 135;
pub const False: Word = CMBASE + 136;
pub const True: Word = CMBASE + 137;

// Useful representation of types
pub const undef_t: Word = 0;
pub const bool_t: Word = 1;
pub const num_t: Word = 2;
pub const char_t: Word = 3;
pub const list_t: Word = 4;
pub const comma_t: Word = 5;
pub const arrow_t: Word = 6;
pub const void_t: Word = 7;
pub const wrong_t: Word = 8;
pub const bind_t: Word = 9;
pub const type_t: Word = 10;
pub const strict_t: Word = 11;
pub const alias_t: Word = 12;
pub const new_t: Word = 13;

pub const synonym_t: Word = 1;
pub const algebraic_t: Word = 2;
pub const abstract_t: Word = 3;
pub const free_t: Word = 4;
pub const placeholder_t: Word = 5;

// Compiler and Reducer Action constants
pub const ACT_NONE: Word = 0;
pub const ACT_NEXTREDEX: Word = 1;
pub const ACT_DONE: Word = 2;

pub const SIGNBIT: Word = 0x10000000;
pub const MAXDIGIT: Word = 0x7fff;
pub const UMAX: Word = 0x10ffff;
pub const XVERSION: Word = 83;

pub const XBASE: Word = ATOMLIMIT - 256;
pub const CHAR_X: Word = XBASE;
pub const SHORT_X: Word = XBASE + 1;
pub const INT_X: Word = XBASE + 2;
pub const DBL_X: Word = XBASE + 3;
pub const ID_X: Word = XBASE + 4;
pub const AKA_X: Word = XBASE + 5;
pub const HERE_X: Word = XBASE + 6;
pub const CONSTRUCT_X: Word = XBASE + 7;
pub const RV_X: Word = XBASE + 8;
pub const PN_X: Word = XBASE + 9;
pub const PN1_X: Word = XBASE + 10;
pub const DEF_X: Word = XBASE + 11;
pub const AP_X: Word = XBASE + 12;
pub const CONS_X: Word = XBASE + 13;
pub const TVAR_X: Word = XBASE + 14;
pub const UNICODE_X: Word = XBASE + 15;


pub const FILE = struct {
    file: std.Io.File = .{ .handle = -1, .flags = .{ .nonblocking = false } },
    pushback: ?u8 = null,
    mem_buf: ?[]const u8 = null,
    mem_pos: usize = 0,
    buf: [8192]u8 = undefined,
    buf_start: usize = 0,
    buf_end: usize = 0,

    pub fn readByte(self: *FILE) !u8 {
        if (self.pushback) |pb| {
            self.pushback = null;
            return pb;
        }
        if (self.mem_buf) |buf| {
            if (self.mem_pos < buf.len) {
                const b = buf[self.mem_pos];
                self.mem_pos += 1;
                return b;
            }
            return error.EndOfStream;
        }
        if (self.buf_start >= self.buf_end) {
            const n = try std.posix.read(self.file.handle, &self.buf);
            if (n == 0) return error.EndOfStream;
            self.buf_start = 0;
            self.buf_end = n;
        }
        const b = self.buf[self.buf_start];
        self.buf_start += 1;
        return b;
    }

    pub fn ungetc(self: *FILE, c: u8) void {
        self.pushback = c;
    }

    pub fn writeByte(self: *FILE, c: u8) !void {
        const buf = [1]u8{c};
        const rc = std.posix.system.write(self.file.handle, &buf, 1);
        if (rc < 0) return error.WriteFailed;
    }

    pub fn writeAll(self: *FILE, slice: []const u8) !void {
        var written: usize = 0;
        while (written < slice.len) {
            const rc = std.posix.system.write(self.file.handle, slice[written..].ptr, slice.len - written);
            if (rc < 0) return error.WriteFailed;
            written += @intCast(rc);
        }
    }

    pub fn writeByteNTimes(self: *FILE, c: u8, count: usize) !void {
        var i: usize = 0;
        while (i < count) : (i += 1) {
            try self.writeByte(c);
        }
    }

    /// Zig-native formatted write to this file (R1.4): the file analogue of
    /// `word.print`/`printErr`. Formats to a stack buffer and writes using
    /// writeAll to maintain correct streaming file offsets.
    pub fn print(self: *FILE, comptime fmt: []const u8, args: anytype) void {
        var buf: [4096]u8 = undefined;
        const fs = std.meta.fields(@TypeOf(args));
        const slice = if (comptime (fs.len == 1 and @typeInfo(fs[0].type) == .@"struct"))
            std.fmt.bufPrint(&buf, fmt, @field(args, fs[0].name)) catch return
        else
            std.fmt.bufPrint(&buf, fmt, args) catch return;
        self.writeAll(slice) catch {};
    }
};

pub fn castToCStr(val: anytype) ?[*:0]const u8 {
    const T = @TypeOf(val);
    if (T == @TypeOf(null)) return null;
    if (@typeInfo(T) == .optional) {
        if (val) |v| {
            return @ptrCast(v);
        } else {
            return null;
        }
    }
    return @ptrCast(val);
}

pub fn castToCStrMut(val: anytype) ?[*:0]u8 {
    const T = @TypeOf(val);
    if (T == @TypeOf(null)) return null;
    if (@typeInfo(T) == .optional) {
        if (val) |v| {
            return @ptrCast(v);
        } else {
            return null;
        }
    }
    return @ptrCast(val);
}

pub fn strcpy(dst_any: anytype, src_any: anytype) ?[*:0]u8 {
    const dst = castToCStrMut(dst_any);
    const src = castToCStr(src_any);
    if (dst == null or src == null) return dst;
    const d = dst.?;
    const s = src.?;
    const src_len = std.mem.span(s).len;
    @memcpy(d[0..src_len], s[0..src_len]);
    d[src_len] = 0;
    return dst;
}

pub fn strcat(dst_any: anytype, src_any: anytype) ?[*:0]u8 {
    const dst = castToCStrMut(dst_any);
    const src = castToCStr(src_any);
    if (dst == null or src == null) return dst;
    const d = dst.?;
    const s = src.?;
    const dst_len = std.mem.span(d).len;
    const src_len = std.mem.span(s).len;
    @memcpy(d[dst_len .. dst_len + src_len], s[0..src_len]);
    d[dst_len + src_len] = 0;
    return dst;
}

pub fn strlen(s_any: anytype) usize {
    const s = castToCStr(s_any);
    if (s == null) return 0;
    return std.mem.span(s.?).len;
}

pub fn strcmp(s1_any: anytype, s2_any: anytype) c_int {
    const s1 = castToCStr(s1_any);
    const s2 = castToCStr(s2_any);
    if (s1 == null or s2 == null) return 0;
    const span1 = std.mem.span(s1.?);
    const span2 = std.mem.span(s2.?);
    const order = std.mem.order(u8, span1, span2);
    return switch (order) {
        .lt => -1,
        .eq => 0,
        .gt => 1,
    };
}

pub fn strncmp(s1_any: anytype, s2_any: anytype, n: usize) c_int {
    const s1 = castToCStr(s1_any);
    const s2 = castToCStr(s2_any);
    if (s1 == null or s2 == null) return 0;
    const span1 = std.mem.span(s1.?);
    const span2 = std.mem.span(s2.?);
    const sa = span1[0..@min(span1.len, n)];
    const sb = span2[0..@min(span2.len, n)];
    const order = std.mem.order(u8, sa, sb);
    return switch (order) {
        .lt => -1,
        .eq => 0,
        .gt => 1,
    };
}

pub fn strncpy(dst_any: anytype, src_any: anytype, n: usize) ?[*:0]u8 {
    const dst = castToCStrMut(dst_any);
    const src = castToCStr(src_any);
    if (dst == null or src == null) return dst;
    const d = dst.?;
    const s = src.?;
    const src_span = std.mem.span(s);
    const limit = @min(src_span.len, n);
    @memcpy(d[0..limit], src_span[0..limit]);
    if (limit < n) {
        @memset(d[limit..n], 0);
    }
    return dst;
}

pub fn strncat(dst_any: anytype, src_any: anytype, n: usize) ?[*:0]u8 {
    const dst = castToCStrMut(dst_any);
    const src = castToCStr(src_any);
    if (dst == null or src == null) return dst;
    const d = dst.?;
    const s = src.?;
    const dst_len = std.mem.span(d).len;
    const src_span = std.mem.span(s);
    const limit = @min(src_span.len, n);
    @memcpy(d[dst_len .. dst_len + limit], src_span[0..limit]);
    d[dst_len + limit] = 0;
    return dst;
}

pub fn strchr(s_any: anytype, char: c_int) ?[*:0]const u8 {
    const s = castToCStr(s_any);
    if (s == null) return null;
    const ptr = s.?;
    const span = std.mem.span(ptr);
    const ch: u8 = @intCast(char);
    for (span, 0..) |item, i| {
        if (item == ch) {
            return ptr + i;
        }
    }
    return null;
}

pub fn strrchr(s_any: anytype, char: c_int) ?[*:0]u8 {
    const s = castToCStr(s_any);
    if (s == null) return null;
    const ptr = @constCast(s.?);
    const span = std.mem.span(ptr);
    const ch: u8 = @intCast(char);
    var i = span.len;
    while (i > 0) {
        i -= 1;
        if (span[i] == ch) {
            return ptr + i;
        }
    }
    return null;
}

pub fn strstr(haystack_any: anytype, needle_any: anytype) ?[*:0]const u8 {
    const haystack = castToCStr(haystack_any);
    const needle = castToCStr(needle_any);
    if (haystack == null or needle == null) return null;
    const h_ptr = haystack.?;
    const n_ptr = needle.?;
    const h_span = std.mem.span(h_ptr);
    const n_span = std.mem.span(n_ptr);
    if (n_span.len == 0) return h_ptr;
    if (h_span.len < n_span.len) return null;
    const limit = h_span.len - n_span.len + 1;
    var i: usize = 0;
    while (i < limit) : (i += 1) {
        if (std.mem.eql(u8, h_span[i .. i + n_span.len], n_span)) {
            return h_ptr + i;
        }
    }
    return null;
}

pub fn rindex(s_any: anytype, char: c_int) ?[*:0]u8 {
    return strrchr(s_any, char);
}

pub var stdout_buf: [8192]u8 = undefined;
pub var stderr_buf: [8192]u8 = undefined;
pub var stdout_writer: std.Io.File.Writer = undefined;
pub var stderr_writer: std.Io.File.Writer = undefined;
pub var writers_initialized: bool = false;

pub fn initWriters() void {
    if (writers_initialized) return;
    const io = std.Options.debug_io;
    stdout_writer = std.Io.File.stdout().writer(io, &stdout_buf);
    stderr_writer = std.Io.File.stderr().writer(io, &stderr_buf);
    writers_initialized = true;
}

// The Zig-native printers below tolerate a double-wrapped arg tuple
// `.{.{a,b}}` (the convention inherited from the C-format shim) by unwrapping
// when the single field is itself a tuple. Scalar/string args like `.{x}` pass
// through untouched, so existing single-brace call sites are unaffected. This
// lets call sites be converted from `printf`/`fprintf` by translating only the
// format string, leaving the arg tuple as-is (R1.4 polish).
pub fn print(comptime fmt: []const u8, args: anytype) void {
    initWriters();
    const fs = std.meta.fields(@TypeOf(args));
    if (comptime (fs.len == 1 and @typeInfo(fs[0].type) == .@"struct")) {
        stdout_writer.interface.print(fmt, @field(args, fs[0].name)) catch {};
    } else {
        stdout_writer.interface.print(fmt, args) catch {};
    }
    stdout_writer.interface.flush() catch {};
}

pub fn printErr(comptime fmt: []const u8, args: anytype) void {
    initWriters();
    const fs = std.meta.fields(@TypeOf(args));
    if (comptime (fs.len == 1 and @typeInfo(fs[0].type) == .@"struct")) {
        stderr_writer.interface.print(fmt, @field(args, fs[0].name)) catch {};
    } else {
        stderr_writer.interface.print(fmt, args) catch {};
    }
    stderr_writer.interface.flush() catch {};
}

/// Zig-native formatted write to an optional file (the `fprintf` analogue):
/// a no-op when `file` is null, matching the old shim's behaviour. Lets
/// file-targeted call sites convert without sprinkling `.?`.
pub fn fprint(file: ?*FILE, comptime fmt: []const u8, args: anytype) void {
    if (file) |f| f.print(fmt, args);
}

pub fn flush() void {
    if (writers_initialized) {
        stdout_writer.interface.flush() catch {};
        stderr_writer.interface.flush() catch {};
    }
}

// ── C-style formatted output (R1.4) ─────────────────────────────────────────
// Moved here from main_clib.zig so call sites can use `word.printf`/`fprintf`/
// `putc`/`putchar` directly and the `clib` shim can eventually be deleted.
// Output is unbuffered (FILE.writeByte/writeAll do direct syscalls), matching
// the previous `clib` behaviour byte-for-byte.

// stdio: std streams, FILE pool, and C-style file ops (R1.5/R1.6 consolidation).
// The whole stdio subsystem lives next to the FILE struct; main_clib.zig
// re-exports these. fread/fwrite preserve the dump (.x) byte format.
pub var std_in = FILE{ .file = .{ .handle = std.posix.STDIN_FILENO, .flags = .{ .nonblocking = false } } };
pub var std_out = FILE{ .file = .{ .handle = std.posix.STDOUT_FILENO, .flags = .{ .nonblocking = false } } };
pub var std_err = FILE{ .file = .{ .handle = std.posix.STDERR_FILENO, .flags = .{ .nonblocking = false } } };

pub fn stdin() ?*FILE {
    return &std_in;
}
pub fn stdout() ?*FILE {
    return &std_out;
}
pub fn stderr() ?*FILE {
    return &std_err;
}

var file_pool: [16]FILE = undefined;
var file_in_use = [_]bool{false} ** 16;

fn allocFile() ?*FILE {
    for (&file_in_use, 0..) |*in_use, idx| {
        if (!in_use.*) {
            in_use.* = true;
            file_pool[idx] = FILE{ .file = .{ .handle = -1, .flags = .{ .nonblocking = false } } };
            return &file_pool[idx];
        }
    }
    return null;
}

fn freeFile(f: *FILE) void {
    const ptr_val = @intFromPtr(f);
    const pool_start = @intFromPtr(&file_pool[0]);
    const pool_end = @as(usize, @intCast(pool_start + @sizeOf(FILE) * 16));
    if (ptr_val >= pool_start and ptr_val < pool_end) {
        const idx = (ptr_val - pool_start) / @sizeOf(FILE);
        file_in_use[idx] = false;
    }
}

pub fn fopen(path: ?*const anyopaque, mode: [*:0]const u8) ?*FILE {
    if (path == null) return null;
    const path_str = @as([*:0]const u8, @ptrCast(path.?));
    const mode_slice = std.mem.span(mode);

    var for_read = false;
    var for_write = false;
    var for_append = false;
    for (mode_slice) |mc| {
        if (mc == 'r') for_read = true;
        if (mc == 'w') for_write = true;
        if (mc == 'a') for_append = true;
    }

    const io = std.Options.debug_io;
    const dir = std.Io.Dir.cwd();

    const file = if (for_read)
        dir.openFile(io, std.mem.span(path_str), .{}) catch return null
    else if (for_write)
        dir.createFile(io, std.mem.span(path_str), .{}) catch return null
    else if (for_append) d: {
        const f = dir.createFile(io, std.mem.span(path_str), .{ .truncate = false }) catch return null;
        _ = std.posix.system.lseek(f.handle, 0, 2);
        break :d f;
    } else
        return null;

    const f_ptr = allocFile() orelse {
        file.close(io);
        return null;
    };
    f_ptr.file = file;
    f_ptr.pushback = null;
    f_ptr.mem_buf = null;
    f_ptr.mem_pos = 0;
    f_ptr.buf_start = 0;
    f_ptr.buf_end = 0;
    return f_ptr;
}

pub fn fclose(file: ?*FILE) c_int {
    if (file) |f| {
        if (f == &std_in or f == &std_out or f == &std_err) {
            return 0;
        }
        if (f.file.handle >= 0) {
            const io = std.Options.debug_io;
            f.file.close(io);
            f.file.handle = -1;
        }
        freeFile(f);
        return 0;
    }
    return -1;
}

pub fn fileno(file: ?*FILE) c_int {
    if (file) |f| return f.file.handle;
    return -1;
}

pub fn setbuf(file: ?*FILE, buf: ?[*]u8) void {
    _ = file;
    _ = buf;
}

pub fn getc(file: ?*FILE) c_int {
    const f = file orelse return -1;
    const byte = f.readByte() catch return -1;
    return @as(c_int, byte);
}

pub fn getchar() c_int {
    return getc(&std_in);
}

pub fn ungetc(ch: c_int, file: ?*FILE) c_int {
    const f = file orelse return -1;
    if (ch == -1) return -1;
    f.ungetc(@intCast(@as(u8, @intCast(ch))));
    return ch;
}

pub fn fgets(buf: [*]u8, size: c_int, file: ?*FILE) ?[*]u8 {
    const f = file orelse return null;
    if (size <= 1) return null;
    var i: usize = 0;
    const limit = @as(usize, @intCast(size - 1));
    while (i < limit) {
        const c_val = getc(f);
        if (c_val == -1) {
            if (i == 0) return null;
            break;
        }
        buf[i] = @intCast(@as(u8, @intCast(c_val)));
        i += 1;
        if (c_val == '\n') {
            break;
        }
    }
    buf[i] = 0;
    return buf;
}

pub fn fread(ptr: ?*anyopaque, size: usize, nmemb: usize, file: ?*FILE) usize {
    const f = file orelse return 0;
    if (ptr == null or size == 0 or nmemb == 0) return 0;
    const buf = @as([*]u8, @ptrCast(ptr.?));
    const total_bytes = size * nmemb;
    var i: usize = 0;
    while (i < total_bytes) : (i += 1) {
        const byte = f.readByte() catch break;
        buf[i] = byte;
    }
    return i / size;
}

pub fn fwrite(ptr: ?*const anyopaque, size: usize, nmemb: usize, file: ?*FILE) usize {
    const f = file orelse return 0;
    if (ptr == null or size == 0 or nmemb == 0) return 0;
    const buf = @as([*]const u8, @ptrCast(ptr.?));
    const total_bytes = size * nmemb;
    var i: usize = 0;
    while (i < total_bytes) : (i += 1) {
        f.writeByte(buf[i]) catch break;
    }
    return i / size;
}

pub fn fdopen(fd: c_int, mode: [*:0]const u8) ?*FILE {
    _ = mode;
    const f_ptr = allocFile() orelse return null;
    f_ptr.file = .{ .handle = fd, .flags = .{ .nonblocking = false } };
    f_ptr.pushback = null;
    f_ptr.mem_buf = null;
    f_ptr.mem_pos = 0;
    return f_ptr;
}

pub fn fmemopen(buf: ?*anyopaque, size: usize, mode: [*:0]const u8) ?*FILE {
    _ = mode;
    if (buf == null) return null;
    const f_ptr = allocFile() orelse return null;
    f_ptr.file = .{ .handle = -1, .flags = .{ .nonblocking = false } };
    f_ptr.pushback = null;
    f_ptr.mem_buf = @as([*]const u8, @ptrCast(buf.?))[0..size];
    f_ptr.mem_pos = 0;
    return f_ptr;
}

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
                const UInt = std.meta.Int(.unsigned, @typeInfo(T).int.bits);
                str = try std.fmt.bufPrint(&buf, "{d}", .{@as(UInt, @bitCast(val))});
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

pub fn printf(format: [*:0]const u8, args: anytype) c_int {
    return fprintf(&std_out, format, args);
}

pub fn putc(ch: c_int, file: ?*FILE) c_int {
    const f = file orelse return -1;
    f.writeByte(@intCast(@as(u8, @intCast(ch)))) catch return -1;
    return ch;
}

pub fn fputc(ch: c_int, file: ?*FILE) c_int {
    return putc(ch, file);
}

pub fn putchar(ch: c_int) c_int {
    return putc(ch, &std_out);
}

pub inline fn isspace(ch: anytype) bool {
    const val: i64 = @intCast(ch);
    return val >= 0 and val <= 255 and std.ascii.isWhitespace(@intCast(val));
}
pub inline fn isdigit(ch: anytype) bool {
    const val: i64 = @intCast(ch);
    return val >= 0 and val <= 255 and std.ascii.isDigit(@intCast(val));
}
pub inline fn isxdigit(ch: anytype) bool {
    const val: i64 = @intCast(ch);
    return val >= 0 and val <= 255 and std.ascii.isHex(@intCast(val));
}
pub inline fn isalpha(ch: anytype) bool {
    const val: i64 = @intCast(ch);
    return val >= 0 and val <= 255 and std.ascii.isAlphabetic(@intCast(val));
}
pub inline fn isalnum(ch: anytype) bool {
    const val: i64 = @intCast(ch);
    return val >= 0 and val <= 255 and std.ascii.isAlphanumeric(@intCast(val));
}
pub inline fn tolower(ch: anytype) u8 {
    const val: i64 = @intCast(ch);
    if (val < 0 or val > 255) return 0;
    return std.ascii.toLower(@intCast(val));
}

test "string helpers strcpy and strcat" {
    var buf1: [32:0]u8 = undefined;
    _ = strcpy(&buf1, "hello");
    try std.testing.expectEqualSlices(u8, "hello", std.mem.span(@as([*:0]u8, &buf1)));
    
    _ = strcat(&buf1, " world");
    try std.testing.expectEqualSlices(u8, "hello world", std.mem.span(@as([*:0]u8, &buf1)));
}


