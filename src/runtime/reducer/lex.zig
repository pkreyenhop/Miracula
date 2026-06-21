const std = @import("std");
const word = @import("../word.zig");
const reduce = @import("reduce_core.zig");
const ReductionCtx = reduce.ReductionCtx;
const Word = reduce.Word;
const abi = reduce.abi;

extern var tag: [*]u8;

inline fn lastarg(ctx: *ReductionCtx) Word {
    return reduce.tl_get(ctx.e);
}
inline fn set_lastarg(ctx: *ReductionCtx, val: Word) void {
    reduce.tl_set(ctx.e, val);
}

inline fn lh(x: Word) Word {
    const h_x = reduce.hd_get(x);
    return if (reduce.is_strcons(h_x)) reduce.tl_get(h_x) else h_x;
}

pub fn handle_G_ERROR(ctx: *ReductionCtx) void {
    reduce.GETARG(ctx, &ctx.args[0]);
    reduce.GETARG(ctx, &ctx.args[1]);
    if (reduce.upleft(ctx)) {
        ctx.action = word.ACT_DONE;
        return;
    }
    ctx.hold = reduce.ap(ctx.args[0], lastarg(ctx));
    ctx.hold = reduce.reduce(ctx.hold);
    if (ctx.hold != word.NIL) {
        reduce.rewrite_to_value(&ctx.e, ctx.hold);
        ctx.action = word.ACT_DONE;
        return;
    }
    ctx.hold = abi.g_residue(lastarg(ctx));
    reduce.rewrite_to_cons(ctx.e, reduce.ap(ctx.args[1], ctx.hold), word.NIL);
    ctx.action = word.ACT_DONE;
}

pub fn handle_G_ALT(ctx: *ReductionCtx) void {
    reduce.GETARG(ctx, &ctx.args[0]);
    reduce.GETARG(ctx, &ctx.args[1]);
    if (reduce.upleft(ctx)) {
        ctx.action = word.ACT_DONE;
        return;
    }
    ctx.hold = reduce.ap(ctx.args[0], lastarg(ctx));
    ctx.hold = reduce.reduce(ctx.hold);
    if (ctx.hold != word.NIL) {
        reduce.rewrite_to_value(&ctx.e, ctx.hold);
        ctx.action = word.ACT_DONE;
        return;
    }
    reduce.hd_set(ctx.e, ctx.args[1]);
    reduce.downLeft(ctx);
    ctx.action = word.ACT_NEXTREDEX;
}

pub fn handle_G_OPT(ctx: *ReductionCtx) void {
    reduce.GETARG(ctx, &ctx.args[0]);
    if (reduce.upleft(ctx)) {
        ctx.action = word.ACT_DONE;
        return;
    }
    ctx.hold = reduce.ap(ctx.args[0], lastarg(ctx));
    ctx.hold = reduce.reduce(ctx.hold);
    if (ctx.hold == word.NIL) {
        reduce.rewrite_to_cons(ctx.e, word.NIL, lastarg(ctx));
    } else {
        reduce.rewrite_to_cons(ctx.e, reduce.cons(reduce.hd_get(ctx.hold), word.NIL), reduce.tl_get(ctx.hold));
    }
    ctx.action = word.ACT_DONE;
}

pub fn handle_G_STAR(ctx: *ReductionCtx) void {
    reduce.GETARG(ctx, &ctx.args[0]);
    if (reduce.upleft(ctx)) {
        ctx.action = word.ACT_DONE;
        return;
    }
    ctx.hold = reduce.ap(ctx.args[0], lastarg(ctx));
    ctx.hold = reduce.reduce(ctx.hold);
    if (ctx.hold == word.NIL) {
        reduce.rewrite_to_cons(ctx.e, word.NIL, lastarg(ctx));
        ctx.action = word.ACT_DONE;
        return;
    }
    ctx.args[1] = reduce.ap(reduce.hd_get(ctx.e), reduce.tl_get(ctx.hold));
    tag[reduce.clean_ptr(ctx.e)] = word.CONS;
    reduce.hd_set(ctx.e, reduce.cons(reduce.hd_get(ctx.hold), reduce.ap(word.HD, ctx.args[1])));
    reduce.tl_set(ctx.e, reduce.ap(word.TL, ctx.args[1]));
    ctx.action = word.ACT_DONE;
}

