/* original parser id follows */
/* yysccsid[] = "@(#)yaccpar	1.9 (Berkeley) 02/21/93" */
/* (use YYMAJOR/YYMINOR for ifdefs dependent on parser version) */

#define YYBYACC 1
#define YYMAJOR 2
#define YYMINOR 0
#define YYPATCH 20260126

#define YYEMPTY        (-1)
#define yyclearin      (yychar = YYEMPTY)
#define yyerrok        (yyerrflag = 0)
#define YYRECOVERING() (yyerrflag != 0)
#define YYENOMEM       (-2)
#define YYEOF          0
#undef YYBTYACC
#define YYBTYACC 0
#define YYDEBUGSTR YYPREFIX "debug"
#define YYPREFIX "yy"

#define YYPURE 0

#line 34 "rules.y"
/* the following definition has to be kept in line with the token declarations
   above */
char *yysterm[]= {
 0,
 "VALUE",
 "EVAL",
 "where",
 "if",
 "&>",
 "<-",
 "::",
 "::=",
 "TYPEVAR",
 "NAME",
 "CONSTRUCTOR-NAME",
 "CONST",
 "$$",
 "OFFSIDE",
 "OFFSIDE =",
 "abstype",
 "with",
 "//",
 "==",
 "%free",
 "%include",
 "%export",
 "type",
 "otherwise",
 "show",
 "PATHNAME",
 "%bnf",
 "%lex",
 "%%",
 "error",
 "end",
 "empty",
 "readvals",
 "NAME",
 "`char-class`",
 "`char-class`",
 "%%begin",
 "->",
 "++",
 "--",
 "..",
 "\\/",
 ">=",
 "~=",
 "<=",
 "mod",
 "div",
 "$NAME",
 "$CONSTRUCTOR"};

#line 94 "rules.y"
#include "data.h"
#include "big.h"
#include "lex.h"
#include "parser_bridge.h"
extern word nill,k_i,Void;
extern word message,standardout;
extern word big_one;
#define isltmess_t(t) (islist_t(t)&&tl(t)==message)
#define isstring_t(t) (islist_t(t)&&tl(t)==char_t)
extern word SYNERR,errs,echoing,gvars;
extern word listdiff_fn,indent_fn,outdent_fn;
word lastname=0;
word suppressids=NIL;
word idsused=NIL;
word tvarscope=0;
word includees=NIL,embargoes=NIL,exportfiles=NIL,freeids=NIL,exports=NIL;
word lexdefs=NIL,lexstates=NIL,inlex=0,inexplist=0;
word inbnf=0,col_fn=0,fnts=NIL,eprodnts=NIL,nonterminals=NIL,sreds=0;
word ihlist=0,ntspecmap=NIL,ntmap=NIL,lasth=0;
word obrct=0;

void evaluate(word x)
{ word t;
  t=type_of(x);
  if(t==wrong_t)return;
  lastexp=x;
  x=codegen(x);
  if(polyshowerror)return;
  if(process())
                 /* setup new process for each evaluation */
  { (void)signals(SIGINT,(sighandler)dieclean);
      /* if interrupted will flush output etc before going */
    compiling=0;
    resetgcstats();
    output(isltmess_t(t)?x:
            cons(ap(standardout,isstring_t(t)?x
                           :ap(mkshow(0,0,t),x)),NIL));
    (void)signals(SIGINT,SIG_IGN);/* otherwise could do outstats() twice */
    putchar('\n');
    outstats();
    exit(0); }
}

void obey(word x) /* like evaluate but no fork, no stats, no extra '\n' */
{ word t=type_of(x);
  x=codegen(x);
  if(polyshowerror)return;
  compiling=0;
  output(isltmess_t(t)?x:
            cons(ap(standardout,isstring_t(t)?x:ap(mkshow(0,0,t),x)),NIL));
}

int isstring(word x)
{ return(x==NILS||(tag[x]==CONS&&is_char(hd(x))));
}

word compose(word x) /* used in compiling 'cases' */
{ word y=hd(x);
  if(hd(y)==OTHERWISE)y=tl(y); /* OTHERWISE was just a marker - lose it */
  else y=tag[y]==LABEL?label(hd(y),ap(tl(y),FAIL)):
         ap(y,FAIL); /* if all guards false result is FAIL */
  x = tl(x);
  if(x!=NIL)
    { while(tl(x)!=NIL)y=label(hd(hd(x)),ap(tl(hd(x)),y)), x=tl(x);
      y=ap(hd(x),y);
     /* first alternative has no label - label of enclosing rhs applies */
    }
  return(y);
}

int eprod(word);

word starts(word x) /* x is grammar rhs - returns list of nonterminals in start set */
{ L: switch(tag[x])
     { case ID: return(cons(x,NIL));
       case LABEL:
       case LET:
       case LETREC: x=tl(x); goto L;
       case AP: switch(hd(x))
                { case G_SYMB:
                  case G_SUCHTHAT:
                  case G_RULE: return(NIL);
                  case G_OPT:
                  case G_FBSTAR:
                  case G_STAR: x=tl(x); goto L;
                  default: if(hd(x)==outdent_fn)
                             { x=tl(x); goto L; }
                           if(tag[hd(x)]==AP) {
                             if(hd(hd(x))==G_ERROR)
                               { x=tl(hd(x)); goto L; }
                             if(hd(hd(x))==G_SEQ)
                               { if(eprod(tl(hd(x))))
                                   return(UNION(starts(tl(hd(x))),starts(tl(x))));
                                 x=tl(hd(x)); goto L; }
                             if(hd(hd(x))==G_ALT)
                               return(UNION(starts(tl(hd(x))),starts(tl(x))));
                             if(hd(hd(x))==indent_fn)
                               { x=tl(x); goto L; }
			     fprintf(stderr, "Internal error: AP tag is followed by unhandled case in starts()\nPlease report it to miranda@groups.io\n");
                           } else fprintf(stderr, "Internal error: AP tag is followed by neither outdent nor AP in starts()\nPlease report it to miranda@groups.io\n");
                }
       default: return(NIL);
     }
}

int eprod(word x) /* x is grammar rhs - does x admit empty production? */
{ L: switch(tag[x])
     { case ID: return(member(eprodnts,x));
       case LABEL:
       case LET:
       case LETREC: x=tl(x); goto L;
       case AP: switch(hd(x))
                { case G_SUCHTHAT:
                  case G_ANY:
                  case G_SYMB: return(0);
                  case G_RULE: return(1);
                  case G_OPT:
                  case G_FBSTAR:
                  case G_STAR: return(1);
                  default: if(hd(x)==outdent_fn)
                             { x=tl(x); goto L; }
                           if(tag[hd(x)]==AP) {
                             if(hd(hd(x))==G_ERROR)
                               { x=tl(hd(x)); goto L; }
                             if(hd(hd(x))==G_SEQ)
                               return(eprod(tl(hd(x)))&&eprod(tl(x))); else
                             if(hd(hd(x))==G_ALT)
                               return(eprod(tl(hd(x)))||eprod(tl(x)));
                             if(hd(hd(x))==indent_fn)
                               { x=tl(x); goto L; }
			     fprintf(stderr, "Internal error: AP tag is followed by unhandled case in eprod()\nPlease report it to miranda@groups.io\n");
			   } else fprintf(stderr, "Internal error: AP tag is followed by neither outdent nor AP in eprod()\nPlease report it to miranda@groups.io\n");
                }
       default: return(x==G_STATE||x==G_UNIT);
       /* G_END is special case, unclear whether it counts as an e-prodn.
          decide no for now, sort this out later */
     }
}

word add_prod(word d,word ps,word hr)
{ word p,n=dlhs(d);
  for(p=ps;p!=NIL;p=tl(p))
  if(dlhs(hd(p))==n) {
     if(dtyp(d)==undef_t&&dval(hd(p))==UNDEF) {
       dval(hd(p))=dval(d); return(ps);
     } else {
       if(dtyp(d)!=undef_t&&dtyp(hd(p))==undef_t)
	 { dtyp(hd(p))=dtyp(d); return(ps); }
       else
	 errs=hr,
	 printf(
	"%ssyntax error: conflicting %s of nonterminal \"%s\"\n",
		 echoing?"\n":"",
		 dtyp(d)==undef_t?"definitions":"specifications",
		 get_id(n)),
	 acterror();
      }
  }
  return(cons(d,ps));
}
/* clumsy - this algorithm is quadratic in number of prodns - fix later */

word getloc(word nt,word prods)  /* get here info for nonterminal */
{ while(prods!=NIL&&dlhs(hd(prods))!=nt)prods=tl(prods);
  if(prods!=NIL)return(hd(dval(hd(prods))));
  return(0);  /* should not happen, but just in case */
}

void findnt(word nt) /* set errs to here info of undefined nonterminal */
{ word p=ntmap;
  while(p!=NIL&&hd(hd(p))!=nt)p=tl(p);
  if(p!=NIL)
    { errs=tl(hd(p)); return; }
  p=ntspecmap;
  while(p!=NIL&&hd(hd(p))!=nt)p=tl(p);
  if(p!=NIL)errs=tl(hd(p));
}

#define isap2(fn,x) (tag[x]==AP&&tag[hd(x)]==AP&&hd(hd(x))==(fn))
#define firstsymb(term) tl(hd(term))

void binom(word rhs,word x)
/* performs the binomial optimisation on rhs of nonterminal x
    x: x alpha1| ... | x alphaN | rest     ||need not be in this order
        ==>
    x: rest (alpha1|...|alphaN)*
*/
{ word *p= &tl(rhs);  /* rhs is of form label(hereinf, stuff) */
  word *lastp=0,*holdrhs,suffix,alpha=NIL;
  if(tag[*p]==LETREC)p = &tl(*p); /* ignore trailing `where defs' */
  if(isap2(G_ERROR,*p))p = &tl(hd(*p));
  holdrhs=p;
  while(isap2(G_ALT,*p))
    if(firstsymb(tl(hd(*p)))==x)
       alpha=cons(tl(tl(hd(*p))),alpha),
       *p=tl(*p),p = &tl(*p);
    else lastp=p,p = &tl(tl(*p));
    /* note each (G_ALT a b) except the outermost is labelled */
  if(lastp&&firstsymb(*p)==x)
    alpha=cons(tl(*p),alpha),
    *lastp=tl(hd(*lastp));
  if(alpha==NIL)return;
  suffix=hd(alpha),alpha=tl(alpha);
  while(alpha!=NIL)
       suffix=ap2(G_ALT,hd(alpha),suffix),
       alpha=tl(alpha);
  *holdrhs=ap2(G_SEQ,*holdrhs,ap(G_FBSTAR,suffix));
}
/* should put some labels on the alpha's - fix later */

word getcol_fn(void)
{ extern char *dicp,*dicq;
  if(!col_fn)
    strcpy(dicp,"bnftokenindentation"),
    dicq=dicp+20,
    col_fn=name();
  return(col_fn);
}

void startbnf(void)
{ ntspecmap=ntmap=nonterminals=NIL; 
  if(fnts==0)col_fn=0; /* reinitialise, a precaution */
}

word ih_abstr(word x)  /* abstract inherited attributes from grammar rule */
{ word ih=ihlist;
  while(ih!=NIL)  /* relies on fact that ihlist is reversed */
       x=lambda(hd(ih),x),ih=tl(ih);
  return(x);
}

int can_elide(word x) /* is x of the form $1 applied to ih attributes in order? */
{ word ih;
  if(ihlist)
    for(ih=ihlist;ih!=NIL&&tag[x]==AP;ih=tl(ih),x=hd(x))
       if(hd(ih)!=tl(x))return(0);
  return(x==mkgvar(1));
}

int e_re(word x) /* does regular expression x match empty string ? */
{ L: if(tag[x]==AP)
       { if(hd(x)==LEX_STAR||hd(x)==LEX_OPT)return(1);
         if(hd(x)==LEX_STRING)return(tl(x)==NIL);
         if(tag[hd(x)]!=AP)return(0);
         if(hd(hd(x))==LEX_OR)
           { if(e_re(tl(hd(x))))return(1);
             x=tl(x); goto L; } else
         if(hd(hd(x))==LEX_SEQ)
           { if(!e_re(tl(hd(x))))return(0);
             x=tl(x); goto L; } else
         if(hd(hd(x))==LEX_RCONTEXT)
           { x=tl(hd(x)); goto L; }
       }
     return(0);
}

#line 336 "y.tab.c"

#if ! defined(YYSTYPE) && ! defined(YYSTYPE_IS_DECLARED)
/* Default: YYSTYPE is the semantic value type. */
typedef int YYSTYPE;
# define YYSTYPE_IS_DECLARED 1
#endif

/* compatibility with bison */
#ifdef YYPARSE_PARAM
/* compatibility with FreeBSD */
# ifdef YYPARSE_PARAM_TYPE
#  define YYPARSE_DECL() yyparse(YYPARSE_PARAM_TYPE YYPARSE_PARAM)
# else
#  define YYPARSE_DECL() yyparse(void *YYPARSE_PARAM)
# endif
#else
# define YYPARSE_DECL() yyparse(void)
#endif

/* Parameters sent to lex. */
#ifdef YYLEX_PARAM
# define YYLEX_DECL() yylex(void *YYLEX_PARAM)
# define YYLEX yylex(YYLEX_PARAM)
#else
# define YYLEX_DECL() yylex(void)
# define YYLEX yylex()
#endif

#if !(defined(yylex) || defined(YYSTATE))
int YYLEX_DECL();
#endif

/* Parameters sent to yyerror. */
#ifndef YYERROR_DECL
#define YYERROR_DECL() yyerror(const char *s)
#endif
#ifndef YYERROR_CALL
#define YYERROR_CALL(msg) yyerror(msg)
#endif

extern int YYPARSE_DECL();

