//! reduce_core.zig — the reduction machine's primitives, shared by the rewrite
//! handlers (`combinators.zig`, `ready.zig`, `lex.zig`, `io.zig`, which all
//! import this file as `reduce`). It owns the `ReductionCtx` register file and
//! the spine-traversal/accessor/classifier/rewrite helpers.
//!
//! **Typed registers (Phase 5 step 4, docs/ZIG_NATIVE_PLAN.md, 2026-07-13).**
//! `ReductionCtx.e`/`.hold`/`.args` and every accessor/classifier/rewrite
//! helper below now carry `graph/value.zig`'s `Value` instead of a bare
//! `Word`. This is a real retype, not a wrapper: `Value` is a
//! `packed struct(u64) { raw: i64 }`, bit-identical to the `Word` it
//! replaces, so the reducer's actual behavior — every reduction step, every
//! bit pattern written to a cell — is unchanged; only the type flowing
//! through this file's API changed. Functions this file calls that are
//! *not yet* migrated (`bignum.zig`, `strtab.zig`, `heap.zig`'s
//! `getDbl`/`stoDbl`, `reducer/reduce.zig`'s own `reduce()`) are called
//! through `Value.fromRaw`/`.toRaw()` at the boundary — the same escape
//! hatch named in `graph/value.zig`'s own doc comment. `reduce_rt.zig`'s
//! own public API (`head`/`force`/`getstring`/`compare`/`numplus`/
//! `badcaseError`/`confError`/`gResidue`/`memclass`/`lexfail`/`lexstate`/
//! `wrapPtr`/`piperrmess`/`apfile`/`closefile`/`outf`/`print`/`output`/
//! `outHere`) was retyped onto `Value` in a later slice than this file's
//! own (see that file's module doc); the `xxxVal` wrappers below now just
//! forward to them directly.
//!
//! **Spine representation (B2 option (b), 2026-07-01; retyped 2026-07-12).**
//! The spine used to be encoded in-graph via pointer reversal: a cell's own
//! `hd`/`tl` field temporarily borrowed to hold the "previous stack top"
//! pointer, tagged with `tlptrbits`. It is now `ctx.spine`, an explicit
//! `Spine` (see `spine.zig`) carrying `Value` directly — no cell ever holds
//! a borrowed value, and no access needs `& ~tlptrbits` masking. The
//! traversal primitives below (`downLeft`/`downRight`/`upLeft`/`upRight`)
//! are thin wrappers over `Spine`'s methods of the same name.
//!
//! **Narrow substructure threading (SHARED_STATE Phase 6, 2026-07-01).** The
//! cell-accessor primitives (`hdGet`/`tlGet`/`getTag`/`ap`/`cons`/`isXxx`/
//! `rewriteToXxx`/…) take an explicit `heap: *Heap` parameter instead of
//! reaching the global `interp.heap` singleton ambiently. Functions that
//! already carry `ctx: *ReductionCtx` (which now owns a `heap` field) don't
//! need a *second* explicit parameter — they pass `ctx.heap` through to the
//! leaf primitives internally.

const std = @import("std");
const word = @import("../graph/word.zig");
const strtab = @import("../graph/strtab.zig");
const spine = @import("spine.zig");
const heap_mod = @import("../graph/heap.zig");
const rt = @import("../runtime/runtime_state.zig");
const value_mod = @import("../graph/value.zig");

/// The interpreter machine word (see `word.Word`). Still used at the
/// boundary with not-yet-migrated subsystems (`bignum`/`strtab`/`EvalState`)
/// and for genuinely scalar (non-graph-value) results like `getsmallint`'s
/// decoded integer.
pub const Word = i64;
/// The typed graph value (see `graph/value.zig`) — what `ReductionCtx.e`/
/// `.hold`/`.args` and every accessor/classifier/rewrite helper below carry.
pub const Value = value_mod.Value;
/// The cell arena (see `heap.zig`); threaded explicitly by the primitives below.
pub const Heap = heap_mod.Heap;

/// Re-export of [word.ReduceError] (defined there, not here, so `heap.zig`
/// can return it from `stoDbl`/`setdbl` without importing this module back
/// — see `word.zig`'s doc comment on `ReduceError` for the cycle rationale).
pub const ReduceError = word.ReduceError;

/// The reduction machine's register file. See `reducer/reduce.zig` for the
/// protocol: `e` focus node · `spine` the explicit spine stack (see
/// `spine.zig`) · `hold` general scratch (used by many handlers for
/// unrelated temporaries, not just spine bookkeeping) · `args` pulled
/// arguments · `action` post-dispatch signal (`ACT_NONE`/`ACT_NEXTREDEX`/
/// `ACT_DONE`) · `heap` the cell arena this reduction runs against · `eval`
/// I/O and evaluation-error-recovery state · `rs` the interpreter-wide
/// `RuntimeState` (`ready.zig`'s `SHOWNUM`/`SHOWHEX`/`SHOWSCALED`/
/// `SHOWFLOAT`/`GETENV` handlers read `ctx.rs.linebuf`/`ctx.rs.UTF8` through
/// it as of Tier 4's `RuntimeState` increment, 2026-07-05 — despite both
/// being whole-interpreter shared state used well beyond the reducer, adding
/// the field costs nothing once `ctx` is already threaded everywhere).
pub const ReductionCtx = struct {
    /// Focus node: the redex currently under examination (the "expression" register).
    e: Value,
    /// The explicit spine stack (replaces the old in-graph pointer-reversal
    /// encoding — see the module doc above).
    spine: spine.Spine,
    /// General-purpose scratch used by many handlers for local temporaries.
    hold: Value,
    /// Arguments pulled off the spine for the current combinator rewrite.
    args: [4]Value,
    /// Post-dispatch signal: `ACT_NONE` / `ACT_NEXTREDEX` / `ACT_DONE`.
    action: c_int,
    /// The cell arena backing every accessor/allocator call this reduction makes.
    heap: *Heap,
    /// I/O and evaluation-error-recovery state (`Tier 4` of the shared-state
    /// plan — mirrors `heap`'s Tier 1.5 threading; see [reduce_mod.EvalState]).
    eval: *reduce_mod.EvalState,
    /// Interpreter-wide runtime state (`Tier 4`, `RuntimeState`) — same
    /// threading rationale as `eval`.
    rs: *rt.RuntimeState,
};

// Re-exports so handlers can reach engine/lexer helpers as `reduce.<name>`.

