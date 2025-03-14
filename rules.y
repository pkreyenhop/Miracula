/* Miranda token declarations and syntax rules for "YACC" */

/**************************************************************************
 * Copyright (C) Research Software Limited 1985-90.  All rights reserved. *
 * The Miranda system is distributed as free software under the terms in  *
 * the file "COPYING" which is included in the distribution.              *
 *------------------------------------------------------------------------*/

/* miranda symbols */

%token VALUE EVAL WHERE IF TO LEFTARROW  COLONCOLON  COLON2EQ
       TYPEVAR  NAME  CNAME  CONST  DOLLAR2  OFFSIDE  ELSEQ
       ABSTYPE WITH DIAG EQEQ FREE INCLUDE  EXPORT  TYPE
       OTHERWISE  SHOWSYM  PATHNAME  BNF  LEX  ENDIR  ERRORSY ENDSY
       EMPTYSY READVALSY

%right ARROW
%right PLUSPLUS ':' MINUSMINUS
%nonassoc DOTDOT
%right VEL
%right '&'
%nonassoc '>' GE '=' NE LE '<'
%left '+' '-'
%left '*'  '/' REM DIV
%right '^'
%left '.'   /* fiddle to make '#' behave */
%left '!'
%right INFIXNAME INFIXCNAME
%token CMBASE  /* placeholder to start combinator values - see combs.h */

%{
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

%}

/* Miranda syntax rules */
/* the associated semantic actions perform the compilation */

%{
#include "data.h"
 /* miscellaneous declarations  */
extern int nill,k_i,Void;
extern int message,standardout;
extern int big_one;
#define isltmess_t(t) (islist_t(t)&&tl[t]==message)
#define isstring_t(t) (islist_t(t)&&tl[t]==char_t)
extern int SYNERR,errs,echoing,gvars;
extern int listdiff_fn,indent_fn;
extern int polyshowerror;
int lastname=0;
int suppressids=NIL;
int idsused=NIL;
int tvarscope=0;
int includees=NIL,embargoes=NIL,exportfiles=NIL,freeids=NIL,exports=NIL;
int inexplist=0;
int inbnf=0,col_fn=0,fnts=NIL,eprodnts=NIL,nonterminals=NIL,sreds=0;
int ntspecmap=NIL,ntmap=NIL,lasth=0;

evaluate(x)
int x;
{ extern int debug;
  int t;
  t=type_of(x);
  if(t==wrong_t)return;
  lastexp=x;
  x=codegen(x);
  if(polyshowerror)return;
  if(process())
                 /* setup new process for each evaluation */
  { extern int dieclean();
    (void)signal(SIGINT,(sighandler)dieclean);
      /* if interrupted will flush output etc before going */
    compiling=0;
    resetgcstats();
    output(isltmess_t(t)?x:
            cons(ap(standardout,isstring_t(t)?x
                           :ap(mkshow(0,0,t),x)),NIL));
    (void)signal(SIGINT,SIG_IGN);/* otherwise could do outstats() twice */
    putchar('\n');
    outstats();
    exit(0); }
}

obey(x) /* like evaluate but no fork, no stats, no extra '\n' */
int x;
{ int t=type_of(x);
  x=codegen(x);
  if(polyshowerror)return;
  compiling=0;
  output(isltmess_t(t)?x:
            cons(ap(standardout,isstring_t(t)?x:ap(mkshow(0,0,t),x)),NIL));
}

isstring(x)
int x;
{ return(x==NILS||tag[x]==CONS&&is_char(hd[x]));
}

compose(x) /* used in compiling 'cases' */
int x;
{ int y=hd[x];
  if(hd[y]==OTHERWISE)y=tl[y]; /* OTHERWISE was just a marker - lose it */
  else y=tag[y]==LABEL?label(hd[y],ap(tl[y],FAIL)):
         ap(y,FAIL); /* if all guards false result is FAIL */
  x = tl[x];
  if(x!=NIL)
    { while(tl[x]!=NIL)y=label(hd[hd[x]],ap(tl[hd[x]],y)), x=tl[x];
      y=ap(hd[x],y);
     /* first alternative has no label - label of enclosing rhs applies */
    }
  return(y);
}

/*
t_result(t)
int t;
{ while(isarrow_t(t))t=tl[t];
  return(head(t));
} /* used in code for collecting law_ts */

%}

%%

entity:  /* the entity to be parsed is either a definition script or an
            expression (the latter appearing as a command line) */

    error|

    script
        = { lastname=0; /* outstats(); */  }|
                        /* statistics not usually wanted after compilation */

