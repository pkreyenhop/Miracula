#include <stdlib.h>
#include <stdio.h>
#include "reduce_internal.h"
#include "data.h"
#include "lex.h"
#include "combs.h"

// Define local macro mapping for context registers
#define e (ctx->e)
#define s (ctx->s)
#define hold (ctx->hold)
#define arg1 (ctx->args[0])
#define arg2 (ctx->args[1])
#define arg3 (ctx->args[2])
#define arg4 (ctx->args[3])

#define DOWNLEFT ctx_down_left(ctx)
#define DOWNRIGHT ctx_down_right(ctx)
#define downright                                                                                  \
  if (ctx_downright(ctx)) {                                                                        \
    ctx->action = ACT_DONE;                                                                        \
    return;                                                                                        \
  }
#define UPLEFT ctx_up_left(ctx)
#define upleft                                                                                     \
  if (ctx_upleft(ctx)) {                                                                           \
    ctx->action = ACT_DONE;                                                                        \
    return;                                                                                        \
  }
#define GETARG(a) ctx_GETARG(ctx, &(a))
#define getarg(a)                                                                                  \
  if (ctx_getarg(ctx, &(a))) {                                                                     \
    ctx->action = ACT_DONE;                                                                        \
    return;                                                                                        \
  }
#define UPRIGHT ctx_up_right(ctx)
#define lastarg tl(e)

#define setcell(t, a, b) tag[e] = t, hd(e) = a, tl(e) = b
#define simpl(r) hd(e) = I, e = tl(e) = r
#define FST HD
#define SND TL

// External declarations are imported via reduce_internal.h

void handle_G_ERROR(ReductionCtx *ctx) {
  GETARG(arg1);
  GETARG(arg2);
  upleft;
  hold = ap(arg1, lastarg);
  hold = reduce(hold);
  if (!fails(hold)) {
    rewrite_to_value(&e, hold);
    ctx->action = ACT_DONE;
    return;
  }
  hold = g_residue(lastarg);
  setcell(CONS, ap(arg2, hold), NIL);
  ctx->action = ACT_DONE;
}

void handle_G_ALT(ReductionCtx *ctx) {
  GETARG(arg1);
  GETARG(arg2);
  upleft;
  hold = ap(arg1, lastarg);
  hold = reduce(hold);
  if (!fails(hold)) {
    rewrite_to_value(&e, hold);
    ctx->action = ACT_DONE;
    return;
  }
  hd(e) = arg2;
  DOWNLEFT;
  ctx->action = ACT_NEXTREDEX;
}

void handle_G_OPT(ReductionCtx *ctx) {
  GETARG(arg1);
  upleft;
  hold = ap(arg1, lastarg);
  hold = reduce(hold);
  if (fails(hold)) {
    rewrite_to_cons(e, NIL, lastarg);
  } else {
    setcell(CONS, cons(hd(hold), NIL), tl(hold));
  }
  ctx->action = ACT_DONE;
}

void handle_G_STAR(ReductionCtx *ctx) {
  GETARG(arg1);
  upleft;
  hold = ap(arg1, lastarg);
  hold = reduce(hold);
  if (fails(hold)) {
    rewrite_to_cons(e, NIL, lastarg);
    ctx->action = ACT_DONE;
    return;
  }
  arg2 = ap(hd(e), tl(hold));
  tag[e] = CONS;
  hd(e) = cons(hd(hold), ap(FST, arg2));
  tl(e) = ap(SND, arg2);
  ctx->action = ACT_DONE;
}

void handle_G_FBSTAR(ReductionCtx *ctx) {
  GETARG(arg1);
  upleft;
  hold = ap(arg1, lastarg);
  hold = reduce(hold);
  if (fails(hold)) {
    rewrite_to_cons(e, I, lastarg);
    ctx->action = ACT_DONE;
    return;
  }
  hd(e) = ap2(G_SEQ, hd(e), ap(G_RULE, ap(CB, hd(hold))));
  tl(e) = tl(hold);
  ctx->action = ACT_NEXTREDEX;
}

void handle_G_SYMB(ReductionCtx *ctx) {
  GETARG(arg1);
  upleft;
  lastarg = reduce(lastarg);
  if (lastarg == NIL) {
    rewrite_to_nil(&e);
    ctx->action = ACT_DONE;
    return;
  }
  hd(lastarg) = reduce(hd(lastarg));
  hold = ap(FST, hd(lastarg));
  if (compare(arg1, reduce(hold))) {
    rewrite_to_failure(&e);
  } else {
    setcell(CONS, arg1, tl(lastarg));
  }
  ctx->action = ACT_DONE;
}

