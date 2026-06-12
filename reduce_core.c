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
  case S: zig_handleS(ctx); break;
  case B: zig_handleB(ctx); break;
  case CB: zig_handleCB(ctx); break;
  case C: zig_handleC(ctx); break;
  case Y: zig_handleY(ctx); break;
  case K: zig_handleK(ctx); break;
  case KI: zig_handleKI(ctx); break;
  case S1: zig_handleS1(ctx); break;
  case B1: zig_handleB1(ctx); break;
  case C1: zig_handleC1(ctx); break;
  case S_p: zig_handleS_p(ctx); break;
  case B_p: zig_handleB_p(ctx); break;
  case C_p: zig_handleC_p(ctx); break;
  case ITERATE: zig_handleITERATE(ctx); break;
  case ITERATE1: zig_handleITERATE1(ctx); break;
  case P:
  case G_RULE: zig_handleP(ctx); break;
  case U: zig_handleU(ctx); break;
  case Uf: zig_handleUf(ctx); break;
  case ATLEAST: zig_handleATLEAST(ctx); break;
  case U_: zig_handleU_(ctx); break;
  case Ug: zig_handleUg(ctx); break;
  case MATCH: zig_handleMATCH(ctx); break;
  case MATCHINT: zig_handleMATCHINT(ctx); break;
  case GENSEQ: zig_handleGENSEQ(ctx); break;
  case MAP: zig_handleMAP(ctx); break;
  case FLATMAP: zig_handleFLATMAP(ctx); break;
  case FILTER: zig_handleFILTER(ctx); break;
  case LIST_LAST: zig_handleLIST_LAST(ctx); break;
  case LENGTH: zig_handleLENGTH(ctx); break;
  case DROP: zig_handleDROP(ctx); break;
  case SUBSCRIPT: zig_handleSUBSCRIPT(ctx); break;
  case FOLDL1: zig_handleFOLDL1(ctx); break;
  case FOLDL: zig_handleFOLDL(ctx); break;
  case FOLDR: zig_handleFOLDR(ctx); break;
  case BADCASE: zig_handleBADCASE(ctx); break;
  case GETARGS: zig_handleGETARGS(ctx); break;
  case CONFERROR: zig_handleCONFERROR(ctx); break;
  case ERROR: zig_handleERROR(ctx); break;
  case WAIT: zig_handleWAIT(ctx); break;
  case TRY: zig_handleTRY(ctx); break;
  case FAIL: zig_handleFAIL(ctx); break;
  case Ush1: zig_handleUsh1(ctx); break;
  case MKSTRICT: zig_handleMKSTRICT(ctx); break;

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
    zig_handle_strict_monadic(ctx);
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
    zig_handle_strict_diadic(ctx);
    break;

  case Ush:
  case STEPUNTIL:
    zig_handle_strict_triadic(ctx);
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
