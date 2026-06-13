#include "parser_bridge.h"
#include <stdio.h>
#include <string.h>

extern int yyparse(void);
extern FILE *s_in;
extern word fileq;
extern word insertdepth;
extern int openfile(const char *n);

int mira_parse_file(const char *filename) {
    if (!openfile(filename)) {
        return -1;
    }
    s_in = (FILE *)hd(hd(fileq));
    return yyparse();
}

int mira_parse_string(const char *source) {
    size_t len = strlen(source);
    // fmemopen is POSIX standard (since 2008), available on macOS and Linux.
    FILE *f = fmemopen((void *)source, len, "r");
    if (!f) {
        return -1;
    }
    fileq = cons(make(STRCONS, (word)f, NIL), fileq);
    insertdepth += 1;
    s_in = f;
    return yyparse();
}

int mira_parse_current(void) {
    return yyparse();
}

void mira_lex_setup_string(const char *source) {
    size_t len = strlen(source);
    FILE *f = fmemopen((void *)source, len, "r");
    if (!f) return;
    fileq = cons(make(STRCONS, (word)f, NIL), fileq);
    insertdepth += 1;
    s_in = f;
}

void mira_lex_cleanup(void) {
    if (s_in) {
        fclose(s_in);
        s_in = NULL;
    }
}

extern void mira_report_parser_error(const char *err_s, int yychar_val, word lookahead_c);
extern int yychar;
extern word c;

void yyerror(char *s) {
    mira_report_parser_error(s, yychar, c);
}

extern word yyval;
extern word yylval;
extern word fileq;
extern word idsused;
extern word gvars;
extern word lexvar;
extern word margstack;
extern word vergstack;
extern word litstack;
extern word linostack;
extern word prefixstack;
extern word echostack;
extern word common_stdin;
extern word common_stdinb;
extern word cook_stdin;
extern word files;
extern word exportfiles;
extern void mark(word);

void mira_parser_mark_roots(void) {
    mark(yyval);
    mark(yylval);
    mark(fileq);
    mark(idsused);
    mark(gvars);
    mark(lexvar);
    mark(margstack);
    mark(vergstack);
    mark(litstack);
    mark(linostack);
    mark(prefixstack);
    mark(echostack);
    mark(common_stdin);
    mark(common_stdinb);
    mark(cook_stdin);
    mark(files);
    mark(exportfiles);
}

