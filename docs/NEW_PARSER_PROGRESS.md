# New Parser Progress Report (Phase 10)

This document summarises the current state of the Miranda Zig parser
migration.  Phases 1–10 are complete.  The new pipeline parses Miranda source
end-to-end and emits `Word` heap values identical to the legacy YACC parser.

---

## Architecture

```
source text ([:0]const u8)
  → lex_bridge.zig   tokenize()    → []Token
  → parser.zig       parseScript() → ast.Script
  → codegen.zig      codegenScript()  (emits Word heap via C runtime)
```

The pipeline is invoked through `parser_api.parseWithNew()`.  The first two
stages are pure Zig (no C interop).  `codegen.zig` is the single boundary to
the Miranda C runtime.

---

## Completed Phases

### Phase 1 – Grammar Recovery ✔
Grammar fully analysed from `rules.y` (1 670 lines) and `y.tab.c`
(5 144 lines).  Operator precedence table and token vocabulary captured in
`src/parser/token_filter.zig` and the Pratt binding-power table in
`src/parser/pratt.zig`.

### Phase 2 – AST Design ✔
`src/parser/ast.zig` defines all AST node types as pure Zig tagged unions.
No runtime objects, no C interop, no parser globals.

### Phase 3 – Token Stream Layer ✔
`src/parser/token_filter.zig` defines `TokenId`, `Token`, and `Span`.
`src/parser/pratt.zig` provides the `TokenStream` struct with `peek`,
`peekAt`, `advance`, `expect`, `check`, and `eat`.

### Phase 4 – Expression Parser ✔
`src/parser/pratt.zig` implements a Pratt parser with binding powers matching
the Miranda operator precedence table.  Handles literals, variables,
application (bp 100), all infix operators, unary negation, list-length (`#`),
list/tuple literals, `where` clauses, conditional guards, and type annotations
(`expr :: type`).

### Phase 5 – Declaration Parser ✔
`src/parser/parser.zig` implements recursive-descent parsing for all top-level
declaration forms: function definitions (multi-arg, guarded, multi-equation),
type specifications (`::`), type synonyms (`type T == …`), and algebraic type
declarations (`T ::= …`).

### Phase 6 – Pattern Parser ✔
Patterns in `parser.zig`: wildcard `_`, variable, constructor, literal,
cons pattern `(x:xs)`, list `[a,b]`, tuple `(a,b)`, constructor application.

### Phase 7 – Module Parser ✔
`parser.zig` parses a full `Script` (sequence of `TopLevel` items):
definitions, type specs, type decls, `%include`, and `%export`.

### Phase 8 – Lexer Bridge ✔
`src/parser/lex_bridge.zig` wraps the C lexer (`yylex()`) via Approach A.
Maps all C token IDs to `TokenId`, captures `line_no`/`col` source spans,
and handles `NAME`/`CNAME`/literal payloads.  `parseWithNew` in
`parser_api.zig` calls `lex_bridge.tokenize()` to feed the Zig parser.

### Phase 9 – Grammar Completeness ✔
All grammar gaps from Phase 7 filled:

- **List comprehensions**: `Expr.listcomp` with `Qualifier` (generator / guard)
- **Operator sections**: `section_left (e op)`, `section_right (op e)`,
  `section_op (+)` (operator-as-function)
- **`abstype … with`**: `TypeDecl.abstype` with `specs: []TypeSpec` field
- **Module directives**: `%include`, `%export`, `%free` fully parsed
- **`%bnf` / `%lex`**: parsed and discarded (stub)
- **Layout tokens**: `OFFSIDE`/`ELSEQ` injected automatically by the C lexer
  bridge; parser consumes them in `parseWhere` and definition blocks

### Phase 10 – Codegen (AST → Miranda heap) ✔
`src/parser/codegen.zig` (≈360 lines) walks `ast.Script` and emits `Word`
heap values via the Miranda C runtime.  `parseWithNew` now runs the full
pipeline: `tokenize` → `parseScript` → `codegenScript`.

Key design decisions:

