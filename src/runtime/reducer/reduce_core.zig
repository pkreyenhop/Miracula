const std = @import("std");
const word = @import("../word.zig");
pub const abi = @import("../c_abi.zig");

pub const Word = c_long;

pub const ReductionCtx = extern struct {
    e: Word,
    s: Word,
    hold: Word,
    args: [4]Word,
    action: c_int,
};

// Extern globals referenced by reducer helpers
extern var hd: [*]Word;
extern var tl: [*]Word;
extern var tag: [*]u8;
pub extern var stdinuse: Word;
pub extern var waiting: Word;
pub extern var errtrap: Word;
pub extern var s_out: ?*word.FILE;

pub extern fn print(e_val: Word) void;
pub extern fn reduce_badcase_error(arg_info: Word) void;
pub extern fn reduce_conf_error(arg_info: Word) void;
pub extern fn conv_args() Word;
pub extern fn getstring(x: Word, cmd: ?[*:0]const u8) ?[*:0]u8;
pub extern fn head(x_val: Word) Word;
pub extern fn force(x_val: Word) void;
pub extern fn reduce(e_val: Word) Word;

pub inline fn clean_ptr(x: Word) usize {
    return @as(usize, @intCast(x & ~abi.tlptrbits));
}

pub inline fn hd_get(x: Word) Word {
    return hd[clean_ptr(x) * 2];
}

pub inline fn hd_set(x: Word, val: Word) void {
    hd[clean_ptr(x) * 2] = val;
}

pub inline fn tl_get(x: Word) Word {
    return tl[clean_ptr(x) * 2];
}

pub inline fn tl_set(x: Word, val: Word) void {
    tl[clean_ptr(x) * 2] = val;
}

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
    ctx.s |= abi.tlptrbit;
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
    ctx.s &= ~abi.tlptrbits;
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
    return !abnormal(x) and tag[@as(usize, @intCast(x))] == word.AP;
}
pub inline fn is_num(x: Word) bool {
    if (abnormal(x)) return false;
    const t = tag[@as(usize, @intCast(x))];
    return t == word.INT or t == word.DOUBLE;
}
pub inline fn is_constructor(x: Word) bool {
    return !abnormal(x) and tag[@as(usize, @intCast(x))] == word.CONSTRUCTOR;
}
pub inline fn is_int(x: Word) bool {
    return !abnormal(x) and tag[@as(usize, @intCast(x))] == word.INT;
}
pub inline fn is_double(x: Word) bool {
    return !abnormal(x) and tag[@as(usize, @intCast(x))] == word.DOUBLE;
}
pub inline fn is_atom(x: Word) bool {
    return !abnormal(x) and tag[@as(usize, @intCast(x))] == word.ATOM;
}
pub inline fn is_strcons(x: Word) bool {
    return !abnormal(x) and tag[@as(usize, @intCast(x))] == word.STRCONS;
}
pub inline fn is_id(x: Word) bool {
    return !abnormal(x) and tag[@as(usize, @intCast(x))] == word.ID;
}
pub inline fn id_val(x: Word) Word {
    return tl_get(x);
}
pub inline fn is_datapair(x: Word) bool {
    return !abnormal(x) and tag[@as(usize, @intCast(x))] == word.DATAPAIR;
}
pub inline fn is_startreadvals(x: Word) bool {
    return !abnormal(x) and tag[@as(usize, @intCast(x))] == word.STARTREADVALS;
}
pub inline fn is_cons(x: Word) bool {
    return !abnormal(x) and tag[@as(usize, @intCast(x))] == word.CONS;
}
pub inline fn is_unicode(x: Word) bool {
    return !abnormal(x) and tag[@as(usize, @intCast(x))] == word.UNICODE;
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
    tag[@as(usize, @intCast(expr))] = word.CONS;
    hd_set(expr, head_value);
}

pub inline fn rewrite_to_cons(expr: Word, head_value: Word, tail_value: Word) void {
    tag[@as(usize, @intCast(expr))] = word.CONS;
    hd_set(expr, head_value);
    tl_set(expr, tail_value);
}

