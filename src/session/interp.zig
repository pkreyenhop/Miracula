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

const runtime_mod = @import("../runtime/runtime_state.zig");
const heap_mod = @import("../graph/heap.zig");
const lex_mod = @import("../parser/lex_state.zig");
const compiler_mod = @import("../compiler/compiler_state.zig");
const core_mod = @import("../runtime/core_state.zig");
const stream_mod = @import("../eval/stream.zig");
const resources_mod = @import("../eval/resources.zig");
const eval_mod = @import("../eval/reduce_rt.zig");
const big_mod = @import("../graph/bignum.zig");
const match_mod = @import("../semantics/match.zig");
const lower_mod = @import("../semantics/lower.zig");
const infer_mod = @import("../semantics/infer.zig");
const parser_api_mod = @import("../parser/parser_api.zig");
const session_repl_mod = @import("repl.zig");
const reduce_core_mod = @import("../eval/reduce_core.zig");
const reduce_engine_mod = @import("../eval/reduce.zig");
const strtab_mod = @import("../graph/strtab.zig");
const editor_mod = @import("editor.zig");
const symbols_mod = @import("../semantics/symbols.zig");
const make_mod = @import("make_state.zig");
const bnf_mod = @import("bnf_state.zig");
const show_mod = @import("../semantics/show_fns.zig");
const repl_mod = @import("repl_session.zig");
const config_mod = @import("config_state.zig");
const script_mod = @import("script_store.zig");

const RuntimeState = runtime_mod.RuntimeState;
const Heap = heap_mod.Heap;
const LexState = lex_mod.LexState;
const CompilerState = compiler_mod.CompilerState;
const CoreState = core_mod.CoreState;
const IoState = stream_mod.IoState;
const EvalState = eval_mod.EvalState;
const Bignum = big_mod.Bignum;
const StringTable = strtab_mod.StringTable;
const LineEditState = editor_mod.LineEditState;
const SymbolTable = symbols_mod.SymbolTable;
const MakeState = make_mod.MakeState;
const BnfState = bnf_mod.BnfState;
const ShowFns = show_mod.ShowFns;
const ReplSession = repl_mod.ReplSession;
const ConfigState = config_mod.ConfigState;
const ScriptStore = script_mod.ScriptStore;

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
    /// The identifier dictionary (docs/GoReady.md Phase 1 step 6):
    /// replaces `LexState.namebucket`'s fixed-size hash-bucket array. See
    /// `semantics/symbols.zig`.
    symbols: SymbolTable = .{},
    /// The `//make`/`-make` build-mode flags and failure list (Phase 4 step
    /// 4, docs/GoReady.md): the first field carved out of the
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
    /// The currently-loaded script's module/name tables (Phase 4 step 4,
    /// the last of the six state-bag slices).
    script: ScriptStore = .{},
};

/// Backing storage for the default interpreter instance. Not read directly —
/// go through `current_interp`, which is what every accessor and `reset()` do.
var backing: Interp = .{};

/// The interpreter instance the process is currently running — read by every
/// owner module's singleton accessor (`heap.heap()`, `core_state.s()`, …) and
/// by the one irreducible C-ABI exception: OS signal handlers, which cannot
/// take parameters and so read `current_interp` directly.
pub var current_interp: *Interp = &backing;

fn activeHeapTop() i64 {
    return current_interp.heap.TOP();
}

pub fn setCurrent(interp: *Interp) void {
    current_interp = interp;
    if (@import("version_options").force_gc_every_allocation) {
        interp.heap.force_gc_every = 1;
    }
    runtime_mod.bind(&interp.rs, activeHeapTop);
    heap_mod.bind(&interp.heap);
    heap_mod.bindInitClock(eval_mod.initclock);
    lex_mod.bind(&interp.lex);
    @import("../parser/lex.zig").bindTypeGeneralizer(infer_mod.genlstatType);
    parser_api_mod.bindEvaluator(session_repl_mod.evaluateRepl);
    reduce_core_mod.bindReducer(reduce_engine_mod.reduce);
    compiler_mod.bind(&interp.comp);
    core_mod.bind(&interp.core);
    stream_mod.bind(&interp.io);
    stream_mod.bindProcessIo(runtime_mod.io);
    resources_mod.bind(&interp.io.resources);
    resources_mod.bindNativeCloser(stream_mod.closeOpaque);
    eval_mod.bind(&interp.eval);
    big_mod.bind(&interp.big);
    big_mod.bindMathError(eval_mod.mathError);
    match_mod.bindLower(lower_mod.fallible, lower_mod.codegen);
    strtab_mod.bind(&interp.strtab);
    editor_mod.bind(&interp.lineedit);
    symbols_mod.bindActive(&interp.symbols);
    make_mod.bind(&interp.make);
    bnf_mod.bind(&interp.bnf);
    show_mod.bind(&interp.show);
    repl_mod.bind(&interp.repl);
    config_mod.bind(&interp.config);
    script_mod.bind(&interp.script);
}

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
    setCurrent(current_interp);
    const active = current_interp;
    const next_resource_id = active.io.resources.next_id;
    active.io.resources.reset(@import("../runtime/runtime_state.zig").allocator);
    active.heap.roots.reset(@import("../runtime/runtime_state.zig").allocator);
    active.* = .{};
    active.io.resources.next_id = next_resource_id;
    if (@import("version_options").force_gc_every_allocation) {
        active.heap.force_gc_every = 1;
    }
}

