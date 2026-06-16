const std = @import("std");
const word_consts = @import("runtime/word.zig");
const platform = @import("io/platform.zig");
const parser_api = @import("parser/parser_api.zig");

const c_raw = @cImport({
    @cInclude("sys/ioctl.h");
    @cInclude("unistd.h");
    @cInclude("sys/stat.h");
    @cInclude("fcntl.h");
    @cInclude("stdio.h");
    @cInclude("setjmp.h");
    @cInclude("sys/resource.h");
    @cInclude("sys/wait.h");
    @cInclude("float.h");
    @cInclude("data.h");
    @cInclude("signals.h");
    @cInclude("string.h");
    @cInclude("stdlib.h");
    @cInclude("ctype.h");
    @cInclude("lex.h");
    @cInclude("version.h");
});

const clib = c_raw;

inline fn get_id(x: Word) [*:0]const u8 {
    return @ptrFromInt(@as(usize, @intCast(h(h(h(x))))));
}

inline fn get_fil(fil: Word) ?[*:0]const u8 {
    const val = h(h(h(fil)));
    if (val == 0) return null;
    return @ptrFromInt(@as(usize, @intCast(val)));
}

const Word = c_long;
const CONS = word_consts.CONS;
const AP = word_consts.AP;
const CMBASE = word_consts.CMBASE;
const NIL = word_consts.NIL;
const ATOMLIMIT = word_consts.ATOMLIMIT;
const UNDEF = word_consts.UNDEF;
const ID = word_consts.ID;
const CONSTRUCTOR = word_consts.CONSTRUCTOR;
const wrong_t = word_consts.wrong_t;
const free_t = word_consts.free_t;
const type_t = word_consts.type_t;
const undef_t = word_consts.undef_t;
const EVAL = word_consts.EVAL;
const FREE = word_consts.FREE;
const VALUE = word_consts.VALUE;
const BUFSIZE = word_consts.BUFSIZE;
const pnlim: usize = @intCast(word_consts.pnlim);
const abstract_t = word_consts.abstract_t;
const algebraic_t = word_consts.algebraic_t;
const placeholder_t = word_consts.placeholder_t;
const synonym_t = word_consts.synonym_t;
const PLUS = word_consts.PLUS;
const FILEINFO = word_consts.FILEINFO;
const XVERSION = word_consts.XVERSION;

extern var hd: [*]Word;
extern var tl: [*]Word;
extern var tag: [*]u8;

extern var s_out: ?*clib.FILE;
extern var dstack: ?[*]Word;
extern var stackp: ?[*]Word;

extern var dicp: [*:0]u8;
extern var dicq: [*:0]u8;
extern var dic: ?[*]u8;

extern var version: c_int;
extern var vdate: [*:0]const u8;
extern var host: [*:0]const u8;

extern var blankerr: c_int;
extern var ARGC: c_int;
extern var ARGV: [*]?[*:0]u8;

extern var current_id: Word;
extern var ATNAMES: Word;
extern var lineptr: Word;

extern var lfrule: c_int;
extern fn make(t: u8, x: Word, y: Word) Word;
extern fn sto_dbl(d: f64) Word;

// Global variables exported to C
export var nill: Word = 0;
export var Void: Word = 0;
var main_id: Word = 0;
export var message: Word = 0;
export var standardout: Word = 0;
export var diagonalise: Word = 0;
export var concat: Word = 0;
export var indent_fn: Word = 0;
export var outdent_fn: Word = 0;
export var listdiff_fn: Word = 0;
export var shownum1: Word = 0;
export var showbool: Word = 0;
export var showchar: Word = 0;
export var showlist: Word = 0;
export var showstring: Word = 0;
export var showparen: Word = 0;
export var showpair: Word = 0;
export var showvoid: Word = 0;
export var showfunction: Word = 0;
export var showabstract: Word = 0;
export var showwhat: Word = 0;

var PRELUDE: [pnlim + 10]u8 = undefined;
var STDENV: [pnlim + 9]u8 = undefined;
var vstack: [4]c_int = undefined;
var mstack: [4][*:0]const u8 = undefined;
var mvp: usize = 0;
var vbuf: [12]u8 = undefined;
export var loading: c_int = 0;
extern var BAD_DUMP: Word;
extern var CLASHES: Word;
extern var col: Word;
extern var DETROP: Word;
extern var MISSING: Word;
extern var ALIASES: Word;
extern var TSUPPRESSED: Word;
export var fnts: Word = NIL;

extern fn signals(signum: c_int, handler: usize) usize;

export var SPACELIMIT: Word = 2500000;
export var DICSPACE: Word = 100000;
export var UTF8: c_int = 0;
export var UTF8OUT: c_int = 0;
export var editor: ?[*:0]u8 = null;
var okprel: Word = 0;
var nostdenv: Word = 0;
export var baded: Word = 0;
export var miralib: ?[*:0]u8 = null;
var mirahdr: ?[*:0]u8 = null;
var lmirahdr: ?[*:0]u8 = null;
var promptstr: [*:0]const u8 = "Miranda ";
export var obsuffix: [*:0]const u8 = "x";
export var s_in: ?*clib.FILE = null;
export var commandmode: Word = 0;
var atobject: c_int = 0;
export var atgc: c_int = 0;
export var atcount: c_int = 0;
export var debug: c_int = 0;
export var magic: Word = 0;
var making: Word = 0;
var mkexports: Word = 0;
var mksources: Word = 0;
export var make_status: Word = 0;
export var compiling: c_int = 1;
export var ideep: c_int = 0;
export var SYNERR: Word = 0;
export var initialising: Word = 1;
export var primenv: Word = NIL;
export var current_script: ?[*:0]u8 = null;
export var lastexp: Word = UNDEF;
export var echoing: Word = 0;
export var listing: Word = 0;
export var verbosity: Word = 0;
export var strictif: Word = 1;
export var rechecking: Word = 0;
export var errline: Word = 0;
export var errs: Word = 0;
export var cstack: ?[*]Word = null;
export var linebuf: [BUFSIZE]u8 = undefined;
export var ebuf: [pnlim]u8 = undefined;
export var home_rc: [pnlim + 8]u8 = undefined;
export var lib_rc: [pnlim + 8]u8 = undefined;
export var rc_error: ?[*:0]const u8 = null;

var env: clib.sigjmp_buf = undefined;
var unlinkme: ?[*:0]const u8 = null;
var lose: c_int = 0;
export var sorted: c_int = 0;
var leftist: c_int = 0;
var words: [400]Word = undefined; // colmax is 400
export var detrop: Word = NIL;
export var rfl: Word = NIL;
export var bereaved: Word = 0;
export var ld_stuff: Word = NIL;
var sigflag: c_int = 0;
export var tlost: Word = NIL;
var pfrts: Word = NIL;

extern var namebucket: [128]Word;
extern var pnvec: ?[*]Word;
extern var TYPERRS: Word;
extern var FBS: Word;
extern var common_stdin: Word;
extern var common_stdinb: Word;
extern var cook_stdin: Word;
extern var c: Word;

extern var files: Word;
extern var current_file: Word;
extern var collecting: Word;
export var oldfiles: Word = NIL;
export var includees: Word = NIL;
export var freeids: Word = NIL;
export var exports: Word = NIL;
extern var exportfiles: Word;
export var embargoes: Word = NIL;
extern var newtyps: Word;
extern var SGC: Word;
extern var speclocs: Word;
extern var rv_script: Word;
extern var algshfns: Word;
extern var nextpn: Word;
export var internals: Word = NIL;
export var lastname: Word = 0;
export var suppressids: Word = NIL;
export var col_fn: Word = 0;
export var eprodnts: Word = NIL;
export var nonterminals: Word = NIL;
export var ntmap: Word = NIL;
export var ihlist: Word = 0;
export var ntspecmap: Word = NIL;
export var lexstates: Word = NIL;
export var lexdefs: Word = NIL;
extern var TABSTRS: Word;
extern var ND: Word;
extern var polyshowerror: c_int;
extern var fileq: Word;

extern fn setupheap() void;
extern fn tsetup() void;
extern fn reset_pns() void;
extern fn bigsetup() void;
extern fn resetgcstats() void;
extern fn reset_state() void;
extern fn reset_lex() void;
extern fn dic_check() void;
extern fn isconstrname(input: [*:0]const u8) c_int;



fn h(x: Word) Word {
    if (x < ATOMLIMIT) return 0;
    return hd[@as(usize, @intCast(x)) * 2];
}

fn t(x: Word) Word {
    if (x < ATOMLIMIT) return 0;
    return tl[@as(usize, @intCast(x)) * 2];
}

fn hp(x: Word) *Word {
    return &hd[@as(usize, @intCast(x)) * 2];
}

fn tp(x: Word) *Word {
    return &tl[@as(usize, @intCast(x)) * 2];
}

fn cons(x: Word, y: Word) Word {
    return make(CONS, x, y);
}

// Token names for out2(): replaces y.tab.c's yysterm[].
// Index i corresponds to lexical token (256 + i).
const yysterm_data = [_]?[*:0]const u8{
    null,             // 0: placeholder (no token 256)
    "VALUE",          // 1: 257
    "EVAL",           // 2: 258
    "where",          // 3: WHERE=259
    "if",             // 4: IF=260
    "&>",             // 5: 261
    "<-",             // 6: LEFTARROW=262
    "::",             // 7: COLONCOLON=263
    "::=",            // 8: COLON2EQ=264
    "TYPEVAR",        // 9: TYPEVAR=265
    "NAME",           // 10: NAME=266
    "CONSTRUCTOR-NAME", // 11: CNAME=267
    "CONST",          // 12: CONST=268
    "$$",             // 13: DOLLARS=269
    "OFFSIDE",        // 14: OFFSIDE=270
    "OFFSIDE =",      // 15: ELSEQ=271
    "abstype",        // 16: ABSTYPE=272
    "with",           // 17: WITH=273
    "//",             // 18: 274
    "==",             // 19: EQEQ=275
    "%free",          // 20: FREE=276
    "%include",       // 21: INCLUDE=277
    "%export",        // 22: EXPORT=278
    "type",           // 23: TYPE=279
    "otherwise",      // 24: OTHERWISE=280
    "show",           // 25: SHOWSYM=281
    "PATHNAME",       // 26: PATHNAME=282
    "%bnf",           // 27: BNF=283
    "%lex",           // 28: LEX=284
    "%%",             // 29: 285
    "error",          // 30: 286
    "end",            // 31: 287
    "empty",          // 32: 288
    "readvals",       // 33: READVALSY=289
    "NAME",           // 34: 290
    "`char-class`",   // 35: 291
    "`char-class`",   // 36: 292
    "%%begin",        // 37: 293
    "->",             // 38: ARROW=294
    "++",             // 39: PLUSPLUS=295
    "--",             // 40: MINUSMINUS=296
    "..",             // 41: DOTDOT=297
    "\\/",            // 42: VEL=298
    ">=",             // 43: GE=299
    "~=",             // 44: NE=300
    "<=",             // 45: LE=301
    "mod",            // 46: REM=302
    "div",            // 47: DIV=303
    "$NAME",          // 48: INFIXNAME=304
    "$CONSTRUCTOR",   // 49: INFIXCNAME=305
};
export var yysterm = yysterm_data;

// Equivalent of y.tab.c obey(): evaluate x without forking, no stats, no trailing newline.
export fn obey(x_in: Word) void {
    var x = x_in;
    const typ = clib.type_of(x);
    x = clib.codegen(x);
    if (polyshowerror != 0) return;
    compiling = 0;
    const list_t: Word = 4;
    const char_t: Word = 3;
    const islist = typ >= ATOMLIMIT and tag[@intCast(typ)] == AP and h(typ) == list_t;
    const out_val: Word = if (islist and t(typ) == message)
        x
    else blk: {
        const inner: Word = if (islist and t(typ) == char_t)
            x
        else
            make(AP, clib.mkshow(0, 0, typ), x);
        break :blk make(CONS, make(AP, standardout, inner), NIL);
    };
    clib.output(out_val);
}

// Equivalent of y.tab.c evaluate(): type-check, fork a child to reduce and print,
// then wait for the child in the parent.  The parent's heap/type state is preserved.
// Called from parser_api.parseCurrent() in command mode.
export fn evaluate_repl(x_in: Word) void {
    var x = x_in;
    const typ = clib.type_of(x);
    if (typ == wrong_t) return;
    lastexp = x;
    x = clib.codegen(x);
    if (polyshowerror != 0) return;
    const list_t: Word = 4;
    const char_t: Word = 3;
    // Build the output expression here in the parent so it's in the child's
    // address space after fork() (copy-on-write).
    const islist = typ >= ATOMLIMIT and tag[@intCast(typ)] == AP and h(typ) == list_t;
    const out_val: Word = if (islist and t(typ) == message)
        x
    else blk: {
        const inner: Word = if (islist and t(typ) == char_t)
            x
        else
            make(AP, clib.mkshow(0, 0, typ), x);
        break :blk make(CONS, make(AP, standardout, inner), NIL);
    };
    if (clib.process() != 0) {
        // Child: evaluate and print, then exit (compiling=0 only here, parent unaffected).
        _ = signals(clib.SIGINT, @intFromPtr(&dieclean));
        compiling = 0;
        resetgcstats();
        clib.output(out_val);
        _ = clib.putchar('\n');
        clib.outstats();
        clib.exit(0);
    }
    // Parent returns here; heap and compiling flag are unchanged.
}

fn getStdin_helper() ?*c_raw.FILE {
    const T = @TypeOf(c_raw.stdin);
    if (comptime @typeInfo(T) == .@"fn") {
        return c_raw.stdin();
    } else if (comptime @typeInfo(T) == .pointer and @typeInfo(@typeInfo(T).pointer.child) == .@"fn") {
        return c_raw.stdin();
    } else {
        return c_raw.stdin;
    }
}

fn getStdout_helper() ?*c_raw.FILE {
    const T = @TypeOf(c_raw.stdout);
    if (comptime @typeInfo(T) == .@"fn") {
        return c_raw.stdout();
    } else if (comptime @typeInfo(T) == .pointer and @typeInfo(@typeInfo(T).pointer.child) == .@"fn") {
        return c_raw.stdout();
    } else {
        return c_raw.stdout;
    }
}

fn getStderr_helper() ?*c_raw.FILE {
    const T = @TypeOf(c_raw.stderr);
    if (comptime @typeInfo(T) == .@"fn") {
        return c_raw.stderr();
    } else if (comptime @typeInfo(T) == .pointer and @typeInfo(@typeInfo(T).pointer.child) == .@"fn") {
        return c_raw.stderr();
    } else {
        return c_raw.stderr;
    }
}

inline fn getStdin() ?*c_raw.FILE {
    return getStdin_helper();
}
inline fn getStdout() ?*c_raw.FILE {
    return getStdout_helper();
}
inline fn getStderr() ?*c_raw.FILE {
    return getStderr_helper();
}

fn fil_time(fil: Word) Word {
    return t(h(h(fil)));
}

fn fil_share(fil: Word) Word {
    return h(t(h(fil)));
}

fn fil_inodev(fil: Word) Word {
    return t(t(h(fil)));
}

fn fil_defs(fil: Word) Word {
    return t(fil);
}

inline fn dval(d: Word) Word {
    return t(t(d));
}

