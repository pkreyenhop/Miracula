#include <stdlib.h>
#include <stdio.h>
#include <ctype.h>
#include <math.h>
#include <errno.h>
#include <sys/types.h>
#include <sys/stat.h>
#include "reduce_internal.h"
#include "data.h"
#include "big.h"
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

#define READY(x) (x)
#define RESTORE(x)

// External declarations not present in headers
extern int debug;
extern char linebuf[];
extern double fa, fb;
extern word stdinuse;

#ifdef RYU
extern word d2s_buffered(double d, char *buf);
#endif

// Static struct stat buf used by FILEMODE / FILESTAT
static struct stat buf;

// Declarations of jumps to avoid cross-function gotos
#define L_K (K)
#define L_KI (KI)
#define L_I (I)

#define coerce_dbl(x) (is_double(x) ? (x) : sto_dbl(bigtodbl(x)))

void handle_ready_state(ReductionCtx *ctx) {
#ifdef DEBUG
  if (debug & 0x2) {
    printf("ready(");
    out_here(stdout, e, 0);
    printf(")\n");
  }
#endif

  switch (e)
  {
  case READY(I):
    UPLEFT;
    e = lastarg;
    ctx->action = ACT_NEXTREDEX;
    return;

  case READY(SEQ):
    UPLEFT;
    upleft;
    e = rewrite_to_existing_tail(e);
    ctx->action = ACT_NEXTREDEX;
    return;

  case READY(FORCE):
    UPLEFT;
    force(lastarg);
    e = rewrite_to_existing_tail(e);
    ctx->action = ACT_NEXTREDEX;
    return;

  case READY(HD):
    UPLEFT;
    if (lastarg == NIL) {
      fprintf(stderr, "\nATTEMPT TO TAKE hd OF []\n");
      outstats();
      exit(1);
    }
    rewrite_to_value(&e, hd(lastarg));
    ctx->action = ACT_NEXTREDEX;
    return;

  case READY(TL):
    UPLEFT;
    if (lastarg == NIL) {
      fprintf(stderr, "\nATTEMPT TO TAKE tl OF []\n");
      outstats();
      exit(1);
    }
    rewrite_to_value(&e, tl(lastarg));
    ctx->action = ACT_NEXTREDEX;
    return;

  case READY(BODY):
    UPLEFT;
    rewrite_to_value(&e, hd(lastarg));
    ctx->action = ACT_NEXTREDEX;
    return;

  case READY(LAST):
    UPLEFT;
    rewrite_to_value(&e, tl(lastarg));
    ctx->action = ACT_NEXTREDEX;
    return;

  case READY(TAKE):
    GETARG(arg1);
    upleft;
    if (!is_int(arg1)) {
      int_error("take");
    }
    {
      long long n = get_int(arg1);
      if (n <= 0 || (lastarg = reduce(lastarg)) == NIL) {
        rewrite_to_nil(&e);
        ctx->action = ACT_DONE;
        return;
      }
      setcell(CONS, hd(lastarg), ap2(TAKE, sto_int(n - 1), tl(lastarg)));
    }
    ctx->action = ACT_DONE;
    return;

  case READY(FILEMODE):
    UPLEFT;
    if (!stat(getstring(lastarg, "filemode"), &buf)) {
      mode_t mode = buf.st_mode;
      word d = S_ISDIR(mode) ? 'd' : '-';
      word perm = buf.st_uid == geteuid()   ? (mode & 0x1c0) >> 6
                  : buf.st_gid == getegid() ? (mode & 0x38) >> 3
                                            : mode & 0x7;
      word r = perm & 0x4 ? 'r' : '-';
      word w = perm & 0x2 ? 'w' : '-';
      word x = perm & 0x1 ? 'x' : '-';
      setcell(CONS, d, cons(r, cons(w, cons(x, NIL))));
    } else {
      rewrite_to_nil(&e);
    }
    ctx->action = ACT_DONE;
    return;

  case READY(FILESTAT):
    UPLEFT;
    if (!stat(getstring(lastarg, "filestat"), &buf)) {
      setcell(CONS, cons(sto_int(buf.st_ino), sto_int(buf.st_dev)), sto_int(buf.st_mtime));
    } else {
      setcell(CONS, cons(stosmallint(0), stosmallint(-1)), stosmallint(0));
    }
    ctx->action = ACT_DONE;
    return;

  case READY(GETENV):
    UPLEFT;
    {
      char *a = getstring(lastarg, "getenv");
      unsigned char *p = (unsigned char *)getenv(a);
      hold = NIL;
      if (p) {
        word i;
        if (UTF8) {
          unsigned char *qbuf = (unsigned char *)malloc(strlen((char *)p) + 1);
          unsigned char *q;
          unsigned char *r;
          if (qbuf == NULL) {
            mallocfail("getenv");
          }
          strcpy((char *)qbuf, (char *)p);
          q = r = qbuf;
          while (*r) {
            if (*r > 127) {
              if ((*r == 194 || *r == 195) && r[1] >= 128 && r[1] <= 191) {
                *q = *r == 194 ? r[1] : r[1] + 64, q++, r += 2;
              } else {
                getenv_error(a),
                *q++ = *r++;
              }
            } else {
              *q++ = *r++;
            }
          }
          *q = '\0';
          i = strlen((char *)qbuf);
          while (i--) {
            hold = cons(qbuf[i], hold);
          }
          free(qbuf);
        } else {
          i = strlen((char *)p);
          while (i--) {
            hold = cons(p[i], hold);
          }
        }
      }
    }
    hd(e) = I;
    e = tl(e) = hold;
    ctx->action = ACT_DONE;
    return;

  case READY(EXEC):
    UPLEFT;
    {
      int pid = (-1);
      int fd[2];
      int fd_a[2];
      char *cp = getstring(lastarg, "system");
      if (pipe(fd) == (-1) || pipe(fd_a) == (-1) || (pid = fork())) {
        FILE *fp = NULL;
        FILE *fp_a = NULL;
        if (pid != -1) {
          close(fd[1]), close(fd_a[1]), fp = fdopen(fd[0], "r"), fp_a = fdopen(fd_a[0], "r");
        }
        if (pid == -1 || !fp || !fp_a) {
          setcell(CONS, NIL, cons(piperrmess(pid), sto_int(-1)));
        } else {
          setcell(CONS, ap(READ, fp), cons(ap(READ, fp_a), ap(WAIT, pid)));
        }
      } else {
        static char *shell = "/bin/sh";
        dup2(fd[1], 1);
        dup2(fd_a[1], 2);
        close(fd[1]);
        close(fd[0]);
        close(fd_a[1]);
        close(fd_a[0]);
        fclose(stdin);
        execl(shell, shell, "-c", cp, (char *)0);
      }
    }
    ctx->action = ACT_DONE;
    return;

  case READY(NUMVAL):
    UPLEFT;
    {
      word x = lastarg;
      word base = 10;
      while (x != NIL) {
        hd(x) = reduce(hd(x)),
            x = tl(x) = reduce(tl(x));
      }
      while (lastarg != NIL && isspace(hd(lastarg))) {
        lastarg = tl(lastarg);
      }
      x = lastarg;
      if (x != NIL && hd(x) == '-') {
        x = tl(x);
      }
      if (hd(x) == '0' && tl(x) != NIL) {
        switch (tolower(hd(tl(x)))) {
        case 'o':
          base = 8;
          x = tl(tl(x));
          while (x != NIL && isodigit(hd(x))) {
            x = tl(x);
          }
          break;
        case 'x':
          base = 16;
          x = tl(tl(x));
          while (x != NIL && isxdigit(hd(x))) {
            x = tl(x);
          }
          break;
        default:
          goto L;
        }
      } else {
      L:
        while (x != NIL && isdigit(hd(x))) {
          x = tl(x);
        }
      }
      if (x == NIL) {
        hd(e) = I, e = tl(e) = strtobig(lastarg, base);
      } else {
        char *p = linebuf;
        double d;
        char junk = 0;
        x = lastarg;
        while (x != NIL && p - linebuf < BUFSIZE - 1) {
          *p++ = hd(x), x = tl(x);
        }
        *p++ = '\0';
        if (p - linebuf > 60 || sscanf(linebuf, "%lf%c", &d, &junk) != 1 || junk) {
          fprintf(stderr, "\nbad arg for numval: \"%s\"\n", linebuf);
          outstats();
          exit(1);
        } else {
          hd(e) = I, e = tl(e) = sto_dbl(d);
        }
      }
      ctx->action = ACT_DONE;
      return;
    }

  case READY(STARTREAD):
    UPLEFT;
    {
      char *fil;
      lastarg = (word)fopen(fil = getstring(lastarg, "read"), "r");
      if ((FILE *)lastarg == NULL) {
        fprintf(stderr, "\nread, cannot open: \"%s\"\n", fil);
        outstats();
        exit(1);
      }
      hd(e) = READ;
      DOWNLEFT;
    }
    handle_READ(ctx);
    return;

  case READY(STARTREADBIN):
    UPLEFT;
    {
      char *fil;
      lastarg = (word)fopen(fil = getstring(lastarg, "readb"), "r");
      if ((FILE *)lastarg == NULL) {
        fprintf(stderr, "\nreadb, cannot open: \"%s\"\n", fil);
        outstats();
        exit(1);
      }
      hd(e) = READBIN;
      DOWNLEFT;
    }
    handle_READBIN(ctx);
    return;

  case READY(TRY):
    GETARG(arg1);
    UPLEFT;
    if (arg1 == FAIL) {
      e = rewrite_to_existing_tail(e);
      ctx->action = ACT_NEXTREDEX;
      return;
    }
    if (S <= (hold = head(arg1)) && hold <= ERROR) {
      ctx->action = ACT_DONE;
      return;
    }
    rewrite_to_value(&e, arg1);
    ctx->action = ACT_NEXTREDEX;
    return;

  case READY(COND):
    UPLEFT;
    if (lastarg == True) {
      rewrite_to_value(&e, K);
      zig_handleK(ctx);
    } else {
      rewrite_to_value(&e, KI);
      zig_handleKI(ctx);
    }
    return;

  case READY(APPEND):
    GETARG(arg1);
    upleft;
    if (arg1 == NIL) {
      e = rewrite_to_existing_tail(e);
      ctx->action = ACT_NEXTREDEX;
      return;
    }
    setcell(CONS, hd(arg1), ap2(APPEND, tl(arg1), lastarg));
    ctx->action = ACT_DONE;
    return;

  case READY(AND):
    UPLEFT;
    if (lastarg == True) {
      e = I;
      handle_strict_monadic(ctx);
    } else {
      hd(e) = K, DOWNLEFT;
      zig_handleK(ctx);
    }
    return;

  case READY(OR):
    UPLEFT;
    if (lastarg == True) {
      hd(e) = K;
      DOWNLEFT;
      zig_handleK(ctx);
    } else {
      e = I;
      handle_strict_monadic(ctx);
    }
    return;

  case READY(NOT):
    UPLEFT;
    rewrite_to_value(&e, lastarg == True ? False : True);
    ctx->action = ACT_DONE;
    return;

  case READY(NEG):
    UPLEFT;
    if (is_int(lastarg)) {
      simpl(bignegate(lastarg));
    } else {
      setdbl(e, -get_dbl(lastarg));
    }
    ctx->action = ACT_DONE;
    return;

  case READY(CODE):
    UPLEFT;
    simpl(make(INT, get_char(lastarg), 0));
    ctx->action = ACT_DONE;
    return;

  case READY(DECODE):
    UPLEFT;
    if (is_double(lastarg)) {
      int_error("decode");
    }
    {
      long long val = get_int(lastarg);
      if (val < 0 || val > UMAX) {
        fprintf(stderr, "\nCHARACTER OUT-OF-RANGE decode(%lld)\n", val);
        outstats();
        exit(1);
      }
      hd(e) = I;
      e = tl(e) = sto_char(val);
    }
    ctx->action = ACT_DONE;
    return;

  case READY(INTEGER):
    UPLEFT;
    rewrite_to_value(&e, is_int(lastarg) ? True : False);
    ctx->action = ACT_NEXTREDEX;
    return;

  case READY(SHOWNUM):
    UPLEFT;
    if (is_double(lastarg)) {
      double x = get_dbl(lastarg);
#ifndef RYU
      sprintf(linebuf, "%.16g", x);
      {
        char *p = linebuf;
        while (isdigit((int)*p)) {
          p++;
        }
        if (!*p) {
          *p++ = '.', *p++ = '0', *p = '\0';
        }
      }
      rewrite_to_string(&e, linebuf);
#else
      d2s_buffered(x, linebuf);
      arg1 = str_conv(linebuf);
      if (*linebuf == '.')
        arg1 = cons('0', arg1);
      if (*linebuf == '-' && linebuf[1] == '.')
        arg1 = cons('-', cons('0', tl(arg1)));
      rewrite_to_value(&e, arg1);
#endif
    }
    else {
      simpl(bigtostr(lastarg));
    }
    ctx->action = ACT_DONE;
    return;

  case READY(SHOWHEX):
    UPLEFT;
    if (is_double(lastarg)) {
      sprintf(linebuf, "%a", get_dbl(lastarg));
      rewrite_to_string(&e, linebuf);
    } else {
      simpl(bigtostrx(lastarg));
    }
    ctx->action = ACT_DONE;
    return;

  case READY(SHOWOCT):
    UPLEFT;
    if (is_double(lastarg)) {
      int_error("showoct");
    } else {
      simpl(bigtostr8(lastarg));
    }
    ctx->action = ACT_DONE;
    return;

  case READY(ARCTAN_FN):
    UPLEFT;
    errno = 0;
    setdbl(e, atan(force_dbl(lastarg)));
    if (errno) {
      math_error("atan");
    }
    ctx->action = ACT_DONE;
    return;

  case READY(EXP_FN):
    UPLEFT;
    errno = 0;
    setdbl(e, exp(force_dbl(lastarg)));
    if (errno) {
      math_error("exp");
    }
    ctx->action = ACT_DONE;
    return;

  case READY(ENTIER_FN):
    UPLEFT;
    if (is_int(lastarg)) {
      rewrite_to_value(&e, lastarg);
    } else {
      simpl(dbltobig(get_dbl(lastarg)));
    }
    ctx->action = ACT_DONE;
    return;

  case READY(LOG_FN):
    UPLEFT;
    if (is_int(lastarg)) {
      setdbl(e, biglog(lastarg));
    } else {
      errno = 0;
      fa = force_dbl(lastarg);
      setdbl(e, log(fa));
      if (errno) {
        math_error("log");
      }
    }
    ctx->action = ACT_DONE;
    return;

  case READY(LOG10_FN):
    UPLEFT;
    if (is_int(lastarg)) {
      setdbl(e, biglog10(lastarg));
    } else {
      errno = 0;
      fa = force_dbl(lastarg);
      setdbl(e, log10(fa));
      if (errno) {
        math_error("log10");
      }
    }
    ctx->action = ACT_DONE;
    return;

  case READY(SIN_FN):
    UPLEFT;
    errno = 0;
    setdbl(e, sin(force_dbl(lastarg)));
    if (errno) {
      math_error("sin");
    }
    ctx->action = ACT_DONE;
    return;

  case READY(COS_FN):
    UPLEFT;
    errno = 0;
    setdbl(e, cos(force_dbl(lastarg)));
    if (errno) {
      math_error("cos");
    }
    ctx->action = ACT_DONE;
    return;

  case READY(SQRT_FN):
    UPLEFT;
    fa = force_dbl(lastarg);
    if (fa < 0.0) {
      math_error("sqrt");
    }
    setdbl(e, sqrt(fa));
    ctx->action = ACT_DONE;
    return;

  case READY(ZIP):
    RESTORE(e);
    GETARG(arg1);
    GETARG(arg2);
    if (arg1 == NIL || arg2 == NIL) {
      rewrite_to_nil(&e);
      ctx->action = ACT_DONE;
      return;
    }
    setcell(CONS, cons(hd(arg1), hd(arg2)), ap2(ZIP, tl(arg1), tl(arg2)));
    ctx->action = ACT_DONE;
    return;

  case READY(EQ):
    RESTORE(e);
    GETARG(arg1);
    UPLEFT;
    rewrite_to_compare_eq(&e, arg1, lastarg);
    ctx->action = ACT_DONE;
    return;

  case READY(NEQ):
    RESTORE(e);
    GETARG(arg1);
    UPLEFT;
    rewrite_to_compare_neq(&e, arg1, lastarg);
    ctx->action = ACT_DONE;
    return;

  case READY(GR):
    RESTORE(e);
    GETARG(arg1);
    UPLEFT;
    rewrite_to_compare_gt(&e, arg1, lastarg);
    ctx->action = ACT_DONE;
    return;

  case READY(GRE):
    RESTORE(e);
    GETARG(arg1);
    UPLEFT;
    rewrite_to_compare_ge(&e, arg1, lastarg);
    ctx->action = ACT_DONE;
    return;

  case READY(PLUS):
    RESTORE(e);
    GETARG(arg1);
    UPLEFT;
    if (is_double(arg1)) {
      setdbl(e, get_dbl(arg1) + force_dbl(lastarg));
    } else if (is_double(lastarg)) {
      setdbl(e, bigtodbl(arg1) + get_dbl(lastarg));
    } else {
      simpl(bigplus(arg1, lastarg));
    }
    ctx->action = ACT_DONE;
    return;

  case READY(MINUS):
    RESTORE(e);
    GETARG(arg1);
    UPLEFT;
    if (is_double(arg1)) {
      setdbl(e, get_dbl(arg1) - force_dbl(lastarg));
    } else if (is_double(lastarg)) {
      setdbl(e, bigtodbl(arg1) - get_dbl(lastarg));
    } else {
      simpl(bigsub(arg1, lastarg));
    }
    ctx->action = ACT_DONE;
    return;

  case READY(TIMES):
    RESTORE(e);
    GETARG(arg1);
    UPLEFT;
    if (is_double(arg1)) {
      setdbl(e, get_dbl(arg1) * force_dbl(lastarg));
    } else if (is_double(lastarg)) {
      setdbl(e, bigtodbl(arg1) * get_dbl(lastarg));
    } else {
      simpl(bigtimes(arg1, lastarg));
    }
    ctx->action = ACT_DONE;
    return;

  case READY(INTDIV):
    RESTORE(e);
    GETARG(arg1);
    UPLEFT;
    if (is_double(arg1) || is_double(lastarg)) {
      int_error("div");
    }
    if (bigzero(lastarg)) {
      div_error();
    }
    simpl(bigdiv(arg1, lastarg));
    ctx->action = ACT_DONE;
    return;

  case READY(FDIV):
    RESTORE(e);
    GETARG(arg1);
    UPLEFT;
    fa = force_dbl(arg1);
    fb = force_dbl(lastarg);
    if (fb == 0.0) {
      div_error();
    }
    setdbl(e, fa / fb);
    ctx->action = ACT_DONE;
    return;

  case READY(MOD):
    RESTORE(e);
    GETARG(arg1);
    UPLEFT;
    if (is_double(arg1) || is_double(lastarg)) {
      int_error("mod");
    }
    if (bigzero(lastarg)) {
      div_error();
    }
    simpl(bigmod(arg1, lastarg));
    ctx->action = ACT_DONE;
    return;

  case READY(POWER):
    RESTORE(e);
    GETARG(arg1);
    UPLEFT;
    if (is_double(lastarg)) {
      fa = force_dbl(arg1);
      if (fa < 0.0) {
        errno = EDOM, math_error("^");
      }
      fb = get_dbl(lastarg);
    } else if (is_double(arg1)) {
      fa = get_dbl(arg1), fb = bigtodbl(lastarg);
    } else if (neg(lastarg)) {
      fa = bigtodbl(arg1), fb = bigtodbl(lastarg);
    } else {
      simpl(bigpow(arg1, lastarg));
      ctx->action = ACT_DONE;
      return;
    }
    errno = 0;
    setdbl(e, pow(fa, fb));
    if (errno) {
      math_error("power");
    }
    ctx->action = ACT_DONE;
    return;

  case READY(SHOWSCALED):
    RESTORE(e);
    GETARG(arg1);
    UPLEFT;
    if (is_double(arg1)) {
      int_error("showscaled");
    }
    arg1 = getsmallint(arg1);
    (void)sprintf(linebuf, "%.*e", (int)arg1, force_dbl(lastarg));
    rewrite_to_string(&e, linebuf);
    ctx->action = ACT_DONE;
    return;

  case READY(SHOWFLOAT):
    RESTORE(e);
    GETARG(arg1);
    UPLEFT;
    if (is_double(arg1)) {
      int_error("showfloat");
    }
    arg1 = getsmallint(arg1);
    (void)sprintf(linebuf, "%.*f", (int)arg1, force_dbl(lastarg));
    rewrite_to_string(&e, linebuf);
    ctx->action = ACT_DONE;
    return;

  case READY(STEP):
    RESTORE(e);
    GETARG(arg1);
    UPLEFT;
    hd(e) = ap(GENSEQ, cons(arg1, NIL));
    ctx->action = ACT_NEXTREDEX;
    return;

  case READY(MERGE):
    RESTORE(e);
    GETARG(arg1);
    UPLEFT;
    if (arg1 == NIL) {
      rewrite_to_value(&e, lastarg);
    } else if (lastarg == NIL) {
      rewrite_to_value(&e, arg1);
    } else if (compare(hd(arg1) = reduce(hd(arg1)), hd(lastarg) = reduce(hd(lastarg))) <= 0) {
      setcell(CONS, hd(arg1), ap2(MERGE, tl(arg1), lastarg));
    } else {
      setcell(CONS, hd(lastarg), ap2(MERGE, tl(lastarg), arg1));
    }
    ctx->action = ACT_DONE;
    return;

  case READY(STEPUNTIL):
    RESTORE(e);
    GETARG(arg1);
    GETARG(arg2);
    UPLEFT;
    hd(e) = ap(GENSEQ, cons(arg1, arg2));
    if (is_int(arg1) ? poz(arg1) : get_dbl(arg1) >= 0.0) {
      tag[tl(hd(e))] = AP;
    }
    ctx->action = ACT_NEXTREDEX;
    return;

  case READY(Ush):
    RESTORE(e);
    GETARG(arg1);
    GETARG(arg2);
    GETARG(arg3);
    if (constr_tag(head(arg1)) != constr_tag(head(arg3))) {
      rewrite_to_fail(&e);
      ctx->action = ACT_DONE;
      return;
    }
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
      hold = cons(' ', ap2(APPEND, ap(tl(arg1), tl(arg3)), hold)), arg1 = hd(arg1), arg3 = hd(arg3);
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
    return;

  default:
    fprintf(stderr, "\nimpossible event in reduce ("), out_here(stderr, e, 0), fprintf(stderr, ")\n"),
        exit(1);
  }
}