/// Re-export of [reduce_mod.print] (the graph-value printer).
pub const print = reduce_mod.print;
/// Re-export of [reduce_mod.badcaseError] (the no-matching-case abort).
pub const badcaseError = reduce_mod.badcaseError;
/// Re-export of [reduce_mod.confError] (the conformality-error abort).
pub const confError = reduce_mod.confError;
/// Re-export of [lex_mod.convArgs] (command-line args as a Miranda list).
pub const convArgs = lex_mod.convArgs;
/// Re-export of [reduce_mod.getstring] (a char list flattened to a C string).
pub const getstring = reduce_mod.getstring;
/// Re-export of [reduce_mod.head] (the head atom of an application spine).
pub const head = reduce_mod.head;
/// Re-export of [reduce_mod.force] (deep evaluation to normal form).
pub const force = reduce_mod.force;
/// Re-export of the engine entry point [reducer_reduce.reduce] (reduce to WHNF).
pub const reduce = reducer_reduce.reduce;

// `Value`-typed wrappers over the above, still-`Word`-typed cross-boundary
// functions — `reduce()`/`head()`/`force()`/`getstring()`/`badcaseError()`/
// `confError()` themselves keep their `Word` signatures (they're called from
// far outside the reducer too; retyping them is out of scope for this
// slice), but every combinator handler's own state (`ctx.e`/`.args`/`.hold`
// and their local temporaries) is `Value` now, so handlers call these
// instead of doing `.toRaw()`/`Value.fromRaw()` at every one of the ~80
// call sites across `combinators.zig`/`ready.zig`/`combinators/lex.zig`/
// `combinators/io.zig`.

/// `Value`-typed [reduce]: reduce `e` to WHNF and return the rewritten root.
pub inline fn reduceVal(heap: *Heap, e: Value) ReduceError!Value {
    return Value.fromRaw(try reduce(heap, e.toRaw()));
}

/// `Value`-typed [head]: the head atom of application spine `x`.
///
/// `head`/`force`/`getstring`/`badcaseError`/`confError` in `reduce_rt.zig`
/// were themselves retyped onto `Value` in a later slice than this wrapper
/// layer's original commit; these four are now trivial passthroughs kept
/// under their original names so the ~80 call sites across
/// `combinators.zig`/`ready.zig`/`combinators/lex.zig`/`combinators/io.zig`
/// that already call `reduce.headVal`/etc. didn't need a second rename.
pub inline fn headVal(heap: *Heap, x: Value) Value {
    return head(heap, x);
}

/// `Value`-typed [force]: deep-evaluate `x` to normal form in place.
pub inline fn forceVal(heap: *Heap, x: Value) ReduceError!void {
    return force(heap, x);
}

/// `Value`-typed [getstring]: flatten char-list `x` to a C string.
pub inline fn getstringVal(heap: *Heap, x: Value, cmd: ?[*:0]const u8) ReduceError!?[*:0]u8 {
    return getstring(heap, x, cmd);
}

/// `Value`-typed [badcaseError]: abort with "no matching case" for `arg_info`.
pub inline fn badcaseErrorVal(heap: *Heap, arg_info: Value) ReduceError!void {
    return badcaseError(heap, arg_info);
}

/// `Value`-typed [confError]: report a conformality error for `arg_info`.
pub inline fn confErrorVal(heap: *Heap, arg_info: Value) void {
    confError(heap, arg_info);
}

/// Strip the spine direction bits and yield a plain heap index. Dead code
/// (no external callers survive the Spine cutover — the direction-bit
/// encoding it existed for is gone, see `spine.zig`'s module doc) but kept,
/// still correct, rather than deleted as a drive-by in a type-migration
/// commit.
pub inline fn cleanPtr(x: Value) usize {
    return @as(usize, @intCast(x.toRaw() & 0x3fffffffffffffff));
}

// Cross-module functions via direct (circular) @import — R7.3.
const reduce_mod = @import("reduce_rt.zig");
const reducer_reduce = @import("reduce.zig");
const lex_mod = @import("../parser/lex.zig");
const big = @import("../graph/bignum.zig");
const os = @import("../os.zig");
const tu = @import("../testutil.zig"); // unit-test harness (test builds only)

// Cell access through a spine word (mask off direction bits, then index the
// heap). This is the raw-`Word` value boundary the B2 `Heap`/`Value` seam will
// type. Mirrors `reducer/reduce.zig`.

/// Read the head (`hd`) field through (possibly marked) spine word `x`.
pub inline fn hdGet(heap: *Heap, x: Value) Value {
    return Value.fromRaw(heap.hCell(x.toRaw() & 0x3fffffffffffffff));
}

/// Write the head (`hd`) field through spine word `x`.
pub inline fn hdSet(heap: *Heap, x: Value, val: Value) void {
    heap.hp(x.toRaw() & 0x3fffffffffffffff).* = val.toRaw();
}

/// Read the tail (`tl`) field through spine word `x`.
pub inline fn tlGet(heap: *Heap, x: Value) Value {
    return Value.fromRaw(heap.tCell(x.toRaw() & 0x3fffffffffffffff));
}

/// Write the tail (`tl`) field through spine word `x`.
pub inline fn tlSet(heap: *Heap, x: Value, val: Value) void {
    heap.tp(x.toRaw() & 0x3fffffffffffffff).* = val.toRaw();
}

/// Read the cell tag through spine word `x`.
pub inline fn getTag(heap: *Heap, x: Value) word.NodeTag {
    return heap.getTag(x.toRaw() & 0x3fffffffffffffff);
}

/// Write the cell tag through spine word `x`.
pub inline fn setTag(heap: *Heap, x: Value, val: word.NodeTag) void {
    heap.setTag(x.toRaw() & 0x3fffffffffffffff, val);
}

/// A pointer to the tail (`tl`) field through spine word `x` (for in-place
/// edits). Stays `*Word`, not `*Value`: its one caller (`combinators.zig`'s
/// `handleWAIT`) walks a pointer that starts at `EvalState.waiting` (a plain
/// `Word` field, not yet migrated) and is then reseated into heap memory via
/// this function — both ends of that walk must agree on one type, and
/// `EvalState` is out of scope for this slice.
pub inline fn tlPtr(heap: *Heap, x: Value) *Word {
    return heap.tp(x.toRaw() & 0x3fffffffffffffff);
}

