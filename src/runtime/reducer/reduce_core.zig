//! reduce_core.zig — the reduction machine's primitives, shared by the rewrite
//! handlers (`combinators.zig`, `ready.zig`, `lex.zig`, `io.zig`, which all
//! import this file as `reduce`). It owns the `ReductionCtx` register file and
//! the spine-traversal/accessor/classifier/rewrite helpers.
//!
//! This is also the seam where the B-track typed-value work (`Heap`/`Value`)
//! will replace the raw-`Word` `hdGet`/`tlGet` reads.
//!
//! **Spine representation (B2 option (b), 2026-07-01).** The spine used to be
//! encoded in-graph via pointer reversal: a cell's own `hd`/`tl` field
//! temporarily borrowed to hold the "previous stack top" pointer, tagged with
//! `tlptrbits`. It is now `ctx.spine`, an explicit `Spine` (see `spine.zig`)
//! — no cell ever holds a borrowed value, and no access needs
//! `& ~tlptrbits` masking. The traversal primitives below (`downLeft`/
//! `downRight`/`upLeft`/`upRight`) are now thin wrappers over `Spine`'s
//! methods of the same name; `spine.zig`'s module doc has the full derivation
//! (which read/write in each original primitive was a real graph mutation
//! vs. pure bookkeeping) and the shadow-validation results (51 real-program
//! checks, zero mismatches) that this cutover rests on.
//!
//! **Narrow substructure threading (SHARED_STATE Phase 6, 2026-07-01).** The
//! cell-accessor primitives (`hdGet`/`tlGet`/`getTag`/`ap`/`cons`/`isXxx`/
//! `rewriteToXxx`/…) take an explicit `heap: *Heap` parameter instead of
//! reaching the global `interp.heap` singleton ambiently. Functions that
//! already carry `ctx: *ReductionCtx` (which now owns a `heap` field) don't
//! need a *second* explicit parameter — they pass `ctx.heap` through to the
//! leaf primitives internally. This is the bounded piece of the broader
//! `heap.zig`-threading effort: `ReductionCtx` is already threaded through
//! every reducer rewrite-handler (`combinators.zig`/`ready.zig`/`io.zig`/
//! `reducer/lex.zig`), so adding `heap` to it costs zero new parameters at
//! ~94 call sites, unlike threading `*Heap` through the compiler/parser/
//! driver's call graphs from scratch (no existing scaffolding there).

const word = @import("../word.zig");
const strtab = @import("../strtab.zig");
const spine = @import("spine.zig");
const heap_mod = @import("../heap.zig");
const rt = @import("../runtime_state.zig");

/// The interpreter machine word (see `word.Word`).
pub const Word = i64;
/// The cell arena (see `heap.zig`); threaded explicitly by the primitives below.
pub const Heap = heap_mod.Heap;

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
    e: Word,
    /// The explicit spine stack (replaces the old in-graph pointer-reversal
    /// encoding — see the module doc above).
    spine: spine.Spine,
    /// General-purpose scratch used by many handlers for local temporaries.
    hold: Word,
    /// Arguments pulled off the spine for the current combinator rewrite.
    args: [4]Word,
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

/// Strip the spine direction bits and yield a plain heap index. Every accessor
/// below masks `& ~tlptrbits` for the same reason — a spine word may carry a
/// direction mark in its top two bits.
pub inline fn cleanPtr(x: Word) usize {
    return @as(usize, @intCast(x & 0x3fffffffffffffff));
}

// Cross-module functions via direct (circular) @import — R7.3.
const reduce_mod = @import("../reduce.zig");
const reducer_reduce = @import("reduce.zig");
const lex_mod = @import("../../parser/lex.zig");
const big = @import("../big.zig");
const os = @import("../os.zig");

// Cell access through a spine word (mask off direction bits, then index the
// heap). This is the raw-`Word` value boundary the B2 `Heap`/`Value` seam will
// type. Mirrors `reducer/reduce.zig`.

/// Read the head (`hd`) field through (possibly marked) spine word `x`.
pub inline fn hdGet(heap: *Heap, x: Word) Word {
    return heap.hCell(x & 0x3fffffffffffffff);
}

/// Write the head (`hd`) field through spine word `x`.
pub inline fn hdSet(heap: *Heap, x: Word, val: Word) void {
    heap.hp(x & 0x3fffffffffffffff).* = val;
}

