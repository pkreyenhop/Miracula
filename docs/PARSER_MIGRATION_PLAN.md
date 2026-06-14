# MIRANDA PARSER MIGRATION PLAN

## YACC/Bison → Idiomatic Zig

---

# Objective

Replace the remaining legacy yacc/bison parser infrastructure with a clean, maintainable, testable Zig implementation while preserving full Miranda language compatibility and existing runtime behaviour.

---

# 1. Mission

The current parser consists of:

* `rules.y`
* `y.tab.c`
* `y.tab.h`
* parser bridge code
* yacc global state
* lexer/parser coupling inherited from C

The parser currently functions but remains the largest piece of legacy architecture in the project.

The goal is **not** to translate yacc-generated code into Zig.

The goal is to:

1. Understand the Miranda grammar.
2. Define a formal AST.
3. Implement a native Zig parser.
4. Lower the AST to Miranda heap values (codegen).
5. Remove yacc dependencies.
6. Make the parser easy to understand and maintain.

---

# 2. Non-Goals

The agent must **NOT**:

* Translate `y.tab.c` line-by-line.
* Recreate yacc internals.
* Preserve yacc global variables.
* Preserve parser bridge abstractions.
* Preserve parser stack implementation details.
* Introduce parser generators.

The final system must be a normal Zig parser.

---

# 3. Overall Migration Strategy

The migration must occur in phases.

Do **NOT** attempt a big-bang rewrite.

The existing yacc parser remains the reference implementation until completion.

---

# Phase 1 – Grammar Recovery ✔ DONE

## Goal

Extract and document the actual Miranda grammar.

## Status

Grammar fully analyzed from `rules.y` (1 670 lines) and `y.tab.c`
(5 144 lines).  Operator precedence table and token vocabulary are
captured in `src/parser/token_filter.zig` and the Pratt binding-power
table in `src/parser/pratt.zig`.

## Operator precedence (from `rules.y` `%right`/`%left` declarations)

| Operator(s) | Associativity | Binding power |
|-------------|---------------|---------------|
| `\/` (vel)  | right | 20 |
| `&`         | right | 30 |
| `= ~= < > <= >=` | left | 40 |
| `: ++ --`   | right | 50 |
| `+ -`       | left  | 60 |
| `* / div mod` | left | 70 |
| `^`         | right | 79 |
| `.` (compose) | left | 80 |
| `!` (subscript) | left | 90 |
| application (juxtaposition) | left | 100 (tightest) |

---

# Phase 2 – AST Design ✔ DONE

## Goal

Create a clean parser target.

## Status

`src/parser/ast.zig` (153 lines) defines all AST node types.
Parser output is pure AST — no runtime objects, no reduction-machine
structures, no parser globals.

## Key types

```zig
// src/parser/ast.zig
pub const TypeExpr = union(enum) {
    type_var, type_name, arrow, type_app, tuple, list, void_t,
};
pub const Expr = union(enum) {
    name, cname, literal, application, infix, neg, length,
    list_nil, list, tuple, typed, where, cond,
};
pub const Pat = union(enum) {
    wildcard, name, cname, literal, cons_pat, list, tuple, application,
};
pub const Def   = struct { lhs: Expr, rhs: Rhs, where_defs: []Def, span: Span };
pub const Script = struct { items: []TopLevel };
```

All nodes carry source spans.  No runtime objects.  No C interop.

---

# Phase 3 – Token Stream Layer ✔ DONE

## Goal

Create a clean parser input abstraction.

## Status

`src/parser/token_filter.zig` (106 lines) defines `TokenId`, `Token`,
and `Span`.  `src/parser/pratt.zig` provides the `TokenStream` struct
with `peek`, `peekAt`, `advance`, `expect`, `check`, and `eat`.

## Token naming invariant

The Miranda `:` list-cons operator is `TokenId.cons` — **not** `.colon`
— to distinguish it unambiguously from `::` (`.coloncolon`) and `::=`
(`.colon2eq`).  This name is load-bearing: the Pratt binding-power table
and all pattern-parsing code rely on it.

## TokenId vocabulary

