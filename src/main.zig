// TODO: Phase 7 - Idiomatic Zig Modernization:
// - Step 1: Split monolithic main.zig into logical driver/compiler/filesystem modules.
// - Step 2: Introduce RuntimeState struct to group global static variables.
// - Step 5: Replace integer flags (compiling, echoing, listing, etc.) with booleans.

const std = @import("std");
const platform = @import("io/platform.zig");
const parser_api = @import("parser/parser_api.zig");

const word_mod = @import("runtime/word.zig");

const clib = @import("runtime/main_clib.zig");
const setup = @import("compiler/setup.zig");
const module_loader = @import("compiler/module_loader.zig");

pub inline fn get_id(x: Word) [*:0]const u8 {
    return @ptrFromInt(@as(usize, @intCast(h(h(h(x))))));
}

pub inline fn get_fil(fil: Word) ?[*:0]const u8 {
    const val = h(h(h(fil)));
    if (val == 0) return null;
    return @ptrFromInt(@as(usize, @intCast(val)));
}

pub const Word = c_long;
pub const CONS: u8 = 11;
pub const AP: u8 = 9;
pub const CMBASE: Word = 306;
pub const NIL: Word = CMBASE + 138;
pub const ATOMLIMIT: Word = CMBASE + 141;

extern var hd: [*]Word;
extern var tl: [*]Word;
extern var tag: [*]u8;

pub extern var s_out: ?*clib.FILE;
extern var dstack: ?[*]Word;
extern var stackp: ?[*]Word;

pub extern var dicp: [*:0]u8;
pub extern var dicq: [*:0]u8;
pub extern var dic: ?[*]u8;

pub extern var version: c_int;
pub extern var vdate: [*:0]const u8;
pub extern var host: [*:0]const u8;

extern var blankerr: c_int;
pub extern var ARGC: c_int;
pub extern var ARGV: [*]?[*:0]u8;

pub extern var current_id: Word;
extern var ATNAMES: Word;
extern var lineptr: Word;

pub extern var lfrule: c_int;

// Global variables exported to C
pub export var nill: Word = 0;
pub export var Void: Word = 0;
pub var main_id: Word = 0;
pub export var message: Word = 0;
pub export var standardout: Word = 0;
pub export var diagonalise: Word = 0;
pub export var concat: Word = 0;
pub export var indent_fn: Word = 0;
pub export var outdent_fn: Word = 0;
pub export var listdiff_fn: Word = 0;
pub export var shownum1: Word = 0;
pub export var showbool: Word = 0;
pub export var showchar: Word = 0;
pub export var showlist: Word = 0;
pub export var showstring: Word = 0;
pub export var showparen: Word = 0;
pub export var showpair: Word = 0;
pub export var showvoid: Word = 0;
pub export var showfunction: Word = 0;
pub export var showabstract: Word = 0;
pub export var showwhat: Word = 0;

pub var PRELUDE: [clib.pnlim + 10]u8 = undefined;
pub var STDENV: [clib.pnlim + 9]u8 = undefined;
var vstack: [4]c_int = undefined;
var mstack: [4][*:0]const u8 = undefined;
var mvp: usize = 0;
var vbuf: [12]u8 = undefined;
pub export var loading: c_int = 0;
extern var BAD_DUMP: Word;
extern var CLASHES: Word;
extern var col: Word;
extern var DETROP: Word;
extern var MISSING: Word;
extern var ALIASES: Word;
extern var TSUPPRESSED: Word;
pub export var fnts: Word = NIL;

pub extern fn signals(signum: c_int, handler: usize) usize;
pub extern fn dieclean() void;
pub extern fn fpe_error(sig: c_int) void;
pub extern fn commandloop(initscript: [*:0]u8) void;
pub extern fn main_entry(argc: c_int, argv: [*][*:0]u8) callconv(.c) c_int;