pub fn handle_G_FBSTAR(ctx: *ReductionCtx) void {
    reduce.GETARG(ctx, &ctx.args[0]);
    if (reduce.upleft(ctx)) {
        ctx.action = word.ACT_DONE;
        return;
    }
    ctx.hold = reduce.ap(ctx.args[0], lastarg(ctx));
    ctx.hold = reduce.reduce(ctx.hold);
    if (ctx.hold == word.NIL) {
        reduce.rewrite_to_cons(ctx.e, word.I, lastarg(ctx));
        ctx.action = word.ACT_DONE;
        return;
    }
    reduce.hd_set(ctx.e, reduce.ap2(word.G_SEQ, reduce.hd_get(ctx.e), reduce.ap(word.G_RULE, reduce.ap(word.CB, reduce.hd_get(ctx.hold)))));
    reduce.tl_set(ctx.e, reduce.tl_get(ctx.hold));
    ctx.action = word.ACT_NEXTREDEX;
}

pub fn handle_G_SYMB(ctx: *ReductionCtx) void {
    reduce.GETARG(ctx, &ctx.args[0]);
    if (reduce.upleft(ctx)) {
        ctx.action = word.ACT_DONE;
        return;
    }
    const lastarg_reduced = reduce.reduce(lastarg(ctx));
    set_lastarg(ctx, lastarg_reduced);
    if (lastarg_reduced == word.NIL) {
        reduce.rewrite_to_nil(&ctx.e);
        ctx.action = word.ACT_DONE;
        return;
    }
    reduce.hd_set(lastarg_reduced, reduce.reduce(reduce.hd_get(lastarg_reduced)));
    ctx.hold = reduce.ap(word.HD, reduce.hd_get(lastarg_reduced));
    if (abi.compare(ctx.args[0], reduce.reduce(ctx.hold)) != 0) {
        reduce.rewrite_to_value(&ctx.e, word.NIL); // rewrite_to_failure in C is NIL
    } else {
        reduce.rewrite_to_cons(ctx.e, ctx.args[0], reduce.tl_get(lastarg_reduced));
    }
    ctx.action = word.ACT_DONE;
}

pub fn handle_G_ANY(ctx: *ReductionCtx) void {
    if (reduce.upleft(ctx)) {
        ctx.action = word.ACT_DONE;
        return;
    }
    const lastarg_reduced = reduce.reduce(lastarg(ctx));
    set_lastarg(ctx, lastarg_reduced);
    if (lastarg_reduced == word.NIL) {
        reduce.rewrite_to_value(&ctx.e, word.NIL);
    } else {
        reduce.rewrite_to_cons(ctx.e, reduce.ap(word.HD, reduce.hd_get(lastarg_reduced)), reduce.tl_get(lastarg_reduced));
    }
    ctx.action = word.ACT_DONE;
}

pub fn handle_G_SUCHTHAT(ctx: *ReductionCtx) void {
    reduce.GETARG(ctx, &ctx.args[0]);
    if (reduce.upleft(ctx)) {
        ctx.action = word.ACT_DONE;
        return;
    }
    const lastarg_reduced = reduce.reduce(lastarg(ctx));
    set_lastarg(ctx, lastarg_reduced);
    if (lastarg_reduced == word.NIL) {
        reduce.rewrite_to_value(&ctx.e, word.NIL);
        ctx.action = word.ACT_DONE;
        return;
    }
    ctx.hold = reduce.ap(word.HD, reduce.hd_get(lastarg_reduced));
    ctx.hold = reduce.reduce(ctx.hold);
    if (reduce.reduce(reduce.ap(ctx.args[0], ctx.hold)) == word.True) {
        reduce.rewrite_to_cons(ctx.e, ctx.hold, reduce.tl_get(lastarg_reduced));
    } else {
        reduce.rewrite_to_value(&ctx.e, word.NIL);
    }
    ctx.action = word.ACT_DONE;
}