```zig
// src/parser/token_filter.zig
pub const TokenId = enum {
    // identifiers & literals
    name, cname, typevar, const_int, const_float, const_str, const_char,
    infixname, infixcname, dollars, pathname,
    // keywords
    kw_where, kw_if, kw_otherwise, kw_abstype, kw_with, kw_type,
    kw_free, kw_include, kw_export, kw_bnf, kw_lex, kw_readvals, kw_show,
    kw_div, kw_mod,
    // single-char tokens
    plus, minus, star, slash, caret, dot, bang, tilde, hash,
    eq, lt, gt, amp, pipe, lparen, rparen, lbracket, rbracket,
    lbrace, rbrace, comma, semicolon, question,
    cons,            // `:` — list cons
    // multi-char tokens
    arrow, plus_plus, minus_minus, dot_dot, vel, ge, ne, le,
    left_arrow, coloncolon, colon2eq, eq_eq,
    // layout tokens injected by the filter pass
    offside, elseq,
    eof, error_tok,
};
```

---

# Phase 4 – Expression Parser ✔ DONE

## Goal

Implement native Zig expression parsing.

## Status

`src/parser/pratt.zig` (427 lines) implements a Pratt parser.  The
binding-power table matches the operator precedence documented in Phase 1.
`cloneExpr` is implemented for shared-expression contexts.

Supports: literals, variables, application (juxtaposition at bp 100),
all infix operators, unary negation (`~`), list-length (`#`), list
literals, tuple literals, `where` clauses, conditional guards, and
type-annotated expressions (`expr :: type`).

---

# Phase 5 – Declaration Parser ✔ DONE (core)

## Goal

Parse top-level declarations.

## Status

`src/parser/parser.zig` (537 lines) implements the recursive-descent
parser.  Core declaration forms are complete:

```miranda
double x = x * 2

map f [] = []
map f (x:xs) = f x : map f xs

fib 0 = 0
fib 1 = 1
fib n = fib (n-1) + fib (n-2), if n > 1
```

Guarded equations, multiple clauses, and `where` blocks are supported.
Type synonyms (`type Pair * * == (* , *)`) and algebraic type declarations
(`Colour ::= Red | Green | Blue`) are parsed.

---

# Phase 6 – Pattern Parser ✔ DONE

## Goal

Parse Miranda patterns.

## Status

Included in `src/parser/parser.zig`.  Supports:

```miranda
[]                  -- list_nil
(x:xs)              -- cons_pat
Just x              -- constructor application
(a, b)              -- tuple
_                   -- wildcard
```

---

# Phase 7 – Module Parser ✔ DONE (core)

## Goal

Parse entire source files.

## Status

`parser.zig` parses a full `Script` (sequence of `TopLevel` items):
definitions, type specifications, type declarations, `%include`, and
`%export`.

## Remaining gaps (resolved in Phase 9)

* List comprehensions `[ e | x <- xs, pred ]`
* Sections: `(+ 1)`, `(1 +)`, `(+)`
* `abstype T * with { type-specs }` — the `with` block is not yet parsed
* `%free { module M }` directive
* `%bnf` / `%lex` sections (low priority — stub parse-and-discard)

---

# Phase 8 – Lexer Bridge

## Goal

Produce a real `[]Token` slice from Miranda source so the new parser has
a genuine input stream instead of hand-built test fixtures.

## Approach A — wrap the existing C lexer (recommended, do first)

`lex.zig` already contains the full tokenisation logic: layout injection,
literal parsing (bigints, floats, characters, strings), the offside /
ELSEQ indentation rule, and string interning via `sto_id()`.  Reuse it:

1. Create `src/parser/lex_bridge.zig`.
2. `@cImport("y.tab.h")` for C token-ID constants.
3. Call `yylex()` in a loop; map each C token ID to a `TokenId`.
4. Read `line_no` / `col` globals (exported by `lex.zig`) after each call
   to populate `Token.span`.
5. For `NAME` / `CNAME` tokens cast `yylval` through `get_id()` (same
   pattern as `parse_actions.zig:28`) to recover the interned `[]const u8`.
6. Collect into `std.ArrayList(Token)` (Zig 0.16 unmanaged API:
   `.empty`, `append(gpa, item)`, `toOwnedSlice(gpa)`) and return.

**Token-ID mapping table**