// Tests: Interp: two independent instances stay isolated when interleaved
test "Interp: two independent instances stay isolated when interleaved" {
    const std = @import("std");
    const heap_api = @import("../graph/heap.zig");
    const lex = @import("../parser/lex.zig");
    const setup = @import("../compiler/setup.zig");
    const reduce = @import("../eval/reduce.zig");
    const big = @import("../graph/bignum.zig");
    const word = @import("../graph/word.zig");
    const Value = @import("../graph/value.zig").Value;

    // Phase 4 step 6, docs/GoReady.md: the phase's definition of done.
    // Every production call path is receiver-threaded from main() down to
    // reduce()/miraSetup(); this constructs two Interps directly (bypassing
    // the module-level `backing` default) and swaps `current_interp` between
    // them mid-evaluation to prove neither leaks into or corrupts the other.
    var interp_a: Interp = .{};
    var interp_b: Interp = .{};
    const saved = current_interp;
    defer setCurrent(saved);

    setCurrent(&interp_a);
    lex.setupdic();
    setup.miraSetup(heap_api.heap());
    const a_val = big.fromInt(heap_api.heap(), 111);

    setCurrent(&interp_b);
    lex.setupdic();
    setup.miraSetup(heap_api.heap());
    const b_val = big.fromInt(heap_api.heap(), 222);

    // Churn interp_b's heap heavily while interp_a sits untouched: if the two
    // ever aliased the same underlying storage (a stray cached pointer, a
    // singleton read that missed the swap), b's allocations would move or
    // overwrite a's cell and the check below would see garbage instead of 112.
    var i: usize = 0;
    while (i < 2000) : (i += 1) {
        _ = heap_api.make(heap_api.heap(), .CONS, word.NIL, word.NIL);
    }

    setCurrent(&interp_a);
    const r_a = try reduce.reduce(heap_api.heap(), reduce.ap2(heap_api.heap(), Value.fromRaw(word.PLUS), Value.fromRaw(a_val), Value.fromRaw(big.fromInt(heap_api.heap(), 1))).toRaw());
    try std.testing.expectEqual(@as(i64, 112), @as(i64, @intCast(big.toInt(heap_api.heap(), r_a))));

    setCurrent(&interp_b);
    const r_b = try reduce.reduce(heap_api.heap(), reduce.ap2(heap_api.heap(), Value.fromRaw(word.TIMES), Value.fromRaw(b_val), Value.fromRaw(big.fromInt(heap_api.heap(), 2))).toRaw());
    try std.testing.expectEqual(@as(i64, 444), @as(i64, @intCast(big.toInt(heap_api.heap(), r_b))));

    // Reverse direction: churn interp_a, then confirm interp_b is unaffected.
    setCurrent(&interp_a);
    i = 0;
    while (i < 2000) : (i += 1) {
        _ = heap_api.make(heap_api.heap(), .CONS, word.NIL, word.NIL);
    }
    setCurrent(&interp_b);
    const r_b2 = try reduce.reduce(heap_api.heap(), reduce.ap2(heap_api.heap(), Value.fromRaw(word.PLUS), Value.fromRaw(b_val), Value.fromRaw(big.fromInt(heap_api.heap(), 1))).toRaw());
    try std.testing.expectEqual(@as(i64, 223), @as(i64, @intCast(big.toInt(heap_api.heap(), r_b2))));
}

test "Interp: independently owned state remains isolated under concurrent mutation" {
    const std = @import("std");

    const Worker = struct {
        fn run(interp: *Interp, heap_marker: i64, limit: i64, verbosity: i32) void {
            var i: usize = 0;
            while (i < 50_000) : (i += 1) {
                interp.heap.files = heap_marker;
                interp.config.SPACELIMIT = limit;
                interp.repl.verbosity = verbosity;
                interp.core.errline = @intCast(i);
            }
        }
    };

    var a: Interp = .{};
    var b: Interp = .{};
    const ta = try std.Thread.spawn(.{}, Worker.run, .{ &a, 111, 12_000, 1 });
    const tb = try std.Thread.spawn(.{}, Worker.run, .{ &b, 222, 24_000, 2 });
    ta.join();
    tb.join();

    try std.testing.expectEqual(@as(i64, 111), a.heap.files);
    try std.testing.expectEqual(@as(i64, 222), b.heap.files);
    try std.testing.expectEqual(@as(i64, 12_000), a.config.SPACELIMIT);
    try std.testing.expectEqual(@as(i64, 24_000), b.config.SPACELIMIT);
    try std.testing.expectEqual(@as(i32, 1), a.repl.verbosity);
    try std.testing.expectEqual(@as(i32, 2), b.repl.verbosity);
}
