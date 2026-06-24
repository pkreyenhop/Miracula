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

const std = @import("std");
const word = @import("../word.zig");
const strtab = @import("../strtab.zig");

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

// Extern globals referenced by reducer helpers

pub const print = reduce_mod.print;
pub const badcaseError = reduce_mod.badcaseError;
pub const confError = reduce_mod.confError;
pub const conv_args = lex_mod.conv_args;
pub const getstring = reduce_mod.getstring;
pub const head = reduce_mod.head;
pub const force = reduce_mod.force;
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

pub inline fn hd_get(x: Word) Word {
    return heap.heap.h(x & ~word.tlptrbits);
}

pub inline fn hd_set(x: Word, val: Word) void {
    heap.heap.hp(x & ~word.tlptrbits).* = val;
}

pub inline fn tl_get(x: Word) Word {
    return heap.heap.t(x & ~word.tlptrbits);
}

pub inline fn tl_set(x: Word, val: Word) void {
    heap.heap.tp(x & ~word.tlptrbits).* = val;
}

pub inline fn getTag(x: Word) u8 {
    return heap.heap.getTag(x & ~word.tlptrbits);
}

pub inline fn setTag(x: Word, val: u8) void {
    heap.heap.setTag(x & ~word.tlptrbits, val);
}

pub inline fn tl_ptr(x: Word) *Word {
    return heap.heap.tp(x & ~word.tlptrbits);
}

// Pointer-reversal traversal — see `reducer/reduce.zig` for the mechanics.
// `downX`/`upX` push/pop the reversed spine; the lowercase wrappers
// (`downright`/`upleft`) stop at the `s < 0` bottom-of-spine sentinel.

pub inline fn downLeft(ctx: *ReductionCtx) void {
    ctx.hold = ctx.s;
    ctx.s = ctx.e;
    ctx.e = hd_get(ctx.e);
    hd_set(ctx.s, ctx.hold);
}

pub inline fn downRight(ctx: *ReductionCtx) void {
    ctx.hold = hd_get(ctx.s);
    hd_set(ctx.s, ctx.e);
    ctx.e = tl_get(ctx.s);
    tl_set(ctx.s, ctx.hold);
    ctx.s |= word.tlptrbit;
}

pub inline fn downright(ctx: *ReductionCtx) bool {
    if (ctx.s < 0) {
        return true;
    }
    downRight(ctx);
    return false;
}

pub inline fn upLeft(ctx: *ReductionCtx) void {
    ctx.hold = ctx.s;
    ctx.s = hd_get(ctx.s);
    hd_set(ctx.hold, ctx.e);
    ctx.e = ctx.hold;
}

pub inline fn upleft(ctx: *ReductionCtx) bool {
    if (ctx.s < 0) {
        return true;
    }
    upLeft(ctx);
    return false;
}

pub inline fn upRight(ctx: *ReductionCtx) void {
    ctx.s &= ~word.tlptrbits;
    ctx.hold = tl_get(ctx.s);
    tl_set(ctx.s, ctx.e);
    ctx.e = hd_get(ctx.s);
    hd_set(ctx.s, ctx.hold);
}

pub inline fn GETARG(ctx: *ReductionCtx, a: *Word) void {
    upLeft(ctx);
    a.* = tl_get(ctx.e);
}

pub inline fn getarg(ctx: *ReductionCtx, a: *Word) bool {
    if (upleft(ctx)) {
        return true;
    }
    a.* = tl_get(ctx.e);
    return false;
}

pub inline fn simpl(ctx: *ReductionCtx, r: Word) void {
    hd_set(ctx.e, word.I);
    tl_set(ctx.e, r);
    ctx.e = r;
}

pub inline fn abnormal(x: Word) bool {
    return x < 0;
}
pub inline fn is_ap(x: Word) bool {
    return !abnormal(x) and getTag(x) == word.AP;
}
pub inline fn is_num(x: Word) bool {
    if (abnormal(x)) return false;
    const t = getTag(x);
    return t == word.INT or t == word.DOUBLE;
}
pub inline fn is_constructor(x: Word) bool {
    return !abnormal(x) and getTag(x) == word.CONSTRUCTOR;
}
pub inline fn is_int(x: Word) bool {
    return !abnormal(x) and getTag(x) == word.INT;
}
pub inline fn is_double(x: Word) bool {
    return !abnormal(x) and getTag(x) == word.DOUBLE;
}
pub inline fn is_atom(x: Word) bool {
    return !abnormal(x) and getTag(x) == word.ATOM;
}
pub inline fn is_strcons(x: Word) bool {
    return !abnormal(x) and getTag(x) == word.STRCONS;
}
pub inline fn is_id(x: Word) bool {
    return !abnormal(x) and getTag(x) == word.ID;
}
pub inline fn id_val(x: Word) Word {
    return tl_get(x);
}
pub inline fn is_datapair(x: Word) bool {
    return !abnormal(x) and getTag(x) == word.DATAPAIR;
}
pub inline fn is_startreadvals(x: Word) bool {
    return !abnormal(x) and getTag(x) == word.STARTREADVALS;
}
pub inline fn is_cons(x: Word) bool {
    return !abnormal(x) and getTag(x) == word.CONS;
}
pub inline fn is_unicode(x: Word) bool {
    return !abnormal(x) and getTag(x) == word.UNICODE;
}