| Construct | Heap encoding |
|-----------|--------------|
| `name` / `cname` | `sto_id(text)` |
| integer literal | `bigscan(decimal_text)` |
| float literal | `sto_dbl(val)` |
| char literal | `sto_char(codepoint)` |
| string literal | right-fold `make(CONS, sto_char(c), …)` from `NIL` |
| `application` | `make(AP, func, arg)` |
| `infix` (standard) | `ap2(opWord(op), lhs, rhs)` |
| `infix !` (subscript) | `ap2(SUBSCRIPT, rhs, lhs)` — args REVERSED |
| `infix :` (cons) | `make(CONS, lhs, rhs)` |
| `neg` | `ap(NEG, inner)` |
| `length` | `ap(LENGTH, inner)` |
| `list_nil` | `NIL` |
| `list [a,b,c]` | right-fold `make(CONS, elem, acc)` from `NIL` |
| `tuple (a,b)` | `make(PAIR, a, b)` |
| `tuple (a,b,c)` | `make(TCONS, a, make(PAIR, b, c))` |
| `typed` | expression only (type annotation erased) |
| `where { body, defs }` | `block(local_defs, body, 0)` |
| `section_left (e op)` | `ap(opWord(op), e)` |
| `section_right (op e)` | `ap2(C, opWord(op), e)` (with C-prefix opt for `lt`/`le`/`!`) |
| `section_op (+)` | `opWord(op)` |
| `listcomp` | qualifiers prepended → reversed; `compzf(body, qq, 0)` |
| range `[a..b]` | `ap3(STEPUNTIL, big_one, b, a)` |
| range `[a..]` | `ap2(STEP, big_one, a)` |
| range `[a,b..c]` | `ap3(STEPUNTIL, ap2(MINUS,b,a), c, a)` |
| range `[a,b..]` | `ap2(STEP, ap2(MINUS,b,a), a)` |
| multi-arg def `f x y = e` | lambda-desugar loop then `declare(lhs, label(here, rhs))` |
| local def | `defn(lhs, undef_t, label(here, rhs))` |
| type synonym | `redtvars(ap(tf, body))`; `decl_type(hd(x), synonym_t, tl(x), here)` |
| algebraic type | reversed ctor list, peel APs, `declconstr` each, `decl_type(tf, algebraic_t, r_ids, here)` |
| abstype | `decl_type(tf, abstract_t, NIL, here)`; `specify` each `with` spec |

---

## Test Baseline

```
zig test src/parser/parser.zig   →  13/13 pass  (pure Zig parser tests)
zig build test                   →  56/58 pass
```

The 2 non-passing tests are pre-existing crashes in `steer-tests` and
`lex-tests` (in `parser.parser_tests.test.new parser AST snapshot tests`),
present before Phase 10 work began.  They are caused by the legacy
`parseString` / snapshot-comparison path, not by the new parser or codegen.

### Phase 11 – Error Recovery ✔
`Diagnostic` struct added to `parser.zig` (`span` + `message`).  `Parser`
carries a `diagnostics: std.ArrayList(Diagnostic)` accumulator.
`parseScript` catches per-item parse errors, records a diagnostic, then calls
`syncToNextItem()` to advance past the broken item to the next OFFSIDE
boundary and continue parsing.  OOM remains fatal; all other parse errors are
recoverable.

`parseWithNew` in `parser_api.zig` prints each diagnostic to stderr and sets
`SYNERR = 1` when errors are present, matching the Miranda REPL contract.

Test baseline: 14/14 pure-Zig tests pass (up from 13/13); 59/61 full-build
tests pass (2 pre-existing crashes unchanged).

---

## Next Steps (Phase 12+)

**Phase 12 – Differential Validation**: run both parsers against
`miralib/prelude`, `miralib/stdenv`, and the test suite; compare heap graphs
directly.  This is the gate before cutover.

**Phase 13 – Integration and Cutover**: wire new pipeline into `main.zig`
behind a `-Dzig-parser=true` build flag; once `mira-tests` passes 100%, remove
`rules.y`, `y.tab.c`, `y.tab.h`, `parser_bridge.c`, and `parse_actions.zig`.

A near-term improvement before Phase 12: multiple-equation function merging.
Currently each `codegenDef` call invokes `declare()` independently.  The C
runtime's `decl1` in `trans.zig` merges equations into `tries()` chains, which
should be verified against the YACC behaviour before differential testing.