inline fn dlhs(d: Word) Word {
    return h(d);
}

fn get_here(x: Word) Word {
    return clib.get_here(x);
}

fn the_val(x: Word) Word {
    return t(x);
}

fn t_class(x: Word) Word {
    return h(t(the_val(x)));
}

fn t_info(x: Word) Word {
    return t(t(the_val(x)));
}

fn id_val(x: Word) Word {
    return t(x);
}

fn id_type(x: Word) Word {
    return t(h(x));
}

fn id_who(x: Word) Word {
    return t(h(h(x)));
}

fn same_file(x: Word, y: Word) bool {
    const ix = fil_inodev(x);
    const iy = fil_inodev(y);
    return h(ix) == h(iy) and t(ix) == t(iy);
}

fn inodev(path: [*:0]const u8) Word {
    if (platform.getFileInfo(path)) |info| {
        return clib.datapair(info.ino, @as(Word, @bitCast(info.dev)));
    } else {
        return clib.datapair(0, -1);
    }
}

fn fileExists(path: [*:0]const u8) bool {
    return platform.getFileInfo(path) != null;
}

fn is(s: [*:0]const u8) bool {
    return std.mem.eql(u8, std.mem.span(dicp), std.mem.span(s));
}

fn badval(x: Word) bool {
    if (@sizeOf(Word) == 4) {
        return (x < 1 or x > 350000000);
    } else {
        return (x < 1 or x > 50000000000);
    }
}

fn isfreeid(x: Word) bool {
    return if (id_type(x) == type_t) t_class(x) == free_t else id_val(x) == FREE;
}

fn isconstructor(x: Word) bool {
    return tag[@intCast(x)] == ID and isconstrname(get_id(x)) != 0;
}

fn isvariable(x: Word) bool {
    return tag[@intCast(x)] == ID and isconstrname(get_id(x)) == 0;
}

fn token() ?[*:0]u8 {
    return clib.token();
}

fn rdline() ?[*:0]u8 {
    return clib.rdline();
}

fn make_fil(name: ?[*:0]const u8, time: Word, share: Word, defs: Word) Word {
    const name_word = @as(Word, @intCast(@intFromPtr(name)));
    const fil_info = make(FILEINFO, name_word, time);
    return cons(cons(fil_info, cons(share, NIL)), defs);
}

fn constructor(n: Word, x: anytype) Word {
    const x_val: Word = switch (@TypeOf(x)) {
        Word => x,
        c_int, c_uint => @intCast(x),
        [*:0]const u8, [*:0]u8 => @intCast(@intFromPtr(x)),
        else => @compileError("Unsupported type for constructor"),
    };
    return make(CONSTRUCTOR, n, x_val);
}

const EDITOR = "vi +!";

export fn fm_time(path: [*:0]const u8) Word {
    if (platform.getFileInfo(path)) |info| {
        return @intCast(info.mtime);
    } else {
        return 0;
    }
}

export fn normal(path: [*:0]const u8) c_int {
    const text = std.mem.span(path);
    return if (text.len >= 2 and std.mem.eql(u8, text[text.len - 2 ..], ".m")) 1 else 0;
}

export fn reverse(input: Word) Word {
    var x = input;
    var y: Word = NIL;
    while (x != NIL) {
        y = cons(h(x), y);
        x = t(x);
    }
    return y;
}

export fn shunt(input_x: Word, input_y: Word) Word {
    var x = input_x;
    var y = input_y;
    while (x != NIL) {
        y = cons(h(x), y);
        x = t(x);
    }
    return y;
}

export fn size(input: Word) Word {
    var x = input;
    var s: Word = 0;
    while (tag[@intCast(x)] == CONS or tag[@intCast(x)] == AP) {
        s += 1 + size(h(x));
        x = t(x);
    }
    return s;
}

export fn filecopy(path: [*:0]const u8) void {
    const fd = clib.open(path, clib.O_RDONLY);
    if (fd < 0) return;
    defer _ = clib.close(fd);

    var buffer: [512]u8 = undefined;
    while (true) {
        const n = clib.read(fd, &buffer, buffer.len);
        if (n <= 0) break;
        _ = clib.write(clib.STDOUT_FILENO, &buffer, @intCast(n));
    }
}

export fn filecp(from: [*:0]const u8, to: [*:0]const u8) void {
    const f_in = clib.open(from, clib.O_RDONLY);
    if (f_in < 0) return;
    defer _ = clib.close(f_in);

    const f_out = clib.open(to, clib.O_WRONLY | clib.O_CREAT | clib.O_TRUNC, @as(c_uint, 0o644));
    if (f_out < 0) return;
    defer _ = clib.close(f_out);

    var buffer: [512]u8 = undefined;
    while (true) {
        const n = clib.read(f_in, &buffer, buffer.len);
        if (n <= 0) break;
        _ = clib.write(f_out, &buffer, @intCast(n));
    }
}

export fn twidth() c_int {
    var window: clib.struct_winsize = undefined;
    if (clib.ioctl(clib.STDOUT_FILENO, clib.TIOCGWINSZ, &window) == -1 or window.ws_col == 0) {
        return 78;
    }
    return @as(c_int, @intCast(window.ws_col)) - 2;
}

export fn mktiny() Word {
    var x: f64 = 1.0;
    var x1: f64 = x / 2.0;
    while (x1 > 0.0) {
        x = x1;
        x1 = x1 / 2.0;
    }
    return sto_dbl(x);
}

export fn checkversion(m: [*:0]const u8) c_int {
    var path_buf: [1024]u8 = undefined;
    const path = std.fmt.bufPrintZ(&path_buf, "{s}/.version", .{m}) catch return 0;
    const f = clib.fopen(path.ptr, "r");
    var v1: c_uint = 0;
    var read_ok: bool = false;
    var r: c_int = 0;
    if (f != null) {
        if (clib.fscanf(f, "%u", &v1) == 1) {
            r = if (v1 == version) 1 else 0;
            read_ok = true;
        }
        _ = clib.fclose(f);
    }
    if (read_ok and r == 0) {
        if (mvp < 4) {
            mstack[mvp] = m;
            vstack[mvp] = @intCast(v1);
            mvp += 1;
        }
    }
    return r;
}

export fn libfails() void {
    const stderr = getStderr().?;
    _ = clib.fprintf(stderr, "found");
    var i: usize = 0;
    while (i < mvp) : (i += 1) {
        _ = clib.fprintf(stderr, "\tversion %s at: %s\n", strvers(vstack[i]), mstack[i]);
    }
}

export fn strvers(v: c_int) [*:0]const u8 {
    if (v < 0 or v > 999999) {
        return "???";
    }
    _ = clib.snprintf(&vbuf, vbuf.len, "%.3f", @as(f64, @floatFromInt(v)) / 1000.0);
    return @ptrCast(&vbuf);
}

export fn unlinkx(t_path: [*:0]const u8) void {
    var obf_buf: [1024]u8 = undefined;
    const t_slice = std.mem.span(t_path);
    if (t_slice.len == 0) return;
    const len = t_slice.len;
    
    @memcpy(obf_buf[0 .. len - 1], t_slice[0 .. len - 1]);
    
    const obsuffix_slice = std.mem.span(obsuffix);
    @memcpy(obf_buf[len - 1 .. len - 1 + obsuffix_slice.len], obsuffix_slice);
    obf_buf[len - 1 + obsuffix_slice.len] = 0;
    
    const obf = @as([*:0]const u8, @ptrCast(obf_buf[0..].ptr));
    if (fileExists(obf)) {
        _ = clib.unlink(obf);
    }
}

export fn unsetids(d_val: Word) void {
    var d = d_val;
    while (d != NIL) : (d = t(d)) {
        const item = h(d);
        if (tag[@intCast(item)] == ID) {
            tp(item).* = UNDEF;
            tp(h(h(item))).* = NIL;
            tp(h(item)).* = undef_t;
        }
    }
}

export fn unload() void {
    sorted = 0;
    speclocs = NIL;
    nextpn = 0;
    rv_script = 0;
    algshfns = NIL;
    unsetids(newtyps);
    newtyps = NIL;
    unsetids(freeids);
    freeids = NIL;
    includees = NIL;
    SGC = NIL;
    TABSTRS = NIL;
    ND = NIL;
    unsetids(internals);
    internals = NIL;
    while (files != NIL) : (files = t(files)) {
        const fil = h(files);
        unsetids(t(fil));
        tp(fil).* = NIL;
    }
    var ld = ld_stuff;
    while (ld != NIL) : (ld = t(ld)) {
        var x = h(ld);
        while (x != NIL) : (x = t(x)) {
            unsetids(t(h(x)));
        }
    }
    ld_stuff = NIL;
}

export fn getln(in: ?*clib.FILE, n_val: Word, s_ptr: [*]u8) c_int {
    var n = n_val;
    var s = s_ptr;
    while (n > 0) {
        n -= 1;
        const ch = clib.getc(in);
        s[0] = @intCast(ch);
        if (ch == '\n') break;
        if (ch == clib.EOF) {
            return 0;
        }
        s += 1;
    }
    if (s[0] != '\n' or n < 0) {
        return 0;
    }
    s[0] = 0;
    return 1;
}

export fn badeditor() c_int {
    const ed = editor orelse {
        baded = 1;
        return 1;
    };
    var p = clib.strchr(ed, '!');
    while (p != null) {
        const offset = @intFromPtr(p.?) - @intFromPtr(ed);
        if (offset > 0 and (p.? - 1)[0] == '\\') {
            p = clib.strchr(p.? + 1, '!');
        } else {
            break;
        }
    }
    baded = if (p == null) 1 else 0;
    return @intCast(baded);
}

export fn fixeditor() void {
    const ed = editor orelse return;
    if (clib.strcmp(ed, "vi") == 0) {
        editor = @constCast("vi +!");
    } else if (clib.strcmp(ed, "pico") == 0) {
        editor = @constCast("pico +!");
    } else if (clib.strcmp(ed, "nano") == 0) {
        editor = @constCast("nano +!");
    } else if (clib.strcmp(ed, "joe") == 0) {
        editor = @constCast("joe +!");
    } else if (clib.strcmp(ed, "jpico") == 0) {
        editor = @constCast("jpico +!");
    } else if (clib.strcmp(ed, "vim") == 0) {
        editor = @constCast("vim +!");
    } else if (clib.strcmp(ed, "gvim") == 0) {
        editor = @constCast("gvim +! % &");
    } else if (clib.strcmp(ed, "emacs") == 0) {
        editor = @constCast("emacs +! % &");
    } else {
        var p = clib.strrchr(ed, '/');
        if (p == null) {
            p = ed;
        } else {
            p = p.? + 1;
        }
        if (clib.strcmp(p.?, "vi") == 0) {
            _ = clib.strcat(p.?, " +!");
        }
    }
    if (clib.strrchr(editor.?, '&') != null) {
        rechecking = 2;
    }
    listing = @intCast(badeditor());
}

export fn rc_read(rcfile: [*:0]const u8) Word {
    var z: [20]u8 = undefined;
    var h_val: Word = 0;
    var d_val: Word = 0;
    var v_val: Word = 0;
    var s_val: Word = 0;
    var r: Word = 0;
    oldversion = version;
    const in = clib.fopen(rcfile, "r");
    if (in == null) return 0;
    defer _ = clib.fclose(in.?);

    if (clib.fscanf(in.?, "%19s", @as([*c]u8, @ptrCast(&z))) != 1) {
        return 0;
    }
    const z_slice = std.mem.span(@as([*:0]const u8, @ptrCast(&z)));
    if (std.mem.startsWith(u8, z_slice, "hdve") or std.mem.eql(u8, z_slice, "lhdve")) {
        var z1 = @as([*:0]u8, @ptrCast(&z)) + 3;
        if (z[0] == 'l') {
            listing = 1;
            z1 += 1;
        }
        // C original: while (*++z1) — pre-increment skips the 'e' in "hdve" before checking flags.
        z1 += 1;
        while (z1[0] != 0) : (z1 += 1) {
            if (z1[0] == 'l') {
                listing = 1;
            } else if (z1[0] == 's') {
                // ignore
            } else if (z1[0] == 'r') {
                rechecking = 2;
            } else {
                rc_error = rcfile;
            }
        }
        if (clib.fscanf(in.?, "%ld%ld%ld%*c", &h_val, &d_val, &v_val) != 3 or getln(in.?, pnlim - 1, @as([*]u8, @ptrCast(&ebuf))) == 0 or badval(h_val) or badval(d_val) or badval(v_val)) {
            rc_error = rcfile;
        } else {
            editor = @ptrCast(&ebuf);
            SPACELIMIT = h_val;
            DICSPACE = d_val;
            r = 1;
            oldversion = @intCast(v_val);
        }
    } else if (std.mem.eql(u8, z_slice, "ehdsv")) {
        if (clib.fscanf(in.?, "%19s%ld%ld%ld%ld", @as([*c]u8, @ptrCast(&ebuf)), &h_val, &d_val, &s_val, &v_val) != 5 or badval(h_val) or badval(d_val) or badval(v_val)) {
            rc_error = rcfile;
        } else {
            editor = @ptrCast(&ebuf);
            SPACELIMIT = h_val;
            DICSPACE = d_val;
            r = 1;
            oldversion = @intCast(v_val);
        }
    } else if (std.mem.eql(u8, z_slice, "ehds")) {
        if (clib.fscanf(in.?, "%s%ld%ld%ld", @as([*c]u8, @ptrCast(&ebuf)), &h_val, &d_val, &s_val) != 4 or badval(h_val) or badval(d_val)) {
            rc_error = rcfile;
        } else {
            editor = @ptrCast(&ebuf);
            SPACELIMIT = h_val;
            DICSPACE = d_val;
            r = 1;
            oldversion = 1;
        }
    } else {
        rc_error = rcfile;
    }
    if (editor != null) {
        fixeditor();
    }
    return r;
}

export fn rc_write() void {
    const out = clib.fopen(@ptrCast(&home_rc), "w");
    if (out == null) {
        const stderr = getStderr().?;
        _ = clib.fprintf(stderr, "warning: cannot write to \"%s\"\n", @as([*:0]const u8, @ptrCast(&home_rc)));
        return;
    }
    defer _ = clib.fclose(out.?);

    _ = clib.fprintf(out.?, "hdve");
    if (listing != 0) {
        _ = clib.fputc('l', out.?);
    }
    if (rechecking == 2) {
        _ = clib.fputc('r', out.?);
    }
    _ = clib.fprintf(out.?, " %ld %ld %d %s\n", SPACELIMIT, DICSPACE, version, editor orelse @constCast(""));
}

export var oldversion: c_int = 0;