// Tests: hdGet/hdSet/tlGet/tlSet/getTag/setTag/tlPtr: read/write a cell's
// fields and tag through a Value handle
test "hdGet/hdSet/tlGet/tlSet/getTag/setTag/tlPtr: read/write a cell's fields and tag" {
    tu.freshInterp();
    const heap_ptr = heap_mod.heap();
    const cell = cons(heap_ptr, Value.imm(1), Value.imm(2));

    try std.testing.expectEqual(word.NodeTag.CONS, getTag(heap_ptr, cell));
    try std.testing.expectEqual(Value.imm(1), hdGet(heap_ptr, cell));
    try std.testing.expectEqual(Value.imm(2), tlGet(heap_ptr, cell));

    hdSet(heap_ptr, cell, Value.imm(9));
    tlSet(heap_ptr, cell, Value.imm(8));
    try std.testing.expectEqual(Value.imm(9), hdGet(heap_ptr, cell));
    try std.testing.expectEqual(Value.imm(8), tlGet(heap_ptr, cell));

    setTag(heap_ptr, cell, .PAIR);
    try std.testing.expectEqual(word.NodeTag.PAIR, getTag(heap_ptr, cell));

    // tlPtr reaches the same storage tlGet/tlSet do.
    tlPtr(heap_ptr, cell).* = 7;
    try std.testing.expectEqual(Value.imm(7), tlGet(heap_ptr, cell));
}

// Spine traversal — see `spine.zig` for the mechanics. `downX`/`upX` push/pop
// the explicit spine; the lowercase wrappers (`downright`/`upleft`) stop when
// the spine is exhausted (the old `s < 0` bottom-of-spine sentinel's
// replacement).

/// Descend into the head: push `e` onto the spine.
pub inline fn downLeft(ctx: *ReductionCtx) void {
    ctx.e = ctx.spine.downLeft(ctx.e);
}

/// Descend into the tail of the spine's current top frame.
pub inline fn downRight(ctx: *ReductionCtx) void {
    ctx.e = ctx.spine.downRight(ctx.heap, ctx.e);
}

/// [downRight] guarded by `atArgumentChainBoundary` (replaces the old
/// `abnormal(ctx.s)`/`ctx.s < 0` guard — true when the spine is truly empty
/// *or* the top frame is already `via_tl=true`; see `Spine.atArgumentChainBoundary`).
pub inline fn downright(ctx: *ReductionCtx) bool {
    if (ctx.spine.atArgumentChainBoundary()) {
        return true;
    }
    downRight(ctx);
    return false;
}

/// Ascend out of the head: pop the spine into `e`.
pub inline fn upLeft(ctx: *ReductionCtx) void {
    ctx.e = ctx.spine.upLeft(ctx.heap, ctx.e);
}

/// [upLeft] guarded by `atArgumentChainBoundary` (replaces the old
/// `abnormal(ctx.s)`/`ctx.s < 0` guard — see `downright` above).
pub inline fn upleft(ctx: *ReductionCtx) bool {
    if (ctx.spine.atArgumentChainBoundary()) {
        return true;
    }
    upLeft(ctx);
    return false;
}

/// Ascend out of the tail of the spine's current (still-top) frame.
pub inline fn upRight(ctx: *ReductionCtx) void {
    ctx.e = ctx.spine.upRight(ctx.heap, ctx.e);
}

/// Pull the next argument off the spine into `a` (unchecked — caller knows it exists).
pub inline fn GETARG(ctx: *ReductionCtx, a: *Value) void {
    upLeft(ctx);
    a.* = tlGet(ctx.heap, ctx.e);
}

/// Pull the next argument off the spine into `a`; true if the spine is exhausted.
pub inline fn getarg(ctx: *ReductionCtx, a: *Value) bool {
    if (upleft(ctx)) {
        return true;
    }
    a.* = tlGet(ctx.heap, ctx.e);
    return false;
}

/// Overwrite the focus node with an `I`-indirection to `r` and refocus on `r`
/// (the in-place "simplify to" rewrite that preserves sharing).
pub inline fn simpl(ctx: *ReductionCtx, r: Value) void {
    hdSet(ctx.heap, ctx.e, Value.comb(.I));
    tlSet(ctx.heap, ctx.e, r);
    ctx.e = r;
}

/// A `ReductionCtx` wired up the same way [reduce] wires its own machine
/// state, for direct unit tests of the traversal/rewrite primitives below
/// (mirrors `spine.zig`'s own test setup, one layer up). Callers must
/// `ctx.spine.register(&ctx.eval.gc_roots_head)` themselves once `ctx` is at
/// its final address — registering here and returning by value would leave
/// the registered pointer dangling into this function's stack frame.
fn testCtx() ReductionCtx {
    var ctx: ReductionCtx = undefined;
    ctx.heap = heap_mod.heap();
    ctx.eval = reduce_mod.ev();
    ctx.rs = rt.rs();
    ctx.spine = spine.Spine.init(rt.allocator, &ctx.eval.spine_buffer_pool);
    ctx.hold = Value.imm(0);
    ctx.args = .{ Value.imm(0), Value.imm(0), Value.imm(0), Value.imm(0) };
    ctx.action = word.ACT_NONE;
    return ctx;
}

// Tests: downLeft/downRight/downright/upLeft/upleft/upRight/GETARG/getarg/
// simpl: the ReductionCtx-level spine wrappers, wired through a real ctx
test "downLeft/downRight/downright/upLeft/upleft/upRight: ReductionCtx spine wrappers" {
    tu.freshInterp();
    var ctx = testCtx();
    ctx.spine.register(&ctx.eval.gc_roots_head);
    defer ctx.spine.deinit(&ctx.eval.spine_buffer_pool);
    defer ctx.spine.unregister(&ctx.eval.gc_roots_head);

    // Exhausted (empty-spine) guards report true and leave `e` untouched.
    ctx.e = Value.imm(42);
    try std.testing.expect(downright(&ctx));
    try std.testing.expect(upleft(&ctx));
    try std.testing.expectEqual(Value.imm(42), ctx.e);

    const e = cons(ctx.heap, Value.imm(111), Value.imm(222));
    ctx.e = e;
    downLeft(&ctx);
    try std.testing.expectEqual(Value.imm(111), ctx.e);

    // Head reduced to 'H'; downright descends into the (pristine) tail.
    ctx.e = Value.imm('H');
    try std.testing.expect(!downright(&ctx));
    try std.testing.expectEqual(Value.imm(222), ctx.e);
    try std.testing.expectEqual(Value.imm('H'), hdGet(ctx.heap, e)); // write-back already happened

    // Tail reduced to 'T'; upRight writes it back and refocuses to the head.
    ctx.e = Value.imm('T');
    upRight(&ctx);
    try std.testing.expectEqual(Value.imm('H'), ctx.e);
    try std.testing.expectEqual(Value.imm('T'), tlGet(ctx.heap, e));

    // Leave the cell: upleft pops with the (possibly further-rewritten) head.
    try std.testing.expect(!upleft(&ctx));
    try std.testing.expectEqual(e, ctx.e);
    try std.testing.expect(ctx.spine.isEmpty());
}