void handle_G_ANY(ReductionCtx *ctx) {
  upleft;
  lastarg = reduce(lastarg);
  if (lastarg == NIL) {
    rewrite_to_failure(&e);
  } else {
    setcell(CONS, ap(FST, hd(lastarg)), tl(lastarg));
  }
  ctx->action = ACT_DONE;
}

void handle_G_SUCHTHAT(ReductionCtx *ctx) {
  GETARG(arg1);
  upleft;
  lastarg = reduce(lastarg);
  if (lastarg == NIL) {
    rewrite_to_failure(&e);
    ctx->action = ACT_DONE;
    return;
  }
  hold = ap(FST, hd(lastarg));
  hold = reduce(hold);
  if (reduce(ap(arg1, hold)) == True) {
    setcell(CONS, hold, tl(lastarg));
  } else {
    rewrite_to_failure(&e);
  }
  ctx->action = ACT_DONE;
}

void handle_G_END(ReductionCtx *ctx) {
  upleft;
  lastarg = reduce(lastarg);
  if (lastarg == NIL) {
    rewrite_to_cons(e, NIL, NIL);
  } else {
    rewrite_to_failure(&e);
  }
  ctx->action = ACT_DONE;
}

void handle_G_STATE(ReductionCtx *ctx) {
  upleft;
  lastarg = reduce(lastarg);
  if (lastarg == NIL) {
    rewrite_to_failure(&e);
  } else {
    setcell(CONS, ap(SND, hd(lastarg)), lastarg);
  }
  ctx->action = ACT_DONE;
}

void handle_G_SEQ(ReductionCtx *ctx) {
  GETARG(arg1);
  GETARG(arg2);
  upleft;
  hold = ap(arg1, lastarg);
  hold = reduce(hold);
  if (fails(hold)) {
    rewrite_to_failure(&e);
    ctx->action = ACT_DONE;
    return;
  }
  arg3 = ap(arg2, tl(hold));
  arg3 = reduce(arg3);
  if (fails(arg3)) {
    rewrite_to_failure(&e);
    ctx->action = ACT_DONE;
    return;
  }
  setcell(CONS, ap(hd(arg3), hd(hold)), tl(arg3));
  ctx->action = ACT_DONE;
}

void handle_G_UNIT(ReductionCtx *ctx) {
  upleft;
  rewrite_to_cons_head(e, I);
  ctx->action = ACT_DONE;
}

void handle_G_ZERO(ReductionCtx *ctx) {
  upleft;
  rewrite_to_failure(&e);
  ctx->action = ACT_DONE;
}

void handle_G_CLOSE(ReductionCtx *ctx) {
  GETARG(arg1);
  GETARG(arg2);
  upleft;
  arg3 = ap(G_COUNT, lastarg);
  hold = ap(arg2, arg3);
  hold = reduce(hold);
  if (fails(hold)) {
    reduce_parse_close_error(arg1, arg3);
  }
  rewrite_to_value(&e, hd(hold));
  ctx->action = ACT_NEXTREDEX;
}

void handle_G_COUNT(ReductionCtx *ctx) {
  upleft;
  if ((lastarg = reduce(lastarg)) == NIL) {
    rewrite_to_nil(&e);
    ctx->action = ACT_DONE;
    return;
  }
  setcell(CONS, hd(lastarg), ap(G_COUNT, tl(lastarg)));
  ctx->action = ACT_DONE;
}

void handle_LEX_RPT1(ReductionCtx *ctx) {
  GETARG(arg1);
  UPLEFT;
  hd(e) = ap(B, ap2(LEX_RPT, arg1, lastarg));
  tl(e) = LEX_COUNT0;
  DOWNLEFT;
  DOWNLEFT;
  ctx->action = ACT_NEXTREDEX;
}

void handle_LEX_RPT(ReductionCtx *ctx) {
  GETARG(arg1);
  GETARG(arg2);
  upleft;
  if ((lastarg = reduce(lastarg)) == NIL) {
    rewrite_to_nil(&e);
    ctx->action = ACT_DONE;
    return;
  }
  hold = ap2(arg1, arg2, lastarg);
  arg1 = hd(hd(e));
  hold = reduce(hold);
  setcell(CONS, hd(hold), ap2(arg1, hd(tl(hold)), tl(tl(hold))));
  ctx->action = ACT_DONE;
}

