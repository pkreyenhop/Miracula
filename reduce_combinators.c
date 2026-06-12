#include <stdlib.h>
#include <stdio.h>
#include <ctype.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <unistd.h>
#include "reduce_internal.h"
#include "data.h"
#include "big.h"
#include "lex.h"
#include "combs.h"

// Define local macro mapping for context registers to allow copy-paste of legacy C code
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

// Only declare variables/functions NOT present in data.h, big.h, lex.h
extern int debug;
extern long long cycles;
extern word waiting;
extern word errtrap;
extern FILE *s_out;

void handle_S(ReductionCtx *ctx) {
  getarg(arg1);
  getarg(arg2);
  upleft;
  hd(e) = ap(arg1, lastarg);
  tl(e) = ap(arg2, lastarg);
  DOWNLEFT;
  DOWNLEFT;
  ctx->action = ACT_NEXTREDEX;
}

void handle_B(ReductionCtx *ctx) {
  getarg(arg1);
  getarg(arg2);
  upleft;
  hd(e) = arg1;
  tl(e) = ap(arg2, lastarg);
  DOWNLEFT;
  ctx->action = ACT_NEXTREDEX;
}

void handle_CB(ReductionCtx *ctx) {
  getarg(arg1);
  getarg(arg2);
  upleft;
  hd(e) = arg2;
  tl(e) = ap(arg1, lastarg);
  DOWNLEFT;
  ctx->action = ACT_NEXTREDEX;
}

void handle_C(ReductionCtx *ctx) {
  getarg(arg1);
  getarg(arg2);
  upleft;
  hd(e) = ap(arg1, lastarg);
  tl(e) = arg2;
  DOWNLEFT;
  DOWNLEFT;
  ctx->action = ACT_NEXTREDEX;
}

void handle_Y(ReductionCtx *ctx) {
  upleft;
  hd(e) = tl(e);
  tl(e) = e;
  DOWNLEFT;
  ctx->action = ACT_NEXTREDEX;
}

void handle_K(ReductionCtx *ctx) {
  getarg(arg1);
  upleft;
  rewrite_to_value(&e, arg1);
  ctx->action = ACT_NEXTREDEX;
}

void handle_KI(ReductionCtx *ctx) {
  upleft;
  upleft;
  e = rewrite_to_existing_tail(e);
  ctx->action = ACT_NEXTREDEX;
}

void handle_S1(ReductionCtx *ctx) {
  getarg(arg1);
  getarg(arg2);
  getarg(arg3);
  upleft;
  hd(e) = ap(arg2, lastarg);
  hd(e) = ap(arg1, hd(e));
  tl(e) = ap(arg3, lastarg);
  DOWNLEFT;
  DOWNLEFT;
  ctx->action = ACT_NEXTREDEX;
}

void handle_B1(ReductionCtx *ctx) {
  getarg(arg1);
  getarg(arg2);
  getarg(arg3);
  upleft;
  hd(e) = arg1;
  tl(e) = ap(arg3, lastarg);
  tl(e) = ap(arg2, tl(e));
  DOWNLEFT;
  ctx->action = ACT_NEXTREDEX;
}

void handle_C1(ReductionCtx *ctx) {
  getarg(arg1);
  getarg(arg2);
  getarg(arg3);
  upleft;
  hd(e) = ap(arg2, lastarg);
  hd(e) = ap(arg1, hd(e));
  tl(e) = arg3;
  DOWNLEFT;
  ctx->action = ACT_NEXTREDEX;
}

void handle_S_p(ReductionCtx *ctx) {
  getarg(arg1);
  getarg(arg2);
  upleft;
  setcell(CONS, ap(arg1, lastarg), ap(arg2, lastarg));
  ctx->action = ACT_DONE;
}

void handle_B_p(ReductionCtx *ctx) {
  getarg(arg1);
  getarg(arg2);
  upleft;
  setcell(CONS, arg1, ap(arg2, lastarg));
  ctx->action = ACT_DONE;
}

void handle_C_p(ReductionCtx *ctx) {
  getarg(arg1);
  getarg(arg2);
  upleft;
  setcell(CONS, ap(arg1, lastarg), arg2);
  ctx->action = ACT_DONE;
}

void handle_ITERATE(ReductionCtx *ctx) {
  getarg(arg1);
  upleft;
  hold = ap(hd(e), ap(arg1, lastarg));
  rewrite_to_cons(e, lastarg, hold);
  ctx->action = ACT_DONE;
}