test "GETARG/getarg: pull spine arguments, reporting exhaustion" {
    tu.freshInterp();
    var ctx = testCtx();
    ctx.spine.register(&ctx.eval.gc_roots_head);
    defer ctx.spine.deinit(&ctx.eval.spine_buffer_pool);
    defer ctx.spine.unregister(&ctx.eval.gc_roots_head);

    // (f arg) -- downLeft focuses f, then GETARG/getarg pull `arg`.
    const app = ap(ctx.heap, Value.comb(.I), Value.imm(9));
    ctx.e = app;
    downLeft(&ctx);
    try std.testing.expectEqual(Value.comb(.I), ctx.e);

    var a: Value = undefined;
    try std.testing.expect(!getarg(&ctx, &a));
    try std.testing.expectEqual(Value.imm(9), a);
    try std.testing.expectEqual(app, ctx.e); // popped back to the AP cell itself

    // Spine now exhausted: getarg reports true without touching `a`.
    try std.testing.expect(getarg(&ctx, &a));
    try std.testing.expectEqual(Value.imm(9), a);

    // GETARG is the unchecked twin -- same pull when a frame is present.
    downLeft(&ctx);
    var b: Value = undefined;
    GETARG(&ctx, &b);
    try std.testing.expectEqual(Value.imm(9), b);
}

test "simpl: rewrites the focus to an I-indirection and refocuses" {
    tu.freshInterp();
    var ctx = testCtx();
    ctx.spine.register(&ctx.eval.gc_roots_head);
    defer ctx.spine.deinit(&ctx.eval.spine_buffer_pool);
    defer ctx.spine.unregister(&ctx.eval.gc_roots_head);

    // simpl rewrites hd/tl to an I-indirection but leaves the tag alone --
    // real callers only ever apply it to an AP redex cell.
    const e = ap(ctx.heap, Value.imm(1), Value.imm(2));
    ctx.e = e;
    simpl(&ctx, Value.imm(99));
    try std.testing.expectEqual(word.NodeTag.AP, getTag(ctx.heap, e));
    try std.testing.expectEqual(Value.comb(.I), hdGet(ctx.heap, e));
    try std.testing.expectEqual(Value.imm(99), tlGet(ctx.heap, e));
    try std.testing.expectEqual(Value.imm(99), ctx.e);
}

/// True for a marked/sentinel spine word (negative) — not a normal cell handle.
pub inline fn abnormal(x: Value) bool {
    return x.toRaw() < 0;
}
/// True when `x` is a (normal) `AP` application cell.
pub inline fn isAp(heap: *Heap, x: Value) bool {
    return !abnormal(x) and getTag(heap, x) == .AP;
}
/// True when `x` is a number (`INT` or `DOUBLE`) cell.
pub inline fn isNum(heap: *Heap, x: Value) bool {
    if (abnormal(x)) return false;
    const t = getTag(heap, x);
    return t == .INT or t == .DOUBLE;
}
/// True when `x` is a `CONSTRUCTOR` cell.
pub inline fn isConstructor(heap: *Heap, x: Value) bool {
    return !abnormal(x) and getTag(heap, x) == .CONSTRUCTOR;
}
/// True when `x` is an `INT` (bignum) cell.
pub inline fn isInt(heap: *Heap, x: Value) bool {
    return !abnormal(x) and getTag(heap, x) == .INT;
}
/// True when `x` is a `DOUBLE` cell.
pub inline fn isDouble(heap: *Heap, x: Value) bool {
    return !abnormal(x) and getTag(heap, x) == .DOUBLE;
}
/// True when `x` is a bare `ATOM` cell.
pub inline fn isAtom(heap: *Heap, x: Value) bool {
    return !abnormal(x) and getTag(heap, x) == .ATOM;
}
/// True when `x` is a `STRCONS` (interned-string) cell.
pub inline fn isStrcons(heap: *Heap, x: Value) bool {
    return !abnormal(x) and getTag(heap, x) == .STRCONS;
}
/// True when `x` is an `ID` (identifier) cell.
pub inline fn isId(heap: *Heap, x: Value) bool {
    return !abnormal(x) and getTag(heap, x) == .ID;
}
/// The value field of id `x` (its tail).
pub inline fn idVal(heap: *Heap, x: Value) Value {
    return tlGet(heap, x);
}
/// True when `x` is a `DATAPAIR` cell.
pub inline fn isDatapair(heap: *Heap, x: Value) bool {
    return !abnormal(x) and getTag(heap, x) == .DATAPAIR;
}
/// True when `x` is a `STARTREADVALS` cell.
pub inline fn isStartreadvals(heap: *Heap, x: Value) bool {
    return !abnormal(x) and getTag(heap, x) == .STARTREADVALS;
}
/// True when `x` is a `CONS` cell.
pub inline fn isCons(heap: *Heap, x: Value) bool {
    return !abnormal(x) and getTag(heap, x) == .CONS;
}
/// True when `x` is a `UNICODE` (wide-char) cell.
pub inline fn isUnicode(heap: *Heap, x: Value) bool {
    return !abnormal(x) and getTag(heap, x) == .UNICODE;
}

// Tests: abnormal, isAp/isNum/isConstructor/isInt/isDouble/isAtom/isStrcons/
// isId/isDatapair/isStartreadvals/isCons/isUnicode, idVal: cell-tag
// classifiers and the abnormal (marked-word) guard they all share
test "abnormal + isXxx classifiers + idVal: cell-tag checks" {
    tu.freshInterp();
    const heap_ptr = heap_mod.heap();

    // A negative Word is "abnormal" -- a marked/sentinel spine word, not a
    // normal cell handle -- and every isXxx classifier treats it as false.
    const marked = Value.fromRaw(-5);
    try std.testing.expect(abnormal(marked));
    try std.testing.expect(!isAp(heap_ptr, marked));
    try std.testing.expect(!isCons(heap_ptr, marked));

    const mk = struct {
        fn cell(h: *Heap, tag: word.NodeTag) Value {
            return Value.fromRaw(h.make(tag, 0, 0));
        }
    }.cell;

    try std.testing.expect(isAp(heap_ptr, mk(heap_ptr, .AP)));
    try std.testing.expect(isNum(heap_ptr, mk(heap_ptr, .INT)));
    try std.testing.expect(isNum(heap_ptr, mk(heap_ptr, .DOUBLE)));
    try std.testing.expect(!isNum(heap_ptr, mk(heap_ptr, .CONS)));
    try std.testing.expect(isConstructor(heap_ptr, mk(heap_ptr, .CONSTRUCTOR)));
    try std.testing.expect(isInt(heap_ptr, mk(heap_ptr, .INT)));
    try std.testing.expect(isDouble(heap_ptr, mk(heap_ptr, .DOUBLE)));
    try std.testing.expect(isAtom(heap_ptr, mk(heap_ptr, .ATOM)));
    try std.testing.expect(isStrcons(heap_ptr, mk(heap_ptr, .STRCONS)));
    try std.testing.expect(isId(heap_ptr, mk(heap_ptr, .ID)));
    try std.testing.expect(isDatapair(heap_ptr, mk(heap_ptr, .DATAPAIR)));
    try std.testing.expect(isStartreadvals(heap_ptr, mk(heap_ptr, .STARTREADVALS)));
    try std.testing.expect(isCons(heap_ptr, mk(heap_ptr, .CONS)));
    try std.testing.expect(isUnicode(heap_ptr, mk(heap_ptr, .UNICODE)));

    // idVal is the tail of an ID cell.
    const id_cell = Value.fromRaw(heap_ptr.make(.ID, 0, 77));
    try std.testing.expectEqual(Value.imm(77), idVal(heap_ptr, id_cell));
}