fn announce() void {
    const w = @divTrunc(twidth() - 50, 2);
    _ = clib.printf("\n\n");
    spaces(w);
    _ = clib.printf("   T h e   M i r a n d a   S y s t e m\n\n");
    spaces(w + 5 - @divTrunc(@as(Word, @intCast(clib.strlen(vdate))), 2));
    _ = clib.printf("  version %s last revised %s\n\n", strvers(version), vdate);
    spaces(w);
    _ = clib.printf("Copyright Research Software Ltd 1985-2020\n\n");
    spaces(w);
    _ = clib.printf("  World Wide Web: http://miranda.org.uk\n\n\n");
    if (SPACELIMIT != 2500000) {
        _ = clib.printf("(%ld cells)\n", SPACELIMIT);
    }
    if (strictif == 0) {
        _ = clib.printf("(-nostrictif : deprecated!)\n");
    }
    if (oldversion < 1999) {
        _ = clib.printf("WARNING:\na new release of Miranda has been installed since you last used\nthe system - please read the `CHANGES' section of the /man pages !!!\n\n");
    } else if (version > oldversion) {
        _ = clib.printf("a new version of Miranda has been installed since you last\nused the system - see under `CHANGES' in the /man pages\n\n");
    }
    if (version < oldversion) {
        _ = clib.printf("warning - this is an older version of Miranda than the one\nyou last used on this machine!!\n\n");
    }
    if (rc_error) |rc_err| {
        _ = clib.printf("warning: \"%s\" contained bad data (ignored)\n", rc_err);
    }
}

export var lastid: Word = 0;
export var rv_expr: Word = 0;

export fn commandloop(initscript: [*:0]u8) void {
    var ch: c_int = undefined;
    var lb: ?[*:0]u8 = undefined;

    if (clib.sigsetjmp(&env, 1) == 0) {
        if (magic != 0) {
            undump(initscript);
            if (files == NIL or ND != NIL or id_val(main_id) == UNDEF) {
                if (files != NIL and ND == NIL and id_val(main_id) == UNDEF) {
                    _ = clib.fprintf(getStderr(), "%s: main not defined\n", initscript);
                }
                _ = clib.fprintf(getStderr(), "mira: incorrect use of \"-exec\" flag\n");
                clib.exit(1);
            }
            magic = 0;
            clib.obey(main_id);
            clib.exit(0);
        }
        _ = signals(clib.SIGINT, @intFromPtr(&reset));
        undump(initscript);
        if (verbosity != 0) {
            _ = clib.printf("for help type /h\n");
        }
    }

    while (true) {
        resetgcstats();
        if (verbosity != 0) {
            _ = clib.printf("%s", promptstr);
        }
        ch = clib.getchar();
        if (rechecking != 0 and src_update() != 0) {
            loadfile(current_script.?);
        }
        while (ch == ' ' or ch == '\t') {
            ch = clib.getchar();
        }
        switch (ch) {
            '?' => {
                ch = clib.getchar();
                if (ch == '?') {
                    var x: Word = undefined;
                    var aka: ?[*:0]u8 = null;
                    if (token() == null and lastid == 0) {
                        _ = clib.printf("\x07identifier needed after `??'\n");
                        ch = clib.getchar();
                        continue;
                    }
                    if (clib.getchar() != '\n') {
                        xschars();
                        continue;
                    }
                    if (baded != 0) {
                        ed_warn();
                        continue;
                    }
                    if (dicp[0] != 0) {
                        x = clib.findid(dicp);
                    } else {
                        _ = clib.printf("??%s\n", get_id(lastid));
                        x = lastid;
                    }
                    if (x == NIL or id_type(x) == undef_t) {
                        diagnose(if (dicp[0] != 0) dicp else get_id(lastid));
                        lastid = 0;
                        continue;
                    }
                    if (id_who(x) == NIL) {
                        _ = clib.printf("%s -- primitive to Miranda\n", if (dicp[0] != 0) dicp else get_id(lastid));
                        lastid = 0;
                        continue;
                    }
                    lastid = x;
                    x = id_who(x);
                    if (tag[@intCast(x)] == CONS) {
                        aka = @ptrFromInt(@as(usize, @intCast(h(h(x)))));
                        x = t(x);
                    }
                    if (aka != null) {
                        _ = clib.printf("originally defined as \"%s\"\n", aka.?);
                    }
                    editfile(@ptrFromInt(@as(usize, @intCast(h(x)))), @intCast(t(x)));
                } else {
                    _ = clib.ungetc(ch, getStdin().?);
                    _ = token();
                    lastid = 0;
                    if (dicp[0] == 0) {
                        if (clib.getchar() != '\n') {
                            xschars();
                        } else {
                            allnamescom();
                        }
                    } else {
                        while (dicp[0] != 0) {
                            finger(dicp);
                            _ = token();
                        }
                        ch = clib.getchar();
                    }
                }
            },
            ':', '/' => {
                _ = token();
                lastid = 0;
                command();
            },
            '!' => {
                lb = rdline();
                if (lb == null) continue;
                lastid = 0;
                if (lb.?[0] != 0) {
                    var shell: ?[*:0]const u8 = null;
                    var oldsig: usize = undefined;
                    var pid: c_int = undefined;
                    shell = clib.getenv("SHELL");
                    if (shell == null) {
                        shell = "/bin/sh";
                    }
                    oldsig = signals(clib.SIGINT, 1);
                    pid = clib.fork();
                    if (pid != 0) { // parent
                        if (pid == -1) {
                            clib.perror("UNIX error - cannot create process");
                        }
                        while (pid != clib.wait(null)) {}
                        _ = signals(clib.SIGINT, oldsig);
                    } else { // child
                        _ = clib.execl(shell.?, shell.?, "-c", lb.?, @as(?*anyopaque, null));
                    }
                    if (src_update() != 0) {
                        loadfile(current_script.?);
                    }
                } else {
                    _ = clib.printf("No previous shell command to substitute for \"!\"\n");
                }
            },
            '|' => {
                ch = clib.getchar();
                if (ch != '|') {
                    _ = clib.printf("\x07unknown command - type /h for help\n");
                }
                while (ch != '\n' and ch != clib.EOF) {
                    ch = clib.getchar();
                }
            },
            '\n' => {},
            clib.EOF => {
                if (verbosity != 0) {
                    _ = clib.printf("\nmiranda logout\n");
                }
                clib.exit(0);
            },
            else => {
                _ = clib.ungetc(ch, getStdin().?);
                lastid = 0;
                tp(h(cook_stdin)).* = 0;
                rv_expr = 0;
                c = EVAL;
                echoing = 0;
                polyshowerror = 0;
                commandmode = 1;
                _ = parser_api.parseCurrent() catch {};
                if (SYNERR != 0) {
                    SYNERR = 0;
                } else if (c != '\n') {
                    _ = clib.printf("syntax error\n");
                    while (c != '\n' and c != clib.EOF) {
                        c = clib.getchar();
                    }
                }
                commandmode = 0;
                echoing = verbosity & listing;
            }
        }
    }
}

export fn parseline(t_val: Word, f: ?*clib.FILE, fil: Word) Word {
    var t1: Word = undefined;
    var ch: c_int = undefined;
    lastexp = UNDEF;
    while (true) {
        ch = clib.getc(f);
        while (ch == ' ' or ch == '\t' or ch == '\n') {
            ch = clib.getc(f);
        }
        if (ch == '|') {
            ch = clib.getc(f);
            if (ch == '|') {
                ch = clib.getc(f);
                while (ch != '\n' and ch != clib.EOF) {
                    ch = clib.getc(f);
                }
                if (ch != clib.EOF) {
                    continue;
                }
            } else {
                _ = clib.ungetc(ch, f);
            }
        }
        if (ch == clib.EOF) {
            return clib.EOF;
        }
        _ = clib.ungetc(ch, f);
        c = VALUE;
        echoing = 0;
        commandmode = 1;
        s_in = f;
        _ = parser_api.parseCurrent() catch {};
        s_in = getStdin();
        if (SYNERR != 0) {
            SYNERR = 0;
            lastexp = UNDEF;
        } else {
            t1 = clib.type_of(lastexp);
            if (t1 == wrong_t) {
                lastexp = UNDEF;
            } else if (clib.subsumes(clib.instantiate(t1), t_val) == 0) {
                _ = clib.printf("data has wrong type :: ");
                clib.out_type(t1);
                _ = clib.printf("\nshould be :: ");
                clib.out_type(t_val);
                 _ = clib.putc('\n', getStdout());
                lastexp = UNDEF;
            }
        }
        if (lastexp != UNDEF) {
            return clib.codegen(lastexp);
        }
        if (clib.isatty(clib.fileno(f)) != 0) {
            _ = clib.printf("please re-enter data:\n");
        } else {
            if (fil != 0) {
                _ = clib.fprintf(getStderr(), "readvals: bad data in file \"%s\"\n", clib.getstring(fil, @constCast("")));
            } else {
                _ = clib.fprintf(getStderr(), "bad data in $+ input\n");
            }
            clib.outstats();
            clib.exit(1);
        }
    }
}

fn ed_warn() void {
    _ = clib.printf("The currently installed editor command, \"%s\", does not\ninclude a facility for opening a file at a specified line number.  As a\nresult the `??' command and certain other features of the Miranda system\nare disabled.  See manual section 31/5 on changing the editor for more\ninformation.\n", editor orelse @constCast(""));
}

fn src_update() c_int {
    var ft: Word = undefined;
    var f = if (files == NIL) oldfiles else files;
    while (f != NIL) {
        if ((fm_time(get_fil(h(f)).?)) != fil_time(h(f))) {
            ft = fm_time(get_fil(h(f)).?);
            if (ft == 0) {
                unlinkx(get_fil(h(f)).?);
            }
            return 1;
        }
        f = t(f);
    }
    return 0;
}

export fn reset() void {
    if (collecting != 0) {
        clib.gcpatch();
    }
    if (loading != 0) {
        if (blankerr == 0) {
            _ = clib.fprintf(getStderr(), "\n<<compilation interrupted>>\n");
        }
        if (unlinkme) |u| {
            _ = clib.unlink(u);
        }
        oldfiles = files;
        unload();
        current_id = 0;
        ATNAMES = 0;
        loading = 0;
        SYNERR = 0;
        lineptr = 0;
        if (blankerr != 0) {
            blankerr = 0;
            makedump();
        }
    } else {
        _ = clib.fprintf(getStderr(), "<<interrupt>>\n");
    }
    reset_state();
    if (collecting != 0) {
        collecting = 0;
        clib.gc();
    }
    if (making != 0 and make_status == 0) {
        make_status = 1;
    }
    clib.siglongjmp(&env, 1);
}

fn v_info(full: c_int) void {
    _ = clib.printf("%s last revised %s\n", strvers(version), vdate);
    if (full == 0) return;
    _ = clib.printf("%s", host);
    _ = clib.printf("XVERSION %u\n", @as(c_uint, XVERSION));
}