/*  MAGIC exp '\n' script
        =  { lastexp=$2; }| /* change to magic scripts 19.11.2013 */

    VALUE exp
        =  { lastexp=$2; }| /* next line of `$+' */

    EVAL exp
        = { if(!SYNERR&&yychar==0)
              { evaluate($2); }
          }|

    EVAL exp COLONCOLON
            /* boring problem - how to make sure no junk chars follow here?
               likewise TO case -- trick used above doesn't work, yychar is
               here always -1 Why? Too fiddly to bother with just now */
          = { int t=type_of($2);
              if(t!=wrong_t)
                { lastexp=$2;
                  if(tag[$2]==ID&&id_type($2)==wrong_t)t=wrong_t;
                  out_type(t);
                  putchar('\n'); }
            }|

    EVAL exp TO
        = { FILE *fil=NULL,*efil;
            extern char *token();
            int t=type_of($2);
            char *f=token(),*ef;
            if(f)keep(f); ef=token(); /* wasteful of dic space, FIX LATER */
            if(f){ fil= fopen(f,$3?"a":"w");
                   if(fil==NULL)
                     printf("cannot open \"%s\" for writing\n",f); }
            else printf("filename missing after \"&>\"\n");
            if(ef)
              { efil= fopen(ef,$3?"a":"w");
                if(efil==NULL)
                  printf("cannot open \"%s\" for writing\n",ef); }
            if(t!=wrong_t)$2=codegen(lastexp=$2);
            if(polyshowerror)return;
            if(t!=wrong_t&&fil!=NULL&&(!ef||efil))
            { int pid;/* launch a concurrent process to perform task */
              sighandler oldsig;
              oldsig=signal(SIGINT,SIG_IGN); /* ignore interrupts */
              if(pid=fork())
                { /* "parent" */
                  if(pid==-1)perror("cannot create process");
                  else printf("process %d\n",pid);
                  fclose(fil);
                  if(ef)fclose(efil);
                  (void)signal(SIGINT,oldsig); }else
              { /* "child" */
                (void)signal(SIGQUIT,SIG_IGN);   /* and quits */
#ifndef SYSTEM5
                (void)signal(SIGTSTP,SIG_IGN);   /* and stops */
#endif
                close(1); dup(fileno(fil));  /* subvert stdout */
                close(2); dup(fileno(ef?efil:fil)); /* subvert stderr */
                /* FUNNY BUG - if redirect stdout stderr to same file by two
                   calls to freopen, their buffers get conflated - whence do
                   by subverting underlying file descriptors, as above
                   (fix due to Martin Guy) */
                /* formerly used dup2, but not present in system V */
                fclose(stdin);
                /* setbuf(stdout,NIL); 
		/* not safe to change buffering of stream already in use */
		/* freopen would have reset the buffering automatically */
                lastexp = NIL;  /* what else should we set to NIL? */
                /*atcount= 1; */
                compiling= 0;
                resetgcstats();
                output(isltmess_t(t)?$2:
                        cons(ap(standardout,isstring_t(t)?$2:
                                       ap(mkshow(0,0,t),$2)),NIL));
                putchar('\n');
                outstats();
                exit(0); } } };

script:
    /* empty */|
    defs;

exp:
    op | /* will later suppress in favour of (op) in arg */
    e1;

op:
    '~'
        =  { $$ = NOT; }|
    '#'
        =  { $$ = LENGTH; }|
    diop;

diop:
    '-'
        =  { $$ = MINUS; }|
    diop1;

diop1:
    '+'
        =  { $$ = PLUS; }|
    PLUSPLUS
        =  { $$ = APPEND; }|
    ':'
        =  { $$ = P; }|
    MINUSMINUS
        =  { $$ = listdiff_fn; }|
    VEL
        =  { $$ = OR; }|
    '&'
        =  { $$ = AND; }|
    relop |
    '*'
        =  { $$ = TIMES; }|
    '/'
        =  { $$ = FDIV; }|
    DIV
        =  { $$ = INTDIV; }|
    REM
        =  { $$ = MOD; }|
    '^'
        =  { $$ = POWER; }|
    '.'
        =  { $$ = B; }|
    '!'
        =  { $$ = ap(C,SUBSCRIPT); }|
    INFIXNAME|
    INFIXCNAME;

relop:
    '>'
        = { $$ = GR; }|
    GE
        = { $$ = GRE; }|
    eqop
        = { $$ = EQ; }|
    NE
        = { $$ = NEQ; }|
    LE
        = { $$ = ap(C,GRE); }|
    '<'
        = { $$ = ap(C,GR); };

eqop:
    EQEQ|  /* silently accept for benefit of Haskell users */
    '=';

rhs:
    cases WHERE ldefs 
        = { $$ = block($3,compose($1),0); }|
    exp WHERE ldefs 
        = { $$ = block($3,$1,0); }|
    exp|
    cases
        =  { $$ = compose($1); };

cases:
    exp ',' if exp
        =  { $$ = cons(ap2(COND,$4,$1),NIL); }|
    exp ',' OTHERWISE
        =  { $$ = cons(ap(OTHERWISE,$1),NIL); }|
    cases reindent ELSEQ alt
        =  { $$ = cons($4,$1); 
             if(hd[hd[$1]]==OTHERWISE)
               syntax("\"otherwise\" must be last case\n"); };