#define VALUE 257
#define EVAL 258
#define WHERE 259
#define IF 260
#define TO 261
#define LEFTARROW 262
#define COLONCOLON 263
#define COLON2EQ 264
#define TYPEVAR 265
#define NAME 266
#define CNAME 267
#define CONST 268
#define DOLLARS 269
#define OFFSIDE 270
#define ELSEQ 271
#define ABSTYPE 272
#define WITH 273
#define DIAG 274
#define EQEQ 275
#define FREE 276
#define INCLUDE 277
#define EXPORT 278
#define TYPE 279
#define OTHERWISE 280
#define SHOWSYM 281
#define PATHNAME 282
#define BNF 283
#define LEX 284
#define ENDIR 285
#define ERRORSY 286
#define ENDSY 287
#define EMPTYSY 288
#define READVALSY 289
#define LEXDEF 290
#define CHARCLASS 291
#define ANTICHARCLASS 292
#define LBEGIN 293
#define ARROW 294
#define PLUSPLUS 295
#define MINUSMINUS 296
#define DOTDOT 297
#define VEL 298
#define GE 299
#define NE 300
#define LE 301
#define REM 302
#define DIV 303
#define INFIXNAME 304
#define INFIXCNAME 305
#define CMBASE 306
#define YYERRCODE 256
typedef int YYINT;
static const YYINT yylhs[] = {                           -1,
    0,    0,    0,    0,    0,    0,    1,    1,    2,    2,
    4,    4,    4,    6,    6,    7,    7,    7,    7,    7,
    7,    7,    7,    7,    7,    7,    7,    7,    7,    7,
    7,    8,    8,    8,    8,    8,    8,    9,    9,   10,
   10,   10,   10,   11,   11,   11,   15,   15,   15,   13,
   13,   17,   18,   19,   19,   14,   20,   20,    5,    5,
    5,    5,    5,    5,    5,    5,   23,   23,   23,   23,
   23,   23,   23,   23,   23,   23,   23,   23,   23,   22,
   22,   22,   22,   22,   22,   22,   22,   22,   22,   22,
   22,   25,   25,   25,   25,   25,   25,   25,   25,   25,
   25,   25,   25,   25,   25,   25,   25,   25,   25,   25,
   25,   25,   26,   26,   26,   27,   27,   27,   27,   27,
   28,   28,   21,   21,   24,   24,   24,   30,   29,   29,
   29,   29,   29,   29,   29,   29,   29,   29,   29,   29,
   29,   29,   29,   29,   29,   29,   29,   29,   29,   29,
   35,   37,   31,   31,   33,   33,   39,   39,   36,   36,
   36,   38,   38,   34,   34,   40,   40,   40,   41,   41,
   42,   42,   42,   42,   43,   43,   43,   43,   43,   43,
   44,   44,   32,   32,   32,   32,   45,   45,   46,   46,
    3,    3,   47,   47,   47,   47,   47,   47,   47,   47,
   63,   47,   57,   60,   60,   65,   65,   66,   66,   61,
   61,   67,   67,   68,   68,   68,   16,   54,   49,   12,
   12,   69,   69,   69,   69,   70,   70,   48,   48,   71,
   71,   71,   71,   71,   72,   72,   73,   73,   73,   73,
   73,   73,   73,   73,   55,   55,   74,   74,   75,   75,
   76,   76,   77,   77,   77,   77,   77,   79,   79,   79,
   80,   80,   58,   58,   58,   58,   58,   58,   58,   58,
   59,   59,   50,   52,   52,   84,   82,   83,   83,   51,
   51,   53,   53,   53,   53,   81,   81,   78,   78,   85,
   85,   56,   86,   86,   87,   87,   89,   89,   89,   88,
   88,   90,   90,   62,   62,   64,   64,   64,   64,   91,
   92,   94,   92,   93,   95,   95,   95,   97,   97,   98,
  100,   98,   96,  101,   96,   99,   99,  103,   99,  102,
  102,  104,  104,  104,  104,  105,  105,  105,  105,  106,
  106,  106,  106,  107,  108,  106,  106,
};
static const YYINT yylen[] = {                            2,
    1,    1,    2,    2,    3,    3,    0,    1,    1,    1,
    1,    1,    1,    1,    1,    1,    1,    1,    1,    1,
    1,    1,    1,    1,    1,    1,    1,    1,    1,    1,
    1,    1,    1,    1,    1,    1,    1,    1,    1,    3,
    3,    1,    1,    4,    3,    4,    2,    5,    4,    0,
    1,    0,    1,    1,    1,    0,    1,    3,    2,    3,
    3,    3,    3,    3,    1,    1,    2,    3,    2,    3,
    2,    3,    2,    3,    2,    3,    2,    1,    1,    2,
    2,    3,    3,    3,    3,    3,    3,    3,    3,    3,
    1,    2,    2,    3,    2,    3,    2,    3,    2,    3,
    2,    3,    2,    3,    2,    3,    2,    3,    2,    3,
    2,    1,    3,    3,    1,    3,    2,    3,    2,    1,
    2,    1,    3,    3,    3,    2,    3,    0,    4,    1,
    1,    1,    1,    1,    1,    2,    3,    5,    7,    5,
    4,    7,    6,    5,    5,    3,    3,    4,    2,    5,
    0,    0,   11,    1,    0,    3,    1,    2,    0,    2,
    2,    6,    0,    3,    1,    3,    2,    1,    2,    1,
    2,    2,    2,    1,    3,    1,    1,    1,    1,    1,
    1,    1,    1,    1,    3,    3,    3,    1,    3,    6,
    1,    2,    7,    1,    7,    8,    8,    5,    5,    4,
    0,    7,    1,    0,    3,    2,    1,    5,    7,    0,
    1,    2,    1,    3,    3,    2,    0,    0,    0,    1,
    2,    1,    3,    3,    7,    1,    3,    1,    3,    3,
    2,    3,    3,    1,    1,    2,    1,    1,    1,    2,
    3,    2,    3,    5,    1,    3,    3,    1,    1,    1,
    2,    2,    1,    1,    3,    3,    5,    0,    1,    3,
    1,    3,    2,    3,    2,    2,    1,    2,    1,    1,
    2,    1,    6,    2,    1,    0,    7,    3,    1,    4,
    2,    2,    2,    3,    3,    1,    1,    1,    1,    0,
    2,    1,    1,    3,    4,    1,    3,    2,    2,    1,
    2,    2,    1,    0,    2,    1,    1,    2,    2,    6,
    0,    0,    4,    2,    1,    1,    3,    1,    4,    1,
    0,    7,    1,    0,    7,    1,    2,    0,    2,    1,
    2,    1,    3,    2,    2,    1,    2,    2,    2,    1,
    1,    1,    1,    0,    0,    5,    1,
};
static const YYINT yydefred[] = {                         0,
    1,    0,    0,  289,    0,    0,  239,  217,  217,    0,
    0,  288,    0,    0,    0,    2,    0,    0,  217,  191,
  219,  194,    0,    0,    0,    0,  235,    0,  130,  131,
  132,  135,   38,  134,  133,   17,   18,   19,   20,   21,
   32,   33,   39,   35,   36,   37,   16,    0,   23,   24,
   26,   25,   27,   28,   29,   30,   31,    0,    0,    0,
    0,    3,    9,    0,   13,   15,   22,   34,    0,    0,
   91,    0,  122,    0,    0,    0,  283,  282,    0,    0,
    0,    0,  231,  237,  238,  240,  226,    0,  242,    0,
  192,  201,  203,    0,   52,    0,  217,  218,  281,    0,
    0,    0,    0,  236,    0,    0,    0,    0,    0,    0,
   59,    0,  136,    0,    0,    0,    0,  149,    0,    0,
    0,    0,    0,    0,    0,   78,   79,  112,    0,    0,
    0,    0,    0,    0,    0,    0,    0,    0,    0,    0,
    0,    0,    0,    0,    0,    0,    0,  121,  163,    6,
    5,  291,    0,    0,    0,  219,    0,    0,   52,    0,
  207,    0,    0,    0,    0,    0,  213,    0,  241,    0,
  243,  304,    0,    0,  219,    0,  217,  229,  230,  232,
  233,  284,  285,    0,    0,    0,  137,    0,    0,    0,
    0,    0,  146,    0,    0,    0,    0,    0,    0,    0,
    0,    0,    0,    0,    0,    0,    0,    0,    0,    0,
  147,    0,    0,    0,    0,    0,    0,    0,    0,    0,
    0,    0,    0,    0,    0,    0,    0,   90,    0,  113,
  114,    0,    0,    0,  272,    0,    0,  218,  205,  206,
    0,    0,  216,   54,   55,  200,   53,  212,  227,    0,
    0,  267,  269,  270,    0,    0,  217,  280,    0,    0,
  183,    0,    0,  184,  188,  141,    0,    0,    0,   57,
    0,    0,    0,    0,    0,    0,  148,    0,    0,    0,
    0,    0,    0,    0,    0,    0,    0,    0,    0,    0,
  129,    0,  217,   52,    0,  199,  271,    0,    0,  214,
  215,  244,  305,    0,  268,  263,  265,  266,    0,  198,
    0,    0,  287,    0,    0,    0,  245,    0,    0,  250,
  254,    0,    0,    0,    0,    0,    0,  145,  140,    0,
    0,  138,  144,    0,  150,  157,    0,    0,    0,    0,
    0,  275,   52,    0,    0,    0,    0,  306,  307,  264,
    0,    0,    0,  253,  251,    0,    0,    0,    0,    0,
  252,  273,    0,    0,    0,  219,    0,    0,  293,  217,
    0,    0,    0,    0,  187,  186,  185,  143,    0,    0,
   58,  158,  156,  181,  182,  176,  177,  178,  179,    0,
   52,    0,    0,    0,    0,  180,    0,    0,  195,  274,
  217,  208,    0,    0,    0,  202,  308,  309,    0,    0,
  193,    0,    0,    0,  256,    0,  255,    0,  247,    0,
    0,  299,    0,  301,    0,    0,    0,  298,    0,    0,
  142,  139,    0,  151,    0,    0,  169,  172,  171,  173,
    0,  278,  276,    0,   52,  304,    0,  219,  222,    0,
  220,   51,   45,    0,    0,  217,    0,    0,    0,  297,
  197,  294,    0,  302,  196,    0,  175,    0,  164,  166,
  162,    0,  209,  217,    0,  221,   52,    0,   44,   46,
    0,    0,  257,  295,  190,    0,    0,    0,    0,  313,
    0,  224,  223,    0,    0,    0,    0,    0,    0,  314,
  315,    0,  318,    0,    0,  310,  217,    0,    0,  152,
  277,   52,  340,  342,  341,  347,  343,    0,    0,  330,
    0,    0,    0,    0,   52,    0,    0,   49,    0,  160,
  161,    0,    0,    0,  331,  335,  338,  337,  339,    0,
    0,  317,    0,    0,   48,  153,  217,  333,  345,  319,
  217,  225,    0,    0,    0,    0,  346,    0,  325,  322,
};
#if defined(YYDESTRUCT_CALL) || defined(YYSTYPE_TOSTRING)
static const YYINT yystos[] = {                           0,
  256,  257,  258,  265,  266,  267,  268,  272,  276,  277,
   45,   42,   91,   40,  308,  309,  311,  324,  325,  355,
  356,  358,  359,  361,  379,  380,  381,  386,  266,  267,
  268,  269,  275,  281,  289,  295,   58,  296,  298,   38,
   62,  299,   61,  300,  301,   60,   43,   45,   42,   47,
  302,  303,   94,   46,   33,  304,  305,  126,   35,   91,
   40,  310,  312,  313,  314,  315,  316,  317,  329,  330,
  334,  336,  337,  338,  310,  386,  393,  393,  324,  324,
  123,  368,  268,  266,  267,   93,  356,  378,   41,  356,
  355,  283,  324,  365,  357,   44,  325,  325,  357,   58,
   43,  304,  305,  381,  304,  305,   45,   35,  330,  126,
  313,  330,   93,  310,   45,  126,   35,   41,  310,  312,
  313,  315,  329,  330,  331,  332,  333,  335,  336,  295,
   58,  296,  298,   38,  316,   43,   45,   42,   47,  302,
  303,   94,   46,   33,  316,  304,  305,  337,  284,  261,
  263,  393,  266,  267,  359,  361,  123,  266,  361,  373,
  374,  266,  267,   45,  369,  375,  376,   44,   93,   44,
   41,  371,  278,  325,  361,  324,  362,  356,  268,  379,
  379,  386,  386,  274,  297,   44,   93,  124,  330,  313,
  330,   44,   41,  295,   58,  296,  298,   38,  313,  316,
   43,   45,   42,   47,  302,  303,   94,   46,   33,  316,
   41,  304,  305,  313,  313,  313,  313,  313,  330,  330,
  330,  330,  330,  330,  330,  330,  330,  330,  330,  334,
  334,  339,  346,  325,  358,  367,  325,  325,  125,  374,
   47,   47,  266,  270,   59,  326,  327,  376,  356,  378,
  370,  266,  282,   43,   45,  366,   61,  357,  263,  324,
  310,  313,  340,  353,  354,   93,  310,  310,  340,  310,
  328,  313,  313,  313,  313,  313,   41,  330,  330,  330,
  330,  330,  330,  330,  330,  330,  330,  330,  334,  334,
  285,   60,  341,  290,  273,  125,  358,   61,  362,  266,
  267,   41,  266,  326,  266,  266,  282,   43,   45,  326,
  324,  266,  279,   91,   40,  363,  382,  383,  384,  385,
  386,  389,  264,  275,  262,   44,   59,   93,   93,  297,
   44,   93,   93,   44,   41,  267,  347,  324,  325,  266,
  360,  390,  391,  310,  275,  266,  372,  390,  399,  266,
  310,  318,  319,  266,  385,  363,  363,  387,  294,  304,
  385,  326,   40,  324,  363,  364,  385,  394,  395,  396,
  397,  363,  310,  313,  353,  310,  353,   93,  310,  328,
  310,  267,   62,  266,  267,  268,  291,  292,   46,   40,
  342,  348,  349,  350,  351,  352,   61,   44,  326,  390,
  325,  326,  363,  400,  402,  285,  390,  399,  259,   44,
  326,  259,  322,   44,   93,   44,   41,  363,  382,  363,
  395,  267,  357,   33,  124,  324,  385,  398,  357,   44,
   93,   93,  342,  325,  124,   47,  349,   43,   42,   63,
  342,  391,  324,  357,   58,   40,  320,  356,  358,  361,
  377,  260,  280,  321,  320,  271,  363,  388,  388,   41,
  326,  395,  305,   33,  326,  310,   41,  343,  342,  349,
  326,  392,  326,  325,  370,  377,  357,  324,  310,  323,
  324,   44,   93,  396,  297,  294,  263,  324,  401,   41,
  325,  264,  275,  310,  363,  310,  363,  286,  288,  403,
  404,  405,  406,  407,  411,  326,   61,   44,  293,  344,
  326,  409,  266,  268,  287,   45,   94,  123,  410,  412,
  413,  414,  415,  124,  408,  410,  324,  280,  321,  267,
  268,  345,  325,  413,  412,  125,   43,   42,   63,   91,
  324,  404,  325,  318,  310,  326,   61,  125,  310,  406,
   61,  326,  324,  416,  324,  318,   93,  318,  326,  326,
};
#endif /* YYDESTRUCT_CALL || YYSTYPE_TOSTRING */
static const YYINT yydgoto[] = {                         15,
   16,  351,   17,   63,   64,   65,   66,   67,   68,  352,
  353,  447,  454,  413,  480,  364,   19,  246,  247,  271,
   69,   70,  125,  126,  127,   71,  128,   72,   73,   74,
  232,  263,  293,  391,  468,  510,  532,  233,  337,  392,
  393,  394,  395,  396,  264,  265,   20,  448,   99,  449,
   23,  341,  450,  177,  365,  366,   94,  256,  236,   82,
  165,  251,  172,  347,  160,  161,  166,  167,  451,   88,
   25,   26,   27,  317,  318,  319,  320,  321,  358,  458,
  322,  342,  343,  472,   77,  368,  369,  370,  371,  428,
  349,  404,  489,  405,  500,  501,  502,  503,  504,  525,
  512,  519,  505,  520,  521,  522,  523,  554,
};
static const YYINT yysindex[] = {                      2787,
    0, 2043, 2043,    0,   34,   34,    0,    0,    0,   52,
    4,    0, 1019, 1012,    0,    0, 2644,  -48,    0,    0,
    0,    0,  264,    0,  171,  -17,    0, -211,    0,    0,
    0,    0,    0,    0,    0,    0,    0,    0,    0,    0,
    0,    0,    0,    0,    0,    0,    0,  886,    0,    0,
    0,    0,    0,    0,    0,    0,    0,  500,  886, 1579,
 1770,    0,    0,   21,    0,    0,    0,    0,  659, 2165,
    0,  132,    0,   71,  203,   34,    0,    0,  538,  249,
  630,  364,    0,    0,    0,    0,    0,   38,    0,  126,
    0,    0,    0,  119,    0,  538,    0,    0,    0,  704,
  243,  704,  704,    0,   34,   34,  886,  886,   18,  500,
    0,  426,    0,  -22,  886,  500,  886,    0,  443,  485,
  238,  500,  659, 2246,  491,    0,    0,    0,  180,  500,
  500,  500,  500,  500,  886,  886,  886,  886,  886,  886,
  886,  886,  886,  886,  886,  716,  716,    0,    0,    0,
    0,    0,   34,   34,  264,    0,  538,   34,    0,  590,
    0,  540,  550,  340,  -27,  364,    0,  704,    0,  704,
    0,    0,  461,  584,    0,  395,    0,    0,    0,    0,
    0,    0,    0, 2043, 1852, 2043,    0, 2043,   18,    0,
  426, 2043,    0,  500,  500,  500,  500,  500,   82,  886,
  886,  886,  886,  886,  886,  886,  886,  886,  886,  886,
    0,  716,  716,   21,   21,   21,   -1,  621,    3,   18,
   18,  143,  143,  143,  143,  143,  426,    0,    3,    0,
    0,  -44,  374,  423,    0,  795,  639,    0,    0,    0,
  437,  438,    0,    0,    0,    0,    0,    0,    0,  152,
  324,    0,    0,    0,  460,  517,    0,    0,  898, -158,
    0,   61,   80,    0,    0,    0,  611,  -41,  139,    0,
  184,   21,   21,   21,   -1,  621,    0,    3,   18,   18,
  143,  143,  143,  143,  143,  426,    0,    3,    0,    0,
    0,  473,    0,    0,  486,    0,    0, 2043,  490,    0,
    0,    0,    0,  522,    0,    0,    0,    0,  535,    0,
 2043,  825,    0, 1008, 1008,  502,    0,  531,  825,    0,
    0,  -27, 1043, 1008, 2043,  500, 2043,    0,    0, 1892,
 2043,    0,    0, 2043,    0,    0,  -29,  446,  766,  798,
  344,    0,    0,  -27, 1008,  798, -197,    0,    0,    0,
   14,  -27,  587,    0,    0,  -25,   10,  808, 1008, 1008,
    0,    0, 1043,  583,  502,    0,  821,  736,    0,    0,
  825,  502,  817,   61,    0,    0,    0,    0,  778,  113,
    0,    0,    0,    0,    0,    0,    0,    0,    0,  446,
    0,  759,  851,  446,  191,    0,  446,  486,    0,    0,
    0,    0,  502,  841,  860,    0,    0,    0, 1203,  -83,
    0, 1203,  641, 1008,    0, 1008,    0,  502,    0,   10,
  876,    0,  -27,    0, 1043,  619,  892,    0,  -27, 2043,
    0,    0,  894,    0,  446,  446,    0,    0,    0,    0,
  -27,    0,    0,  -27,    0,    0, 1203,    0,    0,    0,
    0,    0,    0, 2043, 1203,    0,  502,  115,  889,    0,
    0,    0, 1008,    0,    0,  642,    0,  643,    0,    0,
    0,  679,    0,    0,  142,    0,    0,  274,    0,    0,
 2043, 1008,    0,    0,    0, 2043, 1008,  644,  -27,    0,
  893,    0,    0,  917,  502,  669,   48,    0,  505,    0,
    0,  842,    0,    0,  505,    0,    0,  573,  235,    0,
    0,    0,    0,    0,    0,    0,    0,  359,  505,    0,
  840,  850,  877,  683,    0,  505, 2043,    0, 2043,    0,
    0,  -27,  914,  856,    0,    0,    0,    0,    0, 2043,
  702,    0,  925,  -27,    0,    0,    0,    0,    0,    0,
    0,    0, 2043,  903, 2043,  -27,    0,  -27,    0,    0,
};
static const YYINT yyrindex[] = {                         6,
    0,  715,  715,    0,  689, 1415,    0,    0,    0,  289,
    0,    0,    0,    0,    0,    0,   15,    0,    0,    0,
    0,    0,  737,  332,  568, 1159,    0,    0,    0,    0,
    0,    0,    0,    0,    0,    0,    0,    0,    0,    0,
    0,    0,    0,    0,    0,    0,    0, 1302,    0,    0,
    0,    0,    0,    0,    0,    0,    0, 1392, 1438,  715,
  715,    0,    0,   67,    0,    0,    0,    0, 1191, 1231,
    0,   91,    0,    0, 1002,  329,    0,    0,    0,    0,
    0,  141,    0,    0,    0,    0,    0,    0,    0,    0,
    0,    0,    0,    0,    0,    0,    0,    0,    0,    0,
    0,    0,    0,    0,    0,    0,  715,  715,  843,  715,
    0,  219,    0,    0,  -10,   31,   74,    0,    0,  959,
  965,  101,   72,  201,    0,    0,    0,    0, 1476,  715,
  715,  715,  715,  715,  715,  715,  715,  715,  715,  715,
  715,  715,  715,  715,  715,  715,  715,    0,    0,    0,
    0,    0,  325,  387,  738,    0,    0,  -33,    0,    0,
    0,    0,    0,    0,    0,  159,    0,    0,    0,    0,
    0,    0,    0,    0,    0,    0,    0,    0,    0,    0,
    0,    0,    0,  715,  715,  715,    0,  715, 2401,  172,
 2356,  715,    0,   40,   55,   60,  122,  123,    0,  715,
  130,  160,  161,  166,  170,  176,  195,  245,  269,  270,
    0,  273,  294, 1466, 1491, 1530, 1339, 1282, 1089,  963,
 1036,  381,  577,  648,  717,  770,  523,    0, 1146,    0,
    0,  623,  431,    0,    0,    0,    0,    0,    0,    0,
    0,    0,    0,    0,    0,    0,    0,    0,    0,    0,
    0,    0,    0,    0,    0,    0,    0,    0,    0,    0,
    0,  520,    0,    0,    0,    0,    0,    0,    0,    0,
    0,  503,  698,  818,  100,  305,    0, 2715, 2647, 2707,
 2441, 2512, 2522, 2562, 2602, 2431, 1969, 2722, 2240, 2316,
    0,    0,    0,    0,    0,    0,    0,  715,    0,    0,
    0,    0,    0,    0,    0,    0,    0,    0,    0,    0,
  715,   -3,    0,    0,  985,  288,    0,  281,  564,    0,
    0,    0,  763,    0,  715,  715,  715,    0,    0,  715,
  715,    0,    0,  715,    0,    0,    0,    0,    0,  771,
    0,    0,    0,    0,    0,  -16,    0,    0,    0,    0,
  478,    0,  145,    0,    0,    0,  994,    0,    0,    0,
    0,    0,  -14,    0,   -2,    0,  168,  484,    0,    0,
  487,  504,  609,    0,    0,    0,    0,    0,    0,    0,
    0,    0,    0,    0,    0,    0,    0,    0,    0,    0,
    0,  140,  -24,  371, 1133,    0,    0,    0,    0,    0,
    0,    0,  504,    0,    0,    0,    0,    0,    0, 1934,
    0,    0,    0,    0,    0,    0,    0,  -15,    0,  -20,
    0,    0,    0,    0,  763,    0, 1153,    0,    0,  715,
    0,    0,    0,    0,    0,  417,    0,    0,    0,    0,
    0,    0,    0,    0,    0,    0,  530,    0,    0,  527,
    0,    0,    0,  715,  574,    0,  138,    0,  996,    0,
    0,    0,    0,    0,    0,    0,    0,    0,    0,    0,
    0,    0,    0,    0,    0,    0,    0,    0,    0,    0,
  715,    0,    0,    0,    0,  715,    0,  407,    0,    0,
    0,    0,    0,  465,  954,  575,    0,  165,  448,    0,
    0,  612,    0,  805,  947,    0,    0, 1934,    0,    0,
    0,    0,    0,    0,    0,    0,    0,  947, 1097,    0,
 1583, 1896,    0,  640,    0, 1288,  715,    0,  715,    0,
    0,    0,    0, 1735,    0,    0,    0,    0,    0,  715,
  407,    0,    0,    0,    0,    0,    0,    0,    0,    0,
    0,    0,  715,    0,  715,    0,    0,    0,    0,    0,
};
#if YYBTYACC
static const YYINT yycindex[] = {                         0,
    0,    0,    0,    0,    0,    0,    0,    0,    0,    0,
    0,    0,    0,    0,    0,    0,    0,    0,    0,    0,
    0,    0,    0,    0,    0,    0,    0,    0,    0,    0,
    0,    0,    0,    0,    0,    0,    0,    0,    0,    0,
    0,    0,    0,    0,    0,    0,    0,    0,    0,    0,
    0,    0,    0,    0,    0,    0,    0,    0,    0,    0,
    0,    0,    0,    0,    0,    0,    0,    0,    0,    0,
    0,    0,    0,    0,    0,    0,    0,    0,    0,    0,
    0,    0,    0,    0,    0,    0,    0,    0,    0,    0,
    0,    0,    0,    0,    0,    0,    0,    0,    0,    0,
    0,    0,    0,    0,    0,    0,    0,    0,    0,    0,
    0,    0,    0,    0,    0,    0,    0,    0,    0,    0,
    0,    0,    0,    0,    0,    0,    0,    0,    0,    0,
    0,    0,    0,    0,    0,    0,    0,    0,    0,    0,
    0,    0,    0,    0,    0,    0,    0,    0,    0,    0,
    0,    0,    0,    0,    0,    0,    0,    0,    0,    0,
    0,    0,    0,    0,    0,    0,    0,    0,    0,    0,
    0,    0,    0,    0,    0,    0,    0,    0,    0,    0,
    0,    0,    0,    0,    0,    0,    0,    0,    0,    0,
    0,    0,    0,    0,    0,    0,    0,    0,    0,    0,
    0,    0,    0,    0,    0,    0,    0,    0,    0,    0,
    0,    0,    0,    0,    0,    0,    0,    0,    0,    0,
    0,    0,    0,    0,    0,    0,    0,    0,    0,    0,
    0,    0,    0,    0,    0,    0,    0,    0,    0,    0,
    0,    0,    0,    0,    0,    0,    0,    0,    0,    0,
    0,    0,    0,    0,    0,    0,    0,    0,    0,    0,
    0,    0,    0,    0,    0,    0,    0,    0,    0,    0,
    0,    0,    0,    0,    0,    0,    0,    0,    0,    0,
    0,    0,    0,    0,    0,    0,    0,    0,    0,    0,
    0,    0,    0,    0,    0,    0,    0,    0,    0,    0,
    0,    0,    0,    0,    0,    0,    0,    0,    0,    0,
    0,    0,    0,    0,    0,    0,    0,    0,    0,    0,
    0,    0,    0,    0,    0,    0,    0,    0,    0,    0,
    0,    0,    0,    0,    0,    0,    0,    0,    0,    0,
    0,    0,    0,    0,    0,    0,    0,    0,    0,    0,
    0,    0,    0,    0,    0,    0,    0,    0,    0,    0,
    0,    0,    0,    0,    0,    0,    0,    0,    0,    0,
    0,    0,    0,    0,    0,    0,    0,    0,    0,    0,
    0,    0,    0,    0,    0,    0,    0,    0,    0,    0,
    0,    0,    0,    0,    0,    0,    0,    0,    0,    0,
    0,    0,    0,    0,    0,    0,    0,    0,    0,    0,
    0,    0,    0,    0,    0,    0,    0,    0,    0,    0,
    0,    0,    0,    0,    0,    0,    0,    0,    0,    0,
    0,    0,    0,    0,    0,    0,    0,    0,    0,    0,
    0,    0,    0,    0,    0,    0,    0,    0,    0,    0,
    0,    0,    0,    0,    0,    0,    0,    0,    0,    0,
    0,    0,    0,    0,    0,    0,    0,    0,    0,    0,
    0,    0,    0,    0,    0,    0,    0,    0,    0,    0,
    0,    0,    0,    0,    0,    0,    0,    0,    0,    0,
    0,    0,    0,    0,    0,    0,    0,    0,    0,    0,
    0,    0,    0,    0,    0,    0,    0,    0,    0,    0,
    0,    0,    0,    0,    0,    0,    0,    0,    0,    0,
    0,    0,    0,    0,    0,    0,    0,    0,    0,    0,
    0,    0,    0,    0,    0,    0,    0,    0,    0,    0,
    0,    0,    0,    0,    0,    0,    0,    0,    0,    0,
    0,    0,    0,    0,    0,    0,    0,    0,    0,    0,
};
#endif
static const YYINT yygindex[] = {                         0,
    0,    2,    0,  978, 2259,    0,  981,  904,    0,  198,
    0,  631,  541,    0,    0,    1,  -12, -249,    0,  720,
  993, 2932,    0,    0,    0,    9,    0,  997,   76,    0,
    0,  858,    0, -350,    0,    0,    0,    0,    0,    0,
 -267,    0,    0,    0,  247,    0, 1038, 1201,  -21,  510,
  999,    0,  649,  838, 2569,    0,    0,    0,    0,    0,
    0,  636,    0,    0,    0,  924,    0,  920, -394,  918,
  551,    0, 1066,  733,    0,    0, 1285,    8,    0,  684,
    0, -261,  703,    0,   49,    0, -297,  645,    0,    0,
  760,    0,    0,    0,    0,  585,    0,  570,    0,    0,
    0,  610,    0, -449,  598,    0,    0,    0,
};
#define YYTABLESIZE 3142
static const YYINT yytable[] = {                         95,
   18,  304,  331,   62,   75,    7,  310,   28,   79,   80,
   97,   98,   76,   76,    8,  292,  168,   18,  414,   93,
  259,  186,   14,  312,   28,  246,  258,   52,  246,  253,
   14,  245,  383,   14,  168,  144,  134,  253,  300,  433,
  253,  311,  348,  246,  138,  136,  441,  137,  143,  139,
  144,  332,  476,  416,   78,  253,  300,  410,  134,  138,
  476,  114,  119,  143,  139,  421,   10,  415,  346,  535,
  187,   11,  362,   13,   11,   12,  535,  246,  131,  400,
   69,  168,  174,   76,  469,  407,   28,  406,   28,  253,
  115,  399,  105,  106,  402,   71,  142,  176,  134,  168,
   73,  188,  411,   28,  326,  323,  245,   10,  246,   65,
   10,  142,  182,  183,   12,   65,  324,   12,  131,  134,
  253,  300,  277,  115,  152,   10,  437,  462,  115,   65,
  169,  115,  115,  115,  115,  115,  115,  115,  327,  131,
   74,   15,  234,   63,   15,  237,  238,  148,  115,  115,
  115,  115,  115,  258,  230,  231,  334,   63,  482,   10,
   76,   76,   75,   77,   28,   76,  171,   28,  470,  170,
   95,   61,  328,  461,   81,  144,  452,  260,  261,  465,
  165,  261,  490,  115,  115,  261,  267,  268,  143,  261,
   10,  471,  302,  270,  473,  168,  453,  327,  165,  210,
   97,   99,   78,   43,  148,  432,  101,  483,  250,   59,
  105,  250,   67,  101,  115,   59,  103,  211,   81,   61,
  289,  290,   60,  323,  335,  324,  250,  334,  100,   59,
  261,  333,  439,  438,   92,  107,  142,  382,   66,  506,
  291,  290,  244,   28,   66,  168,  279,  511,   84,   85,
    7,  184,  217,  440,  246,  330,   81,  311,   66,   81,
   81,   81,   81,   81,   81,   81,  253,  300,  359,  168,
   60,   83,  409,  128,  185,  198,   81,   81,   81,   81,
   81,  339,  546,   52,  300,  109,  102,  103,  217,  246,
  253,  250,   52,  338,  552,  195,  133,  217,    4,  344,
  253,  253,  300,  359,  140,  141,  559,   96,  560,  111,
  126,   81,   81,  117,  128,  130,  132,  244,  133,  140,
  141,  248,  325,  128,  248,   10,  373,   10,  376,   10,
  401,  379,  270,  204,  119,  381,   10,   10,  128,  248,
   10,  359,   81,  128,  423,   76,  286,  204,   64,  115,
  429,  115,  115,  115,  149,  130,  132,  128,  133,   10,
  115,  115,   64,   10,  115,  115,   65,   65,  290,   65,
  426,  157,  290,  248,  128,  219,  130,  132,  434,  133,
   84,  444,  245,  115,  128,  115,  115,  115,  115,  115,
  115,  115,  115,  115,   63,   63,  173,   29,   30,   31,
   32,  443,  245,  516,  248,  128,  128,  303,  164,  165,
  210,  170,   34,  128,   43,   56,   28,  170,   84,   28,
   35,   84,   84,   84,   84,   84,  477,   84,  211,  170,
  290,  466,  474,  165,  323,  146,  147,  250,   84,   84,
   84,   84,   84,  128,  128,   29,   30,   31,   32,  128,
  478,  328,  517,  128,   28,  479,  481,  167,  144,  128,
   34,  250,   28,  150,  491,  151,   59,   59,   35,   59,
  154,  250,  250,   84,  488,  167,  154,   81,  128,   81,
   81,   81,  494,  212,  213,  390,  192,  496,   81,   81,
  154,  389,   81,   81,  170,   66,   66,  328,   66,  533,
  328,  530,  531,  254,   84,  255,  326,  527,  326,   22,
  179,   81,  543,   81,   81,   81,   81,   81,   81,   81,
   81,   81,   89,   47,  541,  193,   22,  296,  128,  328,
  545,  211,  194,  196,  108,  197,   42,  492,  344,   61,
  167,  549,  292,   68,  107,  296,   60,  553,  493,  516,
  248,  555,  128,  128,  204,  204,  128,  286,  204,  308,
   89,  309,  219,   89,   89,   89,   89,   89,   89,   89,
  219,  326,  375,  377,  248,  245,   85,  128,   10,   12,
   89,   89,   89,   89,   89,  248,  241,  290,   41,  303,
   60,  290,  290,  244,  219,   52,  242,  290,  517,   64,
   64,  290,   64,  290,  249,  243,   52,  249,  228,  340,
  296,  228,   10,  244,   85,   89,   89,   85,   85,   85,
   85,   85,  249,   85,  513,  110,  514,  518,  228,  162,
  163,   12,   40,  159,   85,   85,   85,   85,   85,   84,
  170,   84,   84,   84,  257,  515,   89,   87,   24,  290,
   84,   84,  180,  181,   84,   84,  249,  259,  134,  290,
  228,  290,  155,  294,  170,   24,  235,  189,  155,   85,
  316,   12,  328,   84,  328,   84,   84,   84,   84,   84,
   84,   84,   84,   84,  217,   87,  167,  249,   87,   87,
   87,   87,   87,  328,   87,  295,  154,  154,  154,  298,
   85,  189,  300,  329,  301,   87,   87,   87,   87,   87,
  167,  384,  385,  386,  239,  154,   86,  326,   46,   43,
   41,  154,  154,   47,  544,  305,  252,  156,  237,  159,
  217,  237,  290,  217,   47,   47,  387,  388,   70,  336,
   87,   61,  253,   14,  175,  297,  237,   42,   11,  237,
  556,  340,  558,  292,   86,   61,  296,   86,   86,   86,
   86,   86,  217,   86,  345,   29,   30,   31,   32,   88,
  513,   87,  514,  219,   86,   86,   86,   86,   86,  237,
   34,   89,  306,   89,   89,   89,  244,  346,   35,  219,
  217,  515,   89,   89,   13,  359,   89,   89,  307,   41,
  350,  217,    4,  153,  154,  156,   60,   88,  159,   86,
   88,   88,   88,   88,   88,   89,   88,   89,   89,   89,
   89,   89,   89,   89,   89,   89,  397,   88,   88,   88,
   88,   88,  452,  249,  360,   85,   12,   85,   85,   85,
   86,  398,   80,   40,  159,  412,   85,   85,  417,  422,
   85,   85,  528,  424,    4,  158,  154,  249,   72,  425,
  430,   62,   88,  320,  315,  321,   12,  249,  249,   85,
  431,   85,   85,   85,   85,   85,   85,   85,   85,   85,
   80,  316,  435,   80,  156,   80,   80,   80,  155,  155,
  155,  538,  537,   88,    4,  158,  154,  436,  445,  446,
   80,   80,   80,   80,   80,  217,   87,  217,   87,   87,
   87,  456,  539,  155,  155,  314,  460,   87,   87,  296,
  108,   87,   87,  463,  464,   61,  217,  217,  320,  498,
  107,  499,  482,   33,  467,   80,  486,  315,  485,   12,
   87,  487,   87,   87,   87,   87,   87,   87,   87,   87,
   87,  290,  290,  507,  237,  237,  237,   42,   44,   45,
  508,  509,   82,  290,  536,  524,   80,  540,  498,   84,
   85,    7,  135,  145,  547,   86,   60,   86,   86,   86,
  548,   29,   30,   31,   32,  551,   86,   86,  314,  499,
   86,   86,  237,  237,  262,  557,   34,  262,  128,   52,
   82,    4,    9,   82,   35,   82,   82,   82,   10,   86,
   52,   86,   86,   86,   86,   86,   86,   86,   86,   86,
   82,   82,   82,   82,   82,  258,  200,  210,   88,  217,
   88,   88,   88,  279,  259,   83,  260,  344,  120,   88,
   88,  122,  455,   88,   88,  269,  262,  315,  529,   12,
  380,   14,   89,  123,   91,   82,   11,  129,   14,    4,
  153,  154,   88,   11,   88,   88,   88,   88,   88,   88,
   88,   88,   88,   83,  320,  299,   83,  155,   83,   83,
   83,  475,  363,  240,   12,  248,   82,  250,  124,    4,
  354,  104,  419,   83,   83,   83,   83,   83,  314,  459,
  442,   80,   13,   80,   80,   80,  408,  484,  542,   13,
  550,   86,   80,   80,  526,  534,   80,   80,    0,    0,
    0,    0,    0,    0,    0,    0,  124,    0,   83,  124,
    0,    0,  124,  314,    0,   80,    0,   80,   80,   80,
   80,   80,   80,   80,    0,  123,  124,  124,  124,  124,
  124,   29,   30,   31,   32,  327,    0,  327,    0,   83,
    0,    0,    4,  312,    0,    0,   34,    0,    0,    0,
    0,    0,  174,  174,   35,    0,  313,    0,  174,  174,
    0,  124,    0,  123,    0,    0,  123,  344,    0,  123,
   65,  174,  303,  303,  303,    0,    0,    0,    0,  234,
   21,  234,  234,  123,  123,  123,  123,  123,    0,    0,
    0,  303,  124,   87,   90,    0,  234,   21,    0,  234,
  327,   82,    0,   82,   82,   82,    0,    0,   65,    0,
   66,   65,   82,   82,   65,    0,   82,   82,  123,    0,
    0,    0,   14,  303,   12,    0,    0,   11,   65,   65,
    0,  234,    0,    0,    0,   82,  174,   82,   82,   82,
   82,   82,   82,   82,    0,    0,    0,    0,   66,  123,
    0,   66,    4,  312,   66,    0,  303,   84,   85,    7,
    0,   64,    0,   65,   84,   85,    7,    0,   66,   66,
    0,    0,    0,   13,   83,    0,   83,   83,   83,    0,
  178,   14,    0,    0,    0,   83,   83,    4,  312,   83,
   83,    0,    0,    0,   65,    0,    0,    0,    0,    0,
    0,    0,   64,   66,    0,   64,    0,    0,   83,    0,
   83,   83,   83,   83,   83,   83,   83,    0,   63,   64,
   64,    0,   14,    0,    0,   14,  329,  124,  329,  124,
  124,  124,    0,    0,   66,    0,    0,    0,  124,  124,
   14,    0,  124,  124,    0,    0,  327,    0,  249,    0,
   87,    0,    0,    0,   64,    0,    0,    0,  344,   63,
    0,  124,   63,  124,  124,  124,  124,  124,  124,  124,
    0,   11,    0,    0,   14,    0,   63,   63,  174,  174,
  174,    0,  174,    0,  123,   64,  123,  123,  123,    0,
    0,  329,    0,    0,    0,  123,  123,  303,  303,  123,
  123,    0,  303,  174,  174,   14,  174,    0,    0,    0,
    0,   63,   11,    0,    0,   11,    0,   12,  123,    0,
  123,  123,  123,  123,  123,  123,  123,    0,    0,   65,
   11,   65,   65,   65,  238,    0,    0,  238,  290,    0,
   65,   65,   63,    0,   65,   60,    0,    4,    5,    6,
    7,    0,  238,    0,    0,  238,    0,    0,   12,    0,
    0,   12,    0,   65,   11,   65,   65,   65,   65,   66,
   61,   66,   66,   66,    0,    0,   12,    0,    0,    0,
   66,   66,    0,    0,   66,  238,   60,    0,  115,   60,
    0,    0,    0,  115,    0,   11,  120,  115,  115,  115,
  115,  115,  115,   66,   60,   66,   66,   66,   66,   62,
   12,   61,    0,  115,   61,  115,  115,  115,    0,    0,
   64,    0,   64,   64,   64,    0,    0,    0,    0,   61,
    0,   64,   64,    0,    0,   64,    0,  329,   60,    0,
   14,   12,   14,    0,   14,    0,    0,    0,    0,  115,
   62,   14,   14,   62,   64,   14,   64,   64,   64,   64,
    0,    0,    0,   61,    0,  128,    0,    0,   62,   60,
    0,    0,    0,    0,   14,    0,  355,   63,   14,   63,
   63,   63,    0,  361,    0,    0,    0,  367,   63,   63,
    0,   55,   63,   59,   61,    0,   40,    0,   61,    0,
   49,   47,   62,   48,   54,   50,    0,  332,    0,    0,
    0,   63,    0,   63,   63,   63,   37,    0,   46,   43,
   41,  332,    0,  332,    0,    0,    0,  367,    0,    0,
   11,    0,   11,   62,   11,  427,    0,    0,    0,    0,
    0,   11,   11,    0,    0,   11,    0,    0,    0,   60,
    0,  113,   53,  332,    0,  128,  332,  290,  290,    0,
  238,  238,  238,    0,   11,    0,    0,    0,   11,  290,
    0,    0,    0,    0,    0,    0,   12,    0,   12,    0,
   12,    0,    0,    0,   58,  332,  332,   12,   12,  367,
    0,   12,    0,    0,    0,    0,    0,    0,  238,  238,
    0,  128,    0,    0,   60,    0,   60,   60,   60,    0,
   12,    0,    0,    0,   12,   60,   60,    0,    0,   60,
    0,    0,    0,    0,    0,    0,    0,  367,    0,   61,
  115,   61,   61,   61,    0,    0,    0,    0,   60,  128,
   61,   61,   60,    0,   61,    0,    0,    0,    0,    0,
  115,  115,    0,  115,  115,  115,  115,  115,  115,  334,
    0,    0,    0,   61,    0,    0,    0,   61,   62,    0,
   62,   62,   62,  334,    0,  334,    0,    0,    0,   62,
   62,    0,   55,   62,  117,    0,    0,   40,    0,   61,
  118,   49,   47,    0,  115,   54,   50,    0,    0,    0,
    0,    0,   62,    0,    0,  334,   62,   37,  334,   46,
   43,   41,    0,    0,    0,    0,    0,    0,    0,    0,
    0,    0,    0,    0,   29,   30,   31,   32,  332,    0,
  332,    0,  332,   33,    0,    0,    0,  334,  334,   34,
   60,    0,    0,   53,    0,    0,    0,   35,    0,  332,
    0,    0,    0,   36,   38,    0,   39,   42,   44,   45,
   51,   52,   56,   57,   55,    0,   59,    0,    0,   40,
    0,   61,    0,   49,   47,  116,   48,   54,   50,    0,
    0,    0,    0,    0,    0,    0,    0,    0,    0,   37,
    0,   46,   43,   41,    0,    0,    0,    0,    0,    0,
    0,    0,    0,    0,   55,    0,   59,    0,    0,   40,
    0,   61,    0,   49,   47,    0,   48,   54,   50,    0,
  336,    0,   60,    0,  266,   53,    0,    0,    0,   37,
    0,   46,   43,   41,  336,    0,  336,    0,    0,    0,
    0,    0,    0,    0,    0,    0,   50,    0,   50,    0,
    0,   50,    0,   50,    0,   50,   50,   58,   50,   50,
   50,    0,   60,    0,  378,   53,  336,    0,    0,  336,
    0,   50,    0,   50,   50,   50,    0,    0,    0,    0,
  334,   90,  334,    0,  334,    0,   90,    0,    0,  110,
   90,   90,   90,   90,   90,   90,    0,   58,  336,  336,
  336,  334,    0,    0,   50,    0,   90,   50,   90,   90,
   90,    0,    0,    0,    0,   29,   30,   31,   32,    0,
    0,    0,    0,    0,   33,    0,    0,    0,    0,    0,
   34,    0,    0,    0,    0,    0,    0,    0,   35,   50,
    0,    0,   90,    0,   36,   38,    0,   39,   42,   44,
   45,   51,   52,   56,   57,   55,    0,   59,    0,    0,
   40,    0,   61,    0,   49,   47,    0,   48,   54,   50,
    0,    0,    0,    0,    0,    0,    0,    0,    0,    0,
   37,    0,   46,   43,   41,    0,    0,    0,    0,    0,
    0,    0,    0,    0,    0,    0,    0,   29,   30,   31,
   32,    0,    0,    0,    0,    0,   33,    0,    0,    0,
    0,    0,   34,   60,    0,    0,   53,    0,    0,    0,
   35,    0,    0,    0,    0,    0,   36,   38,    0,   39,
   42,   44,   45,   51,   52,   56,   57,   29,   30,   31,
   32,  336,    0,  336,    0,  336,   33,    0,   58,    0,
    0,    0,   34,    0,    0,    0,    0,    0,    0,    0,
   35,    0,  336,    0,    0,    0,   36,   38,    0,   39,
   42,   44,   45,   51,   52,   56,   57,  144,    0,   50,
   50,   50,   50,    0,    0,    0,  138,  136,   50,  137,
  143,  139,    0,    0,   50,    0,    0,   50,    0,    0,
    0,    0,   50,    0,   46,   43,   41,    0,   50,   50,
    0,   50,   50,   50,   50,   50,   50,   50,   50,    0,
    0,    0,    0,   90,    0,    0,    0,    0,    0,    0,
    0,    0,    0,    0,    0,    0,    0,    0,  142,    0,
    0,    0,    0,   90,   90,    0,   90,   90,   90,   90,
   90,   90,  113,    0,    0,    0,    0,  113,  209,    0,
  116,  113,  113,  113,  113,  113,  113,  203,  201,    0,
  202,  208,  204,    0,    0,    0,    0,  113,    0,  113,
  113,  113,    0,    0,    0,   46,   43,   41,   29,   30,
   31,   32,    0,    0,    0,    0,  111,   33,    0,  121,
    0,    0,    0,   34,    0,    0,    0,    0,    0,    0,
    0,   35,    0,  113,    0,    0,    0,   36,   38,  207,
   39,   42,   44,   45,   51,   52,   56,   57,  114,    0,
    0,    0,    0,  114,    0,    0,  118,  114,  114,  114,
  114,  114,  114,    0,    0,    0,    0,    0,  111,    0,
    0,    0,    0,  114,  190,  114,  114,  114,    0,    0,
  199,    0,    0,    0,    0,    0,    0,    0,  214,  215,
  216,  217,  218,   81,    0,    0,   93,   81,   81,   81,
   81,   81,   81,    0,    0,    0,    0,    0,    0,  114,
    0,    0,    0,   81,    0,   81,   81,   81,    0,    0,
    0,    0,    0,    0,    0,    0,    0,    0,    0,    0,
    0,    0,    0,    0,    0,    0,    0,    0,   80,   33,
    0,   92,  262,   80,   80,   80,  262,    0,    0,   81,
    0,    0,  272,  273,  274,  275,  276,    0,   80,    0,
   80,   80,   80,   42,   44,   45,  140,  141,   89,    0,
    0,  108,   89,   89,   89,   89,   89,   89,   84,    0,
    0,   98,   84,   84,   84,   84,    0,   84,   89,    0,
   89,   89,   89,    0,    0,    0,    0,    0,   84,    0,
   84,   84,   84,    0,    0,    0,    0,    0,    0,    0,
    0,    0,    0,    0,  113,    0,    0,    0,    0,    0,
   33,    0,    0,    0,   89,    0,    0,    0,    0,    0,
    0,    0,    0,    0,  113,  113,    0,  113,  113,  113,
  113,  113,  113,    0,   42,   44,   45,  205,  206,   85,
    0,    0,  100,   85,   85,   85,   85,    0,   85,   87,
    0,    0,  104,   87,   87,   87,   87,    0,   87,   85,
    0,   85,   85,   85,    0,    0,    0,    0,    0,   87,
    0,   87,   87,   87,  374,  262,    0,    0,    0,    0,
  114,    0,    0,    0,    0,    0,    0,    0,    0,   86,
    0,    0,  102,   86,   86,   86,   86,    0,   86,    0,
  114,  114,    0,  114,  114,  114,  114,  114,  114,   86,
    0,   86,   86,   86,    0,    0,    0,    0,    0,    0,
   81,    0,    0,    0,    0,    0,    0,    0,    0,   88,
    0,    0,  106,   88,   88,   88,   88,    0,   88,    0,
   81,   81,    0,   81,   81,   81,   81,   81,   81,   88,
    0,   88,   88,   88,    0,    0,    0,    0,    0,    0,
    0,    0,    0,    0,    0,   80,    0,    0,    0,    0,
    0,    0,    0,   14,   82,   12,    0,   94,   11,   82,
   82,   82,    0,    0,    0,   80,   80,    0,   80,   80,
   80,   80,    0,    0,   82,   89,   82,   82,   82,    0,
    0,    0,    0,    0,    0,   84,    0,    0,    0,    0,
    0,    0,    0,    0,    0,   89,   89,    0,   89,   89,
   89,   89,   89,   89,   13,   84,   84,    0,   84,   84,
   84,   84,   84,   84,   83,    0,    0,   96,    0,   83,
   83,   83,  124,    0,    0,  127,    0,    0,  124,  123,
    0,    0,  125,    0,   83,  123,   83,   83,   83,    0,
    0,    0,  124,    0,  124,  124,  124,    0,    0,  123,
    0,  123,  123,  123,    0,    0,   85,    0,    0,    0,
    0,    0,    0,    0,    0,    0,   87,    0,    0,    0,
    0,    0,    0,    0,    0,    0,   85,   85,    0,   85,
   85,   85,   85,   85,   85,    0,   87,   87,    0,   87,
   87,   87,   87,   87,   87,    0,   14,  316,   12,    0,
    0,   11,    0,    0,    0,    0,   86,    0,    0,    0,
    0,    0,    0,    0,    0,    0,    0,    0,    0,    0,
    0,    0,    0,    0,    0,    0,   86,   86,    0,   86,
   86,   86,   86,   86,   86,    0,    0,    0,    0,    0,
    0,    0,    0,    0,    0,    0,   88,   13,    0,    0,
    0,    0,  356,  357,    0,    0,    0,    0,    0,    0,
    0,    0,  372,    0,    0,    0,   88,   88,    0,   88,
   88,   88,   88,   88,   88,    0,    0,    0,    4,    5,
    6,    7,    0,  403,    0,    8,    0,    0,    0,    9,
   10,   82,    0,    0,    0,    0,    0,  418,    0,    0,
    0,  420,    0,    0,    0,    0,    0,    0,    0,    0,
    0,   82,   82,    0,   82,   82,   82,   82,    0,    0,
    0,    0,    0,    0,    0,    0,    0,    0,    0,    0,
    0,    0,    0,    0,    0,    0,    0,    0,    0,    0,
    0,    0,    0,    0,    0,    0,    0,    0,    0,  109,
    0,   83,  457,    0,  457,    0,    0,    0,    0,  124,
  112,    0,  124,    0,    0,    0,  123,    0,    0,    0,
    0,   83,   83,    0,   83,   83,   83,   83,    0,  124,
  124,    0,  124,  124,  124,  124,  123,  123,    0,  123,
  123,  123,  123,    0,    0,    0,    0,    0,    0,    0,
    0,    0,    0,    0,    0,    0,    0,    0,  109,  112,
    0,    0,    1,    2,    3,    0,  189,    0,  191,    0,
  495,    4,    5,    6,    7,  497,    0,    0,    8,    0,
    0,    0,    9,   10,    0,    0,  219,  220,  221,  222,
  223,  224,  225,  226,  227,  228,  229,    0,    0,    0,
    0,    0,    0,    0,    0,    0,    0,    0,    0,    0,
    0,    0,    0,    0,    0,    0,    0,    0,    0,    0,
    0,    0,    0,    0,    0,    0,    0,    0,    0,    0,
    0,    0,    0,    0,    0,    0,    0,    0,    0,    0,
    0,    0,    0,    0,    0,    0,    0,    0,    0,    0,
    0,  278,  279,  280,  281,  282,  283,  284,  285,  286,
  287,  288,
};
static const YYINT yycheck[] = {                         21,
    0,  251,   44,    2,    3,    0,  256,    0,    8,    9,
   23,   24,    5,    6,    0,   60,   41,   17,   44,   19,
   41,   44,   40,   40,   17,   41,   41,   61,   44,   33,
   41,   59,   62,   44,   59,   33,   38,   41,   41,  390,
   44,   58,  304,   59,   42,   43,  397,   45,   46,   47,
   33,   93,  447,   44,    6,   59,   59,   44,   38,   42,
  455,   60,   61,   46,   47,  363,    0,   93,  266,  519,
   93,   41,  322,   91,   44,   42,  526,   93,   58,  341,
   41,   44,   95,   76,  435,  347,   79,  285,   81,   93,
    0,  341,  304,  305,  344,   41,   94,   97,   38,  124,
   41,  124,  352,   96,   44,  264,   59,   41,  124,   38,
   44,   94,  105,  106,   41,   44,  275,   44,   58,   38,
  124,  124,   41,   33,   76,   59,  394,  425,   38,   58,
   93,   41,   42,   43,   44,   45,   46,   47,   59,   58,
   41,   41,  155,   44,   44,  158,  159,   72,   58,   59,
   60,   61,   62,  175,  146,  147,   44,   58,   44,   93,
  153,  154,   41,   41,  157,  158,   41,  160,  436,   44,
   41,   40,   93,  423,  123,   33,  260,  177,   41,  429,
   41,   44,   41,   93,   94,  184,  185,  186,   46,  188,
  124,  441,   41,  192,  444,   44,  280,   59,   59,   59,
   41,   41,  154,   59,  129,   93,   41,   93,   41,   38,
   41,   44,   41,   43,  124,   44,   41,   59,    0,   40,
  212,  213,   91,   59,   41,   61,   59,   44,   58,   58,
   93,   93,   42,   43,  283,   41,   94,  267,   38,  489,
  285,  275,  270,  236,   44,  270,  263,  497,  266,  267,
  268,  274,  267,   63,  270,  297,   38,  257,   58,   41,
   42,   43,   44,   45,   46,   47,  270,  270,  294,  294,
   91,  268,  259,  284,  297,   38,   58,   59,   60,   61,
   62,  294,  532,  278,  305,   41,  304,  305,  283,  305,
  294,  124,  278,  293,  544,   58,  298,  283,  265,  298,
  304,  305,  305,  294,  302,  303,  556,   44,  558,   41,
   41,   93,   94,   41,  284,  295,  296,  270,  298,  302,
  303,   41,  262,  284,   44,  259,  325,  261,  327,  263,
  343,  330,  331,   45,   41,  334,  270,  271,  284,   59,
  274,  294,  124,  284,  366,   41,   59,   59,   44,  259,
  372,  261,  262,  263,  284,  295,  296,  284,  298,  293,
  270,  271,   58,  297,  274,  275,  295,  296,   44,  298,
  370,  123,   44,   93,  284,   44,  295,  296,  391,  298,
    0,  403,   59,  293,  284,  295,  296,  297,  298,  299,
  300,  301,  302,  303,  295,  296,  278,  266,  267,  268,
  269,  401,   59,   45,  124,  284,  284,  266,   45,  270,
  270,   41,  281,  284,  270,  271,  409,   47,   38,  412,
  289,   41,   42,   43,   44,   45,  448,   47,  270,   59,
   44,  430,  445,  294,  270,  304,  305,  270,   58,   59,
   60,   61,   62,  284,  284,  266,  267,  268,  269,  284,
  450,   45,   94,  284,  447,  454,  456,   41,   33,  284,
  281,  294,  455,  261,  477,  263,  295,  296,  289,  298,
   40,  304,  305,   93,  474,   59,   46,  259,  284,  261,
  262,  263,  481,  304,  305,   40,   44,  486,  270,  271,
   60,   46,  274,  275,  124,  295,  296,   91,  298,  512,
   94,  267,  268,   43,  124,   45,   59,  507,   61,    0,
  268,  293,  525,  295,  296,  297,  298,  299,  300,  301,
  302,  303,    0,   59,  524,   41,   17,   41,  284,  123,
  529,   41,  295,  296,   35,  298,   59,  264,   91,   40,
  124,  540,   59,   41,   45,   59,   44,  547,  275,   45,
  270,  551,  284,  284,  266,  267,  284,  270,  270,   43,
   38,   45,   59,   41,   42,   43,   44,   45,   46,   47,
   44,  124,  326,  327,  294,   59,    0,  284,   59,   42,
   58,   59,   60,   61,   62,  305,   47,  263,   59,  266,
   91,  263,  264,  270,  263,  264,   47,  273,   94,  295,
  296,  273,  298,  275,   41,  266,  275,   44,   41,  266,
  124,   44,   93,  270,   38,   93,   94,   41,   42,   43,
   44,   45,   59,   47,  266,  126,  268,  123,   61,  266,
  267,   42,   59,   59,   58,   59,   60,   61,   62,  259,
  270,  261,  262,  263,   61,  287,  124,    0,    0,  263,
  270,  271,  102,  103,  274,  275,   93,  263,   38,  273,
   93,  275,   40,  290,  294,   17,  157,   59,   46,   93,
   59,   42,  266,  293,  268,  295,  296,  297,  298,  299,
  300,  301,  302,  303,   45,   38,  270,  124,   41,   42,
   43,   44,   45,  287,   47,  273,  266,  267,  268,   61,
  124,   93,  266,   93,  267,   58,   59,   60,   61,   62,
  294,  266,  267,  268,  125,  285,    0,  270,   60,   61,
   62,  291,  292,  259,  527,  266,  266,   79,   40,   81,
   91,   43,   44,   94,  270,  271,  291,  292,   41,  267,
   93,   44,  282,   40,   96,  236,   58,  270,   45,   61,
  553,  266,  555,  270,   38,   40,  270,   41,   42,   43,
   44,   45,  123,   47,  275,  266,  267,  268,  269,    0,
  266,  124,  268,  270,   58,   59,   60,   61,   62,   91,
  281,  259,  266,  261,  262,  263,  270,  266,  289,  263,
  264,  287,  270,  271,   91,  294,  274,  275,  282,  270,
  266,  275,  265,  266,  267,  157,   91,   38,  160,   93,
   41,   42,   43,   44,   45,  293,   47,  295,  296,  297,
  298,  299,  300,  301,  302,  303,   61,   58,   59,   60,
   61,   62,  260,  270,  304,  259,   42,  261,  262,  263,
  124,   44,    0,  270,  270,  259,  270,  271,   41,  267,
  274,  275,  280,   33,  265,  266,  267,  294,   41,  124,
   44,   44,   93,   59,   40,   61,   42,  304,  305,  293,
   93,  295,  296,  297,  298,  299,  300,  301,  302,  303,
   38,  270,  124,   41,  236,   43,   44,   45,  266,  267,
  268,   42,   43,  124,  265,  266,  267,   47,   58,   40,
   58,   59,   60,   61,   62,  266,  259,  268,  261,  262,
  263,  271,   63,  291,  292,   91,   41,  270,  271,  125,
   35,  274,  275,  305,   33,   40,  287,  288,  124,  286,
   45,  288,   44,  275,   41,   93,  294,   40,  297,   42,
  293,  263,  295,  296,  297,  298,  299,  300,  301,  302,
  303,  263,  264,   61,  266,  267,  268,  299,  300,  301,
   44,  293,    0,  275,  125,  124,  124,   91,  286,  266,
  267,  268,   69,   70,   61,  259,   91,  261,  262,  263,
  125,  266,  267,  268,  269,   61,  270,  271,   91,  288,
  274,  275,  304,  305,   41,   93,  281,   44,  284,  263,
   38,    0,   44,   41,  289,   43,   44,   45,   44,  293,
  273,  295,  296,  297,  298,  299,  300,  301,  302,  303,
   58,   59,   60,   61,   62,   41,  123,  124,  259,  267,
  261,  262,  263,  263,   41,    0,   41,   91,   61,  270,
  271,   61,  412,  274,  275,  188,   93,   40,  508,   42,
  331,   40,   41,   61,   17,   93,   45,   61,   40,  265,
  266,  267,  293,   45,  295,  296,  297,  298,  299,  300,
  301,  302,  303,   38,  270,  238,   41,   79,   43,   44,
   45,  446,   40,  160,   42,  166,  124,  170,    0,  265,
  266,   26,  360,   58,   59,   60,   61,   62,   91,  416,
  398,  259,   91,  261,  262,  263,  347,  463,  524,   91,
  541,   93,  270,  271,  505,  518,  274,  275,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   38,   -1,   93,   41,
   -1,   -1,   44,   91,   -1,  293,   -1,  295,  296,  297,
  298,  299,  300,  301,   -1,    0,   58,   59,   60,   61,
   62,  266,  267,  268,  269,   59,   -1,   61,   -1,  124,
   -1,   -1,  265,  266,   -1,   -1,  281,   -1,   -1,   -1,
   -1,   -1,   40,   41,  289,   -1,  279,   -1,   46,   47,
   -1,   93,   -1,   38,   -1,   -1,   41,   91,   -1,   44,
    0,   59,   40,   41,   42,   -1,   -1,   -1,   -1,   41,
    0,   43,   44,   58,   59,   60,   61,   62,   -1,   -1,
   -1,   59,  124,   13,   14,   -1,   58,   17,   -1,   61,
  124,  259,   -1,  261,  262,  263,   -1,   -1,   38,   -1,
    0,   41,  270,  271,   44,   -1,  274,  275,   93,   -1,
   -1,   -1,   40,   91,   42,   -1,   -1,   45,   58,   59,
   -1,   93,   -1,   -1,   -1,  293,  124,  295,  296,  297,
  298,  299,  300,  301,   -1,   -1,   -1,   -1,   38,  124,
   -1,   41,  265,  266,   44,   -1,  124,  266,  267,  268,
   -1,    0,   -1,   93,  266,  267,  268,   -1,   58,   59,
   -1,   -1,   -1,   91,  259,   -1,  261,  262,  263,   -1,
  100,    0,   -1,   -1,   -1,  270,  271,  265,  266,  274,
  275,   -1,   -1,   -1,  124,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   41,   93,   -1,   44,   -1,   -1,  293,   -1,
  295,  296,  297,  298,  299,  300,  301,   -1,    0,   58,
   59,   -1,   41,   -1,   -1,   44,   59,  259,   61,  261,
  262,  263,   -1,   -1,  124,   -1,   -1,   -1,  270,  271,
   59,   -1,  274,  275,   -1,   -1,  270,   -1,  168,   -1,
  170,   -1,   -1,   -1,   93,   -1,   -1,   -1,   91,   41,
   -1,  293,   44,  295,  296,  297,  298,  299,  300,  301,
   -1,    0,   -1,   -1,   93,   -1,   58,   59,  266,  267,
  268,   -1,  270,   -1,  259,  124,  261,  262,  263,   -1,
   -1,  124,   -1,   -1,   -1,  270,  271,  265,  266,  274,
  275,   -1,  270,  291,  292,  124,  294,   -1,   -1,   -1,
   -1,   93,   41,   -1,   -1,   44,   -1,    0,  293,   -1,
  295,  296,  297,  298,  299,  300,  301,   -1,   -1,  259,
   59,  261,  262,  263,   40,   -1,   -1,   43,   44,   -1,
  270,  271,  124,   -1,  274,    0,   -1,  265,  266,  267,
  268,   -1,   58,   -1,   -1,   61,   -1,   -1,   41,   -1,
   -1,   44,   -1,  293,   93,  295,  296,  297,  298,  259,
    0,  261,  262,  263,   -1,   -1,   59,   -1,   -1,   -1,
  270,  271,   -1,   -1,  274,   91,   41,   -1,   33,   44,
   -1,   -1,   -1,   38,   -1,  124,   41,   42,   43,   44,
   45,   46,   47,  293,   59,  295,  296,  297,  298,    0,
   93,   41,   -1,   58,   44,   60,   61,   62,   -1,   -1,
  259,   -1,  261,  262,  263,   -1,   -1,   -1,   -1,   59,
   -1,  270,  271,   -1,   -1,  274,   -1,  270,   93,   -1,
  259,  124,  261,   -1,  263,   -1,   -1,   -1,   -1,   94,
   41,  270,  271,   44,  293,  274,  295,  296,  297,  298,
   -1,   -1,   -1,   93,   -1,  284,   -1,   -1,   59,  124,
   -1,   -1,   -1,   -1,  293,   -1,  312,  259,  297,  261,
  262,  263,   -1,  319,   -1,   -1,   -1,  323,  270,  271,
   -1,   33,  274,   35,  124,   -1,   38,   -1,   40,   -1,
   42,   43,   93,   45,   46,   47,   -1,   45,   -1,   -1,
   -1,  293,   -1,  295,  296,  297,   58,   -1,   60,   61,
   62,   59,   -1,   61,   -1,   -1,   -1,  363,   -1,   -1,
  259,   -1,  261,  124,  263,  371,   -1,   -1,   -1,   -1,
   -1,  270,  271,   -1,   -1,  274,   -1,   -1,   -1,   91,
   -1,   93,   94,   91,   -1,  284,   94,  263,  264,   -1,
  266,  267,  268,   -1,  293,   -1,   -1,   -1,  297,  275,
   -1,   -1,   -1,   -1,   -1,   -1,  259,   -1,  261,   -1,
  263,   -1,   -1,   -1,  126,  123,  124,  270,  271,  425,
   -1,  274,   -1,   -1,   -1,   -1,   -1,   -1,  304,  305,
   -1,  284,   -1,   -1,  259,   -1,  261,  262,  263,   -1,
  293,   -1,   -1,   -1,  297,  270,  271,   -1,   -1,  274,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,  463,   -1,  259,
  275,  261,  262,  263,   -1,   -1,   -1,   -1,  293,  284,
  270,  271,  297,   -1,  274,   -1,   -1,   -1,   -1,   -1,
  295,  296,   -1,  298,  299,  300,  301,  302,  303,   45,
   -1,   -1,   -1,  293,   -1,   -1,   -1,  297,  259,   -1,
  261,  262,  263,   59,   -1,   61,   -1,   -1,   -1,  270,
  271,   -1,   33,  274,   35,   -1,   -1,   38,   -1,   40,
   41,   42,   43,   -1,   45,   46,   47,   -1,   -1,   -1,
   -1,   -1,  293,   -1,   -1,   91,  297,   58,   94,   60,
   61,   62,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,  266,  267,  268,  269,  266,   -1,
  268,   -1,  270,  275,   -1,   -1,   -1,  123,  124,  281,
   91,   -1,   -1,   94,   -1,   -1,   -1,  289,   -1,  287,
   -1,   -1,   -1,  295,  296,   -1,  298,  299,  300,  301,
  302,  303,  304,  305,   33,   -1,   35,   -1,   -1,   38,
   -1,   40,   -1,   42,   43,  126,   45,   46,   47,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   58,
   -1,   60,   61,   62,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   33,   -1,   35,   -1,   -1,   38,
   -1,   40,   -1,   42,   43,   -1,   45,   46,   47,   -1,
   45,   -1,   91,   -1,   93,   94,   -1,   -1,   -1,   58,
   -1,   60,   61,   62,   59,   -1,   61,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   33,   -1,   35,   -1,
   -1,   38,   -1,   40,   -1,   42,   43,  126,   45,   46,
   47,   -1,   91,   -1,   93,   94,   91,   -1,   -1,   94,
   -1,   58,   -1,   60,   61,   62,   -1,   -1,   -1,   -1,
  266,   33,  268,   -1,  270,   -1,   38,   -1,   -1,   41,
   42,   43,   44,   45,   46,   47,   -1,  126,  123,  124,
  125,  287,   -1,   -1,   91,   -1,   58,   94,   60,   61,
   62,   -1,   -1,   -1,   -1,  266,  267,  268,  269,   -1,
   -1,   -1,   -1,   -1,  275,   -1,   -1,   -1,   -1,   -1,
  281,   -1,   -1,   -1,   -1,   -1,   -1,   -1,  289,  126,
   -1,   -1,   94,   -1,  295,  296,   -1,  298,  299,  300,
  301,  302,  303,  304,  305,   33,   -1,   35,   -1,   -1,
   38,   -1,   40,   -1,   42,   43,   -1,   45,   46,   47,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   58,   -1,   60,   61,   62,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,  266,  267,  268,
  269,   -1,   -1,   -1,   -1,   -1,  275,   -1,   -1,   -1,
   -1,   -1,  281,   91,   -1,   -1,   94,   -1,   -1,   -1,
  289,   -1,   -1,   -1,   -1,   -1,  295,  296,   -1,  298,
  299,  300,  301,  302,  303,  304,  305,  266,  267,  268,
  269,  266,   -1,  268,   -1,  270,  275,   -1,  126,   -1,
   -1,   -1,  281,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
  289,   -1,  287,   -1,   -1,   -1,  295,  296,   -1,  298,
  299,  300,  301,  302,  303,  304,  305,   33,   -1,  266,
  267,  268,  269,   -1,   -1,   -1,   42,   43,  275,   45,
   46,   47,   -1,   -1,  281,   -1,   -1,  284,   -1,   -1,
   -1,   -1,  289,   -1,   60,   61,   62,   -1,  295,  296,
   -1,  298,  299,  300,  301,  302,  303,  304,  305,   -1,
   -1,   -1,   -1,  275,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   94,   -1,
   -1,   -1,   -1,  295,  296,   -1,  298,  299,  300,  301,
  302,  303,   33,   -1,   -1,   -1,   -1,   38,   33,   -1,
   41,   42,   43,   44,   45,   46,   47,   42,   43,   -1,
   45,   46,   47,   -1,   -1,   -1,   -1,   58,   -1,   60,
   61,   62,   -1,   -1,   -1,   60,   61,   62,  266,  267,
  268,  269,   -1,   -1,   -1,   -1,   58,  275,   -1,   61,
   -1,   -1,   -1,  281,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,  289,   -1,   94,   -1,   -1,   -1,  295,  296,   94,
  298,  299,  300,  301,  302,  303,  304,  305,   33,   -1,
   -1,   -1,   -1,   38,   -1,   -1,   41,   42,   43,   44,
   45,   46,   47,   -1,   -1,   -1,   -1,   -1,  110,   -1,
   -1,   -1,   -1,   58,  116,   60,   61,   62,   -1,   -1,
  122,   -1,   -1,   -1,   -1,   -1,   -1,   -1,  130,  131,
  132,  133,  134,   38,   -1,   -1,   41,   42,   43,   44,
   45,   46,   47,   -1,   -1,   -1,   -1,   -1,   -1,   94,
   -1,   -1,   -1,   58,   -1,   60,   61,   62,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   38,  275,
   -1,   41,  184,   43,   44,   45,  188,   -1,   -1,   94,
   -1,   -1,  194,  195,  196,  197,  198,   -1,   58,   -1,
   60,   61,   62,  299,  300,  301,  302,  303,   38,   -1,
   -1,   41,   42,   43,   44,   45,   46,   47,   38,   -1,
   -1,   41,   42,   43,   44,   45,   -1,   47,   58,   -1,
   60,   61,   62,   -1,   -1,   -1,   -1,   -1,   58,   -1,
   60,   61,   62,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,  275,   -1,   -1,   -1,   -1,   -1,
  275,   -1,   -1,   -1,   94,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,  295,  296,   -1,  298,  299,  300,
  301,  302,  303,   -1,  299,  300,  301,  302,  303,   38,
   -1,   -1,   41,   42,   43,   44,   45,   -1,   47,   38,
   -1,   -1,   41,   42,   43,   44,   45,   -1,   47,   58,
   -1,   60,   61,   62,   -1,   -1,   -1,   -1,   -1,   58,
   -1,   60,   61,   62,  326,  327,   -1,   -1,   -1,   -1,
  275,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   38,
   -1,   -1,   41,   42,   43,   44,   45,   -1,   47,   -1,
  295,  296,   -1,  298,  299,  300,  301,  302,  303,   58,
   -1,   60,   61,   62,   -1,   -1,   -1,   -1,   -1,   -1,
  275,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   38,
   -1,   -1,   41,   42,   43,   44,   45,   -1,   47,   -1,
  295,  296,   -1,  298,  299,  300,  301,  302,  303,   58,
   -1,   60,   61,   62,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,  275,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   40,   38,   42,   -1,   41,   45,   43,
   44,   45,   -1,   -1,   -1,  295,  296,   -1,  298,  299,
  300,  301,   -1,   -1,   58,  275,   60,   61,   62,   -1,
   -1,   -1,   -1,   -1,   -1,  275,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,  295,  296,   -1,  298,  299,
  300,  301,  302,  303,   91,  295,  296,   -1,  298,  299,
  300,  301,  302,  303,   38,   -1,   -1,   41,   -1,   43,
   44,   45,   38,   -1,   -1,   41,   -1,   -1,   44,   38,
   -1,   -1,   41,   -1,   58,   44,   60,   61,   62,   -1,
   -1,   -1,   58,   -1,   60,   61,   62,   -1,   -1,   58,
   -1,   60,   61,   62,   -1,   -1,  275,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,  275,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,  295,  296,   -1,  298,
  299,  300,  301,  302,  303,   -1,  295,  296,   -1,  298,
  299,  300,  301,  302,  303,   -1,   40,  259,   42,   -1,
   -1,   45,   -1,   -1,   -1,   -1,  275,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,  295,  296,   -1,  298,
  299,  300,  301,  302,  303,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,  275,   91,   -1,   -1,
   -1,   -1,  314,  315,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,  324,   -1,   -1,   -1,  295,  296,   -1,  298,
  299,  300,  301,  302,  303,   -1,   -1,   -1,  265,  266,
  267,  268,   -1,  345,   -1,  272,   -1,   -1,   -1,  276,
  277,  275,   -1,   -1,   -1,   -1,   -1,  359,   -1,   -1,
   -1,  363,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,  295,  296,   -1,  298,  299,  300,  301,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   48,
   -1,  275,  414,   -1,  416,   -1,   -1,   -1,   -1,  275,
   59,   -1,   61,   -1,   -1,   -1,  275,   -1,   -1,   -1,
   -1,  295,  296,   -1,  298,  299,  300,  301,   -1,  295,
  296,   -1,  298,  299,  300,  301,  295,  296,   -1,  298,
  299,  300,  301,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,  107,  108,
   -1,   -1,  256,  257,  258,   -1,  115,   -1,  117,   -1,
  482,  265,  266,  267,  268,  487,   -1,   -1,  272,   -1,
   -1,   -1,  276,  277,   -1,   -1,  135,  136,  137,  138,
  139,  140,  141,  142,  143,  144,  145,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,  200,  201,  202,  203,  204,  205,  206,  207,  208,
  209,  210,
};
#if YYBTYACC
static const YYINT yyctable[] = {                        -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,
};
#endif
#define YYFINAL 15
#ifndef YYDEBUG
#define YYDEBUG 0
#endif
#define YYMAXTOKEN 306
#define YYUNDFTOKEN 417
#define YYTRANSLATE(a) ((a) > YYMAXTOKEN ? YYUNDFTOKEN : (a))
#if YYDEBUG
#ifndef NULL
#define NULL (void*)0
#endif
static const char *const yyname[] = {

"$end",NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,
NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,
NULL,NULL,"'!'",NULL,"'#'",NULL,NULL,"'&'",NULL,"'('","')'","'*'","'+'","','",
"'-'","'.'","'/'",NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,"':'","';'",
"'<'","'='","'>'","'?'",NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,
NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,
"'['",NULL,"']'","'^'",NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,
NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,
NULL,"'{'","'|'","'}'","'~'",NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,
NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,
NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,
NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,
NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,
NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,
NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,
NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,
NULL,NULL,NULL,NULL,NULL,NULL,NULL,"error","VALUE","EVAL","WHERE","IF","TO",
"LEFTARROW","COLONCOLON","COLON2EQ","TYPEVAR","NAME","CNAME","CONST","DOLLARS",
"OFFSIDE","ELSEQ","ABSTYPE","WITH","DIAG","EQEQ","FREE","INCLUDE","EXPORT",
"TYPE","OTHERWISE","SHOWSYM","PATHNAME","BNF","LEX","ENDIR","ERRORSY","ENDSY",
"EMPTYSY","READVALSY","LEXDEF","CHARCLASS","ANTICHARCLASS","LBEGIN","ARROW",
"PLUSPLUS","MINUSMINUS","DOTDOT","VEL","GE","NE","LE","REM","DIV","INFIXNAME",
"INFIXCNAME","CMBASE","$accept","entity","script","exp","defs","op","e1","diop",
"diop1","relop","eqop","rhs","cases","ldefs","if","reindent","alt","here",
"indent","outdent","separator","liste","reln","e2","es1","relsn","es2","e3",
"es3","comb","arg","$$1","lexrules","qualifiers","lstart","re","$$2","lpostfix",
"$$3","lexdefs","cnames","re1","lterm","lfac","lunit","name","generator",
"generator1","def","v","act2","spec","typeforms","lspecs","typeform","act1",
"type","construction","setexp","parts","specs","bindings","modifiers","names",
"$$4","productions","bindingseq","binding","negmods","negmod","ldef","vlist",
"v1","v2","v3","type1","type2","tap","argtype","typevar","typelist","typel",
"ttype","lspec","namelist","$$5","typevars","constructs","construct","field",
"construct1","field1","production","params","grhs","$$6","phrase","error_term",
"phrase1","term","count_factors","$$7","$$8","factors","$$9","factor","unit",
"symbol","$$10","$$11","illegal-symbol",
};
static const char *const yyrule[] = {
"$accept : entity",
"entity : error",
"entity : script",
"entity : VALUE exp",
"entity : EVAL exp",
"entity : EVAL exp COLONCOLON",
"entity : EVAL exp TO",
"script :",
"script : defs",
"exp : op",
"exp : e1",
"op : '~'",
"op : '#'",
"op : diop",
"diop : '-'",
"diop : diop1",
"diop1 : '+'",
"diop1 : PLUSPLUS",
"diop1 : ':'",
"diop1 : MINUSMINUS",
"diop1 : VEL",
"diop1 : '&'",
"diop1 : relop",
"diop1 : '*'",
"diop1 : '/'",
"diop1 : DIV",
"diop1 : REM",
"diop1 : '^'",
"diop1 : '.'",
"diop1 : '!'",
"diop1 : INFIXNAME",
"diop1 : INFIXCNAME",
"relop : '>'",
"relop : GE",
"relop : eqop",
"relop : NE",
"relop : LE",
"relop : '<'",
"eqop : EQEQ",
"eqop : '='",
"rhs : cases WHERE ldefs",
"rhs : exp WHERE ldefs",
"rhs : exp",
"rhs : cases",
"cases : exp ',' if exp",
"cases : exp ',' OTHERWISE",
"cases : cases reindent ELSEQ alt",
"alt : here exp",
"alt : here exp ',' if exp",
"alt : here exp ',' OTHERWISE",
"if :",
"if : IF",
"indent :",
"outdent : separator",
"separator : OFFSIDE",
"separator : ';'",
"reindent :",
"liste : exp",
"liste : liste ',' exp",
"e1 : '~' e1",
"e1 : e1 PLUSPLUS e1",
"e1 : e1 ':' e1",
"e1 : e1 MINUSMINUS e1",
"e1 : e1 VEL e1",
"e1 : e1 '&' e1",
"e1 : reln",
"e1 : e2",
"es1 : '~' e1",
"es1 : e1 PLUSPLUS e1",
"es1 : e1 PLUSPLUS",
"es1 : e1 ':' e1",
"es1 : e1 ':'",
"es1 : e1 MINUSMINUS e1",
"es1 : e1 MINUSMINUS",
"es1 : e1 VEL e1",
"es1 : e1 VEL",
"es1 : e1 '&' e1",
"es1 : e1 '&'",
"es1 : relsn",
"es1 : es2",
"e2 : '-' e2",
"e2 : '#' e2",
"e2 : e2 '+' e2",
"e2 : e2 '-' e2",
"e2 : e2 '*' e2",
"e2 : e2 '/' e2",
"e2 : e2 DIV e2",
"e2 : e2 REM e2",
"e2 : e2 '^' e2",
"e2 : e2 '.' e2",
"e2 : e2 '!' e2",
"e2 : e3",
"es2 : '-' e2",
"es2 : '#' e2",
"es2 : e2 '+' e2",
"es2 : e2 '+'",
"es2 : e2 '-' e2",
"es2 : e2 '-'",
"es2 : e2 '*' e2",
"es2 : e2 '*'",
"es2 : e2 '/' e2",
"es2 : e2 '/'",
"es2 : e2 DIV e2",
"es2 : e2 DIV",
"es2 : e2 REM e2",
"es2 : e2 REM",
"es2 : e2 '^' e2",
"es2 : e2 '^'",
"es2 : e2 '.' e2",
"es2 : e2 '.'",
"es2 : e2 '!' e2",
"es2 : e2 '!'",
"es2 : es3",
"e3 : comb INFIXNAME e3",
"e3 : comb INFIXCNAME e3",
"e3 : comb",
"es3 : comb INFIXNAME e3",
"es3 : comb INFIXNAME",
"es3 : comb INFIXCNAME e3",
"es3 : comb INFIXCNAME",
"es3 : comb",
"comb : comb arg",
"comb : arg",
"reln : e2 relop e2",
"reln : reln relop e2",
"relsn : e2 relop e2",
"relsn : e2 relop",
"relsn : reln relop e2",
"$$1 :",
"arg : $$1 LEX lexrules ENDIR",
"arg : NAME",
"arg : CNAME",
"arg : CONST",
"arg : READVALSY",
"arg : SHOWSYM",
"arg : DOLLARS",
"arg : '[' ']'",
"arg : '[' exp ']'",
"arg : '[' exp ',' exp ']'",
"arg : '[' exp ',' exp ',' liste ']'",
"arg : '[' exp DOTDOT exp ']'",
"arg : '[' exp DOTDOT ']'",
"arg : '[' exp ',' exp DOTDOT exp ']'",
"arg : '[' exp ',' exp DOTDOT ']'",
"arg : '[' exp '|' qualifiers ']'",
"arg : '[' exp DIAG qualifiers ']'",
"arg : '(' op ')'",
"arg : '(' es1 ')'",
"arg : '(' diop1 e1 ')'",
"arg : '(' ')'",
"arg : '(' exp ',' liste ')'",
"$$2 :",
"$$3 :",
"lexrules : lexrules lstart here re indent $$2 ARROW exp lpostfix $$3 outdent",
"lexrules : lexdefs",
"lstart :",
"lstart : '<' cnames '>'",
"cnames : CNAME",
"cnames : cnames CNAME",
"lpostfix :",
"lpostfix : LBEGIN CNAME",
"lpostfix : LBEGIN CONST",
"lexdefs : lexdefs LEXDEF indent '=' re outdent",
"lexdefs :",
"re : re1 '|' re",
"re : re1",
"re1 : lterm '/' lterm",
"re1 : lterm '/'",
"re1 : lterm",
"lterm : lfac lterm",
"lterm : lfac",
"lfac : lunit '*'",
"lfac : lunit '+'",
"lfac : lunit '?'",
"lfac : lunit",
"lunit : '(' re ')'",
"lunit : CONST",
"lunit : CHARCLASS",
"lunit : ANTICHARCLASS",
"lunit : '.'",
"lunit : name",
"name : NAME",
"name : CNAME",
"qualifiers : exp",
"qualifiers : generator",
"qualifiers : qualifiers ';' generator",
"qualifiers : qualifiers ';' exp",
"generator : e1 ',' generator",
"generator : generator1",
"generator1 : e1 LEFTARROW exp",
"generator1 : e1 LEFTARROW exp ',' exp DOTDOT",
"defs : def",
"defs : defs def",
"def : v act2 indent '=' here rhs outdent",
"def : spec",
"def : ABSTYPE here typeforms indent WITH lspecs outdent",
"def : typeform indent act1 here EQEQ type act2 outdent",
"def : typeform indent act1 here COLON2EQ construction act2 outdent",
"def : indent setexp EXPORT parts outdent",
"def : FREE here '{' specs '}'",
"def : INCLUDE bindings modifiers outdent",
"$$4 :",
"def : here BNF $$4 names outdent productions ENDIR",
"setexp : here",
"bindings :",
"bindings : '{' bindingseq '}'",
"bindingseq : bindingseq binding",
"bindingseq : binding",
"binding : NAME indent '=' exp outdent",
"binding : typeform indent act1 EQEQ type act2 outdent",
"modifiers :",
"modifiers : negmods",
"negmods : negmods negmod",
"negmods : negmod",
"negmod : NAME '/' NAME",
"negmod : CNAME '/' CNAME",
"negmod : '-' NAME",
"here :",
"act1 :",
"act2 :",
"ldefs : ldef",
"ldefs : ldefs ldef",
"ldef : spec",
"ldef : typeform here EQEQ",
"ldef : typeform here COLON2EQ",
"ldef : v act2 indent '=' here rhs outdent",
"vlist : v",
"vlist : vlist ',' v",
"v : v1",
"v : v1 ':' v",
"v1 : v1 '+' CONST",
"v1 : '-' CONST",
"v1 : v2 INFIXNAME v1",
"v1 : v2 INFIXCNAME v1",
"v1 : v2",
"v2 : v3",
"v2 : v2 v3",
"v3 : NAME",
"v3 : CNAME",
"v3 : CONST",
"v3 : '[' ']'",
"v3 : '[' vlist ']'",
"v3 : '(' ')'",
"v3 : '(' v ')'",
"v3 : '(' v ',' vlist ')'",
"type : type1",
"type : type ARROW type",
"type1 : type2 INFIXNAME type1",
"type1 : type2",
"type2 : tap",
"type2 : argtype",
"tap : NAME argtype",
"tap : tap argtype",
"argtype : NAME",
"argtype : typevar",
"argtype : '(' typelist ')'",
"argtype : '[' type ']'",
"argtype : '[' type ',' typel ']'",
"typelist :",
"typelist : type",
"typelist : type ',' typel",
"typel : type",
"typel : typel ',' type",
"parts : parts NAME",
"parts : parts '-' NAME",
"parts : parts PATHNAME",
"parts : parts '+'",
"parts : NAME",
"parts : '-' NAME",
"parts : PATHNAME",
"parts : '+'",
"specs : specs spec",
"specs : spec",
"spec : typeforms indent here COLONCOLON ttype outdent",
"lspecs : lspecs lspec",
"lspecs : lspec",
"$$5 :",
"lspec : namelist indent here $$5 COLONCOLON type outdent",
"namelist : NAME ',' namelist",
"namelist : NAME",
"typeforms : typeforms ',' typeform act2",
"typeforms : typeform act2",
"typeform : CNAME typevars",
"typeform : NAME typevars",
"typeform : typevar INFIXNAME typevar",
"typeform : typevar INFIXCNAME typevar",
"ttype : type",
"ttype : TYPE",
"typevar : '*'",
"typevar : TYPEVAR",
"typevars :",
"typevars : typevar typevars",
"construction : constructs",
"constructs : construct",
"constructs : constructs '|' construct",
"construct : field here INFIXCNAME field",
"construct : construct1",
"construct1 : '(' construct ')'",
"construct1 : construct1 field1",
"construct1 : here CNAME",
"field : type",
"field : argtype '!'",
"field1 : argtype '!'",
"field1 : argtype",
"names :",
"names : names NAME",
"productions : lspec",
"productions : production",
"productions : productions lspec",
"productions : productions production",
"production : NAME params ':' indent grhs outdent",
"params :",
"$$6 :",
"params : $$6 '(' names ')'",
"grhs : here phrase",
"phrase : error_term",
"phrase : phrase1",
"phrase : phrase1 '|' error_term",
"phrase1 : term",
"phrase1 : phrase1 '|' here term",
"term : count_factors",
"$$7 :",
"term : count_factors $$7 indent '=' here rhs outdent",
"error_term : ERRORSY",
"$$8 :",
"error_term : ERRORSY $$8 indent '=' here rhs outdent",
"count_factors : EMPTYSY",
"count_factors : EMPTYSY factors",
"$$9 :",
"count_factors : $$9 factors",
"factors : factor",
"factors : factors factor",
"factor : unit",
"factor : '{' unit '}'",
"factor : '{' unit",
"factor : unit '}'",
"unit : symbol",
"unit : symbol '*'",
"unit : symbol '+'",
"unit : symbol '?'",
"symbol : NAME",
"symbol : ENDSY",
"symbol : CONST",
"symbol : '^'",
"$$10 :",
"$$11 :",
"symbol : $$10 '[' exp $$11 ']'",
"symbol : '-'",

};
#endif

