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

const word = @import("../word.zig");
const strtab = @import("../strtab.zig");
const spine = @import("spine.zig");

/// The interpreter machine word (see `word.Word`).
pub const Word = i64;

/// The reduction machine's register file. See `reducer/reduce.zig` for the
/// protocol: `e` focus node · `spine` the explicit spine stack (see
/// `spine.zig`) · `hold` general scratch (used by many handlers for
/// unrelated temporaries, not just spine bookkeeping) · `args` pulled
/// arguments · `action` post-dispatch signal (`ACT_NONE`/`ACT_NEXTREDEX`/
/// `ACT_DONE`).
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
    return @as(usize, @intCast(x & ~word.tlptrbits));
}

const heap = @import("../heap.zig");
// Cross-module functions via direct (circular) @import — R7.3.
const reduce_mod = @import("../reduce.zig");
const reducer_reduce = @import("reduce.zig");
const lex_mod = @import("../../parser/lex.zig");
const big = @import("../big.zig");
const main_clib = @import("../main_clib.zig");

// Cell access through a spine word (mask off direction bits, then index the
// heap). This is the raw-`Word` value boundary the B2 `Heap`/`Value` seam will
// type. Mirrors `reducer/reduce.zig`.

/// Read the head (`hd`) field through (possibly marked) spine word `x`.
pub inline fn hdGet(x: Word) Word {
    return heap.heap.h(x & ~word.tlptrbits);
}

/// Write the head (`hd`) field through spine word `x`.
pub inline fn hdSet(x: Word, val: Word) void {
    heap.heap.hp(x & ~word.tlptrbits).* = val;
}

/// Read the tail (`tl`) field through spine word `x`.
pub inline fn tlGet(x: Word) Word {
    return heap.heap.t(x & ~word.tlptrbits);
}

/// Write the tail (`tl`) field through spine word `x`.
pub inline fn tlSet(x: Word, val: Word) void {
    heap.heap.tp(x & ~word.tlptrbits).* = val;
}

/// Read the cell tag through spine word `x`.
pub inline fn getTag(x: Word) word.NodeTag {
    return heap.heap.getTag(x & ~word.tlptrbits);
}

/// Write the cell tag through spine word `x`.
pub inline fn setTag(x: Word, val: word.NodeTag) void {
    heap.heap.setTag(x & ~word.tlptrbits, val);
}

/// A pointer to the tail (`tl`) field through spine word `x` (for in-place edits).
pub inline fn tlPtr(x: Word) *Word {
    return heap.heap.tp(x & ~word.tlptrbits);
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
    a.* = tlGet(ctx.e);
}

/// Pull the next argument off the spine into `a`; true if the spine is exhausted.
pub inline fn getarg(ctx: *ReductionCtx, a: *Word) bool {
    if (upleft(ctx)) {
        return true;
    }
    a.* = tlGet(ctx.e);
    return false;
}

/// Overwrite the focus node with an `I`-indirection to `r` and refocus on `r`
/// (the in-place "simplify to" rewrite that preserves sharing).
pub inline fn simpl(ctx: *ReductionCtx, r: Word) void {
    hdSet(ctx.e, word.I);
    tlSet(ctx.e, r);
    ctx.e = r;
}

/// True for a marked/sentinel spine word (negative) — not a normal cell handle.
pub inline fn abnormal(x: Word) bool {
    return x < 0;
}
/// True when `x` is a (normal) `AP` application cell.
pub inline fn isAp(x: Word) bool {
    return !abnormal(x) and getTag(x) == .AP;
}
/// True when `x` is a number (`INT` or `DOUBLE`) cell.
pub inline fn isNum(x: Word) bool {
    if (abnormal(x)) return false;
    const t = getTag(x);
    return t == .INT or t == .DOUBLE;
}
/// True when `x` is a `CONSTRUCTOR` cell.
pub inline fn isConstructor(x: Word) bool {
    return !abnormal(x) and getTag(x) == .CONSTRUCTOR;
}
/// True when `x` is an `INT` (bignum) cell.
pub inline fn isInt(x: Word) bool {
    return !abnormal(x) and getTag(x) == .INT;
}
/// True when `x` is a `DOUBLE` cell.
pub inline fn isDouble(x: Word) bool {
    return !abnormal(x) and getTag(x) == .DOUBLE;
}
/// True when `x` is a bare `ATOM` cell.
pub inline fn isAtom(x: Word) bool {
    return !abnormal(x) and getTag(x) == .ATOM;
}
/// True when `x` is a `STRCONS` (interned-string) cell.
pub inline fn isStrcons(x: Word) bool {
    return !abnormal(x) and getTag(x) == .STRCONS;
}
/// True when `x` is an `ID` (identifier) cell.
pub inline fn isId(x: Word) bool {
    return !abnormal(x) and getTag(x) == .ID;
}
/// The value field of id `x` (its tail).
pub inline fn idVal(x: Word) Word {
    return tlGet(x);
}
/// True when `x` is a `DATAPAIR` cell.
pub inline fn isDatapair(x: Word) bool {
    return !abnormal(x) and getTag(x) == .DATAPAIR;
}
/// True when `x` is a `STARTREADVALS` cell.
pub inline fn isStartreadvals(x: Word) bool {
    return !abnormal(x) and getTag(x) == .STARTREADVALS;
}
/// True when `x` is a `CONS` cell.
pub inline fn isCons(x: Word) bool {
    return !abnormal(x) and getTag(x) == .CONS;
}
/// True when `x` is a `UNICODE` (wide-char) cell.
pub inline fn isUnicode(x: Word) bool {
    return !abnormal(x) and getTag(x) == .UNICODE;
}