alt:
    here exp
        =  { errs=$1,
             syntax("obsolete syntax, \", otherwise\" missing\n");
             $$ = ap(OTHERWISE,label($1,$2)); }|
    here exp ',' if exp
        =  { $$ = label($1,ap2(COND,$5,$2)); }|
    here exp ',' OTHERWISE
        =  { $$ = ap(OTHERWISE,label($1,$2)); };

if:
    /* empty */
        = { extern int strictif;
            if(strictif)syntax("\"if\" missing\n"); }|
    IF;

indent:
    /* empty */
        = { if(!SYNERR){layout(); setlmargin();}
          };
/* note that because of yacc's one symbol look ahead, indent must usually be
   invoked one symbol earlier than the non-terminal to which it applies 
   - see `production:' for an exception */

outdent:
    separator
        = { unsetlmargin(); };

separator:
    OFFSIDE | ';' ;

reindent:
    /* empty */
        = { if(!SYNERR)
              { unsetlmargin(); layout(); setlmargin(); }
          };
 
liste:  /* NB - returns list in reverse order */
    exp
        = { $$ = cons($1,NIL); }|
    liste ',' exp  /* left recursive so as not to eat YACC stack */
        = { $$ = cons($3,$1); };

e1:
    '~' e1 %prec '='
        = { $$ = ap(NOT,$2); }|
    e1 PLUSPLUS e1
        = { $$ = ap2(APPEND,$1,$3); }|
    e1 ':' e1
        = { $$ = cons($1,$3); }|
    e1 MINUSMINUS e1
        = { $$ = ap2(listdiff_fn,$1,$3);  }|
    e1 VEL e1
        = { $$ = ap2(OR,$1,$3); }|
    e1 '&' e1
        = { $$ = ap2(AND,$1,$3); }|
    reln |
    e2;

es1:                     /* e1 or presection */
    '~' e1 %prec '='
        = { $$ = ap(NOT,$2); }|
    e1 PLUSPLUS e1
        = { $$ = ap2(APPEND,$1,$3); }|
    e1 PLUSPLUS
        = { $$ = ap(APPEND,$1); }|
    e1 ':' e1
        = { $$ = cons($1,$3); }|
    e1 ':'
        = { $$ = ap(P,$1); }|
    e1 MINUSMINUS e1
        = { $$ = ap2(listdiff_fn,$1,$3);  }|
    e1 MINUSMINUS
        = { $$ = ap(listdiff_fn,$1);  }|
    e1 VEL e1
        = { $$ = ap2(OR,$1,$3); }|
    e1 VEL
        = { $$ = ap(OR,$1); }|
    e1 '&' e1
        = { $$ = ap2(AND,$1,$3); }|
    e1 '&'
        = { $$ = ap(AND,$1); }|
    relsn |
    es2;

e2:
    '-' e2 %prec '-'
        = { $$ = ap(NEG,$2); }|
    '#' e2 %prec '.'
        = { $$ = ap(LENGTH,$2);  }|
    e2 '+' e2
        = { $$ = ap2(PLUS,$1,$3); }|
    e2 '-' e2
        = { $$ = ap2(MINUS,$1,$3); }|
    e2 '*' e2
        = { $$ = ap2(TIMES,$1,$3); }|
    e2 '/' e2
        = { $$ = ap2(FDIV,$1,$3); }|
    e2 DIV e2
        = { $$ = ap2(INTDIV,$1,$3); } |
    e2 REM e2
        = { $$ = ap2(MOD,$1,$3); }|
    e2 '^' e2
        = { $$ = ap2(POWER,$1,$3); } |
    e2 '.' e2
        = { $$ = ap2(B,$1,$3);  }|
    e2 '!' e2
        = { $$ = ap2(SUBSCRIPT,$3,$1); }|
    e3;

es2:               /* e2 or presection */
    '-' e2 %prec '-'
        = { $$ = ap(NEG,$2); }|
    '#' e2 %prec '.'
        = { $$ = ap(LENGTH,$2);  }|
    e2 '+' e2
        = { $$ = ap2(PLUS,$1,$3); }|
    e2 '+'
        = { $$ = ap(PLUS,$1); }|
    e2 '-' e2
        = { $$ = ap2(MINUS,$1,$3); }|
    e2 '-'
        = { $$ = ap(MINUS,$1); }|
    e2 '*' e2
        = { $$ = ap2(TIMES,$1,$3); }|
    e2 '*'
        = { $$ = ap(TIMES,$1); }|
    e2 '/' e2
        = { $$ = ap2(FDIV,$1,$3); }|
    e2 '/'
        = { $$ = ap(FDIV,$1); }|
    e2 DIV e2
        = { $$ = ap2(INTDIV,$1,$3); } |
    e2 DIV
        = { $$ = ap(INTDIV,$1); } |
    e2 REM e2
        = { $$ = ap2(MOD,$1,$3); }|
    e2 REM
        = { $$ = ap(MOD,$1); }|
    e2 '^' e2
        = { $$ = ap2(POWER,$1,$3); } |
    e2 '^'
        = { $$ = ap(POWER,$1); } |
    e2 '.' e2
        = { $$ = ap2(B,$1,$3);  }|
    e2 '.'
        = { $$ = ap(B,$1);  }|
    e2 '!' e2
        = { $$ = ap2(SUBSCRIPT,$3,$1); }|
    e2 '!'
        = { $$ = ap2(C,SUBSCRIPT,$1); }|
    es3;

