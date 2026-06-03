/* MIRANDA TRANS */
/* performs translation to combinatory logic */
/* Converts parsed and typechecked Miranda definitions into SK-style
   combinator graphs consumed by the reducer. */

/**************************************************************************
 * Copyright (C) Research Software Limited 1985-90.  All rights reserved. *
 * The Miranda system is distributed as free software under the terms in  *
 * the file "COPYING" which is included in the distribution.              *
 *                                                                        *
 * Revised to C11 standard and made 64bit compatible, January 2020        *
 *------------------------------------------------------------------------*/

#include "data.h"
#include "big.h"
#include "lex.h"

/* miscellaneous declarations  */
extern word nill, Void;
extern word listdiff_fn, count_fn, from_fn;
extern word diagonalise, concat;
extern word lastname, initialising;
extern word current_id, echoing;

word newtyps = NIL; /* list of typenames declared in current script */
word SGC = NIL;     /* list of user defined sui-generis constructors */
#define sui_generis(k) (/* k==Void|| */ member(SGC, k))
/* 3/10/88 decision to treat `()' as lifted */
word abshfnck(word /*t*/, word /*f*/);
word abstr(word /*x*/, word /*e*/);
word abstract(word /*x*/, word /*e*/);
word abstrlist(word /*x*/, word /*e*/);
word combine(word /*x*/, word /*y*/);
word fixrepeats(word /*qq*/);
word getrel(word /*r*/, word /*x*/);
word here_inf(word /*rhs*/);
word imageless(word /*r*/, word /*y*/, word /*z*/);
word invgetrel(word /*r*/, word /*x*/);
word leftfactor(word /*x*/);
word less(word /*x*/, word /*y*/);
word less1(word /*x*/, word /*a*/);
word liscomb(word /*x*/, word /*y*/);
word makeshow(word /*here*/, word /*type*/);
word mklazy(word /*d*/);
word mkshowt(word /*s*/, word /*t*/);
word mktuple(word /*x*/);
void nameclash(word /*x*/);
word new_mklazy(word /*d*/);
word primconstr(word /*x*/);
void respec_error(word /*x*/);
word scanpattern(word /*p*/, word /*x*/, word /*e*/, word /*fail*/);
word sort(word /*x*/);
word translet(word /*d*/, word /*e*/);
word transletrec(word /*dd*/, word /*e*/);
word transtries(word /*id*/, word /*x*/);
word transzf(word /*e*/, word /*qq*/, word /*conc*/);

#define mkindex(i) ((i) < 256 ? (i) : make(INT, i, 0))
/* will fall over if i >= IBASE */

word rv_script = 0; /* flags readvals in use (for garbage collector) */

word codegen(word x) /* returns expression x with abstractions performed */
{
  extern word commandmode, cook_stdin, common_stdin, common_stdinb, rv_expr;
  switch (tag[x]) {
  case AP:
    if (commandmode /* beware of corrupting lastexp */
        && x != cook_stdin && x != common_stdin && x != common_stdinb) { /* but share $+ $- */
      return (make(AP, codegen(hd(x)), codegen(tl(x))));
    }
    if (tag[hd(x)] == AP && hd(hd(x)) == APPEND && tl(hd(x)) == NIL) {
      return (codegen(tl(x))); /* post typecheck reversal of HR bug fix */
    }
    hd(x) = codegen(hd(x));
    tl(x) = codegen(tl(x));
    /* otherwise do in situ */
    return (tag[hd(x)] == AP && hd(hd(x)) == G_ALT ? leftfactor(x) : x);
  case TCONS:
  case PAIR:
    return (make(CONS, codegen(hd(x)), codegen(tl(x))));
  case CONS:
    if (commandmode) {
      return (make(CONS, codegen(hd(x)), codegen(tl(x))));
    }
    /* otherwise do in situ (see declare) */
    hd(x) = codegen(hd(x));
    tl(x) = codegen(tl(x));
    return x;
  case LAMBDA:
    return (abstract(hd(x), codegen(tl(x))));
  case LET:
    return (translet(hd(x), tl(x)));
  case LETREC:
    return (transletrec(hd(x), tl(x)));
  case TRIES:
    return (transtries(hd(x), tl(x)));
  case LABEL:
    return (codegen(tl(x)));
  case SHOW:
    return (makeshow(hd(x), tl(x)));
  case LEXER: {
    word r = NIL;
    word uses_state = 0;
    ;
    while (x != NIL) {
      word rule = abstr(mklexvar(0), codegen(tl(tl(hd(x)))));
      rule = abstr(mklexvar(1), rule);
      if (!(tag[rule] == AP && hd(rule) == K)) {
        uses_state = 1;
      }
      r = cons(cons(hd(hd(x)),                   /* start condition stuff */
                    cons(ap(hd(tl(hd(x))), NIL), /* matcher [] */
                         rule)),
               r);
      x = tl(x);
    }
    if (!uses_state) /* strip off (K -) from each rule */
    {
      for (x = r; x != NIL; x = tl(x)) {
        tl(tl(hd(x))) = tl(tl(tl(hd(x))));
      }
      r = ap(LEX_RPT, ap(LEX_TRY, r));
    } else {
      {
        r = ap(LEX_RPT1, ap(LEX_TRY1, r));
      }
    }
    return (ap(r, 0));
  } /* 0 startcond */
  case STARTREADVALS:
    if (ispoly(tl(x))) {
      extern word cook_stdin, ND;
      printf("type error - %s used at polymorphic type :: [",
             cook_stdin && x == hd(cook_stdin) ? "$+" : "readvals or $+");
      out_type(redtvars(tl(x))), printf("]\n");
      polyshowerror = 1;
      if (current_id) {
        ND = add1(current_id, ND), id_type(current_id) = wrong_t, id_val(current_id) = UNDEF;
      }
      if (hd(x)) {
        sayhere(hd(x), 1);
      }
    }
    if (commandmode) {
      rv_expr = 1;
    } else {
      rv_script = 1;
    }
    return x;
  case SHARE:
    if (tl(x) != -1) { /* arbitrary flag for already visited */
      hd(x) = codegen(hd(x)), tl(x) = -1;
    }
    return (hd(x));
  default:
    if (x == NILS) {
      return (NIL);
    }
    return x; /* identifier, private name, or constant */
  }
}

