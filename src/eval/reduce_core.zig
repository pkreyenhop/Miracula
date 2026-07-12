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
//! `getDbl`/`stoDbl`, `reduce_rt.zig`'s `compare`) are called through
//! `Value.fromRaw`/`.toRaw()` at the boundary — the same escape hatch named
//! in `graph/value.zig`'s own doc comment.
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
pub inline fn headVal(heap: *Heap, x: Value) Value {
    return Value.fromRaw(head(heap, x.toRaw()));
}

/// `Value`-typed [force]: deep-evaluate `x` to normal form in place.
pub inline fn forceVal(heap: *Heap, x: Value) ReduceError!void {
    return force(heap, x.toRaw());
}

/// `Value`-typed [getstring]: flatten char-list `x` to a C string.
pub inline fn getstringVal(heap: *Heap, x: Value, cmd: ?[*:0]const u8) ReduceError!?[*:0]u8 {
    return getstring(heap, x.toRaw(), cmd);
}

/// `Value`-typed [badcaseError]: abort with "no matching case" for `arg_info`.
pub inline fn badcaseErrorVal(heap: *Heap, arg_info: Value) ReduceError!void {
    return badcaseError(heap, arg_info.toRaw());
}

/// `Value`-typed [confError]: report a conformality error for `arg_info`.
pub inline fn confErrorVal(heap: *Heap, arg_info: Value) void {
    confError(heap, arg_info.toRaw());
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

/// Rewrite `*expr` to `success_value` if `left` equals `right` (structurally),
/// else to `FAIL` — the pattern-match equality test.
pub inline fn rewriteToMatchResult(heap: *Heap, expr: *Value, left: Value, right: Value, success_value: Value) ReduceError!void {
    hdSet(heap, expr.*, Value.comb(.I));
    const val = if (try reduce_mod.compare(heap, left.toRaw(), right.toRaw()) == 0) success_value else Value.comb(.FAIL);
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

/// Allocate a cons cell `(x : y)`.
pub inline fn cons(heap: *Heap, x: Value, y: Value) Value {
    return Value.fromRaw(heap.make(.CONS, x.toRaw(), y.toRaw()));
}

/// Build the application `((f x) y)`.
pub inline fn ap2(heap: *Heap, f: Value, x: Value, y: Value) Value {
    return ap(heap, ap(heap, f, x), y);
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

/// Rewrite `*expr` to `True`/`False` for `left == right` (structural compare).
pub inline fn rewriteToCompareEq(heap: *Heap, expr: *Value, left: Value, right: Value) ReduceError!void {
    hdSet(heap, expr.*, Value.comb(.I));
    const val = if (try reduce_mod.compare(heap, left.toRaw(), right.toRaw()) == 0) Value.comb(.True) else Value.comb(.False);
    tlSet(heap, expr.*, val);
    expr.* = val;
}

/// Rewrite `*expr` to `True`/`False` for `left != right`.
pub inline fn rewriteToCompareNeq(heap: *Heap, expr: *Value, left: Value, right: Value) ReduceError!void {
    hdSet(heap, expr.*, Value.comb(.I));
    const val = if (try reduce_mod.compare(heap, left.toRaw(), right.toRaw()) != 0) Value.comb(.True) else Value.comb(.False);
    tlSet(heap, expr.*, val);
    expr.* = val;
}

/// Rewrite `*expr` to `True`/`False` for `left > right`.
pub inline fn rewriteToCompareGt(heap: *Heap, expr: *Value, left: Value, right: Value) ReduceError!void {
    hdSet(heap, expr.*, Value.comb(.I));
    const val = if (try reduce_mod.compare(heap, left.toRaw(), right.toRaw()) > 0) Value.comb(.True) else Value.comb(.False);
    tlSet(heap, expr.*, val);
    expr.* = val;
}

/// Rewrite `*expr` to `True`/`False` for `left >= right`.
pub inline fn rewriteToCompareGe(heap: *Heap, expr: *Value, left: Value, right: Value) ReduceError!void {
    hdSet(heap, expr.*, Value.comb(.I));
    const val = if (try reduce_mod.compare(heap, left.toRaw(), right.toRaw()) >= 0) Value.comb(.True) else Value.comb(.False);
    tlSet(heap, expr.*, val);
    expr.* = val;
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