e3:
    comb INFIXNAME e3
        = { $$ = ap2($2,$1,$3); }|
    comb INFIXCNAME e3
        = { $$ = ap2($2,$1,$3); }|
    comb;

es3:                     /* e3 or presection */
    comb INFIXNAME e3
        = { $$ = ap2($2,$1,$3); }|
    comb INFIXNAME
        = { $$ = ap($2,$1); }|
    comb INFIXCNAME e3
        = { $$ = ap2($2,$1,$3); }|
    comb INFIXCNAME
        = { $$ = ap($2,$1); }|
    comb;

comb:
    comb arg
        = { $$ = ap($1,$2); }|
    arg;

reln:
    e2 relop e2
        = { $$ = ap2($2,$1,$3); }|
    reln relop e2
        = { int subject;
            subject = hd[hd[$1]]==AND?tl[tl[$1]]:tl[$1];
            $$ = ap2(AND,$1,ap2($2,subject,$3));
          };  /* EFFICIENCY PROBLEM - subject gets re-evaluated (and
                 retypechecked) - fix later */

relsn:                     /* reln or presection */
    e2 relop e2
        = { $$ = ap2($2,$1,$3); }|
    e2 relop
        = { $$ = ap($2,$1); }|
    reln relop e2
        = { int subject;
            subject = hd[hd[$1]]==AND?tl[tl[$1]]:tl[$1];
            $$ = ap2(AND,$1,ap2($2,subject,$3));
          };  /* EFFICIENCY PROBLEM - subject gets re-evaluated (and
                 retypechecked) - fix later */

arg:
    NAME |
    CNAME |
    CONST |
    READVALSY
        = { $$ = readvals(0,0); }|
    SHOWSYM
        = { $$ = show(0,0); }|
    DOLLAR2
        = { $$ = lastexp;
            if(lastexp==UNDEF)
            syntax("no previous expression to substitute for $$\n"); }|
    '[' ']'
        = { $$ = NIL; }|
    '[' exp ']'
        = { $$ = cons($2,NIL); }|
    '[' exp ',' exp ']'
        = { $$ = cons($2,cons($4,NIL)); }|
    '[' exp ',' exp ',' liste ']'
        = { $$ = cons($2,cons($4,reverse($6))); }|
    '[' exp DOTDOT exp ']'
        = { $$ = ap3(STEPUNTIL,big_one,$4,$2); }|
    '[' exp DOTDOT ']'
        = { $$ = ap2(STEP,big_one,$2); }|
    '[' exp ',' exp DOTDOT exp ']'
        = { $$ = ap3(STEPUNTIL,ap2(MINUS,$4,$2),$6,$2); }|
    '[' exp ',' exp DOTDOT ']'
        = { $$ = ap2(STEP,ap2(MINUS,$4,$2),$2); }|
    '[' exp '|' qualifiers ']'
        = { $$ = SYNERR?NIL:compzf($2,$4,0);  }|
    '[' exp DIAG qualifiers ']'
        = { $$ = SYNERR?NIL:compzf($2,$4,1);  }|
    '(' op ')'     /* RSB */
        = { $$ = $2; }|
    '(' es1 ')'          /* presection or parenthesised e1 */
        = { $$ = $2; }|
    '(' diop1 e1 ')'     /* postsection */
        = { $$ = (tag[$2]==AP&&hd[$2]==C)?ap(tl[$2],$3): /* optimisation */
                 ap2(C,$2,$3); }|
    '(' ')'
        = { $$ = Void; }|  /* the void tuple */
    '(' exp ',' liste ')'
        = { if(tl[$4]==NIL)$$=pair($2,hd[$4]);
            else { $$=pair(hd[tl[$4]],hd[$4]);
                   $4=tl[tl[$4]];
                   while($4!=NIL)$$=tcons(hd[$4],$$),$4=tl[$4];
                   $$ = tcons($2,$$); }
          /* representation of the tuple (a1,...,an) is
             tcons(a1,tcons(a2,...pair(a(n-1),an))) */
          };

qualifiers:
    exp
        = { $$ = cons(cons(GUARD,$1),NIL);  }|
    generator
        = { $$ = cons($1,NIL);  }|
    qualifiers ';' generator
        = { $$ = cons($3,$1);   }|
    qualifiers ';' exp
        = { $$ = cons(cons(GUARD,$3),$1);   };

