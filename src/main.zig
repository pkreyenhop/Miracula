const std = @import("std");
const platform = @import("io/platform.zig");
const parser_api = @import("parser/parser_api.zig");
const word_mod = @import("runtime/word.zig");
const clib = @import("runtime/main_clib.zig");
const setup = @import("compiler/setup.zig");
const module_loader = @import("compiler/module_loader.zig");
const commands = @import("driver/commands.zig");
pub const dump = @import("compiler/dump.zig");
pub const files_mod = @import("io/files.zig");
pub const heap = @import("runtime/heap.zig");
pub const repl = @import("driver/repl.zig");
pub const startup = @import("driver/startup.zig");

// Type and core constants
pub const Word = c_long;
pub const CONS: u8 = 11;
pub const AP: u8 = 9;
pub const CMBASE: Word = 306;
pub const NIL: Word = CMBASE + 138;
pub const ATOMLIMIT: Word = CMBASE + 141;

// Global state variables (referenced by C ABI and other modules)
pub extern var hd: [*]Word;
pub extern var tl: [*]Word;
pub extern var tag: [*]u8;

pub extern var s_out: ?*clib.FILE;
pub extern var dstack: ?[*]Word;
pub extern var stackp: ?[*]Word;

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
pub export var lastid: Word = 0;
pub export var rv_expr: Word = 0;

pub var PRELUDE: [clib.pnlim + 10]u8 = undefined;
pub var STDENV: [clib.pnlim + 9]u8 = undefined;
pub export var loading: c_int = 0;
pub extern var BAD_DUMP: Word;
pub extern var CLASHES: Word;
extern var col: Word;
extern var DETROP: Word;
extern var MISSING: Word;
extern var ALIASES: Word;
extern var TSUPPRESSED: Word;
pub export var fnts: Word = NIL;

pub export var SPACELIMIT: Word = 2500000;
pub export var DICSPACE: Word = 100000;
pub export var UTF8: c_int = 0;
pub export var UTF8OUT: c_int = 0;
pub export var editor: ?[*:0]u8 = null;
pub const EDITOR: [*:0]const u8 = "vi +!";
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
pub export var lastexp: Word = clib.UNDEF;
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
pub var unlinkme: ?[*:0]const u8 = null;
pub export var sorted: c_int = 0;
pub export var detrop: Word = NIL;
pub export var rfl: Word = NIL;
pub export var bereaved: Word = 0;
pub export var ld_stuff: Word = NIL;
pub var sigflag: c_int = 0;

pub extern var namebucket: [128]Word;
pub extern var pnvec: ?[*]Word;
pub extern var TYPERRS: Word;
pub extern var FBS: Word;
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
pub extern var exportfiles: Word;
pub export var embargoes: Word = NIL;
pub extern var newtyps: Word;
pub extern var SGC: Word;
pub extern var speclocs: Word;
pub extern var rv_script: Word;
pub extern var algshfns: Word;
pub extern var nextpn: Word;
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
pub extern var TABSTRS: Word;
pub extern var ND: Word;
pub extern var polyshowerror: c_int;
extern var fileq: Word;

// External / runtime function declarations
pub extern fn signals(signum: c_int, handler: usize) usize;
pub extern fn dieclean() void;
pub extern fn fpe_error(sig: c_int) void;
pub extern fn commandloop(initscript: [*:0]u8) void;
pub extern fn main_entry(argc: c_int, argv: [*][*:0]u8) callconv(.c) c_int;

extern fn setupheap() void;
extern fn tsetup() void;
extern fn reset_pns() void;
extern fn bigsetup() void;
extern fn resetgcstats() void;
extern fn reset_state() void;
extern fn reset_lex() void;
pub extern fn dic_check() void;
extern fn isconstrname(input: [*:0]const u8) c_int;

// Inline functions
pub inline fn get_id(x: Word) [*:0]const u8 {
    return @ptrFromInt(@as(usize, @intCast(h(h(h(x))))));
}

pub inline fn get_fil(fil: Word) ?[*:0]const u8 {
    const val = h(h(h(fil)));
    if (val == 0) return null;
    return @ptrFromInt(@as(usize, @intCast(val)));
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

// Relocated aliases
// Compiler Setup
pub const privlib = setup.privlib;
pub const stdlib = setup.stdlib;
pub const mira_setup = setup.mira_setup;

// Source/Module Loader
pub const loadfile = module_loader.loadfile;
pub const mkincludes = module_loader.mkincludes;

// State Dumping
pub const undump = dump.undump;
pub const makedump = dump.makedump;
pub const fixexports = dump.fixexports;
pub const unfixexports = dump.unfixexports;
pub const readoption = dump.readoption;
pub const sigdefer = dump.sigdefer;

// Filesystem and platform operations
pub const fm_time = files_mod.fm_time;
pub const normal = files_mod.normal;
pub const same_file = files_mod.same_file;
pub const inodev = files_mod.inodev;
pub const fileExists = files_mod.fileExists;
pub const filecopy = files_mod.filecopy;
pub const filecp = files_mod.filecp;
pub const unlinkx = files_mod.unlinkx;
pub const mkabsolute = files_mod.mkabsolute;
pub const twidth = files_mod.twidth;

// Heap accessors & constructors
pub const h = heap.h;
pub const t = heap.t;
pub const hp = heap.hp;
pub const tp = heap.tp;
pub const cons = heap.cons;
pub const fil_time = heap.fil_time;
pub const fil_share = heap.fil_share;
pub const fil_inodev = heap.fil_inodev;
pub const fil_defs = heap.fil_defs;
pub const dval = heap.dval;
pub const dlhs = heap.dlhs;
pub const get_here = heap.get_here;
pub const the_val = heap.the_val;
pub const t_class = heap.t_class;
pub const t_info = heap.t_info;
pub const id_val = heap.id_val;
pub const id_type = heap.id_type;
pub const id_who = heap.id_who;
pub const badval = heap.badval;
pub const isfreeid = heap.isfreeid;
pub const isconstructor = heap.isconstructor;
pub const isvariable = heap.isvariable;
pub const make_fil = heap.make_fil;
pub const constructor = heap.constructor;
pub const addtoenv = heap.addtoenv;
pub const reverse = heap.reverse;
pub const shunt = heap.shunt;
pub const size = heap.size;
pub const alfasort = heap.alfasort;
pub const utf8test = heap.utf8test;
pub const unsetids = heap.unsetids;
pub const unload = heap.unload;
pub const src_update = heap.src_update;

// Interactive REPL/driver helpers
pub const obey = repl.obey;
pub const evaluate_repl = repl.evaluate_repl;
pub const reset = repl.reset;
pub const ed_warn = repl.ed_warn;
pub const announce = repl.announce;
pub const getln = repl.getln;
pub const badeditor = repl.badeditor;
pub const fixeditor = repl.fixeditor;
pub const parseline = repl.parseline;

// Commands driver helpers
pub const command = commands.command;
pub const manaction = commands.manaction;
pub const diagnose = commands.diagnose;
pub const editfile = commands.editfile;
pub const allnamescom = commands.allnamescom;
pub const finger = commands.finger;
pub const xschars = commands.xschars;

// Startup environment configuration
pub const rc_read = startup.rc_read;
pub const rc_write = startup.rc_write;
pub const checkversion = startup.checkversion;
pub const libfails = startup.libfails;
pub const strvers = startup.strvers;
pub const missparam = startup.missparam;
pub const v_info = startup.v_info;

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
    _ = @import("compiler/dump.zig");
    _ = @import("io/files.zig");
    _ = @import("io/signals.zig");
    _ = @import("runtime/version.zig");
}
