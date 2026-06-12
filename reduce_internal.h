#ifndef REDUCE_INTERNAL_H
#define REDUCE_INTERNAL_H

#include <stdbool.h>
#include <string.h>
#include "data.h"

typedef enum {
    ACT_NONE,
    ACT_NEXTREDEX,
    ACT_DONE
} ReduceAction;

typedef struct {
    word e;
    word s;
    word hold;
    word args[4];
    ReduceAction action;
} ReductionCtx;

#define clean_ptr(x) ((x) & ~tlptrbits)
#define abnormal(x) ((x) < 0)
#define fails(x) ((x) == NIL)
#define FAILURE NIL
#define mktlptr(x) ((x) |= tlptrbit)
#define mknormal(x) ((x) &= ~tlptrbits)

static inline void ctx_down_left(ReductionCtx *ctx) {
    ctx->hold = ctx->s;
    ctx->s = ctx->e;
    ctx->e = hd(clean_ptr(ctx->e));
    hd(clean_ptr(ctx->s)) = ctx->hold;
}

static inline void ctx_down_right(ReductionCtx *ctx) {
    ctx->hold = hd(clean_ptr(ctx->s));
    hd(clean_ptr(ctx->s)) = ctx->e;
    ctx->e = tl(clean_ptr(ctx->s));
    tl(clean_ptr(ctx->s)) = ctx->hold;
    ctx->s |= tlptrbit;
}

static inline bool ctx_downright(ReductionCtx *ctx) {
    if (ctx->s < 0) { // abnormal(s)
        return true;
    }
    ctx_down_right(ctx);
    return false;
}

static inline void ctx_up_left(ReductionCtx *ctx) {
    ctx->hold = ctx->s;
    ctx->s = hd(clean_ptr(ctx->s));
    hd(clean_ptr(ctx->hold)) = ctx->e;
    ctx->e = ctx->hold;
}

static inline bool ctx_upleft(ReductionCtx *ctx) {
    if (ctx->s < 0) { // abnormal(s)
        return true;
    }
    ctx_up_left(ctx);
    return false;
}

static inline void ctx_up_right(ReductionCtx *ctx) {
    ctx->s &= ~tlptrbits; // mknormal(s)
    ctx->hold = tl(clean_ptr(ctx->s));
    tl(clean_ptr(ctx->s)) = ctx->e;
    ctx->e = hd(clean_ptr(ctx->s));
    hd(clean_ptr(ctx->s)) = ctx->hold;
}

static inline void ctx_GETARG(ReductionCtx *ctx, word *a) {
    ctx_up_left(ctx);
    *a = tl(clean_ptr(ctx->e));
}

static inline bool ctx_getarg(ReductionCtx *ctx, word *a) {
    if (ctx_upleft(ctx)) {
        return true;
    }
    *a = tl(clean_ptr(ctx->e));
    return false;
}

#undef hd
#undef tl
#define hd(x) hd[clean_ptr(x) * 2]
#define tl(x) tl[clean_ptr(x) * 2]

// Tag Helper Functions
static inline bool is_ap(word x) { return !abnormal(x) && tag[x] == AP; }
static inline bool is_num(word x) { return !abnormal(x) && (tag[x] == INT || tag[x] == DOUBLE); }
static inline bool is_constructor(word x) { return !abnormal(x) && tag[x] == CONSTRUCTOR; }
static inline bool is_int(word x) { return !abnormal(x) && tag[x] == INT; }
static inline bool is_double(word x) { return !abnormal(x) && tag[x] == DOUBLE; }
static inline bool is_atom(word x) { return !abnormal(x) && tag[x] == ATOM; }
static inline bool is_strcons(word x) { return !abnormal(x) && tag[x] == STRCONS; }
static inline bool is_id(word x) { return !abnormal(x) && tag[x] == ID; }
static inline bool is_datapair(word x) { return !abnormal(x) && tag[x] == DATAPAIR; }
static inline bool is_startreadvals(word x) { return !abnormal(x) && tag[x] == STARTREADVALS; }
static inline bool is_cons(word x) { return !abnormal(x) && tag[x] == CONS; }
static inline bool is_unicode(word x) { return !abnormal(x) && tag[x] == UNICODE; }

// Rewrite Helper Functions

static inline void rewrite_to_value(word *expr, word value) {
  hd(*expr) = I;
  *expr = tl(*expr) = value;
}

static inline void rewrite_to_nil(word *expr) {
  rewrite_to_value(expr, NIL);
}