/// Rewrite `*expr` in place to an `I`-indirection to `value`, then refocus on it.
pub inline fn rewriteToValue(heap: *Heap, expr: *Value, value: Value) void {
    hdSet(heap, expr.*, Value.comb(.I));
    tlSet(heap, expr.*, value);
    expr.* = value;
}

/// Rewrite `*expr` to `NIL` (the empty list).
pub inline fn rewriteToNil(heap: *Heap, expr: *Value) void {
    rewriteToValue(heap, expr, Value.comb(.NIL));
}

/// Rewrite `*expr` to the pattern-match `FAIL` sentinel.
pub inline fn rewriteToFail(heap: *Heap, expr: *Value) void {
    rewriteToValue(heap, expr, Value.comb(.FAIL));
}

/// Rewrite `*expr` to a failure (currently `NIL`).
pub inline fn rewriteToFailure(heap: *Heap, expr: *Value) void {
    rewriteToValue(heap, expr, Value.comb(.NIL));
}

/// Turn `expr` into a `CONS` cell with the given head (tail left unchanged).
pub inline fn rewriteToConsHead(heap: *Heap, expr: Value, head_value: Value) void {
    setTag(heap, expr, .CONS);
    hdSet(heap, expr, head_value);
}

/// Turn `expr` into a `CONS` cell `(head_value : tail_value)`.
pub inline fn rewriteToCons(heap: *Heap, expr: Value, head_value: Value, tail_value: Value) void {
    setTag(heap, expr, .CONS);
    hdSet(heap, expr, head_value);
    tlSet(heap, expr, tail_value);
}

/// Collapse `expr` to an `I`-indirection and return its existing tail.
pub inline fn rewriteToExistingTail(heap: *Heap, expr: Value) Value {
    hdSet(heap, expr, Value.comb(.I));
    return tlGet(heap, expr);
}

// Tests: rewriteToValue/rewriteToNil/rewriteToFail/rewriteToFailure/
// rewriteToConsHead/rewriteToCons/rewriteToExistingTail: the in-place
// redex-rewrite family
test "rewriteToValue/Nil/Fail/Failure/ConsHead/Cons/ExistingTail: in-place redex rewrites" {
    tu.freshInterp();
    const heap_ptr = heap_mod.heap();

    const cell1 = ap(heap_ptr, Value.imm(0), Value.imm(0));
    var e1 = cell1;
    rewriteToValue(heap_ptr, &e1, Value.imm(77));
    try std.testing.expectEqual(Value.comb(.I), hdGet(heap_ptr, cell1));
    try std.testing.expectEqual(Value.imm(77), tlGet(heap_ptr, cell1));
    try std.testing.expectEqual(Value.imm(77), e1);

    var e2 = ap(heap_ptr, Value.imm(0), Value.imm(0));
    rewriteToNil(heap_ptr, &e2);
    try std.testing.expectEqual(Value.comb(.NIL), e2);

    var e3 = ap(heap_ptr, Value.imm(0), Value.imm(0));
    rewriteToFail(heap_ptr, &e3);
    try std.testing.expectEqual(Value.comb(.FAIL), e3);

    var e4 = ap(heap_ptr, Value.imm(0), Value.imm(0));
    rewriteToFailure(heap_ptr, &e4);
    try std.testing.expectEqual(Value.comb(.NIL), e4);

    // rewriteToConsHead retags in place, leaving the existing tail untouched.
    const e5 = ap(heap_ptr, Value.imm(0), Value.imm(42));
    rewriteToConsHead(heap_ptr, e5, Value.imm(11));
    try std.testing.expectEqual(word.NodeTag.CONS, getTag(heap_ptr, e5));
    try std.testing.expectEqual(Value.imm(11), hdGet(heap_ptr, e5));
    try std.testing.expectEqual(Value.imm(42), tlGet(heap_ptr, e5));

    const e6 = ap(heap_ptr, Value.imm(0), Value.imm(0));
    rewriteToCons(heap_ptr, e6, Value.imm(1), Value.imm(2));
    try std.testing.expectEqual(word.NodeTag.CONS, getTag(heap_ptr, e6));
    try std.testing.expectEqual(Value.imm(1), hdGet(heap_ptr, e6));
    try std.testing.expectEqual(Value.imm(2), tlGet(heap_ptr, e6));

    const e7 = cons(heap_ptr, Value.imm(1), Value.imm(2));
    const tail = rewriteToExistingTail(heap_ptr, e7);
    try std.testing.expectEqual(Value.comb(.I), hdGet(heap_ptr, e7));
    try std.testing.expectEqual(Value.imm(2), tail);
}

/// Allocate an application cell `(x y)`.
pub inline fn ap(heap: *Heap, x: Value, y: Value) Value {
    return Value.fromRaw(heap.make(.AP, x.toRaw(), y.toRaw()));
}

/// Allocate two application cells in bulk.
pub inline fn apTwo(heap: *Heap, x1: Value, y1: Value, x2: Value, y2: Value, c1: *Value, c2: *Value) void {
    var w1: Word = undefined;
    var w2: Word = undefined;
    heap.makeTwo(.AP, x1.toRaw(), y1.toRaw(), .AP, x2.toRaw(), y2.toRaw(), &w1, &w2);
    c1.* = Value.fromRaw(w1);
    c2.* = Value.fromRaw(w2);
}