generator:
    e1 ',' generator
        = { /* fix syntax to disallow patlist on lhs of iterate generator */
            if(hd[$3]==GENERATOR)
              { int e=tl[tl[$3]];
                if(tag[e]==AP&&tag[hd[e]]==AP&&
                    (hd[hd[e]]==ITERATE||hd[hd[e]]==ITERATE1))
                  syntax("ill-formed generator\n"); }
            $$ = cons(REPEAT,cons(genlhs($1),$3)); idsused=NIL;  }|
    generator1;

generator1:
    e1 LEFTARROW exp
        = { $$ = cons(GENERATOR,cons(genlhs($1),$3)); idsused=NIL;  }|
    e1 LEFTARROW exp ',' exp DOTDOT
        = { int p = genlhs($1); idsused=NIL;
            $$ = cons(GENERATOR,
                      cons(p,ap2(irrefutable(p)?ITERATE:ITERATE1,
                                 lambda(p,$5),$3)));
          };

defs:
    def|
    defs def;

def:
    v act2 indent '=' here rhs outdent
        = { int l = $1, r = $6;
            int f = head(l);
            if(tag[f]==ID&&!isconstructor(f)) /* fnform defn */
              while(tag[l]==AP)r=lambda(tl[l],r),l=hd[l];
            r = label($5,r); /* to help locate type errors */
            declare(l,r),lastname=l; }|

    spec
        = { int h=reverse(hd[$1]),hr=hd[tl[$1]],t=tl[tl[$1]];
            while(h!=NIL&&!SYNERR)specify(hd[h],t,hr),h=tl[h];
            $$ = cons(nill,NIL); }|

    ABSTYPE here typeforms indent WITH lspecs outdent
        = { extern int TABSTRS;
            extern char *dicp,*dicq;
            int x=reverse($6),ids=NIL,tids=NIL;
            while(x!=NIL&&!SYNERR)
                 specify(hd[hd[x]],cons(tl[tl[hd[x]]],NIL),hd[tl[hd[x]]]),
                  ids=cons(hd[hd[x]],ids),x=tl[x];
            /* each id in specs has its id_type set to const(t,NIL) as a way
               of flagging that t is an abstract type */
            x=reverse($3);
            while(x!=NIL&&!SYNERR)
               { int shfn;
                 decltype(hd[x],abstract_t,undef_t,$2);
                 tids=cons(head(hd[x]),tids);
                 /* check for presence of showfunction */
                 (void)strcpy(dicp,"show");
                 (void)strcat(dicp,get_id(hd[tids]));
                 dicq = dicp+strlen(dicp)+1;
                 shfn=name();
                 if(member(ids,shfn))
                   t_showfn(hd[tids])=shfn;
                 x=tl[x]; }
            TABSTRS = cons(cons(tids,ids),TABSTRS);
            $$ = cons(nill,NIL); }|

    typeform indent act1 here EQEQ type act2 outdent
        = { int x=redtvars(ap($1,$6));
            decltype(hd[x],synonym_t,tl[x],$4);
            $$ = cons(nill,NIL); }|

    typeform indent act1 here COLON2EQ construction act2 outdent
        = { int rhs = $6, r_ids = $6, n=0;
            while(r_ids!=NIL)r_ids=tl[r_ids],n++;
            while(rhs!=NIL&&!SYNERR)
            {  int h=hd[rhs],t=$1,stricts=NIL,i=0;
               while(tag[h]==AP)
                    { if(tag[tl[h]]==AP&&hd[tl[h]]==strict_t)
                        stricts=cons(i,stricts),tl[h]=tl[tl[h]];
                      t=ap2(arrow_t,tl[h],t),h=hd[h],i++; }
               if(tag[h]==ID)
                 declconstr(h,--n,t);
                 /* warning - type not yet in reduced form */
               else { stricts=NIL;
                      if(echoing)putchar('\n');
                      printf("syntax error: illegal construct \"");
                      out_type(hd[rhs]);
                      printf("\" on right of ::=\n");
                      acterror(); } /* can this still happen? check later */
               if(stricts!=NIL) /* ! operators were present */
                 { int k = id_val(h);
                   while(stricts!=NIL)
                        k=ap2(MKSTRICT,i-hd[stricts],k),
                        stricts=tl[stricts];
                   id_val(h)=k; /* overwrite id_val of original constructor */
                 }
               r_ids=cons(h,r_ids);
               rhs = tl[rhs]; }
            if(!SYNERR)decltype($1,algebraic_t,r_ids,$4);
            $$ = cons(nill,NIL); }|

    indent setexp EXPORT parts outdent
        = { inexplist=0;
            if(exports!=NIL)
              errs=$2,
              syntax("multiple %export statements are illegal\n");
            else { if($4==NIL&&exportfiles==NIL&&embargoes!=NIL)
		     exportfiles=cons(PLUS,NIL);
                   exports=cons($2,$4); } /* cons(hereinfo,identifiers) */
            $$ = cons(nill,NIL); }|

    FREE here '{' specs '}'
        = { if(freeids!=NIL)
              errs=$2,
              syntax("multiple %free statements are illegal\n"); else
            { int x=reverse($4);
              while(x!=NIL&&!SYNERR)
                 { specify(hd[hd[x]],tl[tl[hd[x]]],hd[tl[hd[x]]]);
                   freeids=cons(head(hd[hd[x]]),freeids);
                   if(tl[tl[hd[x]]]==type_t)
                     t_class(hd[freeids])=free_t;
                   else id_val(hd[freeids])=FREE; /* conventional value */
                   x=tl[x]; }
              fil_share(hd[files])=0; /* parameterised scripts unshareable */
              freeids=alfasort(freeids); 
              for(x=freeids;x!=NIL;x=tl[x])
                 hd[x]=cons(hd[x],cons(datapair(get_id(hd[x]),0),
                       id_type(hd[x])));
              /* each element of freeids is of the form
                 cons(id,cons(original_name,type)) */
            }
            $$ = cons(nill,NIL); }|

    INCLUDE bindings modifiers outdent
    /* fiddle - 'indent' done by yylex() on reading fileid */
        = { extern char *dicp;
            extern int CLASHES,BAD_DUMP;
            includees=cons(cons($1,cons($3,$2)),includees);
                   /* $1 contains file+hereinfo */
            $$ = cons(nill,NIL); };

