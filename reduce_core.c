#include <stdlib.h>
#include <errno.h>
#include <sys/types.h>
#include <sys/stat.h>
#include "reduce_internal.h"
#include "data.h"
#include "big.h"
#include "lex.h"
#include "combs.h"

#define FST HD
#define SND TL
#define BSDCLOCK

double fa = 0.0;
double fb = 0.0;

extern int debug, UTF8, UTF8OUT;
extern long long cycles;
extern word stdinuse;
extern word outfilq;
extern word waiting;
extern FILE *s_out;
extern word errtrap;

#ifdef DEBUG
extern word maxrdepth, rdepth;
#endif

extern void out_here(FILE *f, word h, word nl);
extern void outstats(void);

word reduce(word e_val) {
  ReductionCtx local_ctx;
  ReductionCtx *ctx = &local_ctx;
  ctx->e = e_val;
  ctx->s = BACKSTOP;
  ctx->hold = 0;
  ctx->args[0] = 0;
  ctx->args[1] = 0;
  ctx->args[2] = 0;
  ctx->args[3] = 0;
  ctx->action = ACT_NONE;

#ifdef DEBUG
  if (++rdepth > maxrdepth)
    maxrdepth = rdepth;
  if (debug & 0x2) {
    printf("reducing: ");
    out_here(stdout, ctx->e, 0);
    putchar('\n');
  }
#endif

NEXTREDEX:
  while (is_ap(ctx->e)) {
    ctx_down_left(ctx);
  }
#ifdef HISTO
  histo(ctx->e);
#endif
#ifdef DEBUG
  if (debug & 0x2) {
    printf("head= ");
    if (ctx->e == BACKSTOP)
      printf("BACKSTOP");
    else
      out_here(stdout, ctx->e, 0);
    putchar('\n');
  }
#endif

  cycles++;
  ctx->action = ACT_NONE;

  switch (ctx->e) {
  case S: handle_S(ctx); break;
  case B: handle_B(ctx); break;
  case CB: handle_CB(ctx); break;
  case C: handle_C(ctx); break;
  case Y: handle_Y(ctx); break;
  case K: zig_handleK(ctx); break;
  case KI: handle_KI(ctx); break;
  case S1: handle_S1(ctx); break;
  case B1: handle_B1(ctx); break;
  case C1: handle_C1(ctx); break;
  case S_p: handle_S_p(ctx); break;
  case B_p: handle_B_p(ctx); break;
  case C_p: handle_C_p(ctx); break;
  case ITERATE: handle_ITERATE(ctx); break;
  case ITERATE1: handle_ITERATE1(ctx); break;
  case P:
  case G_RULE: handle_P(ctx); break;
  case U: handle_U(ctx); break;
  case Uf: handle_Uf(ctx); break;
  case ATLEAST: handle_ATLEAST(ctx); break;
  case U_: handle_U_(ctx); break;
  case Ug: handle_Ug(ctx); break;
  case MATCH: handle_MATCH(ctx); break;
  case MATCHINT: handle_MATCHINT(ctx); break;
  case GENSEQ: handle_GENSEQ(ctx); break;
  case MAP: handle_MAP(ctx); break;
  case FLATMAP: handle_FLATMAP(ctx); break;
  case FILTER: handle_FILTER(ctx); break;
  case LIST_LAST: handle_LIST_LAST(ctx); break;
  case LENGTH: handle_LENGTH(ctx); break;
  case DROP: handle_DROP(ctx); break;
  case SUBSCRIPT: handle_SUBSCRIPT(ctx); break;
  case FOLDL1: handle_FOLDL1(ctx); break;
  case FOLDL: handle_FOLDL(ctx); break;
  case FOLDR: handle_FOLDR(ctx); break;
  case BADCASE: handle_BADCASE(ctx); break;
  case GETARGS: handle_GETARGS(ctx); break;
  case CONFERROR: handle_CONFERROR(ctx); break;
  case ERROR: handle_ERROR(ctx); break;
  case WAIT: handle_WAIT(ctx); break;
  case TRY: handle_TRY(ctx); break;
  case FAIL: handle_FAIL(ctx); break;
  case Ush1: handle_Ush1(ctx); break;
  case MKSTRICT: handle_MKSTRICT(ctx); break;

  case I:
    zig_handleI(ctx);
    break;

  case SEQ:
  case FORCE:
  case HD:
  case TL:
  case BODY:
  case LAST:
  case EXEC:
  case FILEMODE:
  case FILESTAT:
  case GETENV:
  case INTEGER:
  case NUMVAL:
  case TAKE:
  case STARTREAD:
  case STARTREADBIN:
  case NB_STARTREAD:
  case COND:
  case APPEND:
  case AND:
  case OR:
  case NOT:
  case NEG:
  case CODE:
  case DECODE:
  case SHOWNUM:
  case SHOWHEX:
  case SHOWOCT:
  case ARCTAN_FN:
  case EXP_FN:
  case ENTIER_FN:
  case LOG_FN:
  case LOG10_FN:
  case SIN_FN:
  case COS_FN:
  case SQRT_FN:
    handle_strict_monadic(ctx);
    break;

  case ZIP:
  case STEP:
  case EQ:
  case NEQ:
  case PLUS:
  case MINUS:
  case TIMES:
  case INTDIV:
  case FDIV:
  case MOD:
  case GRE:
  case GR:
  case POWER:
  case SHOWSCALED:
  case SHOWFLOAT:
  case MERGE:
    handle_strict_diadic(ctx);
    break;

  case Ush:
  case STEPUNTIL:
    handle_strict_triadic(ctx);
    break;

  // Grammar Combinators (reduce_lex.c)
  case G_ERROR: handle_G_ERROR(ctx); break;
  case G_ALT: handle_G_ALT(ctx); break;
  case G_OPT: handle_G_OPT(ctx); break;
  case G_STAR: handle_G_STAR(ctx); break;
  case G_FBSTAR: handle_G_FBSTAR(ctx); break;
  case G_SYMB: handle_G_SYMB(ctx); break;
  case G_ANY: handle_G_ANY(ctx); break;
  case G_SUCHTHAT: handle_G_SUCHTHAT(ctx); break;
  case G_END: handle_G_END(ctx); break;
  case G_STATE: handle_G_STATE(ctx); break;
  case G_SEQ: handle_G_SEQ(ctx); break;
  case G_UNIT: handle_G_UNIT(ctx); break;
  case G_ZERO: handle_G_ZERO(ctx); break;
  case G_CLOSE: handle_G_CLOSE(ctx); break;
  case G_COUNT: handle_G_COUNT(ctx); break;

  // Lexer Combinators (reduce_lex.c)
  case LEX_RPT1: handle_LEX_RPT1(ctx); break;
  case LEX_RPT: handle_LEX_RPT(ctx); break;
  case LEX_TRY: handle_LEX_TRY(ctx); break;
  case LEX_TRY_: handle_LEX_TRY_(ctx); break;
  case LEX_TRY1: handle_LEX_TRY1(ctx); break;
  case LEX_TRY1_: handle_LEX_TRY1_(ctx); break;
  case DESTREV: handle_DESTREV(ctx); break;
  case LEX_COUNT0: handle_LEX_COUNT0(ctx); break;
  case LEX_COUNT: handle_LEX_COUNT(ctx); break;
  case LEX_STRING: handle_LEX_STRING(ctx); break;
  case LEX_CLASS: handle_LEX_CLASS(ctx); break;
  case LEX_DOT: handle_LEX_DOT(ctx); break;
  case LEX_CHAR: handle_LEX_CHAR(ctx); break;
  case LEX_SEQ: handle_LEX_SEQ(ctx); break;
  case LEX_OR: handle_LEX_OR(ctx); break;
  case LEX_RCONTEXT: handle_LEX_RCONTEXT(ctx); break;
  case LEX_STAR: handle_LEX_STAR(ctx); break;
  case LEX_OPT: handle_LEX_OPT(ctx); break;

  // IO (reduce_io.c)
  case READ: handle_READ(ctx); break;
  case READBIN: handle_READBIN(ctx); break;
  case READVALS: handle_READVALS(ctx); break;

  default:
    cycles--;
    if (abnormal(ctx->e)) {
      fprintf(stderr, "\nBLACK HOLE\n");
      outstats();
      exit(1);
    }

    switch (tag[ctx->e]) {
    case STRCONS:
      ctx->e = pn_val(ctx->e);
      if (ctx->e == UNDEF || ctx->e == FREE) {
        fprintf(stderr, "\nimpossible event in reduce - undefined pname\n"), exit(1);
      }
      ctx->action = ACT_NEXTREDEX;
      break;

    case DATAPAIR:
      ctx_up_left(ctx);
      fprintf(stderr, "\nUNDEFINED NAME (specified as \"%s\" in %s)\n", (char *)hd(hd(ctx->e)),
              (char *)tl(ctx->e));
      outstats();
      exit(1);

    case ID:
      if (id_val(ctx->e) == UNDEF || id_val(ctx->e) == FREE) {
        fprintf(stderr, "\nUNDEFINED NAME - %s\n", get_id(ctx->e));
        outstats();
        exit(1);
      }
      ctx->e = id_val(ctx->e);
      ctx->action = ACT_NEXTREDEX;
      break;

    default:
      fprintf(stderr, "\nimpossible tag (%d) in reduce\n", tag[ctx->e]);
      exit(1);

    case CONSTRUCTOR:
      for (;;) {
        if (ctx_upleft(ctx)) {
          ctx->action = ACT_DONE;
          break;
        }
      }
      break;

    case STARTREADVALS:
      handle_STARTREADVALS(ctx);
      break;

    case ATOM:
    case INT:
    case UNICODE:
    case DOUBLE:
    case CONS:
      ctx->action = ACT_DONE;
      break;
    }
    break;
  }

  if (ctx->action == ACT_NEXTREDEX) {
    goto NEXTREDEX;
  }

DONE:
  if (ctx->s == BACKSTOP) {
#ifdef DEBUG
    if (debug & 0x2) {
      printf("result= ");
      out_here(stdout, ctx->e, 0);
      putchar('\n');
    }
    rdepth--;
#endif
    return ctx->e;
  }

  ctx_up_right(ctx);

  if (is_ap(ctx->e)) {
    ctx_down_left(ctx);
    ctx_down_right(ctx);
    goto NEXTREDEX;
  }

  handle_ready_state(ctx);
  if (ctx->action == ACT_NEXTREDEX) {
    goto NEXTREDEX;
  }
  goto DONE;
}