void handle_LEX_TRY(ReductionCtx *ctx) {
  upleft;
  tl(e) = reduce(tl(e));
  force(tl(e));
  hd(e) = LEX_TRY_;
  DOWNLEFT;
  ctx->action = ACT_NEXTREDEX;
}

void handle_LEX_TRY_(ReductionCtx *ctx) {
  GETARG(arg1);
  GETARG(arg2);
  upleft;
L2:
  if (arg1 == NIL) {
    lexfail(lastarg);
  }
  if (hd(hd(hd(arg1))) && !member(hd(hd(hd(arg1))), arg2)) {
    arg1 = tl(arg1);
    goto L2;
  }
  hold = ap(hd(tl(hd(arg1))), lastarg);
  if ((hold = reduce(hold)) == NIL) {
    arg1 = tl(arg1);
    goto L2;
  }
  setcell(CONS, ap(tl(tl(hd(arg1))), ap(DESTREV, hd(hold))),
          cons(tl(hd(hd(arg1))) ? tl(hd(hd(arg1))) - 1 : arg2, tl(hold)));
  ctx->action = ACT_DONE;
}

void handle_LEX_TRY1(ReductionCtx *ctx) {
  upleft;
  tl(e) = reduce(tl(e));
  force(tl(e));
  hd(e) = LEX_TRY1_;
  DOWNLEFT;
  ctx->action = ACT_NEXTREDEX;
}

void handle_LEX_TRY1_(ReductionCtx *ctx) {
  GETARG(arg1);
  GETARG(arg2);
  upleft;
L3:
  if (arg1 == NIL) {
    lexfail(lastarg);
  }
  if (hd(hd(hd(arg1))) && !member(hd(hd(hd(arg1))), arg2)) {
    arg1 = tl(arg1);
    goto L3;
  }
  hold = ap(hd(tl(hd(arg1))), lastarg);
  if ((hold = reduce(hold)) == NIL) {
    arg1 = tl(arg1);
    goto L3;
  }
  setcell(CONS, ap2(tl(tl(hd(arg1))), lexstate(lastarg), ap(DESTREV, hd(hold))),
          cons(tl(hd(hd(arg1))) ? tl(hd(hd(arg1))) - 1 : arg2, tl(hold)));
  ctx->action = ACT_DONE;
}

void handle_DESTREV(ReductionCtx *ctx) {
  GETARG(arg1);
  arg2 = NIL;
  while (arg1 != NIL) {
    if (is_strcons(hd(arg1))) {
      hd(arg1) = tl(hd(arg1));
    }
    hold = tl(arg1), tl(arg1) = arg2, arg2 = arg1, arg1 = hold;
  }
  rewrite_to_value(&e, arg2);
  ctx->action = ACT_DONE;
}

void handle_LEX_COUNT0(ReductionCtx *ctx) {
  upleft;
  hd(e) = LEX_COUNT;
  tl(e) = strcons(0, tl(e));
  DOWNLEFT;
  ctx->action = ACT_NEXTREDEX;
}

void handle_LEX_COUNT(ReductionCtx *ctx) {
  GETARG(arg1);
  if ((tl(arg1) = reduce(tl(arg1))) == NIL) {
    rewrite_to_nil(&e);
    ctx->action = ACT_DONE;
    return;
  }
  hold = hd(tl(arg1));
  setcell(CONS, strcons(hd(arg1), hold), ap(LEX_COUNT, arg1));
  if (hold == '\n') {
    hd(arg1) = ((hd(arg1) >> 8) + 1) << 8;
  } else {
    word col = hd(arg1) & 255;
    col = hold == '\t' ? ((col / 8) + 1) * 8 : col + 1;
    hd(arg1) = (hd(arg1) & (~255)) | col;
  }
  tl(arg1) = tl(tl(arg1));
  ctx->action = ACT_DONE;
}

#undef lh
#define lh(x) (is_strcons(hd(x)) ? tl(hd(x)) : hd(x))

void handle_LEX_STRING(ReductionCtx *ctx) {
  GETARG(arg1);
  GETARG(arg2);
  upleft;
  while (arg1 != NIL) {
    if ((lastarg = reduce(lastarg)) == NIL || lh(lastarg) != hd(arg1)) {
      rewrite_to_nil(&e);
      ctx->action = ACT_DONE;
      return;
    }
    arg1 = tl(arg1);
    arg2 = cons(hd(lastarg), arg2);
    lastarg = tl(lastarg);
  }
  rewrite_to_cons_head(e, arg2);
  ctx->action = ACT_DONE;
}