setexp:
    here
        =  { $$=$1;
             inexplist=1; };  /* hack to fix lex analyser */

bindings:
    /* empty */
        = { $$ = NIL; }|
    '{' bindingseq '}'
        = { $$ = $2; };

bindingseq:
    bindingseq binding
        = { $$ = cons($2,$1); }|
    binding
        = { $$ = cons($1,NIL); };

binding:
    NAME indent '=' exp outdent
        =  { $$ = cons($1,$4); }|
    typeform indent act1 EQEQ type act2 outdent
        =  { int x=redtvars(ap($1,$5)); 
             int arity=0,h=hd[x];
             while(tag[h]==AP)arity++,h=hd[h];
             $$ = ap(h,make_typ(arity,0,synonym_t,tl[x]));
           };

modifiers:
    /* empty */
        =  { $$ = NIL; }|
    negmods
        =  { int a,b,c=0;
             for(a=$1;a!=NIL;a=tl[a])
                for(b=tl[a];b!=NIL;b=tl[b])
                   { if(hd[hd[a]]==hd[hd[b]])c=hd[hd[a]];
                     if(tl[hd[a]]==tl[hd[b]])c=tl[hd[a]]; 
                     if(c)break; }
             if(c)printf(
                  "%ssyntax error: conflicting aliases (\"%s\")\n",
                      echoing?"\n":"",
                      get_id(c)),
                  acterror();
           };

negmods:
    negmods negmod
        =  { $$ = cons($2,$1); }|
    negmod
        =  { $$ = cons($1,NIL); };

negmod:
    NAME '/' NAME
        =  { $$ = cons($1,$3); }|
    CNAME '/' CNAME
        =  { $$ = cons($1,$3); }|
    '-' NAME
        =  { $$ = cons(make_pn(UNDEF),$2); }/*|
    '-' CNAME */;  /* no - cannot suppress constructors selectively */

here:
    /* empty */ 
        =  { extern int line_no;
             lasth = $$ = fileinfo(get_fil(current_file),line_no);
             /* (script,line_no) for diagnostics */
           };

act1:
    /* empty */
        = { tvarscope=1; };

act2:
    /* empty */
        = { tvarscope=0; idsused= NIL; };

ldefs:
    ldef
        = { $$ = cons($1,NIL);
            dval($1) = tries(dlhs($1),cons(dval($1),NIL));
            if(!SYNERR&&get_ids(dlhs($1))==NIL)
              errs=hd[hd[tl[dval($1)]]],
              syntax("illegal lhs for local definition\n");
          }|
    ldefs ldef
        = { if(dlhs($2)==dlhs(hd[$1]) /*&&dval(hd[$1])!=UNDEF*/)
              { $$ = $1;
                if(!fallible(hd[tl[dval(hd[$1])]]))
                    errs=hd[dval($2)],
                    printf("%ssyntax error: \
unreachable case in defn of \"%s\"\n",echoing?"\n":"",get_id(dlhs($2))),
                    acterror();
                tl[dval(hd[$1])]=cons(dval($2),tl[dval(hd[$1])]); }
            else if(!SYNERR)
                 { int ns=get_ids(dlhs($2)),hr=hd[dval($2)];
                   if(ns==NIL)
                     errs=hr,
                     syntax("illegal lhs for local definition\n");
                   $$ = cons($2,$1);
                   dval($2)=tries(dlhs($2),cons(dval($2),NIL));
                   while(ns!=NIL&&!SYNERR) /* local nameclash check */
                        { nclashcheck(hd[ns],$1,hr);
                          ns=tl[ns]; }
                        /* potentially quadratic - fix later */
                 }
          };