#if YYDEBUG
int      yydebug;
#endif

int      yyerrflag;
int      yychar;
YYSTYPE  yyval;
YYSTYPE  yylval;
int      yynerrs;

#if defined(YYLTYPE) || defined(YYLTYPE_IS_DECLARED)
YYLTYPE  yyloc; /* position returned by actions */
YYLTYPE  yylloc; /* position from the lexer */
#endif

#if defined(YYLTYPE) || defined(YYLTYPE_IS_DECLARED)
#ifndef YYLLOC_DEFAULT
#define YYLLOC_DEFAULT(loc, rhs, n) \
do \
{ \
    if (n == 0) \
    { \
        (loc).first_line   = YYRHSLOC(rhs, 0).last_line; \
        (loc).first_column = YYRHSLOC(rhs, 0).last_column; \
        (loc).last_line    = YYRHSLOC(rhs, 0).last_line; \
        (loc).last_column  = YYRHSLOC(rhs, 0).last_column; \
    } \
    else \
    { \
        (loc).first_line   = YYRHSLOC(rhs, 1).first_line; \
        (loc).first_column = YYRHSLOC(rhs, 1).first_column; \
        (loc).last_line    = YYRHSLOC(rhs, n).last_line; \
        (loc).last_column  = YYRHSLOC(rhs, n).last_column; \
    } \
} while (0)
#endif /* YYLLOC_DEFAULT */
#endif /* defined(YYLTYPE) || defined(YYLTYPE_IS_DECLARED) */
#if YYBTYACC

