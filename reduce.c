/* MIRANDA REDUCE     */
/* new SK reduction machine - installed Oct 86 */
/* Owns graph reduction, primitive combinator execution, I/O primitives,
   printing of reduced values, and runtime error reporting. */

/**************************************************************************
 * Copyright (C) Research Software Limited 1985-90.  All rights reserved. *
 * The Miranda system is distributed as free software under the terms in  *
 * the file "COPYING" which is included in the distribution.              *
 *                                                                        *
 * Revised to C11 standard and made 64bit compatible, January 2020        *
 *------------------------------------------------------------------------*/

#include <stdlib.h>
#include <errno.h>
#include <sys/types.h>
#include <sys/stat.h>
static struct stat buf; /* used only by code for FILEMODE, FILESTAT in reduce */
#include "data.h"
#include "big.h"
#include "lex.h"
extern int debug, UTF8, UTF8OUT;
#define FST HD
#define SND TL
#define BSDCLOCK
/* POSIX clock wraps around after c. 72 mins */
#ifdef RYU
char *d2s(double);
word d2s_buffered(double, char *);
#endif

static double fa, fb;
extern long long cycles;
extern word stdinuse;
extern word outfilq;
extern word waiting;
extern FILE *s_out;
extern word errtrap;

extern void apfile(word f);
extern void closefile(word f);
extern int compare(word a, word b);
extern void div_error(void);
extern void fn_error(char *s);
extern void force(word x);
extern void getenv_error(char *a);
extern word g_residue(word toks2);
extern void int_error(char *s);
extern void lexfail(word x);
extern word lexstate(word x);
extern int memclass(int c, word x);
extern word numplus(word x, word y);
extern void outf(word e);
extern word piperrmess(word pid);
extern void print(word e);
extern void stdin_error(int c);
extern void subs_error(void);
extern void initclock(void);
extern void outstats(void);
extern void out_here(FILE *f, word h, word nl);
extern void output(word e);
extern void math_error(char *s);
extern word head(word x);

#define constr_tag(x) hd(x)
#define idconstr_tag(x) hd(id_val(x))
#define constr_name(x) (tag[tl(x)] == ID ? get_id(tl(x)) : get_id(pn_val(tl(x))))
#define suppressed(x) (tag[tl(x)] == STRCONS && tag[pn_val(tl(x))] != ID)
/* suppressed constructor */

#define isodigit(x) ('0' <= (x) && (x) <= '7')
#define sign(x) (x)
#define fsign(x) ((d = (x)) < 0 ? -1 : d > 0)
/* ### */ /* functions marked ### contain possibly recursive calls
             to reduce - fix later */

/* pointer-reversing SK reduction machine - based on code written Sep 83 */

#define READY(x) (x)
#define RESTORE(x)
/* in this machine the above two are no-ops, alternate definitions are, eg
#define READY(x) (x+1)
#define RESTORE(x) x--
(if using this method each strict comb needs next opcode unallocated)
   see comment before "ready" switch */
#define mktlptr(x) x |= tlptrbit
#define mk1tlptr x |= tlptrbits
#define mknormal(x) x &= ~tlptrbits
#define abnormal(x) ((x) < 0)
/* covers x is tlptr and x==BACKSTOP */

/* control abstractions */

#define setcell(t, a, b) tag[e] = t, hd(e) = a, tl(e) = b
#define DOWNLEFT hold = s, s = e, e = hd(e), hd(s) = hold
#define DOWNRIGHT hold = hd(s), hd(s) = e, e = tl(s), tl(s) = hold, mktlptr(s)
#define downright                                                                                  \
  if (abnormal(s))                                                                                 \
    goto DONE;                                                                                     \
  DOWNRIGHT
#define UPLEFT hold = s, s = hd(s), hd(hold) = e, e = hold
#define upleft                                                                                     \
  if (abnormal(s))                                                                                 \
    goto DONE;                                                                                     \
  UPLEFT
#define GETARG(a) UPLEFT, a = tl(e)
#define getarg(a)                                                                                  \
  upleft;                                                                                          \
  a = tl(e)
#define UPRIGHT mknormal(s), hold = tl(s), tl(s) = e, e = hd(s), hd(s) = hold
#define lastarg tl(e)

/* IMPORTANT WARNING - the macro's
     `downright;' `upleft;' `getarg;'
   MUST BE ENCLOSED IN BRACES when they occur as the body of a control
   structure (if, while etc.) */

#define simpl(r) hd(e) = I, e = tl(e) = r

#ifdef DEBUG
word maxrdepth = 0, rdepth = 0;
#endif

#define fails(x) (x == NIL)
#define FAILURE NIL
/* used by grammar combinators */

static void rewrite_to_value(word *expr, word value) {
  hd(*expr) = I;
  *expr = tl(*expr) = value;
}

static void rewrite_to_nil(word *expr) {
  rewrite_to_value(expr, NIL);
}

static void rewrite_to_fail(word *expr) {
  rewrite_to_value(expr, FAIL);
}

static void rewrite_to_failure(word *expr) {
  rewrite_to_value(expr, FAILURE);
}

static void rewrite_to_cons_head(word expr, word head_value) {
  tag[expr] = CONS;
  hd(expr) = head_value;
}

static void rewrite_to_cons(word expr, word head_value, word tail_value) {
  tag[expr] = CONS;
  hd(expr) = head_value;
  tl(expr) = tail_value;
}

static word rewrite_to_existing_tail(word expr) {
  hd(expr) = I;
  return tl(expr);
}

static void rewrite_to_match_result(word *expr, word left, word right, word success_value) {
  hd(*expr) = I;
  *expr = tl(*expr) = compare(left, right) ? FAIL : success_value;
}

static void rewrite_to_int_match_result(word *expr, word literal, word value, word success_value) {
  hd(*expr) = I;
  *expr = tl(*expr) = (tag[value] != INT || bigcmp(literal, value)) ? FAIL : success_value;
}

static void rewrite_to_compare_eq(word *expr, word left, word right) {
  hd(*expr) = I;
  *expr = tl(*expr) = compare(left, right) ? False : True;
}

static void rewrite_to_compare_neq(word *expr, word left, word right) {
  hd(*expr) = I;
  *expr = tl(*expr) = compare(left, right) ? True : False;
}

static void rewrite_to_compare_gt(word *expr, word left, word right) {
  hd(*expr) = I;
  *expr = tl(*expr) = compare(left, right) > 0 ? True : False;
}

static void rewrite_to_compare_ge(word *expr, word left, word right) {
  hd(*expr) = I;
  *expr = tl(*expr) = compare(left, right) >= 0 ? True : False;
}

static void rewrite_to_string(word *expr, const char *value) {
  hd(*expr) = I;
  *expr = tl(*expr) = str_conv(value);
}

extern void reduce_badcase_error(word arg_info);
extern void reduce_conf_error(word arg_info);
extern void reduce_parse_close_error(word arg1, word arg3);

enum reduce_action {
  REDUCE_NOT_HANDLED,
  REDUCE_NEXT,
  REDUCE_DONE,
  REDUCE_RETURN
};

struct reduce_ctx {
  word e;
  word s;
  word hold;
  word arg1;
  word arg2;
  word arg3;
};

extern enum reduce_action reduce_stream_read(struct reduce_ctx *ctx, word op);



/* reduce e to hnf, note that a function in hnf will have head h with
   S<=h<=ERROR all combinators lie in this range see combs.h */
