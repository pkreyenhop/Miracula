#ifndef PARSER_BRIDGE_H
#define PARSER_BRIDGE_H

#include "data.h"

/**
 * ============================================================================
 *                         Miranda Parser Subsystem ABI
 * ============================================================================
 * This header defines the formal interface between the yacc/bison parser 
 * front-end and the Zig runtime. Only functions declared here should cross
 * the C/Zig boundary for parsing operations.
 */

/* ----------------------------------------------------------------------------
 * 1. Execution Control
 * ---------------------------------------------------------------------------- */

/**
 * Parses a script file by filename.
 * Pushes the file handle to the internal stack (fileq) and executes yyparse().
 * Returns 0 on success, or a non-zero status on error.
 */
int mira_parse_file(const char *filename);

/**
 * Parses a script string.
 * Opens an in-memory buffer, pushes it to fileq, and executes yyparse().
 * Returns 0 on success, or a non-zero status on error.
 */
int mira_parse_string(const char *source);

/**
 * Directly calls yyparse() on the currently active stream.
 * Returns 0 on success, or a non-zero status on error.
 */
int mira_parse_current(void);


/* ----------------------------------------------------------------------------
 * 2. Semantic Actions (AST & Runtime construction)
 * ---------------------------------------------------------------------------- */

/* Basic List & AST cell allocation shims */
word parse_nil(void);
word parse_cons(word lhs, word rhs);
word parse_cons_pre(word lhs);
word parse_comb_arg(word lhs, word rhs);

/* Operator applications */
word parse_append(word lhs, word rhs);
word parse_append_pre(word lhs);
word parse_listdiff(word lhs, word rhs);
word parse_listdiff_pre(word lhs);
word parse_or(word lhs, word rhs);
word parse_or_pre(word lhs);
word parse_and(word lhs, word rhs);
word parse_and_pre(word lhs);
word parse_neg(word rhs);
word parse_length(word rhs);
word parse_plus(word lhs, word rhs);
word parse_plus_pre(word lhs);
word parse_minus(word lhs, word rhs);
word parse_minus_pre(word lhs);
word parse_times(word lhs, word rhs);
word parse_times_pre(word lhs);
word parse_fdiv(word lhs, word rhs);
word parse_fdiv_pre(word lhs);
word parse_intdiv(word lhs, word rhs);
word parse_intdiv_pre(word lhs);
word parse_mod(word lhs, word rhs);
word parse_mod_pre(word lhs);
word parse_power(word lhs, word rhs);
word parse_power_pre(word lhs);
word parse_b(word lhs, word rhs);
word parse_b_pre(word lhs);
word parse_subscript(word lhs, word rhs);
word parse_subscript_pre(word lhs);

/* Generic infix operator application */
word parse_infix(word op, word lhs, word rhs);
word parse_infix_pre(word op, word lhs);

/* Conditional guard blocks & cases composition */
word parse_rhs_cases_where(word cases_val, word ldefs_val);
word parse_rhs_exp_where(word exp_val, word ldefs_val);
word parse_rhs_cases(word cases_val);
word parse_case_first(word exp_val, word cond_val);
word parse_case_otherwise_first(word exp_val);
word parse_case_add(word cases_val, word alt_val);
word parse_alt_obsolete(word here_val, word exp_val);
word parse_alt_cond(word here_val, word exp_val, word cond_val);
word parse_alt_otherwise(word here_val, word exp_val);

/* Lists construction */
word parse_liste_first(word exp_val);
word parse_liste_next(word liste_val, word exp_val);

/* Symbol table & Name list management */
word parse_names_add(word names_val, word name_val);

#endif // PARSER_BRIDGE_H