#ifndef YYLVQUEUEGROWTH
#define YYLVQUEUEGROWTH 32
#endif
#endif /* YYBTYACC */

/* define the initial stack-sizes */
#ifdef YYSTACKSIZE
#undef YYMAXDEPTH
#define YYMAXDEPTH  YYSTACKSIZE
#else
#ifdef YYMAXDEPTH
#define YYSTACKSIZE YYMAXDEPTH
#else
#define YYSTACKSIZE 10000
#define YYMAXDEPTH  10000
#endif
#endif

#ifndef YYINITSTACKSIZE
#define YYINITSTACKSIZE 200
#endif

typedef struct {
    unsigned stacksize;
    YYINT    *s_base;
    YYINT    *s_mark;
    YYINT    *s_last;
    YYSTYPE  *l_base;
    YYSTYPE  *l_mark;
#if defined(YYLTYPE) || defined(YYLTYPE_IS_DECLARED)
    YYLTYPE  *p_base;
    YYLTYPE  *p_mark;
#endif
} YYSTACKDATA;
#if YYBTYACC

struct YYParseState_s
{
    struct YYParseState_s *save;    /* Previously saved parser state */
    YYSTACKDATA            yystack; /* saved parser stack */
    int                    state;   /* saved parser state */
    int                    errflag; /* saved error recovery status */
    int                    lexeme;  /* saved index of the conflict lexeme in the lexical queue */
    YYINT                  ctry;    /* saved index in yyctable[] for this conflict */
};
typedef struct YYParseState_s YYParseState;
#endif /* YYBTYACC */
/* variables for the parser stack */
static YYSTACKDATA yystack;
#if YYBTYACC

/* Current parser state */
static YYParseState *yyps = NULL;

/* yypath != NULL: do the full parse, starting at *yypath parser state. */
static YYParseState *yypath = NULL;

/* Base of the lexical value queue */
static YYSTYPE *yylvals = NULL;

/* Current position at lexical value queue */
static YYSTYPE *yylvp = NULL;

/* End position of lexical value queue */
static YYSTYPE *yylve = NULL;

/* The last allocated position at the lexical value queue */
static YYSTYPE *yylvlim = NULL;

#if defined(YYLTYPE) || defined(YYLTYPE_IS_DECLARED)
/* Base of the lexical position queue */
static YYLTYPE *yylpsns = NULL;

/* Current position at lexical position queue */
static YYLTYPE *yylpp = NULL;

/* End position of lexical position queue */
static YYLTYPE *yylpe = NULL;

/* The last allocated position at the lexical position queue */
static YYLTYPE *yylplim = NULL;
#endif

/* Current position at lexical token queue */
static YYINT  *yylexp = NULL;

static YYINT  *yylexemes = NULL;
#endif /* YYBTYACC */
#line 1670 "rules.y"
/*  end of Miranda rules  */
#line 2310 "y.tab.c"

/* For use in generated program */
#define yydepth (int)(yystack.s_mark - yystack.s_base)
#if YYBTYACC
#define yytrial (yyps->save)
#endif /* YYBTYACC */

#if YYDEBUG
#include <stdio.h>	/* needed for printf */
#endif

#include <stdlib.h>	/* needed for malloc, etc */
#include <string.h>	/* needed for memset */

