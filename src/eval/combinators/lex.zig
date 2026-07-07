//! eval/combinators/lex.zig — reduction handlers for the grammar/lexer combinators.
//!
//! Implements Miranda's `%bnf` parser combinators (`G_*`, over a token stream)
//! and `%lex` lexer combinators (`LEX_*`, over a character stream): alternation,
//! sequence, option, repetition, guards, char classes, right-context lookahead,
//! and the position-tracking machinery (`G_COUNT`/`G_CLOSE`) used for parse-error
//! reporting. Dispatched from `reducer/reduce.zig`; each `handle_<NAME>` mirrors
//! the `word.<NAME>` combinator constant. A grammar yields `(result . rest)` on
//! success or `NIL` on failure.

const word = @import("../../graph/word.zig");
const reduce = @import("../reduce_core.zig");
const os = @import("../../os.zig");
const reduce_rt = @import("../reduce_rt.zig");
const types = @import("../../semantics/depend.zig");
const ReductionCtx = reduce.ReductionCtx;
const Word = reduce.Word;

/// The combinator's last argument — the remaining input/token stream (focus node's tail).
inline fn lastarg(ctx: *ReductionCtx) Word {
    return reduce.tlGet(ctx.heap, ctx.e);
}
/// Replace the focus node's last argument (the remaining input).
inline fn setLastarg(ctx: *ReductionCtx, val: Word) void {
    reduce.tlSet(ctx.heap, ctx.e, val);
}

/// The "logical head" of `x`: its char value, unwrapping a `STRCONS` cell.
inline fn lh(heap: *reduce.Heap, x: Word) Word {
    const h_x = reduce.hdGet(heap, x);
    return if (reduce.isStrcons(heap, h_x)) reduce.tlGet(heap, h_x) else h_x;
}

/// `G_ERROR`: try grammar `arg0`; on failure, build an error report via `arg1` over the residual tokens.
pub fn handle_G_ERROR(ctx: *ReductionCtx) reduce.ReduceError!void {
    reduce.GETARG(ctx, &ctx.args[0]);
    reduce.GETARG(ctx, &ctx.args[1]);
    if (reduce.upleft(ctx)) {
        ctx.action = word.ACT_DONE;
        return;
    }
    ctx.hold = reduce.ap(ctx.heap, ctx.args[0], lastarg(ctx));
    ctx.hold = try reduce.reduce(ctx.hold);
    if (ctx.hold != word.NIL) {
        reduce.rewriteToValue(ctx.heap, &ctx.e, ctx.hold);
        ctx.action = word.ACT_DONE;
        return;
    }
    ctx.hold = reduce_rt.gResidue(lastarg(ctx));
    reduce.rewriteToCons(ctx.heap, ctx.e, reduce.ap(ctx.heap, ctx.args[1], ctx.hold), word.NIL);
    ctx.action = word.ACT_DONE;
}

/// `G_ALT`: ordered alternation — try `arg0`, falling back to `arg1` on failure.
pub fn handle_G_ALT(ctx: *ReductionCtx) reduce.ReduceError!void {
    reduce.GETARG(ctx, &ctx.args[0]);
    reduce.GETARG(ctx, &ctx.args[1]);
    if (reduce.upleft(ctx)) {
        ctx.action = word.ACT_DONE;
        return;
    }
    ctx.hold = reduce.ap(ctx.heap, ctx.args[0], lastarg(ctx));
    ctx.hold = try reduce.reduce(ctx.hold);
    if (ctx.hold != word.NIL) {
        reduce.rewriteToValue(ctx.heap, &ctx.e, ctx.hold);
        ctx.action = word.ACT_DONE;
        return;
    }
    reduce.hdSet(ctx.heap, ctx.e, ctx.args[1]);
    reduce.downLeft(ctx);
    ctx.action = word.ACT_NEXTREDEX;
}

/// `G_OPT`: optional — match `arg0` once, or succeed consuming nothing.
pub fn handle_G_OPT(ctx: *ReductionCtx) reduce.ReduceError!void {
    reduce.GETARG(ctx, &ctx.args[0]);
    if (reduce.upleft(ctx)) {
        ctx.action = word.ACT_DONE;
        return;
    }
    ctx.hold = reduce.ap(ctx.heap, ctx.args[0], lastarg(ctx));
    ctx.hold = try reduce.reduce(ctx.hold);
    if (ctx.hold == word.NIL) {
        reduce.rewriteToCons(ctx.heap, ctx.e, word.NIL, lastarg(ctx));
    } else {
        reduce.rewriteToCons(ctx.heap, ctx.e, reduce.cons(ctx.heap, reduce.hdGet(ctx.heap, ctx.hold), word.NIL), reduce.tlGet(ctx.heap, ctx.hold));
    }
    ctx.action = word.ACT_DONE;
}