/// Rewrite `*expr` in place to an `I`-indirection to `value`, then refocus on it.
pub inline fn rewriteToValue(expr: *Word, value: Word) void {
    hdSet(expr.*, word.I);
    tlSet(expr.*, value);
    expr.* = value;
}

/// Rewrite `*expr` to `NIL` (the empty list).
pub inline fn rewriteToNil(expr: *Word) void {
    rewriteToValue(expr, word.NIL);
}

/// Rewrite `*expr` to the pattern-match `FAIL` sentinel.
pub inline fn rewriteToFail(expr: *Word) void {
    rewriteToValue(expr, word.FAIL);
}

/// Rewrite `*expr` to a failure (currently `NIL`).
pub inline fn rewriteToFailure(expr: *Word) void {
    rewriteToValue(expr, word.NIL);
}

/// Turn `expr` into a `CONS` cell with the given head (tail left unchanged).
pub inline fn rewriteToConsHead(expr: Word, head_value: Word) void {
    setTag(expr, .CONS);
    hdSet(expr, head_value);
}

/// Turn `expr` into a `CONS` cell `(head_value : tail_value)`.
pub inline fn rewriteToCons(expr: Word, head_value: Word, tail_value: Word) void {
    setTag(expr, .CONS);
    hdSet(expr, head_value);
    tlSet(expr, tail_value);
}

/// Collapse `expr` to an `I`-indirection and return its existing tail.
pub inline fn rewriteToExistingTail(expr: Word) Word {
    hdSet(expr, word.I);
    return tlGet(expr);
}

/// Allocate an application cell `(x y)`.
pub inline fn ap(x: Word, y: Word) Word {
    return heap.make(.AP, x, y);
}

/// Rewrite `*expr` to `success_value` if `left` equals `right` (structurally),
/// else to `FAIL` — the pattern-match equality test.
pub inline fn rewriteToMatchResult(expr: *Word, left: Word, right: Word, success_value: Word) void {
    hdSet(expr.*, word.I);
    const val = if (reduce_mod.compare(left, right) == 0) success_value else word.FAIL;
    tlSet(expr.*, val);
    expr.* = val;
}

/// Rewrite `*expr` to `success_value` if `value` is the int `literal`, else `FAIL`.
pub inline fn rewriteToIntMatchResult(expr: *Word, literal: Word, value: Word, success_value: Word) void {
    hdSet(expr.*, word.I);
    const val = if (!isInt(value) or big.cmp(heap.heap, literal, value) != 0) word.FAIL else success_value;
    tlSet(expr.*, val);
    expr.* = val;
}

/// Rewrite `*expr` to the Miranda char-list form of C string `value`.
pub inline fn rewriteToString(expr: *Word, value: [*:0]const u8) void {
    hdSet(expr.*, word.I);
    const val = lex_mod.strConv(value);
    tlSet(expr.*, val);
    expr.* = val;
}

/// Allocate a cons cell `(x : y)`.
pub inline fn cons(x: Word, y: Word) Word {
    return heap.make(.CONS, x, y);
}

/// Build the application `((f x) y)`.
pub inline fn ap2(f: Word, x: Word, y: Word) Word {
    return ap(ap(f, x), y);
}

