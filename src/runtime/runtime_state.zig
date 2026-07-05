//! runtime_state.zig — the interpreter's bootstrap globals (`gpa`/`allocator`/
//! `io`/`environ`, set up in `main`) and the aggregate `RuntimeState`: all
//! mutable interpreter state that is not tied to a C-ABI linker symbol. The
//! singleton lives in `interp`; callers reach it as `rs.X`.

const std = @import("std");
const abi = @import("main_clib.zig");

/// The process-wide debug allocator that backs `allocator`.
pub var gpa = std.heap.DebugAllocator(.{}){};
/// The general-purpose allocator used throughout the interpreter (set in `main`).
pub var allocator: std.mem.Allocator = std.heap.page_allocator;
/// The process's std I/O interface (set in `main`).
pub var io: std.Io = std.Options.debug_io;
/// The process environment block (set in `main`).
pub var environ: std.process.Environ = .empty;

const Word = i64;
const CMBASE: Word = 306;
const NIL: Word = CMBASE + 138;
const UNDEF: Word = CMBASE + 140;

/// All mutable interpreter state that does not require a C-ABI linker symbol
/// (see main.zig for the 8 vars that must remain as export var due to heap.zig /
/// parser_api.zig circular-import constraints: loading, compiling, nill, errs,
/// errline, obsuffix, SYNERR, commandmode).
pub const RuntimeState = struct {
    // Identity atoms — heap node IDs set by miraSetup(); valid after setup, zero before.
    Void: Word = 0,
    main_id: Word = 0,
    message: Word = 0,
    standardout: Word = 0,
    diagonalise: Word = 0,
    concat: Word = 0,
    indent_fn: Word = 0,
    outdent_fn: Word = 0,
    listdiff_fn: Word = 0,
    shownum1: Word = 0,
    showbool: Word = 0,
    showchar: Word = 0,
    showlist: Word = 0,
    showstring: Word = 0,
    showparen: Word = 0,
    showpair: Word = 0,
    showvoid: Word = 0,
    showfunction: Word = 0,
    showabstract: Word = 0,
    showwhat: Word = 0,
    /// Last identifier referenced interactively; used for `//f` finger command.
    lastid: Word = 0,
    rv_expr: Word = 0,

    // File paths — null-terminated byte arrays populated by startup; treated as C strings.
    // Zero-initialised so a `.{}` singleton reads as the empty string before startup fills them.
    PRELUDE: [abi.pnlim + 10]u8 = std.mem.zeroes([abi.pnlim + 10]u8),
    STDENV: [abi.pnlim + 9]u8 = std.mem.zeroes([abi.pnlim + 9]u8),

    // Compiler flags (Word-typed because they are linker-visible to lex.zig / trans.zig
    // which CAN switch to @import — no circular constraint, but keep as Word for now)
    /// Heap node holding the list of free-name-to-type bindings for %bnf rules.
    fnts: Word = NIL,
    /// Maximum heap cells before GC triggers; set from `-heap N` CLI flag.
    SPACELIMIT: Word = 2500000,
    /// Dictionary space in bytes; set from `-dic N` CLI flag.
    DICSPACE: Word = 100000,
    UTF8: i32 = 0,
    UTF8OUT: i32 = 0,

    // Configuration — set from CLI flags or .mirarc before miraSetup().
    editor: ?[*:0]u8 = null,
    /// True when the prelude has been accepted without error.
    okprel: bool = false,
    /// True when `-nostandard` flag suppresses loading STDENV.
    nostdenv: bool = false,
    /// Non-zero when the configured editor command is invalid.
    baded: Word = 0,
    miralib: ?[*:0]u8 = null,
    promptstr: [*:0]const u8 = "Miranda ",
    s_in: ?*abi.FILE = null,

    // Runtime counters (all updated by the GC and evaluator; read by //stats).
    atobject: i32 = 0,
    atgc: i32 = 0,
    atcount: i32 = 0,
    debug: i32 = 0,

    // Evaluation control flags
    /// True when building a .mirarc dump; suppresses side-effects.
    magic: bool = false,
    /// True when `//make` is in progress.
    making: bool = false,
    /// True when `//exports` should write an export header.
    mkexports: bool = false,
    mksources: bool = false,
    make_status: Word = 0,
    ideep: i32 = 0,
    /// Non-zero during the one-time startup before `commandLoop` begins.
    /// Guards paths that must not repeat (e.g. panic on missing prelude).
    initialising: Word = 1,
    /// Heap list of primitive environment bindings, built by primlib().
    primenv: Word = NIL,
    /// Path of the .m file currently being loaded; null outside a load.
    current_script: ?[*:0]u8 = null,
    lastexp: Word = UNDEF,

    // I/O mode flags
    echoing: Word = 0,
    listing: Word = 0,
    verbosity: Word = 0,
    /// When true, `if` guards are strict (unevaluated guards are errors).
    /// Converted from Word at B1; only ever true/false.
    strictif: bool = true,
    rechecking: Word = 0,
    cstack: ?[*]Word = null,

    // Working buffers — sized for the longest supported pathname (pnlim).
    // Zero-initialised (see above): cheap for a singleton, removes read-before-write UB risk.
    linebuf: [abi.BUFSIZE]u8 = std.mem.zeroes([abi.BUFSIZE]u8),
    ebuf: [abi.pnlim]u8 = std.mem.zeroes([abi.pnlim]u8),
    home_rc: [abi.pnlim + 8]u8 = std.mem.zeroes([abi.pnlim + 8]u8),
    lib_rc: [abi.pnlim + 8]u8 = std.mem.zeroes([abi.pnlim + 8]u8),
    /// Non-null when readRc fails; points into home_rc or lib_rc (not heap-allocated).
    rc_error: ?[*:0]const u8 = null,

    // Signal / longjmp recovery
    /// Recovery point for SIGINT and SIGFPE via siglongjmp().  POSIX signal
    /// handlers are asynchronous (fire on any call stack) and cannot propagate
    /// Zig error unions via stack unwinding.  This sigjmp_buf MUST remain —
    /// it cannot be replaced with error{EvaluationInterrupted}.
    env: abi.sigjmp_buf = .{},
    /// Path of a temp file to unlink if a signal fires during dump/undump.
    unlinkme: ?[*:0]const u8 = null,
    sigflag: i32 = 0,

    // Sorted output and GC-adjacent state
    sorted: i32 = 0,
    detrop: Word = NIL,
    /// Reload-file list: heap list of file nodes needing re-checking after a change.
    rfl: Word = NIL,
    bereaved: Word = 0,
    ld_stuff: Word = NIL,

    // Module / name tables
    /// Snapshot of `files` at the start of a load; restored on error.
    oldfiles: Word = NIL,
    includees: Word = NIL,
    freeids: Word = NIL,
    exports: Word = NIL,
    embargoes: Word = NIL,
    lastname: Word = 0,
    suppressids: Word = NIL,
    col_fn: Word = 0,

    // BNF / lex extension state
    eprodnts: Word = NIL,
    nonterminals: Word = NIL,
    ntmap: Word = NIL,
    ihlist: Word = 0,
    ntspecmap: Word = NIL,
    lexstates: Word = NIL,
    lexdefs: Word = NIL,

    // ── Driver / REPL display scratch (commands.zig, repl.zig) ─────────────
    /// Cached path to the user's (and library's) `.mirahdr` file, computed
    /// once on first `/edit` use.
    mirahdr: ?[*:0]u8 = null,
    lmirahdr: ?[*:0]u8 = null,
    /// Column-alternation flag for `namescom`'s two-column name listing.
    leftist: bool = false,
    /// Scratch buffer of heap ids for one `namescom` listing pass.
    words: [400]Word = undefined,
    /// Cached length of the miralib path prefix, for `filequote`'s `<name>`
    /// shorthand.
    filequote_mlen: usize = 0,
    /// Elapsed time and GC count from the last evaluated REPL expression,
    /// surfaced in the next prompt string. Also read (as `rt.rs.X`, ambiently)
    /// by `reset()`, the SIGINT handler, which cannot take parameters.
    last_elapsed_ns: ?i128 = null,
    last_gc_count: ?c_long = null,
    /// The forked child's exit status, read once by `commandLoop` to derive
    /// `last_gc_count` above.
    child_exit_status: ?u8 = null,

    /// Validate all runtime state global variables holding heap references.
    pub fn validate(self: *const RuntimeState) void {
        const options = @import("version_options");
        if (@import("builtin").mode != .Debug and !options.is_strict) return;

        const heap = &@import("interp.zig").interp.heap;
        const top_limit = heap.TOP();

        inline for (.{ self.Void, self.main_id, self.message, self.standardout, self.diagonalise, self.concat, self.indent_fn, self.outdent_fn, self.listdiff_fn, self.shownum1, self.showbool, self.showchar, self.showlist, self.showstring, self.showparen, self.showpair, self.showvoid, self.showfunction, self.showabstract, self.showwhat, self.lastid, self.rv_expr, self.fnts, self.primenv, self.oldfiles, self.includees, self.freeids, self.exports, self.embargoes, self.lastname, self.suppressids, self.col_fn, self.eprodnts, self.nonterminals, self.ntmap, self.ntspecmap, self.lexstates, self.lexdefs, self.detrop, self.rfl, self.ld_stuff }) |field| {
            if (field >= @import("word.zig").ATOMLIMIT) {
                if (field >= top_limit) {
                    std.debug.panic("runtime.validate: runtime state field has out-of-bounds heap reference {d} (TOP is {d})", .{ field, top_limit });
                }
            }
        }
    }
};