pub fn handle_G_END(ctx: *ReductionCtx) void {
    if (reduce.upleft(ctx)) {
        ctx.action = word.ACT_DONE;
        return;
    }
    const lastarg_reduced = reduce.reduce(lastarg(ctx));
    set_lastarg(ctx, lastarg_reduced);
    if (lastarg_reduced == word.NIL) {
        reduce.rewrite_to_cons(ctx.e, word.NIL, word.NIL);
    } else {
        reduce.rewrite_to_value(&ctx.e, word.NIL);
    }
    ctx.action = word.ACT_DONE;
}

pub fn handle_G_STATE(ctx: *ReductionCtx) void {
    if (reduce.upleft(ctx)) {
        ctx.action = word.ACT_DONE;
        return;
    }
    const lastarg_reduced = reduce.reduce(lastarg(ctx));
    set_lastarg(ctx, lastarg_reduced);
    if (lastarg_reduced == word.NIL) {
        reduce.rewrite_to_value(&ctx.e, word.NIL);
    } else {
        reduce.rewrite_to_cons(ctx.e, reduce.ap(word.TL, reduce.hd_get(lastarg_reduced)), lastarg_reduced);
    }
    ctx.action = word.ACT_DONE;
}

pub fn handle_G_SEQ(ctx: *ReductionCtx) void {
    reduce.GETARG(ctx, &ctx.args[0]);
    reduce.GETARG(ctx, &ctx.args[1]);
    if (reduce.upleft(ctx)) {
        ctx.action = word.ACT_DONE;
        return;
    }
    ctx.hold = reduce.ap(ctx.args[0], lastarg(ctx));
    ctx.hold = reduce.reduce(ctx.hold);
    if (ctx.hold == word.NIL) {
        reduce.rewrite_to_value(&ctx.e, word.NIL);
        ctx.action = word.ACT_DONE;
        return;
    }
    ctx.args[2] = reduce.ap(ctx.args[1], reduce.tl_get(ctx.hold));
    ctx.args[2] = reduce.reduce(ctx.args[2]);
    if (ctx.args[2] == word.NIL) {
        reduce.rewrite_to_value(&ctx.e, word.NIL);
        ctx.action = word.ACT_DONE;
        return;
    }
    reduce.rewrite_to_cons(ctx.e, reduce.ap(reduce.hd_get(ctx.args[2]), reduce.hd_get(ctx.hold)), reduce.tl_get(ctx.args[2]));
    ctx.action = word.ACT_DONE;
}

pub fn handle_G_UNIT(ctx: *ReductionCtx) void {
    if (reduce.upleft(ctx)) {
        ctx.action = word.ACT_DONE;
        return;
    }
    reduce.rewrite_to_cons_head(ctx.e, word.I);
    ctx.action = word.ACT_DONE;
}

pub fn handle_G_ZERO(ctx: *ReductionCtx) void {
    if (reduce.upleft(ctx)) {
        ctx.action = word.ACT_DONE;
        return;
    }
    reduce.rewrite_to_value(&ctx.e, word.NIL);
    ctx.action = word.ACT_DONE;
}