/// True when bignum `x`'s head digit carries the sign bit (i.e. `x` is negative).
pub inline fn neg(x: Word) bool {
    return (hdGet(x) & word.SIGNBIT) != 0;
}
/// True when bignum `x` is non-negative (the complement of [neg]).
pub inline fn poz(x: Word) bool {
    return !neg(x);
}
/// The value field of private-name node `x` (its tail).
pub inline fn pnVal(x: Word) Word {
    return tlGet(x);
}
/// The interned name text of id node `x`.
pub inline fn getId(x: Word) [*:0]const u8 {
    return strtab.strOf(strtab.table, hdGet(hdGet(hdGet(x))));
}
/// The printed name of constructor node `x` (via its id or private-name value).
pub inline fn constrName(x: Word) [*:0]const u8 {
    const tlx = tlGet(x);
    if (isId(tlx)) {
        return getId(tlx);
    } else {
        return getId(pnVal(tlx));
    }
}
/// True when constructor `x` is suppressed from `show` (a `STRCONS` with no id).
pub inline fn suppressed(x: Word) bool {
    const tlx = tlGet(x);
    return isStrcons(tlx) and !isId(pnVal(tlx));
}

/// The standard-error `FILE` handle.
pub fn getStderr() ?*word.FILE {
    const T = @TypeOf(main_clib.stderr);
    if (comptime @typeInfo(T) == .@"fn") {
        return main_clib.stderr();
    } else if (comptime @typeInfo(T) == .pointer and @typeInfo(@typeInfo(T).pointer.child) == .@"fn") {
        return main_clib.stderr();
    } else {
        return main_clib.stderr;
    }
}
/// The standard-output `FILE` handle.
pub fn getStdout() ?*word.FILE {
    const T = @TypeOf(main_clib.stdout);
    if (comptime @typeInfo(T) == .@"fn") {
        return main_clib.stdout();
    } else if (comptime @typeInfo(T) == .pointer and @typeInfo(@typeInfo(T).pointer.child) == .@"fn") {
        return main_clib.stdout();
    } else {
        return main_clib.stdout;
    }
}
/// The standard-input `FILE` handle.
pub fn getStdin() ?*word.FILE {
    const T = @TypeOf(main_clib.stdin);
    if (comptime @typeInfo(T) == .@"fn") {
        return main_clib.stdin();
    } else if (comptime @typeInfo(T) == .pointer and @typeInfo(@typeInfo(T).pointer.child) == .@"fn") {
        return main_clib.stdin();
    } else {
        return main_clib.stdin;
    }
}

/// `x` as an `f64`, converting from a bignum (`INT`) or reading a `DOUBLE` cell.
pub inline fn forceDbl(x: Word) f64 {
    if (isInt(x)) {
        return big.toFloat(heap.heap, x);
    } else {
        return heap.getDbl(x);
    }
}

/// Coerce `x` to a `DOUBLE` cell (no-op if already double; else promote the int).
pub inline fn coerceDbl(x: Word) Word {
    if (isDouble(x)) return x;
    return heap.stoDbl(big.toFloat(heap.heap, x));
}

/// Rewrite `*expr` to `True`/`False` for `left == right` (structural compare).
pub inline fn rewriteToCompareEq(expr: *Word, left: Word, right: Word) void {
    hdSet(expr.*, word.I);
    const val = if (reduce_mod.compare(left, right) == 0) word.True else word.False;
    tlSet(expr.*, val);
    expr.* = val;
}

/// Rewrite `*expr` to `True`/`False` for `left != right`.
pub inline fn rewriteToCompareNeq(expr: *Word, left: Word, right: Word) void {
    hdSet(expr.*, word.I);
    const val = if (reduce_mod.compare(left, right) != 0) word.True else word.False;
    tlSet(expr.*, val);
    expr.* = val;
}

/// Rewrite `*expr` to `True`/`False` for `left > right`.
pub inline fn rewriteToCompareGt(expr: *Word, left: Word, right: Word) void {
    hdSet(expr.*, word.I);
    const val = if (reduce_mod.compare(left, right) > 0) word.True else word.False;
    tlSet(expr.*, val);
    expr.* = val;
}

/// Rewrite `*expr` to `True`/`False` for `left >= right`.
pub inline fn rewriteToCompareGe(expr: *Word, left: Word, right: Word) void {
    hdSet(expr.*, word.I);
    const val = if (reduce_mod.compare(left, right) >= 0) word.True else word.False;
    tlSet(expr.*, val);
    expr.* = val;
}

/// True when single-cell bignum `x` is zero (head digit and tail both 0).
pub inline fn bigzero(x: Word) bool {
    return hdGet(x) == 0 and tlGet(x) == 0;
}

/// Decode a single-cell bignum `x` to a signed `Word`.
pub inline fn getsmallint(x: Word) Word {
    const h_val = hdGet(x);
    return if ((h_val & word.SIGNBIT) != 0) -(h_val & word.MAXDIGIT) else h_val;
}