pub export var SPACELIMIT: Word = 2500000;
pub export var DICSPACE: Word = 100000;
pub export var UTF8: c_int = 0;
pub export var UTF8OUT: c_int = 0;
pub export var editor: ?[*:0]u8 = null;
pub var okprel: Word = 0;
pub var nostdenv: Word = 0;
pub export var baded: Word = 0;
pub export var miralib: ?[*:0]u8 = null;
pub var promptstr: [*:0]const u8 = "Miranda ";
pub export var obsuffix: [*:0]const u8 = "x";
pub export var s_in: ?*clib.FILE = null;
pub export var commandmode: Word = 0;
pub var atobject: c_int = 0;
pub export var atgc: c_int = 0;
pub export var atcount: c_int = 0;
export var debug: c_int = 0;
pub export var magic: Word = 0;
pub var making: Word = 0;
pub var mkexports: Word = 0;
pub var mksources: Word = 0;
pub export var make_status: Word = 0;
pub export var compiling: c_int = 1;
pub export var ideep: c_int = 0;
pub export var SYNERR: Word = 0;
pub export var initialising: Word = 1;
pub export var primenv: Word = NIL;
pub export var current_script: ?[*:0]u8 = null;
export var lastexp: Word = clib.UNDEF;
pub export var echoing: Word = 0;
pub export var listing: Word = 0;
pub export var verbosity: Word = 0;
pub export var strictif: Word = 1;
pub export var rechecking: Word = 0;
pub export var errline: Word = 0;
pub export var errs: Word = 0;
pub export var cstack: ?[*]Word = null;
pub export var linebuf: [clib.BUFSIZE]u8 = undefined;
pub export var ebuf: [clib.pnlim]u8 = undefined;
pub export var home_rc: [clib.pnlim + 8]u8 = undefined;
pub export var lib_rc: [clib.pnlim + 8]u8 = undefined;
pub export var rc_error: ?[*:0]const u8 = null;

pub var env: clib.sigjmp_buf = undefined;
var unlinkme: ?[*:0]const u8 = null;
pub export var sorted: c_int = 0;
pub export var detrop: Word = NIL;
pub export var rfl: Word = NIL;
pub export var bereaved: Word = 0;
pub export var ld_stuff: Word = NIL;
pub var sigflag: c_int = 0;
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

pub extern var files: Word;
pub extern var current_file: Word;
extern var collecting: Word;
pub export var oldfiles: Word = NIL;
pub export var includees: Word = NIL;
pub export var freeids: Word = NIL;
pub export var exports: Word = NIL;
extern var exportfiles: Word;
pub export var embargoes: Word = NIL;
pub extern var newtyps: Word;
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
pub extern var ND: Word;
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

pub fn h(x: Word) Word {
    if (x < ATOMLIMIT) return 0;
    return hd[@as(usize, @intCast(x)) * 2];
}

pub fn t(x: Word) Word {
    if (x < ATOMLIMIT) return 0;
    return tl[@as(usize, @intCast(x)) * 2];
}

pub fn hp(x: Word) *Word {
    return &hd[@as(usize, @intCast(x)) * 2];
}

pub fn tp(x: Word) *Word {
    return &tl[@as(usize, @intCast(x)) * 2];
}

pub fn cons(x: Word, y: Word) Word {
    return clib.make(clib.CONS, x, y);
}

// Token names for out2(): replaces y.tab.c's yysterm[].
// Index i corresponds to lexical token (256 + i).
const yysterm_data = [_]?[*:0]const u8{
    null, // 0: placeholder (no token 256)
    "VALUE", // 1: 257
    "EVAL", // 2: 258
    "where", // 3: WHERE=259
    "if", // 4: IF=260
    "&>", // 5: 261
    "<-", // 6: LEFTARROW=262
    "::", // 7: COLONCOLON=263
    "::=", // 8: COLON2EQ=264
    "TYPEVAR", // 9: TYPEVAR=265
    "NAME", // 10: NAME=266
    "CONSTRUCTOR-NAME", // 11: CNAME=267
    "CONST", // 12: CONST=268
    "$$", // 13: DOLLARS=269
    "OFFSIDE", // 14: OFFSIDE=270
    "OFFSIDE =", // 15: ELSEQ=271
    "abstype", // 16: ABSTYPE=272
    "with", // 17: WITH=273
    "//", // 18: 274
    "==", // 19: EQEQ=275
    "%free", // 20: FREE=276
    "%include", // 21: INCLUDE=277
    "%export", // 22: EXPORT=278
    "type", // 23: TYPE=279
    "otherwise", // 24: OTHERWISE=280
    "show", // 25: SHOWSYM=281
    "PATHNAME", // 26: PATHNAME=282
    "%bnf", // 27: BNF=283
    "%lex", // 28: LEX=284
    "%%", // 29: 285
    "error", // 30: 286
    "end", // 31: 287
    "empty", // 32: 288
    "readvals", // 33: READVALSY=289
    "NAME", // 34: 290
    "`char-class`", // 35: 291
    "`char-class`", // 36: 292
    "%%begin", // 37: 293
    "->", // 38: ARROW=294
    "++", // 39: PLUSPLUS=295
    "--", // 40: MINUSMINUS=296
    "..", // 41: DOTDOT=297
    "\\/", // 42: VEL=298
    ">=", // 43: GE=299
    "~=", // 44: NE=300
    "<=", // 45: LE=301
    "mod", // 46: REM=302
    "div", // 47: DIV=303
    "$NAME", // 48: INFIXNAME=304
    "$CONSTRUCTOR", // 49: INFIXCNAME=305
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
            clib.make(AP, clib.mkshow(0, 0, typ), x);
        break :blk clib.make(CONS, clib.make(AP, standardout, inner), NIL);
    };
    clib.output(out_val);
}