/// Read the tail (`tl`) field through spine word `x`.
pub inline fn tlGet(heap: *Heap, x: Word) Word {
    return heap.tCell(x & 0x3fffffffffffffff);
}

/// Write the tail (`tl`) field through spine word `x`.
pub inline fn tlSet(heap: *Heap, x: Word, val: Word) void {
    heap.tp(x & 0x3fffffffffffffff).* = val;
}

/// Read the cell tag through spine word `x`.
pub inline fn getTag(heap: *Heap, x: Word) word.NodeTag {
    return heap.getTag(x & 0x3fffffffffffffff);
}

/// Write the cell tag through spine word `x`.
pub inline fn setTag(heap: *Heap, x: Word, val: word.NodeTag) void {
    heap.setTag(x & 0x3fffffffffffffff, val);
}

/// A pointer to the tail (`tl`) field through spine word `x` (for in-place edits).
pub inline fn tlPtr(heap: *Heap, x: Word) *Word {
    return heap.tp(x & 0x3fffffffffffffff);
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
    ctx.e = ctx.spine.downRight(ctx.e);
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
    ctx.e = ctx.spine.upLeft(ctx.e);
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
    ctx.e = ctx.spine.upRight(ctx.e);
}

/// Pull the next argument off the spine into `a` (unchecked — caller knows it exists).
pub inline fn GETARG(ctx: *ReductionCtx, a: *Word) void {
    upLeft(ctx);
    a.* = tlGet(ctx.heap, ctx.e);
}

/// Pull the next argument off the spine into `a`; true if the spine is exhausted.
pub inline fn getarg(ctx: *ReductionCtx, a: *Word) bool {
    if (upleft(ctx)) {
        return true;
    }
    a.* = tlGet(ctx.heap, ctx.e);
    return false;
}

/// Overwrite the focus node with an `I`-indirection to `r` and refocus on `r`
/// (the in-place "simplify to" rewrite that preserves sharing).
pub inline fn simpl(ctx: *ReductionCtx, r: Word) void {
    hdSet(ctx.heap, ctx.e, word.I);
    tlSet(ctx.heap, ctx.e, r);
    ctx.e = r;
}

/// True for a marked/sentinel spine word (negative) — not a normal cell handle.
pub inline fn abnormal(x: Word) bool {
    return x < 0;
}
/// True when `x` is a (normal) `AP` application cell.
pub inline fn isAp(heap: *Heap, x: Word) bool {
    return !abnormal(x) and getTag(heap, x) == .AP;
}
/// True when `x` is a number (`INT` or `DOUBLE`) cell.
pub inline fn isNum(heap: *Heap, x: Word) bool {
    if (abnormal(x)) return false;
    const t = getTag(heap, x);
    return t == .INT or t == .DOUBLE;
}
/// True when `x` is a `CONSTRUCTOR` cell.
pub inline fn isConstructor(heap: *Heap, x: Word) bool {
    return !abnormal(x) and getTag(heap, x) == .CONSTRUCTOR;
}
/// True when `x` is an `INT` (bignum) cell.
pub inline fn isInt(heap: *Heap, x: Word) bool {
    return !abnormal(x) and getTag(heap, x) == .INT;
}
/// True when `x` is a `DOUBLE` cell.
pub inline fn isDouble(heap: *Heap, x: Word) bool {
    return !abnormal(x) and getTag(heap, x) == .DOUBLE;
}
/// True when `x` is a bare `ATOM` cell.
pub inline fn isAtom(heap: *Heap, x: Word) bool {
    return !abnormal(x) and getTag(heap, x) == .ATOM;
}
/// True when `x` is a `STRCONS` (interned-string) cell.
pub inline fn isStrcons(heap: *Heap, x: Word) bool {
    return !abnormal(x) and getTag(heap, x) == .STRCONS;
}
/// True when `x` is an `ID` (identifier) cell.
pub inline fn isId(heap: *Heap, x: Word) bool {
    return !abnormal(x) and getTag(heap, x) == .ID;
}
/// The value field of id `x` (its tail).
pub inline fn idVal(heap: *Heap, x: Word) Word {
    return tlGet(heap, x);
}
/// True when `x` is a `DATAPAIR` cell.
pub inline fn isDatapair(heap: *Heap, x: Word) bool {
    return !abnormal(x) and getTag(heap, x) == .DATAPAIR;
}
/// True when `x` is a `STARTREADVALS` cell.
pub inline fn isStartreadvals(heap: *Heap, x: Word) bool {
    return !abnormal(x) and getTag(heap, x) == .STARTREADVALS;
}
/// True when `x` is a `CONS` cell.
pub inline fn isCons(heap: *Heap, x: Word) bool {
    return !abnormal(x) and getTag(heap, x) == .CONS;
}
/// True when `x` is a `UNICODE` (wide-char) cell.
pub inline fn isUnicode(heap: *Heap, x: Word) bool {
    return !abnormal(x) and getTag(heap, x) == .UNICODE;
}

