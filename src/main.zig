//! main.zig — the composition root. Holds the process entry point (`main`), the
//! `comptime` block that aggregates every module's unit tests into the
//! `main-tests` binary, and the `main.*` re-export namespace through which the
//! C-ported call sites reach the runtime / compiler / driver modules.

const std = @import("std");
const strtab = @import("runtime/strtab.zig");
const abi = @import("runtime/main_clib.zig");
const rt = @import("runtime/runtime_state.zig");
const setup = @import("compiler/setup.zig");
const module_loader = @import("compiler/module_loader.zig");
const types_mod = @import("compiler/types.zig");
const trans_mod = @import("compiler/trans.zig");
const commands = @import("driver/commands.zig");
/// The state-dump (`.x` serialiser) module.
pub const dump = @import("compiler/dump.zig");
/// The filesystem/platform helpers module.
pub const files_mod = @import("io/files.zig");
/// The graph-heap module.
pub const heap = @import("runtime/heap.zig");
/// The REPL driver module.
pub const repl = @import("driver/repl.zig");
/// The CLI-startup module.
pub const startup = @import("driver/startup.zig");
const errors_mod = @import("runtime/errors.zig");
const r7_types = @import("compiler/types.zig");
const r7_repl = @import("driver/repl.zig");
const r7_startup = @import("driver/startup.zig");
const r7_signals = @import("io/signals.zig");
const r7_lex = @import("parser/lex.zig");
const r7_heap = @import("runtime/heap.zig");
/// The interpreter's domain-error set (see `errors.MiraError`).
pub const MiraError = errors_mod.MiraError;
/// Print a diagnostic to stderr and exit(1). See `errors.fatal`.
pub const fatal = errors_mod.fatal;

// Type and core constants
/// The interpreter machine word (see `word.Word`).
pub const Word = i64;
/// `CONS` cell tag (mirrors `word.CONS`).
pub const CONS: u8 = 11;
/// `AP` cell tag (mirrors `word.AP`).
pub const AP: u8 = 9;
/// Base of the combinator/atom code range (mirrors `word.CMBASE`).
pub const CMBASE: Word = 306;
/// The empty list `[]` sentinel (mirrors `word.NIL`).
pub const NIL: Word = CMBASE + 138;
/// First heap-cell handle; values below are atoms (mirrors `word.ATOMLIMIT`).
pub const ATOMLIMIT: Word = CMBASE + 141;

// RuntimeState: all mutable interpreter state not constrained by extern var circularity
/// The aggregate runtime-state struct type (see `runtime_state.RuntimeState`).
pub const RuntimeState = rt.RuntimeState;
/// Pointer to the singleton runtime state.
pub const rs: *RuntimeState = rt.rs;

// Core/error state lives in core_state.zig; callers reach it via `core_state.X`
// directly (no `main.X` re-export — the old extern/export var bridge is gone).

/// Default external editor command (overridable via `EDITOR`/the `.mirarc`).
pub const EDITOR: [*:0]const u8 = "vi +!";

// Re-export compiler_state and cs pointer to singleton
/// The type-checker/compiler state module.
pub const compiler_state = @import("compiler/compiler_state.zig");
/// Pointer to the singleton compiler state.
pub const cs = compiler_state.cs;

// External / runtime function declarations
/// Re-export of `signals.signals` (the installed signal-handler table).
pub const signals = r7_signals.signals;
/// Re-export of `repl.dieClean` (clean-shutdown signal handler).
pub const dieClean = r7_repl.dieClean;
/// Re-export of `repl.fpeError` (the SIGFPE/arith-error handler).
pub const fpeError = r7_repl.fpeError;
/// Re-export of `repl.commandLoop` (the interactive read-eval loop).
pub const commandLoop = r7_repl.commandLoop;
/// Re-export of `startup.mainEntry` (the C-style program entry).
pub const mainEntry = r7_startup.mainEntry;

