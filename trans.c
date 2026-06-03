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
static void decl1(word /*x*/, word /*e*/);
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

word abstract(word x, word e)
/* abstraction of template x from compiled expression e */
{
  switch (tag[x]) {
  case ID:
    if (isconstructor(x)) {
      return (sui_generis(x) ? ap(K, e) : ap2(Ug, primconstr(x), e));
    } else {
      return (abstr(x, e));
    }
  case CONS:
    if (hd(x) == CONST) {
      if (tag[tl(x)] == INT) {
        return (ap2(MATCHINT, tl(x), e));
      }
      return (ap2(MATCH, tl(x) == NILS ? NIL : tl(x), e));
    } else {
      return (ap(U_, abstract(hd(x), abstract(tl(x), e))));
    }
  case TCONS:
  case PAIR: /* tuples */
    return (ap(U, abstract(hd(x), abstract(tl(x), e))));
  case AP:
    if (sui_generis(head(x))) {
      return (ap(Uf, abstract(hd(x), abstract(tl(x), e))));
    }
    if (tag[hd(x)] == AP && hd(hd(x)) == PLUS) { /* n+k pattern */
      return (ap2(ATLEAST, tl(hd(x)), abstract(tl(x), e)));
    }
    while (tag[x] == AP) {
      e = abstract(tl(x), e);
      x = hd(x);
    }
    /* now x must be a constructor */
  default:;
  }
  if (isconstructor(x)) {
    return (ap2(Ug, primconstr(x), e));
  }
  printf("error in declaration of \"%s\", undeclared constructor in pattern: ",
         get_id(current_id)); /* something funny here - fix later */
  out(stdout, x);
  printf("\n");
  return (NIL);
}

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

void declare(word x, word e)
/* translates  <pattern> = <exp>  at top level  */
{
  if (tag[x] == ID && !isconstructor(x)) {
    {
      decl1(x, e);
    }
  } else {
    word bindings =
        scanpattern(x, x, share(tries(x, cons(e, NIL)), undef_t), ap(CONFERROR, cons(x, hd(e))));
    /* hd(e) is here-info */
    /* note creation of share node to force sharing on code generation
       and typechecking */
    if (bindings == NIL) {
      errs = hd(e);
      syntax("illegal lhs for definition\n");
      return;
    }
    lastname = 0;
    while (bindings != NIL) {
      word h;
      if (id_val(h = hd(hd(bindings))) != UNDEF) {
        errs = hd(e);
        nameclash(h);
        return;
      }
      id_val(h) = tl(hd(bindings));
      if (id_who(h) != NIL) {
        speclocs = cons(cons(h, id_who(h)), speclocs);
      }
      id_who(h) = hd(e); /* here-info */
      if (id_type(h) == undef_t) {
        addtoenv(h);
      }
      bindings = tl(bindings);
    }
  }
}

void decl1(word x, word e) /* declare name x to have the value denoted by e */
{
  if (id_val(x) != UNDEF && lastname != x) {
    errs = hd(e);
    nameclash(x);
    return;
  }
  if (id_val(x) == UNDEF) {
    id_val(x) = tries(x, cons(e, NIL));
    if (id_who(x) != NIL) {
      speclocs = cons(cons(x, id_who(x)), speclocs);
    }
    id_who(x) = hd(e); /* here-info */
    if (id_type(x) == undef_t) {
      addtoenv(x);
    }
  } else if (!fallible(hd(tl(id_val(x))))) {
    {
      errs = hd(e),
      printf("%ssyntax error: unreachable case in defn of \"%s\"\n", echoing ? "\n" : "",
             get_id(x)),
      acterror();
    }
  } else {
    {
      tl(id_val(x)) = cons(e, tl(id_val(x)));
    }
  }
  /* multi-clause definitions are composed as tries(id,rhs_list)
     where id is included purely for diagnostic purposes
     note that rhs_list is reversed - put right by code generation */
}

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

#define arity_check                                                                                \
  if (t_arity(tf) != arity)                                                                        \
  printf("%ssyntax error: \
wrong number of parameters for typename \"%s\" (%ld expected)\n",                                  \
         echoing ? "\n" : "", get_id(tf), t_arity(tf)),                                            \
      errs = here, acterror()

void decl_type(word tf, word type_class, word info, word here)
/* declare a user defined type */
{
  word arity = 0;

  while (tag[tf] == AP) {
    arity++, tf = hd(tf);
  }
  if (type_class == synonym_t && id_type(tf) == type_t && t_class(tf) == abstract_t &&
      t_info(tf) ==
          undef_t) { /* this is binding for declared but not yet bound abstract typename */
    arity_check;
    id_who(tf) = here;
    t_info(tf) = info;
    return;
  }
  if (type_class == abstract_t && id_type(tf) == type_t &&
      t_class(tf) == synonym_t) { /* this is abstype declaration of already bound typename */
    arity_check;
    t_class(tf) = abstract_t;
    return;
  }
  if (id_val(tf) != UNDEF) {
    errs = here;
    nameclash(tf);
    return;
  }
  if (type_class != synonym_t) {
    newtyps = add1(tf, newtyps);
  }
  id_val(tf) = make_typ(arity, type_class == algebraic_t ? make_pn(UNDEF) : 0, type_class, info);
  if (id_type(tf) != undef_t) {
    errs = here;
    respec_error(tf);
    return;
  }
  addtoenv(tf);
  id_who(tf) = here;
  id_type(tf) = type_t;
}