/// `G_STAR`: zero-or-more repetition of `arg0`, collecting results into a list.
pub fn handle_G_STAR(ctx: *ReductionCtx) reduce.ReduceError!void {
    reduce.GETARG(ctx, &ctx.args[0]);
    if (reduce.upleft(ctx)) {
        ctx.action = word.ACT_DONE;
        return;
    }
    ctx.hold = reduce.ap(ctx.heap, ctx.args[0], lastarg(ctx));
    ctx.hold = try reduce.reduce(ctx.hold);
    if (ctx.hold == word.NIL) {
        reduce.rewriteToCons(ctx.heap, ctx.e, word.NIL, lastarg(ctx));
        ctx.action = word.ACT_DONE;
        return;
    }
    ctx.args[1] = reduce.ap(ctx.heap, reduce.hdGet(ctx.heap, ctx.e), reduce.tlGet(ctx.heap, ctx.hold));
    reduce.setTag(ctx.heap, ctx.e, .CONS);
    reduce.hdSet(ctx.heap, ctx.e, reduce.cons(ctx.heap, reduce.hdGet(ctx.heap, ctx.hold), reduce.ap(ctx.heap, word.HD, ctx.args[1])));
    reduce.tlSet(ctx.heap, ctx.e, reduce.ap(ctx.heap, word.TL, ctx.args[1]));
    ctx.action = word.ACT_DONE;
}

/// `G_FBSTAR`: fail-back star — greedy repetition composed into a continuation.
pub fn handle_G_FBSTAR(ctx: *ReductionCtx) reduce.ReduceError!void {
    reduce.GETARG(ctx, &ctx.args[0]);
    if (reduce.upleft(ctx)) {
        ctx.action = word.ACT_DONE;
        return;
    }
    ctx.hold = reduce.ap(ctx.heap, ctx.args[0], lastarg(ctx));
    ctx.hold = try reduce.reduce(ctx.hold);
    if (ctx.hold == word.NIL) {
        reduce.rewriteToCons(ctx.heap, ctx.e, word.I, lastarg(ctx));
        ctx.action = word.ACT_DONE;
        return;
    }
    reduce.hdSet(ctx.heap, ctx.e, reduce.ap2(ctx.heap, word.G_SEQ, reduce.hdGet(ctx.heap, ctx.e), reduce.ap(ctx.heap, word.G_RULE, reduce.ap(ctx.heap, word.CB, reduce.hdGet(ctx.heap, ctx.hold)))));
    reduce.tlSet(ctx.heap, ctx.e, reduce.tlGet(ctx.heap, ctx.hold));
    ctx.action = word.ACT_NEXTREDEX;
}

/// `G_SYMB`: match a specific terminal symbol at the head of the input.
pub fn handle_G_SYMB(ctx: *ReductionCtx) reduce.ReduceError!void {
    reduce.GETARG(ctx, &ctx.args[0]);
    if (reduce.upleft(ctx)) {
        ctx.action = word.ACT_DONE;
        return;
    }
    const lastarg_reduced = try reduce.reduce(lastarg(ctx));
    setLastarg(ctx, lastarg_reduced);
    if (lastarg_reduced == word.NIL) {
        reduce.rewriteToNil(ctx.heap, &ctx.e);
        ctx.action = word.ACT_DONE;
        return;
    }
    reduce.hdSet(ctx.heap, lastarg_reduced, try reduce.reduce(reduce.hdGet(ctx.heap, lastarg_reduced)));
    ctx.hold = reduce.ap(ctx.heap, word.HD, reduce.hdGet(ctx.heap, lastarg_reduced));
    if (try reduce_rt.compare(ctx.args[0], try reduce.reduce(ctx.hold)) != 0) {
        reduce.rewriteToValue(ctx.heap, &ctx.e, word.NIL); // rewriteToFailure in C is NIL
    } else {
        reduce.rewriteToCons(ctx.heap, ctx.e, ctx.args[0], reduce.tlGet(ctx.heap, lastarg_reduced));
    }
    ctx.action = word.ACT_DONE;
}

/// `G_ANY`: match any single terminal, yielding it.
pub fn handle_G_ANY(ctx: *ReductionCtx) reduce.ReduceError!void {
    if (reduce.upleft(ctx)) {
        ctx.action = word.ACT_DONE;
        return;
    }
    const lastarg_reduced = try reduce.reduce(lastarg(ctx));
    setLastarg(ctx, lastarg_reduced);
    if (lastarg_reduced == word.NIL) {
        reduce.rewriteToValue(ctx.heap, &ctx.e, word.NIL);
    } else {
        reduce.rewriteToCons(ctx.heap, ctx.e, reduce.ap(ctx.heap, word.HD, reduce.hdGet(ctx.heap, lastarg_reduced)), reduce.tlGet(ctx.heap, lastarg_reduced));
    }
    ctx.action = word.ACT_DONE;
}