// Tests: ap/apTwo/cleanPtr: application-cell allocation, singly and in bulk
test "ap/apTwo/cleanPtr: application-cell allocation" {
    tu.freshInterp();
    const heap_ptr = heap_mod.heap();

    const a = ap(heap_ptr, Value.imm(1), Value.imm(2));
    try std.testing.expectEqual(word.NodeTag.AP, getTag(heap_ptr, a));
    try std.testing.expectEqual(Value.imm(1), hdGet(heap_ptr, a));
    try std.testing.expectEqual(Value.imm(2), tlGet(heap_ptr, a));

    var c1: Value = undefined;
    var c2: Value = undefined;
    apTwo(heap_ptr, Value.imm(3), Value.imm(4), Value.imm(5), Value.imm(6), &c1, &c2);
    try std.testing.expectEqual(word.NodeTag.AP, getTag(heap_ptr, c1));
    try std.testing.expectEqual(Value.imm(3), hdGet(heap_ptr, c1));
    try std.testing.expectEqual(Value.imm(4), tlGet(heap_ptr, c1));
    try std.testing.expectEqual(word.NodeTag.AP, getTag(heap_ptr, c2));
    try std.testing.expectEqual(Value.imm(5), hdGet(heap_ptr, c2));
    try std.testing.expectEqual(Value.imm(6), tlGet(heap_ptr, c2));

    // cleanPtr masks off the (unused, post-Spine-cutover) direction bits.
    try std.testing.expectEqual(@as(usize, @intCast(a.toRaw())), cleanPtr(a));
}

/// Rewrite `*expr` to `success_value` if `left` equals `right` (structurally),
/// else to `FAIL` — the pattern-match equality test.
pub inline fn rewriteToMatchResult(heap: *Heap, expr: *Value, left: Value, right: Value, success_value: Value) ReduceError!void {
    hdSet(heap, expr.*, Value.comb(.I));
    const val = if (try reduce_mod.compare(heap, left, right) == 0) success_value else Value.comb(.FAIL);
    tlSet(heap, expr.*, val);
    expr.* = val;
}

/// Rewrite `*expr` to `success_value` if `value` is the int `literal`, else `FAIL`.
pub inline fn rewriteToIntMatchResult(heap: *Heap, expr: *Value, literal: Value, value: Value, success_value: Value) void {
    hdSet(heap, expr.*, Value.comb(.I));
    const val = if (!isInt(heap, value) or big.cmp(heap, literal.toRaw(), value.toRaw()) != 0) Value.comb(.FAIL) else success_value;
    tlSet(heap, expr.*, val);
    expr.* = val;
}

/// Rewrite `*expr` to the Miranda char-list form of C string `value`.
pub inline fn rewriteToString(heap: *Heap, expr: *Value, value: [*:0]const u8) void {
    hdSet(heap, expr.*, Value.comb(.I));
    const val = Value.fromRaw(lex_mod.strConv(value));
    tlSet(heap, expr.*, val);
    expr.* = val;
}

// Tests: rewriteToMatchResult/rewriteToIntMatchResult/rewriteToString: the
// pattern-match rewrite family that needs cross-module compare/parse helpers
test "rewriteToMatchResult/rewriteToIntMatchResult/rewriteToString: match-result rewrites" {
    tu.freshInterp();
    const heap_ptr = heap_mod.heap();

    var e1 = ap(heap_ptr, Value.imm(0), Value.imm(0));
    const five_a = Value.fromRaw(big.fromInt(heap_ptr, 5));
    const five_b = Value.fromRaw(big.fromInt(heap_ptr, 5));
    try rewriteToMatchResult(heap_ptr, &e1, five_a, five_b, Value.imm(1));
    try std.testing.expectEqual(Value.imm(1), e1);

    var e2 = ap(heap_ptr, Value.imm(0), Value.imm(0));
    const six = Value.fromRaw(big.fromInt(heap_ptr, 6));
    try rewriteToMatchResult(heap_ptr, &e2, five_a, six, Value.imm(1));
    try std.testing.expectEqual(Value.comb(.FAIL), e2);

    var e3 = ap(heap_ptr, Value.imm(0), Value.imm(0));
    rewriteToIntMatchResult(heap_ptr, &e3, five_a, five_b, Value.imm(1));
    try std.testing.expectEqual(Value.imm(1), e3);

    var e4 = ap(heap_ptr, Value.imm(0), Value.imm(0));
    rewriteToIntMatchResult(heap_ptr, &e4, five_a, six, Value.imm(1));
    try std.testing.expectEqual(Value.comb(.FAIL), e4);

    var e5 = ap(heap_ptr, Value.imm(0), Value.imm(0));
    rewriteToString(heap_ptr, &e5, "hi");
    try std.testing.expectEqual(word.NodeTag.CONS, getTag(heap_ptr, e5));
    try std.testing.expectEqual(Value.imm('h'), hdGet(heap_ptr, e5));
    const rest = tlGet(heap_ptr, e5);
    try std.testing.expectEqual(Value.imm('i'), hdGet(heap_ptr, rest));
    try std.testing.expectEqual(Value.comb(.NIL), tlGet(heap_ptr, rest));
}

/// Allocate a cons cell `(x : y)`.
pub inline fn cons(heap: *Heap, x: Value, y: Value) Value {
    return Value.fromRaw(heap.make(.CONS, x.toRaw(), y.toRaw()));
}

/// Build the application `((f x) y)`.
pub inline fn ap2(heap: *Heap, f: Value, x: Value, y: Value) Value {
    return ap(heap, ap(heap, f, x), y);
}

// Tests: cons/ap2: the remaining allocators (ap/apTwo covered above)
test "cons/ap2: cons-cell and two-deep application allocation" {
    tu.freshInterp();
    const heap_ptr = heap_mod.heap();

    const c = cons(heap_ptr, Value.imm(1), Value.imm(2));
    try std.testing.expectEqual(word.NodeTag.CONS, getTag(heap_ptr, c));
    try std.testing.expectEqual(Value.imm(1), hdGet(heap_ptr, c));
    try std.testing.expectEqual(Value.imm(2), tlGet(heap_ptr, c));

    const a2 = ap2(heap_ptr, Value.imm(1), Value.imm(2), Value.imm(3));
    try std.testing.expectEqual(word.NodeTag.AP, getTag(heap_ptr, a2));
    try std.testing.expectEqual(Value.imm(3), tlGet(heap_ptr, a2));
    const inner = hdGet(heap_ptr, a2);
    try std.testing.expectEqual(word.NodeTag.AP, getTag(heap_ptr, inner));
    try std.testing.expectEqual(Value.imm(1), hdGet(heap_ptr, inner));
    try std.testing.expectEqual(Value.imm(2), tlGet(heap_ptr, inner));
}