void declconstr(word x, word n, word t)
/* declare x to be constructor number n of type t */
/* x must be an identifier */
{
  id_val(x) = constructor(n, x);
  if (n >> 16) {
    syntax("algebraic type has too many constructors\n");
    return;
  }
  if (id_type(x) != undef_t) {
    errs = id_who(x);
    respec_error(x);
    return;
  }
  addtoenv(x);
  id_type(x) = t;
} /* the value of a constructor x is constructor(constr_tag,x)
     where constr_tag is a small natural number */

word block(word defs, word e, word keep)
/* semantics of "where" - performs dependency analysis */
/* defs has form list(defn(pat,typ,val)), e is body of block */
/* if `keep' hold together as single letrec */
{
  word ids = NIL;
  word deftoids = NIL;
  word g = NIL;
  word d;
  extern word SYNERR, detrop;
  if (SYNERR) {
    return (NIL); /* analysis falls over on empty patterns */
  }
  for (d = defs; d != NIL; d = tl(d)) /* first collect all ids defined in block */
  {
    word x = get_ids(dlhs(hd(d)));
    ids = UNION(ids, x);
    deftoids = cons(cons(hd(d), x), deftoids);
  }
  defs = sort(defs);
  for (d = defs; d != NIL; d = tl(d)) /* now build dependency relation g */
  {
    word x = intersection(deps(dval(hd(d))), ids);
    word y = NIL;
    for (; x != NIL; x = tl(x)) { /* replace each id by corresponding def */
      y = add1(invgetrel(deftoids, hd(x)), y);
    }
    g = cons(cons(hd(d), add1(hd(d), y)), g);
    /* treat all defs as recursive for now */
  }
  g = reverse(g); /* keep in address order of first components */
                  /* g is list(cons(def,defs))
                     where defs are all on which def immediately depends, plus self */
  g = tclos(g);   /* now g is list(cons(def,ultdefs)) */
  {               /* check for unused definitions */
    word x = intersection(deps(e), ids);
    word y = NIL;
    for (; x != NIL; x = tl(x)) {
      word d = invgetrel(deftoids, hd(x));
      if (!member(y, d)) {
        y = UNION(y, getrel(g, d));
      }
    }
    defs = setdiff(defs, y); /* these are de trop */
    if (defs != NIL) {
      detrop = append1(detrop, defs);
    }
    if (keep) {              /* if local polymorphism not required */
      return (letrec(y, e)); /* analysis was solely to find unwanted defs */
    }
    /* remove redundant entries from g */
    /* no, leave in for typecheck - could remove afterwards
    while(*g1!=NIL&&defs!=NIL)
         if(hd(hd(*g1))==hd(defs))*g1=tl(*g1); else
         if(hd(hd(*g1))<hd(defs))g1= &tl(*g1);
         else defs=tl(defs); */
  }
  g = msc(g);     /* g is list(defgroup,ultdefs) */
  g = tsort(g);   /* g is list(defgroup) in dependency order */
  g = reverse(g); /* reconstruct block inside-first */
  while (g != NIL) {
    if (tl(hd(g)) == NIL && intersection(get_ids(dlhs(hd(hd(g)))), deps(dval(hd(hd(g))))) == NIL) {
      e = let(hd(hd(g)), e); /* single non-recursive def */
    } else {
      e = letrec(hd(g), e);
    }
    g = tl(g);
  }
  return e;
}
/* Implementation note:
   tsort will fall over if there is a non-list strong component because it
   was originally written on assumption that relation is over identifiers.
   Whence need to pretend all defs recursive until after tsort.
   Could do better - some defs may be subsidiary to others */

void specify(word x, word t, word h) /* semantics of a "::" statement */
                                     /* N.B. t not yet in reduced form */
{

  if (tag[x] != ID && t != type_t) {
    errs = h;
    syntax("incorrect use of ::\n");
    return;
  }
  if (t == type_t) {
    word a = 0;
    while (tag[x] == AP) {
      a++, x = hd(x);
    }
    if (!(id_val(x) == UNDEF && id_type(x) == undef_t)) {
      errs = h;
      nameclash(x);
      return;
    }
    id_type(x) = type_t;
    if (id_who(x) == NIL) {
      id_who(x) = h; /* premise always true, see above */
    }
    /* if specified and defined, locate by definition */
    id_val(x) = make_typ(a, showwhat, placeholder_t, NIL); /* placeholder type */
    addtoenv(x);
    newtyps = add1(x, newtyps);
    return;
  }
  if (id_type(x) != undef_t) {
    errs = h;
    respec_error(x);
    return;
  }
  id_type(x) = t;
  if (id_who(x) == NIL) {
    id_who(x) = h; /* as above */
  } else {
    speclocs = cons(cons(x, h), speclocs);
  }
  if (id_val(x) == UNDEF) {
    addtoenv(x);
  }
}

/* end of MIRANDA TRANS */