int lfrule = 0;

word was_poly;
int polyshowerror = 0;

word algshfns = NIL; /* list of showfunctions for all algebraic  types in scope
                       (list of pnames) - needed to make dumps */

void genshfns(void) /* called after meta type check - create show functions for
              algebraic types */
{
  word s;
  for (s = newtyps; s != NIL; s = tl(s)) {
    if (t_class(hd(s)) == algebraic_t) {
      word f = 0;
      word r = t_info(hd(s)); /* r is list of constructors */
      word ush = tl(r) == NIL && member(SGC, hd(r)) ? Ush1 : Ush;
      for (; r != NIL; r = tl(r)) {
        word t = id_type(hd(r));
        word k = id_val(hd(r));
        while (tag[k] != CONSTRUCTOR) {
          k = tl(k); /* lawful and !'d constructors*/
        }
        /* k now holds constructor(i,hd(r)) */
#if 0
	    k=constructor(hd(k),datapair(get_id(tl(k)),0)); 
	      /* this `freezes' the name of the constructor */
	      /* incorrect, makes showfns immune to aliasing, should be
		 done at mkshow time, not genshfn time - FIX LATER */
#endif
        while (isarrow_t(t)) {
          k = ap(k, mkshow(1, 1, tl(hd(t)))), t = tl(t); /* NB 2nd arg */
        }
        k = ap(ush, k);
        while (iscompound_t(t)) {
          k = abstr(tl(t), k), t = hd(t);
        }
        /* see kahrs.bug.m (this is the fix) */
        if (f) {
          f = ap2(TRY, k, f);
        } else {
          f = k;
        }
      }
      /* f~=0, placeholder types dealt with in specify() */
      pn_val(t_showfn(hd(s))) = f;
      algshfns = cons(t_showfn(hd(s)), algshfns);
    } else if (t_class(hd(s)) == abstract_t) {
      { /* if showfn present check type is ok */
        if (t_showfn(hd(s))) {
          if (!abshfnck(hd(s), id_type(t_showfn(hd(s))))) {
            printf("warning - \"%s\" has type inappropriate for a show-function\n",
                   get_id(t_showfn(hd(s)))),
                t_showfn(hd(s)) = 0;
          }
        }
      }
    }
  }
}

word speclocs = NIL; /* list of cons(id,hereinfo) giving location of spec for
                       ids both defined and specified - needed to locate errs
                       in meta_tcheck, abstr_mcheck */

/* NOTE
     When an rhs contains FAIL as a result of compiling an elseless guard set
     it is of the form
        XX ::= ap3(COND,a,b,FAIL) | let[rec](def[s],XX) | lambda(pat,XX)
     an rhs is fallible if
        1) it is an XX, as above, or
        2) it is of the form lambda(pat1,...,lambda(patn,e)...)
           where at least one of the patterns pati is refutable.
  */

#if 0
/* combinator to select i'th out of n args */
word k(word i,word n)
{ if(i==1)return(n==1?I:n==2?K:ap2(B,K,k(1,n-1)));
  if(i==2&&n==2)return(KI); /* redundant but saves space */
  return(ap(K,k(i-1,n-1)));
} /* not currently used */
#endif

/* end of MIRANDA TRANS */
