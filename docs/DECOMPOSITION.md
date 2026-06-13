# Reduce Function Decomposition Plan

This document describes how to decompose `reduce.c`'s `reduce()` function
without changing behaviour. The goal is to expose the evaluator's logical
phases and create small helper boundaries that can be introduced one at a time
with the existing test suite and warning checks.

## Current Shape

`reduce()` is a graph-reduction interpreter. It combines several concerns in
one large routine:

- spine traversal to find the expression head;
- graph rewrites for non-strict combinators;
- strict-argument scheduling using the `s` stack and tail-pointer markers;
- immediate primitive evaluation once strict arguments are ready;
- grammar parser combinators;
- lexer combinators;
- file, process, stdin, numeric, and error primitives;
- final unwinding and return from subtasks.

The control flow depends heavily on the existing macros (`DOWNLEFT`,
`DOWNRIGHT`, `UPLEFT`, `UPRIGHT`, `getarg`, `lastarg`, `setcell`, `simpl`) and
on local variables (`e`, `s`, `hold`, `arg1`, `arg2`, `arg3`). Any decomposition
should preserve those mechanics first, then gradually reduce macro scope.

## Logical Phases

1. **Reduction Setup**

   Sets up the reduction stack, debug counters, tracing, and local scratch
   variables.

   Candidate helper later:

   ```c
   static void trace_reduce_start(word e);
   ```

2. **Spine Descent**

   Walks left through application nodes until the head of the expression is
   reached. This phase also emits histogram/debug head information.

   Candidate helpers:

   ```c
   static word descend_to_head(word *e, word *s, word *hold);
   static void trace_reduce_head(word e);
   ```

   The first helper is risky because it mutates both `e` and `s` through macros.
   It should be introduced only after the stack/navigation macros are converted
   into inline functions or explicitly parameterised macros.

3. **Non-Strict Core Combinator Rewrites**

   Handles graph rewrites that do not first schedule strict evaluation:
   `S`, `B`, `CB`, `C`, `Y`, `K`, `KI`, `S1`, `B1`, `C1`, pair/list-producing
   combinators, iterate, uncurry, matching, sequence generation, and list
   combinators such as `MAP`, `FILTER`, `FOLDL`, `FOLDR`, `DROP`, and
   `SUBSCRIPT`.

   Candidate helpers:

   ```c
   static int reduce_core_combinator(struct reduce_ctx *ctx);
   static int reduce_list_combinator(struct reduce_ctx *ctx);
   static int reduce_match_combinator(struct reduce_ctx *ctx);
   ```

   These helpers should return a small action enum such as `REDUCE_NEXT`,
   `REDUCE_DONE`, or `REDUCE_NOT_HANDLED`, rather than using direct `goto`
   across helper boundaries.

4. **Input and Stream Primitives**

   Handles `READ`, `READBIN`, `READVALS`, `STARTREAD`, `STARTREADBIN`,
   `STARTREADVALS`, stdin-use conflict handling, file opening, EOF conversion,
   and stream-backed lazy list construction.

   Candidate helpers:

   ```c
   static int reduce_stream_constructor(struct reduce_ctx *ctx);
   static int reduce_ready_stream_start(struct reduce_ctx *ctx);
   static word read_next_text_char(FILE *stream);
   static word read_next_binary_char(FILE *stream);
   ```

   This is a good early extraction target after a context struct exists because
   these cases have clearer boundaries and already delegate errors to existing
   helper functions.

5. **Grammar Parser Combinators**

   Handles `G_ERROR`, `G_ALT`, `G_OPT`, `G_STAR`, `G_FBSTAR`, `G_SYMB`,
   `G_ANY`, `G_SUCHTHAT`, `G_END`, `G_STATE`, `G_SEQ`, `G_UNIT`, `G_ZERO`,
   `G_CLOSE`, and `G_COUNT`.

   Candidate helpers:

   ```c
   static int reduce_grammar_combinator(struct reduce_ctx *ctx);
   static void grammar_parse_error(word message, word counted_tokens);
   ```

   This group is cohesive and mostly independent from arithmetic and IO. It
   should be separable once helper return actions replace direct `goto DONE`.

6. **Lexer Combinators**

   Handles `LEX_RPT`, `LEX_RPT1`, `LEX_TRY`, `LEX_TRY1`, `DESTREV`,
   `LEX_COUNT`, `LEX_STRING`, `LEX_CLASS`, `LEX_DOT`, `LEX_CHAR`, `LEX_SEQ`,
   `LEX_OR`, `LEX_RCONTEXT`, `LEX_STAR`, and `LEX_OPT`.

   Candidate helpers:

   ```c
   static int reduce_lexer_combinator(struct reduce_ctx *ctx);
   static int reduce_lex_try(struct reduce_ctx *ctx, int include_state);
   static int reduce_lex_matcher(struct reduce_ctx *ctx);
   ```

   The duplicate shape of `LEX_TRY` and `LEX_TRY1` is a strong candidate for
   shared helper extraction after the initial mechanical split.

