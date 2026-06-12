const std = @import("std");
pub const clib = @cImport({
    @cInclude("sys/types.h");
    @cInclude("sys/stat.h");
    @cInclude("unistd.h");
    @cInclude("data.h");
    @cInclude("big.h");
    @cInclude("lex.h");
    @cInclude("combs.h");
    @cInclude("reduce_internal.h");
});

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

pub inline fn clean_ptr(x: Word) usize {
    return @as(usize, @intCast(x & ~clib.tlptrbits));
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

// Traversal Helpers matching C exactly

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
    ctx.s |= clib.tlptrbit;
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
    ctx.s &= ~clib.tlptrbits;
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

pub inline fn rewrite_to_value(expr: *Word, value: Word) void {
    hd_set(expr.*, clib.I);
    tl_set(expr.*, value);
    expr.* = value;
}

pub inline fn rewrite_to_nil(expr: *Word) void {
    rewrite_to_value(expr, clib.NIL);
}

pub inline fn rewrite_to_fail(expr: *Word) void {
    rewrite_to_value(expr, clib.FAIL);
}

pub inline fn rewrite_to_failure(expr: *Word) void {
    rewrite_to_value(expr, clib.NIL);
}

pub inline fn rewrite_to_cons_head(expr: Word, head_value: Word) void {
    tag[@as(usize, @intCast(expr))] = clib.CONS;
    hd_set(expr, head_value);
}

pub inline fn rewrite_to_cons(expr: Word, head_value: Word, tail_value: Word) void {
    tag[@as(usize, @intCast(expr))] = clib.CONS;
    hd_set(expr, head_value);
    tl_set(expr, tail_value);
}

pub inline fn rewrite_to_existing_tail(expr: Word) Word {
    hd_set(expr, clib.I);
    return tl_get(expr);
}