const setupheap = r7_heap.setupheap;
const tsetup = r7_types.tsetup;
const resetPns = r7_lex.resetPns;
const resetgcstats = r7_heap.resetgcstats;
const resetState = r7_lex.resetState;
const resetLex = r7_lex.resetLex;
/// Re-export of `lex.dicCheck` (dictionary-overflow guard).
pub const dicCheck = r7_lex.dicCheck;
const isconstrname = r7_lex.isconstrname;
// Inline helpers (use heap module directly — B2: no h/t aliases here)
/// The interned name text of id node `x`.
pub inline fn get_id(x: Word) [*:0]const u8 {
    return strtab.strOf(heap.h(heap.h(heap.h(x))));
}

/// The filename of file-record `fil`, or null when absent.
pub inline fn get_fil(fil: Word) ?[*:0]const u8 {
    const val = heap.h(heap.h(heap.h(fil)));
    if (val == 0) return null;
    return strtab.strOf(val);
}

/// The standard-input `FILE` handle.
pub inline fn getStdin() ?*abi.FILE {
    return abi.stdin();
}
/// The standard-output `FILE` handle.
pub inline fn getStdout() ?*abi.FILE {
    return abi.stdout();
}
/// The standard-error `FILE` handle.
pub inline fn getStderr() ?*abi.FILE {
    return abi.stderr();
}

// Relocated aliases — Compiler Setup
/// Re-export of `setup.privlib` (seed the private prelude library).
pub const privlib = setup.privlib;
/// Re-export of `setup.stdlib` (seed the standard library).
pub const stdlib = setup.stdlib;
/// Re-export of `setup.miraSetup` (full interpreter initialisation).
pub const miraSetup = setup.miraSetup;

// Source/Module Loader
/// Re-export of `module_loader.loadfile` (compile/load a source file).
pub const loadfile = module_loader.loadfile;
/// Re-export of `module_loader.mkincludes` (resolve `%include` directives).
pub const mkincludes = module_loader.mkincludes;

// Compiler entry points — direct imports eliminate abi.* linker coupling (H2)
/// Re-export of `types.typeOf` (infer the type of an expression).
pub const typeOf = types_mod.typeOf;
/// Re-export of `types.checktypes` (type-check the current script).
pub const checktypes = types_mod.checktypes;
/// Re-export of `trans.codegen` (compile an expression to a combinator graph).
pub const codegen = trans_mod.codegen;

// State Dumping
/// Re-export of `dump.undump` (load a `.x` dump file).
pub const undump = dump.undump;
/// Re-export of `dump.makedump` (write the current state to a `.x` file).
pub const makedump = dump.makedump;
/// Re-export of `dump.fixexports` (resolve export tables before dumping).
pub const fixexports = dump.fixexports;
/// Re-export of `dump.unfixexports` (undo `fixexports`).
pub const unfixexports = dump.unfixexports;
/// Re-export of `dump.readoption` (read a dump-file option header).
pub const readoption = dump.readoption;
/// Re-export of `dump.sigdefer` (defer-signal handler during dump I/O).
pub const sigdefer = dump.sigdefer;

// Filesystem and platform operations
/// Re-export of `files.fileMtime` (a file's modification time).
pub const fileMtime = files_mod.fileMtime;
/// Re-export of `files.isMirandaSource` (does the path name a `.m` source?).
pub const isMirandaSource = files_mod.isMirandaSource;
/// Re-export of `files.sameFile` (do two paths name the same inode?).
pub const sameFile = files_mod.sameFile;
/// Re-export of `files.inodeId` (a file's device/inode identity).
pub const inodeId = files_mod.inodeId;
/// Re-export of `files.fileExists` (does the path exist?).
pub const fileExists = files_mod.fileExists;
/// Re-export of `files.fileCopy` (copy a file).
pub const fileCopy = files_mod.fileCopy;
/// Re-export of `files.copyFile` (copy a file, alternate form).
pub const copyFile = files_mod.copyFile;
/// Re-export of `files.unlinkObject` (delete a compiled object file).
pub const unlinkObject = files_mod.unlinkObject;
/// Re-export of `files.makeAbsolute` (resolve a path to absolute form).
pub const makeAbsolute = files_mod.makeAbsolute;
/// Re-export of `files.termWidth` (the terminal column width).
pub const termWidth = files_mod.termWidth;