void handle_LEX_CLASS(ReductionCtx *ctx) {
  GETARG(arg1);
  GETARG(arg2);
  upleft;
  if ((lastarg = reduce(lastarg)) == NIL ||
      (hd(arg1) == ANTICHARCLASS ? memclass(lh(lastarg), tl(arg1))
                                 : !memclass(lh(lastarg), arg1))) {
    rewrite_to_nil(&e);
    ctx->action = ACT_DONE;
    return;
  }
  setcell(CONS, cons(hd(lastarg), arg2), tl(lastarg));
  ctx->action = ACT_DONE;
}

void handle_LEX_DOT(ReductionCtx *ctx) {
  GETARG(arg1);
  upleft;
  if ((lastarg = reduce(lastarg)) == NIL) {
    rewrite_to_nil(&e);
    ctx->action = ACT_DONE;
    return;
  }
  setcell(CONS, cons(hd(lastarg), arg1), tl(lastarg));
  ctx->action = ACT_DONE;
}

void handle_LEX_CHAR(ReductionCtx *ctx) {
  GETARG(arg1);
  GETARG(arg2);
  upleft;
  if ((lastarg = reduce(lastarg)) == NIL || lh(lastarg) != arg1) {
    rewrite_to_nil(&e);
    ctx->action = ACT_DONE;
    return;
  }
  setcell(CONS, cons(arg1, arg2), tl(lastarg));
  ctx->action = ACT_DONE;
}

void handle_LEX_SEQ(ReductionCtx *ctx) {
  GETARG(arg1);
  GETARG(arg2);
  GETARG(arg3);
  upleft;
  hold = ap2(arg1, arg3, lastarg);
  lastarg = NIL;
  if ((hold = reduce(hold)) == NIL) {
    e = rewrite_to_existing_tail(e);
    ctx->action = ACT_DONE;
    return;
  }
  hd(e) = ap(arg2, hd(hold));
  tl(e) = tl(hold);
  DOWNLEFT;
  DOWNLEFT;
  ctx->action = ACT_NEXTREDEX;
}

void handle_LEX_OR(ReductionCtx *ctx) {
  GETARG(arg1);
  GETARG(arg2);
  GETARG(arg3);
  upleft;
  hold = ap2(arg1, arg3, lastarg);
  if ((hold = reduce(hold)) == NIL) {
    hd(e) = ap(arg2, arg3);
    DOWNLEFT;
    DOWNLEFT;
    ctx->action = ACT_NEXTREDEX;
    return;
  }
  rewrite_to_value(&e, hold);
  ctx->action = ACT_DONE;
}

void handle_LEX_RCONTEXT(ReductionCtx *ctx) {
  GETARG(arg1);
  GETARG(arg2);
  GETARG(arg3);
  upleft;
  hold = ap2(arg1, arg3, lastarg);
  lastarg = NIL;
  if ((hold = reduce(hold)) == NIL
      || (arg2 ? (reduce(ap2(arg2, hd(hold), tl(hold))) == NIL)
               : (tl(hold) = reduce(tl(hold))) != NIL)) {
    e = rewrite_to_existing_tail(e);
    ctx->action = ACT_DONE;
    return;
  }
  rewrite_to_value(&e, hold);
  ctx->action = ACT_DONE;
}

void handle_LEX_STAR(ReductionCtx *ctx) {
  GETARG(arg1);
  GETARG(arg2);
  upleft;
  hold = ap2(arg1, arg2, lastarg);
  while ((hold = reduce(hold)) != NIL) {
    arg2 = hd(hold), lastarg = tl(hold), hold = ap2(arg1, arg2, lastarg);
  }
  rewrite_to_cons_head(e, arg2);
  ctx->action = ACT_DONE;
}

void handle_LEX_OPT(ReductionCtx *ctx) {
  GETARG(arg1);
  GETARG(arg2);
  upleft;
  hold = ap2(arg1, arg2, lastarg);
  if ((hold = reduce(hold)) == NIL) {
    rewrite_to_cons_head(e, arg2);
    ctx->action = ACT_DONE;
    return;
  }
  rewrite_to_value(&e, hold);
  ctx->action = ACT_DONE;
}