fn command() void {
    var t_val: ?[*:0]u8 = undefined;
    var ch: c_int = undefined;
    var ch1: c_int = undefined;
    switch (dicp[0]) {
        'a' => {
            if (is("a") or is("aux")) {
                if (clib.getchar() != '\n') return;
                _ = clib.strcpy(&linebuf, miralib.?);
                _ = clib.strcat(&linebuf, "/auxfile");
                filecopy(@as([*:0]const u8, @ptrCast(&linebuf)));
                return;
            }
        },
        'c' => {
            if (is("count")) {
                if (clib.getchar() != '\n') return;
                atcount = 1;
                return;
            }
            if (is("cd")) {
                var d = token();
                if (d == null) {
                    d = @constCast(clib.getenv("HOME"));
                } else {
                    d = clib.addextn(0, d.?);
                }
                if (clib.getchar() != '\n') return;
                if (clib.chdir(d.?) == -1) {
                    _ = clib.printf("cannot cd to %s\n", d.?);
                } else if (src_update() != 0) {
                    undump(current_script.?);
                }
                return;
            }
        },
        'd' => {
            if (is("dic")) {
                if (token() == null) {
                    lose = clib.getchar();
                    _ = clib.printf("%ld chars", DICSPACE);
                    if (DICSPACE != 100000) {
                        _ = clib.printf(" (default=%ld)", @as(c_long, 100000));
                    }
                    _ = clib.printf(" %ld in use\n", @as(c_long, @intCast(@intFromPtr(dicq) - @intFromPtr(dic.?))));
                    return;
                }
                if (clib.getchar() != '\n') return;
                _ = clib.printf("sorry, cannot change size of dictionary while in use\n");
                _ = clib.printf("(/q and reinvoke with flag: mira -dic %s ... )\n", dicp);
                return;
            }
        },
        'e' => {
            if (is("e") or is("edit")) {
                var mf: ?[*:0]u8 = null;
                if (token()) |tok| {
                    t_val = clib.addextn(1, tok);
                } else {
                    t_val = current_script;
                }
                if (clib.getchar() != '\n') return;
                if (!fileExists(t_val.?)) { // new file
                    if (lmirahdr == null) {
                        dicp = dicq;
                        _ = clib.strcpy(dicp, clib.getenv("HOME"));
                        if (clib.strcmp(dicp, "/") == 0) {
                            dicp[0] = 0;
                        }
                        _ = clib.strcat(dicp, "/.mirahdr");
                        lmirahdr = dicp;
                        dicq = dicp + clib.strlen(dicp) + 1;
                    }
                    if (fileExists(lmirahdr.?)) {
                        mf = lmirahdr;
                    }
                    if (mf == null and mirahdr == null) {
                        dicp = dicq;
                        _ = clib.strcpy(dicp, miralib.?);
                        _ = clib.strcat(dicp, "/.mirahdr");
                        mirahdr = dicp;
                        dicq = dicp + clib.strlen(dicp) + 1;
                    }
                    if (mf == null and fileExists(mirahdr.?)) {
                        mf = mirahdr;
                    }
                    if (mf != null and t_val != current_script) {
                        _ = clib.printf("open new script \"%s\"? [ny]", t_val.?);
                        ch1 = clib.getchar();
                        ch = ch1;
                        while (ch != '\n' and ch != clib.EOF) {
                            ch = clib.getchar();
                        }
                        if (ch1 != 'y' and ch1 != 'Y') {
                            return;
                        }
                    }
                    if (mf != null) {
                        filecp(mf.?, t_val.?);
                    }
                }
                const err_line_num: c_int = if (clib.strcmp(t_val.?, current_script.?) == 0) @intCast(errline)
                    else if (errs != 0 and clib.strcmp(t_val.?, @ptrFromInt(@as(usize, @intCast(h(errs))))) == 0) @intCast(t(errs))
                    else @intCast(clib.geterrlin(t_val.?));
                editfile(t_val.?, err_line_num);
                return;
            }
            if (is("editor")) {
                const hold = @as([*]u8, @ptrCast(&linebuf[0]));
                if (getln(getStdin(), pnlim - 1, hold) == 0) {
                    return;
                }
                if (hold[0] == 0) {
                    _ = clib.printf("%s\n", editor orelse @constCast(""));
                    return;
                }
                var h_ptr = hold + clib.strlen(hold);
                while ((h_ptr - 1)[0] == ' ' or (h_ptr - 1)[0] == '\t') {
                    h_ptr -= 1;
                    h_ptr[0] = 0;
                }
                if (hold[0] == '"' or hold[0] == '\'') {
                    _ = clib.printf("please type name of editor without quotation marks\n");
                    return;
                }
                _ = clib.printf("change editor to: \"%s\"? [ny]", hold);
                ch1 = clib.getchar();
                ch = ch1;
                while (ch != '\n' and ch != clib.EOF) {
                    ch = clib.getchar();
                }
                if (ch1 != 'y' and ch1 != 'Y') {
                    _ = clib.printf("editor not changed\n");
                    return;
                }
                _ = clib.strcpy(&ebuf, hold);
                editor = @as([*:0]u8, @ptrCast(&ebuf));
                fixeditor();
                echoing = verbosity & listing;
                rc_write();
                _ = clib.printf("editor = %s\n", editor orelse @constCast(""));
                return;
            }
        },
        'f' => {
            if (is("f") or is("file")) {
                const t_tok = token();
                if (clib.getchar() != '\n') return;
                if (t_tok) |tok| {
                    t_val = clib.addextn(1, tok);
                    _ = clib.keep(t_val.?);
                } else {
                    t_val = null;
                }
                if (t_val != null) {
                    errline = 0;
                    errs = 0;
                }
                if (t_val != null) {
                    if (clib.strcmp(t_val.?, current_script.?) != 0 or (files == NIL and clib.okdump(t_val.?) != 0)) {
                        CLASHES = NIL;
                        undump(t_val.?);
                        if (CLASHES != NIL) {
                            loadfile(t_val.?);
                        }
                    } else {
                        loadfile(t_val.?);
                    }
                } else {
                    _ = clib.printf("%s%s\n", current_script.?, @as([*:0]const u8, if (files == NIL) " (not loaded)" else ""));
                }
                return;
            }
            if (is("files")) {
                if (clib.getchar() != '\n') return;
                var f = files;
                while (f != NIL) : (f = t(f)) {
                    _ = clib.printf("(%s,%ld,%ld)", get_fil(h(f)), fil_time(h(f)), fil_share(h(f)));
                    clib.printlist(@constCast(""), fil_defs(h(f)));
                }
                return;
            }
            if (is("find")) {
                var i: Word = 0;
                while (token() != null) {
                    const x = clib.findid(dicp);
                    i += 1;
                    if (x != NIL) {
                        const n = get_id(x);
                        var y = primenv;
                        while (y != NIL) : (y = t(y)) {
                            if (tag[@intCast(h(y))] == ID) {
                                if (h(y) == x or clib.strcmp(clib.getaka(h(y)), n) == 0) {
                                    finger(get_id(h(y)));
                                }
                            }
                        }
                        var f = files;
                        while (f != NIL) : (f = t(f)) {
                            var y_def = fil_defs(h(f));
                            while (y_def != NIL) : (y_def = t(y_def)) {
                                if (tag[@intCast(h(y_def))] == ID) {
                                    if (h(y_def) == x or clib.strcmp(clib.getaka(h(y_def)), n) == 0) {
                                        finger(get_id(h(y_def)));
                                    }
                                }
                            }
                        }
                    }
                }
                ch = clib.getchar();
                if (i == 0) {
                    _ = clib.printf("\x07extra characters at end of command\n");
                }
                return;
            }
        },
        'g' => {
            if (is("gc")) {
                if (clib.getchar() != '\n') return;
                atgc = 1;
                return;
            }
        },
        'h' => {
            if (is("h") or is("help")) {
                if (clib.getchar() != '\n') return;
                _ = clib.strcpy(&linebuf, miralib.?);
                _ = clib.strcat(&linebuf, "/helpfile");
                filecopy(@as([*:0]const u8, @ptrCast(&linebuf)));
                return;
            }
            if (is("heap")) {
                var x: c_long = undefined;
                if (token() == null) {
                    lose = clib.getchar();
                    _ = clib.printf("%ld cells", SPACELIMIT);
                    if (SPACELIMIT != 2500000) {
                        _ = clib.printf(" (default=%ld)", @as(c_long, 2500000));
                    }
                    _ = clib.printf("\n");
                    return;
                }
                if (clib.getchar() != '\n') return;
                if (clib.sscanf(dicp, "%ld", &x) != 1 or badval(x)) {
                    _ = clib.printf("illegal value (heap unchanged)\n");
                    return;
                }
                if (x < clib.trueheapsize()) {
                    _ = clib.printf("sorry, cannot shrink heap to %ld at this time\n", x);
                } else {
                    if (x != SPACELIMIT) {
                        SPACELIMIT = x;
                        clib.resetheap();
                    }
                    _ = clib.printf("heaplimit = %ld cells\n", SPACELIMIT);
                    rc_write();
                }
                return;
            }
            if (is("hush")) {
                if (clib.getchar() != '\n') return;
                echoing = 0;
                verbosity = 0;
                return;
            }
        },
        'l' => {
            if (is("list")) {
                if (clib.getchar() != '\n') return;
                listing = 1;
                echoing = verbosity & listing;
                rc_write();
                return;
            }
        },
        'm' => {
            if (is("m") or is("man")) {
                if (clib.getchar() != '\n') return;
                manaction();
                return;
            }
            if (is("miralib")) {
                if (clib.getchar() != '\n') return;
                _ = clib.printf("%s\n", miralib.?);
                return;
            }
        },
        'n' => {
            if (is("nocount")) {
                if (clib.getchar() != '\n') return;
                atcount = 0;
                return;
            }
            if (is("nogc")) {
                if (clib.getchar() != '\n') return;
                atgc = 0;
                return;
            }
            if (is("nohush")) {
                if (clib.getchar() != '\n') return;
                echoing = listing;
                verbosity = 1;
                return;
            }
            if (is("nolist")) {
                if (clib.getchar() != '\n') return;
                listing = 0;
                echoing = 0;
                rc_write();
                return;
            }
            if (is("norecheck")) {
                if (clib.getchar() != '\n') return;
                rechecking = 0;
                rc_write();
                return;
            }
        },
        'q' => {
            if (is("q") or is("quit")) {
                if (clib.getchar() != '\n') return;
                if (verbosity != 0) {
                    _ = clib.printf("miranda logout\n");
                }
                clib.exit(0);
            }
        },
        'r' => {
            if (is("recheck")) {
                if (clib.getchar() != '\n') return;
                rechecking = 2;
                rc_write();
                return;
            }
        },
        's' => {
            if (is("s") or is("settings")) {
                if (clib.getchar() != '\n') return;
                _ = clib.printf("*\theap %ld\n", SPACELIMIT);
                _ = clib.printf("*\tdic %ld\n", DICSPACE);
                _ = clib.printf("*\teditor = %s\n", editor orelse @constCast(""));
                _ = clib.printf("*\t%slist\n", @as([*:0]const u8, if (listing != 0) "" else "no"));
                _ = clib.printf("*\t%srecheck\n", @as([*:0]const u8, if (rechecking != 0) "" else "no"));
                if (strictif == 0) {
                    _ = clib.printf("\t-nostrictif (deprecated!)\n");
                }
                if (atcount != 0) {
                    _ = clib.printf("\tcount\n");
                }
                if (atgc != 0) {
                    _ = clib.printf("\tgc\n");
                }
                if (UTF8 != 0) {
                    _ = clib.printf("\tUTF-8 i/o\n");
                }
                if (verbosity == 0) {
                    _ = clib.printf("\thush\n");
                }
                if (debug != 0) {
                    _ = clib.printf("\tdebug 0%o\n", debug);
                }
                _ = clib.printf("\n* items remembered between sessions\n");
                return;
            }
        },
        'v' => {
            if (is("v") or is("version")) {
                if (clib.getchar() != '\n') return;
                v_info(0);
                return;
            }
        },
        'V' => {
            if (is("V")) {
                if (clib.getchar() != '\n') return;
                v_info(1);
                return;
            }
        },
        else => {},
    }
    xschars();
}

fn manaction() void {
    _ = clib.sprintf(&linebuf, "\"%s/menudriver\" \"%s/manual\"", miralib.?, miralib.?);
    _ = clib.system(&linebuf);
}

fn editfile(t_val: [*:0]const u8, line: c_int) void {
    var line_val = line;
    const ebuf_local = @as([*]u8, @ptrCast(&linebuf[0]));
    var p = ebuf_local;
    var q = editor.?;
    var tdone: c_int = 0;
    if (line_val == 0) {
        line_val = 1;
    }
    while (q[0] != 0) {
        const ch = q[0];
        q += 1;
        p[0] = ch;
        p += 1;
        if ((p - 1)[0] == '\\' and (q[0] == '!' or q[0] == '%')) {
            (p - 1)[0] = q[0];
            q += 1;
        } else if ((p - 1)[0] == '!') {
            p -= 1;
            _ = clib.sprintf(p, "%d", line_val);
            p += clib.strlen(p);
        } else if ((p - 1)[0] == '%') {
            (p - 1)[0] = '"';
            p[0] = 0;
            const limit = @as(usize, @intCast(BUFSIZE)) + @intFromPtr(ebuf_local) - @intFromPtr(p);
            _ = clib.strncat(p, t_val, limit);
            p += clib.strlen(p);
            p[0] = '"';
            p += 1;
            p[0] = 0;
            tdone = 1;
        }
    }
    p[0] = 0;
    if (tdone == 0) {
        (p - 1)[0] = ' ';
        p[0] = '"';
        p += 1;
        p[0] = 0;
        const limit = @as(usize, @intCast(@as(usize, @intCast(BUFSIZE)) + @intFromPtr(ebuf_local) - @intFromPtr(p)));
        _ = clib.strncat(p, t_val, limit);
        p += clib.strlen(p);
        p[0] = '"';
        p += 1;
        p[0] = 0;
    }
    _ = clib.system(ebuf_local);
    if (src_update() != 0) {
        loadfile(current_script.?);
    }
}

fn xschars() void {
    var ch: c_int = undefined;
    _ = clib.printf("\x07extra characters at end of command\n");
    while (true) {
        ch = clib.getchar();
        if (ch == '\n' or ch == clib.EOF) break;
    }
}

var filequote_mlen: usize = 0;
fn filequote(p: [*:0]const u8) void {
    if (filequote_mlen == 0) {
        const last_slash = clib.strrchr(&PRELUDE, '/');
        if (last_slash != null) {
            filequote_mlen = @intFromPtr(last_slash.?) - @intFromPtr(&PRELUDE) + 1;
        }
    }
    if (clib.strncmp(p, &PRELUDE, filequote_mlen) == 0) {
        _ = clib.printf("<%s>", p + filequote_mlen);
    } else {
        _ = clib.printf("\"%s\"", p);
    }
}

fn finger(n: [*:0]const u8) void {
    const x = clib.findid(@constCast(n));
    var line: Word = 0;
    var s: ?[*:0]u8 = null;
    if (x != NIL and id_type(x) != undef_t) {
        if (id_who(x) != NIL) {
            const here_val = get_here(x);
            s = @ptrFromInt(@as(usize, @intCast(h(here_val))));
            line = t(here_val);
        }
        if (lastid == 0) {
            lastid = x;
        }
        clib.report_type(x);
        if (id_who(x) == NIL) {
            _ = clib.printf(" ||primitive to Miranda\n");
        } else {
            const aka = clib.getaka(x);
            const aka_opt: ?[*:0]const u8 = if (clib.strcmp(aka, get_id(x)) == 0) null else aka;
            if (id_val(x) == UNDEF and id_type(x) != wrong_t) {
                _ = clib.printf(" ||(UNDEFINED) specified in ");
            } else if (id_val(x) == FREE) {
                _ = clib.printf(" ||(FREE) specified in ");
            } else if (id_type(x) == type_t and t_class(x) == free_t) {
                _ = clib.printf(" ||(free type) specified in ");
            } else {
                const class_str: [*:0]const u8 = if (id_type(x) == type_t and t_class(x) == abstract_t) "(abstract type) "
                    else if (id_type(x) == type_t and t_class(x) == algebraic_t) "(algebraic type) "
                    else if (id_type(x) == type_t and t_class(x) == placeholder_t) "(placeholder type) "
                    else if (id_type(x) == type_t and t_class(x) == synonym_t) "(synonym type) "
                    else "";
                _ = clib.printf(" ||%sdefined in ", class_str);
            }
            filequote(s.?);
            if (baded != 0 or rechecking != 0) {
                _ = clib.printf(" line %ld", line);
            }
            if (aka_opt) |aka_s| {
                _ = clib.printf(" (as \"%s\")\n", aka_s);
            } else {
                _ = clib.putchar('\n');
            }
        }
        if (atobject != 0) {
            _ = clib.printf("%s = ", get_id(x));
            clib.out(getStdout(), id_val(x));
            _ = clib.putchar('\n');
        }
        return;
    }
    diagnose(n);
}

fn diagnose(n: [*:0]const u8) void {
    var i: usize = 0;
    if (clib.isalpha(@intCast(n[0])) != 0) {
        while (n[i] != 0 and clib.okid(n[i]) != 0) {
            i += 1;
        }
    }
    if (n[i] != 0) {
        _ = clib.printf("\"%s\" -- not an identifier\n", n);
        return;
    }
    const presym = [_][*:0]const u8{
        "abstype", "div", "if", "mod", "otherwise", "readvals", "show", "type", "where", "with",
    };
    const presym_n = [_]c_int{ 21, 8, 15, 8, 15, 31, 23, 22, 15, 21 };
    inline for (presym, presym_n) |sym, sym_n| {
        if (clib.strcmp(n, sym) == 0) {
            _ = clib.printf("%s -- keyword (see manual, section %d)\n", n, sym_n);
            return;
        }
    }
    _ = clib.printf("identifier \"%s\" not in scope\n", n);
}

fn allnamescom() void {
    var s: Word = undefined;
    var x = ND;
    var y = ND;
    var z: Word = 0;
    leftist = 0;
    namescom(make_fil(if (nostdenv != 0) null else @as([*:0]const u8, @ptrCast(&STDENV)), 0, 0, primenv));
    if (files == NIL) return;
    s = t(files);
    while (s != NIL) : (s = t(s)) {
        namescom(h(s));
    }
    namescom(h(files));
    sorted = 1;

    while (x != NIL and id_type(h(x)) == undef_t) {
        x = t(x);
    }
    while (y != NIL and id_type(h(y)) != undef_t) {
        y = t(y);
    }
    if (x != NIL) {
        _ = clib.printf("WARNING, SCRIPT CONTAINS TYPE ERRORS: ");
        while (x != NIL) : (x = t(x)) {
            if (id_type(h(x)) != undef_t) {
                if (z == 0) {
                    z = 1;
                } else {
                    _ = clib.putchar(',');
                }
                clib.out(getStdout(), h(x));
            }
        }
        _ = clib.printf(";\n");
    }
    if (y != NIL) {
        _ = clib.printf("%s UNDEFINED NAMES: ", @as([*:0]const u8, if (z != 0) "AND" else "WARNING, SCRIPT CONTAINS"));
        z = 0;
        while (y != NIL) : (y = t(y)) {
            if (id_type(h(y)) == undef_t) {
                if (z == 0) {
                    z = 1;
                } else {
                    _ = clib.putchar(',');
                }
                clib.out(getStdout(), h(y));
            }
        }
        _ = clib.printf(";\n");
    }
}

fn spaces(s: Word) void {
    var j = s;
    while (j > 0) : (j -= 1) {
        _ = clib.putchar(' ');
    }
}