/// Rewrite `*expr` in place to an `I`-indirection to `value`, then refocus on it.
pub inline fn rewriteToValue(heap: *Heap, expr: *Word, value: Word) void {
    hdSet(heap, expr.*, word.I);
    tlSet(heap, expr.*, value);
    expr.* = value;
}

/// Rewrite `*expr` to `NIL` (the empty list).
pub inline fn rewriteToNil(heap: *Heap, expr: *Word) void {
    rewriteToValue(heap, expr, word.NIL);
}

/// Rewrite `*expr` to the pattern-match `FAIL` sentinel.
pub inline fn rewriteToFail(heap: *Heap, expr: *Word) void {
    rewriteToValue(heap, expr, word.FAIL);
}

/// Rewrite `*expr` to a failure (currently `NIL`).
pub inline fn rewriteToFailure(heap: *Heap, expr: *Word) void {
    rewriteToValue(heap, expr, word.NIL);
}

/// Turn `expr` into a `CONS` cell with the given head (tail left unchanged).
pub inline fn rewriteToConsHead(heap: *Heap, expr: Word, head_value: Word) void {
    setTag(heap, expr, .CONS);
    hdSet(heap, expr, head_value);
}

/// Turn `expr` into a `CONS` cell `(head_value : tail_value)`.
pub inline fn rewriteToCons(heap: *Heap, expr: Word, head_value: Word, tail_value: Word) void {
    setTag(heap, expr, .CONS);
    hdSet(heap, expr, head_value);
    tlSet(heap, expr, tail_value);
}

/// Collapse `expr` to an `I`-indirection and return its existing tail.
pub inline fn rewriteToExistingTail(heap: *Heap, expr: Word) Word {
    hdSet(heap, expr, word.I);
    return tlGet(heap, expr);
}

/// Allocate an application cell `(x y)`.
pub inline fn ap(heap: *Heap, x: Word, y: Word) Word {
    return heap.make(.AP, x, y);
}

/// Allocate two application cells in bulk.
pub inline fn apTwo(heap: *Heap, x1: Word, y1: Word, x2: Word, y2: Word, c1: *Word, c2: *Word) void {
    heap.makeTwo(.AP, x1, y1, .AP, x2, y2, c1, c2);
}

/// Rewrite `*expr` to `success_value` if `left` equals `right` (structurally),
/// else to `FAIL` — the pattern-match equality test.
pub inline fn rewriteToMatchResult(heap: *Heap, expr: *Word, left: Word, right: Word, success_value: Word) void {
    hdSet(heap, expr.*, word.I);
    const val = if (reduce_mod.compare(left, right) == 0) success_value else word.FAIL;
    tlSet(heap, expr.*, val);
    expr.* = val;
}

/// Rewrite `*expr` to `success_value` if `value` is the int `literal`, else `FAIL`.
pub inline fn rewriteToIntMatchResult(heap: *Heap, expr: *Word, literal: Word, value: Word, success_value: Word) void {
    hdSet(heap, expr.*, word.I);
    const val = if (!isInt(heap, value) or big.cmp(heap, literal, value) != 0) word.FAIL else success_value;
    tlSet(heap, expr.*, val);
    expr.* = val;
}

/// Rewrite `*expr` to the Miranda char-list form of C string `value`.
pub inline fn rewriteToString(heap: *Heap, expr: *Word, value: [*:0]const u8) void {
    hdSet(heap, expr.*, word.I);
    const val = lex_mod.strConv(value);
    tlSet(heap, expr.*, val);
    expr.* = val;
}