ldef:
    spec
        = { errs=hd[tl[$1]];
            syntax("`::' encountered in local defs\n");
            $$ = cons(nill,NIL); }|
    typeform here EQEQ
        = { errs=$2;
            syntax("`==' encountered in local defs\n");
            $$ = cons(nill,NIL); }|
    typeform here COLON2EQ
        = { errs=$2;
            syntax("`::=' encountered in local defs\n");
            $$ = cons(nill,NIL); }|
    v act2 indent '=' here rhs outdent
        = { int l = $1, r = $6;
            int f = head(l);
            if(tag[f]==ID&&!isconstructor(f)) /* fnform defn */
              while(tag[l]==AP)r=lambda(tl[l],r),l=hd[l];
            r = label($5,r); /* to help locate type errors */
            $$ = defn(l,undef_t,r); };

vlist:
    v
        = { $$ = cons($1,NIL); }|
    vlist ',' v /* left recursive so as not to eat YACC stack */
        = { $$ = cons($3,$1);  }; /* reverse order, NB */

v:
    v1 |
    v1 ':' v
        = { $$ = cons($1,$3); };

v1:
    v1 '+' CONST  /* n+k pattern */
        = { if(!isnat($3))
              syntax("inappropriate use of \"+\" in pattern\n");
            $$ = ap2(PLUS,$3,$1); }|
    '-' CONST
        = { /* if(tag[$2]==DOUBLE)
              $$ = cons(CONST,sto_dbl(-get_dbl($2))); else */
            if(tag[$2]==INT)
              $$ = cons(CONST,bignegate($2)); else
            syntax("inappropriate use of \"-\" in pattern\n"); }|
    v2 INFIXNAME v1
        = { $$ = ap2($2,$1,$3); }|
    v2 INFIXCNAME v1
        = { $$ = ap2($2,$1,$3); }|
    v2;

v2:
    v3 |
    v2 v3
        = { $$ = ap(hd[$1]==CONST&&tag[tl[$1]]==ID?tl[$1]:$1,$2); };
        /* repeated name apparatus may have wrapped CONST around leading id
           - not wanted */

v3:
    NAME
        = { if(sreds&&member(gvars,$1))syntax("illegal use of $num symbol\n");
              /* cannot use grammar variable in a binding position */
            if(memb(idsused,$1))$$ = cons(CONST,$1);
                            /* picks up repeated names in a template */
            else idsused= cons($1,idsused);   } |
    CNAME |
    CONST
        = { if(tag[$1]==DOUBLE)
	      syntax("use of floating point literal in pattern\n");
	    $$ = cons(CONST,$1); }|
    '[' ']'
        = { $$ = nill; }|
    '[' vlist ']'
        = { int x=$2,y=nill;
            while(x!=NIL)y = cons(hd[x],y), x = tl[x];
            $$ = y; }|
    '(' ')'
        = { $$ = Void; }|
    '(' v ')'
        = { $$ = $2; }|
    '(' v ',' vlist ')'
        = { if(tl[$4]==NIL)$$=pair($2,hd[$4]);
            else { $$=pair(hd[tl[$4]],hd[$4]);
                   $4=tl[tl[$4]];
                   while($4!=NIL)$$=tcons(hd[$4],$$),$4=tl[$4];
                   $$ = tcons($2,$$); }
          /* representation of the tuple (a1,...,an) is
             tcons(a1,tcons(a2,...pair(a(n-1),an))) */
          };

type:
    type1 |
    type ARROW type
        = { $$ = ap2(arrow_t,$1,$3); };

type1:
    type2 INFIXNAME type1
        = { $$ = ap2($2,$1,$3); }|
    type2;

type2:
    /* type2 argtype  /* too permissive - fix later */
        /* = { $$ = ap($1,$2); }| */
    tap|
    argtype;

tap:
    NAME argtype
        = { $$ = ap($1,$2); }|
    tap argtype
        = { $$ = ap($1,$2); };

argtype:
    NAME
        = { $$ = transtypeid($1); }|
           /* necessary while prelude not meta_tchecked (for prelude)*/
    typevar
        = { if(tvarscope&&!memb(idsused,$1))
            printf("%ssyntax error: unbound type variable ",echoing?"\n":""),
                 out_type($1),putchar('\n'),acterror();
            $$ = $1; }|
    '(' typelist ')'
        = { $$ = $2; }|
    '[' type ']'  /* at release one was `typelist' */
        = { $$ = ap(list_t,$2); }|
    '[' type ',' typel ']'
        = { syntax(
             "tuple-type with missing parentheses (obsolete syntax)\n"); };