pub fn handle_G_CLOSE(ctx: *ReductionCtx) void {
    reduce.GETARG(ctx, &ctx.args[0]);
    reduce.GETARG(ctx, &ctx.args[1]);
    if (reduce.upleft(ctx)) {
        ctx.action = word.ACT_DONE;
        return;
    }
    ctx.args[2] = reduce.ap(word.G_COUNT, lastarg(ctx));
    ctx.hold = reduce.ap(ctx.args[1], ctx.args[2]);
    ctx.hold = reduce.reduce(ctx.hold);
    if (ctx.hold == word.NIL) {
        abi.reduce_parse_close_error(ctx.args[0], ctx.args[2]);
    }
    reduce.rewrite_to_value(&ctx.e, reduce.hd_get(ctx.hold));
    ctx.action = word.ACT_NEXTREDEX;
}

pub fn handle_G_COUNT(ctx: *ReductionCtx) void {
    if (reduce.upleft(ctx)) {
        ctx.action = word.ACT_DONE;
        return;
    }
    const lastarg_reduced = reduce.reduce(lastarg(ctx));
    set_lastarg(ctx, lastarg_reduced);
    if (lastarg_reduced == word.NIL) {
        reduce.rewrite_to_nil(&ctx.e);
        ctx.action = word.ACT_DONE;
        return;
    }
    reduce.rewrite_to_cons(ctx.e, reduce.hd_get(lastarg_reduced), reduce.ap(word.G_COUNT, reduce.tl_get(lastarg_reduced)));
    ctx.action = word.ACT_DONE;
}

pub fn handle_LEX_RPT1(ctx: *ReductionCtx) void {
    reduce.GETARG(ctx, &ctx.args[0]);
    reduce.upLeft(ctx);
    reduce.hd_set(ctx.e, reduce.ap(word.B, reduce.ap2(word.LEX_RPT, ctx.args[0], lastarg(ctx))));
    reduce.tl_set(ctx.e, word.LEX_COUNT0);
    reduce.downLeft(ctx);
    reduce.downLeft(ctx);
    ctx.action = word.ACT_NEXTREDEX;
}

pub fn handle_LEX_RPT(ctx: *ReductionCtx) void {
    reduce.GETARG(ctx, &ctx.args[0]);
    reduce.GETARG(ctx, &ctx.args[1]);
    if (reduce.upleft(ctx)) {
        ctx.action = word.ACT_DONE;
        return;
    }
    const lastarg_reduced = reduce.reduce(lastarg(ctx));
    set_lastarg(ctx, lastarg_reduced);
    if (lastarg_reduced == word.NIL) {
        reduce.rewrite_to_nil(&ctx.e);
        ctx.action = word.ACT_DONE;
        return;
    }
    ctx.hold = reduce.ap2(ctx.args[0], ctx.args[1], lastarg_reduced);
    ctx.args[0] = reduce.hd_get(reduce.hd_get(ctx.e));
    ctx.hold = reduce.reduce(ctx.hold);
    reduce.rewrite_to_cons(ctx.e, reduce.hd_get(ctx.hold), reduce.ap2(ctx.args[0], reduce.hd_get(reduce.tl_get(ctx.hold)), reduce.tl_get(reduce.tl_get(ctx.hold))));
    ctx.action = word.ACT_DONE;
}

pub fn handle_LEX_TRY(ctx: *ReductionCtx) void {
    if (reduce.upleft(ctx)) {
        ctx.action = word.ACT_DONE;
        return;
    }
    reduce.tl_set(ctx.e, reduce.reduce(reduce.tl_get(ctx.e)));
    reduce.force(reduce.tl_get(ctx.e));
    reduce.hd_set(ctx.e, word.LEX_TRY_);
    reduce.downLeft(ctx);
    ctx.action = word.ACT_NEXTREDEX;
}