word reduce(word e) {
  word s = BACKSTOP, hold, arg1, arg2, arg3;
#ifdef DEBUG
  if (++rdepth > maxrdepth)
    maxrdepth = rdepth;
  if (debug & 0x2)
    printf("reducing: "), out(stdout, e), putchar('\n');
#endif

NEXTREDEX:
  while (!abnormal(e) && tag[e] == AP) {
    DOWNLEFT;
  }
#ifdef HISTO
  histo(e);
#endif
#ifdef DEBUG
  if (debug & 0x2) {
    printf("head= ");
    if (e == BACKSTOP)
      printf("BACKSTOP");
    else
      out(stdout, e);
    putchar('\n');
  }
#endif

  /*OPDECODE:*/
  cycles++;
  switch (e) {
  case S: /*  S f g x => f x(g x)  */
    getarg(arg1);
    getarg(arg2);
    upleft;
    hd(e) = ap(arg1, lastarg);
    tl(e) = ap(arg2, lastarg);
    DOWNLEFT;
    DOWNLEFT;
    goto NEXTREDEX;

  case B: /*  B f g x => f(g z)  */
    getarg(arg1);
    getarg(arg2);
    upleft;
    hd(e) = arg1;
    tl(e) = ap(arg2, lastarg);
    DOWNLEFT;
    goto NEXTREDEX;

  case CB: /*  CB f g x => g(f z)  */
    getarg(arg1);
    getarg(arg2);
    upleft;
    hd(e) = arg2;
    tl(e) = ap(arg1, lastarg);
    DOWNLEFT;
    goto NEXTREDEX;

  case C: /*  C f g x => f x g  */
    getarg(arg1);
    getarg(arg2);
    upleft;
    hd(e) = ap(arg1, lastarg);
    tl(e) = arg2;
    DOWNLEFT;
    DOWNLEFT;
    goto NEXTREDEX;

  case Y: /*  Y h => self where self=(h self)  */
    upleft;
    hd(e) = tl(e);
    tl(e) = e;
    DOWNLEFT;
    goto NEXTREDEX;

  L_K:
  case K: /*  K x y => x */
    getarg(arg1);
    upleft;
    rewrite_to_value(&e, arg1);
    goto NEXTREDEX; /* could make eager in first arg */

  L_KI:
  case KI:  /*  KI x y => y  */
    upleft; /* lose first arg  */
    upleft;
    e = rewrite_to_existing_tail(e); /* ?? */
    goto NEXTREDEX; /* could make eager in 2nd arg */

  case S1: /* S1 k f g x => k(f x)(g x) */
    getarg(arg1);
    getarg(arg2);
    getarg(arg3);
    upleft;
    hd(e) = ap(arg2, lastarg);
    hd(e) = ap(arg1, hd(e));
    tl(e) = ap(arg3, lastarg);
    DOWNLEFT;
    DOWNLEFT;
    goto NEXTREDEX;

  case B1:        /* B1 k f g x => k(f(g x)) */
    getarg(arg1); /* Mark Scheevel's new B1 */
    getarg(arg2);
    getarg(arg3);
    upleft;
    hd(e) = arg1;
    tl(e) = ap(arg3, lastarg);
    tl(e) = ap(arg2, tl(e));
    DOWNLEFT;
    goto NEXTREDEX;

  case C1: /* C1 k f g x => k(f x)g */
    getarg(arg1);
    getarg(arg2);
    getarg(arg3);
    upleft;
    hd(e) = ap(arg2, lastarg);
    hd(e) = ap(arg1, hd(e));
    tl(e) = arg3;
    DOWNLEFT;
    goto NEXTREDEX;

  case S_p: /*    S_p f g x => (f x) : (g x)  */
    getarg(arg1);
    getarg(arg2);
    upleft;
    setcell(CONS, ap(arg1, lastarg), ap(arg2, lastarg));
    goto DONE;

  case B_p: /*    B_p f g x => f : (g x)      */
    getarg(arg1);
    getarg(arg2);
    upleft;
    setcell(CONS, arg1, ap(arg2, lastarg));
    goto DONE;

  case C_p: /*    C_p f g x => (f x) : g      */
    getarg(arg1);
    getarg(arg2);
    upleft;
    setcell(CONS, ap(arg1, lastarg), arg2);
    goto DONE;

  case ITERATE: /*  ITERATE f x => x:ITERATE f (f x)  */
    getarg(arg1);
    upleft;
    hold = ap(hd(e), ap(arg1, lastarg));
    rewrite_to_cons(e, lastarg, hold);
    goto DONE;

  case ITERATE1: /*  ITERATE1 f x => [], x=FAIL
                                  => x:ITERATE1 f (f x), otherwise  */
    getarg(arg1);
    upleft;
    if ((lastarg = reduce(lastarg)) == FAIL) /* ### */
    {
      rewrite_to_nil(&e);
    } else {
      hold = ap(hd(e), ap(arg1, lastarg));
      rewrite_to_cons(e, lastarg, hold);
    }
    goto DONE;

  case G_RULE:
  case P: /* P x y => x:y  */
    getarg(arg1);
    upleft;
    rewrite_to_cons(e, arg1, lastarg);
    goto DONE;

  case U: /*    U f x => f (HD x) (TL x)
                non-strict uncurry           */
    getarg(arg1);
    upleft;
    hd(e) = ap(arg1, ap(HD, lastarg));
    tl(e) = ap(TL, lastarg);
    DOWNLEFT;
    DOWNLEFT;
    goto NEXTREDEX;

  case Uf: /*    Uf f x => f (BODY x) (LAST x)
                 version of non-strict U for
                 arbitrary constructors       */
    getarg(arg1);
    upleft;
    if (tag[head(lastarg)] == CONSTRUCTOR) { /* be eager if safe */
      hd(e) = ap(arg1, hd(lastarg)), tl(e) = tl(lastarg);
    } else {
      hd(e) = ap(arg1, ap(BODY, lastarg)), tl(e) = ap(LAST, lastarg);
    }
    DOWNLEFT;
    DOWNLEFT;
    goto NEXTREDEX;

  case ATLEAST: /* ATLEAST k f x => f(x-k), isnat x & x>=k
                                 => FAIL, otherwise        */
                /* for matching n+k patterns */
    getarg(arg1);
    getarg(arg2);
    upleft;
    lastarg = reduce(lastarg); /* ### */
    if (tag[lastarg] == INT) {
      hold = bigsub(lastarg, arg1);
      if (poz(hold)) {
        hd(e) = arg2, tl(e) = hold;
      } else {
        rewrite_to_fail(&e);
      }
    } else {
      rewrite_to_fail(&e);
    }
    goto NEXTREDEX;

  case U_: /*    U_ f (a:b) => f a b
                 U_ f other => FAIL
             U_ is a strict version of U(see above)   */
    getarg(arg1);
    upleft;
    lastarg = reduce(lastarg); /* ### */
    if (lastarg == NIL) {
      rewrite_to_fail(&e);
      goto NEXTREDEX;
    }
    hd(e) = ap(arg1, hd(lastarg));
    tl(e) = tl(lastarg);
    goto NEXTREDEX;

  case Ug: /*  Ug k f (k x1 ... xn) => f x1 ... xn, n>=0
               Ug k f other => FAIL
           Ug is a strict version of U for arbitrary constructor k */
    getarg(arg1);
    getarg(arg2);
    upleft;
    lastarg = reduce(lastarg); /* ### */
    if (constr_tag(arg1) != constr_tag(head(lastarg))) {
      rewrite_to_fail(&e);
      goto NEXTREDEX;
    }
    if (tag[lastarg] == CONSTRUCTOR) /* case n=0 */
    {
      rewrite_to_value(&e, arg2);
      goto NEXTREDEX;
    }
    hd(e) = hd(lastarg);
    tl(e) = tl(lastarg);
    while (tag[hd(e)] != CONSTRUCTOR)
    /* go back to head of arg3, copying spine */
    {
      hd(e) = ap(hd(hd(e)), tl(hd(e)));
      DOWNLEFT;
    }
    hd(e) = arg2; /* replace k with f */
    goto NEXTREDEX;

  case MATCH: /*    MATCH a f a => f
                    MATCH a f b => FAIL    */
    upleft;
    arg1 = lastarg = reduce(lastarg); /* ### */
    /* note that MATCH evaluates arg1, usually needless, could have second
       version - MATCHEQ, say */
    getarg(arg2);
    upleft;
    lastarg = reduce(lastarg); /* ### */
    rewrite_to_match_result(&e, arg1, lastarg, arg2);
    goto NEXTREDEX;

  case MATCHINT: /* same but 1st arg is integer literal */
    getarg(arg1);
    getarg(arg2);
    upleft;
    lastarg = reduce(lastarg); /* ### */
    rewrite_to_int_match_result(&e, arg1, lastarg, arg2);
    /* note no coercion from INT to DOUBLE here */
    goto NEXTREDEX;

  case GENSEQ: /* GENSEQ (i,NIL) a => a:GENSEQ (i,NIL) (a+i)
                  GENSEQ (i,b) a => [], a>b=sign
                                 => a:GENSEQ (i,b) (a+i), otherwise
                                    where
                                    sign =  1, i>=0
                                         = -1, otherwise */
    GETARG(arg1);
    UPLEFT;
    if (tl(arg1) != NIL &&
        (tag[arg1] == AP ? compare(lastarg, tl(arg1)) : compare(tl(arg1), lastarg)) > 0) {
      rewrite_to_nil(&e);
    } else {
      hold = ap(hd(e), numplus(lastarg, hd(arg1)));
      rewrite_to_cons(e, lastarg, hold);
    }
    goto DONE;
    /* efficiency hack - tag of arg1 encodes sign of step */

  case MAP: /* MAP f [] => []
               MAP f (a:x) => f a : MAP f x */
    getarg(arg1);
    upleft;
    lastarg = reduce(lastarg); /* ### */
    if (lastarg == NIL) {
      rewrite_to_nil(&e);
    } else {
      hold = ap(hd(e), tl(lastarg)), setcell(CONS, ap(arg1, hd(lastarg)), hold);
    }
    goto DONE;

  case FLATMAP: /* funny version of map for compiling zf exps
                   FLATMAP f [] => []
                   FLATMAP f (a:x) => FLATMAP f x, f a=FAIL
                                   => f a ++ FLATMAP f x
                   (FLATMAP was formerly called MAP1) */
    getarg(arg1);
    getarg(arg2);
  L1:
    arg2 = reduce(arg2); /* ### */
    if (arg2 == NIL) {
      rewrite_to_nil(&e);
      goto DONE;
    }
    hold = reduce(hold = ap(arg1, hd(arg2)));
    if (hold == FAIL || hold == NIL) {
      arg2 = tl(arg2);
      goto L1;
    }
    tl(e) = ap(hd(e), tl(arg2));
    hd(e) = ap(APPEND, hold);
    goto NEXTREDEX;

  case FILTER: /* FILTER f [] => []
                  FILTER f (a:x) => a : FILTER f x, f a
                                 => FILTER f x, otherwise */
    getarg(arg1);
    upleft;
    lastarg = reduce(lastarg);                                         /* ### */
    while (lastarg != NIL && reduce(ap(arg1, hd(lastarg))) == False) { /* ### */
      lastarg = reduce(tl(lastarg));                                   /* ### */
    }
    if (lastarg == NIL) {
      rewrite_to_nil(&e);
    } else {
      hold = ap(hd(e), tl(lastarg)), setcell(CONS, hd(lastarg), hold);
    }
    goto DONE;

  case LIST_LAST: /* LIST_LAST x  =>  x!(#x-1)  */
    upleft;
    if ((lastarg = reduce(lastarg)) == NIL) {
      fn_error("last []"); /* ### */
    }
    while ((tl(lastarg) = reduce(tl(lastarg))) != NIL) { /* ### */
      lastarg = tl(lastarg);
    }
    rewrite_to_value(&e, hd(lastarg));
    goto NEXTREDEX;

  case LENGTH: /*  takes length of a list */
    upleft;
    {
      long long n = 0; /* problem - may be followed by gc */
      /* cannot make static because of ### below */
      while ((lastarg = reduce(lastarg)) != NIL) { /* ### */
        lastarg = tl(lastarg), n++;
      }
      simpl(sto_int(n));
    }
    goto DONE;

  case DROP:
    getarg(arg1);
    upleft;
    arg1 = tl(hd(e)) = reduce(tl(hd(e))); /* ### */
    if (tag[arg1] != INT) {
      int_error("drop");
    }
    {
      long long n = get_int(arg1);
      while (n-- > 0) {
        if ((lastarg = reduce(lastarg)) == NIL) /* ### */
        {
          rewrite_to_nil(&e);
          goto DONE;
        } else {
          {
            lastarg = tl(lastarg);
          }
        }
      }
    }
    rewrite_to_value(&e, lastarg);
    goto NEXTREDEX;

  case SUBSCRIPT: /* SUBSCRIPT i x  =>  x!i  */
    upleft;
    upleft;
    arg1 = tl(hd(e)) = reduce(tl(hd(e))); /* ### */
    lastarg = reduce(lastarg);            /* ### */
    if (lastarg == NIL) {
      subs_error();
    }
    {
      long long indx = 0; /* 0 is not used but int_error() calls exit() */
      if (tag[arg1] == ATOM) {
        indx = arg1; /* small indexes represented directly */
      } else if (tag[arg1] == INT) {
        indx = get_int(arg1);
      } else {
        int_error("!");
      }
      /* problem, indx may be followed by gc
         - cannot make static, because of ### below */
      if (indx < 0) {
        subs_error();
      }
      while (indx) {
        lastarg = tl(lastarg) = reduce(tl(lastarg)); /* ### */
        if (lastarg == NIL) {
          subs_error();
        }
        indx--;
      }
      rewrite_to_value(&e, hd(lastarg)); /* could be eager in tl(e) */
      goto NEXTREDEX;
    }

  case FOLDL1: /* FOLDL1 op (a:x) => FOLDL op a x */
    getarg(arg1);
    upleft;
    if ((lastarg = reduce(lastarg)) != NIL) /* ### */
    {
      hd(e) = ap2(FOLDL, arg1, hd(lastarg));
      tl(e) = tl(lastarg);
      goto NEXTREDEX;
    } else {
      {
        fn_error("foldl1 applied to []");
      }
    }

  case FOLDL: /* FOLDL op r [] => r
                 FOLDL op r (a:x) => FOLDL op (op r a)^ x

                 ^ (FOLDL op) is made strict in 1st param */
    getarg(arg1);
    getarg(arg2);
    upleft;
    while ((lastarg = reduce(lastarg)) != NIL) {   /* ### */
      arg2 = reduce(ap2(arg1, arg2, hd(lastarg))), /* ^ ### */
          lastarg = tl(lastarg);
    }
    rewrite_to_value(&e, arg2);
    goto NEXTREDEX;

  case FOLDR: /* FOLDR op r [] => r
                 FOLDR op r (a:x) => op a (FOLDR op r x) */
    getarg(arg1);
    getarg(arg2);
    upleft;
    lastarg = reduce(lastarg); /* ### */
    if (lastarg == NIL) {
      rewrite_to_value(&e, arg2);
    } else {
      hold = ap(hd(e), tl(lastarg)), hd(e) = ap(arg1, hd(lastarg)), tl(e) = hold;
    }
    goto NEXTREDEX;

  case READBIN:       /*    READBIN streamptr => nextchar : READBIN streamptr
                            if end of file,    READBIN file => NIL
                            READBIN does no UTF-8 conversion        */
    {
      struct reduce_ctx call_ctx = { .e = e, .s = s, .hold = hold, .arg1 = arg1, .arg2 = arg2, .arg3 = arg3 };
      enum reduce_action act = reduce_stream_read(&call_ctx, READBIN);
      e = call_ctx.e; s = call_ctx.s; hold = call_ctx.hold; arg1 = call_ctx.arg1; arg2 = call_ctx.arg2; arg3 = call_ctx.arg3;
      if (act == REDUCE_DONE) goto DONE;
      if (act == REDUCE_NEXT) goto NEXTREDEX;
    }

  case READ:          /*    READ streamptr => nextchar : READ streamptr
                            if end of file,    READ file => NIL
                            does UTF-8 conversion where appropriate     */
    {
      struct reduce_ctx call_ctx = { .e = e, .s = s, .hold = hold, .arg1 = arg1, .arg2 = arg2, .arg3 = arg3 };
      enum reduce_action act = reduce_stream_read(&call_ctx, READ);
      e = call_ctx.e; s = call_ctx.s; hold = call_ctx.hold; arg1 = call_ctx.arg1; arg2 = call_ctx.arg2; arg3 = call_ctx.arg3;
      if (act == REDUCE_DONE) goto DONE;
      if (act == REDUCE_NEXT) goto NEXTREDEX;
    }

  case READVALS: /*  READVALS (t:fil) f => [], EOF from FILE *f
                                        => val : READVALS t f, otherwise
                     where val is obtained by parsing lines of
                     f, and taking next legal expr of type t */
    {
      struct reduce_ctx call_ctx = { .e = e, .s = s, .hold = hold, .arg1 = arg1, .arg2 = arg2, .arg3 = arg3 };
      enum reduce_action act = reduce_stream_read(&call_ctx, READVALS);
      e = call_ctx.e; s = call_ctx.s; hold = call_ctx.hold; arg1 = call_ctx.arg1; arg2 = call_ctx.arg2; arg3 = call_ctx.arg3;
      if (act == REDUCE_DONE) goto DONE;
      if (act == REDUCE_NEXT) goto NEXTREDEX;
    }

  case BADCASE: /* BADCASE cons(oldn,here_info) => BOTTOM */
    UPLEFT;
    reduce_badcase_error(lastarg);

  case GETARGS: /* GETARGS 0 => argv  ||`$*' = command line args */
    UPLEFT;
    simpl(conv_args());
    goto DONE;

  case CONFERROR: /* CONFERROR error_info => BOTTOM */
    /* if(nargs<1)fprintf(stderr,"\nimpossible event in reduce\n"),
       exit(1); */
    UPLEFT;
    reduce_conf_error(lastarg);

  case ERROR: /* ERROR error_info => BOTTOM */
    upleft;
    if (errtrap) {
      {
        fprintf(stderr, "\n(repeated error)\n");
      }
    } else {
      errtrap = 1;
      fprintf(stderr, "\nprogram error: ");
      s_out = stderr;
      print(lastarg); /* ### */
      putc('\n', stderr);
    }
    outstats();
    exit(1);

  case WAIT: /* WAIT pid => <exit_status of child process pid> */
    UPLEFT;
    {
      word *w = &waiting; /* list of terminated pid's and their exit statuses */
      while (*w != NIL && hd(*w) != lastarg) {
        w = &tl(tl(*w));
      }
      if (*w != NIL) {
        {
          hold = hd(tl(*w)), *w = tl(tl(*w)); /* remove entry */
        }
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
    goto DONE;

  L_I:
    /*  case MONOP:  (all strict monadic operators share this code)  */
  case I: /* we treat I as strict to avoid I-chains (MOD1) */
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
  case ARCTAN_FN: /* ...FN are strict functions of one numeric arg */
  case EXP_FN:
  case ENTIER_FN:
  case LOG_FN:
  case LOG10_FN:
  case SIN_FN:
  case COS_FN:
  case SQRT_FN:
    downright; /* subtask -- reduce arg  */
    goto NEXTREDEX;

  case TRY: /* TRY f g x => TRY(f x)(g x)   */
    getarg(arg1);
    getarg(arg2);
    while (!abnormal(s)) {
      UPLEFT;
      hd(e) = ap(TRY, arg1 = ap(arg1, lastarg));
      arg2 = tl(e) = ap(arg2, lastarg);
    }
    DOWNLEFT;
    /* DOWNLEFT; DOWNRIGHT; equivalent to:*/
    hold = s, s = e, e = tl(e), tl(s) = hold, mktlptr(s); /* now be strict in arg1 */
    goto NEXTREDEX;

  case FAIL: /* FAIL x => FAIL */
    while (!abnormal(s)) {
      hold = s, s = hd(s), hd(hold) = FAIL, tl(hold) = 0;
    }
    goto DONE;

    /*  case DIOP:   (all strict diadic operators share this code)  */
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
    upleft;
    downright; /* first subtask -- reduce arg2  */
    goto NEXTREDEX;

  case Ush: /*  strict in three args */
  case STEPUNTIL:
    upleft;
    upleft;
    downright;
    goto NEXTREDEX; /* first subtask -- reduce arg3 */

  case Ush1: /* non-strict version of Ush */
             /* Ush1 (k f1...fn) p stuff
                       => "k"++' ':f1 x1 ...++' ':fn xn, p='\0'
                       => "(k"++' ':f1 x1 ...++' ':fn xn++")", p='\1'
                          where xi = LAST(BODY^(n-i) stuff) */
    getarg(arg1);
    arg1 = reduce(arg1); /* ### */
    getarg(arg2);
    arg2 = reduce(arg2); /* ### */
    getarg(arg3);
    if (tag[arg1] == CONSTRUCTOR) /* don't parenthesise atom */
    {
      if (suppressed(arg1)) {
        rewrite_to_string(&e, "<unprintable>");
      } else {
        rewrite_to_string(&e, constr_name(arg1));
      }
      goto DONE;
    }
    hold = arg2 ? cons(')', NIL) : NIL;
    while (tag[arg1] != CONSTRUCTOR) {
      hold = cons(' ', ap2(APPEND, ap(tl(arg1), ap(LAST, arg3)), hold)), arg1 = hd(arg1),
      arg3 = ap(BODY, arg3);
    }
    if (suppressed(arg1)) {
      rewrite_to_string(&e, "<unprintable>");
      goto DONE;
    }
    hold = ap2(APPEND, str_conv(constr_name(arg1)), hold);
    if (arg2) {
      setcell(CONS, '(', hold);
      goto DONE;
    } else {
      rewrite_to_value(&e, hold);
      goto NEXTREDEX;
    }

  case MKSTRICT: /* MKSTRICT k f x1 ... xk => f x1 ... xk, xk~=BOT */
    GETARG(arg1);
    getarg(arg2);
    {
      word i = arg1;
      while (i--) {
        upleft;
      }
    }
    lastarg = reduce(lastarg); /* ### */
    while (--arg1)             /* go back towards head, copying spine */
    {
      hd(e) = ap(hd(hd(e)), tl(hd(e)));
      DOWNLEFT;
    }
    hd(e) = arg2; /* overwrite (MKSTRICT k f) with f */
    goto NEXTREDEX;

  case G_ERROR: /* G_ERROR f g toks = (g residue):[], fails(f toks)
                                    = f toks, otherwise */
    GETARG(arg1);
    GETARG(arg2);
    upleft;
    hold = ap(arg1, lastarg);
    hold = reduce(hold); /* ### */
    if (!fails(hold)) {
      rewrite_to_value(&e, hold);
      goto DONE;
    }
    hold = g_residue(lastarg);
    setcell(CONS, ap(arg2, hold), NIL);
    goto DONE;

  case G_ALT: /* G_ALT f g toks = f toks, !fails(f toks)
                                = g toks, otherwise  */
    GETARG(arg1);
    GETARG(arg2);
    upleft;
    hold = ap(arg1, lastarg);
    hold = reduce(hold); /* ### */
    if (!fails(hold)) {
      rewrite_to_value(&e, hold);
      goto DONE;
    }
    hd(e) = arg2;
    DOWNLEFT;
    goto NEXTREDEX;

  case G_OPT: /* G_OPT f toks = []:toks, fails(f toks)
                              = [a]:toks', otherwise
                                where
                                a:toks' = f toks */
    GETARG(arg1);
    upleft;
    hold = ap(arg1, lastarg);
    hold = reduce(hold); /* ### */
    if (fails(hold)) {
      rewrite_to_cons(e, NIL, lastarg);
    } else {
      setcell(CONS, cons(hd(hold), NIL), tl(hold));
    }
    goto DONE;

  case G_STAR: /* G_STAR f toks => []:toks, fails(f toks)
                                => ((a:FST z):SND z)
                                   where
                                   a:toks' = f toks
                                   z = G_STAR f toks'
               */
    GETARG(arg1);
    upleft;
    hold = ap(arg1, lastarg);
    hold = reduce(hold); /* ### */
    if (fails(hold)) {
      rewrite_to_cons(e, NIL, lastarg);
      goto DONE;
    }
    arg2 = ap(hd(e), tl(hold)); /* called z in above rules */
    tag[e] = CONS;
    hd(e) = cons(hd(hold), ap(FST, arg2));
    tl(e) = ap(SND, arg2);
    goto DONE;

    /* G_RULE has same action as P */

  case G_FBSTAR: /* G_FBSTAR f toks
                    = I:toks, if fails(f toks)
                    = G_SEQ (G_FBSTAR f) (G_RULE (CB a)) toks', otherwise
                      where a:toks' = f toks
                 */
    GETARG(arg1);
    upleft;
    hold = ap(arg1, lastarg);
    hold = reduce(hold); /* ### */
    if (fails(hold)) {
      rewrite_to_cons(e, I, lastarg);
      goto DONE;
    }
    hd(e) = ap2(G_SEQ, hd(e), ap(G_RULE, ap(CB, hd(hold))));
    tl(e) = tl(hold);
    goto NEXTREDEX;

  case G_SYMB:    /* G_SYMB t ((t,s):toks) = t:toks
                     G_SYMB t toks = FAILURE  */
    GETARG(arg1); /* will be in NF */
    upleft;
    lastarg = reduce(lastarg); /* ### */
    if (lastarg == NIL) {
      rewrite_to_nil(&e);
      goto DONE;
    }
    hd(lastarg) = reduce(hd(lastarg)); /* ### */
    hold = ap(FST, hd(lastarg));
    if (compare(arg1, reduce(hold))) { /* ### */
      rewrite_to_failure(&e);
    } else {
      setcell(CONS, arg1, tl(lastarg));
    }
    goto DONE;

  case G_ANY: /* G_ANY ((t,s):toks) = t:toks
                 G_ANY [] = FAILURE   */
    upleft;
    lastarg = reduce(lastarg); /* ### */
    if (lastarg == NIL) {
      rewrite_to_failure(&e);
    } else {
      setcell(CONS, ap(FST, hd(lastarg)), tl(lastarg));
    }
    goto DONE;

  case G_SUCHTHAT: /* G_SUCHTHAT f ((t,s):toks) = t:toks, f t
                      G_SUCHTHAT f toks = FAILURE  */
    GETARG(arg1);
    upleft;
    lastarg = reduce(lastarg); /* ### */
    if (lastarg == NIL) {
      rewrite_to_failure(&e);
      goto DONE;
    }
    hold = ap(FST, hd(lastarg));
    hold = reduce(hold);                  /* ### */
    if (reduce(ap(arg1, hold)) == True) { /* ### */
      setcell(CONS, hold, tl(lastarg));
    } else {
      rewrite_to_failure(&e);
    }
    goto DONE;

  case G_END: /* G_END [] = []:[]
                 G_END other = FAILURE */
    upleft;
    lastarg = reduce(lastarg);
    if (lastarg == NIL) {
      rewrite_to_cons(e, NIL, NIL);
    } else {
      rewrite_to_failure(&e);
    }
    goto DONE;

  case G_STATE: /* G_STATE ((t,s):toks) = s:((t,s):toks)
                   G_STATE [] = FAILURE   */
    upleft;
    lastarg = reduce(lastarg); /* ### */
    if (lastarg == NIL) {
      rewrite_to_failure(&e);
    } else {
      setcell(CONS, ap(SND, hd(lastarg)), lastarg);
    }
    goto DONE;

  case G_SEQ: /* G_SEQ f g toks = FAILURE, fails(f toks)
                                = FAILURE, fails(g toks')
                                = b a:toks'', otherwise
                                  where
                                  a:toks' = f toks
                                  b:toks'' = g toks' */
    GETARG(arg1);
    GETARG(arg2);
    upleft;
    hold = ap(arg1, lastarg);
    hold = reduce(hold); /* ### */
    if (fails(hold)) {
      rewrite_to_failure(&e);
      goto DONE;
    }
    arg3 = ap(arg2, tl(hold));
    arg3 = reduce(arg3); /* ### */
    if (fails(arg3)) {
      rewrite_to_failure(&e);
      goto DONE;
    }
    setcell(CONS, ap(hd(arg3), hd(hold)), tl(arg3));
    goto DONE;

  case G_UNIT: /* G_UNIT toks => I:toks */
    upleft;
    rewrite_to_cons_head(e, I);
    goto DONE;
    /* G_UNIT is right multiplicative identity, equivalent (G_RULE I) */

  case G_ZERO: /* G_ZERO toks => FAILURE */
    upleft;
    rewrite_to_failure(&e);
    goto DONE;
    /* G_ZERO is left additive identity */

  case G_CLOSE: /* G_CLOSE s f toks = <error s>, fails(f toks')
                                    = <error s>, toks'' ~= NIL
                                    = a, otherwise
                                      where
                                      toks' = G_COUNT toks
                                      a:toks'' = f toks' */
    GETARG(arg1);
    GETARG(arg2);
    upleft;
    arg3 = ap(G_COUNT, lastarg);
    hold = ap(arg2, arg3);
    hold = reduce(hold); /* ### */
    if (fails(hold)) {
      reduce_parse_close_error(arg1, arg3);
    }
    rewrite_to_value(&e, hd(hold));
    goto NEXTREDEX;
    /* NOTE the atom OFFSIDE differs from every string and is used as a
       pseudotoken when implementing the offside rule - see `indent' in prelude */

  case G_COUNT: /* G_COUNT NIL => NIL
                   G_COUNT (t:toks) => t:G_COUNT toks */
    /* G_COUNT is an identity operation on lists - its purpose is to mark
       last token examined, for syntax error location purposes */
    upleft;
    if ((lastarg = reduce(lastarg)) == NIL) /* ### */
    {
      rewrite_to_nil(&e);
      goto DONE;
    }
    setcell(CONS, hd(lastarg), ap(G_COUNT, tl(lastarg)));
    goto DONE;

    /*  Explanation of %lex combinators.  A lex analyser is of type

            lexer == [char] -> [alpha]

        At top level these are of the form (LEX_RPT f) where f is of type

            lexer1 == startcond -> [char] -> (alpha,startcond,[char])

        A lexer1 is guaranteed to return a triple (if it returns at all...)
        and is built using LEX_TRY.

            LEX_TRY [(scstuff,(matcher [],rule))*] :: lexer1
            rule :: [char] -> alpha
            matcher :: partial_match -> input -> {(alpha,input') | []}

        partial_match and input are both [char] and [] represents failure.
        The other lex combinators - LEX_SEQ, LEX_OR, LEX_CLASS etc., all
        create and combine objects of type matcher.

        LEX_RPT1 is a deviant version that labels the input characters
        with their lexical state (row,col) using LEX_COUNT - goes with
        LEX_TRY1 which feeds the leading state of input to each rule.

    */

  case LEX_RPT1: /* LEX_RPT1 f s x => LEX_RPT f s (LEX_COUNT0 x)
                 i.e. LEX_RPT1 f s => B (LEX_RPT f s) LEX_COUNT0
                 */
    GETARG(arg1);
    UPLEFT;
    hd(e) = ap(B, ap2(LEX_RPT, arg1, lastarg));
    tl(e) = LEX_COUNT0;
    DOWNLEFT;
    DOWNLEFT;
    goto NEXTREDEX;

  case LEX_RPT: /* LEX_RPT f s [] => []
                   LEX_RPT f s x  => a : LEX_RPT f s' y
                                     where
                                     (a,s',y) = f s x
                   note that if f returns a result it is
                   guaranteed to be a triple
                */
    GETARG(arg1);
    GETARG(arg2);
    upleft;
    if ((lastarg = reduce(lastarg)) == NIL) /* ### */
    {
      rewrite_to_nil(&e);
      goto DONE;
    }
    hold = ap2(arg1, arg2, lastarg);
    arg1 = hd(hd(e));
    hold = reduce(hold);
    setcell(CONS, hd(hold), ap2(arg1, hd(tl(hold)), tl(tl(hold))));
    goto DONE;

  case LEX_TRY:
    upleft;
    tl(e) = reduce(tl(e)); /* ### */
    force(tl(e));
    hd(e) = LEX_TRY_;
    DOWNLEFT;
    /* falls thru to next case */

  case LEX_TRY_:
    /* LEX_TRY ((scstuff,(f,rule)):alt) s x => LEX_TRY alt s x, if f x = []
                                            => (rule (rev a),s,y), otherwise
                                               where
                                               (a,y) = f x
       LEX_TRY [] s x => BOTTOM
    */
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
    } /* hd(scstuff) is 0 or list of startconds */
    hold = ap(hd(tl(hd(arg1))), lastarg);
    if ((hold = reduce(hold)) == NIL) /* ### */
    {
      arg1 = tl(arg1);
      goto L2;
    }
    setcell(CONS, ap(tl(tl(hd(arg1))), ap(DESTREV, hd(hold))),
            cons(tl(hd(hd(arg1))) ? tl(hd(hd(arg1))) - 1 : arg2, tl(hold)));
    /* tl(scstuff) is 1 + next start condition (0 = no change) */
    goto DONE;

  case LEX_TRY1:
    upleft;
    tl(e) = reduce(tl(e)); /* ### */
    force(tl(e));
    hd(e) = LEX_TRY1_;
    DOWNLEFT;
    /* falls thru to next case */

  case LEX_TRY1_:
    /* LEX_TRY1 ((scstuff,(f,rule)):alt) s x => LEX_TRY1 alt s x, if f x = []
                                             => (rule n (rev a),s,y), otherwise
                                                where
                                                (a,y) = f x
                                                n = lexstate(x)
       ||same as LEX_TRY but feeds lexstate to rule
    */
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
    } /* hd(scstuff) is 0 or list of startconds */
    hold = ap(hd(tl(hd(arg1))), lastarg);
    if ((hold = reduce(hold)) == NIL) /* ### */
    {
      arg1 = tl(arg1);
      goto L3;
    }
    setcell(CONS, ap2(tl(tl(hd(arg1))), lexstate(lastarg), ap(DESTREV, hd(hold))),
            cons(tl(hd(hd(arg1))) ? tl(hd(hd(arg1))) - 1 : arg2, tl(hold)));
    /* tl(scstuff) is 1 + next start condition (0 = no change) */
    goto DONE;

  case DESTREV:   /* destructive reverse - used only by LEX_TRY */
    GETARG(arg1); /* known to be an explicit list */
    arg2 = NIL;   /* to hold reversed list */
    while (arg1 != NIL) {
      if (tag[hd(arg1)] == STRCONS) { /* strip off lex state if present */
        hd(arg1) = tl(hd(arg1));
      }
      hold = tl(arg1), tl(arg1) = arg2, arg2 = arg1, arg1 = hold;
    }
    rewrite_to_value(&e, arg2);
    goto DONE;

  case LEX_COUNT0: /* LEX_COUNT0 x => LEX_COUNT (state0,x) */
    upleft;
    hd(e) = LEX_COUNT;
    tl(e) = strcons(0, tl(e));
    DOWNLEFT;
    /* falls thru to next case */

  case LEX_COUNT: /* LEX_COUNT (state,[]) => []
                     LEX_COUNT (state,(a:x)) => (state,a):LEX_COUNT(state',a)
                     where
                     state == (line_no*256+col_no)
                  */
    GETARG(arg1);
    if ((tl(arg1) = reduce(tl(arg1))) == NIL) /* ### */
    {
      rewrite_to_nil(&e);
      goto DONE;
    }
    hold = hd(tl(arg1)); /* the char */
    setcell(CONS, strcons(hd(arg1), hold), ap(LEX_COUNT, arg1));
    if (hold == '\n') {
      {
        hd(arg1) = ((hd(arg1) >> 8) + 1) << 8;
      }
    } else {
      word col = hd(arg1) & 255;
      col = hold == '\t' ? ((col / 8) + 1) * 8 : col + 1;
      hd(arg1) = (hd(arg1) & (~255)) | col;
    }
    tl(arg1) = tl(tl(arg1));
    goto DONE;

#define lh(x) (tag[hd(x)] == STRCONS ? tl(hd(x)) : hd(x))
    /* hd char of possibly lex-state-labelled string */

  case LEX_STRING: /*  LEX_STRING [] p x => p : x
                       LEX_STRING (c:s) p (c:x) => LEX_STRING s (c:p) x
                       LEX_STRING (c:s) p other => []
                   */
    GETARG(arg1);
    GETARG(arg2);
    upleft;
    while (arg1 != NIL) {
      if ((lastarg = reduce(lastarg)) == NIL || lh(lastarg) != hd(arg1)) /* ### */
      {
        rewrite_to_nil(&e);
        goto DONE;
      }
      arg1 = tl(arg1);
      arg2 = cons(hd(lastarg), arg2);
      lastarg = tl(lastarg);
    }
    rewrite_to_cons_head(e, arg2);
    goto DONE;

  case LEX_CLASS: /* LEX_CLASS set p (c:x) => (c:p) : x, if c in set
                     LEX_CLASS set p   x   => [], otherwise
                  */
    GETARG(arg1);
    GETARG(arg2);
    upleft;
    if ((lastarg = reduce(lastarg)) == NIL || /* ### */
        (hd(arg1) == ANTICHARCLASS ? memclass(lh(lastarg), tl(arg1))
                                   : !memclass(lh(lastarg), arg1))) {
      rewrite_to_nil(&e);
      goto DONE;
    }
    setcell(CONS, cons(hd(lastarg), arg2), tl(lastarg));
    goto DONE;

  case LEX_DOT: /* LEX_DOT p (c:x) => (c:p) : x
                   LEX_DOT p  []   => []
                */
    GETARG(arg1);
    upleft;
    if ((lastarg = reduce(lastarg)) == NIL) /* ### */
    {
      rewrite_to_nil(&e);
      goto DONE;
    }
    setcell(CONS, cons(hd(lastarg), arg1), tl(lastarg));
    goto DONE;

  case LEX_CHAR: /* LEX_CHAR c p (c:x) => (c:p) : x
                    LEX_CHAR c p  x    => []
                 */
    GETARG(arg1);
    GETARG(arg2);
    upleft;
    if ((lastarg = reduce(lastarg)) == NIL || lh(lastarg) != arg1) /* ### */
    {
      rewrite_to_nil(&e);
      goto DONE;
    }
    setcell(CONS, cons(arg1, arg2), tl(lastarg));
    goto DONE;

  case LEX_SEQ: /* LEX_SEQ f g p x => [], if f p x = []
                                   => g q y, otherwise
                                      where
                                      (q,y) = f p x
                */
    GETARG(arg1);
    GETARG(arg2);
    GETARG(arg3);
    upleft;
    hold = ap2(arg1, arg3, lastarg);
    lastarg = NIL;                    /* anti-dragging measure */
    if ((hold = reduce(hold)) == NIL) /* ### */
    {
      e = rewrite_to_existing_tail(e);
      goto DONE;
    }
    hd(e) = ap(arg2, hd(hold));
    tl(e) = tl(hold);
    DOWNLEFT;
    DOWNLEFT;
    goto NEXTREDEX;

  case LEX_OR: /* LEX_OR f g p x => g p x, if f p x = []
                                 => f p x, otherwise
               */
    GETARG(arg1);
    GETARG(arg2);
    GETARG(arg3);
    upleft;
    hold = ap2(arg1, arg3, lastarg);
    if ((hold = reduce(hold)) == NIL) /* ### */
    {
      hd(e) = ap(arg2, arg3);
      DOWNLEFT;
      DOWNLEFT;
      goto NEXTREDEX;
    }
    rewrite_to_value(&e, hold);
    goto DONE;

  case LEX_RCONTEXT: /* LEX_RC f g p x => [], if f p x = []
                                       => [], if g q y = []
                                       => f p x, otherwise  <-*
                                          where
                                          (q,y) = f p x

                       (*) special case g=0 means test for y=[]
                     */
    GETARG(arg1);
    GETARG(arg2);
    GETARG(arg3);
    upleft;
    hold = ap2(arg1, arg3, lastarg);
    lastarg = NIL;                                                /* anti-dragging measure */
    if ((hold = reduce(hold)) == NIL                              /* ### */
        || (arg2 ? (reduce(ap2(arg2, hd(hold), tl(hold))) == NIL) /* ### */
                 : (tl(hold) = reduce(tl(hold))) != NIL)) {
      e = rewrite_to_existing_tail(e);
      goto DONE;
    }
    rewrite_to_value(&e, hold);
    goto DONE;

  case LEX_STAR: /* LEX_STAR f p x => p : x, if f p x = []
                                   => LEX_STAR f q y, otherwise
                                      where
                                      (q,y) = f p x
                 */
    GETARG(arg1);
    GETARG(arg2);
    upleft;
    hold = ap2(arg1, arg2, lastarg);
    while ((hold = reduce(hold)) != NIL) { /* ### */
      arg2 = hd(hold), lastarg = tl(hold), hold = ap2(arg1, arg2, lastarg);
    }
    rewrite_to_cons_head(e, arg2);
    goto DONE;

  case LEX_OPT: /* LEX_OPT f p x => p : x, if f p x = []
                                 => f p x, otherwise
                 */
    GETARG(arg1);
    GETARG(arg2);
    upleft;
    hold = ap2(arg1, arg2, lastarg);
    if ((hold = reduce(hold)) == NIL) /* ### */
    {
      rewrite_to_cons_head(e, arg2);
      goto DONE;
    }
    rewrite_to_value(&e, hold);
    goto DONE;

  default:           /* non combinator */
    cycles--;        /* oops! */
    if (abnormal(e)) /* silly recursion */
    {
      fprintf(stderr, "\nBLACK HOLE\n");
      outstats();
      exit(1);
    }

    switch (tag[e]) {
    case STRCONS:
      e = pn_val(e); /* private name */
      if (e == UNDEF || e == FREE) {
        fprintf(stderr, "\nimpossible event in reduce - undefined pname\n"), exit(1);
      }
      /* redundant test - remove when sure */
      goto NEXTREDEX;
    case DATAPAIR: /* datapair(oldn,0)(fileinfo(filename,0))=>BOTTOM */
      /* kludge for trapping inherited undefined name without
         current alias - see code in load_defs */
      upleft;
      fprintf(stderr, "\nUNDEFINED NAME (specified as \"%s\" in %s)\n", (char *)hd(hd(e)),
              (char *)hd(lastarg));
      outstats();
      exit(1);
    case ID:
      if (id_val(e) == UNDEF || id_val(e) == FREE) {
        fprintf(stderr, "\nUNDEFINED NAME - %s\n", get_id(e));
        outstats();
        exit(1);
      }
      e = id_val(e); /* could be eager in value */
      goto NEXTREDEX;
    default:
      fprintf(stderr, "\nimpossible tag (%d) in reduce\n", tag[e]);
      exit(1);
    case CONSTRUCTOR:
      for (;;) {
        upleft;
      } /* reapply to args until DONE */
    case STARTREADVALS:
      /* readvals(0,t) file => READVALS (t:file) streamptr */
      {
        char *fil;
        upleft;
        lastarg = reduce(lastarg); /* ### */
        if (lastarg == OFFSIDE)    /* special case, represents stdin */
        {
          if (stdinuse && stdinuse != '+') {
            tag[e] = AP;
            rewrite_to_nil(&e);
            goto DONE;
          }
          stdinuse = '+';
          hold = cons(tl(hd(e)), 0), lastarg = (word)stdin;
        } else {
          hold = cons(tl(hd(e)), lastarg);
          lastarg = (word)fopen(fil = getstring(lastarg, "readvals"), "r");
          if ((FILE *)lastarg == NULL) /* cannot open file for reading */
          /* { hd(e)=I; e=tl(e)=NIL; goto DONE; } */
          {
            fprintf(stderr, "\nreadvals, cannot open: \"%s\"\n", fil);
            outstats();
            exit(1);
          }
        }
        hd(e) = ap(READVALS, hold);
      }
      DOWNLEFT;
      DOWNLEFT;
      {
        struct reduce_ctx call_ctx = { .e = e, .s = s, .hold = hold, .arg1 = arg1, .arg2 = arg2, .arg3 = arg3 };
        enum reduce_action act = reduce_stream_read(&call_ctx, READVALS);
        e = call_ctx.e; s = call_ctx.s; hold = call_ctx.hold; arg1 = call_ctx.arg1; arg2 = call_ctx.arg2; arg3 = call_ctx.arg3;
        if (act == REDUCE_DONE) goto DONE;
        if (act == REDUCE_NEXT) goto NEXTREDEX;
      }
    case ATOM: /* for(;;){upleft; } */
               /* as above if there are constructors with tag ATOM
                  and +ve arity.  Since there are none we could test
                  for missing combinators at this point. Thus:
               if(!abnormal(s))
                  fprintf(stderr,"\nreduce: unknown combinator "),
                  out(stderr,e), putc('\n',stderr),exit(1); */
    case INT:
    case UNICODE:
    case DOUBLE:
    case CONS:; /* all fall thru to DONE */
    }

  } /* end of decode switch  */

DONE: /* sub task completed -- s is either BACKSTOP or a tailpointer */

  if (s == BACKSTOP) { /* whole expression now in hnf */
#ifdef DEBUG
    if (debug & 0x2)
      printf("result= "), out(stdout, e), putchar('\n');
    rdepth--;
#endif
    return e; /* end of reduction */
  }

  /* otherwise deal with return from subtask */
  UPRIGHT;
  if (tag[e] == AP) { /* we have just reduced argn of strict operator -- so now
                         we must reduce arg(n-1) */
    DOWNLEFT;
    DOWNRIGHT; /* there is a faster way to do this - see TRY */
    goto NEXTREDEX;
  }

  /* only possible if mktlptr marks the cell rather than the field */
  /*  if(e==BACKSTOP)
        fprintf(stderr,"\nprogram error: BLACK HOLE2\n"),
        outstats(),
        exit(1); */

  /* we are through reducing args of strict operator */
  /* we can merge the following switch with the main one, if desired,
     - in this case use the alternate definitions of READY and RESTORE
     and replace the following switch by
     e=READY(e); goto OPDECODE; */

#ifdef DEBUG
  if (debug & 0x2) {
    printf("ready(");
    out(stdout, e);
    printf(")\n");
  }
#endif
  switch (e) /* "ready" switch */
  {
    /* paradigm for execution of strict monadic operator
        case READY(MONOP):
        GETARG(arg1);
        hd(e)=I; e=tl(e)=do_monop(arg1);
        goto NEXTREDEX; */

  case READY(I): /*  I x => x */
    UPLEFT;
    e = lastarg;
    goto NEXTREDEX;

  case READY(SEQ): /* SEQ a b => b, a~=BOTTOM  */
    UPLEFT;
    upleft;
    e = rewrite_to_existing_tail(e);
    goto NEXTREDEX;

  case READY(FORCE): /*  FORCE x => x, total x */
    UPLEFT;
    force(lastarg);
    e = rewrite_to_existing_tail(e);
    goto NEXTREDEX;

  case READY(HD):
    UPLEFT;
    if (lastarg == NIL) {
      fprintf(stderr, "\nATTEMPT TO TAKE hd OF []\n");
      outstats();
      exit(1);
    }
    rewrite_to_value(&e, hd(lastarg));
    goto NEXTREDEX;

  case READY(TL):
    UPLEFT;
    if (lastarg == NIL) {
      fprintf(stderr, "\nATTEMPT TO TAKE tl OF []\n");
      outstats();
      exit(1);
    }
    rewrite_to_value(&e, tl(lastarg));
    goto NEXTREDEX;

  case READY(BODY):
    /* BODY(k x1 .. xn) => k x1 ... x(n-1)
       for arbitrary constructor k */
    UPLEFT;
    rewrite_to_value(&e, hd(lastarg));
    goto NEXTREDEX;

  case READY(LAST): /* LAST(k x1 .. xn) => xn
                       for arbitrary constructor k */
    UPLEFT;
    rewrite_to_value(&e, tl(lastarg));
    goto NEXTREDEX;

  case READY(TAKE):
    GETARG(arg1);
    upleft;
    if (tag[arg1] != INT) {
      int_error("take");
    }
    {
      long long n = get_int(arg1);
      if (n <= 0 || (lastarg = reduce(lastarg)) == NIL) /* ### */
      {
        rewrite_to_nil(&e);
        goto DONE;
      }
      setcell(CONS, hd(lastarg), ap2(TAKE, sto_int(n - 1), tl(lastarg)));
    }
    goto DONE;

  case READY(FILEMODE): /* FILEMODE string => string'
                           (see filemode in manual) */
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
    goto DONE;

  case READY(FILESTAT): /* FILESTAT string => ((inode,dev),mtime) */
    UPLEFT;
    /* Notes:
       Non-existent file has conventional ((inode,dev),mtime) of ((0,-1),0)
       We assume time_t can be stored in int field, this may not port   */
    if (!stat(getstring(lastarg, "filestat"), &buf)) {
      setcell(CONS, cons(sto_int(buf.st_ino), sto_int(buf.st_dev)), sto_int(buf.st_mtime));
    } else {
      setcell(CONS, cons(stosmallint(0), stosmallint(-1)), stosmallint(0));
    }
    goto DONE;

  case READY(GETENV): /* GETENV string => string'
                         (see man (2) getenv)    */
    UPLEFT;
    {
      char *a = getstring(lastarg, "getenv");
      unsigned char *p = (unsigned char *)getenv(a);
      hold = NIL;
      if (p) {
        word i;
        if (UTF8) { /* We shouldn't modify what getenv returns as on some systems
                     * it may be a shared area, so copy it and modify the copy */
          unsigned char *qbuf = (unsigned char *)malloc(strlen((char *)p) + 1);
          unsigned char *q;
          unsigned char *r;
          if (qbuf == NULL) {
            mallocfail("getenv");
          }
          strcpy((char *)qbuf, (char *)p);
          q = r = qbuf;
          while (*r) {      /* compress to Latin-1 in situ */
            if (*r > 127) { /* start of multibyte */
              if ((*r == 194 || *r == 195) && r[1] >= 128 && r[1] <= 191) { /* Latin-1 */
                *q = *r == 194 ? r[1] : r[1] + 64, q++, r += 2;
              } else {
                getenv_error(a),
                    /* or silently accept errors here? */
                    *q++ = *r++;
              }
            } else {
              *q++ = *r++;
            }
          }
          *q = '\0';
          /* convert to list */
          i = strlen((char *)qbuf);
          while (i--) {
            hold = cons(qbuf[i], hold);
          }
          free(qbuf);
        } else {
          /* convert to list */
          i = strlen((char *)p);
          while (i--) {
            hold = cons(p[i], hold);
          }
        }
      }
    }
    hd(e) = I;
    e = tl(e) = hold;
    goto DONE;

  case READY(EXEC): /* EXEC string
                       fork off a process to execute string as a
                       shell command, returning (via pipes) the
                       triple (stdout,stderr,exit_status)
                       convention: if fork fails, exit status is -1 */
    UPLEFT;
    {
      int pid = (-1);
      int fd[2];
      int fd_a[2];
      char *cp = getstring(lastarg, "system");
      /* pipe(fd) should return 0, -1 means fail */
      /* fd_a is 2nd pipe, for error messages */
      if (pipe(fd) == (-1) || pipe(fd_a) == (-1) || (pid = fork())) { /* parent (reader) */
        FILE *fp;
        FILE *fp_a;
        if (pid != -1) {
          close(fd[1]), close(fd_a[1]), fp = fdopen(fd[0], "r"), fp_a = fdopen(fd_a[0], "r");
        }
        if (pid == -1 || !fp || !fp_a) {
          setcell(CONS, NIL, cons(piperrmess(pid), sto_int(-1)));
        } else {
          setcell(CONS, ap(READ, fp), cons(ap(READ, fp_a), ap(WAIT, pid)));
        }
      } else { /* child (writer) */
        static char *shell = "/bin/sh";
        dup2(fd[1], 1);   /* so pipe replaces stdout */
        dup2(fd_a[1], 2); /* 2nd pipe replaces stderr */
        close(fd[1]);
        close(fd[0]);
        close(fd_a[1]);
        close(fd_a[0]);
        fclose(stdin); /* anti side-effect measure */
        execl(shell, shell, "-c", cp, (char *)0);
      }
    }
    goto DONE;

  case READY(NUMVAL): /* NUMVAL numeral => number */
    UPLEFT;
    {
      word x = lastarg;
      word base = 10;
      while (x != NIL) {
        hd(x) = reduce(hd(x)),         /* ### */
            x = tl(x) = reduce(tl(x)); /* ### */
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
        {
          hd(e) = I, e = tl(e) = strtobig(lastarg, base);
        }
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
          {
            hd(e) = I, e = tl(e) = sto_dbl(d);
          }
        }
      }
      goto DONE;
    }

  case READY(STARTREAD): /* STARTREAD filename => READ streamptr */
    UPLEFT;
    {
      char *fil;
      lastarg = (word)fopen(fil = getstring(lastarg, "read"), "r");
      if ((FILE *)lastarg == NULL) /* cannot open file for reading  */
      {
        fprintf(stderr, "\nread, cannot open: \"%s\"\n", fil);
        outstats();
        exit(1);
      }
      hd(e) = READ;
      DOWNLEFT;
    }
    {
      struct reduce_ctx call_ctx = { .e = e, .s = s, .hold = hold, .arg1 = arg1, .arg2 = arg2, .arg3 = arg3 };
      enum reduce_action act = reduce_stream_read(&call_ctx, READ);
      e = call_ctx.e; s = call_ctx.s; hold = call_ctx.hold; arg1 = call_ctx.arg1; arg2 = call_ctx.arg2; arg3 = call_ctx.arg3;
      if (act == REDUCE_DONE) goto DONE;
      if (act == REDUCE_NEXT) goto NEXTREDEX;
    }

  case READY(STARTREADBIN): /* STARTREADBIN filename => READBIN streamptr */
    UPLEFT;
    {
      char *fil;
      lastarg = (word)fopen(fil = getstring(lastarg, "readb"), "r");
      if ((FILE *)lastarg == NULL) /* cannot open file for reading  */
      {
        fprintf(stderr, "\nreadb, cannot open: \"%s\"\n", fil);
        outstats();
        exit(1);
      }
      hd(e) = READBIN;
      DOWNLEFT;
    }
    {
      struct reduce_ctx call_ctx = { .e = e, .s = s, .hold = hold, .arg1 = arg1, .arg2 = arg2, .arg3 = arg3 };
      enum reduce_action act = reduce_stream_read(&call_ctx, READBIN);
      e = call_ctx.e; s = call_ctx.s; hold = call_ctx.hold; arg1 = call_ctx.arg1; arg2 = call_ctx.arg2; arg3 = call_ctx.arg3;
      if (act == REDUCE_DONE) goto DONE;
      if (act == REDUCE_NEXT) goto NEXTREDEX;
    }

  case READY(TRY): /* TRY FAIL y => y
                      TRY other y => other  */
    GETARG(arg1);
    UPLEFT;
    if (arg1 == FAIL) {
      e = rewrite_to_existing_tail(e);
      goto NEXTREDEX;
    }
    if (S <= (hold = head(arg1)) && hold <= ERROR) {
      /* function - other than unsaturated constructor */
      goto DONE; /* nb! else may take premature decision(interacts with MOD1)*/
    }
    rewrite_to_value(&e, arg1);
    goto NEXTREDEX;

  case READY(COND): /* COND True => K
                       COND False => KI  */
    UPLEFT;
    if (lastarg == True) {
      rewrite_to_value(&e, K);
      goto L_K;
    } else {
      rewrite_to_value(&e, KI);
      goto L_KI;
    }
    /* goto OPDECODE;   to speed up we have set extra labels */

    /* alternative rules          COND True x => K x
                                  COND False x => I    */

  case READY(APPEND): /* APPEND NIL y => y
                         APPEND (a:x) y => a:APPEND x y  */
    GETARG(arg1);
    upleft;
    if (arg1 == NIL) {
      e = rewrite_to_existing_tail(e);
      goto NEXTREDEX;
    }
    setcell(CONS, hd(arg1), ap2(APPEND, tl(arg1), lastarg));
    goto DONE;

  case READY(AND): /* AND True => I
                      AND False => K False */
    UPLEFT;
    if (lastarg == True) {
      e = I;
      goto L_I;
    } else {
      hd(e) = K, DOWNLEFT;
      goto L_K;
    }

  case READY(OR): /* OR True => K True
                     OR False => I  */
    UPLEFT;
    if (lastarg == True) {
      hd(e) = K;
      DOWNLEFT;
      goto L_K;
    } else {
      e = I;
      goto L_I;
    }

    /* alternative rules     ??         AND True y => y
                                        AND False y => False
                                        OR True y => True
                                        OR False y => y    */

  case READY(NOT): /*    NOT True => False
                         NOT False => True    */
    UPLEFT;
    rewrite_to_value(&e, lastarg == True ? False : True);
    goto DONE;

  case READY(NEG): /*    NEG x => -x, if x is a number */
    UPLEFT;
    if (tag[lastarg] == INT) {
      simpl(bignegate(lastarg));
    } else {
      setdbl(e, -get_dbl(lastarg));
    }
    goto DONE;

  case READY(CODE): /*  miranda char to int type-conversion  */
    UPLEFT;
    simpl(make(INT, get_char(lastarg), 0));
    goto DONE;

  case READY(DECODE): /*  int to char type conversion */
    UPLEFT;
    if (tag[lastarg] == DOUBLE) {
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
    goto DONE;

  case READY(INTEGER): /* predicate on numbers */
    UPLEFT;
    rewrite_to_value(&e, tag[lastarg] == INT ? True : False);
    goto NEXTREDEX;

  case READY(SHOWNUM): /*  SHOWNUM number => numeral */
    UPLEFT;
    if (tag[lastarg] == DOUBLE) {
      double x = get_dbl(lastarg);
#ifndef RYU
      sprintf(linebuf, "%.16g", x);
      {
        char *p = linebuf;
        while (isdigit((int)*p)) {
          p++; /* add .0 to false integer */
        }
        if (!*p) {
          *p++ = '.', *p++ = '0', *p = '\0';
        }
      }
      rewrite_to_string(&e, linebuf);
    }
#else
      d2s_buffered(x, linebuf);
      arg1 = str_conv(linebuf);
      if (*linebuf == '.')
        arg1 = cons('0', arg1);
      if (*linebuf == '-' && linebuf[1] == '.')
        arg1 = cons('-', cons('0', tl(arg1)));
      rewrite_to_value(&e, arg1);
    }
#endif
    else {
      {
        simpl(bigtostr(lastarg));
      }
    }
    goto DONE;

  case READY(SHOWHEX):
    UPLEFT;
    if (tag[lastarg] == DOUBLE) {
      sprintf(linebuf, "%a", get_dbl(lastarg));
      rewrite_to_string(&e, linebuf);
    } else {
      {
        simpl(bigtostrx(lastarg));
      }
    }
    goto DONE;

  case READY(SHOWOCT):
    UPLEFT;
    if (tag[lastarg] == DOUBLE) {
      int_error("showoct");
    } else {
      simpl(bigtostr8(lastarg));
    }
    goto DONE;

  /* paradigm for strict monadic arithmetic fns */
  case READY(ARCTAN_FN): /* atan */
    UPLEFT;
    errno = 0; /* to clear */
    setdbl(e, atan(force_dbl(lastarg)));
    if (errno) {
      math_error("atan");
    }
    goto DONE;

  case READY(EXP_FN): /* exp */
    UPLEFT;
    errno = 0; /* to clear */
    setdbl(e, exp(force_dbl(lastarg)));
    if (errno) {
      math_error("exp");
    }
    goto DONE;

  case READY(ENTIER_FN): /* floor */
    UPLEFT;
    if (tag[lastarg] == INT) {
      rewrite_to_value(&e, lastarg);
    } else {
      simpl(dbltobig(get_dbl(lastarg)));
    }
    goto DONE;

  case READY(LOG_FN): /* log */
    UPLEFT;
    if (tag[lastarg] == INT) {
      {
        setdbl(e, biglog(lastarg));
      }
    } else {
      errno = 0; /* to clear */
      fa = force_dbl(lastarg);
      setdbl(e, log(fa));
      if (errno) {
        math_error("log");
      }
    }
    goto DONE;

  case READY(LOG10_FN): /* log10 */
    UPLEFT;
    if (tag[lastarg] == INT) {
      {
        setdbl(e, biglog10(lastarg));
      }
    } else {
      errno = 0; /* to clear */
      fa = force_dbl(lastarg);
      setdbl(e, log10(fa));
      if (errno) {
        math_error("log10");
      }
    }
    goto DONE;

  case READY(SIN_FN): /* sin */
    UPLEFT;
    errno = 0; /* to clear */
    setdbl(e, sin(force_dbl(lastarg)));
    if (errno) {
      math_error("sin");
    }
    goto DONE;

  case READY(COS_FN): /* cos */
    UPLEFT;
    errno = 0; /* to clear */
    setdbl(e, cos(force_dbl(lastarg)));
    if (errno) {
      math_error("cos");
    }
    goto DONE;

  case READY(SQRT_FN): /* sqrt */
    UPLEFT;
    fa = force_dbl(lastarg);
    if (fa < 0.0) {
      math_error("sqrt");
    }
    setdbl(e, sqrt(fa));
    goto DONE;

#if 0
    /* paradigm for execution of strict diadic operator */
    case READY(DIOP):
    RESTORE(e);  /* do not write modified form of operator back into graph */
    GETARG(arg1);
    GETARG(arg2);
    hd(e)=I; e=tl(e)=diop(arg1,arg2);
    goto NEXTREDEX;
#endif

#if 0
    case READY(EQUAL): /* UNUSED */
    RESTORE(e);
    GETARG(arg1);
    GETARG(arg2);
    if(isap(arg1)&&hd(arg1)!=NUMBER&&isap(arg2)&&hd(arg2)!=NUMBER)
      { /* recurse on components */
        hd(e)=ap2(EQUAL,tl(arg1),tl(arg2));
        hd(e)=ap3(EQUAL,hd(arg1),hd(arg2),hd(e));
        tl(e)=False;
      }  
    else { hd(e)=I; e=tl(e)= (eqatom(arg1,arg2)?True:False); }
    goto NEXTREDEX;
#endif

  case READY(ZIP): /*  ZIP (a:x) (b:y) => (a,b) : ZIP x y
                       ZIP x y => []  */
    RESTORE(e);
    GETARG(arg1);
    GETARG(arg2);
    if (arg1 == NIL || arg2 == NIL) {
      rewrite_to_nil(&e);
      goto DONE;
    }
    setcell(CONS, cons(hd(arg1), hd(arg2)), ap2(ZIP, tl(arg1), tl(arg2)));
    goto DONE;

  case READY(EQ): /*    EQ x x => True
                        EQ x y => False
                  see definition of function "compare" above  */
    RESTORE(e);
    GETARG(arg1);
    UPLEFT;
    rewrite_to_compare_eq(&e, arg1, lastarg); /* ### */
    goto DONE;

  case READY(NEQ): /*    NEQ x x => False
                         NEQ x y => True
                   see definition of function "compare" above  */
    RESTORE(e);
    GETARG(arg1);
    UPLEFT;
    rewrite_to_compare_neq(&e, arg1, lastarg); /* ### */
    goto DONE;

  case READY(GR):
    RESTORE(e);
    GETARG(arg1);
    UPLEFT;
    rewrite_to_compare_gt(&e, arg1, lastarg); /* ### */
    goto DONE;

  case READY(GRE):
    RESTORE(e);
    GETARG(arg1);
    UPLEFT;
    rewrite_to_compare_ge(&e, arg1, lastarg); /* ### */
    goto DONE;

  case READY(PLUS):
    RESTORE(e);
    GETARG(arg1);
    UPLEFT;
    if (tag[arg1] == DOUBLE) {
      setdbl(e, get_dbl(arg1) + force_dbl(lastarg));
    } else if (tag[lastarg] == DOUBLE) {
      setdbl(e, bigtodbl(arg1) + get_dbl(lastarg));
    } else {
      simpl(bigplus(arg1, lastarg));
    }
    goto DONE;

  case READY(MINUS):
    RESTORE(e);
    GETARG(arg1);
    UPLEFT;
    if (tag[arg1] == DOUBLE) {
      setdbl(e, get_dbl(arg1) - force_dbl(lastarg));
    } else if (tag[lastarg] == DOUBLE) {
      setdbl(e, bigtodbl(arg1) - get_dbl(lastarg));
    } else {
      simpl(bigsub(arg1, lastarg));
    }
    goto DONE;

  case READY(TIMES):
    RESTORE(e);
    GETARG(arg1);
    UPLEFT;
    if (tag[arg1] == DOUBLE) {
      setdbl(e, get_dbl(arg1) * force_dbl(lastarg));
    } else if (tag[lastarg] == DOUBLE) {
      setdbl(e, bigtodbl(arg1) * get_dbl(lastarg));
    } else {
      simpl(bigtimes(arg1, lastarg));
    }
    goto DONE;

  case READY(INTDIV):
    RESTORE(e);
    GETARG(arg1);
    UPLEFT;
    if (tag[arg1] == DOUBLE || tag[lastarg] == DOUBLE) {
      int_error("div");
    }
    if (bigzero(lastarg)) {
      div_error(); /* build into bigmod ? */
    }
    simpl(bigdiv(arg1, lastarg));
    goto DONE;

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
    goto DONE;

  case READY(MOD):
    RESTORE(e);
    GETARG(arg1);
    UPLEFT;
    if (tag[arg1] == DOUBLE || tag[lastarg] == DOUBLE) {
      int_error("mod");
    }
    if (bigzero(lastarg)) {
      div_error(); /* build into bigmod ? */
    }
    simpl(bigmod(arg1, lastarg));
    goto DONE;

  case READY(POWER):
    RESTORE(e);
    GETARG(arg1);
    UPLEFT;
    if (tag[lastarg] == DOUBLE) {
      fa = force_dbl(arg1);
      if (fa < 0.0) {
        errno = EDOM, math_error("^");
      }
      fb = get_dbl(lastarg);
    } else if (tag[arg1] == DOUBLE) {
      {
        fa = get_dbl(arg1), fb = bigtodbl(lastarg);
      }
    } else if (neg(lastarg)) {
      {
        fa = bigtodbl(arg1), fb = bigtodbl(lastarg);
      }
    } else {
      simpl(bigpow(arg1, lastarg));
      goto DONE;
    }
    errno = 0; /* to clear */
    setdbl(e, pow(fa, fb));
    if (errno) {
      math_error("power");
    }
    goto DONE;

  case READY(SHOWSCALED): /* SHOWSCALED precision number => numeral */
    RESTORE(e);
    GETARG(arg1);
    UPLEFT;
    if (tag[arg1] == DOUBLE) {
      int_error("showscaled");
    }
    arg1 = getsmallint(arg1);
    (void)sprintf(linebuf, "%.*e", (int)arg1, force_dbl(lastarg));
    rewrite_to_string(&e, linebuf);
    goto DONE;

  case READY(SHOWFLOAT): /* SHOWFLOAT precision number => numeral */
    RESTORE(e);
    GETARG(arg1);
    UPLEFT;
    if (tag[arg1] == DOUBLE) {
      int_error("showfloat");
    }
    arg1 = getsmallint(arg1);
    (void)sprintf(linebuf, "%.*f", (int)arg1, force_dbl(lastarg));
    rewrite_to_string(&e, linebuf);
    goto DONE;

#define coerce_dbl(x) tag[x] == DOUBLE ? (x) : sto_dbl(bigtodbl(x))

  case READY(STEP): /* STEP i a => GENSEQ (i,NIL) a */
    RESTORE(e);
    GETARG(arg1);
    UPLEFT;
    hd(e) = ap(GENSEQ, cons(arg1, NIL));
    goto NEXTREDEX;

  case READY(MERGE): /* MERGE [] y => y
                        MERGE (a:x) [] => a:x
                        MERGE (a:x) (b:y) => a:MERGE x (b:y), if a<=b
                                          => b:MERGE (a:x) y, otherwise */
    RESTORE(e);
    GETARG(arg1);
    UPLEFT;
    if (arg1 == NIL) {
      rewrite_to_value(&e, lastarg);
    } else if (lastarg == NIL) {
      rewrite_to_value(&e, arg1);
    } else if (compare(hd(arg1) = reduce(hd(arg1)), hd(lastarg) = reduce(hd(lastarg))) <=
               0) { /* ### */
      setcell(CONS, hd(arg1), ap2(MERGE, tl(arg1), lastarg));
    } else {
      setcell(CONS, hd(lastarg), ap2(MERGE, tl(lastarg), arg1));
    }
    goto DONE;

  case READY(STEPUNTIL): /* STEPUNTIL i a b => GENSEQ (i,b) a */
    RESTORE(e);
    GETARG(arg1);
    GETARG(arg2);
    UPLEFT;
    hd(e) = ap(GENSEQ, cons(arg1, arg2));
    if (tag[arg1] == INT ? poz(arg1) : get_dbl(arg1) >= 0.0) {
      tag[tl(hd(e))] = AP; /* hack to record sign of step - see GENSEQ */
    }
    goto NEXTREDEX;

  case READY(Ush):
    /* Ush (k f1...fn) p (k x1...xn)
                    => "k"++' ':f1 x1 ...++' ':fn xn, p='\0'
                    => "(k"++' ':f1 x1 ...++' ':fn xn++")", p='\1'
       Ush (k f1...fn) p other => FAIL  */
    RESTORE(e);
    GETARG(arg1);
    GETARG(arg2);
    GETARG(arg3);
    if (constr_tag(head(arg1)) != constr_tag(head(arg3))) {
      rewrite_to_fail(&e);
      goto DONE;
    } /* result is string, so cannot be more args */
    if (tag[arg1] == CONSTRUCTOR) /* don't parenthesise atom */
    {
      if (suppressed(arg1)) {
        rewrite_to_string(&e, "<unprintable>");
      } else {
        rewrite_to_string(&e, constr_name(arg1));
      }
      goto DONE;
    }
    hold = arg2 ? cons(')', NIL) : NIL;
    while (tag[arg1] != CONSTRUCTOR) {
      hold = cons(' ', ap2(APPEND, ap(tl(arg1), tl(arg3)), hold)), arg1 = hd(arg1), arg3 = hd(arg3);
    }
    if (suppressed(arg1)) {
      rewrite_to_string(&e, "<unprintable>");
      goto DONE;
    }
    hold = ap2(APPEND, str_conv(constr_name(arg1)), hold);
    if (arg2) {
      setcell(CONS, '(', hold);
      goto DONE;
    } else {
      rewrite_to_value(&e, hold);
      goto NEXTREDEX;
    }

  default:
    fprintf(stderr, "\nimpossible event in reduce ("), out(stderr, e), fprintf(stderr, ")\n"),
        exit(1);
  } /* end of "ready" switch */

} /* end of reduce */

/* end of MIRANDA REDUCE */