/// True when bignum `x`'s head digit carries the sign bit (i.e. `x` is negative).
pub inline fn neg(heap: *Heap, x: Value) bool {
    return (hdGet(heap, x).toRaw() & word.SIGNBIT) != 0;
}
/// True when bignum `x` is non-negative (the complement of [neg]).
pub inline fn poz(heap: *Heap, x: Value) bool {
    return !neg(heap, x);
}
/// The value field of private-name node `x` (its tail).
pub inline fn pnVal(heap: *Heap, x: Value) Value {
    return tlGet(heap, x);
}
/// The interned name text of id node `x`.
pub inline fn getId(heap: *Heap, x: Value) [*:0]const u8 {
    return strtab.strOf(strtab.table(), hdGet(heap, hdGet(heap, hdGet(heap, x))).toRaw());
}
/// The printed name of constructor node `x` (via its id or private-name value).
pub inline fn constrName(heap: *Heap, x: Value) [*:0]const u8 {
    const tlx = tlGet(heap, x);
    if (isId(heap, tlx)) {
        return getId(heap, tlx);
    } else {
        return getId(heap, pnVal(heap, tlx));
    }
}
/// True when constructor `x` is suppressed from `show` (a `STRCONS` with no id).
pub inline fn suppressed(heap: *Heap, x: Value) bool {
    const tlx = tlGet(heap, x);
    return isStrcons(heap, tlx) and !isId(heap, pnVal(heap, tlx));
}

// Tests: neg/poz/pnVal/getId/constrName/suppressed: bignum sign bit and
// identifier/constructor name lookup
test "neg/poz/pnVal/getId/constrName/suppressed: sign and name accessors" {
    tu.freshInterp();
    const heap_ptr = heap_mod.heap();

    const neg_cell = Value.fromRaw(heap_ptr.make(.INT, word.SIGNBIT | 5, 0));
    const pos_cell = Value.fromRaw(heap_ptr.make(.INT, 5, 0));
    try std.testing.expect(neg(heap_ptr, neg_cell));
    try std.testing.expect(!poz(heap_ptr, neg_cell));
    try std.testing.expect(!neg(heap_ptr, pos_cell));
    try std.testing.expect(poz(heap_ptr, pos_cell));

    // pnVal reads a private-name node's tail, just like idVal reads an id's.
    const pn_cell = Value.fromRaw(heap_ptr.make(.DATAPAIR, 0, 33));
    try std.testing.expectEqual(Value.imm(33), pnVal(heap_ptr, pn_cell));

    const id = Value.fromRaw(lex_mod.makeId("zzrc_getid_test"));
    try std.testing.expectEqualStrings("zzrc_getid_test", std.mem.span(getId(heap_ptr, id)));

    // constrName: a CONSTRUCTOR whose tail is directly the id.
    const ctor_direct = Value.fromRaw(heap_ptr.make(.CONSTRUCTOR, 0, id.toRaw()));
    try std.testing.expectEqualStrings("zzrc_getid_test", std.mem.span(constrName(heap_ptr, ctor_direct)));

    // constrName: a CONSTRUCTOR whose tail is a private-name node pointing at the id.
    const ctor_via_pn = Value.fromRaw(heap_ptr.make(.CONSTRUCTOR, 0, pnVal(heap_ptr, Value.fromRaw(heap_ptr.make(.DATAPAIR, 0, id.toRaw()))).toRaw()));
    try std.testing.expectEqualStrings("zzrc_getid_test", std.mem.span(constrName(heap_ptr, ctor_via_pn)));

    // suppressed: a CONSTRUCTOR whose tail is a STRCONS with no id (tail 0).
    const strcons_bare = Value.fromRaw(heap_ptr.make(.STRCONS, 0, 0));
    const ctor_suppressed = Value.fromRaw(heap_ptr.make(.CONSTRUCTOR, 0, strcons_bare.toRaw()));
    try std.testing.expect(suppressed(heap_ptr, ctor_suppressed));

    // Not suppressed: the STRCONS's tail (pnVal) is an actual id.
    const strcons_named = Value.fromRaw(heap_ptr.make(.STRCONS, 0, id.toRaw()));
    const ctor_named = Value.fromRaw(heap_ptr.make(.CONSTRUCTOR, 0, strcons_named.toRaw()));
    try std.testing.expect(!suppressed(heap_ptr, ctor_named));
}

/// The standard-error `Stream` handle.
pub fn getStderr() ?*word.Stream {
    const T = @TypeOf(os.stderr);
    if (comptime @typeInfo(T) == .@"fn") {
        return os.stderr();
    } else if (comptime @typeInfo(T) == .pointer and @typeInfo(@typeInfo(T).pointer.child) == .@"fn") {
        return os.stderr();
    } else {
        return os.stderr;
    }
}
/// The standard-output `Stream` handle.
pub fn getStdout() ?*word.Stream {
    const T = @TypeOf(os.stdout);
    if (comptime @typeInfo(T) == .@"fn") {
        return os.stdout();
    } else if (comptime @typeInfo(T) == .pointer and @typeInfo(@typeInfo(T).pointer.child) == .@"fn") {
        return os.stdout();
    } else {
        return os.stdout;
    }
}
/// The standard-input `Stream` handle.
pub fn getStdin() ?*word.Stream {
    const T = @TypeOf(os.stdin);
    if (comptime @typeInfo(T) == .@"fn") {
        return os.stdin();
    } else if (comptime @typeInfo(T) == .pointer and @typeInfo(@typeInfo(T).pointer.child) == .@"fn") {
        return os.stdin();
    } else {
        return os.stdin;
    }
}

/// `x` as an `f64`, converting from a bignum (`INT`) or reading a `DOUBLE` cell.
pub inline fn forceDbl(heap: *Heap, x: Value) f64 {
    if (isInt(heap, x)) {
        return big.toFloat(heap, x.toRaw());
    } else {
        return heap_mod.getDbl(x.toRaw());
    }
}

/// Coerce `x` to a `DOUBLE` cell (no-op if already double; else promote the int).
pub inline fn coerceDbl(heap: *Heap, x: Value) ReduceError!Value {
    if (isDouble(heap, x)) return x;
    return Value.fromRaw(try heap_mod.stoDbl(big.toFloat(heap, x.toRaw())));
}