fn namescom(l: Word) void {
    var n = fil_defs(l);
    var col_local: Word = 0;
    var undefs: Word = NIL;
    var wp: usize = 0;
    const scrwd = twidth();
    if (sorted == 0 and n != primenv) {
        n = alfasort(n);
        tp(l).* = n;
    }
    if (n == NIL) return;
    if (get_fil(l)) |gf| {
        filequote(gf);
    } else {
        _ = clib.printf("primitive:");
    }
    _ = clib.printf("\n");
    while (n != NIL) {
        if (id_type(h(n)) == wrong_t or id_val(h(n)) != UNDEF) {
            const w = @as(Word, @intCast(clib.strlen(get_id(h(n)))));
            if (col_local + w < @as(Word, @intCast(scrwd))) {
                col_local += if (col_local != 0) 1 else 0;
            } else if (wp > 0 and col_local + w >= @as(Word, @intCast(scrwd))) {
                var i: Word = 0;
                var r: Word = 0;
                if (wp > 1) {
                    i = @divTrunc(@as(Word, @intCast(scrwd)) - col_local, @as(Word, @intCast(wp - 1)));
                    r = @mod(@as(Word, @intCast(scrwd)) - col_local, @as(Word, @intCast(wp - 1)));
                } else {
                    _ = clib.fprintf(getStderr(), "Internal error: i and r used uninitialized in namescom()\nPlease report it to miranda@groups.io\n");
                    clib.abort();
                }
                if (i + (if (r > 0) @as(Word, 1) else 0) > 3) { // tolerance is 3
                    i = 0;
                    r = 0;
                }
                if (leftist != 0) {
                    col_local = 0;
                    while (col_local < wp) {
                        _ = clib.printf("%s", get_id(words[@as(usize, @intCast(col_local))]));
                        col_local += 1;
                        if (col_local < wp) {
                            spaces(1 + i + if (r > 0) @as(Word, 1) else @as(Word, 0));
                            r -= 1;
                        }
                    }
                } else {
                    r = @as(Word, @intCast(wp)) - 1 - r;
                    col_local = 0;
                    while (col_local < wp) {
                        _ = clib.printf("%s", get_id(words[@as(usize, @intCast(col_local))]));
                        col_local += 1;
                        if (col_local < wp) {
                            spaces(1 + i + if (r <= 0) @as(Word, 1) else @as(Word, 0));
                            r -= 1;
                        }
                    }
                }
                leftist = if (leftist == 0) 1 else 0;
                wp = 0;
                col_local = 0;
                _ = clib.putchar('\n');
            }
            col_local += w;
            words[wp] = h(n);
            wp += 1;
        } else {
            undefs = cons(h(n), undefs);
        }
        n = t(n);
    }
    if (wp > 0) {
        col_local = 0;
        while (col_local < wp) {
            _ = clib.printf("%s", get_id(words[@as(usize, @intCast(col_local))]));
            col_local += 1;
            _ = clib.putc(if (col_local == wp) '\n' else ' ', getStdout());
        }
    }
    if (undefs == NIL) return;
    undefs = reverse(undefs);
    clib.printlist(@constCast("SPECIFIED BUT NOT DEFINED: "), undefs);
}

fn loadfile(t_val: [*:0]const u8) void {
    var h_val: Word = NIL;
    loading = 1;
    errs = 0;
    errline = 0;
    current_script = @constCast(t_val);
    oldfiles = NIL;
    unload();

    if (!fileExists(t_val)) {
        if (initialising != 0) {
            _ = clib.fprintf(getStderr(), "panic: %s not found\n", t_val);
            clib.exit(1);
        }
        if (verbosity != 0) {
            _ = clib.printf("new file %s\n", t_val);
        }
        if (magic != 0) {
            _ = clib.fprintf(getStderr(), "mira -exec %s: no such file\n", t_val);
            clib.exit(1);
        }
        if (making != 0 and ideep == 0) {
            _ = clib.printf("mira -make %s: no such file\n", t_val);
        } else {
            oldfiles = cons(make_fil(t_val, 0, 0, NIL), NIL);
        }
        loading = 0;
        return;
    }

    if (clib.openfile(@constCast(t_val)) == 0) {
        if (initialising != 0) {
            _ = clib.fprintf(getStderr(), "panic: cannot open %s\n", t_val);
            clib.exit(1);
        }
        _ = clib.printf("cannot open %s\n", t_val);
        oldfiles = cons(make_fil(t_val, 0, 0, NIL), NIL);
        loading = 0;
        return;
    }

    files = cons(make_fil(t_val, fm_time(t_val), 1, NIL), NIL);
    current_file = h(files);
    tp(h(fileq)).* = current_file;

    if (initialising != 0 and clib.strcmp(t_val, @as([*:0]const u8, @ptrCast(&PRELUDE))) == 0) {
        privlib();
    } else if (initialising != 0 or nostdenv == 1) {
        if (clib.strcmp(t_val, @as([*:0]const u8, @ptrCast(&STDENV))) == 0) {
            stdlib();
        }
    }

    c = ' ';
    col = 0;
    s_in = @ptrFromInt(@as(usize, @intCast(h(h(fileq)))));
    clib.adjust_prefix(@constCast(t_val));

    commandmode = 0;
    if (verbosity != 0 or making != 0) {
        _ = clib.printf("compiling %s\n", t_val);
    }
    nextpn = 0;
    embargoes = NIL;
    detrop = NIL;
    fnts = NIL;
    rfl = NIL;
    bereaved = NIL;
    ld_stuff = NIL;
    exportfiles = NIL;
    freeids = NIL;
    exports = NIL;
    includees = NIL;
    FBS = NIL;

    _ = parser_api.parseCurrent() catch {};

    if (SYNERR == 0 and exportfiles != NIL) {
        var s = exportfiles;
        while (s != NIL) : (s = t(s)) {
            if (h(s) == PLUS) {
                var i = fil_defs(h(files));
                while (i != NIL) : (i = t(i)) {
                    if (isvariable(h(i)) and !isfreeid(h(i))) {
                        tp(exports).* = clib.add1(h(i), t(exports));
                    }
                }
            } else {
                var count: Word = 0;
                var i = includees;
                while (i != NIL) : (i = t(i)) {
                    if (clib.strcmp(@ptrFromInt(@as(usize, @intCast(h(h(h(i)))))), @ptrFromInt(@as(usize, @intCast(h(s))))) == 0) {
                        hp(s).* = h(h(h(i)));
                        count += 1;
                    }
                }
                if (count != 1) {
                    SYNERR = 1;
                    _ = clib.printf("illegal fileid \"%s\" in export list (%s)\n", @as([*:0]const u8, @ptrFromInt(@as(usize, @intCast(h(s))))), @as([*:0]const u8, if (count != 0) "ambiguous" else "not %%included in script"));
                }
            }
        }
        if (SYNERR != 0) {
            clib.sayhere(h(exports), 1);
            _ = clib.fprintf(getStderr().?, "compilation abandoned\n");
        }
    }

    if (SYNERR == 0 and includees != NIL) {
        files = clib.append1(files, mkincludes(includees));
        includees = NIL;
    }
    ld_stuff = NIL;

    if (SYNERR == 0) {
        if (verbosity != 0 or (making != 0 and mkexports == 0 and mksources == 0)) {
            _ = clib.printf("checking types in %s\n", t_val);
        }
        clib.checktypes();
    }

    if (SYNERR == 0 and exports != NIL) {
        if (ND != NIL) {
            exports = NIL;
        } else {
            var e = embargoes;
            var u: Word = NIL;
            var n: Word = NIL;
            var c_ctr: Word = NIL;
            h_val = h(exports);
            exports = t(exports);

            while (e != NIL) : (e = t(e)) {
                if (id_type(h(e)) == undef_t) {
                    u = cons(h(e), u);
                    ND = clib.add1(h(e), ND);
                } else if (clib.member(exports, h(e)) == 0) {
                    n = cons(h(e), n);
                }
            }

            if (embargoes != NIL) {
                exports = clib.setdiff(exports, embargoes);
            }
            exports = alfasort(exports);

            e = exports;
            while (e != NIL) : (e = t(e)) {
                if (id_type(h(e)) == undef_t) {
                    u = cons(h(e), u);
                    ND = clib.add1(h(e), ND);
                } else if (id_type(h(e)) == type_t and t_class(h(e)) == algebraic_t) {
                    c_ctr = shunt(t_info(h(e)), c_ctr);
                }
            }

            if (exports == NIL) {
                _ = clib.printf("warning, export list has void contents\n");
            } else {
                exports = clib.append1(alfasort(c_ctr), exports);
            }

            if (n != NIL) {
                _ = clib.printf("redundant entry in export list:");
                while (n != NIL) : (n = t(n)) {
                    _ = clib.printf(" -%s", get_id(h(n)));
                }
                _ = clib.putchar('\n');
            }

            if (u != NIL) {
                exports = NIL;
                clib.printlist(@constCast("undefined names in export list: "), u);
            }

            if (u != NIL) {
                clib.sayhere(h_val, 1);
                h_val = NIL;
            } else if (exports == NIL or n != NIL) {
                clib.out_here(getStderr(), h_val, 1);
                h_val = NIL;
            }
        }
    }

    if (SYNERR == 0 and ND == NIL and (exports != NIL or t(files) != NIL)) {
        var e1 = exports;
        var r: Word = NIL;
        var e: Word = NIL;
        if (exports != NIL) {
            while (e1 != NIL) : (e1 = t(e1)) {
                const ty = id_type(h(e1));
                if (ty == type_t) {
                    if (t_class(h(e1)) == synonym_t) {
                        r = clib.UNION(r, clib.deps(t_info(h(e1))));
                    } else {
                        e = cons(h(e1), e);
                    }
                } else {
                    r = clib.UNION(r, clib.deps(ty));
                }
            }
        } else {
            e1 = fil_defs(h(files));
            while (e1 != NIL) : (e1 = t(e1)) {
                const ty = id_type(h(e1));
                if (ty == type_t) {
                    if (t_class(h(e1)) == synonym_t) {
                        r = clib.UNION(r, clib.deps(t_info(h(e1))));
                    } else {
                        e = cons(h(e1), e);
                    }
                } else {
                    r = clib.UNION(r, clib.deps(ty));
                }
            }
        }

        e1 = freeids;
        while (e1 != NIL) : (e1 = t(e1)) {
            const ty = id_type(h(h(e1)));
            if (ty == type_t) {
                if (t_class(h(h(e1))) == synonym_t) {
                    r = clib.UNION(r, clib.deps(t_info(h(h(e1)))));
                } else {
                    e = cons(h(h(e1)), e);
                }
            } else {
                r = clib.UNION(r, clib.deps(ty));
            }
        }

        while (r != NIL) : (r = t(r)) {
            if (clib.member(e, h(r)) == 0) {
                bereaved = cons(h(r), bereaved);
            }
        }
    }

    if (exports != NIL and bereaved != NIL) {
        const b = clib.intersection(bereaved, clib.newtyps);
        if (b != NIL) {
            _ = clib.printf("warning, export list is incomplete - missing typename: ");
            clib.printlist(@constCast(""), b);
        }
        if (b != NIL and h_val != NIL) {
            clib.out_here(getStdout(), h_val, 1);
        }
    }

    if (SYNERR == 0 and detrop != NIL) {
        const gd = detrop;
        while (detrop != NIL and tag[@intCast(dval(h(detrop)))] == clib.LABEL) {
            detrop = t(detrop);
        }
        if (detrop != NIL) {
            _ = clib.printf("warning, script contains unused local definitions:-\n");
        }
        while (detrop != NIL) {
            clib.out_here(getStdout(), h(h(t(dval(h(detrop))))), 0);
            _ = clib.putchar('\t');
            clib.out_pattern(getStdout(), dlhs(h(detrop)));
            _ = clib.putchar('\n');
            detrop = t(detrop);
            while (detrop != NIL and tag[@intCast(dval(h(detrop)))] == clib.LABEL) {
                detrop = t(detrop);
            }
        }

        var gd_mut = gd;
        while (gd_mut != NIL and tag[@intCast(dval(h(gd_mut)))] != clib.LABEL) {
            gd_mut = t(gd_mut);
        }
        if (gd_mut != NIL) {
            _ = clib.printf("warning, grammar contains unused nonterminals:-\n");
        }
        while (gd_mut != NIL) {
            clib.out_here(getStdout(), h(dval(h(gd_mut))), 0);
            _ = clib.putchar('\t');
            clib.out_pattern(getStdout(), dlhs(h(gd_mut)));
            _ = clib.putchar('\n');
            gd_mut = t(gd_mut);
            while (gd_mut != NIL and tag[@intCast(dval(h(gd_mut)))] != clib.LABEL) {
                gd_mut = t(gd_mut);
            }
        }
    }

    if (SYNERR == 0) {
        var x = fil_defs(h(files));
        lfrule = 0;
        while (x != NIL) : (x = t(x)) {
            if (id_type(h(x)) != type_t) {
                current_id = h(x);
                polyshowerror = 0;
                tp(h(x)).* = clib.codegen(id_val(h(x)));
                if (polyshowerror != 0) {
                    tp(h(x)).* = UNDEF;
                }
            }
        }
        current_id = 0;
        if (lfrule != 0 and (verbosity != 0 or making != 0)) {
            _ = clib.printf("grammar optimisation: %d common left factors found\n", lfrule);
        }
        if (initialising != 0 and ND != NIL) {
            _ = clib.fprintf(getStderr(), "panic: %s contains errors\n", @as([*:0]const u8, if (okprel != 0) "stdenv" else "prelude"));
            clib.exit(1);
        }
        if (initialising != 0) {
            makedump();
        } else if (normal(t_val) != 0) {
            fixexports();
            makedump();
            unfixexports();
        }
        if (errline == 0 and errs != 0 and clib.strcmp(@ptrFromInt(@as(usize, @intCast(h(errs)))), current_script.?) == 0) {
            errline = t(errs);
        }
        ND = alfasort(ND);
        loading = 0;
        return;
    }

    if (initialising != 0) {
        _ = clib.fprintf(getStderr(), "panic: cannot compile %s\n", @as([*:0]const u8, if (okprel != 0) "stdenv" else "prelude"));
        clib.exit(1);
    }
    oldfiles = files;
    unload();
    if (normal(t_val) != 0 and SYNERR != 2) {
        makedump();
    }
    SYNERR = 0;
    loading = 0;
}

fn fixexports() void {
    var e = exports;
    var f: Word = undefined;
    while (e != NIL) : (e = t(e)) {
        paint(h(e));
    }
    internals = NIL;
    if (exports == NIL and exportfiles == NIL and embargoes == NIL) {
        e = freeids;
        while (e != NIL) : (e = t(e)) {
            internals = cons(privatise(h(h(e))), internals);
        }
        f = t(files);
        while (f != NIL) : (f = t(f)) {
            var e_def = fil_defs(h(f));
            while (e_def != NIL) : (e_def = t(e_def)) {
                if (tag[@intCast(h(e_def))] == ID) {
                    internals = cons(privatise(h(e_def)), internals);
                }
            }
        }
    } else {
        f = files;
        while (f != NIL) : (f = t(f)) {
            var e_def = fil_defs(h(f));
            while (e_def != NIL) : (e_def = t(e_def)) {
                if (tag[@intCast(h(e_def))] == ID and unpainted(h(e_def))) {
                    internals = cons(privatise(h(e_def)), internals);
                }
            }
        }
    }
    e = exports;
    while (e != NIL) : (e = t(e)) {
        unpaint(h(e));
    }
}

fn paint(x: Word) void {
    tp(x).* = clib.ap(clib.EXPORT, id_val(x));
}

fn unpainted(x: Word) bool {
    const v = id_val(x);
    return tag[@intCast(v)] != AP or h(v) != clib.EXPORT;
}

fn unpaint(x: Word) void {
    tp(x).* = t(id_val(x));
}