pub inline fn rewrite_to_existing_tail(expr: Word) Word {
    hd_set(expr, word.I);
    return tl_get(expr);
}

pub inline fn ap(x: Word, y: Word) Word {
    return abi.make(word.AP, x, y);
}

pub inline fn rewrite_to_match_result(expr: *Word, left: Word, right: Word, success_value: Word) void {
    hd_set(expr.*, word.I);
    const val = if (abi.compare(left, right) == 0) success_value else word.FAIL;
    tl_set(expr.*, val);
    expr.* = val;
}

pub inline fn rewrite_to_int_match_result(expr: *Word, literal: Word, value: Word, success_value: Word) void {
    hd_set(expr.*, word.I);
    const val = if (!is_int(value) or abi.bigcmp(literal, value) != 0) word.FAIL else success_value;
    tl_set(expr.*, val);
    expr.* = val;
}

pub inline fn rewrite_to_string(expr: *Word, value: [*:0]const u8) void {
    hd_set(expr.*, word.I);
    const val = abi.str_conv(value);
    tl_set(expr.*, val);
    expr.* = val;
}

pub inline fn cons(x: Word, y: Word) Word {
    return abi.make(word.CONS, x, y);
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
    return @as([*:0]const u8, @ptrCast(@alignCast(@as(*anyopaque, @ptrFromInt(@as(usize, @intCast(hd_get(hd_get(hd_get(x))))))))));
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
    const T = @TypeOf(abi.stderr);
    if (comptime @typeInfo(T) == .@"fn") {
        return abi.stderr();
    } else if (comptime @typeInfo(T) == .pointer and @typeInfo(@typeInfo(T).pointer.child) == .@"fn") {
        return abi.stderr();
    } else {
        return abi.stderr;
    }
}
pub fn getStdout() ?*word.FILE {
    const T = @TypeOf(abi.stdout);
    if (comptime @typeInfo(T) == .@"fn") {
        return abi.stdout();
    } else if (comptime @typeInfo(T) == .pointer and @typeInfo(@typeInfo(T).pointer.child) == .@"fn") {
        return abi.stdout();
    } else {
        return abi.stdout;
    }
}
pub fn getStdin() ?*word.FILE {
    const T = @TypeOf(abi.stdin);
    if (comptime @typeInfo(T) == .@"fn") {
        return abi.stdin();
    } else if (comptime @typeInfo(T) == .pointer and @typeInfo(@typeInfo(T).pointer.child) == .@"fn") {
        return abi.stdin();
    } else {
        return abi.stdin;
    }
}

pub inline fn force_dbl(x: Word) f64 {
    if (is_int(x)) {
        return abi.bigtodbl(x);
    } else {
        return abi.get_dbl(x);
    }
}

pub inline fn coerce_dbl(x: Word) Word {
    if (is_double(x)) return x;
    return abi.sto_dbl(abi.bigtodbl(x));
}

pub inline fn rewrite_to_compare_eq(expr: *Word, left: Word, right: Word) void {
    hd_set(expr.*, word.I);
    const val = if (abi.compare(left, right) == 0) word.True else word.False;
    tl_set(expr.*, val);
    expr.* = val;
}

pub inline fn rewrite_to_compare_neq(expr: *Word, left: Word, right: Word) void {
    hd_set(expr.*, word.I);
    const val = if (abi.compare(left, right) != 0) word.True else word.False;
    tl_set(expr.*, val);
    expr.* = val;
}

pub inline fn rewrite_to_compare_gt(expr: *Word, left: Word, right: Word) void {
    hd_set(expr.*, word.I);
    const val = if (abi.compare(left, right) > 0) word.True else word.False;
    tl_set(expr.*, val);
    expr.* = val;
}

pub inline fn rewrite_to_compare_ge(expr: *Word, left: Word, right: Word) void {
    hd_set(expr.*, word.I);
    const val = if (abi.compare(left, right) >= 0) word.True else word.False;
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