// Domain types (C2) — typed wrappers for heap node Words.
// Use these at API boundaries; `.word` unwraps to raw Word for legacy accessors.
/// Re-export of `heap.FileNode` (typed wrapper for a file-record node).
pub const FileNode = heap.FileNode;
/// Re-export of `heap.Identifier` (typed wrapper for an id node).
pub const Identifier = heap.Identifier;
/// Re-export of `heap.TypeRef` (typed wrapper for a type node).
pub const TypeRef = heap.TypeRef;
/// Re-export of `heap.NodeRef` (typed wrapper for a generic heap node).
pub const NodeRef = heap.NodeRef;

// Heap accessors — B2: h/t/hp/tp removed; callers use main.heap.h/t/hp/tp directly.
// Other heap aliases kept to avoid churn in call sites not covered by B2.
/// Re-export of `heap.cons` (allocate a cons cell).
pub const cons = heap.cons;
/// Re-export of `heap.filTime` (a file record's mtime field).
pub const filTime = heap.filTime;
/// Re-export of `heap.filShare` (a file record's share-list field).
pub const filShare = heap.filShare;
/// Re-export of `heap.filInodev` (a file record's inode/device field).
pub const filInodev = heap.filInodev;
/// Re-export of `heap.filDefs` (a file record's definitions field).
pub const filDefs = heap.filDefs;
/// Re-export of `heap.dval` (a definition cell's value).
pub const dval = heap.dval;
/// Re-export of `heap.dlhs` (a definition cell's left-hand side).
pub const dlhs = heap.dlhs;
/// Re-export of `heap.getHere` (an id's recorded source location).
pub const getHere = heap.getHere;
/// Re-export of `heap.theVal` (a type/definition cell's value field).
pub const theVal = heap.theVal;
/// Re-export of `heap.tClass` (a type node's class field).
pub const tClass = heap.tClass;
/// Re-export of `heap.tInfo` (a type node's info field).
pub const tInfo = heap.tInfo;
/// Re-export of `heap.idVal` (an id's value field).
pub const idVal = heap.idVal;
/// Re-export of `heap.idType` (an id's type field).
pub const idType = heap.idType;
/// Re-export of `heap.idWho` (an id's definition-site field).
pub const idWho = heap.idWho;
/// Re-export of `heap.badval` (out-of-range sentinel check).
pub const badval = heap.badval;
/// Re-export of `heap.isfreeid` (is the id a `%free` identifier?).
pub const isfreeid = heap.isfreeid;
/// Re-export of `heap.isconstructor` (does the id name a constructor?).
pub const isconstructor = heap.isconstructor;
/// Re-export of `heap.isvariable` (does the id name an ordinary variable?).
pub const isvariable = heap.isvariable;
/// Re-export of `heap.makeFil` (build a file-record node).
pub const makeFil = heap.makeFil;
/// Re-export of `heap.constructor` (build a constructor node).
pub const constructor = heap.constructor;
/// Re-export of `heap.addtoenv` (add an id to the current file's environment).
pub const addtoenv = heap.addtoenv;
/// Re-export of `heap.reverse` (reverse a list).
pub const reverse = heap.reverse;
/// Re-export of `heap.shunt` (reverse-append).
pub const shunt = heap.shunt;
/// Re-export of `heap.size` (list length).
pub const size = heap.size;
/// Re-export of `heap.alfasort` (sort ids alphabetically).
pub const alfasort = heap.alfasort;
/// Re-export of `heap.utf8test` (UTF-8 self-test).
pub const utf8test = heap.utf8test;
/// Re-export of `heap.unsetids` (clear a definition list's id bindings).
pub const unsetids = heap.unsetids;
/// Re-export of `heap.unload` (unload the current script's definitions).
pub const unload = heap.unload;
/// Re-export of `heap.srcUpdate` (note that the source has changed).
pub const srcUpdate = heap.srcUpdate;