pub fn handle_LEX_TRY_(ctx: *ReductionCtx) void {
    reduce.GETARG(ctx, &ctx.args[0]);
    reduce.GETARG(ctx, &ctx.args[1]);
    if (reduce.upleft(ctx)) {
        ctx.action = word.ACT_DONE;
        return;
    }
    while (true) {
        if (ctx.args[0] == word.NIL) {
            abi.lexfail(lastarg(ctx));
        }
        const hd_hd_hd_arg1 = reduce.hd_get(reduce.hd_get(reduce.hd_get(ctx.args[0])));
        if (hd_hd_hd_arg1 != 0 and abi.member(hd_hd_hd_arg1, ctx.args[1]) == 0) {
            ctx.args[0] = reduce.tl_get(ctx.args[0]);
            continue;
        }
        ctx.hold = reduce.ap(reduce.hd_get(reduce.tl_get(reduce.hd_get(ctx.args[0]))), lastarg(ctx));
        ctx.hold = reduce.reduce(ctx.hold);
        if (ctx.hold == word.NIL) {
            ctx.args[0] = reduce.tl_get(ctx.args[0]);
            continue;
        }
        const tl_hd_hd_arg1 = reduce.tl_get(reduce.hd_get(reduce.hd_get(ctx.args[0])));
        reduce.rewrite_to_cons(ctx.e, reduce.ap(reduce.tl_get(reduce.tl_get(reduce.hd_get(ctx.args[0]))), reduce.ap(word.DESTREV, reduce.hd_get(ctx.hold))), reduce.cons(if (tl_hd_hd_arg1 != 0) tl_hd_hd_arg1 - 1 else ctx.args[1], reduce.tl_get(ctx.hold)));
        ctx.action = word.ACT_DONE;
        return;
    }
}

pub fn handle_LEX_TRY1(ctx: *ReductionCtx) void {
    if (reduce.upleft(ctx)) {
        ctx.action = word.ACT_DONE;
        return;
    }
    reduce.tl_set(ctx.e, reduce.reduce(reduce.tl_get(ctx.e)));
    reduce.force(reduce.tl_get(ctx.e));
    reduce.hd_set(ctx.e, word.LEX_TRY1_);
    reduce.downLeft(ctx);
    ctx.action = word.ACT_NEXTREDEX;
}

pub fn handle_LEX_TRY1_(ctx: *ReductionCtx) void {
    reduce.GETARG(ctx, &ctx.args[0]);
    reduce.GETARG(ctx, &ctx.args[1]);
    if (reduce.upleft(ctx)) {
        ctx.action = word.ACT_DONE;
        return;
    }
    while (true) {
        if (ctx.args[0] == word.NIL) {
            abi.lexfail(lastarg(ctx));
        }
        const hd_hd_hd_arg1 = reduce.hd_get(reduce.hd_get(reduce.hd_get(ctx.args[0])));
        if (hd_hd_hd_arg1 != 0 and abi.member(hd_hd_hd_arg1, ctx.args[1]) == 0) {
            ctx.args[0] = reduce.tl_get(ctx.args[0]);
            continue;
        }
        ctx.hold = reduce.ap(reduce.hd_get(reduce.tl_get(reduce.hd_get(ctx.args[0]))), lastarg(ctx));
        ctx.hold = reduce.reduce(ctx.hold);
        if (ctx.hold == word.NIL) {
            ctx.args[0] = reduce.tl_get(ctx.args[0]);
            continue;
        }
        const tl_hd_hd_arg1 = reduce.tl_get(reduce.hd_get(reduce.hd_get(ctx.args[0])));
        reduce.rewrite_to_cons(ctx.e, reduce.ap2(reduce.tl_get(reduce.tl_get(reduce.hd_get(ctx.args[0]))), abi.lexstate(lastarg(ctx)), reduce.ap(word.DESTREV, reduce.hd_get(ctx.hold))), reduce.cons(if (tl_hd_hd_arg1 != 0) tl_hd_hd_arg1 - 1 else ctx.args[1], reduce.tl_get(ctx.hold)));
        ctx.action = word.ACT_DONE;
        return;
    }
}