/// Pointer to the singleton runtime state held in `interp` (so `interp.reset()`
/// clears it). Accessed as `rs.X`.
pub const rs = &@import("interp.zig").interp.rs;

test "RuntimeState default values are self-consistent" {
    const state: RuntimeState = .{};
    try std.testing.expectEqual(@as(Word, NIL), state.detrop);
    try std.testing.expectEqual(@as(Word, NIL), state.primenv);
    try std.testing.expectEqual(true, state.strictif);
    try std.testing.expectEqual(@as(Word, 1), state.initialising);
    try std.testing.expectEqual(@as(Word, 2500000), state.SPACELIMIT);
}

test "RuntimeState bool fields default to false" {
    const state: RuntimeState = .{};
    try std.testing.expect(!state.magic);
    try std.testing.expect(!state.making);
    try std.testing.expect(!state.mkexports);
    try std.testing.expect(!state.mksources);
    try std.testing.expect(!state.okprel);
    try std.testing.expect(!state.nostdenv);
}

test "RuntimeState null-initialised optional fields" {
    const state: RuntimeState = .{};
    try std.testing.expectEqual(@as(?[*:0]u8, null), state.editor);
    try std.testing.expectEqual(@as(?[*:0]u8, null), state.current_script);
    try std.testing.expectEqual(@as(?[*:0]const u8, null), state.rc_error);
    try std.testing.expectEqual(@as(?[*:0]const u8, null), state.unlinkme);
}