/// `G_SUCHTHAT`: match the next terminal only if it satisfies predicate `arg0` (a guard).
pub fn handle_G_SUCHTHAT(ctx: *ReductionCtx) reduce.ReduceError!void {
    reduce.GETARG(ctx, &ctx.args[0]);
    if (reduce.upleft(ctx)) {
        ctx.action = word.ACT_DONE;
        return;
    }
    const lastarg_reduced = try reduce.reduce(lastarg(ctx));
    setLastarg(ctx, lastarg_reduced);
    if (lastarg_reduced == word.NIL) {
        reduce.rewriteToValue(ctx.heap, &ctx.e, word.NIL);
        ctx.action = word.ACT_DONE;
        return;
    }
    ctx.hold = reduce.ap(ctx.heap, word.HD, reduce.hdGet(ctx.heap, lastarg_reduced));
    ctx.hold = try reduce.reduce(ctx.hold);
    if (try reduce.reduce(reduce.ap(ctx.heap, ctx.args[0], ctx.hold)) == word.True) {
        reduce.rewriteToCons(ctx.heap, ctx.e, ctx.hold, reduce.tlGet(ctx.heap, lastarg_reduced));
    } else {
        reduce.rewriteToValue(ctx.heap, &ctx.e, word.NIL);
    }
    ctx.action = word.ACT_DONE;
}

/// `G_END`: succeed only at end of input.
pub fn handle_G_END(ctx: *ReductionCtx) reduce.ReduceError!void {
    if (reduce.upleft(ctx)) {
        ctx.action = word.ACT_DONE;
        return;
    }
    const lastarg_reduced = try reduce.reduce(lastarg(ctx));
    setLastarg(ctx, lastarg_reduced);
    if (lastarg_reduced == word.NIL) {
        reduce.rewriteToCons(ctx.heap, ctx.e, word.NIL, word.NIL);
    } else {
        reduce.rewriteToValue(ctx.heap, &ctx.e, word.NIL);
    }
    ctx.action = word.ACT_DONE;
}

/// `G_STATE`: yield the current lexer state without consuming input.
pub fn handle_G_STATE(ctx: *ReductionCtx) reduce.ReduceError!void {
    if (reduce.upleft(ctx)) {
        ctx.action = word.ACT_DONE;
        return;
    }
    const lastarg_reduced = try reduce.reduce(lastarg(ctx));
    setLastarg(ctx, lastarg_reduced);
    if (lastarg_reduced == word.NIL) {
        reduce.rewriteToValue(ctx.heap, &ctx.e, word.NIL);
    } else {
        reduce.rewriteToCons(ctx.heap, ctx.e, reduce.ap(ctx.heap, word.TL, reduce.hdGet(ctx.heap, lastarg_reduced)), lastarg_reduced);
    }
    ctx.action = word.ACT_DONE;
}

/// `G_SEQ`: sequence — match `arg0` then `arg1`, applying the first result to the second.
pub fn handle_G_SEQ(ctx: *ReductionCtx) reduce.ReduceError!void {
    reduce.GETARG(ctx, &ctx.args[0]);
    reduce.GETARG(ctx, &ctx.args[1]);
    if (reduce.upleft(ctx)) {
        ctx.action = word.ACT_DONE;
        return;
    }
    ctx.hold = reduce.ap(ctx.heap, ctx.args[0], lastarg(ctx));
    ctx.hold = try reduce.reduce(ctx.hold);
    if (ctx.hold == word.NIL) {
        reduce.rewriteToValue(ctx.heap, &ctx.e, word.NIL);
        ctx.action = word.ACT_DONE;
        return;
    }
    ctx.args[2] = reduce.ap(ctx.heap, ctx.args[1], reduce.tlGet(ctx.heap, ctx.hold));
    ctx.args[2] = try reduce.reduce(ctx.args[2]);
    if (ctx.args[2] == word.NIL) {
        reduce.rewriteToValue(ctx.heap, &ctx.e, word.NIL);
        ctx.action = word.ACT_DONE;
        return;
    }
    reduce.rewriteToCons(ctx.heap, ctx.e, reduce.ap(ctx.heap, reduce.hdGet(ctx.heap, ctx.args[2]), reduce.hdGet(ctx.heap, ctx.hold)), reduce.tlGet(ctx.heap, ctx.args[2]));
    ctx.action = word.ACT_DONE;
}

/// `G_UNIT`: the epsilon grammar — succeed consuming nothing, yielding the identity result.
pub fn handle_G_UNIT(ctx: *ReductionCtx) void {
    if (reduce.upleft(ctx)) {
        ctx.action = word.ACT_DONE;
        return;
    }
    reduce.rewriteToConsHead(ctx.heap, ctx.e, word.I);
    ctx.action = word.ACT_DONE;
}