typelist:
    /* empty */
        = { $$ = void_t; }|  /* voidtype */
    type |
    type ',' typel
        = { int x=$3,y=void_t;
            while(x!=NIL)y = ap2(comma_t,hd[x],y), x = tl[x];
            $$ = ap2(comma_t,$1,y); };

typel:
    type 
        = { $$ = cons($1,NIL); }|
    typel ',' type /* left recursive so as not to eat YACC stack */
        = { $$ = cons($3,$1); };

parts: /* returned in reverse order */
    parts NAME 
        = { $$ = add1($2,$1); }|
    parts '-' NAME
	= { $$ = $1; embargoes=add1($3,embargoes); }|
    parts PATHNAME 
        = { $$ = $1; }| /*the pathnames are placed on exportfiles in yylex*/
    parts '+'
        = { $$ = $1;
            exportfiles=cons(PLUS,exportfiles); }|
    NAME
        = { $$ = add1($1,NIL); }|
    '-' NAME
	= { $$ = NIL; embargoes=add1($2,embargoes); }|
    PATHNAME
        = { $$ = NIL; }|
    '+'
        = { $$ = NIL;
            exportfiles=cons(PLUS,exportfiles); };

specs:  /* returns a list of cons(id,cons(here,type))
           in reverse order of appearance */
    specs spec
        = { int x=$1,h=hd[$2],t=tl[$2];
            while(h!=NIL)x=cons(cons(hd[h],t),x),h=tl[h];
            $$ = x; }|
    spec
        = { int x=NIL,h=hd[$1],t=tl[$1];
            while(h!=NIL)x=cons(cons(hd[h],t),x),h=tl[h];
            $$ = x; };

spec:
    typeforms indent here COLONCOLON ttype outdent
        = { $$ = cons($1,cons($3,$5)); };
            /* hack: `typeforms' includes `namelist' */

lspecs:  /* returns a list of cons(id,cons(here,type))
           in reverse order of appearance */
    lspecs lspec
        = { int x=$1,h=hd[$2],t=tl[$2];
            while(h!=NIL)x=cons(cons(hd[h],t),x),h=tl[h];
            $$ = x; }|
    lspec
        = { int x=NIL,h=hd[$1],t=tl[$1];
            while(h!=NIL)x=cons(cons(hd[h],t),x),h=tl[h];
            $$ = x; };

lspec:
    namelist indent here {inbnf=0;} COLONCOLON type outdent
        = { $$ = cons($1,cons($3,$6)); };

namelist:
    NAME ',' namelist
        = { $$ = cons($1,$3); }|
    NAME
        = { $$ = cons($1,NIL); };

typeforms:
    typeforms ',' typeform act2 
        = { $$ = cons($3,$1); }|
    typeform act2
        = { $$ = cons($1,NIL); };
            
typeform:
    CNAME typevars
        = { syntax("upper case identifier out of context\n"); }|
    NAME typevars   /* warning if typevar is repeated */
        = { $$ = $1;
            idsused=$2;
            while($2!=NIL)
              $$ = ap($$,hd[$2]),$2 = tl[$2];
          }|
    typevar INFIXNAME typevar
        = { if(eqtvar($1,$3))
              syntax("repeated type variable in typeform\n");
            idsused=cons($1,cons($3,NIL));
            $$ = ap2($2,$1,$3); }|
    typevar INFIXCNAME typevar
        = { syntax("upper case identifier cannot be used as typename\n"); };

ttype:
    type|
    TYPE
        =  { $$ = type_t; };

typevar:
    '*'
        = { $$ = mktvar(1); }|
    TYPEVAR;

typevars:
    /* empty */
        = { $$ = NIL; }|
    typevar typevars
        = { if(memb($2,$1))
              syntax("repeated type variable on lhs of type def\n");
            $$ = cons($1,$2); };

construction:
    constructs
        = { extern int SGC;  /* keeps track of sui-generis constructors */
            if( tl[$1]==NIL && tag[hd[$1]]!=ID )
                            /* 2nd conjunct excludes singularity types */
              SGC=cons(head(hd[$1]),SGC);
          };

constructs:
    construct
        = { $$ = cons($1,NIL); }|
    constructs '|' construct
        = { $$ = cons($3,$1); };

construct:
    field here INFIXCNAME field
        = { $$ = ap2($3,$1,$4); 
            id_who($3)=$2; }|
    construct1;

construct1:
    '(' construct ')'
        = { $$ = $2; }|
    construct1 field1
        = { $$ = ap($1,$2); }|
    here CNAME
        = { $$ = $2;
            id_who($2)=$1; };

field:
    type|
    argtype '!'
        = { $$ = ap(strict_t,$1); };

field1:
    argtype '!'
        = { $$ = ap(strict_t,$1); }|
    argtype;

%%
/*  end of MIRANDA RULES  */