static inline void rewrite_to_fail(word *expr) {
  rewrite_to_value(expr, FAIL);
}

static inline void rewrite_to_failure(word *expr) {
  rewrite_to_value(expr, FAILURE);
}

static inline void rewrite_to_cons_head(word expr, word head_value) {
  tag[expr] = CONS;
  hd(expr) = head_value;
}

static inline void rewrite_to_cons(word expr, word head_value, word tail_value) {
  tag[expr] = CONS;
  hd(expr) = head_value;
  tl(expr) = tail_value;
}

static inline word rewrite_to_existing_tail(word expr) {
  hd(expr) = I;
  return tl(expr);
}

// External Declarations referenced by rewrites
extern int compare(word a_val, word b_val);
extern int bigcmp(word a_val, word b_val);
extern word str_conv(const char *s_val);

// Helper macros from original reduce.c
#define constr_tag(x) hd(x)
#define idconstr_tag(x) hd(id_val(x))
#define constr_name(x) (tag[tl(x)] == ID ? get_id(tl(x)) : get_id(pn_val(tl(x))))
#define suppressed(x) (tag[tl(x)] == STRCONS && tag[pn_val(tl(x))] != ID)
#define isodigit(x) ('0' <= (x) && (x) <= '7')
#define sign(x) (x)

// Global reducer declarations
extern word reduce(word e_val);
extern void force(word x_val);
extern word numplus(word x_val, word y_val);
extern void fn_error(const char *err_str);
extern void int_error(const char *err_str);
extern void math_error(char *err_str);
extern void div_error(void);
extern void mallocfail(char *err_str);
extern void getenv_error(const char *err_str);
extern void subs_error(void);
extern void reduce_badcase_error(word arg_info);
extern void reduce_conf_error(word arg_info);
extern word piperrmess(word pid_val);
extern void out_here(FILE *f_val, word h_val, word nl_val);
extern void outstats(void);
extern void print(word e_val);
extern void output(word e_val);
extern void outf(word e_val);
extern void apfile(word f_val);
extern void closefile(word f_val);
extern void lexfail(word x_val);
extern word lexstate(word x_val);
extern int memclass(int c_val, word x_val);
extern word g_residue(word toks2_val);
extern void reduce_parse_close_error(word arg1_val, word arg3_val);


static inline void rewrite_to_match_result(word *expr, word left, word right, word success_value) {
  hd(*expr) = I;
  *expr = tl(*expr) = (compare(left, right) == 0) ? success_value : FAIL;
}

static inline void rewrite_to_int_match_result(word *expr, word literal, word value, word success_value) {
  hd(*expr) = I;
  *expr = tl(*expr) = (tag[value] != INT || bigcmp(literal, value)) ? FAIL : success_value;
}

static inline void rewrite_to_compare_eq(word *expr, word left, word right) {
  hd(*expr) = I;
  *expr = tl(*expr) = compare(left, right) == 0 ? True : False;
}

static inline void rewrite_to_compare_neq(word *expr, word left, word right) {
  hd(*expr) = I;
  *expr = tl(*expr) = compare(left, right) != 0 ? True : False;
}

static inline void rewrite_to_compare_gt(word *expr, word left, word right) {
  hd(*expr) = I;
  *expr = tl(*expr) = compare(left, right) > 0 ? True : False;
}

static inline void rewrite_to_compare_ge(word *expr, word left, word right) {
  hd(*expr) = I;
  *expr = tl(*expr) = compare(left, right) >= 0 ? True : False;
}

static inline void rewrite_to_string(word *expr, const char *value) {
  hd(*expr) = I;
  *expr = tl(*expr) = str_conv(value);
}

// Function Prototypes for Modular Reducer Files

