#ifndef MIRANDA_LEX_H
#define MIRANDA_LEX_H

#include "runtime.h"

extern word col;

char *addextn(word /*b*/, char * /*s*/);
void adjust_prefix(char * /*f*/);
word conv_args(void);
void dic_check(void);
void dicovflo(void);
word findid(char * /*n*/);
word getfname(word /*x*/);
int hash(char * /*s*/);
int isconstrname(char * /*s*/);
char *keep(char * /*p*/);
void layout(void);
word make_id(char * /*n*/);
word make_pn(word /*val*/);
word mkgvar(word /*i*/);
word mklexvar(word /*i*/);
void mkprivate(word /*x*/);
word name(void);
int okid(int /*ch*/);
int openfile(char * /*n*/);
char *rdline(void);
void reset_lex(void);
void reset_pns(void);
void reset_state(void);
void setlmargin(void);
void setupdic(void);
word sto_pn(word /*n*/);
word str_conv(const char * /*s*/);
char *token(void);
void unsetlmargin(void);
int yylex(void);

#endif