void handle_ITERATE1(ReductionCtx *ctx) {
  getarg(arg1);
  upleft;
  if ((lastarg = reduce(lastarg)) == FAIL) {
    rewrite_to_nil(&e);
  } else {
    hold = ap(hd(e), ap(arg1, lastarg));
    rewrite_to_cons(e, lastarg, hold);
  }
  ctx->action = ACT_DONE;
}

void handle_P(ReductionCtx *ctx) {
  getarg(arg1);
  upleft;
  rewrite_to_cons(e, arg1, lastarg);
  ctx->action = ACT_DONE;
}

void handle_U(ReductionCtx *ctx) {
  getarg(arg1);
  upleft;
  hd(e) = ap(arg1, ap(HD, lastarg));
  tl(e) = ap(TL, lastarg);
  DOWNLEFT;
  DOWNLEFT;
  ctx->action = ACT_NEXTREDEX;
}

void handle_Uf(ReductionCtx *ctx) {
  getarg(arg1);
  upleft;
  if (is_constructor(head(lastarg))) {
    hd(e) = ap(arg1, hd(lastarg)), tl(e) = tl(lastarg);
  } else {
    hd(e) = ap(arg1, ap(BODY, lastarg)), tl(e) = ap(LAST, lastarg);
  }
  DOWNLEFT;
  DOWNLEFT;
  ctx->action = ACT_NEXTREDEX;
}

void handle_ATLEAST(ReductionCtx *ctx) {
  getarg(arg1);
  getarg(arg2);
  upleft;
  lastarg = reduce(lastarg);
  if (is_int(lastarg)) {
    hold = bigsub(lastarg, arg1);
    if (poz(hold)) {
      hd(e) = arg2, tl(e) = hold;
    } else {
      rewrite_to_fail(&e);
    }
  } else {
    rewrite_to_fail(&e);
  }
  ctx->action = ACT_NEXTREDEX;
}

void handle_U_(ReductionCtx *ctx) {
  getarg(arg1);
  upleft;
  lastarg = reduce(lastarg);
  if (lastarg == NIL) {
    rewrite_to_fail(&e);
    ctx->action = ACT_NEXTREDEX;
    return;
  }
  hd(e) = ap(arg1, hd(lastarg));
  tl(e) = tl(lastarg);
  ctx->action = ACT_NEXTREDEX;
}

void handle_Ug(ReductionCtx *ctx) {
  getarg(arg1);
  getarg(arg2);
  upleft;
  lastarg = reduce(lastarg);
  if (constr_tag(arg1) != constr_tag(head(lastarg))) {
    rewrite_to_fail(&e);
    ctx->action = ACT_NEXTREDEX;
    return;
  }
  if (is_constructor(lastarg)) {
    rewrite_to_value(&e, arg2);
    ctx->action = ACT_NEXTREDEX;
    return;
  }
  hd(e) = hd(lastarg);
  tl(e) = tl(lastarg);
  while (!is_constructor(hd(e))) {
    hd(e) = ap(hd(hd(e)), tl(hd(e)));
    DOWNLEFT;
  }
  hd(e) = arg2;
  ctx->action = ACT_NEXTREDEX;
}

void handle_MATCH(ReductionCtx *ctx) {
  upleft;
  arg1 = lastarg = reduce(lastarg);
  getarg(arg2);
  upleft;
  lastarg = reduce(lastarg);
  rewrite_to_match_result(&e, arg1, lastarg, arg2);
  ctx->action = ACT_NEXTREDEX;
}

void handle_MATCHINT(ReductionCtx *ctx) {
  getarg(arg1);
  getarg(arg2);
  upleft;
  lastarg = reduce(lastarg);
  rewrite_to_int_match_result(&e, arg1, lastarg, arg2);
  ctx->action = ACT_NEXTREDEX;
}

void handle_GENSEQ(ReductionCtx *ctx) {
  GETARG(arg1);
  UPLEFT;
  if (tl(arg1) != NIL &&
      (is_ap(arg1) ? compare(lastarg, tl(arg1)) : compare(tl(arg1), lastarg)) > 0) {
    rewrite_to_nil(&e);
  } else {
    hold = ap(hd(e), numplus(lastarg, hd(arg1)));
    rewrite_to_cons(e, lastarg, hold);
  }
  ctx->action = ACT_DONE;
}

void handle_MAP(ReductionCtx *ctx) {
  getarg(arg1);
  upleft;
  lastarg = reduce(lastarg);
  if (lastarg == NIL) {
    rewrite_to_nil(&e);
  } else {
    hold = ap(hd(e), tl(lastarg)), setcell(CONS, ap(arg1, hd(lastarg)), hold);
  }
  ctx->action = ACT_DONE;
}

