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
#define constr_name(x) (is_id(tl(x)) ? get_id(tl(x)) : get_id(pn_val(tl(x))))
#define suppressed(x) (is_strcons(tl(x)) && !is_id(pn_val(tl(x))))
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
extern void zig_handleS(ReductionCtx *ctx);
extern void zig_handleB(ReductionCtx *ctx);
extern void zig_handleCB(ReductionCtx *ctx);
extern void zig_handleC(ReductionCtx *ctx);
extern void zig_handleY(ReductionCtx *ctx);
extern void zig_handleKI(ReductionCtx *ctx);
extern void zig_handleS1(ReductionCtx *ctx);
extern void zig_handleB1(ReductionCtx *ctx);
extern void zig_handleC1(ReductionCtx *ctx);
extern void zig_handleS_p(ReductionCtx *ctx);
extern void zig_handleB_p(ReductionCtx *ctx);
extern void zig_handleC_p(ReductionCtx *ctx);
extern void zig_handleITERATE(ReductionCtx *ctx);
extern void zig_handleITERATE1(ReductionCtx *ctx);
extern void zig_handleP(ReductionCtx *ctx);
extern void zig_handleU(ReductionCtx *ctx);
extern void zig_handleUf(ReductionCtx *ctx);
extern void zig_handleATLEAST(ReductionCtx *ctx);
extern void zig_handleU_(ReductionCtx *ctx);
extern void zig_handleUg(ReductionCtx *ctx);
extern void zig_handleMATCH(ReductionCtx *ctx);
extern void zig_handleMATCHINT(ReductionCtx *ctx);
extern void zig_handleGENSEQ(ReductionCtx *ctx);
extern void zig_handleMAP(ReductionCtx *ctx);
extern void zig_handleFLATMAP(ReductionCtx *ctx);
extern void zig_handleFILTER(ReductionCtx *ctx);
extern void zig_handleLIST_LAST(ReductionCtx *ctx);
extern void zig_handleLENGTH(ReductionCtx *ctx);
extern void zig_handleDROP(ReductionCtx *ctx);
extern void zig_handleSUBSCRIPT(ReductionCtx *ctx);
extern void zig_handleFOLDL1(ReductionCtx *ctx);
extern void zig_handleFOLDL(ReductionCtx *ctx);
extern void zig_handleFOLDR(ReductionCtx *ctx);
extern void zig_handleBADCASE(ReductionCtx *ctx);
extern void zig_handleGETARGS(ReductionCtx *ctx);
extern void zig_handleCONFERROR(ReductionCtx *ctx);
extern void zig_handleERROR(ReductionCtx *ctx);
extern void zig_handleWAIT(ReductionCtx *ctx);
extern void zig_handleTRY(ReductionCtx *ctx);
extern void zig_handleFAIL(ReductionCtx *ctx);
extern void zig_handleUsh1(ReductionCtx *ctx);
extern void zig_handleMKSTRICT(ReductionCtx *ctx);
extern void zig_handle_strict_monadic(ReductionCtx *ctx);
extern void zig_handle_strict_diadic(ReductionCtx *ctx);
extern void zig_handle_strict_triadic(ReductionCtx *ctx);

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