/// Allocate a cons cell `(x : y)`.
pub inline fn cons(heap: *Heap, x: Word, y: Word) Word {
    return heap.make(.CONS, x, y);
}

/// Build the application `((f x) y)`.
pub inline fn ap2(heap: *Heap, f: Word, x: Word, y: Word) Word {
    return ap(heap, ap(heap, f, x), y);
}

/// True when bignum `x`'s head digit carries the sign bit (i.e. `x` is negative).
pub inline fn neg(heap: *Heap, x: Word) bool {
    return (hdGet(heap, x) & word.SIGNBIT) != 0;
}
/// True when bignum `x` is non-negative (the complement of [neg]).
pub inline fn poz(heap: *Heap, x: Word) bool {
    return !neg(heap, x);
}
/// The value field of private-name node `x` (its tail).
pub inline fn pnVal(heap: *Heap, x: Word) Word {
    return tlGet(heap, x);
}
/// The interned name text of id node `x`.
pub inline fn getId(heap: *Heap, x: Word) [*:0]const u8 {
    return strtab.strOf(strtab.table(), hdGet(heap, hdGet(heap, hdGet(heap, x))));
}
/// The printed name of constructor node `x` (via its id or private-name value).
pub inline fn constrName(heap: *Heap, x: Word) [*:0]const u8 {
    const tlx = tlGet(heap, x);
    if (isId(heap, tlx)) {
        return getId(heap, tlx);
    } else {
        return getId(heap, pnVal(heap, tlx));
    }
}
/// True when constructor `x` is suppressed from `show` (a `STRCONS` with no id).
pub inline fn suppressed(heap: *Heap, x: Word) bool {
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
pub inline fn forceDbl(heap: *Heap, x: Word) f64 {
    if (isInt(heap, x)) {
        return big.toFloat(heap, x);
    } else {
        return heap_mod.getDbl(x);
    }
}

/// Coerce `x` to a `DOUBLE` cell (no-op if already double; else promote the int).
pub inline fn coerceDbl(heap: *Heap, x: Word) Word {
    if (isDouble(heap, x)) return x;
    return heap_mod.stoDbl(big.toFloat(heap, x));
}

/// Rewrite `*expr` to `True`/`False` for `left == right` (structural compare).
pub inline fn rewriteToCompareEq(heap: *Heap, expr: *Word, left: Word, right: Word) void {
    hdSet(heap, expr.*, word.I);
    const val = if (reduce_mod.compare(left, right) == 0) word.True else word.False;
    tlSet(heap, expr.*, val);
    expr.* = val;
}

/// Rewrite `*expr` to `True`/`False` for `left != right`.
pub inline fn rewriteToCompareNeq(heap: *Heap, expr: *Word, left: Word, right: Word) void {
    hdSet(heap, expr.*, word.I);
    const val = if (reduce_mod.compare(left, right) != 0) word.True else word.False;
    tlSet(heap, expr.*, val);
    expr.* = val;
}

/// Rewrite `*expr` to `True`/`False` for `left > right`.
pub inline fn rewriteToCompareGt(heap: *Heap, expr: *Word, left: Word, right: Word) void {
    hdSet(heap, expr.*, word.I);
    const val = if (reduce_mod.compare(left, right) > 0) word.True else word.False;
    tlSet(heap, expr.*, val);
    expr.* = val;
}

/// Rewrite `*expr` to `True`/`False` for `left >= right`.
pub inline fn rewriteToCompareGe(heap: *Heap, expr: *Word, left: Word, right: Word) void {
    hdSet(heap, expr.*, word.I);
    const val = if (reduce_mod.compare(left, right) >= 0) word.True else word.False;
    tlSet(heap, expr.*, val);
    expr.* = val;
}

/// True when single-cell bignum `x` is zero (head digit and tail both 0).
pub inline fn bigzero(heap: *Heap, x: Word) bool {
    return hdGet(heap, x) == 0 and tlGet(heap, x) == 0;
}

/// Decode a single-cell bignum `x` to a signed `Word`.
pub inline fn getsmallint(heap: *Heap, x: Word) Word {
    const h_val = hdGet(heap, x);
    return if ((h_val & word.SIGNBIT) != 0) -(h_val & word.MAXDIGIT) else h_val;
}