void handle_FLATMAP(ReductionCtx *ctx) {
  getarg(arg1);
  getarg(arg2);
L1:
  arg2 = reduce(arg2);
  if (arg2 == NIL) {
    rewrite_to_nil(&e);
    ctx->action = ACT_DONE;
    return;
  }
  hold = reduce(hold = ap(arg1, hd(arg2)));
  if (hold == FAIL || hold == NIL) {
    arg2 = tl(arg2);
    goto L1;
  }
  tl(e) = ap(hd(e), tl(arg2));
  hd(e) = ap(APPEND, hold);
  ctx->action = ACT_NEXTREDEX;
}

void handle_FILTER(ReductionCtx *ctx) {
  getarg(arg1);
  upleft;
  lastarg = reduce(lastarg);
  while (lastarg != NIL && reduce(ap(arg1, hd(lastarg))) == False) {
    lastarg = reduce(tl(lastarg));
  }
  if (lastarg == NIL) {
    rewrite_to_nil(&e);
  } else {
    hold = ap(hd(e), tl(lastarg)), setcell(CONS, hd(lastarg), hold);
  }
  ctx->action = ACT_DONE;
}

void handle_LIST_LAST(ReductionCtx *ctx) {
  upleft;
  if ((lastarg = reduce(lastarg)) == NIL) {
    fn_error("last []");
  }
  while ((tl(lastarg) = reduce(tl(lastarg))) != NIL) {
    lastarg = tl(lastarg);
  }
  rewrite_to_value(&e, hd(lastarg));
  ctx->action = ACT_NEXTREDEX;
}

void handle_LENGTH(ReductionCtx *ctx) {
  upleft;
  {
    long long n = 0;
    while ((lastarg = reduce(lastarg)) != NIL) {
      lastarg = tl(lastarg), n++;
    }
    simpl(sto_int(n));
  }
  ctx->action = ACT_DONE;
}

void handle_DROP(ReductionCtx *ctx) {
  getarg(arg1);
  upleft;
  arg1 = tl(hd(e)) = reduce(tl(hd(e)));
  if (!is_int(arg1)) {
    int_error("drop");
  }
  {
    long long n = get_int(arg1);
    while (n-- > 0) {
      if ((lastarg = reduce(lastarg)) == NIL) {
        rewrite_to_nil(&e);
        ctx->action = ACT_DONE;
        return;
      } else {
        lastarg = tl(lastarg);
      }
    }
  }
  rewrite_to_value(&e, lastarg);
  ctx->action = ACT_NEXTREDEX;
}

void handle_SUBSCRIPT(ReductionCtx *ctx) {
  upleft;
  upleft;
  arg1 = tl(hd(e)) = reduce(tl(hd(e)));
  lastarg = reduce(lastarg);
  if (lastarg == NIL) {
    subs_error();
  }
  {
    long long indx = 0;
    if (is_atom(arg1)) {
      indx = arg1;
    } else if (is_int(arg1)) {
      indx = get_int(arg1);
    } else {
      int_error("!");
    }
    if (indx < 0) {
      subs_error();
    }
    while (indx) {
      lastarg = tl(lastarg) = reduce(tl(lastarg));
      if (lastarg == NIL) {
        subs_error();
      }
      indx--;
    }
    rewrite_to_value(&e, hd(lastarg));
    ctx->action = ACT_NEXTREDEX;
  }
}

void handle_FOLDL1(ReductionCtx *ctx) {
  getarg(arg1);
  upleft;
  if ((lastarg = reduce(lastarg)) != NIL) {
    hd(e) = ap2(FOLDL, arg1, hd(lastarg));
    tl(e) = tl(lastarg);
    ctx->action = ACT_NEXTREDEX;
  } else {
    fn_error("foldl1 applied to []");
  }
}

void handle_FOLDL(ReductionCtx *ctx) {
  getarg(arg1);
  getarg(arg2);
  upleft;
  while ((lastarg = reduce(lastarg)) != NIL) {
    arg2 = reduce(ap2(arg1, arg2, hd(lastarg)));
    lastarg = tl(lastarg);
  }
  rewrite_to_value(&e, arg2);
  ctx->action = ACT_NEXTREDEX;
}

void handle_FOLDR(ReductionCtx *ctx) {
  getarg(arg1);
  getarg(arg2);
  upleft;
  lastarg = reduce(lastarg);
  if (lastarg == NIL) {
    rewrite_to_value(&e, arg2);
  } else {
    hold = ap(hd(e), tl(lastarg)), hd(e) = ap(arg1, hd(lastarg)), tl(e) = hold;
  }
  ctx->action = ACT_NEXTREDEX;
}