/// `G_ZERO`: the grammar that always fails.
pub fn handle_G_ZERO(ctx: *ReductionCtx) void {
    if (reduce.upleft(ctx)) {
        ctx.action = word.ACT_DONE;
        return;
    }
    reduce.rewriteToValue(ctx.heap, &ctx.e, word.NIL);
    ctx.action = word.ACT_DONE;
}

/// `G_CLOSE`: run grammar `arg1` over the position-tagged input, raising a parse error (`arg0`) on failure.
pub fn handle_G_CLOSE(ctx: *ReductionCtx) reduce.ReduceError!void {
    reduce.GETARG(ctx, &ctx.args[0]);
    reduce.GETARG(ctx, &ctx.args[1]);
    if (reduce.upleft(ctx)) {
        ctx.action = word.ACT_DONE;
        return;
    }
    ctx.args[2] = reduce.ap(ctx.heap, word.G_COUNT, lastarg(ctx));
    ctx.hold = reduce.ap(ctx.heap, ctx.args[1], ctx.args[2]);
    ctx.hold = try reduce.reduce(ctx.hold);
    if (ctx.hold == word.NIL) {
        try reduce_rt.parseCloseError(ctx.args[0], ctx.args[2]);
    }
    reduce.rewriteToValue(ctx.heap, &ctx.e, reduce.hdGet(ctx.heap, ctx.hold));
    ctx.action = word.ACT_NEXTREDEX;
}

/// `G_COUNT`: tag each remaining token with its position (for parse-error reporting).
pub fn handle_G_COUNT(ctx: *ReductionCtx) reduce.ReduceError!void {
    if (reduce.upleft(ctx)) {
        ctx.action = word.ACT_DONE;
        return;
    }
    const lastarg_reduced = try reduce.reduce(lastarg(ctx));
    setLastarg(ctx, lastarg_reduced);
    if (lastarg_reduced == word.NIL) {
        reduce.rewriteToNil(ctx.heap, &ctx.e);
        ctx.action = word.ACT_DONE;
        return;
    }
    reduce.rewriteToCons(ctx.heap, ctx.e, reduce.hdGet(ctx.heap, lastarg_reduced), reduce.ap(ctx.heap, word.G_COUNT, reduce.tlGet(ctx.heap, lastarg_reduced)));
    ctx.action = word.ACT_DONE;
}

/// `LEX_RPT1`: one-or-more repetition of a lexer rule.
pub fn handle_LEX_RPT1(ctx: *ReductionCtx) void {
    reduce.GETARG(ctx, &ctx.args[0]);
    reduce.upLeft(ctx);
    reduce.hdSet(ctx.heap, ctx.e, reduce.ap(ctx.heap, word.B, reduce.ap2(ctx.heap, word.LEX_RPT, ctx.args[0], lastarg(ctx))));
    reduce.tlSet(ctx.heap, ctx.e, word.LEX_COUNT0);
    reduce.downLeft(ctx);
    reduce.downLeft(ctx);
    ctx.action = word.ACT_NEXTREDEX;
}

/// `LEX_RPT`: zero-or-more repetition of a lexer rule.
pub fn handle_LEX_RPT(ctx: *ReductionCtx) reduce.ReduceError!void {
    reduce.GETARG(ctx, &ctx.args[0]);
    reduce.GETARG(ctx, &ctx.args[1]);
    if (reduce.upleft(ctx)) {
        ctx.action = word.ACT_DONE;
        return;
    }
    const lastarg_reduced = try reduce.reduce(lastarg(ctx));
    setLastarg(ctx, lastarg_reduced);
    if (lastarg_reduced == word.NIL) {
        reduce.rewriteToNil(ctx.heap, &ctx.e);
        ctx.action = word.ACT_DONE;
        return;
    }
    ctx.hold = reduce.ap2(ctx.heap, ctx.args[0], ctx.args[1], lastarg_reduced);
    ctx.args[0] = reduce.hdGet(ctx.heap, reduce.hdGet(ctx.heap, ctx.e));
    ctx.hold = try reduce.reduce(ctx.hold);
    reduce.rewriteToCons(ctx.heap, ctx.e, reduce.hdGet(ctx.heap, ctx.hold), reduce.ap2(ctx.heap, ctx.args[0], reduce.hdGet(ctx.heap, reduce.tlGet(ctx.heap, ctx.hold)), reduce.tlGet(ctx.heap, reduce.tlGet(ctx.heap, ctx.hold))));
    ctx.action = word.ACT_DONE;
}

/// `LEX_TRY`: attempt a lexer rule, set up to backtrack on failure.
pub fn handle_LEX_TRY(ctx: *ReductionCtx) reduce.ReduceError!void {
    if (reduce.upleft(ctx)) {
        ctx.action = word.ACT_DONE;
        return;
    }
    reduce.tlSet(ctx.heap, ctx.e, try reduce.reduce(reduce.tlGet(ctx.heap, ctx.e)));
    try reduce.force(reduce.tlGet(ctx.heap, ctx.e));
    reduce.hdSet(ctx.heap, ctx.e, word.LEX_TRY_);
    reduce.downLeft(ctx);
    ctx.action = word.ACT_NEXTREDEX;
}