// Tests: forceDbl/coerceDbl: numeric coercion between INT and DOUBLE cells
test "forceDbl/coerceDbl: coerce between boxed int and double" {
    tu.freshInterp();
    const heap_ptr = heap_mod.heap();

    const int_cell = Value.fromRaw(big.fromInt(heap_ptr, 6));
    try std.testing.expectEqual(@as(f64, 6.0), forceDbl(heap_ptr, int_cell));

    const dbl_cell = try coerceDbl(heap_ptr, int_cell);
    try std.testing.expectEqual(word.NodeTag.DOUBLE, getTag(heap_ptr, dbl_cell));
    try std.testing.expectEqual(@as(f64, 6.0), forceDbl(heap_ptr, dbl_cell));

    // Already-double coercion is a no-op (same cell back).
    try std.testing.expectEqual(dbl_cell, try coerceDbl(heap_ptr, dbl_cell));
}

/// Rewrite `*expr` to `True`/`False` for `left == right` (structural compare).
pub inline fn rewriteToCompareEq(heap: *Heap, expr: *Value, left: Value, right: Value) ReduceError!void {
    hdSet(heap, expr.*, Value.comb(.I));
    const val = if (try reduce_mod.compare(heap, left, right) == 0) Value.comb(.True) else Value.comb(.False);
    tlSet(heap, expr.*, val);
    expr.* = val;
}

/// Rewrite `*expr` to `True`/`False` for `left != right`.
pub inline fn rewriteToCompareNeq(heap: *Heap, expr: *Value, left: Value, right: Value) ReduceError!void {
    hdSet(heap, expr.*, Value.comb(.I));
    const val = if (try reduce_mod.compare(heap, left, right) != 0) Value.comb(.True) else Value.comb(.False);
    tlSet(heap, expr.*, val);
    expr.* = val;
}

/// Rewrite `*expr` to `True`/`False` for `left > right`.
pub inline fn rewriteToCompareGt(heap: *Heap, expr: *Value, left: Value, right: Value) ReduceError!void {
    hdSet(heap, expr.*, Value.comb(.I));
    const val = if (try reduce_mod.compare(heap, left, right) > 0) Value.comb(.True) else Value.comb(.False);
    tlSet(heap, expr.*, val);
    expr.* = val;
}

/// Rewrite `*expr` to `True`/`False` for `left >= right`.
pub inline fn rewriteToCompareGe(heap: *Heap, expr: *Value, left: Value, right: Value) ReduceError!void {
    hdSet(heap, expr.*, Value.comb(.I));
    const val = if (try reduce_mod.compare(heap, left, right) >= 0) Value.comb(.True) else Value.comb(.False);
    tlSet(heap, expr.*, val);
    expr.* = val;
}

// Tests: rewriteToCompareEq/Neq/Gt/Ge: the structural-comparison rewrite family
test "rewriteToCompareEq/Neq/Gt/Ge: True/False comparison rewrites" {
    tu.freshInterp();
    const heap_ptr = heap_mod.heap();
    const five = Value.fromRaw(big.fromInt(heap_ptr, 5));
    const six = Value.fromRaw(big.fromInt(heap_ptr, 6));

    var e1 = ap(heap_ptr, Value.imm(0), Value.imm(0));
    try rewriteToCompareEq(heap_ptr, &e1, five, five);
    try std.testing.expectEqual(Value.comb(.True), e1);
    var e2 = ap(heap_ptr, Value.imm(0), Value.imm(0));
    try rewriteToCompareEq(heap_ptr, &e2, five, six);
    try std.testing.expectEqual(Value.comb(.False), e2);

    var e3 = ap(heap_ptr, Value.imm(0), Value.imm(0));
    try rewriteToCompareNeq(heap_ptr, &e3, five, six);
    try std.testing.expectEqual(Value.comb(.True), e3);
    var e4 = ap(heap_ptr, Value.imm(0), Value.imm(0));
    try rewriteToCompareNeq(heap_ptr, &e4, five, five);
    try std.testing.expectEqual(Value.comb(.False), e4);

    var e5 = ap(heap_ptr, Value.imm(0), Value.imm(0));
    try rewriteToCompareGt(heap_ptr, &e5, six, five);
    try std.testing.expectEqual(Value.comb(.True), e5);
    var e6 = ap(heap_ptr, Value.imm(0), Value.imm(0));
    try rewriteToCompareGt(heap_ptr, &e6, five, six);
    try std.testing.expectEqual(Value.comb(.False), e6);

    var e7 = ap(heap_ptr, Value.imm(0), Value.imm(0));
    try rewriteToCompareGe(heap_ptr, &e7, five, five);
    try std.testing.expectEqual(Value.comb(.True), e7);
    var e8 = ap(heap_ptr, Value.imm(0), Value.imm(0));
    try rewriteToCompareGe(heap_ptr, &e8, five, six);
    try std.testing.expectEqual(Value.comb(.False), e8);
}

/// True when single-cell bignum `x` is zero (head digit and tail both 0).
pub inline fn bigzero(heap: *Heap, x: Value) bool {
    return hdGet(heap, x).toRaw() == 0 and tlGet(heap, x).toRaw() == 0;
}

/// Decode a single-cell bignum `x` to a signed `Word` — a plain decoded
/// scalar, not a graph value, so the *return* stays `Word` (the parameter
/// being decoded is still a graph reference, hence `Value`).
pub inline fn getsmallint(heap: *Heap, x: Value) Word {
    const h_val = hdGet(heap, x).toRaw();
    return if ((h_val & word.SIGNBIT) != 0) -(h_val & word.MAXDIGIT) else h_val;
}

// Tests: bigzero/getsmallint: single-cell bignum zero-check and signed decode
test "bigzero/getsmallint: single-cell bignum checks" {
    tu.freshInterp();
    const heap_ptr = heap_mod.heap();

    const zero_cell = Value.fromRaw(heap_ptr.make(.INT, 0, 0));
    try std.testing.expect(bigzero(heap_ptr, zero_cell));
    try std.testing.expectEqual(@as(Word, 0), getsmallint(heap_ptr, zero_cell));

    const pos_cell = Value.fromRaw(heap_ptr.make(.INT, 42, 0));
    try std.testing.expect(!bigzero(heap_ptr, pos_cell));
    try std.testing.expectEqual(@as(Word, 42), getsmallint(heap_ptr, pos_cell));

    const neg_cell = Value.fromRaw(heap_ptr.make(.INT, word.SIGNBIT | 17, 0));
    try std.testing.expect(!bigzero(heap_ptr, neg_cell));
    try std.testing.expectEqual(@as(Word, -17), getsmallint(heap_ptr, neg_cell));
}
