//! interp.zig — the unified interpreter context (shared-state plan Phase 3).
//!
//! `Interp` owns every interpreter state struct as a value field. The
//! process-wide singleton is `interp`; each owner module re-points its own
//! singleton at the matching field (`lex_state.ls = &interp.lex`, etc.), so the
//! ~2,100 existing `owner.singleton.field` access sites are unchanged — they now
//! read/write through `interp`.
//!
//! This is the transitional aggregation: still one global, but a single one.
//! Phase 4 adds `init`/`deinit` and makes it injectable (constructing a fresh
//! `Interp` per test); Phase 5 threads `*Interp`; Phase 6 deletes the global.
//!
//! Circular imports: every owner module imports this file (for `&interp.X`) and
//! this file imports every owner (for the struct *type*). That is fine in Zig —
//! a struct's size depends only on its fields, not on the lazily-evaluated
//! `&interp.X` pointer consts, so there is no comptime size cycle.

const RuntimeState = @import("runtime_state.zig").RuntimeState;
const Heap = @import("heap.zig").Heap;
const LexState = @import("../parser/lex_state.zig").LexState;
const CompilerState = @import("../compiler/compiler_state.zig").CompilerState;
const CoreState = @import("core_state.zig").CoreState;
const IoState = @import("word.zig").IoState;
const EvalState = @import("reduce.zig").EvalState;
const Bignum = @import("big.zig").Bignum;

/// All interpreter state, owned in one place. (Bootstrap infrastructure —
/// `allocator`/`gpa`/`io`/`environ` in `runtime_state.zig` — and the interned
/// `strtab` table remain separate globals for now; folded in a follow-up.)
pub const Interp = struct {
    rs: RuntimeState = .{},
    heap: Heap = .{},
    lex: LexState = .{},
    comp: CompilerState = .{},
    core: CoreState = .{},
    io: IoState = .{},
    eval: EvalState = .{},
    big: Bignum = .{},
};

/// The process-wide singleton (transitional; becomes an injectable value in
/// Phase 4 and loses its global home in Phase 6).
pub var interp: Interp = .{};

/// Reset the interpreter to a pristine state — the injectability the
/// pre-threading architecture allows: a test calls this to start from a clean
/// slate, independent of whatever ran before, instead of relying on partial
/// ad-hoc re-init. The owner-module pointers (`lex_state.ls = &interp.lex`, …)
/// stay valid because `interp` keeps its address; only its value is replaced.
///
/// Resets the eight aggregated state structs. Bootstrap infra
/// (`allocator`/`io`/`gpa`/`environ`) and the process-wide `strtab` cache are
/// intentionally *not* reset (the latter is content-addressed, so sharing it is
/// harmless); heap's still-loose scratch (2b) is re-established by callers'
/// `setupheap`. Old heap/arena allocations are dropped (fine under the test
/// allocator); a freeing `deinit` arrives with explicit construction in Phase 5.
pub fn reset() void {
    interp = .{};
}
