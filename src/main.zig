const std = @import("std");
const platform = @import("io/platform.zig");
const parser_api = @import("parser/parser_api.zig");
const word_mod = @import("runtime/word.zig");
const clib = @import("runtime/main_clib.zig");
const rt = @import("runtime/runtime_state.zig");
const setup = @import("compiler/setup.zig");
const module_loader = @import("compiler/module_loader.zig");
const types_mod = @import("compiler/types.zig");
const trans_mod = @import("compiler/trans.zig");
const commands = @import("driver/commands.zig");
pub const dump = @import("compiler/dump.zig");
pub const files_mod = @import("io/files.zig");
pub const heap = @import("runtime/heap.zig");
pub const repl = @import("driver/repl.zig");
pub const startup = @import("driver/startup.zig");
const errors_mod = @import("runtime/errors.zig");
pub const MiraError = errors_mod.MiraError;
/// Print a diagnostic to stderr and exit(1). See `errors.fatal`.
pub const fatal = errors_mod.fatal;

// Type and core constants
pub const Word = c_long;
pub const CONS: u8 = 11;
pub const AP: u8 = 9;
pub const CMBASE: Word = 306;
pub const NIL: Word = CMBASE + 138;
pub const ATOMLIMIT: Word = CMBASE + 141;

// RuntimeState: all mutable interpreter state not constrained by extern var circularity
pub const RuntimeState = rt.RuntimeState;
pub const rs: *RuntimeState = &rt.rs;

// Global state variables (TYPE B: defined in other modules, re-exported here)
pub extern var hd: [*]Word;
pub extern var tl: [*]Word;
pub extern var tag: [*]u8;

pub extern var s_out: ?*clib.FILE;
pub extern var dstack: ?[*]Word;
pub extern var stackp: ?[*]Word;

pub extern var version: c_int;
pub extern var vdate: [*:0]const u8;
pub extern var host: [*:0]const u8;

// Stuck vars now live in core_state.zig; re-declared here as extern var so
// callers using main.X still compile without modification.
pub extern var nill: Word;
pub extern var loading: c_int;
pub extern var compiling: c_int;
pub extern var errs: Word;
pub extern var errline: Word;
pub extern var obsuffix: [*:0]const u8;
pub extern var SYNERR: Word;
pub extern var commandmode: Word;

pub const EDITOR: [*:0]const u8 = "vi +!";

pub extern var files: Word;
pub extern var current_file: Word;
extern var collecting: Word;

// Re-export compiler_state and cs pointer to singleton
pub const compiler_state = @import("compiler/compiler_state.zig");
pub const cs = &compiler_state.cs;

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

// Inline helpers (use heap module directly — B2: no h/t aliases here)
pub inline fn get_id(x: Word) [*:0]const u8 {
    return @ptrFromInt(@as(usize, @intCast(heap.h(heap.h(heap.h(x))))));
}

pub inline fn get_fil(fil: Word) ?[*:0]const u8 {
    const val = heap.h(heap.h(heap.h(fil)));
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

// Relocated aliases — Compiler Setup
pub const privlib = setup.privlib;
pub const stdlib = setup.stdlib;
pub const mira_setup = setup.mira_setup;

// Source/Module Loader
pub const loadfile = module_loader.loadfile;
pub const mkincludes = module_loader.mkincludes;

// Compiler entry points — direct imports eliminate clib.* linker coupling (H2)
pub const type_of = types_mod.type_of;
pub const checktypes = types_mod.checktypes;
pub const codegen = trans_mod.codegen;

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

// Domain types (C2) — typed wrappers for heap node Words.
// Use these at API boundaries; `.word` unwraps to raw Word for legacy accessors.
pub const FileNode = heap.FileNode;
pub const Identifier = heap.Identifier;
pub const TypeRef = heap.TypeRef;
pub const NodeRef = heap.NodeRef;

// Heap accessors — B2: h/t/hp/tp removed; callers use main.heap.h/t/hp/tp directly.
// Other heap aliases kept to avoid churn in call sites not covered by B2.
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
    rt.io = ctx.io;
    rt.environ = ctx.minimal.environ;
    rt.allocator = rt.gpa.allocator();
    clib.env_slice = ctx.minimal.environ.block.slice;
    const raw_args = ctx.minimal.args.vector;
    const argv: [*][*:0]u8 = @ptrCast(@constCast(raw_args.ptr));
    const argc: c_int = @intCast(raw_args.len);
    const exit_code = main_entry(argc, argv);
    _ = rt.gpa.deinit();
    std.process.exit(@intCast(exit_code));
}

comptime {
    _ = @import("runtime/core_state.zig");
    _ = @import("driver/startup.zig");
    _ = @import("driver/repl.zig");
    _ = @import("driver/commands.zig");
    _ = @import("runtime/heap.zig");
    _ = @import("runtime/errors.zig");
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
    _ = @import("runtime/runtime_state.zig");
}