// Equivalent of y.tab.c evaluate(): type-check, fork a child to reduce and print,
// then wait for the child in the parent.  The parent's heap/type state is preserved.
// Called from parser_api.parseCurrent() in command mode.
export fn evaluate_repl(x_in: Word) void {
    var x = x_in;
    const typ = clib.type_of(x);
    if (typ == clib.wrong_t) return;
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
            clib.make(AP, clib.mkshow(0, 0, typ), x);
        break :blk clib.make(CONS, clib.make(AP, standardout, inner), NIL);
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

pub inline fn getStdin() ?*clib.FILE {
    return clib.stdin();
}
pub inline fn getStdout() ?*clib.FILE {
    return clib.stdout();
}
pub inline fn getStderr() ?*clib.FILE {
    return clib.stderr();
}

pub fn fil_time(fil: Word) Word {
    return t(h(h(fil)));
}

pub fn fil_share(fil: Word) Word {
    return h(t(h(fil)));
}

pub fn fil_inodev(fil: Word) Word {
    return t(t(h(fil)));
}

pub fn fil_defs(fil: Word) Word {
    return t(fil);
}

pub inline fn dval(d: Word) Word {
    return t(t(d));
}

pub inline fn dlhs(d: Word) Word {
    return h(d);
}

pub fn get_here(x: Word) Word {
    return clib.get_here(x);
}

pub fn the_val(x: Word) Word {
    return t(x);
}

pub fn t_class(x: Word) Word {
    return h(t(the_val(x)));
}

pub fn t_info(x: Word) Word {
    return t(t(the_val(x)));
}

pub fn id_val(x: Word) Word {
    return t(x);
}

pub fn id_type(x: Word) Word {
    return t(h(x));
}

pub fn id_who(x: Word) Word {
    return t(h(h(x)));
}

pub fn same_file(x: Word, y: Word) bool {
    const ix = fil_inodev(x);
    const iy = fil_inodev(y);
    return h(ix) == h(iy) and t(ix) == t(iy);
}

pub fn inodev(path: [*:0]const u8) Word {
    if (platform.getFileInfo(path)) |info| {
        return clib.datapair(@as(Word, @bitCast(info.ino)), @as(Word, @bitCast(info.dev)));
    } else {
        return clib.datapair(0, -1);
    }
}

pub fn fileExists(path: [*:0]const u8) bool {
    return platform.getFileInfo(path) != null;
}

pub fn badval(x: Word) bool {
    if (@sizeOf(Word) == 4) {
        return (x < 1 or x > 350000000);
    } else {
        return (x < 1 or x > 50000000000);
    }
}

pub fn isfreeid(x: Word) bool {
    return if (id_type(x) == clib.type_t) t_class(x) == clib.free_t else id_val(x) == clib.FREE;
}

pub fn isconstructor(x: Word) bool {
    return tag[@intCast(x)] == clib.ID and isconstrname(get_id(x)) != 0;
}

pub fn isvariable(x: Word) bool {
    return tag[@intCast(x)] == clib.ID and isconstrname(get_id(x)) == 0;
}

pub fn make_fil(name: ?[*:0]const u8, time: Word, share: Word, defs: Word) Word {
    const name_word = @as(Word, @intCast(@intFromPtr(name)));
    const fil_info = clib.make(clib.FILEINFO, name_word, time);
    return cons(cons(fil_info, cons(share, NIL)), defs);
}

pub fn constructor(n: Word, x: anytype) Word {
    const x_val: Word = switch (@TypeOf(x)) {
        Word => x,
        c_int, c_uint => @intCast(x),
        [*:0]const u8, [*:0]u8 => @intCast(@intFromPtr(x)),
        else => @compileError("Unsupported type for constructor"),
    };
    return clib.make(clib.CONSTRUCTOR, n, x_val);
}

pub const EDITOR = "vi +!";

pub export fn fm_time(path: [*:0]const u8) Word {
    if (platform.getFileInfo(path)) |info| {
        return @intCast(info.mtime);
    } else {
        return 0;
    }
}

pub export fn normal(path: [*:0]const u8) c_int {
    const text = std.mem.span(path);
    return if (text.len >= 2 and std.mem.eql(u8, text[text.len - 2 ..], ".m")) 1 else 0;
}

pub export fn reverse(input: Word) Word {
    var x = input;
    var y: Word = NIL;
    while (x != NIL) {
        y = cons(h(x), y);
        x = t(x);
    }
    return y;
}

pub export fn shunt(input_x: Word, input_y: Word) Word {
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

pub export fn filecopy(path: [*:0]const u8) void {
    const fd = clib.open(path, clib.O_RDONLY, 0);
    if (fd < 0) return;
    defer _ = clib.close(fd);

    var buffer: [512]u8 = undefined;
    while (true) {
        const n = clib.read(fd, &buffer, buffer.len);
        if (n <= 0) break;
        _ = clib.write(clib.STDOUT_FILENO, &buffer, @intCast(n));
    }
}

pub export fn filecp(from: [*:0]const u8, to: [*:0]const u8) void {
    const f_in = clib.open(from, clib.O_RDONLY, 0);
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

pub export fn twidth() c_int {
    var window: clib.struct_winsize = undefined;
    if (clib.ioctl(clib.STDOUT_FILENO, clib.TIOCGWINSZ, &window) == -1 or window.ws_col == 0) {
        return 78;
    }
    return @as(c_int, @intCast(window.ws_col)) - 2;
}

pub export fn mktiny() Word {
    var x: f64 = 1.0;
    var x1: f64 = x / 2.0;
    while (x1 > 0.0) {
        x = x1;
        x1 = x1 / 2.0;
    }
    return clib.sto_dbl(x);
}

pub export fn checkversion(m: [*:0]const u8) c_int {
    var path_buf: [1024]u8 = undefined;
    const path = std.fmt.bufPrintZ(&path_buf, "{s}/.version", .{m}) catch return 0;
    const f = clib.fopen(path.ptr, "r");
    var v1: c_uint = 0;
    var read_ok: bool = false;
    var r: c_int = 0;
    if (f != null) {
        if (clib.fscanf(f, "%u", .{&v1}) == 1) {
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

pub export fn libfails() void {
    const stderr = getStderr().?;
    _ = clib.fprintf(stderr, "found", .{.{}});
    var i: usize = 0;
    while (i < mvp) : (i += 1) {
        _ = clib.fprintf(stderr, "\tversion %s at: %s\n", .{.{strvers(vstack[i]), mstack[i]}});
    }
}

pub export fn strvers(v: c_int) [*:0]const u8 {
    if (v < 0 or v > 999999) {
        return "???";
    }
    _ = clib.snprintf(&vbuf, vbuf.len, "%.3f", .{@as(f64, @floatFromInt(v)) / 1000.0});
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
    while (d != NIL and d != 0) : (d = t(d)) {
        const item = h(d);
        if (tag[@intCast(item)] == clib.ID) {
            tp(item).* = clib.UNDEF;
            tp(h(h(item))).* = NIL;
            tp(h(item)).* = clib.undef_t;
        }
    }
}

pub export fn unload() void {
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
    while (files != NIL and files != 0) : (files = t(files)) {
        const fil = h(files);
        unsetids(t(fil));
        tp(fil).* = NIL;
    }
    var ld = ld_stuff;
    while (ld != NIL and ld != 0) : (ld = t(ld)) {
        var x = h(ld);
        while (x != NIL and x != 0) : (x = t(x)) {
            unsetids(t(h(x)));
        }
    }
    ld_stuff = NIL;
}

pub export fn getln(in: ?*clib.FILE, n_val: Word, s_ptr: [*]u8) c_int {
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

pub export fn fixeditor() void {
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

pub export fn rc_read(rcfile: [*:0]const u8) Word {
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

    if (clib.fscanf(in.?, "%19s", .{@as([*c]u8, @ptrCast(&z))}) != 1) {
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
        if (clib.fscanf(in.?, "%ld%ld%ld%*c", .{&h_val, &d_val, &v_val}) != 3 or getln(in.?, clib.pnlim - 1, @as([*]u8, @ptrCast(&ebuf))) == 0 or badval(h_val) or badval(d_val) or badval(v_val)) {
            rc_error = rcfile;
        } else {
            editor = @ptrCast(&ebuf);
            SPACELIMIT = h_val;
            DICSPACE = d_val;
            r = 1;
            oldversion = @intCast(v_val);
        }
    } else if (std.mem.eql(u8, z_slice, "ehdsv")) {
        if (clib.fscanf(in.?, "%19s%ld%ld%ld%ld", .{@as([*c]u8, @ptrCast(&ebuf)), &h_val, &d_val, &s_val, &v_val}) != 5 or badval(h_val) or badval(d_val) or badval(v_val)) {
            rc_error = rcfile;
        } else {
            editor = @ptrCast(&ebuf);
            SPACELIMIT = h_val;
            DICSPACE = d_val;
            r = 1;
            oldversion = @intCast(v_val);
        }
    } else if (std.mem.eql(u8, z_slice, "ehds")) {
        if (clib.fscanf(in.?, "%s%ld%ld%ld", .{@as([*c]u8, @ptrCast(&ebuf)), &h_val, &d_val, &s_val}) != 4 or badval(h_val) or badval(d_val)) {
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

pub export fn rc_write() void {
    const out = clib.fopen(@ptrCast(&home_rc), "w");
    if (out == null) {
        const stderr = getStderr().?;
        _ = clib.fprintf(stderr, "warning: cannot write to \"%s\"\n", .{.{@as([*:0]const u8, @ptrCast(&home_rc))}});
        return;
    }
    defer _ = clib.fclose(out.?);

    _ = clib.fprintf(out.?, "hdve", .{.{}});
    if (listing != 0) {
        _ = clib.fputc('l', out.?);
    }
    if (rechecking == 2) {
        _ = clib.fputc('r', out.?);
    }
    _ = clib.fprintf(out.?, " %ld %ld %d %s\n", .{.{SPACELIMIT, DICSPACE, version, editor orelse @constCast("")}});
}

export var oldversion: c_int = 0;

pub fn announce() void {
    const w = @divTrunc(twidth() - 50, 2);
    _ = clib.printf("\n\n", .{.{}});
    spaces(w);
    _ = clib.printf("   T h e   M i r a n d a   S y s t e m\n\n", .{.{}});
    spaces(w + 5 - @divTrunc(@as(Word, @intCast(clib.strlen(vdate))), 2));
    _ = clib.printf("  version %s last revised %s\n\n", .{.{strvers(version), vdate}});
    spaces(w);
    _ = clib.printf("Copyright Research Software Ltd 1985-2020\n\n", .{.{}});
    spaces(w);
    _ = clib.printf("  World Wide Web: http://miranda.org.uk\n\n\n", .{.{}});
    if (SPACELIMIT != 2500000) {
        _ = clib.printf("(%ld cells)\n", .{.{SPACELIMIT}});
    }
    if (strictif == 0) {
        _ = clib.printf("(-nostrictif : deprecated!)\n", .{.{}});
    }
    if (oldversion < 1999) {
        _ = clib.printf("WARNING:\na new release of Miranda has been installed since you last used\nthe system - please read the `CHANGES' section of the /man pages !!!\n\n", .{.{}});
    } else if (version > oldversion) {
        _ = clib.printf("a new version of Miranda has been installed since you last\nused the system - see under `CHANGES' in the /man pages\n\n", .{.{}});
    }
    if (version < oldversion) {
        _ = clib.printf("warning - this is an older version of Miranda than the one\nyou last used on this machine!!\n\n", .{.{}});
    }
    if (rc_error) |rc_err| {
        _ = clib.printf("warning: \"%s\" contained bad data (ignored)\n", .{.{rc_err}});
    }
}

pub export var lastid: Word = 0;
pub export var rv_expr: Word = 0;



export fn parseline(t_val: Word, f: ?*clib.FILE, fil: Word) Word {
    var t1: Word = undefined;
    var ch: c_int = undefined;
    lastexp = clib.UNDEF;
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
        c = clib.VALUE;
        echoing = 0;
        commandmode = 1;
        s_in = f;
        _ = parser_api.parseCurrent() catch {};
        s_in = getStdin();
        if (SYNERR != 0) {
            SYNERR = 0;
            lastexp = clib.UNDEF;
        } else {
            t1 = clib.type_of(lastexp);
            if (t1 == clib.wrong_t) {
                lastexp = clib.UNDEF;
            } else if (clib.subsumes(clib.instantiate(t1), t_val) == 0) {
                _ = clib.printf("data has wrong type :: ", .{.{}});
                clib.out_type(t1);
                _ = clib.printf("\nshould be :: ", .{.{}});
                clib.out_type(t_val);
                _ = clib.putc('\n', getStdout());
                lastexp = clib.UNDEF;
            }
        }
        if (lastexp != clib.UNDEF) {
            return clib.codegen(lastexp);
        }
        if (clib.isatty(clib.fileno(f)) != 0) {
            _ = clib.printf("please re-enter data:\n", .{.{}});
        } else {
            if (fil != 0) {
                _ = clib.fprintf(getStderr(), "readvals: bad data in file \"%s\"\n", .{.{clib.getstring(fil, @constCast(""))}});
            } else {
                _ = clib.fprintf(getStderr(), "bad data in $+ input\n", .{.{}});
            }
            clib.outstats();
            clib.exit(1);
        }
    }
}

pub fn ed_warn() void {
    _ = clib.printf("The currently installed editor command, \"%s\", does not\ninclude a facility for opening a file at a specified line number.  As a\nresult the `??' command and certain other features of the Miranda system\nare disabled.  See manual section 31/5 on changing the editor for more\ninformation.\n", .{.{editor orelse @constCast("")}});
}

pub fn src_update() c_int {
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

pub export fn reset() void {
    if (collecting != 0) {
        clib.gcpatch();
    }
    if (loading != 0) {
        if (blankerr == 0) {
            _ = clib.fprintf(getStderr(), "\n<<compilation interrupted>>\n", .{.{}});
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
        _ = clib.fprintf(getStderr(), "<<interrupt>>\n", .{.{}});
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

pub fn v_info(full: c_int) void {
    _ = clib.printf("%s last revised %s\n", .{.{strvers(version), vdate}});
    if (full == 0) return;
    _ = clib.printf("%s", .{.{host}});
    _ = clib.printf("XVERSION %u\n", .{.{@as(c_uint, clib.XVERSION)}});
}

pub extern fn command() void;
pub extern fn manaction() void;
pub extern fn editfile(t_val: [*:0]const u8, line: c_int) void;
pub extern fn xschars() void;
pub extern fn finger(n: [*:0]const u8) void;
pub extern fn diagnose(n: [*:0]const u8) void;
pub extern fn allnamescom() void;

pub fn spaces(s: Word) void {
    var j = s;
    while (j > 0) : (j -= 1) {
        _ = clib.putchar(' ');
    }
}
pub const loadfile = module_loader.loadfile;

pub fn fixexports() void {
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
                if (tag[@intCast(h(e_def))] == clib.ID) {
                    internals = cons(privatise(h(e_def)), internals);
                }
            }
        }
    } else {
        f = files;
        while (f != NIL) : (f = t(f)) {
            var e_def = fil_defs(h(f));
            while (e_def != NIL) : (e_def = t(e_def)) {
                if (tag[@intCast(h(e_def))] == clib.ID and unpainted(h(e_def))) {
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
    return tag[@intCast(v)] != clib.AP or h(v) != clib.EXPORT;
}

fn unpaint(x: Word) void {
    tp(x).* = t(id_val(x));
}

pub fn unfixexports() void {
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

    if (id_type(x) == clib.type_t) {
        tp(t_info(x)).* = cons(clib.datapair(@as(Word, @intCast(@intFromPtr(clib.getaka(x)))), 0), get_here(x));
    }

    if (id_val(x) == clib.UNDEF) {
        tp(x).* = clib.ap(clib.datapair(@as(Word, @intCast(@intFromPtr(clib.getaka(x)))), 0), get_here(x));
    }

    pnvec.?[@as(usize, @intCast(i))] = x;
    tag[@intCast(n)] = clib.ID;
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

    tag[@intCast(i)] = clib.ID;
    hp(i).* = h(x);

    const val = t(i);
    if (tag[@intCast(val)] == clib.AP and tag[@intCast(h(val))] == clib.DATAPAIR) {
        tp(i).* = clib.UNDEF;
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

pub fn sigdefer(_: c_int) callconv(.c) void {
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

pub const mkincludes = module_loader.mkincludes;

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
                if (tag[@intCast(h(h(t_val)))] == clib.STRCONS and t(t(h(h(t_val)))) == clib.type_t) {
                    pfrts = cons(h(h(t_val)), pfrts);
                }
            }
        }
    }

    var rfl_ptr = rfl;
    while (rfl_ptr != NIL) : (rfl_ptr = t(rfl_ptr)) {
        f = fil_defs(h(rfl_ptr));
        while (f != NIL) : (f = t(f)) {
            if (tag[@intCast(h(f))] == clib.ID) {
                t_val = id_type(h(f));
                if (t_val == clib.type_t) {
                    if (t_class(h(f)) == clib.synonym_t) {
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
    _ = clib.printf("MISSING TYPENAME%s\n", .{.{if (t(tlost) == NIL) @as([*:0]const u8, "") else @as([*:0]const u8, "S")}});
    _ = clib.printf("the following type%s no name in this scope:\n", .{.{if (t(tlost) == NIL) @as([*:0]const u8, " is needed but has") else @as([*:0]const u8, "s are needed but have")}});
    while (tlost != NIL) {
        _ = clib.printf("\'%s\' of file \"%s\", needed by: ", .{.{@as([*:0]const u8, @ptrFromInt(@as(usize, @intCast(h(h(t_info(h(h(tlost))))))))), @as([*:0]const u8, @ptrFromInt(@as(usize, @intCast(h(t(t_info(h(h(tlost)))))))))}});
        clib.printlist(@constCast(""), alfasort(t(h(tlost))));
        tlost = t(tlost);
    }
}

fn fixtype(t_val: Word, x: Word) Word {
    switch (tag[@intCast(t_val)]) {
        clib.AP, clib.CONS => {
            tp(t_val).* = fixtype(t(t_val), x);
            hp(t_val).* = fixtype(h(t_val), x);
            return t_val;
        },
        clib.STRCONS => {
            if (clib.member(pfrts, t_val) != 0) {
                return t_val;
            }
            var cur_t = t_val;
            while (tag[@intCast(pn_val(cur_t))] != clib.CONS) {
                cur_t = pn_val(cur_t);
            }
            if (tag[@intCast(cur_t)] != clib.ID) {
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

pub const privlib = setup.privlib;
pub const stdlib = setup.stdlib;

export fn syntax(s: [*:0]const u8) void {
    if (SYNERR != 0) return;
    if (echoing != 0) {
        _ = clib.fprintf(getStderr().?, "\n", .{.{}});
    }
    _ = clib.fprintf(getStderr().?, "syntax error: %s", .{.{s}});
    SYNERR = 1;
    reset_lex();
}

export fn acterror() void {
    if (SYNERR != 0) return;
    SYNERR = 1;
    reset_lex();
}

pub const mira_setup = setup.mira_setup;

inline fn pn_val(x: Word) Word {
    return t(x);
}

pub export fn alfasort(x_val: Word) Word {
    var x = x_val;
    var a = NIL;
    var b = NIL;
    var hold = NIL;
    if (x == NIL) {
        return NIL;
    }
    if (t(x) == NIL) {
        return if (tag[@intCast(h(x))] != clib.ID) NIL else x;
    }
    while (x != NIL) {
        if (tag[@intCast(h(x))] == clib.ID) {
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

pub fn utf8test() c_int {
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

pub fn undump(t_val: [*:0]const u8) void {
    var obf: [clib.pnlim]u8 = undefined;
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
    if (flen > clib.pnlim) {
        _ = clib.printf("sorry, pathname too long (limit=%d): %s\n", .{.{clib.pnlim, t_val}});
        return;
    }

    _ = clib.strcpy(&obf, t_val);
    _ = clib.strcpy(obf[@intCast(flen - 1)..].ptr, obsuffix);
    t2 = @intCast(fm_time(@as([*:0]const u8, @ptrCast(&obf))));
    if (t2 != 0 and t1 == 0) {
        t2 = 0;
        _ = clib.unlink(@as([*:0]const u8, @ptrCast(&obf)));
    }
    if (t2 == 0 or t2 < t1) {
        loadfile(t_val);
        return;
    }

    f = clib.fopen(&obf, "r");
    if (f == null) {
        _ = clib.printf("cannot open %s\n", .{.{@as([*:0]const u8, @ptrCast(&obf))}});
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
        _ = clib.unlink(@as([*:0]const u8, @ptrCast(&obf)));
        unload();
        CLASHES = NIL;
        stackp = dstack;
        _ = clib.printf("warning: %s contains incorrect data (file removed)\n", .{.{@as([*:0]const u8, @ptrCast(&obf))}});
        if (BAD_DUMP == -1) {
            _ = clib.printf("(unrecognised dump format)\n", .{.{}});
        } else if (BAD_DUMP == 1) {
            _ = clib.printf("(wrong source file)\n", .{.{}});
        } else {
            _ = clib.printf("(error %ld)\n", .{.{BAD_DUMP}});
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
            _ = clib.printf("cannot load %s ", .{.{@as([*:0]const u8, @ptrCast(&obf))}});
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
            _ = clib.fprintf(getStderr(), "panic: %s contains errors\n", .{.{@as([*:0]const u8, @ptrCast(&obf))}});
            clib.exit(1);
        }
    } else {
        if (verbosity != 0 or magic != 0 or mkexports != 0) {
            if (files == NIL) {
                _ = clib.printf("%s contains syntax error\n", .{.{t_val}});
            } else {
                if (ND != NIL) {
                    _ = clib.printf("%s contains undefined names or type errors\n", .{.{t_val}});
                } else if (making == 0 and magic == 0) {
                    _ = clib.printf("%s\n", .{.{t_val}});
                }
            }
        }
    }

    if (files != NIL and making == 0 and initialising == 0) {
        unfixexports();
    }
    loading = 0;
}

pub fn missparam(s: [*:0]const u8) void {
    _ = clib.fprintf(getStderr(), "mira: missing param after flag \"-%s\"\n", .{.{s}});
    clib.exit(1);
}

pub fn makedump() void {
    const obf = &linebuf;
    var f: ?*clib.FILE = null;
    _ = clib.strcpy(obf, current_script.?);
    const len = clib.strlen(obf);
    _ = clib.strcpy(obf[len - 1 ..].ptr, obsuffix);
    f = clib.fopen(obf, "w");
    if (f == null) {
        _ = clib.printf("WARNING: CANNOT WRITE TO %s\n", .{.{@as([*:0]const u8, @ptrCast(obf))}});
        if (clib.strcmp(current_script.?, &PRELUDE) == 0 or clib.strcmp(current_script.?, &STDENV) == 0) {
            _ = clib.printf("TO FIX THIS PROBLEM PLEASE GET SUPER-USER TO EXECUTE `mira'\n", .{.{}});
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

pub fn mkabsolute(m: [*:0]u8) [*:0]u8 {
    if (m[0] == '/') {
        return m;
    }
    if (clib.getcwd(dicp, clib.pnlim) == null) {
        _ = clib.fprintf(getStderr(), "panic: cwd too long\n", .{.{}});
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

pub fn addtoenv(x: Word) void {
    tp(h(files)).* = cons(x, t(h(files)));
}

pub fn main(ctx: std.process.Init) !void {
    clib.env_slice = ctx.minimal.environ.block.slice;
    const raw_args = ctx.minimal.args.vector;
    const argv: [*][*:0]u8 = @ptrCast(@constCast(raw_args.ptr));
    const argc: c_int = @intCast(raw_args.len);
    const exit_code = main_entry(argc, argv);
    std.process.exit(@intCast(exit_code));
}

comptime {
    _ = @import("driver/startup.zig");
    _ = @import("driver/repl.zig");
    _ = @import("driver/commands.zig");
    _ = @import("runtime/heap.zig");
    _ = @import("runtime/reduce.zig");
    _ = @import("runtime/combinator.zig");
    _ = @import("runtime/big.zig");
    _ = @import("parser/lex.zig");
    _ = @import("parser/parser_tests.zig");
    _ = @import("compiler/trans.zig");
    _ = @import("compiler/types.zig");
    _ = @import("compiler/setup.zig");
    _ = @import("compiler/module_loader.zig");
    _ = @import("io/signals.zig");
    _ = @import("runtime/version.zig");
}