// Interactive REPL/driver helpers
/// Re-export of `repl.obey` (execute a REPL directive).
pub const obey = repl.obey;
/// Re-export of `repl.evaluateRepl` (evaluate and print an expression).
pub const evaluateRepl = repl.evaluateRepl;
/// Re-export of `repl.reset` (reset the REPL to a clean prompt).
pub const reset = repl.reset;
/// Re-export of `repl.edWarn` (warn about a stale editor session).
pub const edWarn = repl.edWarn;
/// Re-export of `repl.announce` (print the startup banner).
pub const announce = repl.announce;
/// Re-export of `repl.getLine` (read a line of REPL input).
pub const getLine = repl.getLine;
/// Re-export of `repl.badEditor` (report an unusable `$EDITOR`).
pub const badEditor = repl.badEditor;
/// Re-export of `repl.fixEditor` (repair/recover the editor setting).
pub const fixEditor = repl.fixEditor;
/// Re-export of `repl.parseLine` (parse a line of REPL input).
pub const parseLine = repl.parseLine;

// Commands driver helpers
/// Re-export of `commands.command` (dispatch a `/`-command).
pub const command = commands.command;
/// Re-export of `commands.manaction` (the `/man` action).
pub const manaction = commands.manaction;
/// Re-export of `commands.diagnose` (print diagnostics for a name).
pub const diagnose = commands.diagnose;
/// Re-export of `commands.editfile` (open a source file in the editor).
pub const editfile = commands.editfile;
/// Re-export of `commands.allnamescom` (list all defined names).
pub const allnamescom = commands.allnamescom;
/// Re-export of `commands.finger` (show information about a name).
pub const finger = commands.finger;
/// Re-export of `commands.xschars` (the `%list`/cross-section helper).
pub const xschars = commands.xschars;

// Startup environment configuration
/// Re-export of `startup.readRc` (read the `.mirarc` config).
pub const readRc = startup.readRc;
/// Re-export of `startup.writeRc` (write the `.mirarc` config).
pub const writeRc = startup.writeRc;
/// Re-export of `startup.checkVersion` (verify a library's `.version`).
pub const checkVersion = startup.checkVersion;
/// Re-export of `startup.libFails` (report library version mismatches).
pub const libFails = startup.libFails;
/// Re-export of `startup.versionString` (format an integer version as `M.mmm`).
pub const versionString = startup.versionString;
/// Re-export of `startup.missingParam` (abort on a missing CLI parameter).
pub const missingParam = startup.missingParam;
/// Re-export of `startup.versionInfo` (print the release/date line).
pub const versionInfo = startup.versionInfo;

/// Process entry point: wire up the runtime context (io/allocator/argv) and forward to `mainEntry`.
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
    _ = @import("runtime/reducer/combinators.zig");
    _ = @import("runtime/errors.zig");
    _ = @import("runtime/reduce.zig");
    _ = @import("runtime/combinator.zig");
    _ = @import("runtime/big.zig");
    _ = @import("parser/lex.zig");
    _ = @import("parser/parser_tests.zig");
    _ = @import("parser/diagnostics.zig");
    _ = @import("compiler/trans.zig");
    _ = @import("compiler/types.zig");
    _ = @import("compiler/setup.zig");
    _ = @import("compiler/module_loader.zig");
    _ = @import("compiler/dump.zig");
    _ = @import("io/files.zig");
    _ = @import("io/signals.zig");
    _ = @import("runtime/version.zig");
    _ = @import("runtime/runtime_state.zig");
    _ = @import("testutil.zig");
}