pub fn handle_DESTREV(ctx: *ReductionCtx) void {
    reduce.GETARG(ctx, &ctx.args[0]);
    ctx.args[1] = word.NIL;
    while (ctx.args[0] != word.NIL) {
        if (reduce.is_strcons(reduce.hd_get(ctx.args[0]))) {
            reduce.hd_set(ctx.args[0], reduce.tl_get(reduce.hd_get(ctx.args[0])));
        }
        ctx.hold = reduce.tl_get(ctx.args[0]);
        reduce.tl_set(ctx.args[0], ctx.args[1]);
        ctx.args[1] = ctx.args[0];
        ctx.args[0] = ctx.hold;
    }
    reduce.rewrite_to_value(&ctx.e, ctx.args[1]);
    ctx.action = word.ACT_DONE;
}

pub fn handle_LEX_COUNT0(ctx: *ReductionCtx) void {
    if (reduce.upleft(ctx)) {
        ctx.action = word.ACT_DONE;
        return;
    }
    reduce.hd_set(ctx.e, word.LEX_COUNT);
    reduce.tl_set(ctx.e, abi.strcons(0, reduce.tl_get(ctx.e)));
    reduce.downLeft(ctx);
    ctx.action = word.ACT_NEXTREDEX;
}

pub fn handle_LEX_COUNT(ctx: *ReductionCtx) void {
    reduce.GETARG(ctx, &ctx.args[0]);
    const next_tl = reduce.reduce(reduce.tl_get(ctx.args[0]));
    reduce.tl_set(ctx.args[0], next_tl);
    if (next_tl == word.NIL) {
        reduce.rewrite_to_nil(&ctx.e);
        ctx.action = word.ACT_DONE;
        return;
    }
    ctx.hold = reduce.hd_get(next_tl);
    reduce.rewrite_to_cons(ctx.e, abi.strcons(reduce.hd_get(ctx.args[0]), ctx.hold), reduce.ap(word.LEX_COUNT, ctx.args[0]));
    if (ctx.hold == '\n') {
        reduce.hd_set(ctx.args[0], ((reduce.hd_get(ctx.args[0]) >> 8) + 1) << 8);
    } else {
        var col = reduce.hd_get(ctx.args[0]) & 255;
        col = if (ctx.hold == '\t') ((@divTrunc(col, 8)) + 1) * 8 else col + 1;
        reduce.hd_set(ctx.args[0], (reduce.hd_get(ctx.args[0]) & (~@as(Word, 255))) | col);
    }
    reduce.tl_set(ctx.args[0], reduce.tl_get(next_tl));
    ctx.action = word.ACT_DONE;
}

pub fn handle_LEX_STRING(ctx: *ReductionCtx) void {
    reduce.GETARG(ctx, &ctx.args[0]);
    reduce.GETARG(ctx, &ctx.args[1]);
    if (reduce.upleft(ctx)) {
        ctx.action = word.ACT_DONE;
        return;
    }
    while (ctx.args[0] != word.NIL) {
        const lastarg_reduced = reduce.reduce(lastarg(ctx));
        set_lastarg(ctx, lastarg_reduced);
        if (lastarg_reduced == word.NIL or lh(lastarg_reduced) != reduce.hd_get(ctx.args[0])) {
            reduce.rewrite_to_nil(&ctx.e);
            ctx.action = word.ACT_DONE;
            return;
        }
        ctx.args[0] = reduce.tl_get(ctx.args[0]);
        ctx.args[1] = reduce.cons(reduce.hd_get(lastarg_reduced), ctx.args[1]);
        set_lastarg(ctx, reduce.tl_get(lastarg_reduced));
    }
    reduce.rewrite_to_cons_head(ctx.e, ctx.args[1]);
    ctx.action = word.ACT_DONE;
}