| `y.tab.h` constant | `TokenId` |
|-------------------|-----------|
| `NAME` | `.name` |
| `CNAME` | `.cname` |
| `TYPEVAR` | `.typevar` |
| `CONST` (int) | `.const_int` |
| `CONST` (float) | `.const_float` |
| `CONST` (string) | `.const_str` |
| `CONST` (char) | `.const_char` |
| `INFIXNAME` | `.infixname` |
| `INFIXCNAME` | `.infixcname` |
| `DOLLARS` | `.dollars` |
| `WHERE` | `.kw_where` |
| `IF` | `.kw_if` |
| `OTHERWISE` | `.kw_otherwise` |
| `ABSTYPE` | `.kw_abstype` |
| `WITH` | `.kw_with` |
| `TYPEKEY` | `.kw_type` |
| `FREE` | `.kw_free` |
| `INCLUDE` | `.kw_include` |
| `EXPORT` | `.kw_export` |
| `BNF` | `.kw_bnf` |
| `LEX` | `.kw_lex` |
| `READVALSY` | `.kw_readvals` |
| `SHOW` | `.kw_show` |
| `DIV` | `.kw_div` |
| `MOD` | `.kw_mod` |
| `OFFSIDE` | `.offside` |
| `ELSEQ` | `.elseq` |
| `':'` (ASCII 58) | `.cons` |
| `COLONCOLON` | `.coloncolon` |
| `COLON2EQ` | `.colon2eq` |
| `ARROW` | `.arrow` |
| `PLUSPLUS` | `.plus_plus` |
| `MINUSMINUS` | `.minus_minus` |
| `DOTDOT` | `.dot_dot` |
| `VEL` | `.vel` |
| `GE` | `.ge` |
| `NE` | `.ne` |
| `LE` | `.le` |
| `LEFTARROW` | `.left_arrow` |
| `EQEQ` | `.eq_eq` |
| `0` (EOF / `yylex` returns 0) | `.eof` |
| single-char ASCII (`+`, `-`, …) | matching `.plus`, `.minus`, … |

## Approach B — pure-Zig tokeniser (deferred)

Extract the character-by-character logic from `lex.zig` into a new
`src/parser/tokenizer.zig` that takes `[]const u8` and emits `[]Token`
without touching the Miranda heap.  This removes the last `@cImport` from
the parser subsystem but requires porting the layout/offside logic and all
literal-parsing routines.  Defer to a later clean-up pass; Approach A
unblocks Phase 9 immediately.

## Deliverables

* `src/parser/lex_bridge.zig` — `pub fn tokenize(gpa, path: []const u8) ![]Token`
* Unit tests: tokenize several `.m` snippets and assert token sequences.
* Update `parser.zig` test block to use `tokenize()` instead of hand-built slices.

---

# Phase 9 – Grammar Completeness

## Goal

Fill the grammar gaps identified in Phase 7.

## 9.1 — List comprehensions

```miranda
[ e | x <- xs, y <- ys, pred ]
```

Add `Expr.listcomp` to `ast.zig`:

```zig
listcomp: struct { body: *Expr, qualifiers: []Qualifier },
// Qualifier = generator { pat, src } | guard { cond }
```

## 9.2 — Sections

```miranda
(+ 1)    -- right section: \x -> x + 1
(1 +)    -- left section:  \x -> 1 + x
(+)      -- operator as function
```

Add `Expr.section` or encode as `Expr.infix` with a synthesised
placeholder operand — match what `rules.y` lines ~440–520 produce.

## 9.3 — `abstype … with`

```miranda
abstype stack * with
    push  :: * -> stack * -> stack *
    empty :: stack *
```

`TypeDecl.abstype` exists in `ast.zig`; add a `specs: []TypeSpec` field
and parse the `with` block.

## 9.4 — Module directives

```miranda
%include "foo.m"
%export foo bar
%free { module MyMod }
```

`kw_include`, `kw_export`, and `kw_free` are already in `TokenId`.
`TopLevel.include` and `TopLevel.export_list` exist in `ast.zig`.  Wire
up the parser rules that consume `%free`.

## 9.5 — Layout tokens (OFFSIDE / ELSEQ)

With Approach A from Phase 8, the C lexer injects `.offside` and `.elseq`
automatically; the parser already handles them in `parseWhere` and
definition blocks.  With Approach B a layout algorithm must be implemented
before these tokens appear.

## 9.6 — `%bnf` / `%lex` sections

Low priority.  Parse and discard.  Validate that `miralib/*.m` files do
not use `%bnf` in critical paths before removing the stub.

