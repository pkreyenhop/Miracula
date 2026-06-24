const std = @import("std");
const platform = @import("io/platform.zig");
const parser_api = @import("parser/parser_api.zig");
const word_mod = @import("runtime/word.zig");
const strtab = @import("runtime/strtab.zig");
const abi = @import("runtime/main_clib.zig");
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
const r7_types = @import("compiler/types.zig");
const r7_repl = @import("driver/repl.zig");
const r7_startup = @import("driver/startup.zig");
const r7_signals = @import("io/signals.zig");
const r7_lex = @import("parser/lex.zig");
const r7_big = @import("runtime/big.zig");
const r7_heap = @import("runtime/heap.zig");
const reduce = @import("runtime/reduce.zig");
const version = @import("runtime/version.zig");
const core_state = @import("runtime/core_state.zig");
pub const MiraError = errors_mod.MiraError;
/// Print a diagnostic to stderr and exit(1). See `errors.fatal`.
pub const fatal = errors_mod.fatal;

// Type and core constants
pub const Word = i64;
pub const CONS: u8 = 11;
pub const AP: u8 = 9;
pub const CMBASE: Word = 306;
pub const NIL: Word = CMBASE + 138;
pub const ATOMLIMIT: Word = CMBASE + 141;

// RuntimeState: all mutable interpreter state not constrained by extern var circularity
pub const RuntimeState = rt.RuntimeState;
pub const rs: *RuntimeState = rt.rs;

// Core/error state lives in core_state.zig; callers reach it via `core_state.X`
// directly (no `main.X` re-export — the old extern/export var bridge is gone).

pub const EDITOR: [*:0]const u8 = "vi +!";

// Re-export compiler_state and cs pointer to singleton
pub const compiler_state = @import("compiler/compiler_state.zig");
pub const cs = compiler_state.cs;

// External / runtime function declarations
pub const signals = r7_signals.signals;
pub const dieClean = r7_repl.dieClean;
pub const fpeError = r7_repl.fpeError;
pub const commandLoop = r7_repl.commandLoop;
pub const mainEntry = r7_startup.mainEntry;

const setupheap = r7_heap.setupheap;
const tsetup = r7_types.tsetup;
const reset_pns = r7_lex.reset_pns;
const bigsetup = r7_big.setup;
const resetgcstats = r7_heap.resetgcstats;
const reset_state = r7_lex.reset_state;
const reset_lex = r7_lex.reset_lex;
pub const dic_check = r7_lex.dic_check;
const isconstrname = r7_lex.isconstrname;
// Inline helpers (use heap module directly — B2: no h/t aliases here)
pub inline fn get_id(x: Word) [*:0]const u8 {
    return strtab.strOf(heap.h(heap.h(heap.h(x))));
}

pub inline fn get_fil(fil: Word) ?[*:0]const u8 {
    const val = heap.h(heap.h(heap.h(fil)));
    if (val == 0) return null;
    return strtab.strOf(val);
}

pub inline fn getStdin() ?*abi.FILE {
    return abi.stdin();
}
pub inline fn getStdout() ?*abi.FILE {
    return abi.stdout();
}
pub inline fn getStderr() ?*abi.FILE {
    return abi.stderr();
}

// Relocated aliases — Compiler Setup
pub const privlib = setup.privlib;
pub const stdlib = setup.stdlib;
pub const mira_setup = setup.mira_setup;

// Source/Module Loader
pub const loadfile = module_loader.loadfile;
pub const mkincludes = module_loader.mkincludes;

// Compiler entry points — direct imports eliminate abi.* linker coupling (H2)
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
pub const fileMtime = files_mod.fileMtime;
pub const isMirandaSource = files_mod.isMirandaSource;
pub const sameFile = files_mod.sameFile;
pub const inodeId = files_mod.inodeId;
pub const fileExists = files_mod.fileExists;
pub const fileCopy = files_mod.fileCopy;
pub const copyFile = files_mod.copyFile;
pub const unlinkObject = files_mod.unlinkObject;
pub const makeAbsolute = files_mod.makeAbsolute;
pub const termWidth = files_mod.termWidth;

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
pub const evaluateRepl = repl.evaluateRepl;
pub const reset = repl.reset;
pub const edWarn = repl.edWarn;
pub const announce = repl.announce;
pub const getLine = repl.getLine;
pub const badEditor = repl.badEditor;
pub const fixEditor = repl.fixEditor;
pub const parseLine = repl.parseLine;

// Commands driver helpers
pub const command = commands.command;
pub const manaction = commands.manaction;
pub const diagnose = commands.diagnose;
pub const editfile = commands.editfile;
pub const allnamescom = commands.allnamescom;
pub const finger = commands.finger;
pub const xschars = commands.xschars;

// Startup environment configuration
pub const readRc = startup.readRc;
pub const writeRc = startup.writeRc;
pub const checkVersion = startup.checkVersion;
pub const libFails = startup.libFails;
pub const versionString = startup.versionString;
pub const missingParam = startup.missingParam;
pub const versionInfo = startup.versionInfo;

pub fn main(ctx: std.process.Init) !void {
    rt.io = ctx.io;
    rt.environ = ctx.minimal.environ;
    rt.allocator = rt.gpa.allocator();
    abi.env_slice = ctx.minimal.environ.block.slice;
    const raw_args = ctx.minimal.args.vector;
    const argv: [*][*:0]u8 = @ptrCast(@constCast(raw_args.ptr));
    const argc: c_int = @intCast(raw_args.len);
    const exit_code = mainEntry(argc, argv);
    _ = rt.gpa.deinit();
    std.process.exit(@intCast(exit_code));
}

comptime {
    _ = @import("runtime/core_state.zig");
    _ = @import("driver/startup.zig");
    _ = @import("driver/repl.zig");
    _ = @import("driver/commands.zig");
    _ = @import("runtime/heap.zig");
    _ = @import("runtime/strtab.zig");
    _ = @import("runtime/reducer/reduce_test.zig");
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