pub fn handle_LEX_CLASS(ctx: *ReductionCtx) void {
    reduce.GETARG(ctx, &ctx.args[0]);
    reduce.GETARG(ctx, &ctx.args[1]);
    if (reduce.upleft(ctx)) {
        ctx.action = word.ACT_DONE;
        return;
    }
    const lastarg_reduced = reduce.reduce(lastarg(ctx));
    set_lastarg(ctx, lastarg_reduced);
    if (lastarg_reduced == word.NIL or
        (if (reduce.hd_get(ctx.args[0]) == word.ANTICHARCLASS)
            abi.memclass(@intCast(lh(lastarg_reduced)), reduce.tl_get(ctx.args[0])) != 0
        else
            abi.memclass(@intCast(lh(lastarg_reduced)), ctx.args[0]) == 0))
    {
        reduce.rewrite_to_nil(&ctx.e);
        ctx.action = word.ACT_DONE;
        return;
    }
    reduce.rewrite_to_cons(ctx.e, reduce.cons(reduce.hd_get(lastarg_reduced), ctx.args[1]), reduce.tl_get(lastarg_reduced));
    ctx.action = word.ACT_DONE;
}

pub fn handle_LEX_DOT(ctx: *ReductionCtx) void {
    reduce.GETARG(ctx, &ctx.args[0]);
    if (reduce.upleft(ctx)) {
        ctx.action = word.ACT_DONE;
        return;
    }
    const lastarg_reduced = reduce.reduce(lastarg(ctx));
    set_lastarg(ctx, lastarg_reduced);
    if (lastarg_reduced == word.NIL) {
        reduce.rewrite_to_nil(&ctx.e);
        ctx.action = word.ACT_DONE;
        return;
    }
    reduce.rewrite_to_cons(ctx.e, reduce.cons(reduce.hd_get(lastarg_reduced), ctx.args[0]), reduce.tl_get(lastarg_reduced));
    ctx.action = word.ACT_DONE;
}

pub fn handle_LEX_CHAR(ctx: *ReductionCtx) void {
    reduce.GETARG(ctx, &ctx.args[0]);
    reduce.GETARG(ctx, &ctx.args[1]);
    if (reduce.upleft(ctx)) {
        ctx.action = word.ACT_DONE;
        return;
    }
    const lastarg_reduced = reduce.reduce(lastarg(ctx));
    set_lastarg(ctx, lastarg_reduced);
    if (lastarg_reduced == word.NIL or lh(lastarg_reduced) != ctx.args[0]) {
        reduce.rewrite_to_nil(&ctx.e);
        ctx.action = word.ACT_DONE;
        return;
    }
    reduce.rewrite_to_cons(ctx.e, reduce.cons(ctx.args[0], ctx.args[1]), reduce.tl_get(lastarg_reduced));
    ctx.action = word.ACT_DONE;
}

pub fn handle_LEX_SEQ(ctx: *ReductionCtx) void {
    reduce.GETARG(ctx, &ctx.args[0]);
    reduce.GETARG(ctx, &ctx.args[1]);
    reduce.GETARG(ctx, &ctx.args[2]);
    if (reduce.upleft(ctx)) {
        ctx.action = word.ACT_DONE;
        return;
    }
    ctx.hold = reduce.ap2(ctx.args[0], ctx.args[2], lastarg(ctx));
    set_lastarg(ctx, word.NIL);
    ctx.hold = reduce.reduce(ctx.hold);
    if (ctx.hold == word.NIL) {
        ctx.e = reduce.rewrite_to_existing_tail(ctx.e);
        ctx.action = word.ACT_DONE;
        return;
    }
    reduce.hd_set(ctx.e, reduce.ap(ctx.args[1], reduce.hd_get(ctx.hold)));
    reduce.tl_set(ctx.e, reduce.tl_get(ctx.hold));
    reduce.downLeft(ctx);
    reduce.downLeft(ctx);
    ctx.action = word.ACT_NEXTREDEX;
}