// Combinators (reduce_combinators.c)
extern void zig_handleI(ReductionCtx *ctx);
extern void zig_handleK(ReductionCtx *ctx);
void handle_S(ReductionCtx *ctx);
void handle_B(ReductionCtx *ctx);
void handle_CB(ReductionCtx *ctx);
void handle_C(ReductionCtx *ctx);
void handle_Y(ReductionCtx *ctx);
void handle_K(ReductionCtx *ctx);
void handle_KI(ReductionCtx *ctx);
void handle_S1(ReductionCtx *ctx);
void handle_B1(ReductionCtx *ctx);
void handle_C1(ReductionCtx *ctx);
void handle_S_p(ReductionCtx *ctx);
void handle_B_p(ReductionCtx *ctx);
void handle_C_p(ReductionCtx *ctx);
void handle_ITERATE(ReductionCtx *ctx);
void handle_ITERATE1(ReductionCtx *ctx);
void handle_P(ReductionCtx *ctx);
void handle_U(ReductionCtx *ctx);
void handle_Uf(ReductionCtx *ctx);
void handle_ATLEAST(ReductionCtx *ctx);
void handle_U_(ReductionCtx *ctx);
void handle_Ug(ReductionCtx *ctx);
void handle_MATCH(ReductionCtx *ctx);
void handle_MATCHINT(ReductionCtx *ctx);
void handle_GENSEQ(ReductionCtx *ctx);
void handle_MAP(ReductionCtx *ctx);
void handle_FLATMAP(ReductionCtx *ctx);
void handle_FILTER(ReductionCtx *ctx);
void handle_LIST_LAST(ReductionCtx *ctx);
void handle_LENGTH(ReductionCtx *ctx);
void handle_DROP(ReductionCtx *ctx);
void handle_SUBSCRIPT(ReductionCtx *ctx);
void handle_FOLDL1(ReductionCtx *ctx);
void handle_FOLDL(ReductionCtx *ctx);
void handle_FOLDR(ReductionCtx *ctx);
void handle_BADCASE(ReductionCtx *ctx);
void handle_GETARGS(ReductionCtx *ctx);
void handle_CONFERROR(ReductionCtx *ctx);
void handle_ERROR(ReductionCtx *ctx);
void handle_WAIT(ReductionCtx *ctx);
void handle_TRY(ReductionCtx *ctx);
void handle_FAIL(ReductionCtx *ctx);
void handle_Ush1(ReductionCtx *ctx);
void handle_MKSTRICT(ReductionCtx *ctx);
void handle_strict_monadic(ReductionCtx *ctx);
void handle_strict_diadic(ReductionCtx *ctx);
void handle_strict_triadic(ReductionCtx *ctx);

// Grammar and Lexer combinators (reduce_lex.c)
void handle_G_ERROR(ReductionCtx *ctx);
void handle_G_ALT(ReductionCtx *ctx);
void handle_G_OPT(ReductionCtx *ctx);
void handle_G_STAR(ReductionCtx *ctx);
void handle_G_FBSTAR(ReductionCtx *ctx);
void handle_G_SYMB(ReductionCtx *ctx);
void handle_G_ANY(ReductionCtx *ctx);
void handle_G_SUCHTHAT(ReductionCtx *ctx);
void handle_G_END(ReductionCtx *ctx);
void handle_G_STATE(ReductionCtx *ctx);
void handle_G_SEQ(ReductionCtx *ctx);
void handle_G_UNIT(ReductionCtx *ctx);
void handle_G_ZERO(ReductionCtx *ctx);
void handle_G_CLOSE(ReductionCtx *ctx);
void handle_G_COUNT(ReductionCtx *ctx);
void handle_LEX_RPT1(ReductionCtx *ctx);
void handle_LEX_RPT(ReductionCtx *ctx);
void handle_LEX_TRY(ReductionCtx *ctx);
void handle_LEX_TRY_(ReductionCtx *ctx);
void handle_LEX_TRY1(ReductionCtx *ctx);
void handle_LEX_TRY1_(ReductionCtx *ctx);
void handle_DESTREV(ReductionCtx *ctx);
void handle_LEX_COUNT0(ReductionCtx *ctx);
void handle_LEX_COUNT(ReductionCtx *ctx);
void handle_LEX_STRING(ReductionCtx *ctx);
void handle_LEX_CLASS(ReductionCtx *ctx);
void handle_LEX_DOT(ReductionCtx *ctx);
void handle_LEX_CHAR(ReductionCtx *ctx);
void handle_LEX_SEQ(ReductionCtx *ctx);
void handle_LEX_OR(ReductionCtx *ctx);
void handle_LEX_RCONTEXT(ReductionCtx *ctx);
void handle_LEX_STAR(ReductionCtx *ctx);
void handle_LEX_OPT(ReductionCtx *ctx);

// IO / Streams (reduce_io.c)
void handle_READ(ReductionCtx *ctx);
void handle_READBIN(ReductionCtx *ctx);
void handle_READVALS(ReductionCtx *ctx);
void handle_STARTREADVALS(ReductionCtx *ctx);

// Ready State (reduce_ready.c)
void handle_ready_state(ReductionCtx *ctx);

#endif /* REDUCE_INTERNAL_H */