fn unfixexports() void {
    var i = internals;
    if (mkexports != 0) return;
    while (i != NIL) : (i = t(i)) {
        _ = publicise(h(i));
    }
    internals = NIL;
}

fn privatise(x: Word) Word {

    const n = clib.make_pn(x);
    const hash_idx = hash(get_id(x));
    const i = h(n);

    if (id_type(x) == type_t) {
        tp(t_info(x)).* = cons(clib.datapair(clib.getaka(x), 0), get_here(x));
    }

    if (id_val(x) == UNDEF) {
        tp(x).* = clib.ap(clib.datapair(clib.getaka(x), 0), get_here(x));
    }

    pnvec.?[@as(usize, @intCast(i))] = x;
    tag[@intCast(n)] = ID;
    hp(n).* = h(x);
    tag[@intCast(x)] = clib.STRCONS;
    hp(x).* = i;

    const current_bucket = namebucket[hash_idx];
    if (h(current_bucket) == x) {
        hp(current_bucket).* = n;
    } else {
        var prev = current_bucket;
        var curr = t(current_bucket);
        while (curr != NIL) {
            if (h(curr) == x) {
                hp(curr).* = n;
                break;
            }
            prev = curr;
            curr = t(curr);
        }
    }
    return n;
}

fn hash(s: [*:0]const u8) usize {
    return (@as(usize, s[0]) + @as(usize, s[clib.strlen(s) - 1])) & 127;
}

fn publicise(x: Word) Word {
    const i = id_val(x);
    const hash_idx = hash(get_id(x));

    tag[@intCast(i)] = ID;
    hp(i).* = h(x);

    const val = t(i);
    if (tag[@intCast(val)] == AP and tag[@intCast(h(val))] == clib.DATAPAIR) {
        tp(i).* = UNDEF;
    }

    const current_bucket = namebucket[hash_idx];
    if (h(current_bucket) == x) {
        hp(current_bucket).* = i;
    } else {
        var prev = current_bucket;
        var curr = t(current_bucket);
        while (curr != NIL) {
            if (h(curr) == x) {
                hp(curr).* = i;
                break;
            }
            prev = curr;
            curr = t(curr);
        }
    }
    return i;
}

fn sigdefer(_: c_int) callconv(.c) void {
    sigflag = 1;
}

fn WEXITSTATUS(status: c_int) c_int {
    return (status >> 8) & 0xff;
}

fn WIFSIGNALED(status: c_int) bool {
    return (status & 0x7f) != 0 and (status & 0x7f) != 0x7f;
}

fn WTERMSIG(status: c_int) c_int {
    return status & 0x7f;
}

fn mkincludes(includees_val: Word) Word {
    var includees_list = includees_val;
    var result: Word = NIL;
    var tclashes: Word = NIL;
    includees_list = reverse(includees_list);
    const pid = clib.fork();
    if (pid != 0) { // parent
        var status: c_int = 0;
        if (pid == -1) {
            clib.perror("UNIX error - cannot create process");
            if (ideep > 6) {
                _ = clib.fprintf(getStderr(), "error occurs %d deep in %%include files\n", ideep);
            }
            if (ideep != 0) {
                clib.exit(2);
            }
            SYNERR = 2;
            _ = clib.printf("compilation of \"%s\" abandoned\n", current_script.?);
            return NIL;
        }
        while (pid != clib.wait(&status)) {}
        if (WEXITSTATUS(status) == 2) {
            if (ideep != 0) {
                clib.exit(2);
            } else {
                SYNERR = 2;
                _ = clib.printf("compilation of \"%s\" abandoned\n", current_script.?);
                return NIL;
            }
        }
    } else { // child
        _ = signals(clib.SIGINT, 0);
        ideep += 1;
        making = 1;
        make_status = 0;
        echoing = 0;
        listing = 0;
        verbosity = 0;
        magic = 0;
        _ = clib.sigsetjmp(&env, 1);
        while (includees_list != NIL and make_status == 0) {
            undump(@ptrFromInt(@as(usize, @intCast(h(h(h(includees_list)))))));
            if (ND != NIL or (files == NIL and oldfiles != NIL)) {
                make_status = 1;
            }
            includees_list = t(includees_list);
        }
        clib.exit(@intCast(make_status));
    }

    sigflag = 0;
    while (includees_list != NIL) {
        var x: Word = NIL;
        var oldsig: usize = 0;
        var f: ?*clib.FILE = null;
        const fn_str = @as([*:0]const u8, @ptrFromInt(@as(usize, @intCast(h(h(h(includees_list)))))));

        _ = clib.strcpy(dicp, fn_str);
        _ = clib.strcpy(dicp + clib.strlen(dicp) - 1, obsuffix);

        if (making == 0) {
            oldsig = signals(clib.SIGINT, @intFromPtr(&sigdefer));
        }

        f = clib.fopen(dicp, "r");
        if (f != null) {
            x = clib.load_script(f.?, @constCast(fn_str), h(t(h(includees_list))), t(t(h(includees_list))), 0);
            _ = clib.fclose(f.?);
        }

        ld_stuff = cons(x, ld_stuff);
        if (making == 0) {
            _ = signals(clib.SIGINT, oldsig);
        }

        if (sigflag != 0) {
            sigflag = 0;
            if (oldsig > 1) {
                const handler: *const fn (c_int) callconv(.c) void = @ptrFromInt(oldsig);
                handler(clib.SIGINT);
            }
        }

        if (f != null and clib.BAD_DUMP == 0 and x != NIL and ND == NIL and clib.CLASHES == NIL and clib.ALIASES == NIL and clib.TSUPPRESSED == NIL and clib.DETROP == NIL and clib.MISSING == NIL) {
            if (clib.TORPHANS != 0) {
                rfl = shunt(x, rfl);
            }
            var y = x;
            while (y != NIL) : (y = t(y)) {
                const nodev = inodev(get_fil(h(y)).?);
                tp(fil_inodev(h(y))).* = nodev;
            }

            y = x;
            while (y != NIL) : (y = t(y)) {
                if (fil_share(h(y)) != 0) {
                    var z = result;
                    while (z != NIL) : (z = t(z)) {
                        if (fil_share(h(z)) != 0 and same_file(h(y), h(z)) and fil_time(h(y)) == fil_time(h(z))) {
                            var p = fil_defs(h(y));
                            var q = fil_defs(h(z));
                            while (p != NIL and q != NIL) {
                                if (tag[@intCast(h(p))] == ID) {
                                    if (id_type(h(p)) == type_t and (tag[@intCast(h(q))] == ID or tag[@intCast(pn_val(h(q)))] == ID)) {
                                        var w = tclashes;
                                        const orig = if (tag[@intCast(h(q))] == ID) h(q) else pn_val(h(q));
                                        if (t_class(h(p)) == synonym_t) {
                                            p = t(p);
                                            q = t(q);
                                            continue;
                                        }
                                        while (w != NIL and (clib.strcmp(get_fil(h(w)).?, get_fil(h(z)).?) != 0 or h(t(h(w))) != orig)) {
                                            w = t(w);
                                        }
                                        if (w == NIL) {
                                            tclashes = cons(clib.strcons(@as(Word, @intCast(@intFromPtr(get_fil(h(z)).?))), cons(orig, NIL)), tclashes);
                                            w = tclashes;
                                        }
                                        tp(t(t(h(w)))).* = cons(h(p), t(t(h(w))));
                                    } else {
                                        tp(h(q)).* = h(p);
                                    }
                                } else {
                                    tp(h(p)).* = h(q);
                                }
                                p = t(p);
                                q = t(q);
                            }
                            if (p != NIL or q != NIL) {
                                _ = clib.fprintf(getStderr(), "impossible event in mkincludes\n");
                            }
                        }
                    }
                }
            }

            if (clib.member(exportfiles, @intCast(@intFromPtr(fn_str))) != 0) {
                y = x;
                while (y != NIL) : (y = t(y)) {
                    var z = fil_defs(h(y));
                    while (z != NIL) : (z = t(z)) {
                        if (isvariable(h(z))) {
                            tp(exports).* = clib.add1(h(z), t(exports));
                        }
                    }
                }
            }

            result = clib.append1(result, x);
            if (h(FBS) == NIL) {
                FBS = t(FBS);
            } else {
                hp(FBS).* = cons(t(h(h(includees_list))), h(FBS));
            }
            includees_list = t(includees_list);
            continue;
        }

        if (f == null) {
            result = cons(make_fil(fn_str, fm_time(fn_str), 0, NIL), result);
        } else if (x == NIL and clib.BAD_DUMP != -2) {
            result = clib.append1(result, oldfiles);
            oldfiles = NIL;
        } else {
            result = clib.append1(result, x);
        }

        SYNERR = 1;
        _ = clib.printf("unsuccessful %%include directive ");
        clib.sayhere(t(h(h(includees_list))), 1);

        if (f == null) {
            _ = clib.printf("\"%s\" cannot be loaded\n", fn_str);
            CLASHES = NIL;
            DETROP = NIL;
            MISSING = NIL;
        } else if (clib.BAD_DUMP == -2) {
            clib.printlist(@constCast("aliasing causes nameclashes: "), CLASHES);
            CLASHES = NIL;
        } else if (ALIASES != NIL or TSUPPRESSED != NIL) {
            if (ALIASES != NIL) {
                _ = clib.printf("alias fails (name%s not found in file", @as([*:0]const u8, if (t(ALIASES) == NIL) "" else "s"));
                clib.printlist(@constCast("): "), ALIASES);
                ALIASES = NIL;
            }
            if (TSUPPRESSED != NIL) {
                _ = clib.printf("illegal alias (cannot suppress typename%s):", @as([*:0]const u8, if (t(TSUPPRESSED) == NIL) "" else "s"));
                var ts = TSUPPRESSED;
                while (ts != NIL) : (ts = t(ts)) {
                    _ = clib.printf(" -%s", get_id(h(ts)));
                }
                _ = clib.putchar('\n');
            }
        } else if (clib.BAD_DUMP != 0) {
            _ = clib.printf("\"%s\" has bad data in dump file\n", fn_str);
        } else if (x == NIL) {
            _ = clib.printf("\"%s\" contains syntax error\n", fn_str);
        } else if (ND != NIL) {
            _ = clib.printf("\"%s\" contains undefined names or type errors\n", fn_str);
        }

        if (ND == NIL and CLASHES != NIL) {
            _ = clib.printf("\"%s\" ", fn_str);
            clib.printlist(@constCast("causes nameclashes: "), CLASHES);
        }

        while (DETROP != NIL and tag[@intCast(h(DETROP))] == CONS) {
            const fa = h(t(h(DETROP)));
            const ta = t(t(h(DETROP)));
            const pn = get_id(h(h(DETROP)));
            if (fa == -1 or ta == -1) {
                _ = clib.printf("`%s' has binding of wrong kind ", pn);
                _ = clib.printf(if (fa == -1) "(should be \"= value\" not \"== type\")\n" else "(should be \"== type\" not \"= value\")\n");
            } else {
                _ = clib.printf("`%s' has == binding of wrong arity ", pn);
                _ = clib.printf("(formal has arity %ld, actual has arity %ld)\n", fa, ta);
            }
            DETROP = t(DETROP);
        }

        if (DETROP != NIL) {
            _ = clib.printf("illegal parameter binding (name%s not %%free in file", @as([*:0]const u8, if (t(DETROP) == NIL) "" else "s"));
            clib.printlist(@constCast("): "), DETROP);
            DETROP = NIL;
        }

        if (MISSING != NIL) {
            _ = clib.printf("missing parameter binding%s: ", @as([*:0]const u8, if (t(MISSING) == NIL) "" else "s"));
        }

        while (MISSING != NIL) {
            _ = clib.fprintf(getStderr().?, "%s%s", @as([*:0]const u8, @ptrFromInt(@as(usize, @intCast(h(h(MISSING)))))), @as([*:0]const u8, if (t(MISSING) == NIL) ";\n" else ","));
            MISSING = t(MISSING);
        }

        _ = clib.fprintf(getStderr().?, "compilation abandoned\n");
        stackp = dstack;
        includees_list = t(includees_list);
        return result;
    }

    if (tclashes != NIL) {
        _ = clib.fprintf(getStderr().?, "TYPECLASH - the following type%s multiply named:\n", @as([*:0]const u8, if (t(tclashes) == NIL) " is" else "s are"));
        while (tclashes != NIL) {
            _ = clib.fprintf(getStderr().?, "\'%s\' of file \"%s\", as: ", clib.getaka(h(t(h(tclashes)))), @as([*:0]const u8, @ptrFromInt(@as(usize, @intCast(h(h(tclashes)))))));
            clib.printlist(@constCast(""), alfasort(t(t(h(tclashes)))));
            tclashes = t(tclashes);
        }
        _ = clib.fprintf(getStderr().?, "typecheck cannot proceed - compilation abandoned\n");
        SYNERR = 1;
        return result;
    }

    return result;
}

export fn readoption() void {
    var f: Word = undefined;
    var t_val: Word = undefined;

    pfrts = NIL;
    tlost = NIL;

    if (FBS != NIL) {
        f = FBS;
        while (f != NIL) : (f = t(f)) {
            t_val = t(h(f));
            while (t_val != NIL) : (t_val = t(t_val)) {
                if (tag[@intCast(h(h(t_val)))] == clib.STRCONS and t(t(h(h(t_val)))) == type_t) {
                    pfrts = cons(h(h(t_val)), pfrts);
                }
            }
        }
    }

    var rfl_ptr = rfl;
    while (rfl_ptr != NIL) : (rfl_ptr = t(rfl_ptr)) {
        f = fil_defs(h(rfl_ptr));
        while (f != NIL) : (f = t(f)) {
            if (tag[@intCast(h(f))] == ID) {
                t_val = id_type(h(f));
                if (t_val == type_t) {
                    if (t_class(h(f)) == synonym_t) {
                        tp(t_info(h(f))).* = fixtype(t_info(h(f)), h(f));
                    }
                } else {
                    tp(h(h(f))).* = fixtype(t_val, h(f));
                }
            }
        }
    }

    if (tlost == NIL) return;
    TYPERRS += 1;
    _ = clib.printf("MISSING TYPENAME%s\n", if (t(tlost) == NIL) @as([*:0]const u8, "") else @as([*:0]const u8, "S"));
    _ = clib.printf("the following type%s no name in this scope:\n", if (t(tlost) == NIL) @as([*:0]const u8, " is needed but has") else @as([*:0]const u8, "s are needed but have"));
    while (tlost != NIL) {
        _ = clib.printf("\'%s\' of file \"%s\", needed by: ", @as([*:0]const u8, @ptrFromInt(@as(usize, @intCast(h(h(t_info(h(h(tlost))))))))), @as([*:0]const u8, @ptrFromInt(@as(usize, @intCast(h(t(t_info(h(h(tlost))))))))));
        clib.printlist(@constCast(""), alfasort(t(h(tlost))));
        tlost = t(tlost);
    }
}