/* allocate initial stack or double stack size, up to YYMAXDEPTH */
static int yygrowstack(YYSTACKDATA *data)
{
    int i;
    unsigned newsize;
    YYINT *newss;
    YYSTYPE *newvs;
#if defined(YYLTYPE) || defined(YYLTYPE_IS_DECLARED)
    YYLTYPE *newps;
#endif

    if ((newsize = data->stacksize) == 0)
        newsize = YYINITSTACKSIZE;
    else if (newsize >= YYMAXDEPTH)
        return YYENOMEM;
    else if ((newsize *= 2) > YYMAXDEPTH)
        newsize = YYMAXDEPTH;

    i = (int) (data->s_mark - data->s_base);
    newss = (YYINT *)realloc(data->s_base, newsize * sizeof(*newss));
    if (newss == NULL)
        return YYENOMEM;

    data->s_base = newss;
    data->s_mark = newss + i;

    newvs = (YYSTYPE *)realloc(data->l_base, newsize * sizeof(*newvs));
    if (newvs == NULL)
        return YYENOMEM;

    data->l_base = newvs;
    data->l_mark = newvs + i;

#if defined(YYLTYPE) || defined(YYLTYPE_IS_DECLARED)
    newps = (YYLTYPE *)realloc(data->p_base, newsize * sizeof(*newps));
    if (newps == NULL)
        return YYENOMEM;

    data->p_base = newps;
    data->p_mark = newps + i;
#endif

    data->stacksize = newsize;
    data->s_last = data->s_base + newsize - 1;

#if YYDEBUG
    if (yydebug)
        fprintf(stderr, "%sdebug: stack size increased to %d\n", YYPREFIX, newsize);
#endif
    return 0;
}

#if YYPURE || defined(YY_NO_LEAKS)
static void yyfreestack(YYSTACKDATA *data)
{
    free(data->s_base);
    free(data->l_base);
#if defined(YYLTYPE) || defined(YYLTYPE_IS_DECLARED)
    free(data->p_base);
#endif
    memset(data, 0, sizeof(*data));
}
#else
#define yyfreestack(data) /* nothing */
#endif /* YYPURE || defined(YY_NO_LEAKS) */
#if YYBTYACC

static YYParseState *
yyNewState(unsigned size)
{
    YYParseState *p = (YYParseState *) malloc(sizeof(YYParseState));
    if (p == NULL) return NULL;

    p->yystack.stacksize = size;
    if (size == 0)
    {
        p->yystack.s_base = NULL;
        p->yystack.l_base = NULL;
#if defined(YYLTYPE) || defined(YYLTYPE_IS_DECLARED)
        p->yystack.p_base = NULL;
#endif
        return p;
    }
    p->yystack.s_base    = (YYINT *) malloc(size * sizeof(YYINT));
    if (p->yystack.s_base == NULL) return NULL;
    p->yystack.l_base    = (YYSTYPE *) malloc(size * sizeof(YYSTYPE));
    if (p->yystack.l_base == NULL) return NULL;
    memset(p->yystack.l_base, 0, size * sizeof(YYSTYPE));
#if defined(YYLTYPE) || defined(YYLTYPE_IS_DECLARED)
    p->yystack.p_base    = (YYLTYPE *) malloc(size * sizeof(YYLTYPE));
    if (p->yystack.p_base == NULL) return NULL;
    memset(p->yystack.p_base, 0, size * sizeof(YYLTYPE));
#endif

    return p;
}

static void
yyFreeState(YYParseState *p)
{
    yyfreestack(&p->yystack);
    free(p);
}
#endif /* YYBTYACC */

#define YYABORT  goto yyabort
#define YYREJECT goto yyabort
#define YYACCEPT goto yyaccept
#define YYERROR  goto yyerrlab
#if YYBTYACC
#define YYVALID        do { if (yyps->save)            goto yyvalid; } while(0)
#define YYVALID_NESTED do { if (yyps->save && \
                                yyps->save->save == 0) goto yyvalid; } while(0)
#endif /* YYBTYACC */