/// `LEX_TRY` continuation: resume the backtracking attempt with the matched prefix.
pub fn handle_LEX_TRY_(ctx: *ReductionCtx) reduce.ReduceError!void {
    reduce.GETARG(ctx, &ctx.args[0]);
    reduce.GETARG(ctx, &ctx.args[1]);
    if (reduce.upleft(ctx)) {
        ctx.action = word.ACT_DONE;
        return;
    }
    while (true) {
        if (ctx.args[0] == word.NIL) {
            reduce_rt.lexfail(lastarg(ctx));
        }
        const hd_hd_hd_arg1 = reduce.hdGet(ctx.heap, reduce.hdGet(ctx.heap, reduce.hdGet(ctx.heap, ctx.args[0])));
        if (hd_hd_hd_arg1 != 0 and types.member(ctx.heap, hd_hd_hd_arg1, ctx.args[1]) == 0) {
            ctx.args[0] = reduce.tlGet(ctx.heap, ctx.args[0]);
            continue;
        }
        ctx.hold = reduce.ap(ctx.heap, reduce.hdGet(ctx.heap, reduce.tlGet(ctx.heap, reduce.hdGet(ctx.heap, ctx.args[0]))), lastarg(ctx));
        ctx.hold = try reduce.reduce(ctx.hold);
        if (ctx.hold == word.NIL) {
            ctx.args[0] = reduce.tlGet(ctx.heap, ctx.args[0]);
            continue;
        }
        const tl_hd_hd_arg1 = reduce.tlGet(ctx.heap, reduce.hdGet(ctx.heap, reduce.hdGet(ctx.heap, ctx.args[0])));
        reduce.rewriteToCons(ctx.heap, ctx.e, reduce.ap(ctx.heap, reduce.tlGet(ctx.heap, reduce.tlGet(ctx.heap, reduce.hdGet(ctx.heap, ctx.args[0]))), reduce.ap(ctx.heap, word.DESTREV, reduce.hdGet(ctx.heap, ctx.hold))), reduce.cons(ctx.heap, if (tl_hd_hd_arg1 != 0) tl_hd_hd_arg1 - 1 else ctx.args[1], reduce.tlGet(ctx.heap, ctx.hold)));
        ctx.action = word.ACT_DONE;
        return;
    }
}

/// `LEX_TRY1`: single-result backtracking attempt of a lexer rule.
pub fn handle_LEX_TRY1(ctx: *ReductionCtx) reduce.ReduceError!void {
    if (reduce.upleft(ctx)) {
        ctx.action = word.ACT_DONE;
        return;
    }
    reduce.tlSet(ctx.heap, ctx.e, try reduce.reduce(reduce.tlGet(ctx.heap, ctx.e)));
    try reduce.force(reduce.tlGet(ctx.heap, ctx.e));
    reduce.hdSet(ctx.heap, ctx.e, word.LEX_TRY1_);
    reduce.downLeft(ctx);
    ctx.action = word.ACT_NEXTREDEX;
}

/// `LEX_TRY1` continuation: resume the single-result attempt.
pub fn handle_LEX_TRY1_(ctx: *ReductionCtx) reduce.ReduceError!void {
    reduce.GETARG(ctx, &ctx.args[0]);
    reduce.GETARG(ctx, &ctx.args[1]);
    if (reduce.upleft(ctx)) {
        ctx.action = word.ACT_DONE;
        return;
    }
    while (true) {
        if (ctx.args[0] == word.NIL) {
            reduce_rt.lexfail(lastarg(ctx));
        }
        const hd_hd_hd_arg1 = reduce.hdGet(ctx.heap, reduce.hdGet(ctx.heap, reduce.hdGet(ctx.heap, ctx.args[0])));
        if (hd_hd_hd_arg1 != 0 and types.member(ctx.heap, hd_hd_hd_arg1, ctx.args[1]) == 0) {
            ctx.args[0] = reduce.tlGet(ctx.heap, ctx.args[0]);
            continue;
        }
        ctx.hold = reduce.ap(ctx.heap, reduce.hdGet(ctx.heap, reduce.tlGet(ctx.heap, reduce.hdGet(ctx.heap, ctx.args[0]))), lastarg(ctx));
        ctx.hold = try reduce.reduce(ctx.hold);
        if (ctx.hold == word.NIL) {
            ctx.args[0] = reduce.tlGet(ctx.heap, ctx.args[0]);
            continue;
        }
        const tl_hd_hd_arg1 = reduce.tlGet(ctx.heap, reduce.hdGet(ctx.heap, reduce.hdGet(ctx.heap, ctx.args[0])));
        reduce.rewriteToCons(ctx.heap, ctx.e, reduce.ap2(ctx.heap, reduce.tlGet(ctx.heap, reduce.tlGet(ctx.heap, reduce.hdGet(ctx.heap, ctx.args[0]))), reduce_rt.lexstate(lastarg(ctx)), reduce.ap(ctx.heap, word.DESTREV, reduce.hdGet(ctx.heap, ctx.hold))), reduce.cons(ctx.heap, if (tl_hd_hd_arg1 != 0) tl_hd_hd_arg1 - 1 else ctx.args[1], reduce.tlGet(ctx.heap, ctx.hold)));
        ctx.action = word.ACT_DONE;
        return;
    }
}