fn fixtype(t_val: Word, x: Word) Word {
    switch (tag[@intCast(t_val)]) {
        AP, CONS => {
            tp(t_val).* = fixtype(t(t_val), x);
            hp(t_val).* = fixtype(h(t_val), x);
            return t_val;
        },
        clib.STRCONS => {
            if (clib.member(pfrts, t_val) != 0) {
                return t_val;
            }
            var cur_t = t_val;
            while (tag[@intCast(pn_val(cur_t))] != CONS) {
                cur_t = pn_val(cur_t);
            }
            if (tag[@intCast(cur_t)] != ID) {
                var w = tlost;
                while (w != NIL and h(h(w)) != cur_t) {
                    w = t(w);
                }
                if (w == NIL) {
                    tlost = cons(cons(cur_t, cons(x, NIL)), tlost);
                    w = tlost;
                }
                tp(h(w)).* = clib.add1(x, t(h(w)));
            }
            return cur_t;
        },
        else => return t_val,
    }
}

fn primdef(n: [*:0]const u8, v: Word, t_val: Word) void {
    const x = clib.make_id(@constCast(n));
    primenv = cons(x, primenv);
    tp(x).* = v;
    tp(h(x)).* = t_val;
}

fn predef(n: [*:0]const u8, v: Word, t_val: Word) void {
    const x = clib.make_id(@constCast(n));
    addtoenv(x);
    tp(x).* = if (isconstructor(x)) constructor(v, x) else v;
    tp(h(x)).* = t_val;
}

fn primlib() void {
    primdef("num", clib.make_typ(0, 0, synonym_t, clib.num_t), type_t);
    primdef("char", clib.make_typ(0, 0, synonym_t, clib.char_t), type_t);
    primdef("bool", clib.make_typ(0, 0, synonym_t, clib.bool_t), type_t);
    primdef("True", 1, clib.bool_t);
    primdef("False", 0, clib.bool_t);
}

fn privlib() void {
    predef("offside", clib.OFFSIDE, clib.ltchar);
    predef("changetype", clib.I, wrong_t);
    predef("first", clib.HD, wrong_t);
    predef("rest", clib.TL, wrong_t);
    predef("code", clib.CODE, undef_t);
    predef("concat", clib.ap2(clib.FOLDR, clib.APPEND, NIL), undef_t);
    predef("decode", clib.DECODE, undef_t);
    predef("drop", clib.DROP, undef_t);
    predef("error", clib.ERROR, undef_t);
    predef("filter", clib.FILTER, undef_t);
    predef("foldr", clib.FOLDR, undef_t);
    predef("hd", clib.HD, undef_t);
    predef("map", clib.MAP, undef_t);
    predef("shownum", clib.SHOWNUM, undef_t);
    predef("take", clib.TAKE, undef_t);
    predef("tl", clib.TL, undef_t);
}

fn stdlib() void {
    predef("arctan", clib.ARCTAN_FN, undef_t);
    predef("code", clib.CODE, undef_t);
    predef("cos", clib.COS_FN, undef_t);
    predef("decode", clib.DECODE, undef_t);
    predef("drop", clib.DROP, undef_t);
    predef("entier", clib.ENTIER_FN, undef_t);
    predef("error", clib.ERROR, undef_t);
    predef("exp", clib.EXP_FN, undef_t);
    predef("filemode", clib.FILEMODE, undef_t);
    predef("filestat", clib.FILESTAT, undef_t);
    predef("foldl", clib.FOLDL, undef_t);
    predef("foldl1", clib.FOLDL1, undef_t);
    predef("hugenum", sto_dbl(clib.DBL_MAX), undef_t);
    predef("last", clib.LIST_LAST, undef_t);
    predef("foldr", clib.FOLDR, undef_t);
    predef("force", clib.FORCE, undef_t);
    predef("getenv", clib.GETENV, undef_t);
    predef("integer", clib.INTEGER, undef_t);
    predef("log", clib.LOG_FN, undef_t);
    predef("log10", clib.LOG10_FN, undef_t);
    predef("merge", clib.MERGE, undef_t);
    predef("numval", clib.NUMVAL, undef_t);
    predef("read", clib.STARTREAD, undef_t);
    predef("readb", clib.STARTREADBIN, undef_t);
    predef("seq", clib.SEQ, undef_t);
    predef("shownum", clib.SHOWNUM, undef_t);
    predef("showhex", clib.SHOWHEX, undef_t);
    predef("showoct", clib.SHOWOCT, undef_t);
    predef("showfloat", clib.SHOWFLOAT, undef_t);
    predef("showscaled", clib.SHOWSCALED, undef_t);
    predef("sin", clib.SIN_FN, undef_t);
    predef("sqrt", clib.SQRT_FN, undef_t);
    predef("system", clib.EXEC, undef_t);
    predef("take", clib.TAKE, undef_t);
    predef("tinynum", mktiny(), undef_t);
    predef("zip2", clib.ZIP, undef_t);
}

export fn syntax(s: [*:0]const u8) void {
    if (SYNERR != 0) return;
    if (echoing != 0) {
        _ = clib.fprintf(getStderr().?, "\n");
    }
    _ = clib.fprintf(getStderr().?, "syntax error: %s", s);
    SYNERR = 1;
    reset_lex();
}

export fn acterror() void {
    if (SYNERR != 0) return;
    SYNERR = 1;
    reset_lex();
}

fn mira_setup() void {

    setupheap();
    tsetup();
    reset_pns();
    bigsetup();
    common_stdin = clib.ap(clib.READ, 0);
    common_stdinb = clib.ap(clib.READBIN, 0);
    cook_stdin = clib.ap(clib.readvals(0, 0), clib.OFFSIDE);
    nill = cons(clib.CONST, NIL);
    Void = clib.make_id(@constCast("()"));
    tp(h(Void)).* = clib.void_t;
    tp(Void).* = constructor(0, Void);
    message = clib.make_id(@constCast("sys_message"));
    main_id = clib.make_id(@constCast("main"));
    concat = clib.make_id(@constCast("concat"));
    diagonalise = clib.make_id(@constCast("diagonalise"));
    standardout = constructor(0, @as([*:0]const u8, "Stdout"));
    indent_fn = clib.make_id(@constCast("indent"));
    outdent_fn = clib.make_id(@constCast("outdent"));
    listdiff_fn = clib.make_id(@constCast("listdiff"));
    shownum1 = clib.make_id(@constCast("shownum1"));
    showbool = clib.make_id(@constCast("showbool"));
    showchar = clib.make_id(@constCast("showchar"));
    showlist = clib.make_id(@constCast("showlist"));
    showstring = clib.make_id(@constCast("showstring"));
    showparen = clib.make_id(@constCast("showparen"));
    showpair = clib.make_id(@constCast("showpair"));
    showvoid = clib.make_id(@constCast("showvoid"));
    showfunction = clib.make_id(@constCast("showfunction"));
    showabstract = clib.make_id(@constCast("showabstract"));
    showwhat = clib.make_id(@constCast("showwhat"));
    primlib();
}

export fn dieclean() void {
    _ = clib.fprintf(getStderr(), "<<...interrupt>>\n");
    clib.outstats();
    clib.exit(0);
}

export fn process() Word {
    var oldsig: usize = undefined;
    oldsig = signals(clib.SIGINT, 1);
    const pid = clib.fork();
    if (pid != 0) { // parent
        var status: c_int = 0;
        if (pid == -1) {
            clib.perror("UNIX error - cannot create process");
            return 0;
        }
        while (pid != clib.wait(&status)) {}
        if (WIFSIGNALED(status)) {
            const cd: [*:0]const u8 = if ((status & 0x80) != 0) " (core dumped)" else "";
            const sig = WTERMSIG(status);
            switch (sig) {
                clib.SIGBUS => _ = clib.fprintf(getStderr(), "\n<<...bus error%s>>\n", cd),
                clib.SIGSEGV => _ = clib.fprintf(getStderr(), "\n<<...segmentation fault%s>>\n", cd),
                else => _ = clib.fprintf(getStderr(), "\n<<...uncaught signal %d>>\n", sig),
            }
        }
        _ = signals(clib.SIGINT, oldsig);
        return 0;
    }
    return 1; // child
}

export fn fpe_error(sig: c_int) void {
    if (compiling != 0) {
        _ = signals(sig, @intFromPtr(&fpe_error));
        syntax("floating point number out of range\n");
        SYNERR = 0;
        clib.siglongjmp(&env, 1);
    } else {
        _ = clib.printf("\nFLOATING POINT OVERFLOW\n");
        clib.exit(1);
    }
}

fn main_entry(argc: c_int, argv: [*][*:0]u8) callconv(.c) c_int {
    var manonly: Word = 0;
    cstack = @ptrCast(&manonly);
    unlimit_stack();
    verbosity = if (clib.isatty(0) != 0) 1 else 0;
    clib.setbuf(getStdout(), null);

    const home = clib.getenv("HOME");
    var okhome_rc: Word = 0;
    if (home != null) {
        _ = clib.strcpy(&home_rc, home);
        if (clib.strcmp(&home_rc, "/") == 0) {
            home_rc[0] = 0;
        }
        _ = clib.strcat(&home_rc, "/.mirarc");
        okhome_rc = rc_read(@as([*:0]const u8, @ptrCast(&home_rc)));
    }

    UTF8 = utf8test();
    UTF8OUT = UTF8;

    var arg_idx: usize = 1;
    const argc_u = @as(usize, @intCast(argc));
    while (arg_idx < argc_u and argv[arg_idx][0] == '-') {
        const arg = argv[arg_idx];
        if (clib.strcmp(arg, "-stdenv") == 0) {
            nostdenv = 1;
        } else if (clib.strcmp(arg, "-count") == 0) {
            atcount = 1;
        } else if (clib.strcmp(arg, "-list") == 0) {
            listing = 1;
        } else if (clib.strcmp(arg, "-nolist") == 0) {
            listing = 0;
        } else if (clib.strcmp(arg, "-nostrictif") == 0) {
            strictif = 0;
        } else if (clib.strcmp(arg, "-gc") == 0) {
            atgc = 1;
        } else if (clib.strcmp(arg, "-object") == 0) {
            atobject = 1;
        } else if (clib.strcmp(arg, "-lib") == 0) {
            arg_idx += 1;
            if (arg_idx == argc_u) {
                missparam("lib");
            } else {
                miralib = argv[arg_idx];
            }
        } else if (clib.strcmp(arg, "-dic") == 0) {
            arg_idx += 1;
            if (arg_idx == argc_u) {
                missparam("dic");
            } else {
                var val: c_long = 0;
                if (clib.sscanf(argv[arg_idx], "%ld", &val) != 1 or badval(val)) {
                    _ = clib.fprintf(getStderr(), "mira: bad value after flag \"-dic\"\n");
                    clib.exit(1);
                }
                DICSPACE = val;
            }
        } else if (clib.strcmp(arg, "-heap") == 0) {
            arg_idx += 1;
            if (arg_idx == argc_u) {
                missparam("heap");
            } else {
                var val: c_long = 0;
                if (clib.sscanf(argv[arg_idx], "%ld", &val) != 1 or badval(val)) {
                    _ = clib.fprintf(getStderr(), "mira: bad value after flag \"-heap\"\n");
                    clib.exit(1);
                }
                SPACELIMIT = val;
            }
        } else if (clib.strcmp(arg, "-editor") == 0) {
            arg_idx += 1;
            if (arg_idx == argc_u) {
                missparam("editor");
            } else {
                editor = argv[arg_idx];
                fixeditor();
            }
        } else if (clib.strcmp(arg, "-hush") == 0) {
            verbosity = 0;
        } else if (clib.strcmp(arg, "-nohush") == 0) {
            verbosity = 1;
        } else if (clib.strcmp(arg, "-exp") == 0 or clib.strcmp(arg, "-log") == 0) {
            _ = clib.fprintf(getStderr(), "mira: obsolete flag \"%s\"\nuse \"-exec\" or \"-exec2\", see manual\n", arg);
            clib.exit(1);
        } else if (clib.strcmp(arg, "-exec") == 0) {
            ARGC = @intCast(argc - @as(c_int, @intCast(arg_idx)) - 1);
            ARGV = @ptrCast(argv + arg_idx + 1);
            magic = 1;
            verbosity = 0;
            arg_idx = argc_u;
            break;
        } else if (clib.strcmp(arg, "-exec2") == 0) {
            if (arg_idx + 1 >= argc_u) {
                _ = clib.fprintf(getStderr(), "incorrect use of -exec2 flag, missing filename\n");
                clib.exit(1);
            }
            const filename = argv[arg_idx + 1];
            var p = clib.strrchr(filename, '/');
            if (p == null) {
                p = filename;
            } else {
                p = p.? + 1;
            }
            const logfilname = @as(?[*:0]u8, @ptrCast(clib.malloc(clib.strlen(p.?) + 9)));
            if (logfilname == null) {
                clib.mallocfail(@constCast("logfile name"));
            }
            _ = clib.sprintf(logfilname.?, "miralog/%s", p.?);
            const fil = clib.fopen(logfilname.?, "a");
            if (fil != null) {
                _ = clib.dup2(clib.fileno(fil), 2);
            } else {
                _ = clib.fprintf(getStderr(), "could not open %s\n", logfilname.?);
            }
            ARGC = @intCast(argc - @as(c_int, @intCast(arg_idx)) - 1);
            ARGV = @ptrCast(argv + arg_idx + 1);
            magic = 1;
            verbosity = 0;
            arg_idx = argc_u;
            break;
        } else if (clib.strcmp(arg, "-man") == 0) {
            manonly = 1;
        } else if (clib.strcmp(arg, "-version") == 0) {
            v_info(0);
            clib.exit(0);
        } else if (clib.strcmp(arg, "-V") == 0) {
            v_info(1);
            clib.exit(0);
        } else if (clib.strcmp(arg, "-make") == 0) {
            making = 1;
            verbosity = 0;
        } else if (clib.strcmp(arg, "-exports") == 0) {
            making = 1;
            mkexports = 1;
            verbosity = 0;
        } else if (clib.strcmp(arg, "-sources") == 0) {
            making = 1;
            mksources = 1;
            verbosity = 0;
        } else if (clib.strcmp(arg, "-UTF-8") == 0) {
            UTF8 = 1;
        } else if (clib.strcmp(arg, "-noUTF-8") == 0) {
            UTF8 = 0;
        } else {
            _ = clib.fprintf(getStderr(), "mira: unknown flag \"%s\"\n", arg);
            clib.exit(1);
        }
        arg_idx += 1;

    }

    const remaining_argc = argc_u - arg_idx;
    if (remaining_argc > 1 and magic == 0 and making == 0) {
        _ = clib.fprintf(getStderr(), "mira: too many args\n");
        clib.exit(1);
    }

    var badlib: c_int = 0;
    if (miralib == null) {
        if (clib.getenv("MIRALIB")) |m| {
            miralib = @constCast(m);
        } else if (checkversion("/usr/lib/miralib") != 0) {
            miralib = @constCast("/usr/lib/miralib");
        } else if (checkversion("/usr/local/lib/miralib") != 0) {
            miralib = @constCast("/usr/local/lib/miralib");
        } else if (checkversion("miralib") != 0) {
            miralib = @constCast("miralib");
        } else {
            badlib = 1;
        }
    }

    if (badlib != 0) {
        _ = clib.fprintf(getStderr(), "fatal error: miralib version %s not found\n", strvers(@intCast(version)));
        libfails();
        clib.exit(1);
    }

    if (okhome_rc == 0) {
        if (rc_error == @as(?[*:0]const u8, @ptrCast(&lib_rc))) {
            rc_error = null;
        }
        _ = clib.strcpy(&lib_rc, miralib.?);
        _ = clib.strcat(&lib_rc, "/.mirarc");
        _ = rc_read(@as([*:0]const u8, @ptrCast(&lib_rc)));
    }

    if (editor == null) {
        if (clib.getenv("EDITOR")) |ed| {
            editor = @constCast(ed);
        } else {
            editor = @constCast(EDITOR);
        }
        if (editor != null) {
            _ = clib.strcpy(&ebuf, editor.?);
            editor = @as([*:0]u8, @ptrCast(&ebuf));
            fixeditor();
        }
    }

    if (clib.getenv("MIRAPROMPT")) |prs| {
        promptstr = prs;
    }

    if (clib.getenv("RECHECKMIRA") != null and rechecking == 0) {
        rechecking = 1;
    }

    if (clib.getenv("NOSTRICTIF") != null) {
        strictif = 0;
    }

    clib.setupdic();
    s_in = getStdin();
    s_out = getStdout();
    miralib = mkabsolute(miralib.?);

    if (manonly != 0) {
        manaction();
        clib.exit(0);
    }

    _ = clib.strcpy(&PRELUDE, miralib.?);
    _ = clib.strcat(&PRELUDE, "/prelude");

    _ = clib.strcpy(&STDENV, miralib.?);
    _ = clib.strcat(&STDENV, "/stdenv.m");

    mira_setup();

    if (verbosity != 0) {
        announce();
    }

    files = NIL;
    undump(@as([*:0]const u8, @ptrCast(&PRELUDE)));
    okprel = 1;
    clib.mkprivate(fil_defs(h(files)));
    files = NIL;

    if (nostdenv == 0) {
        undump(@as([*:0]const u8, @ptrCast(&STDENV)));
        while (files != NIL) {
            primenv = alfasort(clib.append1(primenv, fil_defs(h(files))));
            files = t(files);
        }
        primenv = alfasort(primenv);
        newtyps = NIL;
        files = NIL;
    }

    if (magic == 0) {
        rc_write();
    }

    echoing = verbosity & listing;
    initialising = 0;

    if (mkexports != 0) {
        const arg_count: usize = remaining_argc;
        var s: [*:0]u8 = undefined;
        _ = clib.sigsetjmp(&env, 1);
        var cur_argv_idx = arg_idx;
        while (cur_argv_idx < argc_u) : (cur_argv_idx += 1) {
            var x: Word = NIL;
            s = clib.addextn(1, argv[cur_argv_idx]);
            if (s == dicp) {
                _ = clib.keep(dicp);
            }
            undump(s);
            if (files == NIL or ND != NIL) {
                continue;
            }
            if (arg_count != 1) {
                _ = clib.printf("%s\n", s);
            }
            if (exports != NIL) {
                x = exports;
            } else {
                var f = files;
                while (f != NIL) : (f = t(f)) {
                    x = clib.append1(fil_defs(h(f)), x);
                }
            }

            if (freeids != NIL) {
                var f = freeids;
                while (f != NIL) : (f = t(f)) {
                    const n = clib.findid(@constCast(get_id(h(f))));
                    tp(n).* = t(t(h(f)));
                    tp(h(h(n))).* = the_val(h(h(f)));
                    hp(f).* = n;
                }
                freeids = clib.typesfirst(freeids);
                f = freeids;
                _ = clib.printf("\t%%free {\n");
                while (f != NIL) : (f = t(f)) {
                    _ = clib.putchar('\t');
                    clib.report_type(h(f));
                    _ = clib.putchar('\n');
                }
                _ = clib.printf("\t}\n");
            }

            var item = clib.typesfirst(alfasort(x));
            while (item != NIL) : (item = t(item)) {
                _ = clib.putchar('\t');
                clib.report_type(h(item));
                _ = clib.putchar('\n');
            }
        }
        clib.exit(0);
    }

    if (mksources != 0) {
        var s: [*:0]u8 = undefined;
        var x: Word = NIL;
        _ = clib.sigsetjmp(&env, 1);
        var cur_argv_idx = arg_idx;
        while (cur_argv_idx < argc_u) : (cur_argv_idx += 1) {
            s = clib.addextn(1, argv[cur_argv_idx]);
            if (fileExists(s)) {
                if (s == dicp) {
                    _ = clib.keep(dicp);
                }
                undump(s);
                var f = if (files == NIL) oldfiles else files;
                while (f != NIL) : (f = t(f)) {
                    const filename_str = get_fil(h(f)).?;
                    if (clib.member(x, @intCast(@intFromPtr(filename_str))) == 0) {
                        x = cons(@intCast(@intFromPtr(filename_str)), x);
                        _ = clib.printf("%s\n", filename_str);
                    }
                }
            }
        }
        clib.exit(0);
    }

    if (making != 0) {
        var s: [*:0]u8 = undefined;
        _ = clib.sigsetjmp(&env, 1);
        var cur_argv_idx = arg_idx;
        while (cur_argv_idx < argc_u) : (cur_argv_idx += 1) {
            s = clib.addextn(1, argv[cur_argv_idx]);
            if (s == dicp) {
                _ = clib.keep(dicp);
            }
            undump(s);
            if (ND != NIL or (files == NIL and oldfiles != NIL)) {
                if (make_status == 1) {
                    make_status = 0;
                }
                make_status = clib.strcons(@as(Word, @intCast(@intFromPtr(s))), make_status);
            }
        }
        if (tag[@intCast(make_status)] == clib.STRCONS) {
            var h_val: Word = 0;
            var maxw: Word = 0;
            _ = clib.printf("errors or undefined names found in:-\n");
            while (make_status != 0) {
                h_val = clib.strcons(h(make_status), h_val);
                const w = @as(Word, @intCast(clib.strlen(@ptrFromInt(@as(usize, @intCast(h(h_val)))))));
                if (w > maxw) {
                    maxw = w;
                }
                make_status = t(make_status);
            }
            maxw += 1;
            const n = @divTrunc(@as(Word, 78), maxw);
            var w: Word = 0;
            while (h_val != 0) {
                w += 1;
                _ = clib.printf("%*s%s", @as(c_int, @intCast(maxw)), @as([*:0]const u8, @ptrFromInt(@as(usize, @intCast(h(h_val))))), @as([*:0]const u8, if ((@rem(w, n)) != 0) "" else "\n"));
                h_val = t(h_val);
            }
            if ((@rem(w, n)) != 0) {
                _ = clib.printf("\n");
            }
            make_status = 1;
        }
        clib.exit(@intCast(make_status));
    }

    var initscript: [*:0]const u8 = undefined;
    if (remaining_argc == 0) {
        initscript = "script.m";
    } else if (magic != 0) {
        initscript = argv[arg_idx];
    } else {
        initscript = clib.addextn(1, argv[arg_idx]);
    }

    if (initscript == dicp) {
        _ = clib.keep(dicp);
    }

    _ = signals(clib.SIGFPE, @intFromPtr(&fpe_error));
    _ = signals(clib.SIGTERM, @intFromPtr(&clib.exit));
    commandloop(@constCast(initscript));
    return 0;
}