pub inline fn rewrite_to_value(expr: *Word, value: Word) void {
    hd_set(expr.*, word.I);
    tl_set(expr.*, value);
    expr.* = value;
}

pub inline fn rewrite_to_nil(expr: *Word) void {
    rewrite_to_value(expr, word.NIL);
}

pub inline fn rewrite_to_fail(expr: *Word) void {
    rewrite_to_value(expr, word.FAIL);
}

pub inline fn rewrite_to_failure(expr: *Word) void {
    rewrite_to_value(expr, word.NIL);
}

pub inline fn rewrite_to_cons_head(expr: Word, head_value: Word) void {
    setTag(expr, word.CONS);
    hd_set(expr, head_value);
}

pub inline fn rewrite_to_cons(expr: Word, head_value: Word, tail_value: Word) void {
    setTag(expr, word.CONS);
    hd_set(expr, head_value);
    tl_set(expr, tail_value);
}

pub inline fn rewrite_to_existing_tail(expr: Word) Word {
    hd_set(expr, word.I);
    return tl_get(expr);
}

pub inline fn ap(x: Word, y: Word) Word {
    return heap.make(word.AP, x, y);
}

pub inline fn rewrite_to_match_result(expr: *Word, left: Word, right: Word, success_value: Word) void {
    hd_set(expr.*, word.I);
    const val = if (reduce_mod.compare(left, right) == 0) success_value else word.FAIL;
    tl_set(expr.*, val);
    expr.* = val;
}

pub inline fn rewrite_to_int_match_result(expr: *Word, literal: Word, value: Word, success_value: Word) void {
    hd_set(expr.*, word.I);
    const val = if (!is_int(value) or big.cmp(literal, value) != 0) word.FAIL else success_value;
    tl_set(expr.*, val);
    expr.* = val;
}

pub inline fn rewrite_to_string(expr: *Word, value: [*:0]const u8) void {
    hd_set(expr.*, word.I);
    const val = lex_mod.str_conv(value);
    tl_set(expr.*, val);
    expr.* = val;
}

pub inline fn cons(x: Word, y: Word) Word {
    return heap.make(word.CONS, x, y);
}

pub inline fn ap2(f: Word, x: Word, y: Word) Word {
    return ap(ap(f, x), y);
}

pub inline fn neg(x: Word) bool {
    return (hd_get(x) & word.SIGNBIT) != 0;
}
pub inline fn poz(x: Word) bool {
    return !neg(x);
}
pub inline fn pn_val(x: Word) Word {
    return tl_get(x);
}
pub inline fn get_id(x: Word) [*:0]const u8 {
    return strtab.strOf(hd_get(hd_get(hd_get(x))));
}
pub inline fn constr_name(x: Word) [*:0]const u8 {
    const tlx = tl_get(x);
    if (is_id(tlx)) {
        return get_id(tlx);
    } else {
        return get_id(pn_val(tlx));
    }
}
pub inline fn suppressed(x: Word) bool {
    const tlx = tl_get(x);
    return is_strcons(tlx) and !is_id(pn_val(tlx));
}

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

pub inline fn force_dbl(x: Word) f64 {
    if (is_int(x)) {
        return big.toFloat(x);
    } else {
        return heap.get_dbl(x);
    }
}

pub inline fn coerce_dbl(x: Word) Word {
    if (is_double(x)) return x;
    return heap.sto_dbl(big.toFloat(x));
}

pub inline fn rewrite_to_compare_eq(expr: *Word, left: Word, right: Word) void {
    hd_set(expr.*, word.I);
    const val = if (reduce_mod.compare(left, right) == 0) word.True else word.False;
    tl_set(expr.*, val);
    expr.* = val;
}

pub inline fn rewrite_to_compare_neq(expr: *Word, left: Word, right: Word) void {
    hd_set(expr.*, word.I);
    const val = if (reduce_mod.compare(left, right) != 0) word.True else word.False;
    tl_set(expr.*, val);
    expr.* = val;
}

pub inline fn rewrite_to_compare_gt(expr: *Word, left: Word, right: Word) void {
    hd_set(expr.*, word.I);
    const val = if (reduce_mod.compare(left, right) > 0) word.True else word.False;
    tl_set(expr.*, val);
    expr.* = val;
}

pub inline fn rewrite_to_compare_ge(expr: *Word, left: Word, right: Word) void {
    hd_set(expr.*, word.I);
    const val = if (reduce_mod.compare(left, right) >= 0) word.True else word.False;
    tl_set(expr.*, val);
    expr.* = val;
}

pub inline fn bigzero(x: Word) bool {
    return hd_get(x) == 0 and tl_get(x) == 0;
}

pub inline fn getsmallint(x: Word) Word {
    const h_val = hd_get(x);
    return if ((h_val & word.SIGNBIT) != 0) -(h_val & word.MAXDIGIT) else h_val;
}