---

# Phase 10 – Codegen (AST → Miranda heap)

## Goal

Walk `ast.Script` and produce the same `Word` heap values that the legacy
`parse_actions.zig` + YACC grammar currently emit.

This phase has **no analogue in the original plan** — the original assumed
"parser output = AST only."  That is correct for the parser itself, but the
Miranda evaluator expects `Word` heap graphs.  A codegen pass is required
to bridge the two worlds before the legacy pipeline can be removed.

## Architecture

```
ast.Script
  → codegen.zig (imports data.h, uses make/ap/cons/label)
  → Word heap graph (identical to legacy parse_actions.zig output)
```

The codegen `@cImport`s `data.h` and uses the same primitives as
`parse_actions.zig`.  It is the **only** file in the new pipeline that
touches the C runtime.

## Mapping guide

```
Expr.name / .cname        → sto_id(text)
Expr.literal .int         → bigscan(decimal_text)
Expr.literal .float       → sto_dbl(val)
Expr.literal .char        → sto_char(codepoint)
Expr.literal .string      → scan_string(text)  (builds STRCONS chain)
Expr.application          → make(AP, codegen(func), codegen(arg))
Expr.infix { op, l, r }   → ap2(codegen_op(op), codegen(l), codegen(r))
Expr.neg                  → ap(NEG, codegen(inner))
Expr.length               → ap(LENGTH, codegen(inner))
Expr.list_nil             → NIL
Expr.list { elems }       → fold right: cons(codegen(e), acc) from NIL
Expr.tuple (2-tuple)      → ap(ap(PAIR, codegen(a)), codegen(b))
Expr.typed                → codegen(expr)   -- type annotations erased
Expr.where { body, defs } → block(codegen_defs(defs), codegen(body), 0)
Expr.cond { guard, expr } → ap2(COND, codegen(guard), codegen(expr))
```

Use `parse_actions.zig` as the reference for every operator mapping
(`parse_or`, `parse_and`, `parse_compose`, `parse_rhs_cases_where`, etc.).

**Critical invariant**: the codegen must produce structurally identical heap
graphs to the YACC actions — not just semantically equivalent — because the
Miranda evaluator and GC assume specific tag/arity combinations.

## Deliverables

* `src/parser/codegen.zig` — `pub fn codegenScript(script: ast.Script) Word`
* Golden tests: parse a known `.m` snippet with the new pipeline, call
  `codegenScript`, compare the heap graph to the one produced by the legacy
  `mira_parse_string()` → `yyparse()` path.

---

# Phase 11 – Error Recovery

## Goal

Replace yacc error handling.

## Create

```zig
pub const ParseError = struct {
    message: []const u8,
    span: Span,
};
```

Support:

```text
unexpected token
missing ')'
missing '='
invalid pattern
```

Parser must:

* continue after recoverable errors
* report multiple errors
* preserve the `yyerror()` → `mira_report_parser_error()` error reporting
  contract for the REPL's interactive use case

---

# Phase 12 – Differential Validation

## Goal

Ensure behaviour matches the existing parser.

## Create

```text
tests/parser_compatibility/
```

Run both parsers against:

```text
miralib/prelude
miralib/stdenv
tests/*
stress.m
```

## Compare

AST shape for the new parser vs. heap graph for the legacy parser
(via golden tests from Phase 10).

After codegen is added: compare heap graphs directly.

---

# Phase 13 – Integration and Cutover

## Goal

Wire the new pipeline into `main.zig` and remove the legacy parser.

## 13.1 — Add parser module to the mira executable

In `build.zig`:

```zig
const parser_mod = b.createModule(.{
    .root_source_file = b.path("src/parser/parser.zig"),
    .target = target,
    .optimize = optimize,
    .link_libc = true,
});
parser_mod.addIncludePath(b.path("."));
parser_mod.addIncludePath(b.path("src/parser/legacy"));
mira.root_module.addImport("parser", parser_mod);
```

## 13.2 — Build flag for parallel testing

Add a compile-time flag so the new parser can be tested in production
builds while the legacy fallback remains:

```zig
const use_zig_parser = b.option(bool, "zig-parser",
    "Use the new Zig parser") orelse false;
```

When the flag is set, `main.zig` calls:
```zig
const tok    = try lex_bridge.tokenize(gpa, path);
const script = try Parser.init(gpa, tok).parseScript();
const val    = try codegen.codegenScript(script);
```