void handle_BADCASE(ReductionCtx *ctx) {
  UPLEFT;
  reduce_badcase_error(lastarg);
}

void handle_GETARGS(ReductionCtx *ctx) {
  UPLEFT;
  simpl(conv_args());
  ctx->action = ACT_DONE;
}

void handle_CONFERROR(ReductionCtx *ctx) {
  UPLEFT;
  reduce_conf_error(lastarg);
}

void handle_ERROR(ReductionCtx *ctx) {
  upleft;
  if (errtrap) {
    fprintf(stderr, "\n(repeated error)\n");
  } else {
    errtrap = 1;
    fprintf(stderr, "\nprogram error: ");
    s_out = stderr;
    print(lastarg);
    putc('\n', stderr);
  }
  outstats();
  exit(1);
}

void handle_WAIT(ReductionCtx *ctx) {
  UPLEFT;
  {
    word *w = &waiting;
    while (*w != NIL && hd(*w) != lastarg) {
      w = &tl(tl(*w));
    }
    if (*w != NIL) {
      hold = hd(tl(*w)), *w = tl(tl(*w));
    } else {
      int status;
      while ((hold = wait(&status)) != lastarg && hold != -1) {
        waiting = cons(hold, cons(WEXITSTATUS(status), waiting));
      }
      if (hold != -1) {
        hold = WEXITSTATUS(status);
      }
    }
  }
  simpl(stosmallint(hold));
  ctx->action = ACT_DONE;
}

void handle_TRY(ReductionCtx *ctx) {
  getarg(arg1);
  getarg(arg2);
  while (!abnormal(s)) {
    UPLEFT;
    hd(e) = ap(TRY, arg1 = ap(arg1, lastarg));
    arg2 = tl(e) = ap(arg2, lastarg);
  }
  DOWNLEFT;
  hold = s, s = e, e = tl(e), tl(s) = hold, s |= tlptrbit;
  ctx->action = ACT_NEXTREDEX;
}

void handle_FAIL(ReductionCtx *ctx) {
  while (!abnormal(s)) {
    hold = s, s = hd(s), hd(hold) = FAIL, tl(hold) = 0;
  }
  ctx->action = ACT_DONE;
}

void handle_Ush1(ReductionCtx *ctx) {
  getarg(arg1);
  arg1 = reduce(arg1);
  getarg(arg2);
  arg2 = reduce(arg2);
  getarg(arg3);
  if (is_constructor(arg1)) {
    if (suppressed(arg1)) {
      rewrite_to_string(&e, "<unprintable>");
    } else {
      rewrite_to_string(&e, constr_name(arg1));
    }
    ctx->action = ACT_DONE;
    return;
  }
  hold = arg2 ? cons(')', NIL) : NIL;
  while (!is_constructor(arg1)) {
    hold = cons(' ', ap2(APPEND, ap(tl(arg1), ap(LAST, arg3)), hold)), arg1 = hd(arg1),
    arg3 = ap(BODY, arg3);
  }
  if (suppressed(arg1)) {
    rewrite_to_string(&e, "<unprintable>");
    ctx->action = ACT_DONE;
    return;
  }
  hold = ap2(APPEND, str_conv(constr_name(arg1)), hold);
  if (arg2) {
    setcell(CONS, '(', hold);
    ctx->action = ACT_DONE;
  } else {
    rewrite_to_value(&e, hold);
    ctx->action = ACT_NEXTREDEX;
  }
}

void handle_MKSTRICT(ReductionCtx *ctx) {
  GETARG(arg1);
  getarg(arg2);
  {
    word i = arg1;
    while (i--) {
      upleft;
    }
  }
  lastarg = reduce(lastarg);
  while (--arg1) {
    hd(e) = ap(hd(hd(e)), tl(hd(e)));
    DOWNLEFT;
  }
  hd(e) = arg2;
  ctx->action = ACT_NEXTREDEX;
}

void handle_strict_monadic(ReductionCtx *ctx) {
  downright;
  ctx->action = ACT_NEXTREDEX;
}

void handle_strict_diadic(ReductionCtx *ctx) {
  upleft;
  downright;
  ctx->action = ACT_NEXTREDEX;
}

void handle_strict_triadic(ReductionCtx *ctx) {
  upleft;
  upleft;
  downright;
  ctx->action = ACT_NEXTREDEX;
}