7. **Strict Argument Scheduling**

   Handles the first switch cases that do not evaluate directly, but instead
   move into strict-argument subtasks: monadic primitives (`I`, `SEQ`, `HD`,
   `TL`, etc.), strict diadic primitives (`ZIP`, `EQ`, arithmetic, `MERGE`),
   and strict three-argument primitives (`Ush`, `STEPUNTIL`).

   Candidate helpers:

   ```c
   static int schedule_strict_monadic(struct reduce_ctx *ctx, word op);
   static int schedule_strict_diadic(struct reduce_ctx *ctx, word op);
   static int schedule_strict_triadic(struct reduce_ctx *ctx, word op);
   ```

   This phase should be split before the ready switch, because it defines the
   invariant consumed by the ready phase: strict arguments are reduced right to
   left, then the operator is revisited as `READY(op)`.

8. **Subtask Completion and Ready Dispatch**

   The `DONE` block either returns the final HNF or unwinds one strict subtask.
   If the operator still has application shape, it schedules the next strict
   argument; otherwise the ready switch executes the primitive.

   Candidate helpers:

   ```c
   static enum reduce_action finish_subtask(struct reduce_ctx *ctx);
   static int reduce_ready_operator(struct reduce_ctx *ctx);
   ```

   This is the central seam of the current evaluator. Extracting it should wait
   until a context struct makes `e`, `s`, and scratch variables explicit.

9. **Ready Monadic Primitives**

   Handles ready forms of `I`, `SEQ`, `FORCE`, selectors, `TAKE`, file metadata,
   environment lookup, `EXEC`, `NUMVAL`, reads, `TRY`, conditionals, booleans,
   numeric predicates/conversions, display conversion, and math functions.

   Candidate helpers:

   ```c
   static int reduce_ready_control(struct reduce_ctx *ctx);
   static int reduce_ready_selector(struct reduce_ctx *ctx);
   static int reduce_ready_system(struct reduce_ctx *ctx);
   static int reduce_ready_numeric_unary(struct reduce_ctx *ctx);
   static int reduce_ready_show(struct reduce_ctx *ctx);
   ```

10. **Ready Diadic and Triadic Primitives**

    Handles `ZIP`, comparisons, arithmetic, `SHOWSCALED`, `SHOWFLOAT`, `STEP`,
    `MERGE`, `STEPUNTIL`, and strict constructor display via `Ush`.

    Candidate helpers:

    ```c
    static int reduce_ready_comparison(struct reduce_ctx *ctx);
    static int reduce_ready_arithmetic_binary(struct reduce_ctx *ctx);
    static int reduce_ready_sequence(struct reduce_ctx *ctx);
    static int reduce_ready_constructor_show(struct reduce_ctx *ctx);
    ```

11. **Non-Combinator Head Handling**

    Handles unresolved private names, data-pair undefined-name traps, identifiers,
    constructors, atoms, numbers, unicode, doubles, cons cells, and invalid tags.

    Candidate helper:

    ```c
    static int reduce_non_combinator_head(struct reduce_ctx *ctx);
    ```

## Proposed Staging

1. **Introduce a reducer context struct without moving logic**

   Define a local-only struct in `reduce.c`:

   ```c
   struct reduce_ctx {
     word e;
     word s;
     word hold;
     word arg1;
     word arg2;
     word arg3;
   };
   ```

   Initially keep existing locals and add no functional changes. The first
   behaviour-neutral step is to document which macros read or write which
   fields.