fn unlimit_stack() void {
    var rlimit: clib.struct_rlimit = undefined;
    if (clib.getrlimit(clib.RLIMIT_STACK, &rlimit) == 0) {
        rlimit.rlim_cur = rlimit.rlim_max;
        _ = clib.setrlimit(clib.RLIMIT_STACK, &rlimit);
    }
}

inline fn pn_val(x: Word) Word {
    return t(x);
}

export fn alfasort(x_val: Word) Word {
    var x = x_val;
    var a = NIL;
    var b = NIL;
    var hold = NIL;
    if (x == NIL) {
        return NIL;
    }
    if (t(x) == NIL) {
        return if (tag[@intCast(h(x))] != ID) NIL else x;
    }
    while (x != NIL) {
        if (tag[@intCast(h(x))] == ID) {
            hold = a;
            a = cons(h(x), b);
            b = hold;
        }
        x = t(x);
    }
    a = alfasort(a);
    b = alfasort(b);
    x = NIL;
    while (a != NIL and b != NIL) {
        if (clib.strcmp(get_id(h(a)), get_id(h(b))) < 0) {
            x = cons(h(a), x);
            a = t(a);
        } else {
            x = cons(h(b), x);
            b = t(b);
        }
    }
    if (a == NIL) {
        a = b;
    }
    while (a != NIL) {
        x = cons(h(a), x);
        a = t(a);
    }
    return reverse(x);
}

fn utf8test() c_int {
    var lang = clib.getenv("LC_CTYPE");
    if (lang == null) {
        lang = clib.getenv("LANG");
    }
    if (lang) |l| {
        if (clib.strstr(l, "UTF-8") != null or
            clib.strstr(l, "UTF8") != null or
            clib.strstr(l, "utf-8") != null or
            clib.strstr(l, "utf8") != null)
        {
            return 1;
        }
    }
    return 0;
}

fn undump(t_val: [*:0]const u8) void {
    var obf: [pnlim]u8 = undefined;
    var f: ?*clib.FILE = null;
    var flen: Word = undefined;
    var t1: clib.time_t = undefined;
    var t2: clib.time_t = undefined;
    var oldsig: usize = 0;

    if (normal(t_val) == 0 and initialising == 0) {
        loadfile(t_val);
        return;
    }

    flen = @intCast(clib.strlen(t_val));
    t1 = @intCast(fm_time(t_val));
    if (flen > pnlim) {
        _ = clib.printf("sorry, pathname too long (limit=%d): %s\n", pnlim, t_val);
        return;
    }

    _ = clib.strcpy(&obf, t_val);
    _ = clib.strcpy(obf[@intCast(flen - 1)..].ptr, obsuffix);
    t2 = @intCast(fm_time(@as([*:0]const u8, @ptrCast(&obf))));
    if (t2 != 0 and t1 == 0) {
        t2 = 0;
        _ = clib.unlink(&obf);
    }
    if (t2 == 0 or t2 < t1) {
        loadfile(t_val);
        return;
    }

    f = clib.fopen(&obf, "r");
    if (f == null) {
        _ = clib.printf("cannot open %s\n", @as([*:0]const u8, @ptrCast(&obf)));
        loadfile(t_val);
        return;
    }

    current_script = @constCast(t_val);
    loading = 1;
    oldfiles = NIL;
    unload();

    if (initialising == 0 and making == 0) {
        sigflag = 0;
        oldsig = signals(clib.SIGINT, @intFromPtr(&sigdefer));
    }

    files = clib.load_script(f.?, @constCast(t_val), NIL, NIL, if (making == 0 and initialising == 0) 1 else 0);
    _ = clib.fclose(f.?);

    if (BAD_DUMP != 0) {
        _ = clib.unlink(&obf);
        unload();
        CLASHES = NIL;
        stackp = dstack;
        _ = clib.printf("warning: %s contains incorrect data (file removed)\n", @as([*:0]const u8, @ptrCast(&obf)));
        if (BAD_DUMP == -1) {
            _ = clib.printf("(unrecognised dump format)\n");
        } else if (BAD_DUMP == 1) {
            _ = clib.printf("(wrong source file)\n");
        } else {
            _ = clib.printf("(error %ld)\n", BAD_DUMP);
        }
    }

    if (initialising == 0 and making == 0) {
        _ = signals(clib.SIGINT, oldsig);
    }
    if (sigflag != 0) {
        sigflag = 0;
        if (oldsig > 1) {
            const handler: *const fn (c_int) callconv(.c) void = @ptrFromInt(oldsig);
            handler(clib.SIGINT);
        }
    }

    if (CLASHES != NIL) {
        if (ideep == 0) {
            _ = clib.printf("cannot load %s ", @as([*:0]const u8, @ptrCast(&obf)));
            clib.printlist(@constCast("due to name clashes: "), alfasort(CLASHES));
        }
        unload();
        loading = 0;
        return;
    }

    if (BAD_DUMP != 0 or src_update() != 0) {
        loadfile(t_val);
    } else if (initialising != 0) {
        if (ND != NIL or files == NIL) {
            _ = clib.fprintf(getStderr(), "panic: %s contains errors\n", @as([*:0]const u8, @ptrCast(&obf)));
            clib.exit(1);
        }
    } else {
        if (verbosity != 0 or magic != 0 or mkexports != 0) {
            if (files == NIL) {
                _ = clib.printf("%s contains syntax error\n", t_val);
            } else {
                if (ND != NIL) {
                    _ = clib.printf("%s contains undefined names or type errors\n", t_val);
                } else if (making == 0 and magic == 0) {
                    _ = clib.printf("%s\n", t_val);
                }
            }
        }
    }

    if (files != NIL and making == 0 and initialising == 0) {
        unfixexports();
    }
    loading = 0;
}

fn missparam(s: [*:0]const u8) void {
    _ = clib.fprintf(getStderr(), "mira: missing param after flag \"-%s\"\n", s);
    clib.exit(1);
}

fn makedump() void {
    const obf = &linebuf;
    var f: ?*clib.FILE = null;
    _ = clib.strcpy(obf, current_script.?);
    const len = clib.strlen(obf);
    _ = clib.strcpy(obf[len - 1 ..].ptr, obsuffix);
    f = clib.fopen(obf, "w");
    if (f == null) {
        _ = clib.printf("WARNING: CANNOT WRITE TO %s\n", @as([*:0]const u8, @ptrCast(obf)));
        if (clib.strcmp(current_script.?, &PRELUDE) == 0 or clib.strcmp(current_script.?, &STDENV) == 0) {
            _ = clib.printf("TO FIX THIS PROBLEM PLEASE GET SUPER-USER TO EXECUTE `mira'\n");
        }
        if (making != 0 and make_status == 0) {
            make_status = 1;
        }
        return;
    }
    unlinkme = @ptrCast(obf);
    clib.setprefix(current_script.?);
    clib.dump_script(files, f.?);
    unlinkme = null;
    _ = clib.fclose(f.?);
}

fn mkabsolute(m: [*:0]u8) [*:0]u8 {
    if (m[0] == '/') {
        return m;
    }
    if (clib.getcwd(dicp, pnlim) == null) {
        _ = clib.fprintf(getStderr(), "panic: cwd too long\n");
        clib.exit(1);
    }
    _ = clib.strcat(dicp, "/");
    _ = clib.strcat(dicp, m);
    const m_new = dicp;
    dicq += clib.strlen(dicp) + 1;
    dicp = dicq;
    dic_check();
    return m_new;
}

fn addtoenv(x: Word) void {
    tp(h(files)).* = cons(x, t(h(files)));
}

pub fn main(ctx: std.process.Init) !void {
    const raw_args = ctx.minimal.args.vector;
    const argv: [*][*:0]u8 = @ptrCast(@constCast(raw_args.ptr));
    const argc: c_int = @intCast(raw_args.len);
    const exit_code = main_entry(argc, argv);
    std.process.exit(@intCast(exit_code));
}

comptime {
    _ = @import("runtime/heap.zig");
    _ = @import("runtime/reduce.zig");
    _ = @import("runtime/combinator.zig");
    _ = @import("runtime/big.zig");
    _ = @import("parser/lex.zig");
    _ = @import("parser/parser_tests.zig");
    _ = @import("compiler/trans.zig");
    _ = @import("compiler/types.zig");
    _ = @import("io/utf8.zig");
    _ = @import("io/signals.zig");
    _ = @import("version.zig");
}