pub fn handle_LEX_OR(ctx: *ReductionCtx) void {
    reduce.GETARG(ctx, &ctx.args[0]);
    reduce.GETARG(ctx, &ctx.args[1]);
    reduce.GETARG(ctx, &ctx.args[2]);
    if (reduce.upleft(ctx)) {
        ctx.action = word.ACT_DONE;
        return;
    }
    ctx.hold = reduce.ap2(ctx.args[0], ctx.args[2], lastarg(ctx));
    ctx.hold = reduce.reduce(ctx.hold);
    if (ctx.hold == word.NIL) {
        reduce.hd_set(ctx.e, reduce.ap(ctx.args[1], ctx.args[2]));
        reduce.downLeft(ctx);
        reduce.downLeft(ctx);
        ctx.action = word.ACT_NEXTREDEX;
        return;
    }
    reduce.rewrite_to_value(&ctx.e, ctx.hold);
    ctx.action = word.ACT_DONE;
}

pub fn handle_LEX_RCONTEXT(ctx: *ReductionCtx) void {
    reduce.GETARG(ctx, &ctx.args[0]);
    reduce.GETARG(ctx, &ctx.args[1]);
    reduce.GETARG(ctx, &ctx.args[2]);
    if (reduce.upleft(ctx)) {
        ctx.action = word.ACT_DONE;
        return;
    }
    ctx.hold = reduce.ap2(ctx.args[0], ctx.args[2], lastarg(ctx));
    set_lastarg(ctx, word.NIL);
    ctx.hold = reduce.reduce(ctx.hold);
    if (ctx.hold == word.NIL or
        (if (ctx.args[1] != 0)
            reduce.reduce(reduce.ap2(ctx.args[1], reduce.hd_get(ctx.hold), reduce.tl_get(ctx.hold))) == word.NIL
        else blk: {
            const next_tl = reduce.reduce(reduce.tl_get(ctx.hold));
            reduce.tl_set(ctx.hold, next_tl);
            break :blk next_tl != word.NIL;
        }))
    {
        ctx.e = reduce.rewrite_to_existing_tail(ctx.e);
        ctx.action = word.ACT_DONE;
        return;
    }
    reduce.rewrite_to_value(&ctx.e, ctx.hold);
    ctx.action = word.ACT_DONE;
}

pub fn handle_LEX_STAR(ctx: *ReductionCtx) void {
    reduce.GETARG(ctx, &ctx.args[0]);
    reduce.GETARG(ctx, &ctx.args[1]);
    if (reduce.upleft(ctx)) {
        ctx.action = word.ACT_DONE;
        return;
    }
    ctx.hold = reduce.ap2(ctx.args[0], ctx.args[1], lastarg(ctx));
    while (true) {
        const next_hold = reduce.reduce(ctx.hold);
        if (next_hold == word.NIL) break;
        ctx.args[1] = reduce.hd_get(next_hold);
        set_lastarg(ctx, reduce.tl_get(next_hold));
        ctx.hold = reduce.ap2(ctx.args[0], ctx.args[1], lastarg(ctx));
    }
    reduce.rewrite_to_cons_head(ctx.e, ctx.args[1]);
    ctx.action = word.ACT_DONE;
}

pub fn handle_LEX_OPT(ctx: *ReductionCtx) void {
    reduce.GETARG(ctx, &ctx.args[0]);
    reduce.GETARG(ctx, &ctx.args[1]);
    if (reduce.upleft(ctx)) {
        ctx.action = word.ACT_DONE;
        return;
    }
    ctx.hold = reduce.ap2(ctx.args[0], ctx.args[1], lastarg(ctx));
    ctx.hold = reduce.reduce(ctx.hold);
    if (ctx.hold == word.NIL) {
        reduce.rewrite_to_cons_head(ctx.e, ctx.args[1]);
        ctx.action = word.ACT_DONE;
        return;
    }
    reduce.rewrite_to_value(&ctx.e, ctx.hold);
    ctx.action = word.ACT_DONE;
}