/// `DESTREV`: destructively reverse the accumulated result list.
pub fn handle_DESTREV(ctx: *ReductionCtx) void {
    reduce.GETARG(ctx, &ctx.args[0]);
    ctx.args[1] = word.NIL;
    while (ctx.args[0] != word.NIL) {
        if (reduce.isStrcons(ctx.heap, reduce.hdGet(ctx.heap, ctx.args[0]))) {
            reduce.hdSet(ctx.heap, ctx.args[0], reduce.tlGet(ctx.heap, reduce.hdGet(ctx.heap, ctx.args[0])));
        }
        ctx.hold = reduce.tlGet(ctx.heap, ctx.args[0]);
        reduce.tlSet(ctx.heap, ctx.args[0], ctx.args[1]);
        ctx.args[1] = ctx.args[0];
        ctx.args[0] = ctx.hold;
    }
    reduce.rewriteToValue(ctx.heap, &ctx.e, ctx.args[1]);
    ctx.action = word.ACT_DONE;
}

/// `LEX_COUNT0`: begin counting matched input (from position 0).
pub fn handle_LEX_COUNT0(ctx: *ReductionCtx) void {
    if (reduce.upleft(ctx)) {
        ctx.action = word.ACT_DONE;
        return;
    }
    reduce.hdSet(ctx.heap, ctx.e, word.LEX_COUNT);
    reduce.tlSet(ctx.heap, ctx.e, os.strcons(0, reduce.tlGet(ctx.heap, ctx.e)));
    reduce.downLeft(ctx);
    ctx.action = word.ACT_NEXTREDEX;
}

/// `LEX_COUNT`: advance the match counter as input is consumed.
pub fn handle_LEX_COUNT(ctx: *ReductionCtx) reduce.ReduceError!void {
    reduce.GETARG(ctx, &ctx.args[0]);
    const next_tl = try reduce.reduce(reduce.tlGet(ctx.heap, ctx.args[0]));
    reduce.tlSet(ctx.heap, ctx.args[0], next_tl);
    if (next_tl == word.NIL) {
        reduce.rewriteToNil(ctx.heap, &ctx.e);
        ctx.action = word.ACT_DONE;
        return;
    }
    ctx.hold = reduce.hdGet(ctx.heap, next_tl);
    reduce.rewriteToCons(ctx.heap, ctx.e, os.strcons(reduce.hdGet(ctx.heap, ctx.args[0]), ctx.hold), reduce.ap(ctx.heap, word.LEX_COUNT, ctx.args[0]));
    if (ctx.hold == '\n') {
        reduce.hdSet(ctx.heap, ctx.args[0], ((reduce.hdGet(ctx.heap, ctx.args[0]) >> 8) + 1) << 8);
    } else {
        var col = reduce.hdGet(ctx.heap, ctx.args[0]) & 255;
        col = if (ctx.hold == '\t') ((@divTrunc(col, 8)) + 1) * 8 else col + 1;
        reduce.hdSet(ctx.heap, ctx.args[0], (reduce.hdGet(ctx.heap, ctx.args[0]) & (~@as(Word, 255))) | col);
    }
    reduce.tlSet(ctx.heap, ctx.args[0], reduce.tlGet(ctx.heap, next_tl));
    ctx.action = word.ACT_DONE;
}

/// `LEX_STRING`: match a literal string at the head of the input.
pub fn handle_LEX_STRING(ctx: *ReductionCtx) reduce.ReduceError!void {
    reduce.GETARG(ctx, &ctx.args[0]);
    reduce.GETARG(ctx, &ctx.args[1]);
    if (reduce.upleft(ctx)) {
        ctx.action = word.ACT_DONE;
        return;
    }
    while (ctx.args[0] != word.NIL) {
        const lastarg_reduced = try reduce.reduce(lastarg(ctx));
        setLastarg(ctx, lastarg_reduced);
        if (lastarg_reduced == word.NIL or lh(ctx.heap, lastarg_reduced) != reduce.hdGet(ctx.heap, ctx.args[0])) {
            reduce.rewriteToNil(ctx.heap, &ctx.e);
            ctx.action = word.ACT_DONE;
            return;
        }
        ctx.args[0] = reduce.tlGet(ctx.heap, ctx.args[0]);
        ctx.args[1] = reduce.cons(ctx.heap, reduce.hdGet(ctx.heap, lastarg_reduced), ctx.args[1]);
        setLastarg(ctx, reduce.tlGet(ctx.heap, lastarg_reduced));
    }
    reduce.rewriteToConsHead(ctx.heap, ctx.e, ctx.args[1]);
    ctx.action = word.ACT_DONE;
}

