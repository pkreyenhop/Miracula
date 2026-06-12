#include <stdlib.h>
#include <stdio.h>
#include "reduce_internal.h"
#include "data.h"
#include "lex.h"
#include "combs.h"

struct reduce_ctx {
  word e;
  word s;
  word hold;
  word arg1;
  word arg2;
  word arg3;
};

extern int reduce_stream_read(struct reduce_ctx *c, word op);
extern word stdinuse;
extern void outstats(void);

void handle_READ(ReductionCtx *ctx) {
  struct reduce_ctx call_ctx;
  call_ctx.e = ctx->e;
  call_ctx.s = ctx->s;
  call_ctx.hold = ctx->hold;
  call_ctx.arg1 = ctx->args[0];
  call_ctx.arg2 = ctx->args[1];
  call_ctx.arg3 = ctx->args[2];
  int act = reduce_stream_read(&call_ctx, READ);
  ctx->e = call_ctx.e;
  ctx->s = call_ctx.s;
  ctx->hold = call_ctx.hold;
  ctx->args[0] = call_ctx.arg1;
  ctx->args[1] = call_ctx.arg2;
  ctx->args[2] = call_ctx.arg3;
  ctx->action = (ReduceAction)act;
}

void handle_READBIN(ReductionCtx *ctx) {
  struct reduce_ctx call_ctx;
  call_ctx.e = ctx->e;
  call_ctx.s = ctx->s;
  call_ctx.hold = ctx->hold;
  call_ctx.arg1 = ctx->args[0];
  call_ctx.arg2 = ctx->args[1];
  call_ctx.arg3 = ctx->args[2];
  int act = reduce_stream_read(&call_ctx, READBIN);
  ctx->e = call_ctx.e;
  ctx->s = call_ctx.s;
  ctx->hold = call_ctx.hold;
  ctx->args[0] = call_ctx.arg1;
  ctx->args[1] = call_ctx.arg2;
  ctx->args[2] = call_ctx.arg3;
  ctx->action = (ReduceAction)act;
}

void handle_READVALS(ReductionCtx *ctx) {
  struct reduce_ctx call_ctx;
  call_ctx.e = ctx->e;
  call_ctx.s = ctx->s;
  call_ctx.hold = ctx->hold;
  call_ctx.arg1 = ctx->args[0];
  call_ctx.arg2 = ctx->args[1];
  call_ctx.arg3 = ctx->args[2];
  int act = reduce_stream_read(&call_ctx, READVALS);
  ctx->e = call_ctx.e;
  ctx->s = call_ctx.s;
  ctx->hold = call_ctx.hold;
  ctx->args[0] = call_ctx.arg1;
  ctx->args[1] = call_ctx.arg2;
  ctx->args[2] = call_ctx.arg3;
  ctx->action = (ReduceAction)act;
}

// Define local macro mapping for context registers after the wrappers
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

void handle_STARTREADVALS(ReductionCtx *ctx) {
  char *fil;
  upleft;
  lastarg = reduce(lastarg);
  if (lastarg == OFFSIDE) {
    if (stdinuse && stdinuse != '+') {
      tag[e] = AP;
      rewrite_to_nil(&e);
      ctx->action = ACT_DONE;
      return;
    }
    stdinuse = '+';
    hold = cons(tl(hd(e)), 0), lastarg = (word)stdin;
  } else {
    hold = cons(tl(hd(e)), lastarg);
    lastarg = (word)fopen(fil = getstring(lastarg, "readvals"), "r");
    if ((FILE *)lastarg == NULL) {
      fprintf(stderr, "\nreadvals, cannot open: \"%s\"\n", fil);
      outstats();
      exit(1);
    }
  }
  hd(e) = ap(READVALS, hold);
  DOWNLEFT;
  DOWNLEFT;
  handle_READVALS(ctx);
}