int
YYPARSE_DECL()
{
    int yym, yyn, yystate, yyresult;
#if YYBTYACC
    int yynewerrflag;
    YYParseState *yyerrctx = NULL;
#endif /* YYBTYACC */
#if defined(YYLTYPE) || defined(YYLTYPE_IS_DECLARED)
    YYLTYPE  yyerror_loc_range[3]; /* position of error start/end (0 unused) */
#endif
#if YYDEBUG
    const char *yys;

    if ((yys = getenv("YYDEBUG")) != NULL)
    {
        yyn = *yys;
        if (yyn >= '0' && yyn <= '9')
            yydebug = yyn - '0';
    }
    if (yydebug)
        fprintf(stderr, "%sdebug[<# of symbols on state stack>]\n", YYPREFIX);
#endif
#if defined(YYLTYPE) || defined(YYLTYPE_IS_DECLARED)
    memset(yyerror_loc_range, 0, sizeof(yyerror_loc_range));
#endif

#if YYBTYACC
    yyps = yyNewState(0); if (yyps == NULL) goto yyenomem;
    yyps->save = NULL;
#endif /* YYBTYACC */
    yym = 0;
    /* yyn is set below */
    yynerrs = 0;
    yyerrflag = 0;
    yychar = YYEMPTY;
    yystate = 0;

#if YYPURE
    memset(&yystack, 0, sizeof(yystack));
#endif

    if (yystack.s_base == NULL && yygrowstack(&yystack) == YYENOMEM) goto yyoverflow;
    yystack.s_mark = yystack.s_base;
    yystack.l_mark = yystack.l_base;
#if defined(YYLTYPE) || defined(YYLTYPE_IS_DECLARED)
    yystack.p_mark = yystack.p_base;
#endif
    yystate = 0;
    *yystack.s_mark = 0;

yyloop:
    if ((yyn = yydefred[yystate]) != 0) goto yyreduce;
    if (yychar < 0)
    {
#if YYBTYACC
        do {
        if (yylvp < yylve)
        {
            /* we're currently re-reading tokens */
            yylval = *yylvp++;
#if defined(YYLTYPE) || defined(YYLTYPE_IS_DECLARED)
            yylloc = *yylpp++;
#endif
            yychar = *yylexp++;
            break;
        }
        if (yyps->save)
        {
            /* in trial mode; save scanner results for future parse attempts */
            if (yylvp == yylvlim)
            {   /* Enlarge lexical value queue */
                size_t p = (size_t) (yylvp - yylvals);
                size_t s = (size_t) (yylvlim - yylvals);

                s += YYLVQUEUEGROWTH;
                if ((yylexemes = (YYINT *)realloc(yylexemes, s * sizeof(YYINT))) == NULL) goto yyenomem;
                if ((yylvals   = (YYSTYPE *)realloc(yylvals, s * sizeof(YYSTYPE))) == NULL) goto yyenomem;
#if defined(YYLTYPE) || defined(YYLTYPE_IS_DECLARED)
                if ((yylpsns   = (YYLTYPE *)realloc(yylpsns, s * sizeof(YYLTYPE))) == NULL) goto yyenomem;
#endif
                yylvp   = yylve = yylvals + p;
                yylvlim = yylvals + s;
#if defined(YYLTYPE) || defined(YYLTYPE_IS_DECLARED)
                yylpp   = yylpe = yylpsns + p;
                yylplim = yylpsns + s;
#endif
                yylexp  = yylexemes + p;
            }
            *yylexp = (YYINT) YYLEX;
            *yylvp++ = yylval;
            yylve++;
#if defined(YYLTYPE) || defined(YYLTYPE_IS_DECLARED)
            *yylpp++ = yylloc;
            yylpe++;
#endif
            yychar = *yylexp++;
            break;
        }
        /* normal operation, no conflict encountered */
#endif /* YYBTYACC */
        yychar = YYLEX;
#if YYBTYACC
        } while (0);
#endif /* YYBTYACC */
        if (yychar < 0) yychar = YYEOF;
#if YYDEBUG
        if (yydebug)
        {
            if ((yys = yyname[YYTRANSLATE(yychar)]) == NULL) yys = yyname[YYUNDFTOKEN];
            fprintf(stderr, "%s[%d]: state %d, reading token %d (%s)",
                            YYDEBUGSTR, yydepth, yystate, yychar, yys);
#ifdef YYSTYPE_TOSTRING
#if YYBTYACC
            if (!yytrial)
#endif /* YYBTYACC */
                fprintf(stderr, " <%s>", YYSTYPE_TOSTRING(yychar, yylval));
#endif
            fputc('\n', stderr);
        }
#endif
    }
#if YYBTYACC

    /* Do we have a conflict? */
    if (((yyn = yycindex[yystate]) != 0) && (yyn += yychar) >= 0 &&
        yyn <= YYTABLESIZE && yycheck[yyn] == (YYINT) yychar)
    {
        YYINT ctry;

        if (yypath)
        {
            YYParseState *save;
#if YYDEBUG
            if (yydebug)
                fprintf(stderr, "%s[%d]: CONFLICT in state %d: following successful trial parse\n",
                                YYDEBUGSTR, yydepth, yystate);
#endif
            /* Switch to the next conflict context */
            save = yypath;
            yypath = save->save;
            save->save = NULL;
            ctry = save->ctry;
            if (save->state != yystate) YYABORT;
            yyFreeState(save);

        }
        else
        {

            /* Unresolved conflict - start/continue trial parse */
            YYParseState *save;
#if YYDEBUG
            if (yydebug)
            {
                fprintf(stderr, "%s[%d]: CONFLICT in state %d. ", YYDEBUGSTR, yydepth, yystate);
                if (yyps->save)
                    fputs("ALREADY in conflict, continuing trial parse.\n", stderr);
                else
                    fputs("Starting trial parse.\n", stderr);
            }
#endif
            save                  = yyNewState((unsigned)(yystack.s_mark - yystack.s_base + 1));
            if (save == NULL) goto yyenomem;
            save->save            = yyps->save;
            save->state           = yystate;
            save->errflag         = yyerrflag;
            save->yystack.s_mark  = save->yystack.s_base + (yystack.s_mark - yystack.s_base);
            memcpy (save->yystack.s_base, yystack.s_base, (size_t) (yystack.s_mark - yystack.s_base + 1) * sizeof(YYINT));
            save->yystack.l_mark  = save->yystack.l_base + (yystack.l_mark - yystack.l_base);
            memcpy (save->yystack.l_base, yystack.l_base, (size_t) (yystack.l_mark - yystack.l_base + 1) * sizeof(YYSTYPE));
#if defined(YYLTYPE) || defined(YYLTYPE_IS_DECLARED)
            save->yystack.p_mark  = save->yystack.p_base + (yystack.p_mark - yystack.p_base);
            memcpy (save->yystack.p_base, yystack.p_base, (size_t) (yystack.p_mark - yystack.p_base + 1) * sizeof(YYLTYPE));
#endif
            ctry                  = yytable[yyn];
            if (yyctable[ctry] == -1)
            {
#if YYDEBUG
                if (yydebug && yychar >= YYEOF)
                    fprintf(stderr, "%s[%d]: backtracking 1 token\n", YYDEBUGSTR, yydepth);
#endif
                ctry++;
            }
            save->ctry = ctry;
            if (yyps->save == NULL)
            {
                /* If this is a first conflict in the stack, start saving lexemes */
                if (!yylexemes)
                {
                    yylexemes = (YYINT *) malloc((YYLVQUEUEGROWTH) * sizeof(YYINT));
                    if (yylexemes == NULL) goto yyenomem;
                    yylvals   = (YYSTYPE *) malloc((YYLVQUEUEGROWTH) * sizeof(YYSTYPE));
                    if (yylvals == NULL) goto yyenomem;
                    yylvlim   = yylvals + YYLVQUEUEGROWTH;
#if defined(YYLTYPE) || defined(YYLTYPE_IS_DECLARED)
                    yylpsns   = (YYLTYPE *) malloc((YYLVQUEUEGROWTH) * sizeof(YYLTYPE));
                    if (yylpsns == NULL) goto yyenomem;
                    yylplim   = yylpsns + YYLVQUEUEGROWTH;
#endif
                }
                if (yylvp == yylve)
                {
                    yylvp  = yylve = yylvals;
#if defined(YYLTYPE) || defined(YYLTYPE_IS_DECLARED)
                    yylpp  = yylpe = yylpsns;
#endif
                    yylexp = yylexemes;
                    if (yychar >= YYEOF)
                    {
                        *yylve++ = yylval;
#if defined(YYLTYPE) || defined(YYLTYPE_IS_DECLARED)
                        *yylpe++ = yylloc;
#endif
                        *yylexp  = (YYINT) yychar;
                        yychar   = YYEMPTY;
                    }
                }
            }
            if (yychar >= YYEOF)
            {
                yylvp--;
#if defined(YYLTYPE) || defined(YYLTYPE_IS_DECLARED)
                yylpp--;
#endif
                yylexp--;
                yychar = YYEMPTY;
            }
            save->lexeme = (int) (yylvp - yylvals);
            yyps->save   = save;
        }
        if (yytable[yyn] == ctry)
        {
#if YYDEBUG
            if (yydebug)
                fprintf(stderr, "%s[%d]: state %d, shifting to state %d\n",
                                YYDEBUGSTR, yydepth, yystate, yyctable[ctry]);
#endif
            if (yychar < 0)
            {
                yylvp++;
#if defined(YYLTYPE) || defined(YYLTYPE_IS_DECLARED)
                yylpp++;
#endif
                yylexp++;
            }
            if (yystack.s_mark >= yystack.s_last && yygrowstack(&yystack) == YYENOMEM)
                goto yyoverflow;
            yystate = yyctable[ctry];
            *++yystack.s_mark = (YYINT) yystate;
            *++yystack.l_mark = yylval;
#if defined(YYLTYPE) || defined(YYLTYPE_IS_DECLARED)
            *++yystack.p_mark = yylloc;
#endif
            yychar  = YYEMPTY;
            if (yyerrflag > 0) --yyerrflag;
            goto yyloop;
        }
        else
        {
            yyn = yyctable[ctry];
            goto yyreduce;
        }
    } /* End of code dealing with conflicts */
#endif /* YYBTYACC */
    if (((yyn = yysindex[yystate]) != 0) && (yyn += yychar) >= 0 &&
            yyn <= YYTABLESIZE && yycheck[yyn] == (YYINT) yychar)
    {
#if YYDEBUG
        if (yydebug)
            fprintf(stderr, "%s[%d]: state %d, shifting to state %d\n",
                            YYDEBUGSTR, yydepth, yystate, yytable[yyn]);
#endif
        if (yystack.s_mark >= yystack.s_last && yygrowstack(&yystack) == YYENOMEM) goto yyoverflow;
        yystate = yytable[yyn];
        *++yystack.s_mark = yytable[yyn];
        *++yystack.l_mark = yylval;
#if defined(YYLTYPE) || defined(YYLTYPE_IS_DECLARED)
        *++yystack.p_mark = yylloc;
#endif
        yychar = YYEMPTY;
        if (yyerrflag > 0)  --yyerrflag;
        goto yyloop;
    }
    if (((yyn = yyrindex[yystate]) != 0) && (yyn += yychar) >= 0 &&
            yyn <= YYTABLESIZE && yycheck[yyn] == (YYINT) yychar)
    {
        yyn = yytable[yyn];
        goto yyreduce;
    }
    if (yyerrflag != 0) goto yyinrecovery;
#if YYBTYACC

    yynewerrflag = 1;
    goto yyerrhandler;
    goto yyerrlab; /* redundant goto avoids 'unused label' warning */

yyerrlab:
    /* explicit YYERROR from an action -- pop the rhs of the rule reduced
     * before looking for error recovery */
    yystack.s_mark -= yym;
    yystate = *yystack.s_mark;
    yystack.l_mark -= yym;
#if defined(YYLTYPE) || defined(YYLTYPE_IS_DECLARED)
    yystack.p_mark -= yym;
#endif

    yynewerrflag = 0;
yyerrhandler:
    while (yyps->save)
    {
        int ctry;
        YYParseState *save = yyps->save;
#if YYDEBUG
        if (yydebug)
            fprintf(stderr, "%s[%d]: ERROR in state %d, CONFLICT BACKTRACKING to state %d, %d tokens\n",
                            YYDEBUGSTR, yydepth, yystate, yyps->save->state,
                    (int)(yylvp - yylvals - yyps->save->lexeme));
#endif
        /* Memorize most forward-looking error state in case it's really an error. */
        if (yyerrctx == NULL || yyerrctx->lexeme < yylvp - yylvals)
        {
            /* Free old saved error context state */
            if (yyerrctx) yyFreeState(yyerrctx);
            /* Create and fill out new saved error context state */
            yyerrctx                 = yyNewState((unsigned)(yystack.s_mark - yystack.s_base + 1));
            if (yyerrctx == NULL) goto yyenomem;
            yyerrctx->save           = yyps->save;
            yyerrctx->state          = yystate;
            yyerrctx->errflag        = yyerrflag;
            yyerrctx->yystack.s_mark = yyerrctx->yystack.s_base + (yystack.s_mark - yystack.s_base);
            memcpy (yyerrctx->yystack.s_base, yystack.s_base, (size_t) (yystack.s_mark - yystack.s_base + 1) * sizeof(YYINT));
            yyerrctx->yystack.l_mark = yyerrctx->yystack.l_base + (yystack.l_mark - yystack.l_base);
            memcpy (yyerrctx->yystack.l_base, yystack.l_base, (size_t) (yystack.l_mark - yystack.l_base + 1) * sizeof(YYSTYPE));
#if defined(YYLTYPE) || defined(YYLTYPE_IS_DECLARED)
            yyerrctx->yystack.p_mark = yyerrctx->yystack.p_base + (yystack.p_mark - yystack.p_base);
            memcpy (yyerrctx->yystack.p_base, yystack.p_base, (size_t) (yystack.p_mark - yystack.p_base + 1) * sizeof(YYLTYPE));
#endif
            yyerrctx->lexeme         = (int) (yylvp - yylvals);
        }
        yylvp          = yylvals   + save->lexeme;
#if defined(YYLTYPE) || defined(YYLTYPE_IS_DECLARED)
        yylpp          = yylpsns   + save->lexeme;
#endif
        yylexp         = yylexemes + save->lexeme;
        yychar         = YYEMPTY;
        yystack.s_mark = yystack.s_base + (save->yystack.s_mark - save->yystack.s_base);
        memcpy (yystack.s_base, save->yystack.s_base, (size_t) (yystack.s_mark - yystack.s_base + 1) * sizeof(YYINT));
        yystack.l_mark = yystack.l_base + (save->yystack.l_mark - save->yystack.l_base);
        memcpy (yystack.l_base, save->yystack.l_base, (size_t) (yystack.l_mark - yystack.l_base + 1) * sizeof(YYSTYPE));
#if defined(YYLTYPE) || defined(YYLTYPE_IS_DECLARED)
        yystack.p_mark = yystack.p_base + (save->yystack.p_mark - save->yystack.p_base);
        memcpy (yystack.p_base, save->yystack.p_base, (size_t) (yystack.p_mark - yystack.p_base + 1) * sizeof(YYLTYPE));
#endif
        ctry           = ++save->ctry;
        yystate        = save->state;
        /* We tried shift, try reduce now */
        if ((yyn = yyctable[ctry]) >= 0) goto yyreduce;
        yyps->save     = save->save;
        save->save     = NULL;
        yyFreeState(save);

        /* Nothing left on the stack -- error */
        if (!yyps->save)
        {
#if YYDEBUG
            if (yydebug)
                fprintf(stderr, "%sdebug[%d,trial]: trial parse FAILED, entering ERROR mode\n",
                                YYPREFIX, yydepth);
#endif
            /* Restore state as it was in the most forward-advanced error */
            yylvp          = yylvals   + yyerrctx->lexeme;
#if defined(YYLTYPE) || defined(YYLTYPE_IS_DECLARED)
            yylpp          = yylpsns   + yyerrctx->lexeme;
#endif
            yylexp         = yylexemes + yyerrctx->lexeme;
            yychar         = yylexp[-1];
            yylval         = yylvp[-1];
#if defined(YYLTYPE) || defined(YYLTYPE_IS_DECLARED)
            yylloc         = yylpp[-1];
#endif
            yystack.s_mark = yystack.s_base + (yyerrctx->yystack.s_mark - yyerrctx->yystack.s_base);
            memcpy (yystack.s_base, yyerrctx->yystack.s_base, (size_t) (yystack.s_mark - yystack.s_base + 1) * sizeof(YYINT));
            yystack.l_mark = yystack.l_base + (yyerrctx->yystack.l_mark - yyerrctx->yystack.l_base);
            memcpy (yystack.l_base, yyerrctx->yystack.l_base, (size_t) (yystack.l_mark - yystack.l_base + 1) * sizeof(YYSTYPE));
#if defined(YYLTYPE) || defined(YYLTYPE_IS_DECLARED)
            yystack.p_mark = yystack.p_base + (yyerrctx->yystack.p_mark - yyerrctx->yystack.p_base);
            memcpy (yystack.p_base, yyerrctx->yystack.p_base, (size_t) (yystack.p_mark - yystack.p_base + 1) * sizeof(YYLTYPE));
#endif
            yystate        = yyerrctx->state;
            yyFreeState(yyerrctx);
            yyerrctx       = NULL;
        }
        yynewerrflag = 1;
    }
    if (yynewerrflag == 0) goto yyinrecovery;
#endif /* YYBTYACC */

    YYERROR_CALL("syntax error");
#if defined(YYLTYPE) || defined(YYLTYPE_IS_DECLARED)
    yyerror_loc_range[1] = yylloc; /* lookahead position is error start position */
#endif

#if !YYBTYACC
    goto yyerrlab; /* redundant goto avoids 'unused label' warning */
yyerrlab:
#endif
    ++yynerrs;

yyinrecovery:
    if (yyerrflag < 3)
    {
        yyerrflag = 3;
        for (;;)
        {
            if (((yyn = yysindex[*yystack.s_mark]) != 0) && (yyn += YYERRCODE) >= 0 &&
                    yyn <= YYTABLESIZE && yycheck[yyn] == (YYINT) YYERRCODE)
            {
#if YYDEBUG
                if (yydebug)
                    fprintf(stderr, "%s[%d]: state %d, error recovery shifting to state %d\n",
                                    YYDEBUGSTR, yydepth, *yystack.s_mark, yytable[yyn]);
#endif
                if (yystack.s_mark >= yystack.s_last && yygrowstack(&yystack) == YYENOMEM) goto yyoverflow;
                yystate = yytable[yyn];
                *++yystack.s_mark = yytable[yyn];
                *++yystack.l_mark = yylval;
#if defined(YYLTYPE) || defined(YYLTYPE_IS_DECLARED)
                /* lookahead position is error end position */
                yyerror_loc_range[2] = yylloc;
                YYLLOC_DEFAULT(yyloc, yyerror_loc_range, 2); /* position of error span */
                *++yystack.p_mark = yyloc;
#endif
                goto yyloop;
            }
            else
            {
#if YYDEBUG
                if (yydebug)
                    fprintf(stderr, "%s[%d]: error recovery discarding state %d\n",
                                    YYDEBUGSTR, yydepth, *yystack.s_mark);
#endif
                if (yystack.s_mark <= yystack.s_base) goto yyabort;
#if defined(YYLTYPE) || defined(YYLTYPE_IS_DECLARED)
                /* the current TOS position is the error start position */
                yyerror_loc_range[1] = *yystack.p_mark;
#endif
#if defined(YYDESTRUCT_CALL)
#if YYBTYACC
                if (!yytrial)
#endif /* YYBTYACC */
#if defined(YYLTYPE) || defined(YYLTYPE_IS_DECLARED)
                    YYDESTRUCT_CALL("error: discarding state",
                                    yystos[*yystack.s_mark], yystack.l_mark, yystack.p_mark);
#else
                    YYDESTRUCT_CALL("error: discarding state",
                                    yystos[*yystack.s_mark], yystack.l_mark);
#endif /* defined(YYLTYPE) || defined(YYLTYPE_IS_DECLARED) */
#endif /* defined(YYDESTRUCT_CALL) */
                --yystack.s_mark;
                --yystack.l_mark;
#if defined(YYLTYPE) || defined(YYLTYPE_IS_DECLARED)
                --yystack.p_mark;
#endif
            }
        }
    }
    else
    {
        if (yychar == YYEOF) goto yyabort;
#if YYDEBUG
        if (yydebug)
        {
            if ((yys = yyname[YYTRANSLATE(yychar)]) == NULL) yys = yyname[YYUNDFTOKEN];
            fprintf(stderr, "%s[%d]: state %d, error recovery discarding token %d (%s)\n",
                            YYDEBUGSTR, yydepth, yystate, yychar, yys);
        }
#endif
#if defined(YYDESTRUCT_CALL)
#if YYBTYACC
        if (!yytrial)
#endif /* YYBTYACC */
#if defined(YYLTYPE) || defined(YYLTYPE_IS_DECLARED)
            YYDESTRUCT_CALL("error: discarding token", yychar, &yylval, &yylloc);
#else
            YYDESTRUCT_CALL("error: discarding token", yychar, &yylval);
#endif /* defined(YYLTYPE) || defined(YYLTYPE_IS_DECLARED) */
#endif /* defined(YYDESTRUCT_CALL) */
        yychar = YYEMPTY;
        goto yyloop;
    }

yyreduce:
    yym = yylen[yyn];
#if YYDEBUG
    if (yydebug)
    {
        fprintf(stderr, "%s[%d]: state %d, reducing by rule %d (%s)",
                        YYDEBUGSTR, yydepth, yystate, yyn, yyrule[yyn]);
#ifdef YYSTYPE_TOSTRING
#if YYBTYACC
        if (!yytrial)
#endif /* YYBTYACC */
            if (yym > 0)
            {
                int i;
                fputc('<', stderr);
                for (i = yym; i > 0; i--)
                {
                    if (i != yym) fputs(", ", stderr);
                    fputs(YYSTYPE_TOSTRING(yystos[yystack.s_mark[1-i]],
                                           yystack.l_mark[1-i]), stderr);
                }
                fputc('>', stderr);
            }
#endif
        fputc('\n', stderr);
    }
#endif
    if (yym > 0)
        yyval = yystack.l_mark[1-yym];
    else
        memset(&yyval, 0, sizeof yyval);
#if defined(YYLTYPE) || defined(YYLTYPE_IS_DECLARED)

    /* Perform position reduction */
    memset(&yyloc, 0, sizeof(yyloc));
#if YYBTYACC
    if (!yytrial)
#endif /* YYBTYACC */
    {
        YYLLOC_DEFAULT(yyloc, &yystack.p_mark[-yym], yym);
        /* just in case YYERROR is invoked within the action, save
           the start of the rhs as the error start position */
        yyerror_loc_range[1] = yystack.p_mark[1-yym];
    }
#endif

    switch (yyn)
    {
case 2:
#line 360 "rules.y"
	{ lastname=0; /* outstats(); */  }
#line 2983 "y.tab.c"
break;
case 3:
#line 367 "rules.y"
	{ lastexp=yystack.l_mark[0]; }
#line 2988 "y.tab.c"
break;
case 4:
#line 370 "rules.y"
	{ if(!SYNERR&&yychar==0)
              { evaluate(yystack.l_mark[0]); }
          }
#line 2995 "y.tab.c"
break;
case 5:
#line 378 "rules.y"
	{ word t=type_of(yystack.l_mark[-1]);
              if(t!=wrong_t)
                { lastexp=yystack.l_mark[-1];
                  if(tag[yystack.l_mark[-1]]==ID&&id_type(yystack.l_mark[-1])==wrong_t)t=wrong_t;
                  out_type(t);
                  putchar('\n'); }
            }
#line 3006 "y.tab.c"
break;
case 6:
#line 387 "rules.y"
	{ FILE *fil=NULL,*efil=NULL;
            word t=type_of(yystack.l_mark[-1]);
            char *f=token(),*ef;
            if(f)keep(f); ef=token(); /* wasteful of dic space, FIX LATER */
            if(f){ fil= fopen(f,yystack.l_mark[0]?"a":"w");
                   if(fil==NULL)
                     printf("cannot open \"%s\" for writing\n",f); }
            else printf("filename missing after \"&>\"\n");
            if(ef)
              { efil= fopen(ef,yystack.l_mark[0]?"a":"w");
                if(efil==NULL)
                  printf("cannot open \"%s\" for writing\n",ef); }
            if(t!=wrong_t)yystack.l_mark[-1]=codegen(lastexp=yystack.l_mark[-1]);
            if(!polyshowerror&&t!=wrong_t&&fil!=NULL&&(!ef||efil))
            { int pid;/* launch a concurrent process to perform task */
              sighandler oldsig;
              oldsig=signals(SIGINT,SIG_IGN); /* ignore interrupts */
              if((pid=fork()))
                { /* "parent" */
                  if(pid==-1)perror("cannot create process");
                  else printf("process %d\n",pid);
                  fclose(fil);
                  if(efil)fclose(efil);
                  (void)signals(SIGINT,oldsig); }else
              { /* "child" */
                (void)signals(SIGQUIT,SIG_IGN);   /* and quits */
#ifndef SYSTEM5
                (void)signals(SIGTSTP,SIG_IGN);   /* and stops */
#endif
                close(1); dup(fileno(fil));  /* subvert stdout */
                close(2); dup(fileno(ef?efil:fil)); /* subvert stderr */
                /* FUNNY BUG - if redirect stdout stderr to same file by two
                   calls to freopen, their buffers get conflated - whence do
                   by subverting underlying file descriptors, as above
                   (fix due to Martin Guy) */
                /* formerly used dup2, but not present in system V */
                fclose(stdin);
                /* setbuf(stdout,NIL);  */
		/* not safe to change buffering of stream already in use */
		/* freopen would have reset the buffering automatically */
                lastexp = NIL;  /* what else should we set to NIL? */
                /*atcount= 1; */
                compiling= 0;
                resetgcstats();
                output(isltmess_t(t)?yystack.l_mark[-1]:
                        cons(ap(standardout,isstring_t(t)?yystack.l_mark[-1]:
                                       ap(mkshow(0,0,t),yystack.l_mark[-1])),NIL));
                putchar('\n');
                outstats();
                exit(0); } } }
#line 3060 "y.tab.c"
break;
case 11:
#line 448 "rules.y"
	{ yyval = NOT; }
#line 3065 "y.tab.c"
break;
case 12:
#line 450 "rules.y"
	{ yyval = LENGTH; }
#line 3070 "y.tab.c"
break;
case 14:
#line 455 "rules.y"
	{ yyval = MINUS; }
#line 3075 "y.tab.c"
break;
case 16:
#line 460 "rules.y"
	{ yyval = PLUS; }
#line 3080 "y.tab.c"
break;
case 17:
#line 462 "rules.y"
	{ yyval = APPEND; }
#line 3085 "y.tab.c"
break;
case 18:
#line 464 "rules.y"
	{ yyval = P; }
#line 3090 "y.tab.c"
break;
case 19:
#line 466 "rules.y"
	{ yyval = listdiff_fn; }
#line 3095 "y.tab.c"
break;
case 20:
#line 468 "rules.y"
	{ yyval = OR; }
#line 3100 "y.tab.c"
break;
case 21:
#line 470 "rules.y"
	{ yyval = AND; }
#line 3105 "y.tab.c"
break;
case 23:
#line 473 "rules.y"
	{ yyval = TIMES; }
#line 3110 "y.tab.c"
break;
case 24:
#line 475 "rules.y"
	{ yyval = FDIV; }
#line 3115 "y.tab.c"
break;
case 25:
#line 477 "rules.y"
	{ yyval = INTDIV; }
#line 3120 "y.tab.c"
break;
case 26:
#line 479 "rules.y"
	{ yyval = MOD; }
#line 3125 "y.tab.c"
break;
case 27:
#line 481 "rules.y"
	{ yyval = POWER; }
#line 3130 "y.tab.c"
break;
case 28:
#line 483 "rules.y"
	{ yyval = B; }
#line 3135 "y.tab.c"
break;
case 29:
#line 485 "rules.y"
	{ yyval = ap(C,SUBSCRIPT); }
#line 3140 "y.tab.c"
break;
case 32:
#line 491 "rules.y"
	{ yyval = GR; }
#line 3145 "y.tab.c"
break;
case 33:
#line 493 "rules.y"
	{ yyval = GRE; }
#line 3150 "y.tab.c"
break;
case 34:
#line 495 "rules.y"
	{ yyval = EQ; }
#line 3155 "y.tab.c"
break;
case 35:
#line 497 "rules.y"
	{ yyval = NEQ; }
#line 3160 "y.tab.c"
break;
case 36:
#line 499 "rules.y"
	{ yyval = ap(C,GRE); }
#line 3165 "y.tab.c"
break;
case 37:
#line 501 "rules.y"
	{ yyval = ap(C,GR); }
#line 3170 "y.tab.c"
break;
case 40:
#line 509 "rules.y"
	{ yyval = parse_rhs_cases_where(yystack.l_mark[-2], yystack.l_mark[0]); }
#line 3175 "y.tab.c"
break;
case 41:
#line 511 "rules.y"
	{ yyval = parse_rhs_exp_where(yystack.l_mark[-2], yystack.l_mark[0]); }
#line 3180 "y.tab.c"
break;
case 43:
#line 514 "rules.y"
	{ yyval = parse_rhs_cases(yystack.l_mark[0]); }
#line 3185 "y.tab.c"
break;
case 44:
#line 518 "rules.y"
	{ yyval = parse_case_first(yystack.l_mark[-3], yystack.l_mark[0]); }
#line 3190 "y.tab.c"
break;
case 45:
#line 520 "rules.y"
	{ yyval = parse_case_otherwise_first(yystack.l_mark[-2]); }
#line 3195 "y.tab.c"
break;
case 46:
#line 522 "rules.y"
	{ yyval = parse_case_add(yystack.l_mark[-3], yystack.l_mark[0]); }
#line 3200 "y.tab.c"
break;
case 47:
#line 526 "rules.y"
	{ yyval = parse_alt_obsolete(yystack.l_mark[-1], yystack.l_mark[0]); }
#line 3205 "y.tab.c"
break;
case 48:
#line 528 "rules.y"
	{ yyval = parse_alt_cond(yystack.l_mark[-4], yystack.l_mark[-3], yystack.l_mark[0]); }
#line 3210 "y.tab.c"
break;
case 49:
#line 530 "rules.y"
	{ yyval = parse_alt_otherwise(yystack.l_mark[-3], yystack.l_mark[-2]); }
#line 3215 "y.tab.c"
break;
case 50:
#line 534 "rules.y"
	{ extern word strictif;
            if(strictif)syntax("\"if\" missing\n"); }
#line 3221 "y.tab.c"
break;
case 52:
#line 540 "rules.y"
	{ if(!SYNERR){layout(); setlmargin();}
          }
#line 3227 "y.tab.c"
break;
case 53:
#line 548 "rules.y"
	{ unsetlmargin(); }
#line 3232 "y.tab.c"
break;
case 56:
#line 555 "rules.y"
	{ if(!SYNERR)
              { unsetlmargin(); layout(); setlmargin(); }
          }
#line 3239 "y.tab.c"
break;
case 57:
#line 561 "rules.y"
	{ yyval = parse_liste_first(yystack.l_mark[0]); }
#line 3244 "y.tab.c"
break;
case 58:
#line 563 "rules.y"
	{ yyval = parse_liste_next(yystack.l_mark[-2], yystack.l_mark[0]); }
#line 3249 "y.tab.c"
break;
case 59:
#line 567 "rules.y"
	{ yyval = parse_neg(yystack.l_mark[0]); }
#line 3254 "y.tab.c"
break;
case 60:
#line 569 "rules.y"
	{ yyval = parse_append(yystack.l_mark[-2],yystack.l_mark[0]); }
#line 3259 "y.tab.c"
break;
case 61:
#line 571 "rules.y"
	{ yyval = parse_cons(yystack.l_mark[-2],yystack.l_mark[0]); }
#line 3264 "y.tab.c"
break;
case 62:
#line 573 "rules.y"
	{ yyval = parse_listdiff(yystack.l_mark[-2],yystack.l_mark[0]);  }
#line 3269 "y.tab.c"
break;
case 63:
#line 575 "rules.y"
	{ yyval = parse_or(yystack.l_mark[-2],yystack.l_mark[0]); }
#line 3274 "y.tab.c"
break;
case 64:
#line 577 "rules.y"
	{ yyval = parse_and(yystack.l_mark[-2],yystack.l_mark[0]); }
#line 3279 "y.tab.c"
break;
case 67:
#line 583 "rules.y"
	{ yyval = parse_neg(yystack.l_mark[0]); }
#line 3284 "y.tab.c"
break;
case 68:
#line 585 "rules.y"
	{ yyval = parse_append(yystack.l_mark[-2],yystack.l_mark[0]); }
#line 3289 "y.tab.c"
break;
case 69:
#line 587 "rules.y"
	{ yyval = parse_append_pre(yystack.l_mark[-1]); }
#line 3294 "y.tab.c"
break;
case 70:
#line 589 "rules.y"
	{ yyval = parse_cons(yystack.l_mark[-2],yystack.l_mark[0]); }
#line 3299 "y.tab.c"
break;
case 71:
#line 591 "rules.y"
	{ yyval = parse_cons_pre(yystack.l_mark[-1]); }
#line 3304 "y.tab.c"
break;
case 72:
#line 593 "rules.y"
	{ yyval = parse_listdiff(yystack.l_mark[-2],yystack.l_mark[0]);  }
#line 3309 "y.tab.c"
break;
case 73:
#line 595 "rules.y"
	{ yyval = parse_listdiff_pre(yystack.l_mark[-1]);  }
#line 3314 "y.tab.c"
break;
case 74:
#line 597 "rules.y"
	{ yyval = parse_or(yystack.l_mark[-2],yystack.l_mark[0]); }
#line 3319 "y.tab.c"
break;
case 75:
#line 599 "rules.y"
	{ yyval = parse_or_pre(yystack.l_mark[-1]); }
#line 3324 "y.tab.c"
break;
case 76:
#line 601 "rules.y"
	{ yyval = parse_and(yystack.l_mark[-2],yystack.l_mark[0]); }
#line 3329 "y.tab.c"
break;
case 77:
#line 603 "rules.y"
	{ yyval = parse_and_pre(yystack.l_mark[-1]); }
#line 3334 "y.tab.c"
break;
case 80:
#line 609 "rules.y"
	{ yyval = parse_neg(yystack.l_mark[0]); }
#line 3339 "y.tab.c"
break;
case 81:
#line 611 "rules.y"
	{ yyval = parse_length(yystack.l_mark[0]);  }
#line 3344 "y.tab.c"
break;
case 82:
#line 613 "rules.y"
	{ yyval = parse_plus(yystack.l_mark[-2],yystack.l_mark[0]); }
#line 3349 "y.tab.c"
break;
case 83:
#line 615 "rules.y"
	{ yyval = parse_minus(yystack.l_mark[-2],yystack.l_mark[0]); }
#line 3354 "y.tab.c"
break;
case 84:
#line 617 "rules.y"
	{ yyval = parse_times(yystack.l_mark[-2],yystack.l_mark[0]); }
#line 3359 "y.tab.c"
break;
case 85:
#line 619 "rules.y"
	{ yyval = parse_fdiv(yystack.l_mark[-2],yystack.l_mark[0]); }
#line 3364 "y.tab.c"
break;
case 86:
#line 621 "rules.y"
	{ yyval = parse_intdiv(yystack.l_mark[-2],yystack.l_mark[0]); }
#line 3369 "y.tab.c"
break;
case 87:
#line 623 "rules.y"
	{ yyval = parse_mod(yystack.l_mark[-2],yystack.l_mark[0]); }
#line 3374 "y.tab.c"
break;
case 88:
#line 625 "rules.y"
	{ yyval = parse_power(yystack.l_mark[-2],yystack.l_mark[0]); }
#line 3379 "y.tab.c"
break;
case 89:
#line 627 "rules.y"
	{ yyval = parse_b(yystack.l_mark[-2],yystack.l_mark[0]);  }
#line 3384 "y.tab.c"
break;
case 90:
#line 629 "rules.y"
	{ yyval = parse_subscript(yystack.l_mark[-2],yystack.l_mark[0]); }
#line 3389 "y.tab.c"
break;
case 92:
#line 634 "rules.y"
	{ yyval = parse_neg(yystack.l_mark[0]); }
#line 3394 "y.tab.c"
break;
case 93:
#line 636 "rules.y"
	{ yyval = parse_length(yystack.l_mark[0]);  }
#line 3399 "y.tab.c"
break;
case 94:
#line 638 "rules.y"
	{ yyval = parse_plus(yystack.l_mark[-2],yystack.l_mark[0]); }
#line 3404 "y.tab.c"
break;
case 95:
#line 640 "rules.y"
	{ yyval = parse_plus_pre(yystack.l_mark[-1]); }
#line 3409 "y.tab.c"
break;
case 96:
#line 642 "rules.y"
	{ yyval = parse_minus(yystack.l_mark[-2],yystack.l_mark[0]); }
#line 3414 "y.tab.c"
break;
case 97:
#line 644 "rules.y"
	{ yyval = parse_minus_pre(yystack.l_mark[-1]); }
#line 3419 "y.tab.c"
break;
case 98:
#line 646 "rules.y"
	{ yyval = parse_times(yystack.l_mark[-2],yystack.l_mark[0]); }
#line 3424 "y.tab.c"
break;
case 99:
#line 648 "rules.y"
	{ yyval = parse_times_pre(yystack.l_mark[-1]); }
#line 3429 "y.tab.c"
break;
case 100:
#line 650 "rules.y"
	{ yyval = parse_fdiv(yystack.l_mark[-2],yystack.l_mark[0]); }
#line 3434 "y.tab.c"
break;
case 101:
#line 652 "rules.y"
	{ yyval = parse_fdiv_pre(yystack.l_mark[-1]); }
#line 3439 "y.tab.c"
break;
case 102:
#line 654 "rules.y"
	{ yyval = parse_intdiv(yystack.l_mark[-2],yystack.l_mark[0]); }
#line 3444 "y.tab.c"
break;
case 103:
#line 656 "rules.y"
	{ yyval = parse_intdiv_pre(yystack.l_mark[-1]); }
#line 3449 "y.tab.c"
break;
case 104:
#line 658 "rules.y"
	{ yyval = parse_mod(yystack.l_mark[-2],yystack.l_mark[0]); }
#line 3454 "y.tab.c"
break;
case 105:
#line 660 "rules.y"
	{ yyval = parse_mod_pre(yystack.l_mark[-1]); }
#line 3459 "y.tab.c"
break;
case 106:
#line 662 "rules.y"
	{ yyval = parse_power(yystack.l_mark[-2],yystack.l_mark[0]); }
#line 3464 "y.tab.c"
break;
case 107:
#line 664 "rules.y"
	{ yyval = parse_power_pre(yystack.l_mark[-1]); }
#line 3469 "y.tab.c"
break;
case 108:
#line 666 "rules.y"
	{ yyval = parse_b(yystack.l_mark[-2],yystack.l_mark[0]);  }
#line 3474 "y.tab.c"
break;
case 109:
#line 668 "rules.y"
	{ yyval = parse_b_pre(yystack.l_mark[-1]);  }
#line 3479 "y.tab.c"
break;
case 110:
#line 670 "rules.y"
	{ yyval = parse_subscript(yystack.l_mark[-2],yystack.l_mark[0]); }
#line 3484 "y.tab.c"
break;
case 111:
#line 672 "rules.y"
	{ yyval = parse_subscript_pre(yystack.l_mark[-1]); }
#line 3489 "y.tab.c"
break;
case 113:
#line 677 "rules.y"
	{ yyval = parse_infix(yystack.l_mark[-1],yystack.l_mark[-2],yystack.l_mark[0]); }
#line 3494 "y.tab.c"
break;
case 114:
#line 679 "rules.y"
	{ yyval = parse_infix(yystack.l_mark[-1],yystack.l_mark[-2],yystack.l_mark[0]); }
#line 3499 "y.tab.c"
break;
case 116:
#line 684 "rules.y"
	{ yyval = parse_infix(yystack.l_mark[-1],yystack.l_mark[-2],yystack.l_mark[0]); }
#line 3504 "y.tab.c"
break;
case 117:
#line 686 "rules.y"
	{ yyval = parse_infix_pre(yystack.l_mark[0],yystack.l_mark[-1]); }
#line 3509 "y.tab.c"
break;
case 118:
#line 688 "rules.y"
	{ yyval = parse_infix(yystack.l_mark[-1],yystack.l_mark[-2],yystack.l_mark[0]); }
#line 3514 "y.tab.c"
break;
case 119:
#line 690 "rules.y"
	{ yyval = parse_infix_pre(yystack.l_mark[0],yystack.l_mark[-1]); }
#line 3519 "y.tab.c"
break;
case 121:
#line 695 "rules.y"
	{ yyval = parse_comb_arg(yystack.l_mark[-1],yystack.l_mark[0]); }
#line 3524 "y.tab.c"
break;
case 123:
#line 700 "rules.y"
	{ yyval = parse_infix(yystack.l_mark[-1],yystack.l_mark[-2],yystack.l_mark[0]); }
#line 3529 "y.tab.c"
break;
case 124:
#line 702 "rules.y"
	{ word subject;
            subject = hd(hd(yystack.l_mark[-2]))==AND?tl(tl(yystack.l_mark[-2])):tl(yystack.l_mark[-2]);
            yyval = ap2(AND,yystack.l_mark[-2],ap2(yystack.l_mark[-1],subject,yystack.l_mark[0]));
          }
#line 3537 "y.tab.c"
break;
case 125:
#line 710 "rules.y"
	{ yyval = parse_infix(yystack.l_mark[-1],yystack.l_mark[-2],yystack.l_mark[0]); }
#line 3542 "y.tab.c"
break;
case 126:
#line 712 "rules.y"
	{ yyval = parse_infix_pre(yystack.l_mark[0],yystack.l_mark[-1]); }
#line 3547 "y.tab.c"
break;
case 127:
#line 714 "rules.y"
	{ word subject;
            subject = hd(hd(yystack.l_mark[-2]))==AND?tl(tl(yystack.l_mark[-2])):tl(yystack.l_mark[-2]);
            yyval = ap2(AND,yystack.l_mark[-2],ap2(yystack.l_mark[-1],subject,yystack.l_mark[0]));
          }
#line 3555 "y.tab.c"
break;
case 128:
#line 721 "rules.y"
	{ if(!SYNERR)lexstates=NIL,inlex=1; }
#line 3560 "y.tab.c"
break;
case 129:
#line 723 "rules.y"
	{ inlex=0; lexdefs=NIL;
            if(lexstates!=NIL)
              { word echoed=0;
                for(;lexstates!=NIL;lexstates=tl(lexstates))
                { if(!echoed)printf(echoing?"\n":""),echoed=1;
                  if(!(tl(hd(lexstates))&1))
                    printf("warning: lex state %s is never entered\n",
                           get_id(hd(hd(lexstates)))); else
                  if(!(tl(hd(lexstates))&2))
                    printf("warning: lex state %s has no associated rules\n",
                           get_id(hd(hd(lexstates)))); }
              }
            if(yystack.l_mark[-1]==NIL)syntax("%lex with no rules\n");
            else tag[yystack.l_mark[-1]]=LEXER;
            /* result is lex-list, in reverse order, of items of the form
                 cons(scstuff,cons(matcher,rhs))
               where scstuff is of the form
                 cons(0-or-list-of-startconditions,1+newstartcondition)
            */
            yyval = yystack.l_mark[-1]; }
#line 3584 "y.tab.c"
break;
case 133:
#line 747 "rules.y"
	{ yyval = readvals(0,0); }
#line 3589 "y.tab.c"
break;
case 134:
#line 749 "rules.y"
	{ yyval = show(0,0); }
#line 3594 "y.tab.c"
break;
case 135:
#line 751 "rules.y"
	{ yyval = lastexp;
            if(lastexp==UNDEF)
            syntax("no previous expression to substitute for $$\n"); }
#line 3601 "y.tab.c"
break;
case 136:
#line 755 "rules.y"
	{ yyval = NIL; }
#line 3606 "y.tab.c"
break;
case 137:
#line 757 "rules.y"
	{ yyval = cons(yystack.l_mark[-1],NIL); }
#line 3611 "y.tab.c"
break;
case 138:
#line 759 "rules.y"
	{ yyval = cons(yystack.l_mark[-3],cons(yystack.l_mark[-1],NIL)); }
#line 3616 "y.tab.c"
break;
case 139:
#line 761 "rules.y"
	{ yyval = cons(yystack.l_mark[-5],cons(yystack.l_mark[-3],reverse(yystack.l_mark[-1]))); }
#line 3621 "y.tab.c"
break;
case 140:
#line 763 "rules.y"
	{ yyval = ap3(STEPUNTIL,big_one,yystack.l_mark[-1],yystack.l_mark[-3]); }
#line 3626 "y.tab.c"
break;
case 141:
#line 765 "rules.y"
	{ yyval = ap2(STEP,big_one,yystack.l_mark[-2]); }
#line 3631 "y.tab.c"
break;
case 142:
#line 767 "rules.y"
	{ yyval = ap3(STEPUNTIL,ap2(MINUS,yystack.l_mark[-3],yystack.l_mark[-5]),yystack.l_mark[-1],yystack.l_mark[-5]); }
#line 3636 "y.tab.c"
break;
case 143:
#line 769 "rules.y"
	{ yyval = ap2(STEP,ap2(MINUS,yystack.l_mark[-2],yystack.l_mark[-4]),yystack.l_mark[-4]); }
#line 3641 "y.tab.c"
break;
case 144:
#line 771 "rules.y"
	{ yyval = SYNERR?NIL:compzf(yystack.l_mark[-3],yystack.l_mark[-1],0);  }
#line 3646 "y.tab.c"
break;
case 145:
#line 773 "rules.y"
	{ yyval = SYNERR?NIL:compzf(yystack.l_mark[-3],yystack.l_mark[-1],1);  }
#line 3651 "y.tab.c"
break;
case 146:
#line 775 "rules.y"
	{ yyval = yystack.l_mark[-1]; }
#line 3656 "y.tab.c"
break;
case 147:
#line 777 "rules.y"
	{ yyval = yystack.l_mark[-1]; }
#line 3661 "y.tab.c"
break;
case 148:
#line 779 "rules.y"
	{ yyval = (tag[yystack.l_mark[-2]]==AP&&hd(yystack.l_mark[-2])==C)?ap(tl(yystack.l_mark[-2]),yystack.l_mark[-1]): /* optimisation */
                 ap2(C,yystack.l_mark[-2],yystack.l_mark[-1]); }
#line 3667 "y.tab.c"
break;
case 149:
#line 782 "rules.y"
	{ yyval = Void; }
#line 3672 "y.tab.c"
break;
case 150:
#line 784 "rules.y"
	{ if(tl(yystack.l_mark[-1])==NIL)yyval=pair(yystack.l_mark[-3],hd(yystack.l_mark[-1]));
            else { yyval=pair(hd(tl(yystack.l_mark[-1])),hd(yystack.l_mark[-1]));
                   yystack.l_mark[-1]=tl(tl(yystack.l_mark[-1]));
                   while(yystack.l_mark[-1]!=NIL)yyval=tcons(hd(yystack.l_mark[-1]),yyval),yystack.l_mark[-1]=tl(yystack.l_mark[-1]);
                   yyval = tcons(yystack.l_mark[-3],yyval); }
          /* representation of the tuple (a1,...,an) is
             tcons(a1,tcons(a2,...pair(a(n-1),an))) */
          }
#line 3684 "y.tab.c"
break;
case 151:
#line 794 "rules.y"
	{ if(!SYNERR)inlex=2; }
#line 3689 "y.tab.c"
break;
case 152:
#line 795 "rules.y"
	{ if(!SYNERR)inlex=1; }
#line 3694 "y.tab.c"
break;
case 153:
#line 796 "rules.y"
	{ if(yystack.l_mark[-2]<0 && e_re(yystack.l_mark[-7]))
              errs=yystack.l_mark[-8],
              syntax("illegal lex rule - lhs matches empty\n");
            yyval = cons(cons(cons(yystack.l_mark[-9],1+yystack.l_mark[-2]),cons(yystack.l_mark[-7],label(yystack.l_mark[-8],yystack.l_mark[-3]))),yystack.l_mark[-10]); }
#line 3702 "y.tab.c"
break;
case 154:
#line 801 "rules.y"
	{ yyval = NIL; }
#line 3707 "y.tab.c"
break;
case 155:
#line 805 "rules.y"
	{ yyval = 0; }
#line 3712 "y.tab.c"
break;
case 156:
#line 807 "rules.y"
	{ word ns=NIL;
            for(;yystack.l_mark[-1]!=NIL;yystack.l_mark[-1]=tl(yystack.l_mark[-1]))
               { word *x = &lexstates,i=1;
                 while(*x!=NIL&&hd(hd(*x))!=hd(yystack.l_mark[-1]))i++,x = &tl(*x);
                 if(*x == NIL)*x = cons(cons(hd(yystack.l_mark[-1]),2),NIL);
                 else tl(hd(*x)) |= 2; 
                 ns = add1(i,ns); }
            yyval = ns; }
#line 3724 "y.tab.c"
break;
case 157:
#line 818 "rules.y"
	{ yyval=cons(yystack.l_mark[0],NIL); }
#line 3729 "y.tab.c"
break;
case 158:
#line 820 "rules.y"
	{ if(member(yystack.l_mark[-1],yystack.l_mark[0]))
     printf("%ssyntax error: repeated name \"%s\" in start conditions\n",
                      echoing?"\n":"",get_id(yystack.l_mark[0])),
              acterror();
            yyval = cons(yystack.l_mark[0],yystack.l_mark[-1]); }
#line 3738 "y.tab.c"
break;
case 159:
#line 828 "rules.y"
	{ yyval = -1; }
#line 3743 "y.tab.c"
break;
case 160:
#line 830 "rules.y"
	{ word *x = &lexstates,i=1;
                while(*x!=NIL&&hd(hd(*x))!=yystack.l_mark[0])i++,x = &tl(*x);
                if(*x == NIL)*x = cons(cons(yystack.l_mark[0],1),NIL);
                else tl(hd(*x)) |= 1;
                yyval = i;
              }
#line 3753 "y.tab.c"
break;
case 161:
#line 837 "rules.y"
	{ if(!isnat(yystack.l_mark[0])||get_int(yystack.l_mark[0])!=0)
                   syntax("%begin not followed by IDENTIFIER or 0\n");
                yyval = 0; }
#line 3760 "y.tab.c"
break;
case 162:
#line 843 "rules.y"
	{ lexdefs = cons(cons(yystack.l_mark[-4],yystack.l_mark[-1]),lexdefs); }
#line 3765 "y.tab.c"
break;
case 163:
#line 845 "rules.y"
	{ lexdefs = NIL; }
#line 3770 "y.tab.c"
break;
case 164:
#line 849 "rules.y"
	{ yyval = ap2(LEX_OR,yystack.l_mark[-2],yystack.l_mark[0]); }
#line 3775 "y.tab.c"
break;
case 166:
#line 854 "rules.y"
	{ yyval = ap2(LEX_RCONTEXT,yystack.l_mark[-2],yystack.l_mark[0]); }
#line 3780 "y.tab.c"
break;
case 167:
#line 856 "rules.y"
	{ yyval = ap2(LEX_RCONTEXT,yystack.l_mark[-1],0); }
#line 3785 "y.tab.c"
break;
case 169:
#line 861 "rules.y"
	{ yyval = ap2(LEX_SEQ,yystack.l_mark[-1],yystack.l_mark[0]); }
#line 3790 "y.tab.c"
break;
case 171:
#line 866 "rules.y"
	{ if(e_re(yystack.l_mark[-1]))
            syntax("illegal regular expression - arg of * matches empty\n");
          yyval = ap(LEX_STAR,yystack.l_mark[-1]); }
#line 3797 "y.tab.c"
break;
case 172:
#line 870 "rules.y"
	{ yyval = ap2(LEX_SEQ,yystack.l_mark[-1],ap(LEX_STAR,yystack.l_mark[-1])); }
#line 3802 "y.tab.c"
break;
case 173:
#line 872 "rules.y"
	{ yyval = ap(LEX_OPT,yystack.l_mark[-1]); }
#line 3807 "y.tab.c"
break;
case 175:
#line 877 "rules.y"
	{ yyval = yystack.l_mark[-1]; }
#line 3812 "y.tab.c"
break;
case 176:
#line 879 "rules.y"
	{ if(!isstring(yystack.l_mark[0]))
              printf("%ssyntax error - unexpected token \"",
                        echoing?"\n":""),
              out(stdout,yystack.l_mark[0]),printf("\" in regular expression\n"),
              acterror();
            yyval = yystack.l_mark[0]==NILS?ap(LEX_STRING,NIL):
                 tl(yystack.l_mark[0])==NIL?ap(LEX_CHAR,hd(yystack.l_mark[0])):
                             ap(LEX_STRING,yystack.l_mark[0]);
          }
#line 3825 "y.tab.c"
break;
case 177:
#line 889 "rules.y"
	{ if(yystack.l_mark[0]==NIL)
              syntax("empty character class `` cannot match\n");
            yyval = tl(yystack.l_mark[0])==NIL?ap(LEX_CHAR,hd(yystack.l_mark[0])):ap(LEX_CLASS,yystack.l_mark[0]); }
#line 3832 "y.tab.c"
break;
case 178:
#line 893 "rules.y"
	{ yyval = ap(LEX_CLASS,cons(ANTICHARCLASS,yystack.l_mark[0])); }
#line 3837 "y.tab.c"
break;
case 179:
#line 895 "rules.y"
	{ yyval = LEX_DOT; }
#line 3842 "y.tab.c"
break;
case 180:
#line 897 "rules.y"
	{ word x=lexdefs;
            while(x!=NIL&&hd(hd(x))!=yystack.l_mark[0])x=tl(x);
            if(x==NIL)
              printf(
      "%ssyntax error: undefined lexeme %s in regular expression\n",
                      echoing?"\n":"",
                      get_id(yystack.l_mark[0])),
                  acterror();
            else yyval = tl(hd(x)); }
#line 3855 "y.tab.c"
break;
case 183:
#line 911 "rules.y"
	{ yyval = cons(cons(GUARD,yystack.l_mark[0]),NIL);  }
#line 3860 "y.tab.c"
break;
case 184:
#line 913 "rules.y"
	{ yyval = cons(yystack.l_mark[0],NIL);  }
#line 3865 "y.tab.c"
break;
case 185:
#line 915 "rules.y"
	{ yyval = cons(yystack.l_mark[0],yystack.l_mark[-2]);   }
#line 3870 "y.tab.c"
break;
case 186:
#line 917 "rules.y"
	{ yyval = cons(cons(GUARD,yystack.l_mark[0]),yystack.l_mark[-2]);   }
#line 3875 "y.tab.c"
break;
case 187:
#line 921 "rules.y"
	{ /* fix syntax to disallow patlist on lhs of iterate generator */
            if(hd(yystack.l_mark[0])==GENERATOR)
              { word e=tl(tl(yystack.l_mark[0]));
                if(tag[e]==AP&&tag[hd(e)]==AP&&
                    (hd(hd(e))==ITERATE||hd(hd(e))==ITERATE1))
                  syntax("ill-formed generator\n"); }
            yyval = cons(REPEAT,cons(genlhs(yystack.l_mark[-2]),yystack.l_mark[0])); idsused=NIL;  }
#line 3886 "y.tab.c"
break;
case 189:
#line 932 "rules.y"
	{ yyval = cons(GENERATOR,cons(genlhs(yystack.l_mark[-2]),yystack.l_mark[0])); idsused=NIL;  }
#line 3891 "y.tab.c"
break;
case 190:
#line 934 "rules.y"
	{ word p = genlhs(yystack.l_mark[-5]); idsused=NIL;
            yyval = cons(GENERATOR,
                      cons(p,ap2(irrefutable(p)?ITERATE:ITERATE1,
                                 lambda(p,yystack.l_mark[-1]),yystack.l_mark[-3])));
          }
#line 3900 "y.tab.c"
break;
case 193:
#line 946 "rules.y"
	{ word l = yystack.l_mark[-6], r = yystack.l_mark[-1];
            word f = head(l);
            if(tag[f]==ID&&!isconstructor(f)) /* fnform defn */
              while(tag[l]==AP)r=lambda(tl(l),r),l=hd(l);
            r = label(yystack.l_mark[-2],r); /* to help locate type errors */
            declare(l,r),lastname=l; }
#line 3910 "y.tab.c"
break;
case 194:
#line 954 "rules.y"
	{ word h=reverse(hd(yystack.l_mark[0])),hr=hd(tl(yystack.l_mark[0])),t=tl(tl(yystack.l_mark[0]));
            while(h!=NIL&&!SYNERR)specify(hd(h),t,hr),h=tl(h);
            yyval = cons(nill,NIL); }
#line 3917 "y.tab.c"
break;
case 195:
#line 959 "rules.y"
	{ extern word TABSTRS;
            extern char *dicp,*dicq;
            word x=reverse(yystack.l_mark[-1]),ids=NIL,tids=NIL;
            while(x!=NIL&&!SYNERR)
                 specify(hd(hd(x)),cons(tl(tl(hd(x))),NIL),hd(tl(hd(x)))),
                  ids=cons(hd(hd(x)),ids),x=tl(x);
            /* each id in specs has its id_type set to const(t,NIL) as a way
               of flagging that t is an abstract type */
            x=reverse(yystack.l_mark[-4]);
            while(x!=NIL&&!SYNERR)
               { word shfn;
                 decl_type(hd(x),abstract_t,undef_t,yystack.l_mark[-5]);
                 tids=cons(head(hd(x)),tids);
                 /* check for presence of showfunction */
                 (void)strcpy(dicp,"show");
                 (void)strcat(dicp,get_id(hd(tids)));
                 dicq = dicp+strlen(dicp)+1;
                 shfn=name();
                 if(member(ids,shfn))
                   t_showfn(hd(tids))=shfn;
                 x=tl(x); }
            TABSTRS = cons(cons(tids,ids),TABSTRS);
            yyval = cons(nill,NIL); }
#line 3944 "y.tab.c"
break;
case 196:
#line 984 "rules.y"
	{ word x=redtvars(ap(yystack.l_mark[-7],yystack.l_mark[-2]));
            decl_type(hd(x),synonym_t,tl(x),yystack.l_mark[-4]);
            yyval = cons(nill,NIL); }
#line 3951 "y.tab.c"
break;
case 197:
#line 989 "rules.y"
	{ word rhs = yystack.l_mark[-2], r_ids = yystack.l_mark[-2], n=0;
            while(r_ids!=NIL)r_ids=tl(r_ids),n++;
            while(rhs!=NIL&&!SYNERR)
            {  word h=hd(rhs),t=yystack.l_mark[-7],stricts=NIL,i=0;
               while(tag[h]==AP)
                    { if(tag[tl(h)]==AP&&hd(tl(h))==strict_t)
                        stricts=cons(i,stricts),tl(h)=tl(tl(h));
                      t=ap2(arrow_t,tl(h),t),h=hd(h),i++; }
               if(tag[h]==ID)
                 declconstr(h,--n,t);
                 /* warning - type not yet in reduced form */
               else { stricts=NIL;
                      if(echoing)putchar('\n');
                      printf("syntax error: illegal construct \"");
                      out_type(hd(rhs));
                      printf("\" on right of ::=\n");
                      acterror(); } /* can this still happen? check later */
               if(stricts!=NIL) /* ! operators were present */
                 { word k = id_val(h);
                   while(stricts!=NIL)
                        k=ap2(MKSTRICT,i-hd(stricts),k),
                        stricts=tl(stricts);
                   id_val(h)=k; /* overwrite id_val of original constructor */
                 }
               r_ids=cons(h,r_ids);
               rhs = tl(rhs); }
            if(!SYNERR)decl_type(yystack.l_mark[-7],algebraic_t,r_ids,yystack.l_mark[-4]);
            yyval = cons(nill,NIL); }
#line 3983 "y.tab.c"
break;
case 198:
#line 1019 "rules.y"
	{ inexplist=0;
            if(exports!=NIL)
              errs=yystack.l_mark[-3],
              syntax("multiple %export statements are illegal\n");
            else { if(yystack.l_mark[-1]==NIL&&exportfiles==NIL&&embargoes!=NIL)
		     exportfiles=cons(PLUS,NIL);
                   exports=cons(yystack.l_mark[-3],yystack.l_mark[-1]); } /* cons(hereinfo,identifiers) */
            yyval = cons(nill,NIL); }
#line 3995 "y.tab.c"
break;
case 199:
#line 1029 "rules.y"
	{ if(freeids!=NIL)
              errs=yystack.l_mark[-3],
              syntax("multiple %free statements are illegal\n"); else
            { word x=reverse(yystack.l_mark[-1]);
              while(x!=NIL&&!SYNERR)
                 { specify(hd(hd(x)),tl(tl(hd(x))),hd(tl(hd(x))));
                   freeids=cons(head(hd(hd(x))),freeids);
                   if(tl(tl(hd(x)))==type_t)
                     t_class(hd(freeids))=free_t;
                   else id_val(hd(freeids))=FREE; /* conventional value */
                   x=tl(x); }
              fil_share(hd(files))=0; /* parameterised scripts unshareable */
              freeids=alfasort(freeids); 
              for(x=freeids;x!=NIL;x=tl(x))
                 hd(x)=cons(hd(x),cons(datapair(get_id(hd(x)),0),
                       id_type(hd(x))));
              /* each element of freeids is of the form
                 cons(id,cons(original_name,type)) */
            }
            yyval = cons(nill,NIL); }
#line 4019 "y.tab.c"
break;
case 200:
#line 1052 "rules.y"
	{ includees=cons(cons(yystack.l_mark[-3],cons(yystack.l_mark[-1],yystack.l_mark[-2])),includees);
                   /* $1 contains file+hereinfo */
            yyval = cons(nill,NIL); }
#line 4026 "y.tab.c"
break;
case 201:
#line 1056 "rules.y"
	{ startbnf(); inbnf=1;}
#line 4031 "y.tab.c"
break;
case 202:
#line 1058 "rules.y"
	{ word lhs=NIL,p=yystack.l_mark[-1],subjects,body,startswith=NIL,leftrecs=NIL;
            ihlist=inbnf=0;
            nonterminals=UNION(nonterminals,yystack.l_mark[-3]);
            for(;p!=NIL;p=tl(p))
            if(dval(hd(p))==UNDEF)nonterminals=add1(dlhs(hd(p)),nonterminals);
             else lhs=add1(dlhs(hd(p)),lhs);
            nonterminals=setdiff(nonterminals,lhs);
            if(nonterminals!=NIL)
              errs=yystack.l_mark[-6],
              member(yystack.l_mark[-3],hd(nonterminals))/*||findnt(hd(nonterminals))*/,
              printf("%sfatal error in grammar, ",echoing?"\n":""),
              printf("undefined nonterminal%s: ",
                      tl(nonterminals)==NIL?"":"s"),
              printlist("",nonterminals),
              acterror(); else
            { /* compute list of nonterminals admitting empty prodn */
            eprodnts=NIL;
          L:for(p=yystack.l_mark[-1];p!=NIL;p=tl(p))
               if(!member(eprodnts,dlhs(hd(p)))&&eprod(dval(hd(p))))
                 { eprodnts=cons(dlhs(hd(p)),eprodnts); goto L; }
            /* now compute startswith reln between nonterminals
               (performing binomial transformation en route)
               and use to detect unremoved left recursion */
            for(p=yystack.l_mark[-1];p!=NIL;p=tl(p))
               if(member(lhs=starts(dval(hd(p))),dlhs(hd(p))))
                 binom(dval(hd(p)),dlhs(hd(p))),
                 startswith=cons(cons(dlhs(hd(p)),starts(dval(hd(p)))),
                                 startswith);
               else startswith=cons(cons(dlhs(hd(p)),lhs),startswith);
            startswith=tclos(sortrel(startswith));
            for(;startswith!=NIL;startswith=tl(startswith))
               if(member(tl(hd(startswith)),hd(hd(startswith))))
                 leftrecs=add1(hd(hd(startswith)),leftrecs);
            if(leftrecs!=NIL)
              errs=getloc(hd(leftrecs),yystack.l_mark[-1]),
              printf("%sfatal error in grammar, ",echoing?"\n":""),
              printlist("irremovable left recursion: ",leftrecs),
              acterror();
            if(yystack.l_mark[-3]==NIL) /* implied start symbol */
              yystack.l_mark[-3]=cons(dlhs(hd(lastlink(yystack.l_mark[-1]))),NIL);
            fnts=1; /* fnts is flag indicating %bnf in use */
            if(tl(yystack.l_mark[-3])==NIL) /* only one start symbol */
              subjects=getfname(hd(yystack.l_mark[-3])),
              body=ap2(G_CLOSE,str_conv(get_id(hd(yystack.l_mark[-3]))),hd(yystack.l_mark[-3]));
            else
            { body=subjects=Void;
              while(yystack.l_mark[-3]!=NIL)
                   subjects=pair(getfname(hd(yystack.l_mark[-3])),subjects),
                   body=pair(
                         ap2(G_CLOSE,str_conv(get_id(hd(yystack.l_mark[-3]))),hd(yystack.l_mark[-3])),
                            body),
                   yystack.l_mark[-3]=tl(yystack.l_mark[-3]);
            }
            declare(subjects,label(yystack.l_mark[-6],block(yystack.l_mark[-1],body, 0)));
          }}
#line 4090 "y.tab.c"
break;
case 203:
#line 1116 "rules.y"
	{ yyval=yystack.l_mark[0];
             inexplist=1; }
#line 4096 "y.tab.c"
break;
case 204:
#line 1121 "rules.y"
	{ yyval = NIL; }
#line 4101 "y.tab.c"
break;
case 205:
#line 1123 "rules.y"
	{ yyval = yystack.l_mark[-1]; }
#line 4106 "y.tab.c"
break;
case 206:
#line 1127 "rules.y"
	{ yyval = cons(yystack.l_mark[0],yystack.l_mark[-1]); }
#line 4111 "y.tab.c"
break;
case 207:
#line 1129 "rules.y"
	{ yyval = cons(yystack.l_mark[0],NIL); }
#line 4116 "y.tab.c"
break;
case 208:
#line 1133 "rules.y"
	{ yyval = cons(yystack.l_mark[-4],yystack.l_mark[-1]); }
#line 4121 "y.tab.c"
break;
case 209:
#line 1135 "rules.y"
	{ word x=redtvars(ap(yystack.l_mark[-6],yystack.l_mark[-2])); 
             word arity=0,h=hd(x);
             while(tag[h]==AP)arity++,h=hd(h);
             yyval = ap(h,make_typ(arity,0,synonym_t,tl(x)));
           }
#line 4130 "y.tab.c"
break;
case 210:
#line 1143 "rules.y"
	{ yyval = NIL; }
#line 4135 "y.tab.c"
break;
case 211:
#line 1145 "rules.y"
	{ word a,b,c=0;
             for(a=yystack.l_mark[0];a!=NIL;a=tl(a))
                for(b=tl(a);b!=NIL;b=tl(b))
                   { if(hd(hd(a))==hd(hd(b)))c=hd(hd(a));
                     if(tl(hd(a))==tl(hd(b)))c=tl(hd(a)); 
                     if(c)break; }
             if(c)printf(
                  "%ssyntax error: conflicting aliases (\"%s\")\n",
                      echoing?"\n":"",
                      get_id(c)),
                  acterror();
           }
#line 4151 "y.tab.c"
break;
case 212:
#line 1160 "rules.y"
	{ yyval = cons(yystack.l_mark[0],yystack.l_mark[-1]); }
#line 4156 "y.tab.c"
break;
case 213:
#line 1162 "rules.y"
	{ yyval = cons(yystack.l_mark[0],NIL); }
#line 4161 "y.tab.c"
break;
case 214:
#line 1166 "rules.y"
	{ yyval = cons(yystack.l_mark[-2],yystack.l_mark[0]); }
#line 4166 "y.tab.c"
break;
case 215:
#line 1168 "rules.y"
	{ yyval = cons(yystack.l_mark[-2],yystack.l_mark[0]); }
#line 4171 "y.tab.c"
break;
case 216:
#line 1170 "rules.y"
	{ yyval = cons(make_pn(UNDEF),yystack.l_mark[0]); }
#line 4176 "y.tab.c"
break;
case 217:
#line 1175 "rules.y"
	{ extern word line_no;
             lasth = yyval = fileinfo(get_fil(current_file),line_no);
             /* (script,line_no) for diagnostics */
           }
#line 4184 "y.tab.c"
break;
case 218:
#line 1182 "rules.y"
	{ tvarscope=1; }
#line 4189 "y.tab.c"
break;
case 219:
#line 1186 "rules.y"
	{ tvarscope=0; idsused= NIL; }
#line 4194 "y.tab.c"
break;
case 220:
#line 1190 "rules.y"
	{ yyval = cons(yystack.l_mark[0],NIL);
            dval(yystack.l_mark[0]) = tries(dlhs(yystack.l_mark[0]),cons(dval(yystack.l_mark[0]),NIL));
            if(!SYNERR&&get_ids(dlhs(yystack.l_mark[0]))==NIL)
              errs=hd(hd(tl(dval(yystack.l_mark[0])))),
              syntax("illegal lhs for local definition\n");
          }
#line 4204 "y.tab.c"
break;
case 221:
#line 1197 "rules.y"
	{ if(dlhs(yystack.l_mark[0])==dlhs(hd(yystack.l_mark[-1])) /*&&dval(hd($1))!=UNDEF*/)
              { yyval = yystack.l_mark[-1];
                if(!fallible(hd(tl(dval(hd(yystack.l_mark[-1]))))))
                    errs=hd(dval(yystack.l_mark[0])),
                    printf("%ssyntax error: \
unreachable case in defn of \"%s\"\n",echoing?"\n":"",get_id(dlhs(yystack.l_mark[0]))),
                    acterror();
                tl(dval(hd(yystack.l_mark[-1])))=cons(dval(yystack.l_mark[0]),tl(dval(hd(yystack.l_mark[-1])))); }
            else if(!SYNERR)
                 { word ns=get_ids(dlhs(yystack.l_mark[0])),hr=hd(dval(yystack.l_mark[0]));
                   if(ns==NIL)
                     errs=hr,
                     syntax("illegal lhs for local definition\n");
                   yyval = cons(yystack.l_mark[0],yystack.l_mark[-1]);
                   dval(yystack.l_mark[0])=tries(dlhs(yystack.l_mark[0]),cons(dval(yystack.l_mark[0]),NIL));
                   while(ns!=NIL&&!SYNERR) /* local nameclash check */
                        { nclashcheck(hd(ns),yystack.l_mark[-1],hr);
                          ns=tl(ns); }
                        /* potentially quadratic - fix later */
                 }
          }
#line 4229 "y.tab.c"
break;
case 222:
#line 1221 "rules.y"
	{ errs=hd(tl(yystack.l_mark[0]));
            syntax("`::' encountered in local defs\n");
            yyval = cons(nill,NIL); }
#line 4236 "y.tab.c"
break;
case 223:
#line 1225 "rules.y"
	{ errs=yystack.l_mark[-1];
            syntax("`==' encountered in local defs\n");
            yyval = cons(nill,NIL); }
#line 4243 "y.tab.c"
break;
case 224:
#line 1229 "rules.y"
	{ errs=yystack.l_mark[-1];
            syntax("`::=' encountered in local defs\n");
            yyval = cons(nill,NIL); }
#line 4250 "y.tab.c"
break;
case 225:
#line 1233 "rules.y"
	{ word l = yystack.l_mark[-6], r = yystack.l_mark[-1];
            word f = head(l);
            if(tag[f]==ID&&!isconstructor(f)) /* fnform defn */
              while(tag[l]==AP)r=lambda(tl(l),r),l=hd(l);
            r = label(yystack.l_mark[-2],r); /* to help locate type errors */
            yyval = defn(l,undef_t,r); }
#line 4260 "y.tab.c"
break;
case 226:
#line 1242 "rules.y"
	{ yyval = cons(yystack.l_mark[0],NIL); }
#line 4265 "y.tab.c"
break;
case 227:
#line 1244 "rules.y"
	{ yyval = cons(yystack.l_mark[0],yystack.l_mark[-2]);  }
#line 4270 "y.tab.c"
break;
case 229:
#line 1249 "rules.y"
	{ yyval = cons(yystack.l_mark[-2],yystack.l_mark[0]); }
#line 4275 "y.tab.c"
break;
case 230:
#line 1253 "rules.y"
	{ if(!isnat(yystack.l_mark[0]))
              syntax("inappropriate use of \"+\" in pattern\n");
            yyval = ap2(PLUS,yystack.l_mark[0],yystack.l_mark[-2]); }
#line 4282 "y.tab.c"
break;
case 231:
#line 1257 "rules.y"
	{ /* if(tag[$2]==DOUBLE)
              $$ = cons(CONST,sto_dbl(-get_dbl($2))); else */
            if(tag[yystack.l_mark[0]]==INT)
              yyval = cons(CONST,bignegate(yystack.l_mark[0])); else
            syntax("inappropriate use of \"-\" in pattern\n"); }
#line 4291 "y.tab.c"
break;
case 232:
#line 1263 "rules.y"
	{ yyval = ap2(yystack.l_mark[-1],yystack.l_mark[-2],yystack.l_mark[0]); }
#line 4296 "y.tab.c"
break;
case 233:
#line 1265 "rules.y"
	{ yyval = ap2(yystack.l_mark[-1],yystack.l_mark[-2],yystack.l_mark[0]); }
#line 4301 "y.tab.c"
break;
case 236:
#line 1271 "rules.y"
	{ yyval = ap(hd(yystack.l_mark[-1])==CONST&&tag[tl(yystack.l_mark[-1])]==ID?tl(yystack.l_mark[-1]):yystack.l_mark[-1],yystack.l_mark[0]); }
#line 4306 "y.tab.c"
break;
case 237:
#line 1277 "rules.y"
	{ if(sreds&&member(gvars,yystack.l_mark[0]))syntax("illegal use of $num symbol\n");
              /* cannot use grammar variable in a binding position */
            if(memb(idsused,yystack.l_mark[0]))yyval = cons(CONST,yystack.l_mark[0]);
                            /* picks up repeated names in a template */
            else idsused= cons(yystack.l_mark[0],idsused);   }
#line 4315 "y.tab.c"
break;
case 239:
#line 1284 "rules.y"
	{ if(tag[yystack.l_mark[0]]==DOUBLE)
	      syntax("use of floating point literal in pattern\n");
	    yyval = cons(CONST,yystack.l_mark[0]); }
#line 4322 "y.tab.c"
break;
case 240:
#line 1288 "rules.y"
	{ yyval = nill; }
#line 4327 "y.tab.c"
break;
case 241:
#line 1290 "rules.y"
	{ word x=yystack.l_mark[-1],y=nill;
            while(x!=NIL)y = cons(hd(x),y), x = tl(x);
            yyval = y; }
#line 4334 "y.tab.c"
break;
case 242:
#line 1294 "rules.y"
	{ yyval = Void; }
#line 4339 "y.tab.c"
break;
case 243:
#line 1296 "rules.y"
	{ yyval = yystack.l_mark[-1]; }
#line 4344 "y.tab.c"
break;
case 244:
#line 1298 "rules.y"
	{ if(tl(yystack.l_mark[-1])==NIL)yyval=pair(yystack.l_mark[-3],hd(yystack.l_mark[-1]));
            else { yyval=pair(hd(tl(yystack.l_mark[-1])),hd(yystack.l_mark[-1]));
                   yystack.l_mark[-1]=tl(tl(yystack.l_mark[-1]));
                   while(yystack.l_mark[-1]!=NIL)yyval=tcons(hd(yystack.l_mark[-1]),yyval),yystack.l_mark[-1]=tl(yystack.l_mark[-1]);
                   yyval = tcons(yystack.l_mark[-3],yyval); }
          /* representation of the tuple (a1,...,an) is
             tcons(a1,tcons(a2,...pair(a(n-1),an))) */
          }
#line 4356 "y.tab.c"
break;
case 246:
#line 1310 "rules.y"
	{ yyval = ap2(arrow_t,yystack.l_mark[-2],yystack.l_mark[0]); }
#line 4361 "y.tab.c"
break;
case 247:
#line 1314 "rules.y"
	{ yyval = ap2(yystack.l_mark[-1],yystack.l_mark[-2],yystack.l_mark[0]); }
#line 4366 "y.tab.c"
break;
case 251:
#line 1325 "rules.y"
	{ yyval = ap(yystack.l_mark[-1],yystack.l_mark[0]); }
#line 4371 "y.tab.c"
break;
case 252:
#line 1327 "rules.y"
	{ yyval = ap(yystack.l_mark[-1],yystack.l_mark[0]); }
#line 4376 "y.tab.c"
break;
case 253:
#line 1331 "rules.y"
	{ yyval = transtypeid(yystack.l_mark[0]); }
#line 4381 "y.tab.c"
break;
case 254:
#line 1334 "rules.y"
	{ if(tvarscope&&!memb(idsused,yystack.l_mark[0]))
              printf("%ssyntax error: unbound type variable ",echoing?"\n":""),
                 out_type(yystack.l_mark[0]),putchar('\n'),acterror();
            yyval = yystack.l_mark[0]; }
#line 4389 "y.tab.c"
break;
case 255:
#line 1339 "rules.y"
	{ yyval = yystack.l_mark[-1]; }
#line 4394 "y.tab.c"
break;
case 256:
#line 1341 "rules.y"
	{ yyval = ap(list_t,yystack.l_mark[-1]); }
#line 4399 "y.tab.c"
break;
case 257:
#line 1343 "rules.y"
	{ syntax(
             "tuple-type with missing parentheses (obsolete syntax)\n"); }
#line 4405 "y.tab.c"
break;
case 258:
#line 1348 "rules.y"
	{ yyval = void_t; }
#line 4410 "y.tab.c"
break;
case 260:
#line 1351 "rules.y"
	{ word x=yystack.l_mark[0],y=void_t;
            while(x!=NIL)y = ap2(comma_t,hd(x),y), x = tl(x);
            yyval = ap2(comma_t,yystack.l_mark[-2],y); }
#line 4417 "y.tab.c"
break;
case 261:
#line 1357 "rules.y"
	{ yyval = cons(yystack.l_mark[0],NIL); }
#line 4422 "y.tab.c"
break;
case 262:
#line 1359 "rules.y"
	{ yyval = cons(yystack.l_mark[0],yystack.l_mark[-2]); }
#line 4427 "y.tab.c"
break;
case 263:
#line 1363 "rules.y"
	{ yyval = add1(yystack.l_mark[0],yystack.l_mark[-1]); }
#line 4432 "y.tab.c"
break;
case 264:
#line 1365 "rules.y"
	{ yyval = yystack.l_mark[-2]; embargoes=add1(yystack.l_mark[0],embargoes); }
#line 4437 "y.tab.c"
break;
case 265:
#line 1367 "rules.y"
	{ yyval = yystack.l_mark[-1]; }
#line 4442 "y.tab.c"
break;
case 266:
#line 1369 "rules.y"
	{ yyval = yystack.l_mark[-1];
            exportfiles=cons(PLUS,exportfiles); }
#line 4448 "y.tab.c"
break;
case 267:
#line 1372 "rules.y"
	{ yyval = add1(yystack.l_mark[0],NIL); }
#line 4453 "y.tab.c"
break;
case 268:
#line 1374 "rules.y"
	{ yyval = NIL; embargoes=add1(yystack.l_mark[0],embargoes); }
#line 4458 "y.tab.c"
break;
case 269:
#line 1376 "rules.y"
	{ yyval = NIL; }
#line 4463 "y.tab.c"
break;
case 270:
#line 1378 "rules.y"
	{ yyval = NIL;
            exportfiles=cons(PLUS,exportfiles); }
#line 4469 "y.tab.c"
break;
case 271:
#line 1384 "rules.y"
	{ word x=yystack.l_mark[-1],h=hd(yystack.l_mark[0]),t=tl(yystack.l_mark[0]);
            while(h!=NIL)x=cons(cons(hd(h),t),x),h=tl(h);
            yyval = x; }
#line 4476 "y.tab.c"
break;
case 272:
#line 1388 "rules.y"
	{ word x=NIL,h=hd(yystack.l_mark[0]),t=tl(yystack.l_mark[0]);
            while(h!=NIL)x=cons(cons(hd(h),t),x),h=tl(h);
            yyval = x; }
#line 4483 "y.tab.c"
break;
case 273:
#line 1394 "rules.y"
	{ yyval = cons(yystack.l_mark[-5],cons(yystack.l_mark[-3],yystack.l_mark[-1])); }
#line 4488 "y.tab.c"
break;
case 274:
#line 1400 "rules.y"
	{ word x=yystack.l_mark[-1],h=hd(yystack.l_mark[0]),t=tl(yystack.l_mark[0]);
            while(h!=NIL)x=cons(cons(hd(h),t),x),h=tl(h);
            yyval = x; }
#line 4495 "y.tab.c"
break;
case 275:
#line 1404 "rules.y"
	{ word x=NIL,h=hd(yystack.l_mark[0]),t=tl(yystack.l_mark[0]);
            while(h!=NIL)x=cons(cons(hd(h),t),x),h=tl(h);
            yyval = x; }
#line 4502 "y.tab.c"
break;
case 276:
#line 1409 "rules.y"
	{inbnf=0;}
#line 4507 "y.tab.c"
break;
case 277:
#line 1410 "rules.y"
	{ yyval = cons(yystack.l_mark[-6],cons(yystack.l_mark[-4],yystack.l_mark[-1])); }
#line 4512 "y.tab.c"
break;
case 278:
#line 1414 "rules.y"
	{ yyval = cons(yystack.l_mark[-2],yystack.l_mark[0]); }
#line 4517 "y.tab.c"
break;
case 279:
#line 1416 "rules.y"
	{ yyval = cons(yystack.l_mark[0],NIL); }
#line 4522 "y.tab.c"
break;
case 280:
#line 1420 "rules.y"
	{ yyval = cons(yystack.l_mark[-1],yystack.l_mark[-3]); }
#line 4527 "y.tab.c"
break;
case 281:
#line 1422 "rules.y"
	{ yyval = cons(yystack.l_mark[-1],NIL); }
#line 4532 "y.tab.c"
break;
case 282:
#line 1426 "rules.y"
	{ syntax("upper case identifier out of context\n"); }
#line 4537 "y.tab.c"
break;
case 283:
#line 1428 "rules.y"
	{ yyval = yystack.l_mark[-1];
            idsused=yystack.l_mark[0];
            while(yystack.l_mark[0]!=NIL)
              yyval = ap(yyval,hd(yystack.l_mark[0])),yystack.l_mark[0] = tl(yystack.l_mark[0]);
          }
#line 4546 "y.tab.c"
break;
case 284:
#line 1434 "rules.y"
	{ if(eqtvar(yystack.l_mark[-2],yystack.l_mark[0]))
              syntax("repeated type variable in typeform\n");
            idsused=cons(yystack.l_mark[-2],cons(yystack.l_mark[0],NIL));
            yyval = ap2(yystack.l_mark[-1],yystack.l_mark[-2],yystack.l_mark[0]); }
#line 4554 "y.tab.c"
break;
case 285:
#line 1439 "rules.y"
	{ syntax("upper case identifier cannot be used as typename\n"); }
#line 4559 "y.tab.c"
break;
case 287:
#line 1444 "rules.y"
	{ yyval = type_t; }
#line 4564 "y.tab.c"
break;
case 288:
#line 1448 "rules.y"
	{ yyval = mktvar(1); }
#line 4569 "y.tab.c"
break;
case 290:
#line 1453 "rules.y"
	{ yyval = NIL; }
#line 4574 "y.tab.c"
break;
case 291:
#line 1455 "rules.y"
	{ if(memb(yystack.l_mark[0],yystack.l_mark[-1]))
              syntax("repeated type variable on lhs of type def\n");
            yyval = cons(yystack.l_mark[-1],yystack.l_mark[0]); }
#line 4581 "y.tab.c"
break;
case 292:
#line 1461 "rules.y"
	{ extern word SGC;  /* keeps track of sui-generis constructors */
            if( tl(yystack.l_mark[0])==NIL && tag[hd(yystack.l_mark[0])]!=ID )
                            /* 2nd conjunct excludes singularity types */
              SGC=cons(head(hd(yystack.l_mark[0])),SGC);
          }
#line 4590 "y.tab.c"
break;
case 293:
#line 1469 "rules.y"
	{ yyval = cons(yystack.l_mark[0],NIL); }
#line 4595 "y.tab.c"
break;
case 294:
#line 1471 "rules.y"
	{ yyval = cons(yystack.l_mark[0],yystack.l_mark[-2]); }
#line 4600 "y.tab.c"
break;
case 295:
#line 1475 "rules.y"
	{ yyval = ap2(yystack.l_mark[-1],yystack.l_mark[-3],yystack.l_mark[0]); 
            id_who(yystack.l_mark[-1])=yystack.l_mark[-2]; }
#line 4606 "y.tab.c"
break;
case 297:
#line 1481 "rules.y"
	{ yyval = yystack.l_mark[-1]; }
#line 4611 "y.tab.c"
break;
case 298:
#line 1483 "rules.y"
	{ yyval = ap(yystack.l_mark[-1],yystack.l_mark[0]); }
#line 4616 "y.tab.c"
break;
case 299:
#line 1485 "rules.y"
	{ yyval = yystack.l_mark[0];
            id_who(yystack.l_mark[0])=yystack.l_mark[-1]; }
#line 4622 "y.tab.c"
break;
case 301:
#line 1491 "rules.y"
	{ yyval = ap(strict_t,yystack.l_mark[-1]); }
#line 4627 "y.tab.c"
break;
case 302:
#line 1495 "rules.y"
	{ yyval = ap(strict_t,yystack.l_mark[-1]); }
#line 4632 "y.tab.c"
break;
case 304:
#line 1500 "rules.y"
	{ yyval = parse_nil(); }
#line 4637 "y.tab.c"
break;
case 305:
#line 1502 "rules.y"
	{ yyval = parse_names_add(yystack.l_mark[-1], yystack.l_mark[0]); }
#line 4642 "y.tab.c"
break;
case 306:
#line 1506 "rules.y"
	{ word h=reverse(hd(yystack.l_mark[0])),hr=hd(tl(yystack.l_mark[0])),t=tl(tl(yystack.l_mark[0]));
            inbnf=1;
            yyval=NIL;
            while(h!=NIL&&!SYNERR)
                 ntspecmap=cons(cons(hd(h),hr),ntspecmap),
                 yyval=add_prod(defn(hd(h),t,UNDEF),yyval,hr),
                 h=tl(h);
          }
#line 4654 "y.tab.c"
break;
case 307:
#line 1515 "rules.y"
	{ yyval = cons(yystack.l_mark[0],NIL); }
#line 4659 "y.tab.c"
break;
case 308:
#line 1517 "rules.y"
	{ word h=reverse(hd(yystack.l_mark[0])),hr=hd(tl(yystack.l_mark[0])),t=tl(tl(yystack.l_mark[0]));
            inbnf=1;
            yyval=yystack.l_mark[-1];
            while(h!=NIL&&!SYNERR)
                 ntspecmap=cons(cons(hd(h),hr),ntspecmap),
                 yyval=add_prod(defn(hd(h),t,UNDEF),yyval,hr),
                 h=tl(h);
          }
#line 4671 "y.tab.c"
break;
case 309:
#line 1526 "rules.y"
	{ yyval = add_prod(yystack.l_mark[0],yystack.l_mark[-1],hd(dval(yystack.l_mark[0]))); }
#line 4676 "y.tab.c"
break;
case 310:
#line 1531 "rules.y"
	{ yyval = defn(yystack.l_mark[-5],undef_t,yystack.l_mark[-1]); }
#line 4681 "y.tab.c"
break;
case 311:
#line 1535 "rules.y"
	{ ihlist=0; }
#line 4686 "y.tab.c"
break;
case 312:
#line 1536 "rules.y"
	{ inbnf=0; }
#line 4691 "y.tab.c"
break;
case 313:
#line 1537 "rules.y"
	{ inbnf=1;
            if(yystack.l_mark[-1]==NIL)syntax("unexpected token ')'\n");
            ihlist=yystack.l_mark[-1]; }
#line 4698 "y.tab.c"
break;
case 314:
#line 1543 "rules.y"
	{ yyval = label(yystack.l_mark[-1],yystack.l_mark[0]); }
#line 4703 "y.tab.c"
break;
case 315:
#line 1547 "rules.y"
	{ yyval = ap2(G_ERROR,G_ZERO,yystack.l_mark[0]); }
#line 4708 "y.tab.c"
break;
case 316:
#line 1549 "rules.y"
	{ yyval=hd(yystack.l_mark[0]), yystack.l_mark[0]=tl(yystack.l_mark[0]);
            while(yystack.l_mark[0]!=NIL)
                 yyval=label(hd(yystack.l_mark[0]),yyval),yystack.l_mark[0]=tl(yystack.l_mark[0]),
                 yyval=ap2(G_ALT,hd(yystack.l_mark[0]),yyval),yystack.l_mark[0]=tl(yystack.l_mark[0]);
        }
#line 4717 "y.tab.c"
break;
case 317:
#line 1555 "rules.y"
	{ yyval=hd(yystack.l_mark[-2]), yystack.l_mark[-2]=tl(yystack.l_mark[-2]);
            while(yystack.l_mark[-2]!=NIL)
                 yyval=label(hd(yystack.l_mark[-2]),yyval),yystack.l_mark[-2]=tl(yystack.l_mark[-2]),
                 yyval=ap2(G_ALT,hd(yystack.l_mark[-2]),yyval),yystack.l_mark[-2]=tl(yystack.l_mark[-2]);
            yyval = ap2(G_ERROR,yyval,yystack.l_mark[0]); }
#line 4726 "y.tab.c"
break;
case 318:
#line 1564 "rules.y"
	{ yyval=cons(yystack.l_mark[0],NIL); }
#line 4731 "y.tab.c"
break;
case 319:
#line 1566 "rules.y"
	{ yyval = cons(yystack.l_mark[0],cons(yystack.l_mark[-1],yystack.l_mark[-3])); }
#line 4736 "y.tab.c"
break;
case 320:
#line 1570 "rules.y"
	{ word n=0,f=yystack.l_mark[0],rule=Void;
                         /* default value of a production is () */
                         /* rule=mkgvar(sreds);  formerly last symbol */
            if(f!=NIL&&hd(f)==G_END)sreds++;
            if(ihlist)rule=ih_abstr(rule);
            while(n<sreds)rule=lambda(mkgvar(++n),rule);
            sreds=0;
            rule=ap(G_RULE,rule);
            while(f!=NIL)rule=ap2(G_SEQ,hd(f),rule),f=tl(f);
            yyval = rule; }
#line 4750 "y.tab.c"
break;
case 321:
#line 1580 "rules.y"
	{inbnf=2;}
#line 4755 "y.tab.c"
break;
case 322:
#line 1581 "rules.y"
	{ if(yystack.l_mark[-6]!=NIL&&hd(yystack.l_mark[-6])==G_END)sreds++;
            if(sreds==1&&can_elide(yystack.l_mark[-1]))
              inbnf=1,sreds=0,yyval=hd(yystack.l_mark[-6]); /* optimisation */
            else
            { word f=yystack.l_mark[-6],rule=label(yystack.l_mark[-2],yystack.l_mark[-1]),n=0;
              inbnf=1;
              if(ihlist)rule=ih_abstr(rule);
              while(n<sreds)rule=lambda(mkgvar(++n),rule);
              sreds=0;
              rule=ap(G_RULE,rule);
              while(f!=NIL)rule=ap2(G_SEQ,hd(f),rule),f=tl(f);
              yyval = rule; }
          }
#line 4772 "y.tab.c"
break;
case 323:
#line 1597 "rules.y"
	{ word rule = ap(K,Void); /* default value of a production is () */
            if(ihlist)rule=ih_abstr(rule);
            yyval = rule; }
#line 4779 "y.tab.c"
break;
case 324:
#line 1600 "rules.y"
	{ inbnf=2,sreds=2; }
#line 4784 "y.tab.c"
break;
case 325:
#line 1601 "rules.y"
	{ word rule = label(yystack.l_mark[-2],yystack.l_mark[-1]);
            if(ihlist)rule=ih_abstr(rule);
            yyval = lambda(pair(mkgvar(1),mkgvar(2)),rule);
            inbnf=1,sreds=0; }
#line 4792 "y.tab.c"
break;
case 326:
#line 1608 "rules.y"
	{ sreds=0; yyval=NIL; }
#line 4797 "y.tab.c"
break;
case 327:
#line 1610 "rules.y"
	{ syntax("unexpected token after empty\n");
            sreds=0; yyval=NIL; }
#line 4803 "y.tab.c"
break;
case 328:
#line 1612 "rules.y"
	{ obrct=0; }
#line 4808 "y.tab.c"
break;
case 329:
#line 1613 "rules.y"
	{ word f=yystack.l_mark[0];
            if(obrct)
              syntax(obrct>0?"unmatched { in grammar rule\n":
                             "unmatched } in grammar rule\n");
            for(sreds=0;f!=NIL;f=tl(f))sreds++;
            if(hd(yystack.l_mark[0])==G_END)sreds--;
            yyval = yystack.l_mark[0]; }
#line 4819 "y.tab.c"
break;
case 330:
#line 1623 "rules.y"
	{ yyval = cons(yystack.l_mark[0],NIL); }
#line 4824 "y.tab.c"
break;
case 331:
#line 1625 "rules.y"
	{ if(hd(yystack.l_mark[-1])==G_END)
               syntax("unexpected token after end\n");
             yyval = cons(yystack.l_mark[0],yystack.l_mark[-1]); }
#line 4831 "y.tab.c"
break;
case 333:
#line 1632 "rules.y"
	{ yyval = ap(outdent_fn,ap2(indent_fn,getcol_fn(),yystack.l_mark[-1])); }
#line 4836 "y.tab.c"
break;
case 334:
#line 1634 "rules.y"
	{ obrct++;
            yyval = ap2(indent_fn,getcol_fn(),yystack.l_mark[0]); }
#line 4842 "y.tab.c"
break;
case 335:
#line 1637 "rules.y"
	{ if(--obrct<0)syntax("unmatched `}' in grammar rule\n");
            yyval = ap(outdent_fn,yystack.l_mark[-1]); }
#line 4848 "y.tab.c"
break;
case 337:
#line 1643 "rules.y"
	{ yyval = ap(G_STAR,yystack.l_mark[-1]); }
#line 4853 "y.tab.c"
break;
case 338:
#line 1645 "rules.y"
	{ yyval = ap2(G_SEQ,yystack.l_mark[-1],ap2(G_SEQ,ap(G_STAR,yystack.l_mark[-1]),ap(G_RULE,ap(C,P)))); }
#line 4858 "y.tab.c"
break;
case 339:
#line 1647 "rules.y"
	{ yyval = ap(G_OPT,yystack.l_mark[-1]); }
#line 4863 "y.tab.c"
break;
case 340:
#line 1651 "rules.y"
	{ extern word NEW;
            nonterminals=newadd1(yystack.l_mark[0],nonterminals);
            if(NEW)ntmap=cons(cons(yystack.l_mark[0],lasth),ntmap); }
#line 4870 "y.tab.c"
break;
case 341:
#line 1655 "rules.y"
	{ yyval = G_END; }
#line 4875 "y.tab.c"
break;
case 342:
#line 1657 "rules.y"
	{ if(!isstring(yystack.l_mark[0]))
              printf("%ssyntax error: illegal terminal ",echoing?"\n":""),
              out(stdout,yystack.l_mark[0]),printf(" (should be string-const)\n"),
              acterror();
            yyval = ap(G_SYMB,yystack.l_mark[0]); }
#line 4884 "y.tab.c"
break;
case 343:
#line 1663 "rules.y"
	{ yyval=G_STATE; }
#line 4889 "y.tab.c"
break;
case 344:
#line 1664 "rules.y"
	{inbnf=0;}
#line 4894 "y.tab.c"
break;
case 345:
#line 1664 "rules.y"
	{inbnf=1;}
#line 4899 "y.tab.c"
break;
case 346:
#line 1665 "rules.y"
	{ yyval = ap(G_SUCHTHAT,yystack.l_mark[-2]); }
#line 4904 "y.tab.c"
break;
case 347:
#line 1667 "rules.y"
	{ yyval = G_ANY; }
#line 4909 "y.tab.c"
break;
#line 4911 "y.tab.c"
    default:
        break;
    }
    yystack.s_mark -= yym;
    yystate = *yystack.s_mark;
    yystack.l_mark -= yym;
#if defined(YYLTYPE) || defined(YYLTYPE_IS_DECLARED)
    yystack.p_mark -= yym;
#endif
    yym = yylhs[yyn];
    if (yystate == 0 && yym == 0)
    {
#if YYDEBUG
        if (yydebug)
        {
            fprintf(stderr, "%s[%d]: after reduction, ", YYDEBUGSTR, yydepth);
#ifdef YYSTYPE_TOSTRING
#if YYBTYACC
            if (!yytrial)
#endif /* YYBTYACC */
                fprintf(stderr, "result is <%s>, ", YYSTYPE_TOSTRING(yystos[YYFINAL], yyval));
#endif
            fprintf(stderr, "shifting from state 0 to final state %d\n", YYFINAL);
        }
#endif
        yystate = YYFINAL;
        *++yystack.s_mark = YYFINAL;
        *++yystack.l_mark = yyval;
#if defined(YYLTYPE) || defined(YYLTYPE_IS_DECLARED)
        *++yystack.p_mark = yyloc;
#endif
        if (yychar < 0)
        {
#if YYBTYACC
            do {
            if (yylvp < yylve)
            {
                /* we're currently re-reading tokens */
                yylval = *yylvp++;
#if defined(YYLTYPE) || defined(YYLTYPE_IS_DECLARED)
                yylloc = *yylpp++;
#endif
                yychar = *yylexp++;
                break;
            }
            if (yyps->save)
            {
                /* in trial mode; save scanner results for future parse attempts */
                if (yylvp == yylvlim)
                {   /* Enlarge lexical value queue */
                    size_t p = (size_t) (yylvp - yylvals);
                    size_t s = (size_t) (yylvlim - yylvals);

                    s += YYLVQUEUEGROWTH;
                    if ((yylexemes = (YYINT *)realloc(yylexemes, s * sizeof(YYINT))) == NULL)
                        goto yyenomem;
                    if ((yylvals   = (YYSTYPE *)realloc(yylvals, s * sizeof(YYSTYPE))) == NULL)
                        goto yyenomem;
#if defined(YYLTYPE) || defined(YYLTYPE_IS_DECLARED)
                    if ((yylpsns   = (YYLTYPE *)realloc(yylpsns, s * sizeof(YYLTYPE))) == NULL)
                        goto yyenomem;
#endif
                    yylvp   = yylve = yylvals + p;
                    yylvlim = yylvals + s;
#if defined(YYLTYPE) || defined(YYLTYPE_IS_DECLARED)
                    yylpp   = yylpe = yylpsns + p;
                    yylplim = yylpsns + s;
#endif
                    yylexp  = yylexemes + p;
                }
                *yylexp = (YYINT) YYLEX;
                *yylvp++ = yylval;
                yylve++;
#if defined(YYLTYPE) || defined(YYLTYPE_IS_DECLARED)
                *yylpp++ = yylloc;
                yylpe++;
#endif
                yychar = *yylexp++;
                break;
            }
            /* normal operation, no conflict encountered */
#endif /* YYBTYACC */
            yychar = YYLEX;
#if YYBTYACC
            } while (0);
#endif /* YYBTYACC */
            if (yychar < 0) yychar = YYEOF;
#if YYDEBUG
            if (yydebug)
            {
                if ((yys = yyname[YYTRANSLATE(yychar)]) == NULL) yys = yyname[YYUNDFTOKEN];
                fprintf(stderr, "%s[%d]: state %d, reading token %d (%s)\n",
                                YYDEBUGSTR, yydepth, YYFINAL, yychar, yys);
            }
#endif
        }
        if (yychar == YYEOF) goto yyaccept;
        goto yyloop;
    }
    if (((yyn = yygindex[yym]) != 0) && (yyn += yystate) >= 0 &&
            yyn <= YYTABLESIZE && yycheck[yyn] == (YYINT) yystate)
        yystate = yytable[yyn];
    else
        yystate = yydgoto[yym];
#if YYDEBUG
    if (yydebug)
    {
        fprintf(stderr, "%s[%d]: after reduction, ", YYDEBUGSTR, yydepth);
#ifdef YYSTYPE_TOSTRING
#if YYBTYACC
        if (!yytrial)
#endif /* YYBTYACC */
            fprintf(stderr, "result is <%s>, ", YYSTYPE_TOSTRING(yystos[yystate], yyval));
#endif
        fprintf(stderr, "shifting from state %d to state %d\n", *yystack.s_mark, yystate);
    }
#endif
    if (yystack.s_mark >= yystack.s_last && yygrowstack(&yystack) == YYENOMEM) goto yyoverflow;
    *++yystack.s_mark = (YYINT) yystate;
    *++yystack.l_mark = yyval;
#if defined(YYLTYPE) || defined(YYLTYPE_IS_DECLARED)
    *++yystack.p_mark = yyloc;
#endif
    goto yyloop;
#if YYBTYACC

    /* Reduction declares that this path is valid. Set yypath and do a full parse */
yyvalid:
    if (yypath) YYABORT;
    while (yyps->save)
    {
        YYParseState *save = yyps->save;
        yyps->save = save->save;
        save->save = yypath;
        yypath = save;
    }
#if YYDEBUG
    if (yydebug)
        fprintf(stderr, "%s[%d]: state %d, CONFLICT trial successful, backtracking to state %d, %d tokens\n",
                        YYDEBUGSTR, yydepth, yystate, yypath->state, (int)(yylvp - yylvals - yypath->lexeme));
#endif
    if (yyerrctx)
    {
        yyFreeState(yyerrctx);
        yyerrctx = NULL;
    }
    yylvp          = yylvals + yypath->lexeme;
#if defined(YYLTYPE) || defined(YYLTYPE_IS_DECLARED)
    yylpp          = yylpsns + yypath->lexeme;
#endif
    yylexp         = yylexemes + yypath->lexeme;
    yychar         = YYEMPTY;
    yystack.s_mark = yystack.s_base + (yypath->yystack.s_mark - yypath->yystack.s_base);
    memcpy (yystack.s_base, yypath->yystack.s_base, (size_t) (yystack.s_mark - yystack.s_base + 1) * sizeof(YYINT));
    yystack.l_mark = yystack.l_base + (yypath->yystack.l_mark - yypath->yystack.l_base);
    memcpy (yystack.l_base, yypath->yystack.l_base, (size_t) (yystack.l_mark - yystack.l_base + 1) * sizeof(YYSTYPE));
#if defined(YYLTYPE) || defined(YYLTYPE_IS_DECLARED)
    yystack.p_mark = yystack.p_base + (yypath->yystack.p_mark - yypath->yystack.p_base);
    memcpy (yystack.p_base, yypath->yystack.p_base, (size_t) (yystack.p_mark - yystack.p_base + 1) * sizeof(YYLTYPE));
#endif
    yystate        = yypath->state;
    goto yyloop;
#endif /* YYBTYACC */

yyoverflow:
    YYERROR_CALL("yacc stack overflow");
#if YYBTYACC
    goto yyabort_nomem;
yyenomem:
    YYERROR_CALL("memory exhausted");
yyabort_nomem:
#endif /* YYBTYACC */
    yyresult = 2;
    goto yyreturn;

yyabort:
    yyresult = 1;
    goto yyreturn;

yyaccept:
#if YYBTYACC
    if (yyps->save) goto yyvalid;
#endif /* YYBTYACC */
    yyresult = 0;

yyreturn:
#if defined(YYDESTRUCT_CALL)
    if (yychar != YYEOF && yychar != YYEMPTY)
#if defined(YYLTYPE) || defined(YYLTYPE_IS_DECLARED)
        YYDESTRUCT_CALL("cleanup: discarding token", yychar, &yylval, &yylloc);
#else
        YYDESTRUCT_CALL("cleanup: discarding token", yychar, &yylval);
#endif /* defined(YYLTYPE) || defined(YYLTYPE_IS_DECLARED) */

    {
        YYSTYPE *pv;
#if defined(YYLTYPE) || defined(YYLTYPE_IS_DECLARED)
        YYLTYPE *pp;

        for (pv = yystack.l_base, pp = yystack.p_base; pv <= yystack.l_mark; ++pv, ++pp)
             YYDESTRUCT_CALL("cleanup: discarding state",
                             yystos[*(yystack.s_base + (pv - yystack.l_base))], pv, pp);
#else
        for (pv = yystack.l_base; pv <= yystack.l_mark; ++pv)
             YYDESTRUCT_CALL("cleanup: discarding state",
                             yystos[*(yystack.s_base + (pv - yystack.l_base))], pv);
#endif /* defined(YYLTYPE) || defined(YYLTYPE_IS_DECLARED) */
    }
#endif /* defined(YYDESTRUCT_CALL) */

#if YYBTYACC
    if (yyerrctx)
    {
        yyFreeState(yyerrctx);
        yyerrctx = NULL;
    }
    while (yyps)
    {
        YYParseState *save = yyps;
        yyps = save->save;
        save->save = NULL;
        yyFreeState(save);
    }
    while (yypath)
    {
        YYParseState *save = yypath;
        yypath = save->save;
        save->save = NULL;
        yyFreeState(save);
    }
#endif /* YYBTYACC */
    yyfreestack(&yystack);
    return (yyresult);
}