Otherwise it calls `mira_parse_file()` → `yyparse()` as before.

## 13.3 — Integration gate

Run `zig build test -Dzig-parser=true` against the full `mira-tests`
suite.  Fix all failures before proceeding to cutover.

## 13.4 — Cutover: remove legacy files

Only after `mira-tests` passes 100% with `-Dzig-parser=true`:

Remove from `build.zig`:
```text
src/parser/legacy/y.tab.c      (c_sources)
src/parser/legacy/parser_bridge.c  (c_sources)
addIncludePath("src/parser/legacy")  (no longer needed)
-Dzig-parser flag  (new parser becomes unconditional)
```

Delete:
```text
src/parser/legacy/rules.y
src/parser/legacy/y.tab.c
src/parser/legacy/y.tab.h
src/parser/legacy/parser_bridge.c
src/parser/legacy/parser_bridge.h
src/parser/parse_actions.zig   (replaced by codegen.zig)
```

If Phase 8B (pure-Zig lexer) was completed, also remove `lex.zig` and the
`lex_bridge.zig` `@cImport`.

---

# Risk Register

| Risk | Likelihood | Mitigation |
|------|-----------|------------|
| Layout/OFFSIDE mismatch: new pipeline injects OFFSIDE at wrong column | High | Use Phase 8A bridge; the C lexer handles layout. Add golden tests for indented `where` blocks before enabling in `main.zig`. |
| Codegen graph mismatch: evaluator crashes on subtly wrong AP/CONS structures | High | Phase 10 golden tests compare heap graphs byte-for-byte before enabling new parser. |
| Error recovery: REPL enters bad state after syntax error | Medium | Preserve `yyerror()` → `mira_report_parser_error()` path as fallback until Phase 11 is complete. |
| `$$` (DOLLARS / lastexp) not threaded through new parser context | Medium | `TokenId.dollars` already exists; add a `last_expr: ?Word` field to the codegen context. |
| Missing grammar constructs discovered during integration | Medium | Run `mira-tests` with `-Dzig-parser=true` early, after Phase 10, before cutover. |
| `%bnf` / `%lex` sections in prelude files break bootstrap | Low | Stub parse-and-discard; verify `miralib/*.m` do not use `%bnf` in critical paths. |

---

# Acceptance Criteria

The migration is complete when all of the following are true:

- [ ] `zig build test` passes with zero failures
- [ ] `zig build test -Dzig-parser=true` passes the full `mira-tests` suite
- [ ] `src/parser/legacy/` directory is deleted from the repository
- [ ] `build.zig` contains no `c_sources` entries for parser files
- [ ] `build.zig` contains no `-Dzig-parser` flag (new parser is unconditional)
- [ ] `src/parser/parse_actions.zig` is deleted
- [ ] CI passes on both `aarch64-macos` and `x86_64-linux`

---

# Final Directory Structure

```text
src/
└── parser/
    ├── token_filter.zig      -- TokenId, Token, Span
    ├── lex_bridge.zig        -- tokenize(): wraps yylex() or pure-Zig lexer
    ├── ast.zig               -- all AST node types
    ├── pratt.zig             -- Pratt expression parser, TokenStream
    ├── parser.zig            -- recursive-descent top-level parser
    └── codegen.zig           -- AST → Miranda Word heap values
```

---

# Quality Standards

Every public function must be self-documenting through clear naming.  Add a
comment only when the **why** is non-obvious (hidden constraint, invariant,
workaround for a specific bug).

Every parser component must include:

```zig
test "..." { ... }
```

The parser must:

* use no globals
* use no hidden state
* use no macros
* use no generated code
* use no C interop (except `lex_bridge.zig` during Phase 8A and
  `codegen.zig` which is the single boundary to the C runtime)
* compile cleanly with Zig 0.16
* be understandable by a developer who has never seen yacc

---

# Success Criterion

A new contributor should be able to start at `parser.zig`, follow the code
through a handful of files, and fully understand how Miranda source becomes
an AST — and how that AST becomes Miranda heap values — without needing any
knowledge of yacc, parser generators, or the original C implementation.

The resulting parser represents a modern, idiomatic Zig frontend
architecture suitable for future compiler evolution, optimisation, and
eventual self-hosting efforts.