/// `LEX_CLASS`: match a character belonging to a character class.
pub fn handle_LEX_CLASS(ctx: *ReductionCtx) reduce.ReduceError!void {
    reduce.GETARG(ctx, &ctx.args[0]);
    reduce.GETARG(ctx, &ctx.args[1]);
    if (reduce.upleft(ctx)) {
        ctx.action = word.ACT_DONE;
        return;
    }
    const lastarg_reduced = try reduce.reduce(lastarg(ctx));
    setLastarg(ctx, lastarg_reduced);
    if (lastarg_reduced == word.NIL or
        (if (reduce.hdGet(ctx.heap, ctx.args[0]) == word.ANTICHARCLASS)
            reduce_rt.memclass(@intCast(lh(ctx.heap, lastarg_reduced)), reduce.tlGet(ctx.heap, ctx.args[0])) != 0
        else
            reduce_rt.memclass(@intCast(lh(ctx.heap, lastarg_reduced)), ctx.args[0]) == 0))
    {
        reduce.rewriteToNil(ctx.heap, &ctx.e);
        ctx.action = word.ACT_DONE;
        return;
    }
    reduce.rewriteToCons(ctx.heap, ctx.e, reduce.cons(ctx.heap, reduce.hdGet(ctx.heap, lastarg_reduced), ctx.args[1]), reduce.tlGet(ctx.heap, lastarg_reduced));
    ctx.action = word.ACT_DONE;
}

/// `LEX_DOT`: match any single character.
pub fn handle_LEX_DOT(ctx: *ReductionCtx) reduce.ReduceError!void {
    reduce.GETARG(ctx, &ctx.args[0]);
    if (reduce.upleft(ctx)) {
        ctx.action = word.ACT_DONE;
        return;
    }
    const lastarg_reduced = try reduce.reduce(lastarg(ctx));
    setLastarg(ctx, lastarg_reduced);
    if (lastarg_reduced == word.NIL) {
        reduce.rewriteToNil(ctx.heap, &ctx.e);
        ctx.action = word.ACT_DONE;
        return;
    }
    reduce.rewriteToCons(ctx.heap, ctx.e, reduce.cons(ctx.heap, reduce.hdGet(ctx.heap, lastarg_reduced), ctx.args[0]), reduce.tlGet(ctx.heap, lastarg_reduced));
    ctx.action = word.ACT_DONE;
}

/// `LEX_CHAR`: match a specific character.
pub fn handle_LEX_CHAR(ctx: *ReductionCtx) reduce.ReduceError!void {
    reduce.GETARG(ctx, &ctx.args[0]);
    reduce.GETARG(ctx, &ctx.args[1]);
    if (reduce.upleft(ctx)) {
        ctx.action = word.ACT_DONE;
        return;
    }
    const lastarg_reduced = try reduce.reduce(lastarg(ctx));
    setLastarg(ctx, lastarg_reduced);
    if (lastarg_reduced == word.NIL or lh(ctx.heap, lastarg_reduced) != ctx.args[0]) {
        reduce.rewriteToNil(ctx.heap, &ctx.e);
        ctx.action = word.ACT_DONE;
        return;
    }
    reduce.rewriteToCons(ctx.heap, ctx.e, reduce.cons(ctx.heap, ctx.args[0], ctx.args[1]), reduce.tlGet(ctx.heap, lastarg_reduced));
    ctx.action = word.ACT_DONE;
}

/// `LEX_SEQ`: sequence two lexer rules.
pub fn handle_LEX_SEQ(ctx: *ReductionCtx) reduce.ReduceError!void {
    reduce.GETARG(ctx, &ctx.args[0]);
    reduce.GETARG(ctx, &ctx.args[1]);
    reduce.GETARG(ctx, &ctx.args[2]);
    if (reduce.upleft(ctx)) {
        ctx.action = word.ACT_DONE;
        return;
    }
    ctx.hold = reduce.ap2(ctx.heap, ctx.args[0], ctx.args[2], lastarg(ctx));
    setLastarg(ctx, word.NIL);
    ctx.hold = try reduce.reduce(ctx.hold);
    if (ctx.hold == word.NIL) {
        ctx.e = reduce.rewriteToExistingTail(ctx.heap, ctx.e);
        ctx.action = word.ACT_DONE;
        return;
    }
    reduce.hdSet(ctx.heap, ctx.e, reduce.ap(ctx.heap, ctx.args[1], reduce.hdGet(ctx.heap, ctx.hold)));
    reduce.tlSet(ctx.heap, ctx.e, reduce.tlGet(ctx.heap, ctx.hold));
    reduce.downLeft(ctx);
    reduce.downLeft(ctx);
    ctx.action = word.ACT_NEXTREDEX;
}

