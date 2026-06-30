//! reduce_core.zig — the reduction machine's primitives, shared by the rewrite
//! handlers (`combinators.zig`, `ready.zig`, `lex.zig`, `io.zig`, which all
//! import this file as `reduce`). It owns the `ReductionCtx` register file and
//! the pointer-reversal traversal/accessor/classifier/rewrite helpers.
//!
//! These primitives are duplicated, definition-for-definition, in the engine
//! file `reducer/reduce.zig` (which uses its own copies inside `reduce()`); that
//! file carries the full explanation of the graph-reduction machine and the
//! pointer-reversal spine. **Keep the two copies in lock-step** — a change here
//! must be mirrored there. This is also the seam where the B-track typed-value
//! work (`Heap`/`Value`) will replace the raw-`Word` `hd_get`/`tl_get` reads.

const word = @import("../word.zig");
const strtab = @import("../strtab.zig");

/// The interpreter machine word (see `word.Word`).
pub const Word = i64;

/// The reduction machine's register file (kept `extern` for a stable layout
/// matching the original C struct). See `reducer/reduce.zig` for the protocol:
///   `e` focus node · `s` reversed-spine pointer (top bits = direction mark,
///   `BACKSTOP` = bottom) · `hold` swap scratch · `args` pulled arguments ·
///   `action` post-dispatch signal (`ACT_NONE`/`ACT_NEXTREDEX`/`ACT_DONE`).
pub const ReductionCtx = extern struct {
    e: Word,
    s: Word,
    hold: Word,
    args: [4]Word,
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
pub inline fn clean_ptr(x: Word) usize {
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
pub inline fn hd_get(x: Word) Word {
    return heap.heap.h(x & ~word.tlptrbits);
}

/// Write the head (`hd`) field through spine word `x`.
pub inline fn hd_set(x: Word, val: Word) void {
    heap.heap.hp(x & ~word.tlptrbits).* = val;
}

/// Read the tail (`tl`) field through spine word `x`.
pub inline fn tl_get(x: Word) Word {
    return heap.heap.t(x & ~word.tlptrbits);
}

/// Write the tail (`tl`) field through spine word `x`.
pub inline fn tl_set(x: Word, val: Word) void {
    heap.heap.tp(x & ~word.tlptrbits).* = val;
}

/// Read the cell tag through spine word `x`.
pub inline fn getTag(x: Word) word.NodeTag {
    return @enumFromInt(heap.heap.getTag(x & ~word.tlptrbits));
}

/// Write the cell tag through spine word `x`.
pub inline fn setTag(x: Word, val: u8) void {
    heap.heap.setTag(x & ~word.tlptrbits, val);
}

/// A pointer to the tail (`tl`) field through spine word `x` (for in-place edits).
pub inline fn tl_ptr(x: Word) *Word {
    return heap.heap.tp(x & ~word.tlptrbits);
}

// Pointer-reversal traversal — see `reducer/reduce.zig` for the mechanics.
// `downX`/`upX` push/pop the reversed spine; the lowercase wrappers
// (`downright`/`upleft`) stop at the `s < 0` bottom-of-spine sentinel.

/// Descend into the head, reversing the spine link (push `e` onto `s`).
pub inline fn downLeft(ctx: *ReductionCtx) void {
    ctx.hold = ctx.s;
    ctx.s = ctx.e;
    ctx.e = hd_get(ctx.e);
    hd_set(ctx.s, ctx.hold);
}

/// Descend into the tail, marking the spine word's direction bit.
pub inline fn downRight(ctx: *ReductionCtx) void {
    ctx.hold = hd_get(ctx.s);
    hd_set(ctx.s, ctx.e);
    ctx.e = tl_get(ctx.s);
    tl_set(ctx.s, ctx.hold);
    ctx.s |= word.tlptrbit;
}

/// [downRight] guarded by the bottom-of-spine sentinel; true if `s` is exhausted.
pub inline fn downright(ctx: *ReductionCtx) bool {
    if (ctx.s < 0) {
        return true;
    }
    downRight(ctx);
    return false;
}

/// Ascend out of the head, restoring the reversed spine link (pop `s` into `e`).
pub inline fn upLeft(ctx: *ReductionCtx) void {
    ctx.hold = ctx.s;
    ctx.s = hd_get(ctx.s);
    hd_set(ctx.hold, ctx.e);
    ctx.e = ctx.hold;
}

/// [upLeft] guarded by the bottom-of-spine sentinel; true if `s` is exhausted.
pub inline fn upleft(ctx: *ReductionCtx) bool {
    if (ctx.s < 0) {
        return true;
    }
    upLeft(ctx);
    return false;
}

/// Ascend out of the tail, clearing the direction mark and restoring the link.
pub inline fn upRight(ctx: *ReductionCtx) void {
    ctx.s &= ~word.tlptrbits;
    ctx.hold = tl_get(ctx.s);
    tl_set(ctx.s, ctx.e);
    ctx.e = hd_get(ctx.s);
    hd_set(ctx.s, ctx.hold);
}

/// Pull the next argument off the spine into `a` (unchecked — caller knows it exists).
pub inline fn GETARG(ctx: *ReductionCtx, a: *Word) void {
    upLeft(ctx);
    a.* = tl_get(ctx.e);
}

/// Pull the next argument off the spine into `a`; true if the spine is exhausted.
pub inline fn getarg(ctx: *ReductionCtx, a: *Word) bool {
    if (upleft(ctx)) {
        return true;
    }
    a.* = tl_get(ctx.e);
    return false;
}

/// Overwrite the focus node with an `I`-indirection to `r` and refocus on `r`
/// (the in-place "simplify to" rewrite that preserves sharing).
pub inline fn simpl(ctx: *ReductionCtx, r: Word) void {
    hd_set(ctx.e, word.I);
    tl_set(ctx.e, r);
    ctx.e = r;
}

/// True for a marked/sentinel spine word (negative) — not a normal cell handle.
pub inline fn abnormal(x: Word) bool {
    return x < 0;
}
/// True when `x` is a (normal) `AP` application cell.
pub inline fn is_ap(x: Word) bool {
    return !abnormal(x) and getTag(x) == .AP;
}
/// True when `x` is a number (`INT` or `DOUBLE`) cell.
pub inline fn is_num(x: Word) bool {
    if (abnormal(x)) return false;
    const t = getTag(x);
    return t == .INT or t == .DOUBLE;
}
/// True when `x` is a `CONSTRUCTOR` cell.
pub inline fn is_constructor(x: Word) bool {
    return !abnormal(x) and getTag(x) == .CONSTRUCTOR;
}
/// True when `x` is an `INT` (bignum) cell.
pub inline fn is_int(x: Word) bool {
    return !abnormal(x) and getTag(x) == .INT;
}
/// True when `x` is a `DOUBLE` cell.
pub inline fn is_double(x: Word) bool {
    return !abnormal(x) and getTag(x) == .DOUBLE;
}
/// True when `x` is a bare `ATOM` cell.
pub inline fn is_atom(x: Word) bool {
    return !abnormal(x) and getTag(x) == .ATOM;
}
/// True when `x` is a `STRCONS` (interned-string) cell.
pub inline fn is_strcons(x: Word) bool {
    return !abnormal(x) and getTag(x) == .STRCONS;
}
/// True when `x` is an `ID` (identifier) cell.
pub inline fn is_id(x: Word) bool {
    return !abnormal(x) and getTag(x) == .ID;
}
/// The value field of id `x` (its tail).
pub inline fn idVal(x: Word) Word {
    return tl_get(x);
}
/// True when `x` is a `DATAPAIR` cell.
pub inline fn is_datapair(x: Word) bool {
    return !abnormal(x) and getTag(x) == .DATAPAIR;
}
/// True when `x` is a `STARTREADVALS` cell.
pub inline fn is_startreadvals(x: Word) bool {
    return !abnormal(x) and getTag(x) == .STARTREADVALS;
}
/// True when `x` is a `CONS` cell.
pub inline fn is_cons(x: Word) bool {
    return !abnormal(x) and getTag(x) == .CONS;
}
/// True when `x` is a `UNICODE` (wide-char) cell.
pub inline fn is_unicode(x: Word) bool {
    return !abnormal(x) and getTag(x) == .UNICODE;
}

/// Rewrite `*expr` in place to an `I`-indirection to `value`, then refocus on it.
pub inline fn rewrite_to_value(expr: *Word, value: Word) void {
    hd_set(expr.*, word.I);
    tl_set(expr.*, value);
    expr.* = value;
}

/// Rewrite `*expr` to `NIL` (the empty list).
pub inline fn rewrite_to_nil(expr: *Word) void {
    rewrite_to_value(expr, word.NIL);
}

/// Rewrite `*expr` to the pattern-match `FAIL` sentinel.
pub inline fn rewrite_to_fail(expr: *Word) void {
    rewrite_to_value(expr, word.FAIL);
}

/// Rewrite `*expr` to a failure (currently `NIL`).
pub inline fn rewrite_to_failure(expr: *Word) void {
    rewrite_to_value(expr, word.NIL);
}

/// Turn `expr` into a `CONS` cell with the given head (tail left unchanged).
pub inline fn rewrite_to_cons_head(expr: Word, head_value: Word) void {
    setTag(expr, word.CONS);
    hd_set(expr, head_value);
}

/// Turn `expr` into a `CONS` cell `(head_value : tail_value)`.
pub inline fn rewrite_to_cons(expr: Word, head_value: Word, tail_value: Word) void {
    setTag(expr, word.CONS);
    hd_set(expr, head_value);
    tl_set(expr, tail_value);
}

/// Collapse `expr` to an `I`-indirection and return its existing tail.
pub inline fn rewrite_to_existing_tail(expr: Word) Word {
    hd_set(expr, word.I);
    return tl_get(expr);
}

/// Allocate an application cell `(x y)`.
pub inline fn ap(x: Word, y: Word) Word {
    return heap.make(word.AP, x, y);
}

/// Rewrite `*expr` to `success_value` if `left` equals `right` (structurally),
/// else to `FAIL` — the pattern-match equality test.
pub inline fn rewrite_to_match_result(expr: *Word, left: Word, right: Word, success_value: Word) void {
    hd_set(expr.*, word.I);
    const val = if (reduce_mod.compare(left, right) == 0) success_value else word.FAIL;
    tl_set(expr.*, val);
    expr.* = val;
}

/// Rewrite `*expr` to `success_value` if `value` is the int `literal`, else `FAIL`.
pub inline fn rewrite_to_int_match_result(expr: *Word, literal: Word, value: Word, success_value: Word) void {
    hd_set(expr.*, word.I);
    const val = if (!is_int(value) or big.cmp(literal, value) != 0) word.FAIL else success_value;
    tl_set(expr.*, val);
    expr.* = val;
}

/// Rewrite `*expr` to the Miranda char-list form of C string `value`.
pub inline fn rewrite_to_string(expr: *Word, value: [*:0]const u8) void {
    hd_set(expr.*, word.I);
    const val = lex_mod.strConv(value);
    tl_set(expr.*, val);
    expr.* = val;
}

/// Allocate a cons cell `(x : y)`.
pub inline fn cons(x: Word, y: Word) Word {
    return heap.make(word.CONS, x, y);
}

/// Build the application `((f x) y)`.
pub inline fn ap2(f: Word, x: Word, y: Word) Word {
    return ap(ap(f, x), y);
}

/// True when bignum `x`'s head digit carries the sign bit (i.e. `x` is negative).
pub inline fn neg(x: Word) bool {
    return (hd_get(x) & word.SIGNBIT) != 0;
}
/// True when bignum `x` is non-negative (the complement of [neg]).
pub inline fn poz(x: Word) bool {
    return !neg(x);
}
/// The value field of private-name node `x` (its tail).
pub inline fn pnVal(x: Word) Word {
    return tl_get(x);
}
/// The interned name text of id node `x`.
pub inline fn get_id(x: Word) [*:0]const u8 {
    return strtab.strOf(hd_get(hd_get(hd_get(x))));
}
/// The printed name of constructor node `x` (via its id or private-name value).
pub inline fn constr_name(x: Word) [*:0]const u8 {
    const tlx = tl_get(x);
    if (is_id(tlx)) {
        return get_id(tlx);
    } else {
        return get_id(pnVal(tlx));
    }
}
/// True when constructor `x` is suppressed from `show` (a `STRCONS` with no id).
pub inline fn suppressed(x: Word) bool {
    const tlx = tl_get(x);
    return is_strcons(tlx) and !is_id(pnVal(tlx));
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
pub inline fn force_dbl(x: Word) f64 {
    if (is_int(x)) {
        return big.toFloat(x);
    } else {
        return heap.getDbl(x);
    }
}

/// Coerce `x` to a `DOUBLE` cell (no-op if already double; else promote the int).
pub inline fn coerce_dbl(x: Word) Word {
    if (is_double(x)) return x;
    return heap.stoDbl(big.toFloat(x));
}

/// Rewrite `*expr` to `True`/`False` for `left == right` (structural compare).
pub inline fn rewrite_to_compare_eq(expr: *Word, left: Word, right: Word) void {
    hd_set(expr.*, word.I);
    const val = if (reduce_mod.compare(left, right) == 0) word.True else word.False;
    tl_set(expr.*, val);
    expr.* = val;
}

/// Rewrite `*expr` to `True`/`False` for `left != right`.
pub inline fn rewrite_to_compare_neq(expr: *Word, left: Word, right: Word) void {
    hd_set(expr.*, word.I);
    const val = if (reduce_mod.compare(left, right) != 0) word.True else word.False;
    tl_set(expr.*, val);
    expr.* = val;
}

/// Rewrite `*expr` to `True`/`False` for `left > right`.
pub inline fn rewrite_to_compare_gt(expr: *Word, left: Word, right: Word) void {
    hd_set(expr.*, word.I);
    const val = if (reduce_mod.compare(left, right) > 0) word.True else word.False;
    tl_set(expr.*, val);
    expr.* = val;
}

/// Rewrite `*expr` to `True`/`False` for `left >= right`.
pub inline fn rewrite_to_compare_ge(expr: *Word, left: Word, right: Word) void {
    hd_set(expr.*, word.I);
    const val = if (reduce_mod.compare(left, right) >= 0) word.True else word.False;
    tl_set(expr.*, val);
    expr.* = val;
}

/// True when single-cell bignum `x` is zero (head digit and tail both 0).
pub inline fn bigzero(x: Word) bool {
    return hd_get(x) == 0 and tl_get(x) == 0;
}

/// Decode a single-cell bignum `x` to a signed `Word`.
pub inline fn getsmallint(x: Word) Word {
    const h_val = hd_get(x);
    return if ((h_val & word.SIGNBIT) != 0) -(h_val & word.MAXDIGIT) else h_val;
}
