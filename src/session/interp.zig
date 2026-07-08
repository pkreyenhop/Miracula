//! interp.zig — the unified interpreter context (shared-state plan Phase 6).
//!
//! `Interp` owns every interpreter state struct as a value field. Every owner
//! module reads its state through `current_interp` (`heap.heap()`,
//! `core_state.s()`, …), a pointer rather than a fixed address, so the
//! ~2,100 existing access sites now read `owner.singleton().field` instead of
//! a `const`-computed address — one extra indirection, but no change to
//! *which* struct they reach.
//!
//! `current_interp` defaults to `&backing` (a real, zero-initialized `Interp`
//! living right here) so the test binary — which never runs `main()` — has a
//! valid interpreter from the first access, matching the old `pub var interp`
//! singleton's behavior exactly. `main()` may still construct and point at a
//! separate `Interp` explicitly if it wants to (the capability Phase 4/5
//! built); the production path does not need to for `current_interp` to work.
//!
//! Circular imports: every owner module imports this file (for `current_interp.X`)
//! and this file imports every owner (for the struct *type*). That is fine in
//! Zig — a struct's size depends only on its fields, not on the lazily-evaluated
//! accessor functions, so there is no comptime size cycle.

const RuntimeState = @import("../runtime/runtime_state.zig").RuntimeState;
const Heap = @import("../graph/heap.zig").Heap;
const LexState = @import("../parser/lex_state.zig").LexState;
const CompilerState = @import("../compiler/compiler_state.zig").CompilerState;
const CoreState = @import("../runtime/core_state.zig").CoreState;
const IoState = @import("../graph/word.zig").IoState;
const EvalState = @import("../eval/reduce_rt.zig").EvalState;
const Bignum = @import("../graph/bignum.zig").Bignum;
const StringTable = @import("../graph/strtab.zig").StringTable;
const LineEditState = @import("editor.zig").LineEditState;
const SymbolTable = @import("../semantics/symbols.zig").SymbolTable;
const MakeState = @import("make_state.zig").MakeState;
const BnfState = @import("bnf_state.zig").BnfState;
const ShowFns = @import("../semantics/show_fns.zig").ShowFns;
const ReplSession = @import("repl_session.zig").ReplSession;
const ConfigState = @import("config_state.zig").ConfigState;

/// All interpreter state, owned in one place — including heap's GC/dictionary
/// scratch (folded into `heap` by Phase 2b), the interned `strtab` table, and
/// the interactive line-editor's state (`lineedit`, only ever populated when
/// stdin is a TTY). (Only bootstrap infrastructure —
/// `allocator`/`gpa`/`io`/`environ` in `runtime_state.zig` — stays a separate
/// global, set once at startup.)
pub const Interp = struct {
    rs: RuntimeState = .{},
    heap: Heap = .{},
    lex: LexState = .{},
    comp: CompilerState = .{},
    core: CoreState = .{},
    io: IoState = .{},
    eval: EvalState = .{},
    big: Bignum = .{},
    strtab: StringTable = .{},
    lineedit: LineEditState = .{},
    /// The identifier dictionary (docs/ZIG_NATIVE_PLAN.md Phase 1 step 6):
    /// replaces `LexState.namebucket`'s fixed-size hash-bucket array. See
    /// `semantics/symbols.zig`.
    symbols: SymbolTable = .{},
    /// The `//make`/`-make` build-mode flags and failure list (Phase 4 step
    /// 4, docs/ZIG_NATIVE_PLAN.md): the first field carved out of the
    /// monolithic `RuntimeState`.
    make: MakeState = .{},
    /// The `%bnf` grammar-extension bookkeeping (Phase 4 step 4): mostly
    /// dead GC roots left over from Phase 1's lexer rewrite.
    bnf: BnfState = .{},
    /// The per-type `show` combinator identifiers (Phase 4 step 4).
    show: ShowFns = .{},
    /// Interactive REPL state (Phase 4 step 4): last expression/id, echo/
    /// listing/verbosity flags, prompt string, and timing scratch.
    repl: ReplSession = .{},
    /// Process-wide startup configuration (Phase 4 step 4): prelude/stdenv
    /// paths, heap/dictionary limits, editor, open source stream.
    config: ConfigState = .{},
};

/// Backing storage for the default interpreter instance. Not read directly —
/// go through `current_interp`, which is what every accessor and `reset()` do.
var backing: Interp = .{};

/// The interpreter instance the process is currently running — read by every
/// owner module's singleton accessor (`heap.heap()`, `core_state.s()`, …) and
/// by the one irreducible C-ABI exception: OS signal handlers, which cannot
/// take parameters and so read `current_interp` directly.
pub var current_interp: *Interp = &backing;

/// Reset the interpreter to a pristine state — the injectability the
/// pre-threading architecture allows: a test calls this to start from a clean
/// slate, independent of whatever ran before, instead of relying on partial
/// ad-hoc re-init. Every owner accessor reads through `current_interp` at
/// call time, so replacing `current_interp.*` (not its address) is enough —
/// no pointer anywhere goes stale.
///
/// Resets all aggregated state — the ten structs including `heap` (with its 2b
/// scratch) and `strtab` (whose `initialized = false` makes the next access
/// re-intern from empty). Only the startup bootstrap infra
/// (`allocator`/`io`/`gpa`/`environ`) is left alone. Old heap/arena allocations
/// are dropped (fine under the test allocator); a freeing `deinit` arrives with
/// explicit construction in Phase 5.
///
/// `lineedit`'s `active` flag defaults back to `false` on reset — safe in
/// practice since it's only ever `true` when stdin is a TTY, which no test
/// run is, so `reset()` never blows away a live editor's system resources
/// (terminal state, allocated history) without going through its own
/// `deinit()` first.
pub fn reset() void {
    current_interp.* = .{};
}
