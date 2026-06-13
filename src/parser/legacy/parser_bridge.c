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

extern void mira_report_parser_error(const char *err_s, int yychar_val, word lookahead_c);
extern int yychar;
extern word c;

void yyerror(char *s) {
    mira_report_parser_error(s, yychar, c);
}

