//! runtime_state.zig — the interpreter's bootstrap globals (`gpa`/`allocator`/
//! `io`/`environ`, set up in `main`) and the aggregate `RuntimeState`: all
//! mutable interpreter state that is not tied to a C-ABI linker symbol. The
//! singleton lives in `interp`; callers reach it as `rs.X`.

const std = @import("std");
const abi = @import("../os.zig");

/// The process-wide debug allocator that backs `allocator`.
pub var gpa = std.heap.DebugAllocator(.{}){};
/// The general-purpose allocator used throughout the interpreter (set in `main`).
pub var allocator: std.mem.Allocator = std.heap.page_allocator;
/// The process's std I/O interface (set in `main`).
pub var io: std.Io = std.Options.debug_io;
/// The process environment block (set in `main`).
pub var environ: std.process.Environ = .empty;

/// Set by the SIGINT/SIGTERM handler (Phase 3, docs/GO_PORT_PLAN.md — the
/// replacement for the old `sigsetjmp`/`siglongjmp` mechanism). The handler's
/// *only* job is this one atomic store (async-signal-safe by construction);
/// `reduce()`'s main loop polls it and unwinds via a normal Zig error return
/// (`error.Interrupted`, from `word.ReduceError`) instead of a signal-context
/// non-local jump. Cleared once the interrupted evaluation has been reported
/// back to the REPL prompt.
pub var interrupt_flag: std.atomic.Value(bool) = .init(false);

const Word = i64;
const CMBASE: Word = 306;
const NIL: Word = CMBASE + 138;

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
    rv_expr: Word = 0,

    // Compiler flags (Word-typed because they are linker-visible to lex.zig / trans.zig
    // which CAN switch to @import — no circular constraint, but keep as Word for now)
    UTF8: i32 = 0,
    UTF8OUT: i32 = 0,

    // Runtime counters (all updated by the GC and evaluator; read by //stats).
    atobject: i32 = 0,
    atgc: i32 = 0,
    atcount: i32 = 0,
    debug: i32 = 0,

    // Evaluation control flags
    /// True when building a .mirarc dump; suppresses side-effects.
    magic: bool = false,
    ideep: i32 = 0,
    /// Non-zero during the one-time startup before `commandLoop` begins.
    /// Guards paths that must not repeat (e.g. panic on missing prelude).
    initialising: Word = 1,
    /// Heap list of primitive environment bindings, built by primlib().
    primenv: Word = NIL,

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

    // ── Bootstrap scratch (startup.zig) ─────────────────────────────────────
    /// Version-mismatch scratch, filled by `checkVersion` and drained by
    /// `libFails` while resolving the miralib directory at startup.
    vstack: [4]c_int = undefined,
    /// The corresponding directory paths for `vstack`.
    mstack: [4][*:0]const u8 = undefined,
    /// Count of recorded mismatches in `vstack`/`mstack` (<= 4).
    mvp: usize = 0,
    /// Formatting scratch for `versionString`.
    vbuf: [12]u8 = undefined,

    /// Validate all runtime state global variables holding heap references.
    pub fn validate(self: *const RuntimeState) void {
        const options = @import("version_options");
        if (@import("builtin").mode != .Debug and !options.is_strict) return;

        const heap = &@import("../session/interp.zig").current_interp.heap;
        const top_limit = heap.TOP();

        inline for (.{ self.Void, self.main_id, self.message, self.standardout, self.diagonalise, self.concat, self.indent_fn, self.outdent_fn, self.listdiff_fn, self.rv_expr, self.primenv }) |field| {
            if (field >= @import("../graph/word.zig").ATOMLIMIT) {
                if (field >= top_limit) {
                    std.debug.panic("runtime.validate: runtime state field has out-of-bounds heap reference {d} (TOP is {d})", .{ field, top_limit });
                }
            }
        }

        const script = @import("../session/script_store.zig").store();
        inline for (.{ script.oldfiles, script.includees, script.freeids, script.exports, script.embargoes, script.lastname, script.suppressids, script.col_fn, script.detrop, script.rfl, script.ld_stuff, script.fnts }) |field| {
            if (field >= @import("../graph/word.zig").ATOMLIMIT) {
                if (field >= top_limit) {
                    std.debug.panic("runtime.validate: script store field has out-of-bounds heap reference {d} (TOP is {d})", .{ field, top_limit });
                }
            }
        }
    }
};

/// Pointer to the singleton runtime state held in `current_interp` (so
/// `interp.reset()` clears it). Accessed as `rt.rs().X`.
pub inline fn rs() *RuntimeState {
    return &@import("../session/interp.zig").current_interp.rs;
}

test "RuntimeState default values are self-consistent" {
    const state: RuntimeState = .{};
    try std.testing.expectEqual(@as(Word, NIL), state.primenv);
    try std.testing.expectEqual(true, state.strictif);
    try std.testing.expectEqual(@as(Word, 1), state.initialising);
}

test "RuntimeState bool fields default to false" {
    const state: RuntimeState = .{};
    try std.testing.expect(!state.magic);
}

test "RuntimeState null-initialised optional fields" {
    const state: RuntimeState = .{};
    try std.testing.expectEqual(@as(?[*:0]const u8, null), state.rc_error);
}