/// `LEX_OR`: ordered alternation of two lexer rules.
pub fn handle_LEX_OR(ctx: *ReductionCtx) reduce.ReduceError!void {
    reduce.GETARG(ctx, &ctx.args[0]);
    reduce.GETARG(ctx, &ctx.args[1]);
    reduce.GETARG(ctx, &ctx.args[2]);
    if (reduce.upleft(ctx)) {
        ctx.action = word.ACT_DONE;
        return;
    }
    ctx.hold = reduce.ap2(ctx.heap, ctx.args[0], ctx.args[2], lastarg(ctx));
    ctx.hold = try reduce.reduce(ctx.hold);
    if (ctx.hold == word.NIL) {
        reduce.hdSet(ctx.heap, ctx.e, reduce.ap(ctx.heap, ctx.args[1], ctx.args[2]));
        reduce.downLeft(ctx);
        reduce.downLeft(ctx);
        ctx.action = word.ACT_NEXTREDEX;
        return;
    }
    reduce.rewriteToValue(ctx.heap, &ctx.e, ctx.hold);
    ctx.action = word.ACT_DONE;
}

/// `LEX_RCONTEXT`: right-context lookahead — match only if followed by the context pattern.
pub fn handle_LEX_RCONTEXT(ctx: *ReductionCtx) reduce.ReduceError!void {
    reduce.GETARG(ctx, &ctx.args[0]);
    reduce.GETARG(ctx, &ctx.args[1]);
    reduce.GETARG(ctx, &ctx.args[2]);
    if (reduce.upleft(ctx)) {
        ctx.action = word.ACT_DONE;
        return;
    }
    ctx.hold = reduce.ap2(ctx.heap, ctx.args[0], ctx.args[2], lastarg(ctx));
    setLastarg(ctx, word.NIL);
    ctx.hold = try reduce.reduce(ctx.hold);
    if (ctx.hold == word.NIL or
        (if (ctx.args[1] != 0)
            try reduce.reduce(reduce.ap2(ctx.heap, ctx.args[1], reduce.hdGet(ctx.heap, ctx.hold), reduce.tlGet(ctx.heap, ctx.hold))) == word.NIL
        else blk: {
            const next_tl = try reduce.reduce(reduce.tlGet(ctx.heap, ctx.hold));
            reduce.tlSet(ctx.heap, ctx.hold, next_tl);
            break :blk next_tl != word.NIL;
        }))
    {
        ctx.e = reduce.rewriteToExistingTail(ctx.heap, ctx.e);
        ctx.action = word.ACT_DONE;
        return;
    }
    reduce.rewriteToValue(ctx.heap, &ctx.e, ctx.hold);
    ctx.action = word.ACT_DONE;
}

/// `LEX_STAR`: greedy zero-or-more of a lexer rule.
pub fn handle_LEX_STAR(ctx: *ReductionCtx) reduce.ReduceError!void {
    reduce.GETARG(ctx, &ctx.args[0]);
    reduce.GETARG(ctx, &ctx.args[1]);
    if (reduce.upleft(ctx)) {
        ctx.action = word.ACT_DONE;
        return;
    }
    ctx.hold = reduce.ap2(ctx.heap, ctx.args[0], ctx.args[1], lastarg(ctx));
    while (true) {
        const next_hold = try reduce.reduce(ctx.hold);
        if (next_hold == word.NIL) break;
        ctx.args[1] = reduce.hdGet(ctx.heap, next_hold);
        setLastarg(ctx, reduce.tlGet(ctx.heap, next_hold));
        ctx.hold = reduce.ap2(ctx.heap, ctx.args[0], ctx.args[1], lastarg(ctx));
    }
    reduce.rewriteToConsHead(ctx.heap, ctx.e, ctx.args[1]);
    ctx.action = word.ACT_DONE;
}

/// `LEX_OPT`: optional lexer rule (match once, or skip).
pub fn handle_LEX_OPT(ctx: *ReductionCtx) reduce.ReduceError!void {
    reduce.GETARG(ctx, &ctx.args[0]);
    reduce.GETARG(ctx, &ctx.args[1]);
    if (reduce.upleft(ctx)) {
        ctx.action = word.ACT_DONE;
        return;
    }
    ctx.hold = reduce.ap2(ctx.heap, ctx.args[0], ctx.args[1], lastarg(ctx));
    ctx.hold = try reduce.reduce(ctx.hold);
    if (ctx.hold == word.NIL) {
        reduce.rewriteToConsHead(ctx.heap, ctx.e, ctx.args[1]);
        ctx.action = word.ACT_DONE;
        return;
    }
    reduce.rewriteToValue(ctx.heap, &ctx.e, ctx.hold);
    ctx.action = word.ACT_DONE;
}