2. **Wrap repeated terminal rewrites**

   Add tiny helpers for repeated patterns that do not change control flow:

   ```c
   static void rewrite_to_value(word *e, word value);
   static void rewrite_to_nil(word *e);
   static void rewrite_to_fail(word *e);
   static void rewrite_to_cons_head(word e, word hd_value);
   static word rewrite_to_existing_tail(word e);
   static void rewrite_to_cons(word e, word hd_value, word tl_value);
   static void rewrite_to_match_result(word *e, word left, word right, word success_value);
   static void rewrite_to_compare_eq(word *e, word left, word right);
   static void rewrite_to_string(word *e, const char *value);
   ```

   These helpers can replace repeated `hd(e) = I; e = tl(e) = ...` and
   `setcell(CONS, ...)` patterns before splitting switch sections.

   Status: started. `reduce.c` now has `rewrite_to_value()`,
   `rewrite_to_nil()`, `rewrite_to_fail()`, and `rewrite_to_failure()` for
   already-computed values and constants. They are intentionally not used where
   the replacement expression allocates cells, to avoid changing GC-visible
   evaluation order. A second pass applied these helpers to list combinator
   and stream EOF rewrites where the replacement was already available or a
   constant. A third pass extended the same pattern through selected grammar,
   lexer, and ready selector paths. A fourth pass covered additional ready
   control, predicate, zip, and constructor-display rewrites whose replacement
   values were constants or had already been computed. A fifth pass covered
   more core, grammar, lexer, environment, numeric, and merge rewrites without
   moving any allocation or comparison calls across graph mutation. A sixth
   pass added `rewrite_to_cons_head()` for terminal `CONS` rewrites that
   intentionally preserve the existing tail pointer. A seventh pass added
   `rewrite_to_existing_tail()` for identity rewrites that continue through
   the current node's existing tail rather than replacing `tl(e)`. An eighth
   pass added `rewrite_to_cons()` for `CONS` rewrites whose head and tail
   values were already computed locals or constants. A ninth pass added
   comparison-specific rewrite helpers that preserve the old mutation order:
   the expression head is rewritten to `I` before `compare()` or `bigcmp()`
   can recursively reduce graph nodes. A tenth pass added `rewrite_to_string()`
   for string conversion rewrites that must set the expression head before
   calling `str_conv()`.

3. **Extract error-only helpers first**

   Error/reporting code has fewer dependencies on reducer navigation. Good
   candidates:

   ```c
   static void reduce_badcase_error(word info);
   static void reduce_conf_error(word info);
   static void reduce_missing_case_error(word subject, word here);
   static void reduce_parse_close_error(word message, word counted_tokens);
   ```

4. **Extract stream primitives**

   Move `READ`, `READBIN`, `READVALS`, and ready `STARTREAD*` handling into
   helpers once terminal rewrite helpers exist. Preserve stdin-use side effects
   exactly.

5. **Extract grammar combinators**

   Grammar combinators are a coherent block and can return explicit actions.
   This extraction should leave `G_RULE`/`P` sharing untouched until after the
   block is moved.

6. **Extract lexer combinators**

   Move the lexer block after grammar extraction. Then fold the duplicate
   `LEX_TRY`/`LEX_TRY1` loops into a shared helper that takes an
   `include_state` flag.

7. **Split ready dispatch**

   Extract ready monadic primitives first, then diadic/triadic primitives.
   This should happen after the `DONE` unwind mechanics are represented by a
   context struct and action enum.

8. **Split core combinator rewrites last**

   The early combinator cases are tightly coupled to stack navigation macros
   and jump labels such as `L_K`, `L_KI`, `L_I`, `L_READ`, and `L_READBIN`.
   Extract them after helper actions can express `NEXTREDEX`, `DONE`, and
   "jump to specialised label" behaviours.

## Helper Boundary Rules

- Preserve in-place graph mutation order exactly.
- Do not move calls marked with `/* ### */` across assignments or local-variable
  lifetimes; those comments indicate places where garbage collection may run.
- Do not hide side effects on globals such as `stdinuse`, `waiting`, `s_out`,
  `errno`, `cycles`, `errtrap`, `linebuf`, or stream handles.
- Avoid helpers that allocate cells unless every live local they rely on is
  protected exactly as before.
- Prefer action-returning helpers over helper-internal `goto`.
- Keep generated/parser and lexer combinator semantics separate from ordinary
  list combinators.

## Suggested Action Enum

When extraction begins, use a small enum instead of cross-function gotos:

```c
enum reduce_action {
  REDUCE_NOT_HANDLED,
  REDUCE_NEXT,
  REDUCE_DONE,
  REDUCE_RETURN
};
```

Helpers can return `REDUCE_NOT_HANDLED` when the opcode belongs to another
phase. The main reducer remains responsible for jumping to `NEXTREDEX`, `DONE`,
or returning the final value until the state machine is fully explicit.

## Verification Plan

Each extraction step should run:

- `make check`
- `make warning-audit`
- the temporary handwritten declaration probe:

```sh
make CFLAGS="-std=c23 -D_POSIX_C_SOURCE=200809L -Wall -Wextra -Wpedantic -Wmissing-variable-declarations -Wmissing-prototypes" mira tools
```

For larger phase extractions, add targeted Miranda smoke inputs that exercise:

- list combinators (`map`, `filter`, `foldl`, `foldr`, indexing);
- arithmetic and numeric display;
- `read`, `readb`, and `readvals`;
- grammar and lexer combinator paths;
- undefined-name and pattern-match error reporting;
- command-line stats and process execution paths where practical.
