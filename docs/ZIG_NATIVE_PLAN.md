# Miracula — Zig-Native Plan

> **Goal:** make the repository read as a well-composed, well-architected *native Zig
> program* — one that could have been written by someone who never saw the C Miranda
> source — while preserving Miranda semantics exactly.
>
> **Created:** 2026-07-05. This plan **supersedes and replaces** the retired plan
> documents (`IDIOMATIC_ZIG_PLAN`, `IDIOMATIC_ARCHITECTURE_PLAN`, `READABILITY_PLAN`,
> `REDESIGN_DATA_MODEL`, `REMAINING_WORK_PLAN`, `SHARED_STATE_PLAN`,
> `TESTABILITY_PLAN` — all deleted; see git history). Where an old document declared
> something "permanent" or "not worth doing" (the signal `longjmp` floor, the
> `*Interp` threading deferral, the `SYNERR` sentinel survey), this plan deliberately
> re-opens it: those conclusions were local optima of an incremental cleanup, not
> properties of a good architecture.

---

## 1. North star — definition of done

The test for every decision: **could this file have been written by someone who never
saw `mira` in C?** Concretely, the project is done when all of the following hold and
are enforced by the scorecard (Phase 0):

- [ ] No `setjmp`/`longjmp`/`jmp_buf` anywhere.
- [ ] `extern fn` and `[*:0]` / `c_int` / `c_long` exist **only** in one small `os.zig`.
- [ ] Exactly **one** module-level mutable global: an atomic interrupt flag. A unit
      test constructs **two `Interp` instances in one process and runs both** — the
      test is the proof, not a comment.
- [ ] All fallible paths return error unions; diagnostics are structured values with
      spans, not printed side effects plus a `SYNERR` flag.
- [ ] All I/O flows through `std.Io` writers/readers owned by the `Interp`.
- [ ] Values are typed (`Value`, `Comb`, `CellRef`) — no bare `i64` with numeric
      threshold checks; `Word` survives only in the `.x` wire-format code.
- [ ] `@import`s form a DAG (checked in CI); no source file over ~1,000 lines.
- [ ] All user-facing behaviour byte-identical (golden corpus + C-differential suite).

## 2. What does NOT change

- **Miranda semantics**, as pinned by the golden corpus, `tests/regression.zig`
  (C-differential), smoke, sigint and spine-differential suites. These suites *are*
  the specification for this plan.
- **The `.x` dump format** — bit-compatible (prelude/stdenv dumps, `//make`). All
  format knowledge ends up isolated in `graph/dump.zig`.
- **Miranda domain vocabulary** — `hd`/`tl`, combinator names (`S`, `K`, `TRY`,
  `U_`…), `NIL`, offside, spine, private names. Renaming is for *C artifacts*, not
  domain terms (Phase 6 glossary).
- **The execution model** — SK-combinator graph reduction with the explicit spine
  stack, the mark-sweep GC, lazy semantics.
- **Test conventions** — inline per-function tests, `Tests:` doc references, the
  golden/differential cadence, `zig build strict`.

## 3. Baseline (measured 2026-07-05)

| Metric | Count | Where it concentrates |
| --- | ---: | --- |
| `[*:0]` C-string types | 299 | lex.zig, main_clib.zig, driver, RuntimeState |
| `c_int` / `c_long` / `c_ulong` | 309 | main_clib.zig, lex.zig, drivers |
| Ambient singleton reads (`heap.heap().`, `rs().`, `cs().`, `ls().`, `ev().`, `s().`) | ~1,577 | everywhere |
| C-format print calls (`word.print`/`printErr`/`printf`/`fprintf`/`sprintf`) | ~320 | compiler, driver, reducer |
| `setjmp`/`longjmp` mentions | 27 | repl, startup, module_loader, main_clib |
| `extern fn` | 15 | main_clib.zig (syscall floor + setjmp family) |
| `@ptrFromInt` / `@intFromPtr` | 67 | FILE-in-cell hacks, C-string plumbing |
| Files > 1,000 lines | 9 | heap 2786, types 2733, lex 2080, trans 1831, word 1718, main_clib 1489, combinators 1299, big 1087, parser 1009 |
| Hand-rolled libc | ~2,500 lines | main_clib.zig + the `FILE`/printf/ctype half of word.zig |

Structural facts the plan is built around:

- The production tokenizer is still the C-ported `yylex` (`parser/lex.zig`); the
  "new" recursive-descent/Pratt parser consumes tokens manufactured from it by
  `parser/lex_bridge.zig`. There is **no native lexer yet**.
- Every REPL evaluation **forks a child process** (`repl.process()`) so graph
  mutation can't corrupt the parent's compiled script; recovery is
  `sigsetjmp`/`siglongjmp` on `rs.env`.
- `word.zig` mixes the value vocabulary with a pooled `FILE` implementation and a
  printf engine; the heap imports the REPL and the type checker (cyclic imports).
- State is aggregated (`Interp`) but consumed ambiently through singleton accessors
  reading `interp.current_interp`.

## 4. Target architecture

### 4.1 Module tree and layering

```
src/
  main.zig        CLI parsing, construct Interp, run. The only process-aware file.
  os.zig          The POSIX floor: signal registration, child processes.
                  ALL extern fns, [*:0], c_int live here and nowhere else.
  syntax/         text -> AST. Pure: fn(allocator, source) -> {AST, Diagnostics}.
    source.zig      file bytes, line starts for spans, literate-margin stripping, UTF-8
    lexer.zig       the native tokenizer (replaces yylex): identifiers/keywords/
                    operators/numerals/strings/chars/comments; produces a flat
                    token stream with no offside/layout tokens yet
    layout.zig      the offside rule (see correction below — NOT today's
                    token_filter.zig, which is just the Token/TokenId/Span
                    vocabulary with no logic in it)
    parser.zig, pratt.zig, ast.zig
    directives.zig  %include/%export/%free/%insert/%bnf... -> structured Directive values
  semantics/      AST -> combinator graph.
    symbols.zig     symbol table over interned strings (replaces the id dictionary)
    infer.zig       type inference walk        (from types.zig)
    unify.zig       unify/subst/occurs/instantiate (from types.zig)
    type_errors.zig type-error reporting        (from types.zig)
    depend.zig      tsort/deps                  (from types.zig)
    lower.zig       AST -> combinators          (from trans.zig + codegen.zig)
    match.zig       pattern-match compilation   (from trans.zig)
    modules.zig     %include graph, load/reload (from module_loader.zig)
  graph/          the object model. Imports NOTHING above it.
    value.zig       Value, Comb, CellRef, Tag
    heap.zig        cell arena, constructors, typed payload accessors
    gc.zig          mark/sweep + the root registry
    dump.zig        .x wire format (the only home of `Word` at the end)
    print.zig       term/type printing (outTerm, charname)
    bignum.zig      (today's big.zig)
  eval/           the reduction machine.
    reduce.zig, spine.zig, combinators/ (combinators, ready, lex, io handlers)
    stream.zig      READ/READVALS/Tofile streams over std.fs.File
  session/        the composition root and user interface.
    interp.zig      Interp: owns Heap, SymbolTable, ScriptStore, Config, ReplSession...
    repl.zig, commands.zig, editor.zig, config.zig (.mirarc, flags), boot.zig
  tools/, testutil.zig, micro_benchmarks.zig   (unchanged homes)
```

**Layering rule** (CI-enforced, Phase 4): `graph` and `syntax` are leaves;
`semantics` may import `syntax` + `graph`; `eval` may import `graph`; `session`
may import everything; nothing imports `session`; only `main.zig`/`session` and
`eval/stream.zig` may import `os.zig`. Today's heap→repl and types→trans→lex
cycles become build failures.

### 4.2 Ownership model

`main()` builds an `Interp` from `(allocator, std.Io, args)`. Subsystems are structs
with methods; dependencies arrive as parameters (`*Heap`, `*Diagnostics`, a
`Compile` context…). The ~1,600 ambient reads become method calls on receivers
already in hand. `current_interp` is deleted. The only global left is
`os.interrupt_flag: std.atomic.Value(bool)`.

### 4.3 Value model

Keep today's **bit layout** (so `.x` files and the reducer's performance are
untouched); change the **type**:

```zig
pub const Value = packed struct(u64) { raw: i64 };  // ctors: char(u21), smallInt(i64), comb(Comb), cell(CellRef)
pub const Comb  = enum(u16) { S, K, I, ..., False, True, NIL, NILS, UNDEF };  // exhaustive, from cmbnms
pub const CellRef = enum(u32) { _ };                // cannot be confused with a count
pub const Kind = union(enum) { char: u21, small: u8, comb: Comb, cell: CellRef };
```

`x < ATOMLIMIT` / `CMBASE + 138` threshold checks become `switch (v.kind())`.
The existing `Ref`/`classify()` seam is the embryo of this and is absorbed by it.
The string table's *negated-id* trick (non-cell payloads kept out of the traced
range) becomes an explicit, documented payload variant instead of a sign convention.

### 4.4 Error and diagnostics model

- All fallible paths return `MiraError!T`; the REPL loop is the sole recovery point.
- `Diagnostics` (grown from the parser's existing `{span, message}` list) replaces
  the `SYNERR`/`errs`/`errline`/`errcol` sentinel cluster. Printing stays *eager and
  byte-identical* where the C did it eagerly — the structural change is that the
  *state* lives in a diagnostics value, not scattered flags.
- Interruption: signal handlers only set the atomic flag; the reduce loop polls it
  on its existing cycle counter and returns `error.Interrupted`. No stack is ever
  unwound by `siglongjmp` again.

### 4.5 I/O model

`Interp` owns buffered `out`/`err` writers built on `std.Io`. Miranda-level file
streams (`READ`, `Tofile`, `Appendfile`) become a small `Stream` type over
`std.fs.File` with a pushback buffer. The pooled `FILE`, the printf engine, ctype,
and the C string functions are deleted in favour of `std.fmt`/`std.ascii`/`std.mem`.

### 4.6 Process model

Fork-per-evaluation is replaced by **heap checkpoint/restore**: copy the cell arena
(and root set) before evaluating, restore after. At the default 2.5M cells that is a
~40 MB copy — single-digit milliseconds at an interactive prompt. `!cmd` and the
editor use `std.process.Child`. Fallback if the differential suite finds a semantic
gap: fork stays, but confined behind one function in `os.zig`.

---

## 5. Phases

| # | Name | Theme | Size |
| --- | --- | --- | --- |
| 0 | Behaviour lock & ratchet | measurement + golden coverage | S |
| 1 | One front end | delete the C lexer | XL |
| 2 | Native I/O & diagnostics | delete the libc | L |
| 3 | Structured control flow | delete setjmp/longjmp + fork-per-eval | L |
| 4 | Composition | layering, god-file splits, ownership threading | XL |
| 5 | Typed object model | Value/Comb/CellRef | L |
| 6 | Surface polish & docs | types, names, build.zig, docs | M |

Sizes: S ≤ 1 day, M = a few days, L = 1–2 weeks, XL = several weeks of steady work.
Every phase ends with `zig build check && zig build strict && zig build test-golden
&& zig build test-regression` green and `zig build bench` within noise. Phases are
ordered so each one deletes coupling that would make the next one touch more lines.

---

### Phase 0 — Behaviour lock & ratchet

**Goal:** turn "looks idiomatic" into numbers that can only go down, and widen the
behavioural net before Phase 1 moves the most delicate surface (the lexer).

**Steps**

1. **`scripts/scorecard.sh`** — one script replacing `idiomatic-check.sh`,
   `readability-check.sh`, `shared-state-check.sh`, `test-coverage-check.sh`
   (delete those four). It reports every metric in §3 plus: module-level `var`
   declarations, import-cycle count, and files > 1,000 lines. Counts land in a
   checked-in `scripts/scorecard.baseline` (plain `key value` lines).
2. **Ratchet rule:** the script fails if any count *rises* above baseline; a commit
   that lowers a count updates the baseline in the same commit. Wire it into
   `zig build check` and `zig build strict` as a run step.
3. **Golden coverage for Phase-1 surfaces.** Add golden cases (byte-exact stdout +
   stderr) for: literate scripts; each `%` directive form (`%include` with aliases
   and parametrised includes, `%export`, `%free`, `%insert`, `%list`/`%nolist`);
   `%bnf` grammars and lexstate rules; hex/octal/bignum literals; char classes and
   string escapes; private names surviving a dump/undump round-trip; and the exact
   wording/position of representative lexer error messages.
4. **Differential coverage.** Extend `tests/regression.zig` to run the same corpus
   against the reference C `mira` where available, so lexer parity is checked twice.
5. Document the cadence (this section) in `ARCHITECTURE.md`'s testing chapter.

**Gate:** scorecard runs in `check`/`strict`; baseline committed; new golden cases
pass against the current binary (they pin today's behaviour, bugs included).

**Risks:** none — additive only.

---

### Phase 1 — One front end (delete the C lexer)

**Complete as of 2026-07-06** (all 8 steps landed — see each step's own
"landed" entry below for what shipped and, for step 8, how the original
goal below was corrected on investigation: `lex.zig`/`lex_state.zig` are
trimmed of the character-at-a-time tokenizer, not deleted outright, since
both still hold genuinely load-bearing production state/helpers unrelated
to lexing).

**Goal:** a single, native `syntax/` pipeline: `Source → Lexer → layout → Parser →
AST → lower`. Delete `parser/lex.zig` (2,080 lines), `parser/lex_bridge.zig` (387),
`parser/lex_state.zig`, and the FILE-handle-in-a-cell hack.

**Why first:** the legacy lexer is the anchor tenant of the fake libc (`FILE`,
`getc`/`ungetc`, `fmemopen`), of `DICSPACE` hand-managed memory, and of the last
heap-building-during-scanning behaviour. Nothing else can get idiomatic while the
front door is C.

**Design decisions**

- The lexer is **pure**: `(allocator, *const Source) → {[]Token, Diagnostics}`. No
  heap cells are built during scanning. Numerals keep their source digits in the
  token (as `ast.Literal.int` already does); bignums, string cons-lists and id
  nodes are built later, in `lower`/`symbols`.
- `Source` owns the file bytes (read whole via `std.fs`; scripts are small),
  computes line starts for `Span`s, strips literate margins, validates UTF-8
  (reusing `io/utf8.zig`). `fmemopen`-style string input becomes "a `Source` over a
  byte slice" — the REPL path and the file path unify.
- `%` directives tokenize as tokens; **parsing** them into structured values
  (`Directive` union: include/export/free/insert/list/bnf/…) happens in
  `syntax/directives.zig`. `semantics/modules.zig` consumes `Directive` values —
  today's pattern of mutating `includees`/`exports` heap lists *mid-lex* ends.
- **Correction (found 2026-07-05, confirmed against a clean `main` checkout, not
  caused by this plan's work):** `%include`/`%export`/`%free` are not actually wired
  up end to end today. `src/parser/codegen.zig:808` no-ops all three AST nodes
  (`.include, .export_list, .free_directive => {}`), and `src/parser/lex_bridge.zig`
  drops the pathname payload the legacy lexer's `directive()` already parsed for
  `%include`, so even a bare `%include "x"` with nothing else in the file fails with
  a syntax error at the next token — reproduces on the shipped
  `miralib/ex/polish.m` example too. See `tests/golden/README_pending_phase1.md`
  for the fixtures (`directive_include`/`directive_include_alias`/
  `directive_export_scope`/`directive_free`) that demonstrate this, deliberately
  left unpinned rather than freezing "feature absent" as a golden case. So step 5
  below is not "preserve behaviour" for these three directives — it is **first
  implementation** against the native front end. `%insert` is unaffected (pure
  textual substitution inside the lexer, no AST node) and is pinned normally.
- The identifier dictionary (`makeId`/`findid`/`keep`, `DICSPACE`, `dicovflo`)
  becomes `semantics/symbols.zig`: interned `[]const u8` (the existing
  `strtab.StringTable`) → id node, allocator-backed, no fixed dictionary space.
  Private names (`makePn`/`stoPn`/`resetPns`) move here too.

**Steps** (each lands green; legacy path stays wired until step 8)

1. `syntax/source.zig` with literate stripping + spans; unit tests against the
   literate golden cases. **Landed** (2026-07-06): plain/literate detection (leading
   `>` or `.lit.m` filename), in-place prose blanking that preserves every byte
   offset/column/line number, `position()` for `Span` lookup.
2. `syntax/lexer.zig` core: names, keywords, typevars, operators, numerals
   (decimal/hex/octal integers, decimal floats), strings, chars (with the full
   escape table — `\a\b\f\n\r\t\v`, `\xHHHH`/`\XHHHHHH` hex, up-to-3-digit decimal,
   `\&` elision, `` \` ``, line-continuation), and `||`/`#!` comments; emits
   `token_filter.zig`'s `Token`/`TokenId`/`Span` vocabulary. Deliberately out of
   this step's scope, to keep it reviewable: hex-float numerals (`0x1.8p3`),
   backtick infix names, `%`-directive tokenization, char classes (`%bnf`/`%lex`
   only) — noted as gaps in the file, not silently dropped. **Landed**
   (2026-07-06, merged with step 4 below since a real scanner naturally handles
   literals together): 29 tests, verified digit-for-digit against `lex.zig`.
3. **Correction (found 2026-07-06):** `token_filter.zig` is *only* the
   `Token`/`TokenId`/`Span` type vocabulary — zero logic. The offside rule itself
   is `lex.zig`'s `yylex()` checking `ls().col < ls().lmargin` against a
   margin/verge stack (`ls().margstack`/`ls().lverge`) that the **parser**
   mutates via `setlmargin()`/`unsetlmargin()` when it enters/leaves a layout
   block (`where`, `%bnf`, …) — i.e. today's lexer and parser are mutually
   coupled through this shared margin state, not cleanly layered. `layout()`
   itself (confusingly similarly named) is just whitespace/`||`-comment
   skipping, already folded into step 2 above. Porting the real offside rule
   means designing how the native `parser.zig` requests a margin push/pop from
   the lexer/token-stream (e.g. the lexer takes a margin-stack parameter, or
   the parser post-processes a flat token stream the way `token_filter.zig`'s
   name suggested but never implemented) — a real design decision, not a
   mechanical port. Do this as its own step, test-first against layout-heavy
   golden cases (nested `where`, multi-clause definitions, `%bnf` blocks)
   *before* wiring numerals/strings from step 2 into production. **Landed**
   (2026-07-06): `syntax/layout.zig`. First cut was a from-scratch
   Haskell-style layout algorithm (push a margin at the first token and
   after `where`/`with`) — **wrong**, corrected the same day after finding
   `parser/lex_bridge.zig`'s `tokenizeLoop`, which is the mechanism *actually
   driving today's shipping parser* (not a legacy-only artifact): it tracks
   `seen_def_eq`/`paren_depth` and pushes a margin at the column *following*
   a top-level `=`/`::`/`::=`/`==` (not at block-opening keywords), with
   `where` only clearing `seen_def_eq` so the block's own first `=` does the
   push. `layout.zig` is now a direct, faithful port of that proven state
   machine rather than an independent re-derivation — much safer, since it's
   provably what already works. Lesson: when a "the parser and lexer share
   mutable state" tangle blocks a clean design, look for whether something
   *already* untangles it in practice before designing a replacement from
   principles — `lex_bridge.zig` already had the answer.
   6 unit tests (one per trigger: `=`, `::`, `where`, cascading dedent,
   bracket-guarded comparison `=`, explicit semicolon) plus 5 end-to-end
   tests running `Source → lexer.tokenize → applyLayout →
   parser.zig's parseScript` and inspecting the resulting AST — including
   `miralib/ex/fib.m` verbatim (comments + a realigned guard) — which caught
   two real bugs in turn (first cut: `.elseq` injected *before* the `=`
   token instead of replacing it; second cut, while fixing the first: a
   test asserting the *previous*, wrong algorithm's output, caught once the
   rewrite disagreed with it). **Not yet differentially verified** against
   the legacy lexer's actual token-for-token output — that is step 4 below,
   still to do; being a direct port of proven logic is a much stronger
   starting point than the first cut, but "ported by reading the source"
   and "verified by running both and diffing" are still not the same claim.
4. Numerals/strings/chars/comments (landed as part of step 2, above) and
   `syntax/layout.zig` (step 3) — parity-tested token-by-token against the
   bridge output over the whole golden corpus (a temporary dual-run test
   harness: run both lexers, diff the token streams). **Landed, partially**
   (2026-07-06): `src/syntax/differential_test.zig` — tokenizes the same
   source through `lex_bridge.zig`'s `tokenize` (real `yylex()` +
   `setlmargin`/`unsetlmargin`, the mechanism actually driving today's
   parser) and the native `Source → lexer.tokenize → applyLayout`, and diffs
   the `TokenId` sequences. 8 real scripts pass byte-for-byte (the golden
   corpus's non-directive `.m` files plus `miralib/ex/fib.m` verbatim) — this
   is the strongest evidence yet that `lexer.zig`/`layout.zig` are actually
   correct, not just internally consistent. Caught one more thing worth
   recording: `lex_bridge.tokenize()` is normally called once per process
   (real `mira` usage) and leaves sticky global state (the dictionary
   buffer, `SYNERR`, the margin stack) that corrupted the *next* call when
   this harness ran it repeatedly — worked around with a full
   `interp.reset()` + re-`miraSetup()` before each comparison, not a change
   to `lex_bridge.zig` itself. **Corpus auto-discovery landed** (2026-07-06):
   a 9th test walks every `.m` file under `tests/golden/` via
   `std.testing.io` (not `ctx.io` — that's only available in `main()`-style
   entry points; `std.testing.io` is the equivalent inside a `test` block,
   confirmed from `parser_tests.zig`'s existing use of it), skipping any
   script containing `%` or `` ` `` (this lexer's known gaps at the time —
   see below, `%` no longer is one). **Still not done:** wiring this as its
   own build step (it currently only runs as part of `main-tests`); char
   classes (`` `[...]` ``, `%bnf`/`%lex`-only, deferred with `%bnf`/`%lex`
   themselves per the plan's own ordering).
   **Landed (2026-07-06):** `%`-directive tokenization (see the step-5
   `Scanner`-wiring entry below) and `$name`/`$Cname`/`$$` infix notation —
   correcting a wrong assumption in `lexer.zig`'s own original header, which
   described this as backtick notation; verified against `lex.zig`'s `'$'`
   case, real Miranda uses `$`, backtick has no general lexical meaning
   here. Hex-float numerals (`0x1.8p3`) also landed: `std.fmt.parseFloat`
   accepts the same lenient grammar `lex.zig`'s `hexnumeral` does (leading-
   dot fractions, optional exponent), verified directly rather than assumed,
   so the whole matched text is handed to it rather than hand-rolling hex
   arithmetic. 15 new tests across these three additions.
5. `syntax/directives.zig` + `semantics/modules.zig` consumption. This is where
   `%include`/`%export`/`%free` actually get implemented (aliasing, free-binding
   substitution, cycle detection, dependency ordering) — module_loader.zig's real
   logic (692 lines) is the reference for the *intended* semantics (see
   docs/man/mira.man.ms §27), but its wiring to the AST must be built, not just
   moved, since none currently exists. Verify against `tests/golden/directive_*`
   (promote them from pending to pinned once working) plus the manual's worked
   examples (`%include "matrices" {elem==num; zero=0; ...}`,
   `%include "mike" -g mike_f/f`). `%bnf`/`%lex` grammar-extension machinery
   (`eprodnts`/`nonterminals`/`lexstates`/`lexdefs`) ported **last** — it is the
   hairiest and least-covered corner; goldens from Phase 0 step 3 gate it.
   **Scoping note (found 2026-07-06):** `%` isn't a token in `syntax/lexer.zig`
   at all yet (step 2 deliberately deferred it) — legacy's `directive()` does
   its own specialised scanning after `%` (a directive keyword, distinct from
   plain identifiers; `"..."`/`<...>` pathnames with different quoting rules
   than string literals; a brace-delimited, possibly multi-line binding/spec
   block for `%include`'s bindings and `%free`'s signature).
   **Landed** (2026-07-06): `src/syntax/directives.zig`'s `Scanner` — scans
   directly over `Source` bytes (not `lexer.tokenize`'s output; a directive's
   pathname/keyword rules are different enough from ordinary tokens that
   scanning raw bytes was simpler than threading directive-awareness through
   the general lexer). Produces a `Directive` value per `%include`/`%export`/
   `%free` with the bindings/spec/parts-list kept as raw text (deferring
   deep parsing to whichever of `semantics/lower.zig` or the ported
   `semantics/infer.zig` needs it, as planned) plus fully-parsed alias lists
   (`new/old`, `-old`) since that grammar is simple enough to scan directly.
   `%insert`/`%list`/`%nolist`/`%bnf`/`%lex`/`%begin` are recognized but
   explicitly not processed (see the file's header for why each is out of
   scope). 8 tests, drawn from docs/man/mira.man.ms §27's own worked examples
   (`%include "matrices" {elem==num; ...}`, `%include "mike" -g mike_f/f`)
   where possible.
   **`semantics/modules.zig` landed, partially** (2026-07-06): the two *pure*
   transformations the manual specifies, independent of actually compiling
   anything. `resolveExports` computes a script's export set from its
   top-level names and a parsed `%export` directive (`parseExportParts`
   handles `+`, bare names, `-exclude`, and `"fileid"` re-export forms;
   a negative occurrence overrides positives regardless of ordering, per
   the manual, checked with a dedicated test) — no `%export` directive
   defaults to exactly `+`. `applyAliases` applies an `%include`'s alias
   list (`new/old` rename, `-old` suppress) to a name→`ID`-node map. Both
   operate on plain name maps, not real compiled scripts, so both are fully
   unit-tested without a heap or parser; 9 tests, several matching the
   manual's own worked examples (`%export + -flooby`, `%export "liba" "libb"`,
   `-g mike_f/f`) exactly. **Not yet done — the harder half of step 5:**
   actually loading and compiling an `%include`d file, extracting its real
   export set from a real heap (today's tests supply a stub map), binding
   the result into the including script's identifier scope via
   `semantics/symbols.zig` (itself not wired into `codegen.zig`/`trans.zig`
   yet either — see step 6), cycle detection across a chain of `%include`s,
   and free-binding substitution (`%free`'s signature is still raw text,
   needing an expression/type parser `syntax/` doesn't have — though
   `parser.zig`'s existing `parseType`/`parseOneTypeSpec` may cover this by
   re-tokenizing the captured spec text rather than needing something new).
   Also still not done: path resolution (`<...>`/`~`/prefix-relative — needs
   interpreter context), and consuming the now-landed `.directive` token in
   `parser.zig`/building the real AST shape (see below).
   **`Scanner` wired into `syntax/lexer.zig` (landed 2026-07-06):** a `%`
   dispatches to a new `lexDirective`, which hands off to `directives.zig`'s
   `Scanner` and produces one atomic `.directive` token (a new `TokenId`)
   whose `int_val` indexes a side-list of parsed `Directive` values
   (`Lexer.directives`; `tokenize` discards it, `tokenizeWithDirectives`
   returns both) — directive grammar doesn't decompose into the lexer's
   ordinary token set, so it's scanned as one unit rather than token-by-token.
   6 new tests. **Deliberately not touched:** `token_filter.zig`'s existing
   `kw_include`/`kw_export`/`kw_free`/`kw_bnf`/`kw_lex`/`pathname` token kinds
   and `parser.zig`'s existing `parseInclude`/`parseExport`/`parseFree`/
   `parseDiscardSection` — these turned out to be *live production code*,
   not dead placeholders: `lex_bridge.zig` (driving today's shipping parser)
   already maps the legacy lexer's own directive scanning into these exact
   token kinds, so `%include`/`%export`/`%free`/`%bnf`/`%lex` already parse
   (into a simpler, narrower AST shape) via the legacy bridge today, even
   though `codegen.zig:808` still no-ops the resulting AST nodes (matches
   the step-5 correction above — parses, does nothing).
   **AST + parser wiring landed (2026-07-06):** `ast.TopLevel` gains a
   `.directive` variant carrying the *real* grammar's full data (bindings,
   aliases, `from_miralib`, the full `%export` parts grammar as raw text) —
   added alongside, not instead of, the existing `include`/`export_list`/
   `free_directive` variants, which stay exactly as the legacy-bridge path
   left them. The payload type (`Directive`, plus `DirectiveAlias`/
   `DirectiveInclude`) moved from `syntax/directives.zig` into
   `parser/token_filter.zig` (which re-exports it for source compat) so
   `parser/ast.zig` and `parser/parser.zig` could reference it without
   creating an import cycle: `syntax/` already depends on `parser/`
   (`syntax/layout.zig` imports `parser/parser.zig`), so `parser/` importing
   `syntax/directives.zig` back would cycle — `token_filter.zig` has no
   dependencies of its own, so it's the shared home, the same role `Span`
   already plays there. `Parser` gained a `directives` field and
   `initWithDirectives` constructor (additive — `Parser.init` and all 13
   existing callers are unchanged, defaulting to an empty slice, since the
   legacy-bridge-fed production path never produces `.directive` tokens);
   `parseTopLevel` dispatches `.directive` tokens to a new
   `parseDirectiveToken`, which just wraps the already-parsed payload (no
   further parsing needed — the `Scanner` already did it); `codegenScript`
   no-ops it like the other three. One new end-to-end test
   (`syntax/layout.zig`): `Source → tokenizeWithDirectives → applyLayout →
   Parser.initWithDirectives → parseScript` on a script with `%export`,
   checking the resulting `.directive` node's `export_list.parts_text`.
   **Still not done — the actual "harder half":** loading and compiling an
   `%include`d file, extracting its real export set from a real heap
   (`semantics/modules.zig`'s `resolveExports`/`applyAliases` exist but
   operate on stub maps in their own tests, not a real compiled script),
   binding the result into the including script's `symbols.zig` scope,
   cycle detection across a chain of `%include`s, path resolution
   (`<...>`/`~`/prefix-relative — needs interpreter context), and
   free-binding substitution for `%free` (still raw `spec_text`; likely
   re-tokenizes-and-reparses via `parser.zig`'s existing `parseOneTypeSpec`
   rather than needing a new parser, but not attempted yet). This is a
   genuinely large, mostly-from-scratch feature (no reusable reference
   implementation — `module_loader.zig`'s `mkincludes` was already
   confirmed dead code with an unverifiable heap encoding, see the
   step-5 "Investigated" entry below) — expect it to need its own
   dedicated design pass, not a mechanical continuation of this entry.
   Verify the eventual full semantics against `tests/golden/directive_*`
   (promote from pending to pinned once working).
   `%bnf`/`%lex` grammar-extension machinery (`eprodnts`/`nonterminals`/
   `lexstates`/`lexdefs`) ported **last** — it is the hairiest and
   least-covered corner; goldens from Phase 0 step 3 gate it.
   **The harder half landed (2026-07-06), against the native pipeline** (per
   the user's own direction — built after step 7's cutover, not against the
   legacy path about to be deleted): `semantics/modules.zig` gained
   `processIncludes`/`processOneInclude`, wired into `parser_api.zig`'s
   `runParsedTokens` right before the including script's own `codegenScript`
   call. Per `%include`: resolve the path (`<...>` relative to
   `rt.rs().miralib`, `"..."` relative to the including file's own
   directory, `.m` appended if missing), cycle-detect via an
   `IncludingStack` (a `StringHashMapUnmanaged(void)` of resolved absolute
   paths, push/pop around the recursive call so a diamond-shaped, non-cyclic
   include graph is still fine), read + `%insert`-splice + tokenize/layout/
   parse the target file, compile any `{bindings}` block *first* (see below),
   recursively process the target's own nested `%include`s, `codegenScript`
   the target's own definitions, then compute its `%export` set (the
   already-existing, already-tested `resolveExports`/`parseExportParts`),
   resolve each exported name to its `Word` via `symbols.syms().find`, apply
   the including directive's aliases (the already-existing, already-tested
   `applyAliases`), `SymbolTable.bind` (a new primitive — see below) each
   alias's new name, and permanently hide every one of the included file's
   own top-level names that didn't survive into the final visible set via
   `lex.mkprivate` (proven earlier in this phase for prelude's own
   internal-primitive hiding; applied here for the first time to something
   other than bootstrap). `%free`'s bindings block (`{elem==num; zero=0;
   add=+}`) is compiled by a pragmatic clause-splitting transformation, not
   real abstract/opaque free-variable type-checking: each `;`-separated
   clause becomes ordinary top-level syntax (`==` → `type {lhs} == {rhs}`,
   single `=` → `{lhs} = ({rhs})`, the parens letting a bare operator symbol
   like `add=+` parse as `add = (+)`) and is compiled as a normal top-level
   definition *before* the library's own code, so the library's later
   references to `elem`/`zero`/`add` resolve via ordinary name lookup — the
   "no bindings supplied" case (genuine abstract free variables) is an
   accepted, documented gap, matching every shipped fixture. Needed one new
   `symbols.zig` primitive, `SymbolTable.bind` (unconditional insert-or-
   overwrite, whether or not the name existed before) — distinct from the
   three that already existed (`intern` find-or-create, `createFresh`
   always-fresh, `rebind` requires a pre-existing name): an alias's "new"
   name usually isn't interned yet, and it's a new *name* pointing at an
   *existing* node, not a node changing identity for a name that already
   resolves there.
   Two real, previously-invisible bugs found purely by running the five
   `directive_*` golden fixtures end to end (not by inspection) and fixed:
   **(1)** `directives.zig`'s `Scanner.scanBraceBlock` (the optional
   `{bindings}` block probe following an `%include`'s pathname) called
   `skipWhitespaceAndNewlines()` before checking for `{` — with no bindings
   block present, this walked the scanner's position *past* a blank line
   onto the *next* top-level declaration looking for a `{` that was never
   there, found none, and returned `null` without restoring `self.pos` —
   silently corrupting the scan position so the *next* declaration's first
   token (e.g. `use_it` in `use_it x = visible_fn x`) got swallowed by the
   subsequent alias-list scan and discarded (it doesn't match the
   `identifier/identifier` or `-identifier` alias grammar, so `scanAliases`
   just aborted after consuming it). Fixed by only skipping horizontal
   whitespace before the `{` probe — a bindings block, when present, always
   follows on the same line as the pathname/aliases in every fixture and
   the manual's own examples. **(2)** A first attempt at `symbols.bind`
   used explicit `[*:0]const u8` casts where the called functions
   (`strtab.strBits` takes `anytype`; a `[:0]u8`'s own `.ptr` already
   coerces) didn't need them — removed to avoid an avoidable scorecard
   `[*:0]` regression, same as `createFresh`'s parameter-type redesign
   earlier in this phase.
   All five `tests/golden/directive_*` fixtures promoted from pending to
   pinned (`zig build generate-golden`, reviewed): `directive_include`
   (105/101), `directive_include_alias` (aliased, 105),
   `directive_export_scope` (`hidden_fn` genuinely inaccessible after
   `%include` — `UNDEFINED NAME - hidden_fn`, confirmed distinct from and
   unaffected by two *pre-existing*, unrelated bugs also surfaced by this
   fixture: `sayhere`'s "undefined name" diagnostic on stdout interleaves
   oddly with stderr's "UNDEFINED NAME" under a naive `2>&1` capture — not a
   real formatting bug, reproduces on a plain script with no `%include` at
   all, each stream is coherent read separately), `directive_free` (6).
   `tests/golden/README_pending_phase1.md` is stale as a result and
   should be deleted; its history is preserved in this entry and in the
   commit that pinned the five fixtures.
   **Investigated (2026-07-06):** `module_loader.zig`'s `mkincludes` (the
   692-line reference above) is real, dense, still-`fork()`-using logic with
   a triple-nested heap-cons encoding for its `includees` input — but it is
   currently **dead code**: `loadfile()` only calls it when
   `rs.includees != NIL`, and nothing populates `rs.includees` since
   `codegen.zig:808` no-ops the `.include` AST node. So it has not been
   exercised by any passing test through this whole porting effort, and its
   exact heap encoding was built for a YACC grammar's mid-rule actions that
   no longer exist to construct it correctly. Wiring straight into it would
   mean reverse-engineering unverified legacy heap layout at real risk, for a
   dependency (`fork()`) Phase 3 is deleting anyway — confirms "reference for
   intended semantics, not something to reuse directly" is the right call,
   and that a clean `semantics/modules.zig` needs `symbols.zig` (step 6, see
   below) as a prerequisite for clean identifier binding, not the other way
   around.
6. `semantics/symbols.zig`; `codegen.zig`/`trans.zig` id lookups rewired from
   `lex.findid`/`makeId` to it. Dump/undump round-trip goldens verify private-name
   serialization is unchanged. **Landed, partially** (2026-07-06):
   `src/semantics/symbols.zig`'s `SymbolTable` (replaces the fixed-size
   hash-bucket array + heap-cons chaining of `findid`/`makeId`/`name()` with
   a `std.StringHashMapUnmanaged`, keyed by `heap.getId`'s stable
   `strtab`-owned bytes — no string ownership of its own) and `PrivateNames`
   (replaces the manually-`realloc`ed, fixed-+400-chunk-growth `pnvec` with a
   plain `std.ArrayList`). The heap encoding downstream code already
   understands (`ID`/`STRCONS` cells) is untouched — only the lookup
   structure changed. 8 tests. **Not yet done:** actually rewiring
   `codegen.zig`/`trans.zig`'s identifier lookups to use this instead of
   `lex.findid`/`makeId` — today's increment is additive only, same pattern
   as every `syntax/` file landed so far.
   **Attempted and reverted (2026-07-06) — read before trying again.** A
   first attempt swapped `findid`/`makeId`/`name()`/`completeIds`'s bodies
   over to `SymbolTable`, keeping their signatures unchanged (so callers —
   `codegen.zig`'s `nameWord`, `setup.zig`'s bootstrap identifiers — needed
   no edits). That part checked out: `makeId`'s real call sites (verified by
   reading every one, not assumed) never call it for a name already present,
   so `SymbolTable.intern`'s find-or-create is behaviourally identical to
   the original always-insert semantics, and `miraSetup()`'s bootstrap
   identifiers run before any script is lexed, so the dictionary is
   genuinely empty at that point. But `LexState.namebucket` (the field being
   replaced) turned out to have **three** load-bearing consumers, not one:
   1. `findid`/`makeId`/`name()`/`completeIds` (`lex.zig`) — the dictionary
      lookup itself, the one this step is about.
   2. **GC root marking** (`heap.zig`'s `mark()`, ~line 500): every bucket
      head is marked as a root, keeping every dictionary-referenced `ID`
      node alive. Nothing marks a replacement structure automatically —
      miss this and the GC silently collects identifiers still "in scope."
   3. **`%export` dump-time hiding** (`compiler/dump.zig`'s `privatise`/
      `publicise`): the mechanism that hides non-exported definitions when
      writing/reading a `.x` file works by *finding and mutating the
      specific cons cell inside the bucket chain* that references a given
      `ID` node, swapping it for a private-name node in place. This has no
      equivalent operation on a flat hash map (which stores values directly,
      not via a searchable/mutable chain) — it's a structural mismatch, not
      a missing method to add.
   (2) has a small, mechanical fix (iterate the new table and mark each
   value). (3) does not — it needs either a redesigned hiding mechanism (a
   real design task, and exactly what `semantics/modules.zig`'s eventual
   `%export` implementation should probably subsume rather than duplicate)
   or keeping a parallel structure just for this one narrow purpose, which
   defeats the point. Reverted cleanly (`git checkout --`) rather than ship
   partial: shipping (1)+(2) without (3) would silently break `%export`'s
   dump-time hiding for any script that dumps/undumps with private
   definitions — a regression the existing test suite would very likely
   *not* catch (no golden case exercises `%export` + dump/undump together,
   since `%include`/`%export` are non-functional in the current pipeline
   anyway — see the step-5 correction above). Next attempt should design (3)
   as part of `semantics/modules.zig`'s real `%export` semantics, not as a
   drop-in dictionary swap; do (1)+(2) together with it, not before it.
   **Landed (2026-07-06), second attempt.** Did (1)+(2)+(3) together as a
   single rewiring: `findid`/`makeId`/`name()`/`completeIds` (lex.zig), GC
   root marking (`heap.zig`'s `mark()`), and `dump.zig`'s `privatise`/
   `publicise` all moved to `symbols.zig`'s `SymbolTable`, using a new
   `rebind(name, new_id)` method for (3) instead of a redesigned `%export`
   mechanism — `privatise`/`publicise` still swap *which node* a name
   resolves to exactly as before, `rebind` just does that swap by name
   instead of by bucket-chain-splice. Two real bugs found only by running
   the actual golden/mira suites end-to-end (not by code inspection), both
   in `parser/lex.zig`'s `mkprivate` (the `%export`-independent mechanism
   that hides *every* private-prelude identifier — `offside`, `hd`, `error`,
   `concat`, etc. — right after the prelude loads, so its own name never
   shadows a script's later use of the same word):
   - `makeId` itself first went in as `SymbolTable.intern` (find-or-create).
     Wrong: verified empirically (not just by inspection) that `setup.zig`'s
     `predef`/`primdef` rely on `makeId` being *always create a fresh,
     shadowing cell*, because `privlib()`/`stdlib()` deliberately `predef`
     the same names ("error", "code", "decode", "drop", "foldr", "shownum",
     "take") once per bootstrap stage. Symptom: 100% golden failure,
     `stdenv.x` reported "name clashes" with garbled entries. Fixed by
     making `makeId` always `stoId` + unconditional `table.put` (shadowing
     overwrite), matching the original bucket-chain's unconditional insert.
   - After that fix, golden tests still failed 100%, but only on a
     *second* process invocation (i.e. loading a previously-dumped `.x`
     file, not fresh compilation) — a dump/undump round-trip bug, not a
     bootstrap bug. Root cause: `mkprivate` mutates a privatised
     identifier's name in place (`strtab.privatize`, which flips the top
     bit of the first byte) but leaves the node's *tag* and *binding*
     alone — the legacy `namebucket`'s `hash()` masks away exactly that
     bit before taking `& 127`, so a privatised name lands in the *same*
     bucket its un-privatised self was already chained in; combined with
     the bucket scan comparing each candidate's *live* `getId()` against
     the sought text, this gave two lookups for the price of one: the old
     (plain) name silently stops matching (correctly hidden), while the
     new (privatised) name — exactly the bytes `dumpOb`'s `.ID` case writes
     for any live reference to the node, e.g. `trans.zig`'s
     `ap(rt.rs().concat, e)` embedding `rt.rs().concat` directly into a
     compiled list-comprehension graph — still finds it. `SymbolTable`,
     keyed by a name fixed at insertion time, cannot reproduce that
     duality implicitly. Fixed by making `mkprivate` explicit about both
     halves: remove the old-name entry, then insert a new entry keyed by
     the post-privatisation (garbled) name pointing at the same node.
     Verified against a real repro (`miralib/ex/divmodtest.m`, which uses
     `concat` internally via list comprehensions): compile fresh, then run
     the resulting `.x` five times in a row.
   Verified with the full battery: `main-tests` (250, direct binary run
   per the `--listen=-` quirk), `test-golden` (all pass except the
   pre-existing, unrelated `script_syntax_err` off-by-one, confirmed
   present on unmodified HEAD too), `test-mira` (3 consecutive clean runs —
   this suite reuses the same `miralib/*.x` cache across all its cases
   sequentially, so it's a stronger dump/undump stress test than golden),
   `test-spine`, `test-sigint`, `test-smoke`. `test-regression` skips (no
   `mira_original` C binary in this environment). Scorecard: two metrics
   rose and the baseline was bumped with justification (not a false
   positive, a real and expected consequence, confirmed with the user
   first) — `current_interp references` 34→36 (`symbols.zig`'s new `syms()`
   accessor follows the exact existing `heap.heap()`/`core_state.s()`
   pattern for interp-owned singleton state; every new field on `Interp`
   costs one of these until Phase 4 removes the global entirely) and
   `[*:0] C-string types` 253→255 (`mkprivate`'s two new `getId(heap, ...)`
   calls, in a `parser/lex.zig` file not yet migrated to native strings —
   that's Phase 2's target, not this step's).
   **Not yet done:** `codegen.zig`/`trans.zig` still call `lex.findid`/
   `makeId` directly rather than `symbols.zig` — those now happen to be
   thin wrappers over `SymbolTable`, but the indirection through
   `lex_state.LexState` (`pnvec`/`PNBASE`/`nextpn`) is still live and
   untouched; `PrivateNames` (symbols.zig) is still unused by production
   code (`dump.zig`'s `privatise`/`publicise` still call `lexs.pnvec`
   directly, unchanged). Step 7/8 (flip `parser_api.zig`, delete the legacy
   lexer) still requires the syntax/ pipeline wiring from steps 5-6's
   "not yet done" list above, independent of this dictionary swap.
7. Flip `parser_api.zig` to the native pipeline as the only path; keep the legacy
   lexer behind a build flag (`-Dlegacy-lexer`) for one commit window for
   differential debugging.
8. Delete `lex.zig`, `lex_bridge.zig`, `lex_state.zig`, the `-Dlegacy-lexer` flag,
   `LexState` from `Interp`, `fileq`/`insertdepth`/`s_in` from the parse path, and
   the dictionary-space config (`DICSPACE`, `-dic` flag: accept-and-ignore with a
   deprecation note, since `.mirarc` files may set it).

   **Step 7 landed (2026-07-06).** `parser_api.zig`'s `parseCurrent` now
   dispatches to a new `parseCurrentNative` by default (`Source` →
   `lexer.tokenizeWithDirectives` → `applyLayout` →
   `Parser.initWithDirectives` → `parseScript`/`codegenScript`), with
   `-Dlegacy-lexer` forcing the old `parseCurrentLegacy` (`lex_bridge` +
   `parser.zig`, unchanged) for differential debugging — both share a new
   `runParsedTokens` tail (command-mode expression eval or full-script
   codegen + diagnostics). `parseWithNew` (string-only, only used by
   `parser_tests.zig`) is untouched, still legacy-bridge-fed.

   Getting a real end-to-end flip working (not just "compiles") surfaced
   five real bugs, each found by actually running scripts through the
   flipped pipeline, not by inspection — the same "verify against the real
   system" pattern as every other step this phase:
   1. **REPL line boundaries.** The native pipeline needs a whole buffer up
      front (`Source` isn't streaming); naively draining `rt.rs().s_in`
      until EOF is correct for a whole script file but wrong for the
      interactive command-mode prompt, which reads **one line** at a time
      from a long-lived stdin shared across many `parseCurrent` calls —
      draining the whole stream on the first REPL line silently swallowed
      every later line. Fixed: `slurpCurrentStream` takes a
      `stop_at_newline` flag, true for command mode.
   2. **`s_in` never resets to stdin after a whole-file compile.** Legacy's
      `yylex()` does this as a side effect of `lexEndOfFile()` popping the
      last entry off the file queue mid-scan (`rt.rs().s_in =
      getStdin()`) — a real, if easy to miss, character-level side effect
      with no equivalent moment in a batch/slurp model. Without replicating
      it, every REPL prompt after the initial script compiled read from the
      now-exhausted script file and got instant EOF forever. Fixed:
      `parseCurrentNative` explicitly closes and resets `s_in` once a whole
      file (not a REPL line) is fully read.
   3. **`driver/repl.zig`'s command loop reads `lexs.c`** (the legacy
      lexer's single-character lookahead) after `parseCurrent()` returns, to
      decide whether the line held trailing garbage — a postcondition the
      native pipeline never touches otherwise. Fixed: `parseCurrentNative`'s
      command-mode success path sets `lex_state.ls().c = '\n'` explicitly,
      satisfying the same contract the legacy lexer left as a side effect.
   4. **Tab columns.** `syntax/source.zig`'s `Source.position()` computed
      columns as raw byte offsets — never expanding tabs — since it was
      first written; nothing exercised a *real*, tab-indented script
      through the full pipeline until this step. `miralib/prelude`'s
      `cutoff` function (tab-indented `where` block) immediately
      mis-aligned the offside margin comparison. Fixed: `position()` now
      expands tabs to the next multiple-of-8 column, matching `lex.zig`'s
      `getch()` — relative to column 1 rather than `getch()`'s current
      left-verge (`lverge`), since this module has no layout/margin state
      to consult; the offside rule only ever compares two columns computed
      the same way, so lines sharing an identical tab/space prefix still
      align correctly under this simpler assumption (see `position()`'s own
      doc comment for the one case this wouldn't cover).
   5. **A bare `/` was never tokenized.** `syntax/lexer.zig`'s `next()`
      switch never had a case for it — `token_filter.zig` already had
      `.slash` defined (anticipating this), but nothing ever produced it.
      An oversight from the original step-2 scanning work, invisible until
      a script that actually uses division (`miralib/ex/divmodtest.m`,
      `a/b`) ran through the native lexer. `//` (`word.DIAG`,
      "diagonalise") has no `TokenId` or `lex_bridge.zig` mapping at all —
      confirmed out of scope, not part of this fix.

   Also newly implemented (not a bug fix, a real gap the flip exposed):
   **`%insert`'s actual textual splicing.** `directives.zig` always
   documented `%insert` as "a `Source`-level concern, splicing another
   file's bytes in place" but nothing did the splicing — the directive was
   scanned and recognized (`.unsupported`) but never actually spliced,
   so `tests/golden/directive_insert` (a real, previously-passing golden
   case) produced a malformed AST and crashed with a stack overflow in
   `trans.zig`'s `scanpattern`. Fixed: a new `Source.resolveInserts`
   (recursive, depth-capped at 12 matching `lex.zig`'s own
   `insertdepth < 12`) splices the target file's bytes in place of the
   `%insert "path"` directive, called on the raw bytes before `Source.init`
   runs. Resolves `"..."`-form paths relative to the including file's own
   directory; `<...>`-form (miralib-relative) is not resolved (not
   exercised by the shipped corpus, matching `%include`'s own unresolved
   path-resolution gap). **Known limitation:** legacy attributes
   diagnostics inside an inserted file to that file's own line numbers (a
   per-file stack, restored when the insert ends) and continues the outer
   file's count correctly afterward; this straight splice does neither —
   not observed to matter for the shipped corpus, but a real gap if a
   diagnostic ever needs to point inside or after an insert.

   **Diagnostic routing, also newly discovered:** legacy's error reporting
   is not uniform. The shared `syntax()` helper (`compiler/setup.zig`)
   writes to *stderr* with a "syntax error: " prefix it adds itself; other
   call sites (`errclass()`'s string/char-const escape errors,
   `directive()`'s "unknown directive") print directly to *stdout*, ad hoc,
   sometimes with "syntax error: " already baked into the literal,
   sometimes not — and only the *first* such diagnostic ever prints
   (`syntax()`/`acterror()` both guard on `SYNERR != 0`). `syntax/lexer.zig`
   and `syntax/directives.zig`'s own `Diagnostic` types gained a
   `stream`/`add_prefix` pair (a shared `DiagnosticStream` enum lives in
   `token_filter.zig`, for the same import-cycle reason `Directive` does)
   so each diagnostic carries its own exact routing; `parser_api.zig`'s new
   `reportLexerDiagnostic` replays it. `decodeEscape`'s error cases became a
   structured `EscapeErrorKind` (mirroring `errclass()`'s `val` codes)
   instead of a plain string, since the exact wording needs string/char-const
   *context* the decoder itself doesn't have.

   **Verified with the full battery:** `main-tests` (265), `test-mira`,
   `test-spine` (full corpus, including `directive_insert`), `test-sigint`,
   `test-smoke` all green. `test-golden`: all pass except three narrow
   diagnostic-wording gaps and one pre-existing, unrelated bug —
   **not fixed, explicitly deferred:**
   - `lex_err_bad_escape`, `lex_err_unterminated_string`: the *primary*
     message (stdout for the escape error, or stderr for the
     non-escaped-newline case) now matches legacy exactly, but the
     *secondary* stderr line these goldens also expect
     (`"{line}:{col}: syntax error at {line}:{col} - unexpected token"`,
     `parser.zig`'s own diagnostic format) does not appear. In legacy, this
     second diagnostic comes from the *parser* noticing leftover tokens
     after a lexer error left the token stream in a recoverable-but-odd
     state (character-at-a-time recovery); this native lexer abandons the
     token immediately (`.error_tok`) instead, so `parseExpr` fails
     directly rather than reaching that "trailing tokens" check. A real
     architectural difference in error-recovery strategy, not a wording
     typo — needs its own design decision, not a quick fix.
   - `lex_err_unknown_directive`: the directive's own message
     (`"syntax error: unknown directive \"%bogus\""`, stdout) now matches
     exactly, but the golden also expects `"error found near line 1 of
     file \"...\"\ncompilation abandoned\n"` (from `resetLex()`,
     stderr) plus a later `"UNDEFINED NAME - x"` runtime message —
     `directive()` itself never calls `acterror()`/`syntax()`, so this
     must come from *something else* going wrong afterward in legacy
     (unclear what without more archaeology) that this port doesn't yet
     reproduce.
   - `script_syntax_err`: confirmed pre-existing on unmodified `main` (see
     the step-6 entry above) — an unrelated, already-known off-by-one in
     `parser.zig`'s own line reporting for a specific syntax-error shape,
     not something this step introduced (its exact wrong line number did
     shift, from a different tokenizer producing a different token
     sequence around the error point, but it was already wrong before).
     Still open, still unrelated to the lexer-diagnostic-routing gaps
     below — deliberately not touched by the decision that follows.

   **Formally accepted (2026-07-06, confirmed with the user), not fixed:**
   the three lexer-diagnostic-wording gaps above are a genuine, permanent
   architectural difference (character-at-a-time error recovery leaving a
   still-parseable trailing token for the parser to also complain about,
   vs. this lexer's `.error_tok`-and-abandon strategy; a legacy
   `directive()`/`resetLex()` follow-on message never fully traced to its
   source) rather than a bug to keep chasing — re-fixing them would mean
   either reintroducing character-level recovery (undoing the batch-lexer
   design step 2 deliberately chose) or reverse-engineering an
   under-documented legacy control path for cosmetic parity alone. Pinned
   the native pipeline's own (still correct, just differently-worded)
   output as the new golden expectation: `lex_err_bad_escape`'s stderr is
   now empty (the primary "unrecognised escape" message alone, on stdout,
   already conveys the error — no secondary parser diagnostic follows
   since there's no trailing token to notice); `lex_err_unterminated_string`
   drops the secondary parser line for the same reason;
   `lex_err_unknown_directive`'s stderr is now exactly `"UNDEFINED NAME -
   x"` (the directive's own "unknown directive" message already appears
   correctly on stdout; the "compilation abandoned" follow-on legacy
   printed here never had a traced cause and isn't reproduced). This
   clears step 8's gate — see below.

   Scorecard: two metrics rose and the baseline was bumped with
   justification (confirmed with the user first, not a false positive) —
   `printf-family calls` 383→389 (`word.print`/`word.printErr` calls
   replicating legacy's exact diagnostic routing) and `ambient
   singleton-accessor call sites` 1403→1409 (`rt.rs()`/`core.s()` reads the
   old `lex_bridge` path didn't need in `parser_api.zig` directly).

**Status as of 2026-07-06:** steps 1–4 landed, steps 5–6 partially landed
(`syntax/source.zig`, `syntax/lexer.zig`, `syntax/layout.zig`,
`syntax/differential_test.zig`, `syntax/directives.zig`,
`semantics/symbols.zig`, `semantics/modules.zig` — 72 new tests total, all
green, no leaks, including every non-gap golden `.m` script —
auto-discovered, not hand-picked — plus `miralib/ex/fib.m` verbatim, all
verified byte-for-byte against the real production tokenizer), none yet
wired into `parser_api.zig` or each other. Three lessons from this session,
each general enough to apply for the rest of the plan, not just Phase 1:
(1) a from-scratch design (`layout.zig`'s first cut) needs verifying against
the system it replaces, not just internal consistency — the differential
harness this step added is exactly the tool that would have caught both of
`layout.zig`'s corrections immediately, and should have been built before,
not after, hand-deriving an algorithm; (2) `zig ast-check` only catches
syntax errors — a real type error in `directives.zig`
(`std.mem.trimRight`/`trimEnd`) passed `ast-check` and a plain `zig build`
silently because nothing calls the new code from production yet, so it's
never analyzed outside test mode; every new file needs an actual
`main-tests` run; (3) before wiring into an existing subsystem
(`mkincludes`, investigated for step 5), check whether it's actually
exercised by anything first — dead code that still compiles is not a
foundation to build on, however complete it looks. Step 6's dictionary swap
(`LexState.namebucket` → `symbols.zig`'s `SymbolTable`, all three consumers —
lookup, GC marking, `%export` hiding — together) landed the same day (see the
step-6 entry above for the two dump/undump-round-trip bugs this surfaced and
how they were found/fixed); the "not yet done" list there
(`codegen.zig`/`trans.zig` still call `lex.findid`/`makeId` rather than
`symbols.zig` directly, `PrivateNames` unused, `pnvec`/`PNBASE`/`nextpn`
untouched) is real remaining work but no longer blocks anything — those are
now thin wrappers, and the risky part (three load-bearing consumers of one
data structure) is done. Step 7 (production cutover — `parser_api.zig`
defaults to the native pipeline, `-Dlegacy-lexer` escape hatch) also landed
the same day, surfacing and fixing five more real bugs only visible once
real scripts ran through the flipped pipeline end to end (REPL line
boundaries, `s_in`/`lexs.c` postconditions the legacy lexer set as sideeffects
of character-level reads, tab-column expansion, a missing `/` token case,
and `%insert`'s never-actually-implemented textual splicing) — see the
step-7 entry above for details and the three narrow, explicitly-deferred
diagnostic-wording gaps that remain (lexer-error-recovery architecture
differs from legacy's character-at-a-time model; a directive-error
follow-on message not yet traced to its source). Step 5's harder half
(actually loading/compiling an `%include`d file, real cycle detection,
free-binding substitution, path resolution) landed the same day too —
deliberately held until *after* step 7 per the user's own direction, to
avoid building throwaway glue against the pipeline about to be replaced;
see the step-5 entry above for the design and the two real bugs (a
directive-scanner position-restore bug that silently swallowed the next
declaration's first token; an avoidable `[*:0]` scorecard regression) found
landing it. The three diagnostic-wording gaps were formally accepted
(2026-07-06, confirmed with the user) rather than fixed — see the step-7
entry above for why, and the re-pinned goldens.

**Step 8 landed (2026-07-06), scope corrected on investigation.** The
plan's framing above ("delete `lex.zig`, `lex_bridge.zig`, `lex_state.zig`,
... `LexState` from `Interp`, `fileq`/`insertdepth`/`s_in` from the parse
path, ... `DICSPACE`") turned out not to match reality once actually
investigated — the same "verify before believing the plan" pattern as
every other step. A careful function-by-function and field-by-field
caller audit (grepping every call site across the whole tree, not just
lex.zig, and cross-checking against `runtime/main_clib.zig`'s re-exports —
several of lex.zig's functions are reachable under the same name through
that module, which an external-caller grep restricted to lex.zig itself
would miss) found:
- **Genuinely deletable** (the character-at-a-time tokenizer and
  everything only it needed): `yylex`, the offside `layout` rule,
  `setlmargin`/`unsetlmargin`, `%`-`directive` handling, `pathname`,
  numeral/hex/octal-numeral scanning, string/char-class scanning,
  `identifier`/`kollect`/`getch`/`getlitch`/`errclass` and a dozen smaller
  helpers — genuinely dead once `lex_bridge.zig` (their only entry point)
  is gone. ~1,400 lines deleted from `lex.zig` (2,110 → 696 lines, now
  under the scorecard's 1,000-line-file threshold), plus `lex_bridge.zig`
  (387 lines) and `syntax/differential_test.zig` (184 lines, its whole
  purpose — diffing legacy vs. native tokenizers — was step 7's own
  verification tool, moot once there's no more "legacy" to diff against)
  deleted outright, plus the `-Dlegacy-lexer` build flag and
  `parseCurrentLegacy`.
- **Not deletable — genuinely still load-bearing production code that
  happened to live in the same file**: the identifier dictionary
  (`setupdic`/`makeId`/`findid`/`keep`/`name`, used throughout
  `compiler/setup.zig`'s bootstrap), the private-name machinery
  (`makePn`/`mkprivate`, `%export`'s permanent-hiding mechanism this
  phase's own step 5 depends on), REPL-only raw token/line reading
  (`token`/`rdline`, driving slash commands — not Miranda expression
  parsing, so untouched by the tokenizer swap), value-building helpers
  (`convArgs`/`strConv`) the reducer calls directly, and `openfile`/
  `dicCheck`/`adjustPrefix` (called via `main_clib.zig`'s re-exports from
  `module_loader.zig`'s real file-loading path and `driver/lineedit.zig`'s
  tab completion). `LexState` similarly stays close to its current shape —
  `fileq`/`dic`/`dicp`/`dicq`/the GC-root stacks/`ARGC`/`ARGV` are real,
  live production state, not tokenizer-internal scratch; only ~20 fields
  that were exclusively read/written by the deleted tokenizer
  (`insertdepth`'s reader — not its writer, still harmlessly written by
  `openfile`/`resetLex` — `lmargin`, `col`-adjacent scanning flags,
  `tok_start_col`, `blankerr`, `rawch`, `errch`, `lastc`, `sl`,
  `namebucket` (superseded by `symbols.zig` back in step 6, but left
  sitting unused until now), etc.) were actually removable. `fileq`/`s_in`
  themselves are `module_loader.zig`'s current production file-I/O layer
  (`word.FILE`-based), a separate concern from tokenization — replacing
  *that* is Phase 2's job ("native I/O & diagnostics"), not this step's.
  `DICSPACE`/`-dic` likewise remain live, active configuration for the
  (still-needed) dictionary, not dead weight.
- Also migrated in the same pass: `parseWithNew` (`parser_tests.zig`'s
  string-input entry point, previously always legacy-bridge-fed regardless
  of `-Dlegacy-lexer`) now goes through the same native pipeline as
  `parseCurrentNative`, gaining `%include` processing and lexer
  diagnostics for free; a shared `reportIncludeError` helper avoids
  duplicating `parseCurrentNative`'s diagnostic call sites (this would
  otherwise have been a `printf-family calls` scorecard regression —
  avoided instead of bumped, confirmed with the user). `parser_tests.zig`
  lost `captureTokenStream`/`runSnapshotTest` and the "golden/error
  snapshot tests" that existed specifically to test `yylex`'s token
  stream — meaningless once `yylex` is gone, redundant with
  `syntax/lexer.zig`'s own unit tests and `test-golden`. Its orphaned
  `tests/parser/snapshots/*.snapshot` files went with them. "prelude
  parsing test" (`parseFile`'s only caller) was rewritten to read the file
  directly and call `parseString`, letting `parseFile`/`lex.setupFile`
  drop too without inventing a replacement file-opening path for a
  single test.
- Two pre-existing bugs surfaced and fixed along the way, unrelated to the
  deletion itself: `parser_api.zig` had three `core.s.SYNERR = 1` sites
  missing the `()` call (a copy-paste-shaped typo predating this session,
  confirmed via `git log`) — harmless under a plain Debug build but a hard
  compile error under `-Dstrict`, caught by building the strict variant as
  part of this step's verification; and `lex.zig`/`parser_tests.zig` both
  already failed `zig fmt --check` before this session touched them
  (confirmed by stashing and re-checking) — reformatted as a low-risk
  courtesy since both files were already being heavily edited.

  Verified: `main-tests` (256), `test-mira`, `test-spine`, `test-smoke`,
  `test-golden` (only the pre-existing, unrelated `script_syntax_err` gap
  fails, same as before this step) all green; `-Dstrict` and `zig build
  strict` both build cleanly (the latter's remaining two failures —
  `script_syntax_err` again, and a codebase-wide `zig fmt --check`
  non-compliance across many files this step never touched — are both
  pre-existing, confirmed via git history/stash, not regressions).
  `test-sigint` is flaky specifically when run inside the aggregate `zig
  build test`/`check` step (fails intermittently there) but passes
  reliably (3/3) standalone — pre-existing test-harness timing flakiness,
  not a logic regression (no signal-handling or fork code was touched).
  Scorecard: every tracked metric *improved* (no bump needed) —
  `ambient singleton-accessor call sites` 1412→931, `files > 1000 lines`
  10→9, `[*:0]` 251→238, `printf-family calls` 393→372, and so on across
  the board, since the deleted code was saturated with exactly the
  C-isms this whole migration tracks.

**Deletes:** ~1,970 lines total (`lex_bridge.zig` 387 + `differential_test.zig`
184 + ~1,400 from `lex.zig` + the orphaned parser-snapshot fixtures) — the
character-at-a-time C-ported tokenizer and its dedicated migration-era
verification harness. `lex.zig`/`lex_state.zig` themselves are not fully
deleted (see above); the remaining ~700 lines are load-bearing dictionary/
private-name/REPL-token machinery, not lexing.

**Gate:** golden corpus unchanged except the already-accepted step-7 gaps;
scorecard improved on every tracked metric; `main-tests`/`test-mira`/
`test-spine`/`test-smoke` green.

**Risks & fallbacks:** error-message parity (mitigated by Phase 0 goldens);
`%bnf`/`%lex` semantics (mitigated by doing it last within the phase, dual-run
harness, and the build-flag escape hatch); offside edge cases (the dual-run harness
covers the corpus, and the spine/regression suites cover semantics).

---

### Phase 2 — Native I/O & diagnostics (delete the libc)

**Goal:** all output through `std.Io`; structured diagnostics; `word.zig` shrinks to
the value vocabulary; `main_clib.zig` shrinks to `os.zig`.

**Steps**

1. **Writers.** `Interp` gains `out`/`err` buffered writers (from `ctx.io` in
   `main`, from in-memory buffers in tests). Convert the driver/REPL surface first
   (prompts, `//commands`, stats), then compiler messages, then reducer output.

   **Landed (2026-07-07), much smaller than framed.** Investigation found
   this infrastructure already ~80% built (an earlier shared-state-plan
   pass had already folded it in): `Interp.io: IoState` already holds
   buffered `stdout_writer`/`stderr_writer` (`std.Io.File.Writer`, 8KB
   backing buffers), and `word.print`/`word.printErr` — which
   `driver/repl.zig` and `driver/commands.zig` already call exclusively,
   no ambient `FILE*`/libc calls — already route through them. The one
   real gap: `word.zig`'s `initWriters()`/`fopen()`/`fclose()` were
   hardcoded to `std.Options.debug_io` instead of `runtime_state.zig`'s
   `io` var (set from `ctx.io` in `main.zig`) — harmless today since both
   resolve to the same implementation for the native CLI binary, but a
   latent inconsistency where the one module owning every writer and file
   handle silently ignored the process's actual `std.Io` context. Fixed
   via an inline `@import` (`procIo()`, matching the existing `fio()`
   pattern) rather than a top-level `const` import, since `word.zig` is a
   leaf module every other file imports freely and `runtime_state.zig`
   imports `main_clib.zig` which imports `word.zig` back — a top-level
   import would cycle. Steps 3-5 (format conversion, ctype/string-helper
   deletion, `main_clib.zig` → `os.zig`) are unaffected and still ahead.

2. **Diagnostics.** Promote the parser's `Diagnostic{span, message}` to a shared
   `Diagnostics` type (list + counts). Replace `SYNERR`/`errs`/`errline`/`errcol`
   with it: `errs`'s second life as a "current compile position breadcrumb" for
   runtime error reporting becomes an explicit `last_position: Span` field —
   the two unrelated purposes the old survey found get two named homes.

   **Landed (2026-07-07), scope narrowed after investigation (confirmed
   with the user).** A full-tree caller audit found `errs` far more deeply
   coupled than "replace it" suggests: it's a heap `FILEINFO` cons cell
   `(file . line)`, read via `h()`/`t()` by 12 sites in `compiler/trans.zig`
   alone, plus `compiler/types.zig`, `runtime/reduce.zig`, and
   `parser/lex.zig`'s `resetLex` (trimmed just last session in Phase 1 step
   8) — each with a load-bearing "first-error-wins" `== 0` guard. Fully
   retiring it in one pass, as the plan's wording implies, would mean
   touching all of those simultaneously — a large, deep, cross-cutting
   risk disproportionate to one step. Landed instead, confirmed with the
   user: **(a)** the three independently-defined, near-identical
   `Diagnostic` structs (`parser/parser.zig`, `syntax/lexer.zig`,
   `syntax/directives.zig` — the first missing the other two's `stream`/
   `add_prefix` routing fields) converged on one shared type in
   `parser/token_filter.zig` (already the zero-dependency home `Span`/
   `DiagnosticStream` live in, for the same import-cycle reason), each
   site now a one-line re-export; **(b)** `parser/diagnostics.zig` — a
   fourth, differently-shaped, never-actually-integrated "modern
   collector" (`severity`/`line`/`column` fields, a `Diagnostics` type
   with `addError`/`addWarning`/`addNote`) whose only caller anywhere was
   `main.zig`'s test-aggregator import — deleted outright, since leaving
   a second, dead, incompatible "Diagnostic" type around would undercut
   the entire point of converging on one; **(c)** `CoreState` gains
   `last_diagnostic_message: []const u8 = ""`, populated additively by
   `parser_api.zig`'s four diagnostic-reporting sites (`runParsedTokens`
   and `parseWithNew`, one lexer-diagnostic and one parser-diagnostic path
   each) alongside the existing `errline`/`errcol` writes — first
   diagnostic wins, matching their existing semantics. The message text is
   arena-backed at the point it's reported (the same arena
   `parseCurrentNative`/`parseWithNew` frees on return), so
   `recordDiagnosticMessage()` duplicates it with `rt.allocator` before
   storing — deliberately leaked, same convention as `lex.zig`'s `keep()`
   permanently retaining dictionary strings, matching this field's
   "one message per failed compile, for the life of the process" role.
   `core_state.zig` deliberately has zero source-tree imports (its own
   header's G1 acyclic invariant, so `heap.zig`/`parser_api.zig` can reach
   it without a cycle), so the new field is a plain `[]const u8`, not the
   shared `Diagnostic` type itself — callers copy just what they need.
   **Not done — deliberately deferred, a separate future step:** `errs`
   itself, and `trans.zig`/`types.zig`/`reduce.zig`/`resetLex`'s existing
   usage of it, are completely untouched; `last_diagnostic_message` is not
   yet read by anything (a foundation for a future step, same as
   `syntax/`'s early landings coexisted unread by production code for
   several steps before their own cutover).
3. **Format conversion.** Mechanically convert the ~320 C-format call sites
   (`%s`/`%d`/`%ld` → `{s}`/`{d}`), dropping the `.{.{a}}` tuple convention. Module
   by module; a temporary comptime C-format shim is permitted mid-phase and deleted
   at the end. Miranda's number printing (`%g`-family in `shownum`/`outTerm`) gets a
   dedicated `formatMiraFloat` helper replicating current output digit-for-digit
   (golden-gated).

   **Landed (2026-07-07), and the "~320 sites" scope corrected.** The
   scorecard's "printf-family calls" metric double-counts two very
   different things: real `printf`/`fprintf`/`sprintf` calls (interpreted
   at runtime by `main_clib.zig`'s C-format engine, `formatC`) and
   `word.print`/`word.printErr` calls — but the latter already require
   comptime Zig format strings (Zig won't compile a bare `%s` there), so
   357 of the ~372 sites were already effectively converted; only ~13 real
   C-format call sites remained. Landed in four parts:
   - Dropped the `.{.{a}}` double-wrapped tuple convention (6 real call
     sites, all now written directly) and, once nothing needed it, deleted
     `word.print`/`word.printErr`'s comptime unwrap branch that tolerated it.
   - Converted the four non-float `sprintf` sites (`driver/commands.zig`'s
     `manaction`/`editfile` line-and-column-placeholder substitution,
     `driver/startup.zig`'s logfile name) to `std.fmt.bufPrintZ`/`bufPrint`.
   - The four float-formatting `sprintf` sites (`runtime/reducer/ready.zig`'s
     `SHOWNUM`/`SHOWHEX`/`SHOWSCALED`/`SHOWFLOAT`) — the plan's own flagged
     risk item. Investigation found `formatC`'s float-formatting case
     (`'f'/'g'/'e'/'a'`) already discarded the C specifier and the
     `precision` parameter entirely (a literal `_ = precision;` in
     `formatArg`), always calling `std.fmt.bufPrint(&buf, "{d}", .{val})`
     regardless — so `SHOWNUM`'s `%.16g` was **already** Zig-native
     under the hood; a direct `std.fmt.bufPrint(..., "{d}", ...)` port
     (`formatMiraShowNum`) is confirmed byte-identical across a range of
     representative values (matching `formatC`'s own already-broken
     handling of astronomical magnitudes too — both silently produce
     nothing past a certain exponent, `formatArg`'s internal 128-byte
     scratch buffer being far smaller than a full decimal expansion of
     e.g. `1e300` needs; not fixed, out of scope, no golden coverage).
     `SHOWFLOAT`/`SHOWSCALED`/`SHOWHEX`, though, were **completely
     broken already** — `formatC`'s `%.*` (read-precision-from-args)
     parsing didn't handle the `*` form at all, producing literal
     `?INVALID_SPECIFIER?f` garbage for every call, and `%a` fell through
     to the same ignore-everything decimal case as `%g` (printing a
     *decimal* number for what's documented, `docs/man/mira.man.ms`, as a
     hex-float builtin). Fixed properly rather than mechanically
     preserving broken output: `formatMiraFixed`/`formatMiraScaled` use
     Zig's own runtime-precision format specifiers (`{d:.[1]}`,
     `{e:.[1]}`); `formatMiraScaled`'s scientific notation and
     `formatMiraHex`'s hex-float both need a small postprocessing step
     (`toCScientificExponent`) since Zig's bare exponent (`e5`, `p1`) needs
     a C-mandated sign (`e+05`, `p+1`) — `%e`'s convention also requires a
     2-digit floor (`%a`'s doesn't). `formatMiraHex` is verified against
     `docs/man/mira.man.ms`'s own worked example (`showhex pi =>
     0x1.921fb54442d18p+1`) byte-for-byte; `formatMiraScaled`'s exponent
     convention is verified against the C standard's own `%e` specification
     (mandatory sign, 2-digit floor) rather than a live reference binary
     (none was available in this sandbox) — the one part of this step
     without an executable oracle, flagged as such in the code itself.
     11 new unit tests across all four helpers.
   - `errors.zig`'s `fatal()` (`noreturn`, print-then-`exit(1)`) was the
     last genuine C-format consumer: its own `fmt` parameter was runtime
     `[*:0]const u8`, not comptime, so all 16 call sites across
     `driver/startup.zig`/`repl.zig`, `io/files.zig`, `parser/lex.zig`,
     `compiler/dump.zig`/`module_loader.zig` passed real `%s`-style format
     strings. Converted `fatal`'s `fmt` to `comptime []const u8` (matching
     `word.print`/`word.printErr`) and every call site's format string and
     arg tuple.

   Not yet done (deliberately, follow-on work): `main_clib.zig`'s
   `printf`/`fprintf`/`sprintf`/`formatC` engine itself, and `word.zig`'s
   `FILE` struct/pool/ctype predicates/string helpers — step 5's charter,
   gated on nothing calling them anymore, which is now true except for
   incidental internal uses (`fopen`/`fclose`/`getc`, `fmemopen` for dump
   reading) that belong to step 4 (Streams). `ready.zig` crossed 1,000
   lines (996 → 1,003) adding the four `formatMira*` helpers plus their
   tests — the scorecard's "files > 1000 lines" check still passes (the
   recorded baseline ceiling is 10, unchanged since before Phase 1 step 8
   lowered the *actual* count to 9; this uses up that slack rather than
   requiring a bump, but is worth noting rather than leaving silently
   implicit).
4. **Streams.** `eval/stream.zig`: a `Stream` over `std.fs.File` with pushback,
   plus a fixed-buffer variant (replaces `fmemopen` remnants). Port `READ`/
   `READBIN`/`READVALS`, `Tofile`/`Appendfile` (`outfilq`), and dump/undump file
   I/O in `heap.zig`/`dump.zig`.

   **Landed (2026-07-07), scope split after investigation (confirmed with
   the user).** A full-tree audit found real, structural risk beyond what
   "port to a Stream" suggests: `FILE*` pointers are embedded as raw
   `@intFromPtr`/`@ptrFromInt` casts inside three separate heap cons-lists
   (`lex_state.zig`'s `fileq`, `reduce.zig`'s `EvalState.outfilq`, and
   `READ`/`READVALS`'s own lazy stream cells in `reduce.zig`'s
   `streamRead`) — a genuine redesign of that representation, not a
   type-level swap, and the binary `.x` dump format (`heap.zig`'s
   `dumpOb`/`loadDefs`) is byte-order-sensitive with (before this step)
   only one unit test covering round-trip, and none checking byte-for-byte
   stability. Landed in three parts, each verified independently, deferring
   the actual cell-embedding redesign and the `FILE`→`Stream` rename to a
   later, dedicated pass:
   - **Prerequisite:** a real CLI-level dump/undump round-trip test
     (`tests/mira_tests.zig`'s `caseDumpUndumpRoundTrip`) — compiles a
     script exercising a spread of `dumpOb`'s node kinds once from source,
     then again unchanged so `undump` takes the fast reload path (both
     confirmed by reading `module_loader.zig`/`dump.zig` directly, not
     assumed), asserting matching stdout *and* a byte-identical `.x` file
     across both runs. This is the safety net the rest of step 4 (and any
     future Stream work) checks against.
   - **Format-conversion cleanup, discovered while scoping the move:**
     two real `snprintf` call sites step 3's own grep missed (it only
     matched `sprintf`, not `snprintf`) — `driver/startup.zig`'s
     `versionString` and `driver/commands.zig`'s `editfile`. Converting
     the first surfaced a fourth real, pre-existing float-formatting bug
     matching `showfloat`/`showscaled`'s: `formatC`'s float case ignores
     precision entirely, so `versionString(2000)` silently produced `"2"`
     instead of `"2.000"` — the existing two-case test happened not to
     exercise a trailing-zero value. Fixed with Zig's own `{d:.3}`.
   - **Dead-code deletion:** with those two converted, `printf`/`fprintf`/
     `sprintf`/`snprintf` (and the `formatC`/`formatArg` engine plus
     `BufferWriter` they're built on — duplicated near-identically in both
     `word.zig` and `main_clib.zig`) had zero real callers left anywhere,
     confirmed via a whole-tree grep. Deleted both copies outright, plus
     `fmemopen` and the standalone `flush()` (both already confirmed dead
     earlier this phase), rather than moving dead code into a new
     abstraction. `word.print`/`word.printErr`/`word.fprint` (the last
     still used extensively by `heap.zig`'s dump/`outTerm` pretty-printer)
     are unaffected.
   - **The move:** `FILE`, `IoState`, and every stdio-shaped operation
     built on them (`fopen`/`fclose`/`fileno`/`setbuf`/`getc`/`getchar`/
     `ungetc`/`fgets`/`fread`/`fwrite`/`fdopen`/`putc`/`putchar`, `fio()`,
     `initWriters`/`print`/`printErr`/`fprint`, `stdin`/`stdout`/`stderr`)
     moved from `word.zig` to a new `runtime/stream.zig` (the current-tree
     equivalent of the plan's aspirational `eval/stream.zig` — no `eval/`
     directory exists yet; that's Phase 4's "moves" step) — a pure
     relocation, same names, `word.zig` re-exporting every one so no other
     file's imports needed to change. `word.zig` shrank from ~1,720 to
     ~1,060 lines (with the dead-code deletions above also counted).
     First extraction attempt swept in ~280 unrelated lines (the
     `strcpy`/`strcat`/`strcmp`/... string helpers, interspersed in the
     original file between `FILE`'s definition and the rest of the stdio
     block) — caught immediately by the build (`"no member named
     strcpy"`) and moved back to `word.zig` before proceeding.
   **Not done — deliberately deferred at the time (the `FILE`→`Stream`
   rename itself landed later this same step, once the GC-safety crash
   below was fixed — see further down):** kept the name `FILE` to avoid
   touching call sites in the same pass that moved their import path;
   the actual redesign of the `fileq`/`outfilq`/`streamRead` cell-
   embedding pattern (still raw pointer casts, now `wrapPtr`-wrapped
   rather than embedded bare — see the GC-safety fix below — but still
   pointers, not pool-slot indices); the fixed-buffer `Stream` variant
   (`fmemopen`'s replacement —
   moot, since `fmemopen` itself was already dead); and "porting"
   `READ`/`READBIN`/`READVALS`/`Tofile`/`Appendfile`/dump-undump to
   anything new — they call the exact same functions as before, just via
   the new file's re-exported names.

   **Landed (2026-07-07), a second pass: test-first coverage for the
   deferred hard parts, plus two real bugs it surfaced (confirmed with
   the user before fixing).** Before attempting the `fileq`/`outfilq`/
   `streamRead` redesign, built the promised regression coverage first
   (`Tofile`/`Appendfile`/`Closefile`/`read`/`readvals` had zero test
   coverage anywhere in the tree) — and found the redesign's premise
   was more urgent than scoped: an Explore agent's "handle-based
   redesign is low-risk, zero dump-format impact" assessment was
   correct about the dump format but missed a live crash. Found via
   direct experimentation against the real binary (matching this
   session's established "run it before writing the test" discipline):
   - `Tofile fil string` (`runtime/reduce.zig`'s `output()`) only
     switched the output stream (`outf`) and silently dropped `string`
     instead of writing it — contradicting the manual's documented
     behavior (`"the characters of the string are transmitted to the
     file"`). Fixed by also calling `print(eval, rs, t(h(e)))` after
     `outf`, matching `Stdout`'s own case shape.
   - `sum (readvals "file")` on trivial input (`"1\n2\n3\n"`) crashed
     with `heap.validate: cell ... (tag AP) has out-of-bounds tl
     reference <huge number>` — heap corruption, not a hang or a clean
     error. Confirmed via a throwaway `git worktree` at an earlier
     commit that this predates the whole session (undiscovered only
     because nothing ever exercised it). Root-caused (a first hypothesis
     — a missing `lastexp` save/restore across `streamRead`'s reentrant
     call into `parseLine`/`parseCurrent`/`evaluateRepl` — was tested
     and empirically ruled out; the corruption was already present
     before the reentrant call's own first `validate()` ran) to
     `Heap.mark`/`Heap.validate` (`runtime/heap.zig`): both walk a
     cell's tail as a chase-able reference whenever its tag ordinal is
     `>= NodeTag.INT`, with no way to know a particular field holds a
     disguised raw pointer instead. `STARTREAD`/`STARTREADBIN`/
     `STARTREADVALS`/`system`'s pipe-reading `EXEC` handler, plus
     `streamRead`'s own per-character chain-building, all embed a raw
     `FILE*` directly in an `AP`-tagged cell's tail (`AP`'s ordinal is
     above both thresholds) — reusing the reduction spine's own cell,
     unlike `fileq`/`outfilq`'s dedicated `DATAPAIR`-wrapped entries
     (`DATAPAIR`'s ordinal sits below both thresholds, so `mark`/
     `validate` never look inside one). Any GC landing while such a
     cell is reachable tries to treat the pointer bit pattern as a cell
     index and panics. `readvals`'s own per-value reentrant parse+
     codegen+typecheck+fork cycle allocates enough to make hitting this
     nearly certain (which is how it was found); `read`/`readb`/
     `system` share the identical hazard, just less reliably — confirmed
     the hard way when `system_exec`'s own spine-differential
     regression test caught an incomplete first pass that only patched
     `streamRead`'s sites and missed `handleReadyEXEC`'s pipe-opening
     ones (`reducer/ready.zig`). Fixed with `wrapPtr`/`unwrapPtr`
     (`runtime/reduce.zig`): wrap the raw pointer in a `DATAPAIR` cell
     before storing it — extending the exact pattern `fileq`/`outfilq`
     already used to the sites that had instead reused the spine's own
     `AP` cells directly. A whole-tree `@intFromPtr` grep after the fix
     found no other unwrapped write sites.
   - Added the missing regression coverage: `caseTofileAppendfileRoundTrip`
     and `caseReadvalsSurvivesGcPressure` (`tests/mira_tests.zig`), the
     latter run under `-heap 100` — the minimum accepted heap size — to
     force real GC pressure rather than relying on a lucky pass.
   - **Noted but deliberately not fixed:** `readvals`'s reentrant
     `parseLine` call reuses the *full* `evaluateRepl` (fork + reduce +
     default-output-mechanism print + exit) just to parse-and-typecheck
     one value, so every value read is also echoed to stdout as a side
     effect (confirmed harmless — no crash, no corruption — but
     surprising, and almost certainly not the intent of a "just parse
     this value" helper). Fixing it properly means changing `parseLine`
     to skip the fork/reduce/print ceremony entirely, which overlaps
     substantially with Phase 3 step 3's planned checkpoint/restore
     replacement for fork-per-eval — attempting it now would likely be
     redone by that work. The new `caseReadvalsSurvivesGcPressure` test
     asserts today's actual (echoing) output, not the eventually-correct
     one, so Phase 3 will need to update that assertion once
     fork-per-eval is gone.
   - **`FILE`→`Stream` rename, landed.** With the GC-safety crash fixed
     at its root, the rename deferred earlier in this same step was low
     enough risk to do immediately: `runtime/stream.zig`'s `FILE` struct
     (and every `word.FILE`/`abi.FILE`/`?*FILE`/`*FILE` call site across
     the tree — 15 files, ~120 sites) renamed to `Stream`, via `perl -pe
     's/\bFILE\b/Stream/g'` per file (word-boundary-safe, so `FILEINFO` —
     an unrelated, pre-existing tag name — is untouched) followed by a
     full rebuild to catch anything the mechanical pass missed (it
     needed one follow-up: `tests/utf8_tests.zig`, a test-only file the
     first tree-wide grep's file list omitted). Pure rename, zero
     behavior change — the cell-embedding representation itself (still
     `wrapPtr`-wrapped raw pointers, not pool-slot indices) is untouched
     and still not attempted.

   Verified: `main-tests` (245, all `FILE`/string-helper tests correctly
   relocated/retained and passing under their new module paths), the new
   round-trip test, `test-golden` (only the pre-existing
   `script_syntax_err` gap), `test-mira`/`test-spine`/`test-smoke` all
   green; manual compile-then-reload-from-dump check against the real
   binary; scorecard improved (`printf-family` 372→364, `[*:0]` and
   `c_int` both down) with no regressions.
5. **Deletions.** From `word.zig`: the `Stream` struct (renamed from `FILE`,
   Phase 2 step 4) + pool, `fopen`/`fclose`/
   `getc`/`ungetc`/`fflush`, the printf engine, ctype predicates (→ `std.ascii`),
   `strcmp`/`strlen`/`strcpy` (→ `std.mem`). `word.zig` ends ≤ ~600 lines of value
   vocabulary. Rename what's left of `main_clib.zig` to `os.zig`: signals,
   `fork`/`wait`/`execl` (until Phase 3), `sigsetjmp` (until Phase 3), rlimits.
   `malloc`-family shims die (allocator everywhere).

   **Landed (2026-07-07), ctype/string-helper half only — scope confirmed
   with the user after investigation showed the plan's assumption didn't
   quite hold.** These wrappers weren't dead/broken code like the printf
   engine (Step 3) — they were legitimate polymorphic-pointer coercions
   (`castToCStr`/`castToCStrMut` accepting `anytype` C-string-ish
   arguments, plus null handling) already delegating to `std.ascii`/
   `std.mem` internally. Converting every call site to the raw
   `std.ascii`/`std.mem` idiom directly (rather than through the wrapper)
   is more inline code at each site, not less — a real cost the plan
   didn't account for — but the user chose to do it anyway "to fully
   match the plan's original wording," so it was carried out call-site by
   call-site rather than deferred:
   - **ctype predicates** (7 real call sites total: `isspace`/`isdigit`/
     `isxdigit`/`isalpha`/`isalnum`/`tolower` across `reducer/ready.zig`,
     `parser/lex.zig`, `driver/commands.zig`) converted to direct
     `std.ascii` calls, with small local range-guard helpers where the
     source is a heap `Word`/`i64` or a `getchar()`-shaped `c_int` that
     can be out of ASCII-byte range or `EOF` (`std.ascii`'s predicates
     take a `u8`, and can't see either case directly).
   - **String helpers** (`strcmp`/`strlen`/`strcpy`/`strcat`/`strncmp`/
     `strncpy`/`strncat`/`strrchr`/`strstr`/`rindex`, ~140 real call
     sites once two file-scope `const strcmp = word.strcmp;` aliases in
     `heap.zig`/`trans.zig` were found — missed by the first grep, which
     only matched `word.strcmp(` directly, not local aliases; caught
     immediately by the build once the wrapper was deleted) converted
     file by file (`io/files.zig`, `driver/repl.zig`, `compiler/dump.zig`,
     `compiler/module_loader.zig`, `runtime/reduce.zig`,
     `runtime/reducer/ready.zig`, `parser/lex.zig`, `driver/commands.zig`,
     `driver/startup.zig`, `runtime/heap.zig`, `compiler/trans.zig`) to
     `std.mem.span`/`eql`/`len`/`order`/`lastIndexOfScalar`/`indexOf` plus
     `@memcpy` for the copy/concat sites, preserving each site's exact
     byte-level semantics — including `strncpy`'s C-style pad-not-
     terminate behavior, `strncmp`'s prefix-comparison quirk (a bounded
     compare where both operands are also truncated to `n`, so a
     shorter-than-`n` operand can still "match" — reproduced exactly in
     `commands.zig`'s `filequote`), and `hdsort`/`alfasort`'s two
     genuine *ordering* comparisons (`strcmp(...) < 0`, not equality —
     the only two of ~150 sites that weren't; converted to
     `std.mem.order(...) == .lt`). One real behavior *improvement*, not
     just a port: `commands.zig`'s `getenv("HOME")` site previously left
     a stale/uninitialized buffer untouched (and then read it back as a
     C string) when `$HOME` is unset — undefined behavior on a path with
     no test oracle — now treated as `""`, matching every other missing-
     env-var fallback already in that function. An Explore agent mapped
     every call site's argument types first (optional vs. already-
     unwrapped) to catch this kind of case before converting rather than
     after; only that one site turned out to need it.
   - Deleted `castToCStr`/`castToCStrMut` and all ten string helpers plus
     the six ctype predicates from `word.zig` once a whole-tree grep
     confirmed zero real callers remained anywhere (`word.zig`: 1,058 →
     732 lines). `strchr` (0 callers from the start) went with them.
   - **Not done:** the `FILE` struct/pool deletion (still gated on the
     Step 4 hard parts — `FILE`→`Stream` rename, `fileq`/`outfilq`/
     `streamRead` cell-embedding redesign) and the `main_clib.zig` →
     `os.zig` rename.
   - Verified: `zig build test` (256/256), `test-mira`/`test-spine`/
     `test-smoke` all green, `scripts/scorecard.sh --check` OK (no
     tracked metric rose above baseline — `printf-family` and `[*:0]`
     both still trending down from Step 3/4's work).

**Gate:** printf-family count = 0; `extern fn` reduced to the signal/process floor;
goldens byte-identical (float formatting is the watch item); scorecard `[*:0]` and
`@intFromPtr` drop sharply.

**Risks:** float-format parity (`formatMiraFloat` + goldens); output buffering/flush
order around child processes (flush before spawn; differential suite watches).

**Phase 2 complete (2026-07-07).** All five steps landed; scorecard vs. the
Phase 0/1 baseline: `c_int`-family 210→165, `[*:0]` 255→230, `@intFromPtr`/
`@ptrFromInt` 66→57, sentinel `== NIL`/`!= NIL` 345→326, files > 1000 lines
10→9, `extern fn` unchanged at 13 (already the signal/process floor) —
every metric this phase actually targets moved the right direction; none
regressed. `test-golden`/`test-mira`/`test-spine`/`test-smoke` all green
throughout (only the pre-existing, unrelated `script_syntax_err` gap).

One gate line needs a correction, not a deferral: **"printf-family count
= 0" is unreachable as literally worded and was never actually the goal**
— `scripts/scorecard.sh`'s `printf-family` metric counts `word.print`/
`word.printErr` calls alongside real `printf`/`fprintf`/`sprintf`, but
the former are `comptime`-format-string Zig-native calls (the *correct*,
permanent replacement for C's output, not a C-ism to eliminate) — of the
reported 391→364, roughly 350 are `word.print`/`printErr`; the real
C-format engine (`printf`/`fprintf`/`sprintf`/`snprintf`/`fmemopen`, ~15
genuine call sites plus `errors.zig`'s `fatal()`) was fully converted
and deleted in step 3/4. This was identified early in step 3 (see its own
landed note above) but the scorecard metric itself and this gate's wording
were never updated to reflect it — worth fixing the metric definition in
a later pass so it doesn't misreport a permanently-nonzero number as an
open gap.

**Deliberately not done, carried forward:**
- The `fileq`/`outfilq`/`streamRead` cell-embedding redesign (raw
  pointer → pool-slot index). No longer correctness-critical — the
  GC-safety crash that originally motivated this was root-caused and
  fixed with `wrapPtr`/`unwrapPtr` (step 4) — so this is now a pure
  cosmetic/structural improvement, not a bug fix. Revisit alongside
  Phase 4's "moves" work if `eval/stream.zig`'s target location makes
  the representation change natural to bundle in.
- `word.zig`'s `Stream` (and `fopen`/`fclose`/`getc`/… ) re-export
  aliases. The plan's step 5 wording implies removing these from
  `word.zig` entirely, but by the time step 4 moved the real
  implementation to `stream.zig`, the aliases are the *entire* remaining
  cost (~25 lines) — removing them requires updating every one of
  ~600 call sites (`word.print`/`printErr` alone: 365) to import
  `stream.zig` directly instead, for zero functional change. This
  contradicts the explicit design choice step 4 made ("`word.zig`
  re-exporting every one so no other file's imports needed to change")
  and was assessed as not worth undoing for a documentation-level line
  count. Left in place; `word.zig` sits at 732 lines of genuine value
  vocabulary plus this one re-export block.
- `readvals`'s per-value echo (documented under step 4's second landed
  note) — tied to Phase 3 step 3's fork-per-eval removal.

---

### Phase 3 — Structured control flow (delete setjmp/longjmp and fork-per-eval)

**Goal:** error unions are the only non-local control flow; interruption is a polled
flag; evaluation is in-process.

**Steps**

1. **Interrupt flag.** `os.zig` registers SIGINT/SIGTERM handlers that only
   `interrupt_flag.store(true, .release)`. The reduce loop already counts cycles —
   poll every N (≈4096) cycles and return `error.Interrupted`; the compiler polls
   per-definition. The REPL catches, prints the existing `<<...interrupt>>` text,
   resets via the normal (non-signal) reset path. Delete `sigsetjmp(rs.env)`,
   `siglongjmp`, `rs.env`, `jmp_buf`/`sigjmp_buf`, and main.zig's size asserts for
   them. `tests/sigint_check.zig` is the gate.
2. **SIGFPE elimination.** Audit arithmetic paths: integer division already guards
   zero (bignum); float overflow routes to `fpeError`'s *message* via an explicit
   check, not a signal. Remove FPE signal recovery.
   **Landed** (2026-07-08): `heap.zig`'s `stoDbl`/`setdbl` return
   `word.ReduceError!Word`/`!void` (a new `FloatOverflow` variant alongside
   `Interrupted` — both live in `word.zig`, the cycle-free leaf module, with
   `reduce_core.ReduceError` re-exporting it) instead of calling `fpeError`.
   The 23 runtime call sites (`reduce.zig`, `reduce_core.zig`, `ready.zig`)
   thread `try` through the already-fallible reducer; `evaluateRepl` catches
   `error.FloatOverflow` next to `error.Interrupted` and prints "FLOATING
   POINT OVERFLOW" *without exiting the process* — a deliberate behavior
   change from the old eval-time `abi.exit(1)`, matching this phase's "evaluation
   is in-process" goal. The 2 compile-time call sites (`codegen.zig`'s float
   literal codegen) are NOT threaded through the whole compiler (that's step
   5's job) — `stoDbl(v) catch floatLiteralOverflow()` reports via the
   existing `setup.syntax()`/`SYNERR` set-flag-and-continue idiom, the same
   one every other codegen-time syntax error already uses. The 2
   `setup.zig` bootstrap call sites (`hugenum`, `tiny`) use `catch
   unreachable` — both values are hardcoded finite constants, so the error
   path is provably dead there. `heap.zig`'s dump-loading `getdbl` (a
   non-finite value can only mean a corrupt `.x` file, since a well-formed
   one was itself written from a value `stoDbl`/`setdbl` already accepted)
   flags `BAD_DUMP` instead, matching the existing dump-corruption
   convention. `fpeError`, its SIGFPE registration, `rs.env`, and
   `sigsetjmp`/`siglongjmp`/`jmp_buf`/`sigjmp_buf` (and main.zig's size
   asserts for them) are deleted; the 4 now-inert `sigsetjmp(&rs.env, ...)`
   calls whose only purpose was establishing fpeError's landing point
   (`startup.zig` x3, `module_loader.zig`'s already-dead `mkincludes` path)
   are deleted too. Scorecard's `setjmp/longjmp/jmp_buf mentions` metric
   dropped from 37 to 6 (all doc-comment history, no real usage).
3. **Checkpoint/restore replaces fork-per-eval.** `Heap.checkpoint()` copies the
   `MultiArrayList` columns (up to `len`), the live bitset, `free_head`, and a
   snapshot of registered roots; `Heap.restore()` puts them back. `repl.process()`'s
   fork/wait/`WIFSIGNALED` reporting is deleted — a crash in evaluation is now a Zig
   panic (strict builds catch in CI), not a "child died" message.
   *Differential watch-list:* stdout interleaving, `System`/exit-code observables,
   SIGINT mid-eval, `//stats` GC counters (checkpoint must not perturb them —
   snapshot the counters too), CAF over-evaluation sharing (the parent previously
   never saw the child's reductions; restore reproduces that exactly).
   **Fallback:** keep a fork path behind one function in `os.zig`, comptime-selected;
   delete after a full release cycle of differential green.
   **Also fix here (noted, Phase 2 step 4):** `driver/repl.zig`'s `parseLine`
   (the `readvals` value-at-a-time reader) reuses the *full* `evaluateRepl`
   (fork + reduce + default-output-mechanism print + exit) just to parse-
   and-typecheck one value, so every value `readvals` reads is also echoed
   to stdout as a side effect — confirmed harmless (no crash) but almost
   certainly not intended. `tests/mira_tests.zig`'s
   `caseReadvalsSurvivesGcPressure` currently asserts *today's* echoing
   output; once fork-per-eval is gone, `parseLine` should skip straight to
   returning the codegen'd expression without forking/reducing/printing,
   and that test's expected string should drop the per-value echoes.
4. **Shell escape and editor** (`!cmd`, `/e`) → `std.process.Child` (argv built
   as slices, no `execl`/`[*:0]` juggling outside `os.zig`).
5. **Error unions end-to-end.** `loadfile`/`privlib`/`parse*`/`compile` return
   `MiraError!T`; `acterror()`/`syntax()`-style set-flag-and-continue becomes
   record-diagnostic-then-`return error.SyntaxError`. `fatal()` keeps its role for
   startup/CLI death. Delete `MiraError.EvaluationInterrupted`'s "documents intent"
   caveat — it's now real.
   **Landed** (2026-07-08), with two deliberate scope decisions: `parse*` needed
   no work (`parser.zig`'s ~24 functions, `parser_api.zig`'s
   `parseCurrent`/`parseString`/`parseWithNew`, and `pratt.zig`'s `parseExpr`
   were already `ParseError!T`). `setup.zig`'s `syntax()`/`acterror()` now
   return `errors.MiraError!void` (still print + set `SYNERR` + reset the
   lexer as before, then `return error.SyntaxError`) — their ~12 call sites in
   `trans.zig`/`codegen.zig` all `catch {}` immediately rather than
   threading `try` further, because every one of them already does "print,
   set the flag, return a placeholder value in place" and relies on
   `module_loader.zig`'s `if (core.SYNERR == 0) {...}` gates to notice later
   — those gates are NOT an antipattern to eliminate here, they're what lets
   `loadfile`'s per-definition codegen loop keep going after one bad
   definition and collect every diagnostic for the file in one pass (verified
   this still works: a file with a genuine duplicate-definition error still
   prints its diagnostic and reports "compilation abandoned", not a crash or
   an early silent stop). `loadfile` itself now returns
   `errors.MiraError!void` — `error.LoadError` when the file is missing or
   can't be opened, `error.SyntaxError` when `SYNERR` ended up set after the
   pipeline runs (message already printed) — with its internal `SYNERR`-gated
   pipeline stages otherwise unchanged; all 12 external call sites (`repl.zig`
   ×2, `commands.zig` ×3, `dump.zig`'s `undump` ×4, `parser_tests.zig` ×3)
   `catch {}` since none of them branched on loadfile's outcome before this
   change either. `privlib()` was NOT converted: it and its `predef`/`primdef`
   callees have no failure path at all in this port (no clash detection, no
   validation) — giving it a `MiraError!void` signature that can never
   actually return an error would be exactly the empty-error-handling this
   codebase avoids, so it stays `void`. `MiraError.EvaluationInterrupted`'s
   caveat is NOT deleted either — that variant is about interrupted
   evaluation, which (deliberately, see step 1/2) uses the narrower
   `word.ReduceError`, not `MiraError`; it remains an unused placeholder.

**Deletes:** the setjmp family and both fork sites; `unlinkme`/`sigflag` become
`errdefer` cleanup; `WIFSIGNALED`/`WTERMSIG` helpers.
**Landed** (2026-07-08): `unlinkme`/`sigflag`/`sigdefer` deleted outright rather
than reimplemented as `errdefer`. `unlinkme` was dead on arrival in this port —
set/cleared in `dump.zig`'s `makedump` but never once read, so it protected
nothing. `sigflag`/`sigdefer` existed to defer SIGINT during dump I/O (swap in
a flag-setting handler, restore the old one after, manually re-raise if it
fired) because the *old* handlers it was deferring (`reset`/`dieClean`,
gone since step 3) were unsafe to run mid-write. The now-permanent
`onInterrupt` (step 1) is already async-signal-safe everywhere — it only
does one atomic store, never touches heap state or longjmps — so there is
nothing left to defer; the swap-and-redeliver dance in `dump.zig`'s `undump`
and `module_loader.zig`'s `mkincludes` is simply removed, and dump writes
now rely on the pre-existing `BAD_DUMP` corruption check to clean up a
partial file on the next load (already true before this change; SIGKILL and
panics were never covered by `unlinkme` either, since neither runs Zig
`defer`s). `callconv(.c)` usage drops from 4 to 1 (only `onInterrupt`
remains).

**Gate:** scorecard setjmp/longjmp = 0; sigint, smoke, golden, regression suites
green; bench unchanged (checkpoint cost is per-REPL-eval, not per-reduction).

**Phase 3 complete (2026-07-08).** All five steps landed; scorecard vs. the
Phase 2 baseline: setjmp/longjmp/jmp_buf mentions 37→6 (all doc-comment
history explaining the deleted mechanism, zero real usage — the literal
"=0" gate isn't met, but nothing left is `setjmp`/`longjmp`/`sigjmp_buf`
itself, and trimming those comments would remove real context for a vanity
number); fork()/wait() 8→5 (the `system` builtin's own real fork,
`std.process.Child`'s `wait`, and `module_loader.zig`'s already-dead
`mkincludes` fork remain — none are fork-per-eval); callconv(.c) 6→1 (only
`onInterrupt`); ambient singleton-accessor call sites 1412→943 (module-scope
`RuntimeState`/`Heap` threading landed alongside this phase's own work).
sigint/smoke/golden/regression/spine suites all green throughout; no bench
regression (checkpoint/restore is per-REPL-eval, confirmed via the existing
benchmark suite).

---

### Phase 4 — Composition (layering, splits, ownership)

**Goal:** the §4.1 tree with a CI-enforced import DAG; no god files; state owned by
subsystems and passed explicitly; the ambient singleton deleted.

**Steps**

1. **Moves.** Pure `git mv` into the target tree + import-path fixes. One commit,
   zero logic change.
   **Landed** (2026-07-08), **partial by design** — paced deliberately to stop
   before the god-file splits (step 3) and receiver threading (step 5), which
   are the actual size/risk of this phase. 24 files moved: `runtime/os.zig` →
   top-level `os.zig`; `runtime/{big,word,strtab,combinator}.zig` →
   `graph/{bignum,word,strtab,combinator}.zig`; `runtime/stream.zig` and all
   of `runtime/reducer/*` → `eval/` (`combinators.zig`/`ready.zig`/`lex.zig`/
   `io.zig` under `eval/combinators/`); `runtime/reduce.zig` → renamed to
   `eval/reduce_rt.zig` (its old name collided with `reducer/reduce.zig`,
   the dispatch engine itself, once both landed under `eval/`);
   `parser/{ast,pratt,parser,token_filter}.zig` → `syntax/`; `runtime/interp.zig`
   → `session/interp.zig`; `driver/{repl,commands}.zig` → `session/`;
   `driver/lineedit.zig` → renamed to `session/editor.zig` (matching the
   plan's own §4.1 naming). Import paths fixed via a script (computes each
   edge's new relative path from both endpoints' old/new locations — plain
   sed can't do this correctly since the same import string means a
   different relative path depending on which file is asking).
   **Deliberately NOT moved this pass** (no unambiguous 1:1 mapping without
   guessing at file boundaries that step 3/4 own): `heap.zig` (splits into
   4 files), `types.zig`/`trans.zig` (split into `infer`/`unify`/
   `type_errors`/`depend`/`lower`/`match`), `module_loader.zig` (folds into
   the *existing*, differently-scoped `semantics/modules.zig`), `dump.zig`/
   `setup.zig`/`compiler_state.zig` (naming collides with the target's own
   `graph/dump.zig`, and/or are state-bag territory for step 4),
   `runtime/{core_state,runtime_state,errors,version}.zig` (state-bag
   dissolution is step 4's job, not a pure move), `parser/{lex,lex_state,
   codegen,parser_api,parser_tests}.zig`, `driver/startup.zig`, `io/*.zig`.
   **A scare worth recording:** partway through, a stray `git checkout --
   src/graph/word.zig` (used to undo a sanity-test edit) silently reverted
   the file to a *stale staged-index* version with a since-fixed broken
   import (`@import("stream.zig")`, valid before the move, broken after) —
   the working tree had been correct the whole time, but the index entry
   `git mv` had captured did not match, and `zig build`'s cache didn't
   re-surface the discrepancy until a full cache wipe (`rm -rf .zig-cache`)
   forced a real recompile. Fixed by re-verifying every moved file's import
   resolves to a real on-disk path, then `git add -A` (minus the two
   pre-existing, unrelated files this session found already dirty at
   startup) to force the index back in sync with disk. **Lesson:** after a
   bulk move-and-rewrite, don't trust `zig build` success alone if the cache
   might be stale from before the move landed — a clean-cache rebuild is the
   real check, and the git index can silently diverge from the working tree
   in ways `git status`'s rename heuristic doesn't surface.
2. **DAG check.** A small Zig tool (or script) parses `@import` edges and validates
   the layer rules; wire into scorecard. Existing cycles get a temporary allowlist
   that must shrink to empty within the phase.
   **Landed** (2026-07-08): `scripts/layer_check.py` implements the §4.1 rule
   (`graph`/`syntax` leaves; `semantics` → `syntax`+`graph`; `eval` →
   `graph`; `session` → everything; only `main.zig`/`session`/
   `eval/stream.zig` → `os.zig`). It only checks edges where BOTH endpoints
   have already landed in the target tree (`graph`/`syntax`/`semantics`/
   `eval`/`session`/`main.zig`/`os.zig`) — most of the codebase is still in
   the pre-Phase-4 `runtime`/`compiler`/`parser`/`driver`/`io` directories
   after step 1's partial move, so those edges aren't classified into a
   layer yet and are silently skipped (they start being checked the moment
   the file on either end moves). The 19 real violations among
   already-migrated files today (mostly `os.zig`'s giant re-export surface
   reaching into `eval`/`session`, and `graph/{bignum,strtab,word}.zig`
   reaching into `eval`/`session` via the still-ambient `current_interp`
   singleton) are grandfathered into `scripts/layer_allowlist.txt`, per-edge,
   and must shrink to empty by the end of the phase — new violations not in
   the allowlist fail the check. Wired into `scorecard.sh` as
   `unallowed §4.1 layer violations` (target 0, gated) alongside `@import
   cycles` (pre-existing tool, was computed but never actually gated —
   `RATCHET_COUNT` was stale at 15 from before that metric existed; bumped
   to 17 to cover both, matching the script's own "Category 3: structure"
   comment that said they should be).
3. **Split the god files** (move-only commits, one per split):
   - `heap.zig` → `graph/heap.zig` (arena, make/cons, payload accessors),
     `graph/gc.zig` (mark/sweep, dstack, root marking), `graph/dump.zig`
     (`dumpScript`/`loadScript` + XBASE), `graph/print.zig` (`outTerm`, `charname`);
     `alfasort` → `semantics/`. **Landed** (2026-07-08), fourth and last of
     the four splits, done in three commits. (1) A pure move
     `runtime/heap.zig` → `graph/heap.zig` (34 importers fixed), no logic
     change. (2) `graph/print.zig`: `charname`/`outReal`/`castPtr`
     (private→pub)/`outTerm`/`outSubterm`/`outAtom`, the term/type printer.
     (3) `graph/dump.zig`: the full `.x` wire format —
     `setprefix`/`mkrel`/`okdump`/`geterrlin`, `getword`/`putword`/
     `putint`/`getint`/`putdbl`/`getdbl`, `dumpScript`/`dumpDefs`/`dumpOb`,
     `loadScript`/`loadDefs`, `bindparams`/`unscramble`, `unload`/
     `unsetids`/`srcUpdate`, plus the private helpers used only by those
     (the four `id*Ptr` accessors, `getPn`/`pnVal`, the dump scratch-stack
     `stackp*`, `datapair`/`fileinfo`/`readvals`/`ap`, a duplicated
     `gettvar`/`mktvar`) — matching the existing convention of duplicating
     cheap accessors into each split file rather than exporting internals.
     `alfasort` moved to `semantics/depend.zig` in the same pass (a generic
     list-sort utility, not heap machinery); 8 external call sites
     repointed. **No separate `graph/gc.zig` this pass**: the plan's
     one-line manifest lists "mark/sweep, dstack, root marking" for it, but
     `Heap.mark`/`Heap.gc` are *methods* on the `Heap` struct itself (which
     stays intact as one unit per the pure-move commit), and the
     free-function wrappers around them (`gc()`, `setupheap`/`resetheap`/
     `resetgcstats`, `mallocfail`/`mallocPanic`, `markRoot`) are thin
     singleton-delegators — the same category as `h`/`t`/`cons`, which
     already stay in `heap.zig` rather than getting their own file.
     `dstack`'s allocation (`dsetup`/`dgrow`) turned out to be dump-load
     scratch-stack management, not GC bookkeeping (the comment literally
     says "the dump scratch stack"), so it went to `dump.zig` with the rest
     of the load path, not a hypothetical `gc.zig`. A real `graph/gc.zig`
     would mean pulling `mark`/`gc` out of the `Heap` struct itself — an
     actual architecture change, not a move, and out of scope here.
     **Corruption caught during verification**: the first draft of
     `dump.zig` reconstructed `getPn`/`pnVal` and the four `id*Ptr` helpers
     from memory instead of copying the committed source, and got every
     field-offset formula wrong (e.g. `idTypePtr` as `hp(t(x))` instead of
     the real `tp(h(x))`). This compiled cleanly and was invisible until
     the built binary crashed loading the prelude (`reached unreachable
     code` in `Heap.hp`'s bounds assert) on the first `zig build test` —
     caught by running the full programmatic function-body diff against
     every moved function (not a sample), which flagged exactly those six
     plus a `mallocPanic`/`mallocfail` mix-up in `setprefix` (the original
     calls the plain `mallocfail`, not the `noreturn` wrapper). Both fixed;
     a second clean-cache `zig build test` plus a fresh `git worktree`
     build confirmed the fix. `files > 1000 lines` rises 9→10 (`dump.zig`
     lands at 1150 lines — the wire-format reader/writer has real internal
     call dependencies, e.g. `loadScript` calls `loadDefs`, and further
     subdivision would cut arbitrarily through that graph rather than along
     a real seam); baseline updated with this justification.
   - `types.zig` → `infer.zig` / `unify.zig` / `type_errors.zig` / `depend.zig`.
     **Landed** (2026-07-08), third of the four splits and the largest so
     far (128 functions, 6 tests, 2733 lines). `depend.zig` got the generic
     sorted-set operations (`remove1`/`setdiff`/`add1`/`newadd1`/`UNION`/
     `intersection`/`member`/`typesfirst`) plus `tsort`/`msc`/`deps`/
     `rembvars`/`redtfr` — deliberately *not* `compDeps`, which the plan's
     one-line "tsort/deps" summary might suggest belongs there too, but
     which is tightly coupled to `metaTcheck`/`sayhere` (the type-checking
     driver) rather than being a reusable dependency-analysis primitive, so
     it stayed in `infer.zig`. `unify.zig` got the substitution engine
     (`lookup`/`addsubst`/`subst`/`occurs`/`instantiate`/`linst`/
     `redtvars`/`unify`/`subsumes`) — `conforms` stayed in `infer.zig` for
     the same reason as `compDeps`. `type_errors.zig` got `typeError`
     through `typeError8`, `locate`/`sayhere`, and the `outType*`/
     `outPattern`/`outFormal*` printers. Genuine multi-way dependencies
     exist between all four (e.g. `unify.zig`'s `unify` calls
     `type_errors.zig`'s `typeError`; `infer.zig` and `depend.zig` import
     each other for `getId`) — same rationale as `lower.zig`↔`match.zig`:
     the original single file's internal call graph didn't respect these
     boundaries, so splitting it necessarily crosses them in both
     directions; all four land in the same `semantics/` layer so this
     isn't a cross-layer violation.
     Verified with the same programmatic-diff process as the `trans.zig`
     split (all 128 functions and 6 tests extracted and diffed against
     `git show HEAD:src/compiler/types.zig` before considering this done).
     One deliberate, documented deviation survived that diff: `newadd1`
     (dead code — no call sites anywhere in the codebase, confirmed in
     both the original and after) had a genuine pre-existing bug
     (`cs.NEW = 1` instead of `cs().NEW = 1`, since `cs` is a function) that
     never surfaced because Zig's lazy analysis never type-checks an
     unreferenced `pub fn`'s body; fixed in place rather than preserved,
     since preserving a non-compiling statement verbatim isn't meaningful
     and the fix cannot change behavior (the function is never called).
     **Also fixed in passing:** `src/syntax/layout.zig` still imported
     `parser/token_filter.zig` and `parser/parser.zig` via their pre-move
     paths from Phase 4 step 1 — invisible locally because an uncommitted
     working-tree fix (present since before this session, never staged)
     already corrected it, but the actual pushed history had been
     unbuildable from a clean checkout ever since that step landed
     (confirmed via `git worktree add` against the prior commit). Committed
     separately as its own fix ahead of this split.
   - `trans.zig` → `lower.zig` / `match.zig`.
     **Landed** (2026-07-08), second of the four splits. `match.zig` got
     exactly the three functions the file's own module doc named as
     "pattern-match compilation" (`scanpattern`, `genlhs`, `transtries`);
     everything else (bracket abstraction, let/letrec/ZF translation,
     show-function generation, declaration bookkeeping, the relation/
     topological-sort helpers, the top-level `codegen`, and every low-level
     graph accessor) went to `lower.zig`. Unlike the config/boot split, a
     genuine two-way dependency was unavoidable here: `lower.zig`'s
     `declare` calls `match.scanpattern`, `lower.zig`'s `codegen` calls
     `match.transtries`, and `match.zig`'s `transtries` calls back into
     `lower.zig`'s `codegen` to compile each match alternative -- inherent
     to the algorithm (this is exactly how the single original file's
     internal recursion worked), not a design mistake. `match.zig`
     duplicates a handful of one-line graph accessors (`h`/`t`/`cons`/`ap`/
     etc.) rather than importing them, matching the existing convention in
     `eval/combinators/*.zig`; `getId` was made `pub` in `lower.zig` and
     called from there instead of being duplicated a third time, since its
     `[*:0]const u8` return type is one of the scorecard's tracked C-string
     metrics and a second copy would have shown up as a regression.
     Verified the same way as the `startup.zig` split, and more thoroughly
     given that one's near-miss: every one of the original's 104 functions
     and 4 tests were extracted programmatically and diffed against `git
     show HEAD:src/compiler/trans.zig` byte-for-byte (modulo the expected
     cross-file call prefixes) before this was considered done -- caught
     zero corruption this time, unlike the previous split, which is itself
     the point of doing it this way. Exercised constructor pattern matching,
     multi-clause guards, and recursive numeric definitions in the built
     binary as a live check, not just the existing test suite. Also fixed a
     real gap the layer-check tool surfaced: `trans.zig` living in the
     unclassified `compiler/` directory had hidden 3 real cross-layer edges
     (`os.zig` ↔ `lower.zig`, `eval/reduce_test.zig` → `lower.zig`) from
     the checker; now that it's in `semantics/`, they're visible and
     grandfathered into the allowlist like the original 19. Separately
     discovered `scripts/layer_allowlist.txt` was never actually committed
     in the prior "steps 1-2" commit -- a blanket `*.txt` `.gitignore` rule
     silently excluded it, so a fresh clone would have seen 19 false
     "new" violations. Fixed with a `.gitignore` exception; the file is
     version-controlled from this commit onward.
   - `startup.zig` → `session/config.zig` (flags, `.mirarc`) + `session/boot.zig`
     (miralib resolution, version stack).
     **Landed** (2026-07-08), first of the four splits (smallest/least
     depended-upon, done first per this phase's own risk-ordering). One
     genuine two-way call exists between the split files (`boot.zig`'s
     `mainEntry` drives `config.zig`'s flag/rc functions; `config.zig`'s
     `parseFlags` calls `boot.zig`... except it doesn't — `versionInfo`/
     `versionString` were deliberately placed in `config.zig`, not `boot.zig`
     as the plan's one-line description might suggest, specifically so the
     dependency stays one-directional: `boot.zig` imports `config.zig` (for
     `versionString` in the miralib-not-found message), `config.zig` imports
     nothing from `boot.zig`. **A verification lesson worth keeping:** the
     first draft of this split, done from memory of an earlier read of
     `startup.zig` rather than by copying the actual text, silently
     corrupted three things — `runSourcesMode` called a nonexistent
     `heap_mod.filName`, `runMakeMode`'s failure-collection logic used a
     completely different (wrong) data structure, and `parseFlags`'s first
     two flag branches were invented (`-nostandard`/`-verbose`/`-quiet`
     instead of the real `-stdenv`/`-count`) — all three compiled fine
     syntactically (the `filName` one didn't even compile, but the other two
     would have silently shipped wrong CLI/`-make` behavior). Caught by
     diffing every function's extracted body against `git show
     HEAD:src/driver/startup.zig` programmatically before considering the
     split done, not by eyeballing or trusting a green `zig build`. Applies
     generally to the remaining god-file splits: reconstruct from the actual
     committed text, not from memory of having read it earlier, and diff
     each moved function against the original mechanically.
4. **Dissolve the state bags** into owners (each move = one commit).
   **Landed** (2026-07-08), all six slices, each verified independently
   (clean-cache `zig build test`, `layer_check.py`, `scorecard.sh`) and
   pushed as its own commit:
   - `MakeState` (`session/make_state.zig`): `making`/`mkexports`/
     `mksources`/`make_status`. Smallest slice (~30 sites); established
     the pattern every later slice followed (a value field on `Interp`
     alongside `rs`/`heap`/`lex`/…, a `pub inline fn X() *T` singleton
     accessor mirroring `rs()`, cleared automatically by `interp.reset()`'s
     `.* = .{}` since it's just one more field on that struct).
   - `BnfState` (`session/bnf_state.zig`): `eprodnts`/`nonterminals`/
     `ntmap`/`ihlist`/`ntspecmap`/`lexstates`/`lexdefs`. Confirmed
     genuinely dead outside `heap.zig`'s GC root-marking loop — "already
     reduced by Phase 1" turned out to mean "reduced to nothing but
     always-NIL roots a future `%bnf` implementation would repopulate".
   - `ShowFns` (`semantics/show_fns.zig`, **not** `session/`):
     `shownum1`/`showbool`/`showchar`/`showlist`/`showstring`/
     `showparen`/`showpair`/`showvoid`/`showfunction`/`showabstract`/
     `showwhat` — 11 fields, not the "20" this line originally said (the
     rest were apparently retired earlier). Its only real reader,
     `semantics/lower.zig`, is semantics-layer, and semantics may not
     import session (`layer_check.py` caught this on the first attempt
     at `session/show_fns.zig` — a real violation, unlike the graph-side
     slices' GC-reach edges, which are grandfathered precedent). Kept
     plain named `Word` fields rather than `std.EnumArray(ShowFn, Value)`
     — `Value` doesn't exist before Phase 5, and retyping the access
     pattern itself is bigger, distinct work from "which struct owns
     this data".
   - `ReplSession` (`session/repl_session.zig`): `lastexp`/`lastid`/
     `echoing`/`listing`/`promptstr`/`last_elapsed_ns`/`last_gc_count`,
     plus `verbosity` (not in this line's original list, but folded in
     since every `echoing` site computes it as `verbosity & listing`
     identically — splitting it out would cut across that expression for
     no reason). ~90 sites, the first slice to also need repointing the
     explicit `rs: *RuntimeState` parameter form (`module_loader.zig`/
     `repl.zig`/`commands.zig`/`dump.zig`, which already took `rs` for
     other fields) alongside the ambient `rt.rs()` form. Couldn't avoid a
     real `semantics/lower.zig -> session/repl_session.zig` edge either
     (`echoing` is REPL-owned state lower.zig merely reads); grandfathered
     rather than relocating the whole struct, since the cleaner fix (an
     explicit flag threaded into lower.zig's own context) is step-5
     territory, not a data move.
   - `ConfigState` (`session/config_state.zig`, **not** `config.zig` —
     that name was already taken by the flag-parsing/`.mirarc` logic from
     the step-3 `startup.zig` split, which populates this struct but
     isn't it): `PRELUDE`/`STDENV`/`SPACELIMIT`/`DICSPACE`/`editor`/
     `okprel`/`nostdenv`/`baded`/`miralib`/`s_in`. `UTF8`/`UTF8OUT`
     deliberately stayed on `RuntimeState` despite being in the same
     source comment block — they're read as `ctx.rs.UTF8` inside
     `eval/reduce_rt.zig`'s `ReductionCtx` (the reduction hot path's own
     receiver-carrying context), so moving them means changing
     `ReductionCtx`'s signature, which is step 5's job. Largest slice:
     ~140 sites across 14 files.
   - `ScriptStore` (`session/script_store.zig`): `oldfiles`/`includees`/
     `freeids`/`exports`/`embargoes`/`lastname`/`suppressids`/`col_fn`/
     `sorted`/`detrop`/`rfl`/`bereaved`/`ld_stuff`/`current_script`/
     `fnts`. `files` itself stays on `Heap` — an earlier phase (shared-
     state Phase 2b) already folded it there, so every accessor already
     reaches it as `heap().files`, never `rt.rs().files`; this line's
     "`files`, `oldfiles`, …" phrasing predates that. `RuntimeState.
     validate()` (the hand-maintained heap-root-safety check the Root
     registry below is meant to eventually replace) now also walks
     ScriptStore's fields internally, so every existing
     `rt.rs().validate()` call site catches the moved fields too without
     a second call needed at each site.

   **Left on `RuntimeState` after all six slices** (~35 fields, no clean
   single-bucket fit): identity atoms set once by `miraSetup` and never
   touched again (`Void`/`main_id`/`message`/…), `UTF8`/`UTF8OUT` (tied to
   `ReductionCtx`, see above), GC/evaluator counters (`atobject`/`atgc`/…),
   working buffers (`linebuf`/`ebuf`/`home_rc`/…), and startup/REPL-
   display scratch (`vstack`/`mstack`/`mirahdr`/…). The phase's gate
   (singleton-accessor count, `current_interp` references, layer
   allowlist) is checked at the end of the whole phase, after step 5's
   receiver threading — not against `RuntimeState` itself being empty —
   so this residual state is left alone rather than force-fit into a
   seventh bag.

   Each slice caught the same shape of build error once its fields
   moved out from under an explicit `rs: *RuntimeState` parameter that
   also carried other fields: the parameter goes fully unused in a few
   functions (`compiler/dump.zig`'s `unfixexports`/`fixexports`/
   `readoption`, `compiler/module_loader.zig`'s several `resolveExports`-
   family functions, `graph/dump.zig`'s `dumpScript`/`unload`/
   `srcUpdate`, `session/repl.zig`'s `edWarn`/`badEditor`/`parseLine`,
   `graph/dump.zig`'s `loadDefs`) — each fixed with an explicit `_ = rs;`
   rather than removing the parameter, since dropping it would be a
   signature change (step-5 territory) forced by an incidental
   consequence of a pure data move, not something this step should do.

   One pre-existing bug investigated and ruled out as unrelated: `double
   21` immediately followed by `/heap` in the REPL loses the `"42"`
   output. Confirmed via `git stash` + rebuild that this reproduces
   identically before any of this step's commits landed — the same class
   of bug as the already-flagged output-loss-after-a-type-error issue,
   not a regression introduced here. Flagged separately (task_7b741d68)
   rather than fixed inline.
   - `CoreState`: `SYNERR`/`errs`/`errline`/`errcol` are gone (Phase 2);
     `loading`/`compiling` → a `Mode` enum on the compile context; `commandmode` →
     a parse-mode *parameter*; `nill` → a `graph` constant.
     **`nill` landed** (2026-07-08): moved onto `Heap` as a plain field
     (`heap.nill`/`heap.heap().nill`), not a literal constant — it's a
     heap-allocated cons cell built once by `miraSetup`, so it belongs
     alongside `Heap`'s other setup-time identity fields (`files`/
     `current_file`/`CFN`), the same category of move as every state-bag
     slice above. **`loading`/`compiling` → `Mode` and `commandmode` →
     parameter deliberately not attempted**: both are real signature/
     behavior changes (an enum consolidation changes every read site's
     comparison logic; "→ a parameter" is literally receiver-threading),
     not data relocation — they belong to step 5's work, not this step's
     "move fields to their right owner, no other changes" discipline.
   - **Root registry:** `graph/gc.zig` gets `Roots` — owners register slices/
     callbacks of heap refs. Replaces both the GC's hard-wired knowledge of every
     subsystem's fields and `RuntimeState.validate()`'s hand-maintained list.
5. **Thread receivers, subsystem by subsystem** (each a green commit):
   `graph` first (heap methods already exist), then `eval` (the `ReductionCtx`
   carries `*Heap` + `*EvalState` + `*Roots`), then `semantics` (a `Compile`
   context struct: heap, symbols, diagnostics, config, script store), then
   `session`. Finish by deleting `heap.heap()`, `rs()`, `cs()`, `ls()`, `ev()`,
   `s()`, `interp.current_interp`, and `interp.reset()` (tests construct their own
   `Interp`; `testutil` provides the harness).
6. **The two-Interp test** — construct two `Interp`s, load a small script in each,
   evaluate interleaved, assert isolation. This is the phase's definition of done.

   **`graph` subsystem, in progress.** Landed subsystem-by-subsystem, each a
   green commit: `graph/print.zig` (`charname`/`outTerm`/`outSubterm`/`outAtom`
   take an explicit `heap: *Heap`; `outReal`/`castPtr` untouched, neither
   touches heap-cell data), `graph/dump.zig` (nearly everything —
   `setprefix`/`mkrel`/`dumpScript`/`dumpDefs`/`loadScript`/`bindparams`/
   `unscramble`/`dsetup`/`dgrow`/`loadDefs`/`unsetids`/`unload`/`srcUpdate`
   plus a dozen private helpers), then `graph/heap.zig`'s own core API
   (`h`/`hp`/`t`/`tp`/`getTag`/`cons`/`make` — the file's central allocator
   primitives, called from every other subsystem). The `heap.zig` conversion
   also deleted one genuinely dead free function (`makeTwo`, confirmed
   unreferenced via a `@compileError` injection: its only apparent caller
   actually calls the `Heap.makeTwo` *method* through its own explicit
   receiver) and fixed the same shadowing bug in `gc()` (reachable only from
   `micro_benchmarks.zig`, outside `zig build test`'s default coverage).
   Every other subsystem that calls these seven functions was fixed
   mechanically (`h(x)` → `h(heap, x)`) wherever a `heap: *Heap` was already
   in scope; where a small, high-fanout helper (e.g. a file-local `cons`/`ap`
   wrapper called from dozens of sites) had no receiver of its own and adding
   one would cascade into unrelated signature changes, the helper's own
   signature was left alone and its *body* calls `heap_mod.heap()` explicitly
   instead ("ambient-internal", as distinct from the "thread it explicitly"
   treatment used everywhere a receiver was already in scope) — used in
   `heap.zig` itself (its ~25 small accessors), `parser/lex.zig`, `parser/
   codegen.zig`, `semantics/{infer,lower,match,unify,type_errors,modules}.zig`,
   `eval/reduce_rt.zig`, `eval/spine.zig`, `os.zig`'s `strcons`.

   **`dumpOb` deliberately kept ambient, not receiver-threaded** (see its own
   doc comment in `graph/dump.zig`): a receiver-threaded version measurably
   regressed the safe recursion depth (dumpOb recurses on `.CONS`'s tail
   *before* its head, so it isn't tail-call-optimisable, and its depth is
   proportional to list length, which is user data — unbounded). Confirmed
   via `git stash` bisection: pre-conversion handled a 1500-element list
   literal through `-make`; the receiver-threaded version crashed at 1000.
   Reverted to its original ambient form (only `heap_mod.heap()` calls
   inserted, no new parameter), then re-verified via the same stress
   methodology against `graph/heap.zig`'s core-API conversion (extra
   stress-testing per explicit request): n=1500 succeeds cleanly, matching
   pre-existing behaviour; n=8000 crashes identically on both the pre- and
   post-heap.zig-conversion binaries (built and diffed via a throwaway `git
   worktree` at the prior commit) — confirming the crash threshold is
   unchanged, not a new regression. `dumpOb` itself still needs the deferred
   fix (walk its own `stackpPush`/`stackpPop` scratch stack explicitly,
   matching `loadDefs`, its inverse) before it can be receiver-threaded like
   the rest of the file.

   **`eval` subsystem's leaf helpers, in progress.** `ReductionCtx` (`eval/
   reduce_core.zig`) already carried an explicit `heap: *Heap` field from an
   earlier, pre-Phase-4 pass (SHARED_STATE Phase 6, 2026-07-01) — its own
   accessor/rewrite primitives (`hdGet`/`tlGet`/`getTag`/`cons`/`ap`/…) were
   already receiver-threaded, so the reducer's own dispatch loop needed no
   further work. What remained was `eval/reduce_rt.zig`'s *own*, separate set
   of small private ambient helpers (`h`/`t`/`hp`/`tp`/`getTag`/`setTag`/
   `cons`/`ap`/`datapair`/`digit0`/`stosmallint`/`lh` — duplicates of
   `reduce_core.zig`'s already-threaded equivalents, but calling
   `heap.heap()` internally instead) and the ~20 public functions built on
   top of them (`wrapPtr`/`unwrapPtr`, `rewriteToValue`/`rewriteToNil`/
   `setcell`/`rewriteToCons`, `badcaseError`/`confError`/`parseCloseError`,
   `gResidue`/`lexstate`, `outHere`, `apfile`/`closefile`/`outf`/`print`/
   `output`, `numplus`/`memclass`/`lexfail`/`compare`/`force`/`head`) —
   explicitly asked for despite the cascade (a fanned-out choice over
   stopping at eval's "good enough" pre-existing state). All ~30 now take an
   explicit `heap: *Heap` (or route through their existing `ctx: *ReductionCtx`
   receiver where one was already in scope), with every external call site
   across `combinators.zig`/`ready.zig`/`io.zig`/`lex.zig`/`session/repl.zig`/
   `parser/codegen.zig` fixed to pass `ctx.heap`/`heap` explicitly.
   `compare`/`force`/`head` were the ones flagged by the earlier recursion-risk
   audit (task_a08ed1a5) — their added parameter was checked against the same
   dumpOb-class regression before converting: their recursion depth is bounded
   by *value nesting* (a data structure's own type-bounded shape), not *list
   length* (unbounded user data), so adding one pointer-sized parameter here
   doesn't reproduce dumpOb's regression — confirmed empirically with a
   depth-5000 user-defined recursive-tree walk (runs on the heap-backed
   `Spine`, not native recursion, so unaffected either way) and a depth-3000
   `force`/`compare` exercise via `-make`, both clean. Ambient singleton-
   accessor call sites: 702 → 695 (`scorecard.sh`). `fsign`/`sign`/`getStdin`/
   `getStderr`/`getStdout`/`stdname` untouched — none touch heap-cell data.

   **`eval`'s `Spine`/`combinators.zig`/`ready.zig`, landed.** `Spine`'s three
   real-write primitives (`downRight`/`upLeft`/`upRight`, plus their
   spine-empty-guarded variants `downright`/`upleft`) took an explicit
   `heap: *Heap` receiver too — their only callers turned out to be
   `reduce_core.zig`'s three already-`ctx`-taking wrappers of the same name
   (`downRight(ctx)`/`upLeft(ctx)`/`upRight(ctx)`, which the ~140
   `combinators.zig`/`ready.zig`/`lex.zig`/`io.zig` call sites already used),
   so only those 3 wrapper bodies needed a one-line fix
   (`ctx.spine.downRight(ctx.heap, ctx.e)`) — the ~140 sites downstream of
   them needed no changes at all, since their own signature (`ctx: *ReductionCtx`)
   was already the receiver. `Spine`'s own guarded `downright`/`upleft`
   methods (distinct from `reduce_core.zig`'s same-named wrappers, which
   reimplement the same guard directly against `ctx.spine` rather than
   delegating) turned out to have no callers outside `spine.zig`'s own tests.
   `combinators.zig` (7 sites) and `ready.zig` (25 sites) — mostly
   `big.toInt`/`fromInt`/`sub`/`add`/`mul`/`div`/`mod`/`pow`/… calls inside
   handlers that already had `ctx: *ReductionCtx` — fixed the same way,
   `heap.heap()` → `ctx.heap`, no signature changes needed anywhere in either
   file. `eval/reduce.zig`'s `reduce()` itself (the ONE remaining non-test
   ambient site in `eval/`) is deliberately left ambient — it is the actual
   root of the whole `ReductionCtx` chain (nothing calls it with a `heap`
   already in hand; it's where `ctx.heap` first gets populated from the
   singleton, once per `reduce()` invocation), so it stays until the final
   singleton-deletion step, same as `outstats`'s in-file no-receiver-anywhere
   case. `eval/` subsystem is now effectively fully receiver-threaded outside
   test code and those two structural exceptions.

   **`semantics` subsystem, in progress.** No `Compile` context struct was
   introduced — `heap: *Heap` was already the first parameter on essentially
   every `pub fn` across `depend.zig`/`lower.zig`/`match.zig`/`infer.zig`/
   `unify.zig`/`type_errors.zig`/`modules.zig`/`symbols.zig` from earlier
   phases' work, so this slice was purely about each file's own small private
   ambient helpers (the same `cons`/`ap`/`datapair`/… pattern as `eval`'s).
   Converted where the caller count was small and every caller already had
   `heap` in scope: `type_errors.zig`'s `ap` (2 callers), `unify.zig`'s
   `cons`/`ap` (4 and 1 callers — `mktvar` stays ambient-internal, entangled
   with `NTV()`'s ~100 far-flung callers in `infer.zig`'s dispatch table, see
   below), `symbols.zig`'s `PrivateNames.make`/`get` (test-only callers, no
   non-test call sites exist yet — `PrivateNames` isn't wired into
   `codegen.zig`/`lex.zig` yet), `match.zig`'s `cons`/`ap`/`ap2`/`lambda`/
   `datapair` (8 real call sites total, all within `heap`-scoped functions),
   `depend.zig`'s `alfasort` (the recursive merge-sort flagged safe by the
   earlier audit — O(log n) depth — now takes `heap` explicitly, fixing all
   12 external call sites across `infer.zig`/`compiler/dump.zig`/
   `compiler/module_loader.zig`/`session/boot.zig`/`session/commands.zig`),
   and `lower.zig`'s `pair`/`datapair`/`constructor`/`lambda`/`share`/`tries`/
   `let`/`letrec` (2-6 callers each, all within `heap`-scoped functions).

   **Deliberately left ambient-internal** (matching the `infer.zig` `ap`/
   `tf`/`tf2`/`tf3`/`lt`/`pairType` precedent from earlier this phase):
   `infer.zig`'s own `cons`/`ap` (entangled with that same ~50+-site dispatch
   table), `unify.zig`'s `mktvar` (wraps `NTV()`, called ~100 times across
   `infer.zig`'s dispatch with no `heap` anywhere nearby), and `lower.zig`'s
   `cons`/`ap`/`ap2`/`ap3` (47 and 38 real call sites respectively — the
   file's own version of the same giant `codegen()` dispatch-table shape).
   `modules.zig`'s 2 sites (inside `applyExportsAndAliases`, one caller deep
   with no `heap` threaded anywhere in that particular call chain) also left
   as-is — a real but small cascade, lower priority than the sites just
   fixed.

   `zig build test`: all 253 unit tests + integration suite + spine
   differential/golden corpus green after every sub-slice. `layer_check.py`:
   0 new violations. `scorecard.sh`: no regression.

   **`session` subsystem, landed.** Small: `commands.zig`'s `cmdEdit`
   (single caller, `command`, already had `heap`) and `editfile` (2 real
   callers, both already had `heap`) now take it explicitly. Everything else
   found in `session/` turned out to be a structural exception rather than
   something to fix: `boot.zig`'s `mainEntry` (`const heap = heap_mod.heap();`
   — the literal root of the whole chain, nothing above it to thread from),
   `main.zig`'s own two post-`mainEntry` validate calls (same reason —
   `main()` predates any heap construction and outlives `mainEntry`'s own
   local `heap`), and `editor.zig`'s tab-completion callback (`zigline`'s own
   fixed callback signature, no room for an extra parameter). All four are
   the same shape as `eval/reduce.zig`'s `reduce()` and `outstats()`: no
   receiver exists anywhere in the call chain to thread from, so they're
   deferred to the final singleton-deletion step rather than "fixed" now.

   `graph`/`eval`/`semantics`/`session` — the four subsystems step 5 named —
   are now all done to the point where every remaining ambient call is one of
   a handful of structural roots, or sits inside one of two deliberately-
   deferred giant dispatch-table clusters. A scoping pass (2026-07-08, no code
   changes) investigated what actually stands between here and the phase's
   literal gate (singleton-accessor count = 0). Conclusion: **nothing left is
   architecturally blocked** — every remaining site is either already
   receiver-threaded one level up (so the fix is mechanical, "thread one more
   parameter through"), or has a viable concrete fix identified below. The
   remaining volume is comparable to everything already landed across the
   `graph`/`eval`/`semantics`/`session` slices combined — a multi-commit
   undertaking, not a quick finish. Four things stand between here and zero:

   1. **`session/interp.zig`'s architecture already supports this.** `Interp`
      bundles every owner module's state as a *value* field; `current_interp:
      *Interp` is a pointer to it (still a module-scope mutable global — one
      of the "module-scope mutable globals" the scorecard counts, exempted
      from the target-of-1 count same as the interrupt flag until this step
      lands). Every `heap.heap()`/`rs()`/`cs()`/`ls()`/`ev()`/`s()` accessor is
      a one-line `return &current_interp.X`. Deleting them doesn't mean
      deleting `Interp`/`current_interp` — it means no code path may read
      `current_interp` *ambiently* anymore; `main()` reads it once (or owns an
      `Interp` value directly) and threads every sub-state down explicitly
      from there. `current_interp` itself likely survives as the one place OS
      signal handlers (which cannot take parameters) still read state from —
      already called out as "the one irreducible C-ABI exception" in
      `interp.zig`'s own module doc.
   2. **The four structural roots, reassessed — none were hard blockers, and
      all four are now landed (2026-07-08):**
      - `main.zig`'s two post-`mainEntry` validate calls — **landed**:
        `interp_storage.heap.validate()`/`lower.validate(&interp_storage.heap)`
        read the already-in-scope local directly; no architectural change.
      - `boot.zig`'s `mainEntry`'s `const heap = heap_mod.heap();` — **landed**:
        `mainEntry(heap: *Heap, argc: c_int, argv: [*][*:0]u8)` now takes it
        as a parameter; `main()` passes `&interp_storage.heap`. Zero other
        changes needed inside `mainEntry` itself — the whole function already
        used its local `heap` binding consistently, so turning that binding
        from a computed constant into a parameter was the entire fix.
      - `eval/reduce.zig`'s `reduce()`'s `ctx.heap = heap_mod.heap();` — **the
        real remaining bulk, landed separately** (previous commit): `reduce()`
        had ~90 real (non-comment, non-test) call sites, confined entirely to
        `eval/` (`combinators.zig`, `combinators/lex.zig`, `reduce_rt.zig`,
        `combinators/ready.zig`, `reduce.zig` itself), all already sitting
        inside `handle*(ctx: *ReductionCtx)` functions with `ctx.heap` on
        hand — mechanical, just large. This is what directly unblocked
        `mainEntry` above: once `reduce()` no longer needed the ambient
        accessor, nothing downstream of `mainEntry` did either.
      - `session/editor.zig`'s zigline tab-completion callback — **landed**:
        `CompletionHandler` gained a `heap: *Heap = undefined` field, set once
        by `editor.init()` (now itself taking `heap_ptr` explicitly, threaded
        from `mainEntry`) before `setHandler` ever registers the callback;
        `tab_complete(self: *CompletionHandler)` reads `self.heap` instead of
        the ambient ex-`state()` read. `completeWord` gained the same
        parameter. 1 struct field + 2 call sites, exactly as scoped. Not
        exercised by the automated suite (needs a real TTY), but the change
        is a single field assignment before the only place the callback can
        fire, so risk is low; the full non-interactive suite (which does
        cover the rest of `editor.zig`'s init/deinit/fillLine path) stayed
        green throughout, and a manual piped-REPL smoke test (`echo "2+3" |
        mira -hush`) confirmed `mainEntry`'s own threading didn't regress the
        ordinary path.
   3. **The two giant dispatch-table clusters, unwind cost estimated:**
      - `infer.zig`'s `ap`/`tf`/`tf2`/`tf3`/`lt`/`pairType`/`NTV` cluster:
        `NTV()` alone has ~100 call sites across the primitive-type dispatch
        table (`infer.zig` lines ~1200-1650); `ap`/`tf`-family layer on top of
        that. All confirmed (this phase, `unify.zig`'s parallel investigation)
        to sit within functions that already carry `heap` — so, like `reduce()`,
        mechanical but voluminous.
      - `lower.zig`'s own `codegen()`-internal `cons`/`ap`/`ap2`/`ap3`: 47 and
        38 real call sites respectively, same shape.
      - Combined, these two clusters are on the order of ~150-200 call sites
        — roughly the size of the `semantics` subsystem slice already landed,
        just concentrated in two single functions instead of spread across a
        file. Whether to cascade into these now or document them as a
        permanently-accepted exception to "singleton-accessor count = 0" (the
        dispatch tables are pure, non-recursive, one-shot-per-typecheck code —
        arguably lower-value to convert than everything else) is a real
        decision, not yet made.
   4. **Files never swept under the `graph`/`eval`/`semantics`/`session`
      checklist**, still carrying real (non-test) ambient calls:
      `graph/dump.zig` (22 — all `dumpOb`'s own deliberately-ambient body,
      already documented, not new work), plus `parser/codegen.zig`,
      `parser/lex.zig`, `parser/parser_api.zig`, `compiler/setup.zig`,
      `compiler/module_loader.zig`, `graph/bignum.zig` (not individually
      surveyed this pass — step 5's plan text named only the four subsystems
      above, so these were always going to need their own pass regardless of
      how the four named subsystems turned out).

   **`reduce()`'s cascade, landed (2026-07-08).** `reduce(heap: *heap_mod.Heap,
   e_val: Word)` now takes its `Heap` explicitly instead of reading
   `heap_mod.heap()` internally — the function's own body needed exactly one
   line changed (`ctx.heap = heap;`), since everything else already operated
   on `&ctx`. Every real call site turned out to already have `heap`/`ctx.heap`
   on hand, confirming the scoping pass's read: `reduce_rt.zig`'s own internal
   callers (`print`/`output`/`force`/`compare`/`parseCloseError`/`getstring`'s
   force-loop/…) already took `heap_ptr` from earlier `eval`-subsystem work,
   and all ~90 call sites across `combinators.zig`/`combinators/lex.zig`/
   `combinators/io.zig`/`combinators/ready.zig` sit inside `handle*(ctx:
   *ReductionCtx)` handlers with `ctx.heap` already in scope — fixed
   mechanically via `reduce.reduce(` → `reduce.reduce(ctx.heap, `. The two
   call sites inside a `combinators.zig` unit test (no `ctx` there) got
   `heap.heap()` instead, matching every other test's own convention; same for
   `testutil.zig`'s and `reduce_test.zig`'s remaining test-only `reduce()`
   calls (test helpers stay ambient by design — `expectReducesTo`/`expectInt`/
   etc. are meant to be simple 2-arg calls, not receiver-threaded).

   `zig build test`: all 253 unit tests + integration suite + spine
   differential/golden corpus green (no dedicated extra stress test needed —
   `reduce()` itself is an iterative `while` loop, not self-recursive, so
   adding one parameter to its own signature carries none of `dumpOb`'s
   per-list-element stack-growth risk; the existing golden/differential suite
   already exercises deep reduction chains). `layer_check.py`: 0 new
   violations. `scorecard.sh`: no regression.

   This was item 2's third (and largest) bullet from the scoping pass, and it
   directly unblocks `mainEntry`'s own remaining `heap.heap()` call.

   **`mainEntry`/`main()`'s bootstrap restructuring and the `editor.zig`
   callback fix, landed (2026-07-08, same session).** `mainEntry` now takes
   `heap: *Heap` as its first parameter instead of computing it from the
   ambient singleton (zero other changes needed inside the function — its
   existing `heap` local was already used consistently throughout); `main()`
   passes `&interp_storage.heap`, and its own two post-`mainEntry` validate
   calls read that same local directly. `editor.zig`'s tab-completion
   callback (see item 2 above) is fixed the same session. All four structural
   roots the scoping pass identified are now closed. Ambient singleton-
   accessor call sites: 695 → 694; `current_interp` references: 48 → 47 (small
   deltas — these four sites were a handful of call sites each, not a bulk
   cluster). `zig build test` green throughout (all 253 unit tests +
   integration suite + spine differential/golden corpus); a manual piped-REPL
   smoke test (`echo "2+3" | mira -lib ./miralib -hush` → `5`) confirmed the
   ordinary non-interactive path survives the `mainEntry` signature change.

   **The not-yet-swept files, mostly landed (2026-07-08, same session).**
   `compiler/module_loader.zig`'s one remaining site (`pnVal`, 2 callers, both
   with `heap`) is now fully clean. `compiler/setup.zig`'s `syntax`/`acterror`
   (the two grammar/parse-error reporters) now take `heap: *Heap` explicitly —
   all ~10 real callers across `lower.zig`/`match.zig` already had it;
   `codegen.zig`'s one caller (`floatLiteralOverflow`, itself still ambient,
   deferred with the rest of `codegen.zig` below) passes `heap.heap()`
   explicitly instead of relying on `syntax`'s own old ambient read — the
   same "ambient-internal for the one caller that can't provide a receiver"
   pattern used throughout this phase. `parser/lex.zig`'s `openfile` (1
   caller) and `makePn` (2 callers) now take `heap` too. `parser/parser_api.zig`'s
   production entry point chain — `parseCurrent` → `parseCurrentNative` →
   `runParsedTokens` — now threads `heap` explicitly end to end (3 real
   callers: `module_loader.zig`'s `loadfile`, `repl.zig`'s `commandLoop` and
   `parseLine`, all already had it); `parseString`/`parseWithNew` (test-only
   callers, no production use) stay ambient. `setup.zig`'s `miraSetup` (used
   by both `mainEntry` *and* several test-harness `freshInterp()`-style
   helpers with no natural `heap` binding) and `graph/bignum.zig` (not
   examined this pass) are the two files' remaining ambient work, both
   correctly left as-is — `miraSetup` for the same "many far-flung ambient
   callers, some without a receiver at all" reason `NTV()`/dispatch-table
   helpers stay ambient. `zig build test` green throughout (all 253 unit
   tests + integration suite + spine differential/golden corpus).
   `layer_check.py`: 0 new violations. `scorecard.sh`: ambient singleton-
   accessor call sites 694 → 690.

   **`graph/bignum.zig`, checked — already done.** Turns out to have been
   fully receiver-threaded in an *earlier* phase (2026-07-01, "Track
   SHARED_STATE, Phase 5 Tier 1", predating this whole Phase 4 step 5 effort)
   — every real function already takes the `*Heap`/`*Bignum` it needs
   explicitly, by the file's own module doc. Its 26 remaining
   `heap_mod.heap()` sites are all test-only (constructing a heap value for
   the test's own use, same convention as every other file's tests). Zero
   work needed.

   **Remaining, all grouped as one decision: three same-shape ambient
   clusters,** now that everything smaller has landed:
   - `infer.zig`'s `ap`/`tf`/`tf2`/`tf3`/`lt`/`pairType`/`NTV` cluster (~150
     call sites, `NTV()` alone ~100).
   - `lower.zig`'s own `codegen()`-internal `cons`/`ap`/`ap2`/`ap3` (~85 call
     sites: 47 + 38).
   - `parser/codegen.zig`'s file-wide ambient convention (~35 real sites) —
     checked this pass: unlike the other two, this isn't one giant switch/
     dispatch function but a *file-wide* pattern spread across many separate
     top-level functions (`codegenDef`/`codegenLocalDef`/`buildLdefs`/
     `applyWhereDefs`/`codegenExpr`/…), several of which recurse into each
     other and are themselves called from `parser_api.zig`/`match.zig`
     (`transtries` calls back into `lower.zig`'s `codegen`, which calls back
     into `codegen.zig`'s own helpers) — same *mechanical* shape as the other
     two (every site sits within a function whose callers, traced so far,
     already have `heap` on hand), but the *cascade path* is less contained:
     fixing it properly means touching most of `codegen.zig`'s own top-level
     functions' signatures, not just a handful of leaf helpers.

   Combined, these three clusters were ~270 call sites — noticeably bigger
   than any single slice landed earlier this session, concentrated in three
   files' core dispatch logic rather than spread thin. Explicitly chosen to
   cascade into all three rather than document them as an exception (they
   carry no recursion-depth stack-growth risk analogous to `dumpOb`'s, being
   driven by a program's static structure rather than unbounded runtime
   data, but the phase's own stated gate is a literal zero).

   **`lower.zig`'s `codegen()`-internal cluster, landed (2026-07-08).**
   `cons`/`ap`/`ap2`/`ap3` (and `makeTyp`, one more small helper found along
   the way) now take `heap: *Heap` explicitly. All ~85 real call sites sit
   within this file's own already-`heap`-scoped functions — a single
   scripted pass (insert `heap, ` as the first argument to every bare
   `cons(`/`ap(`/`ap2(`/`ap3(` call not already threaded) plus 4 manual
   fixups (one true ambient helper, `makeTyp`, needing its own signature
   change; three test blocks where the script's blanket `heap` substitution
   didn't have a real `heap` binding in scope and needed `heap_mod.heap()`
   instead, matching every other test's convention). `mkindex` stays
   ambient-internal (matches the pattern used for `heap.zig`'s own small
   leaf accessors). Zero external callers needed fixing — all four functions
   are file-private. `zig build test`: all 253 unit tests + integration
   suite + spine differential/golden corpus green. `layer_check.py`: 0 new
   violations. `scorecard.sh`: no regression (this metric only tracks the
   `.method()`-chained ambient style, not the argument-passing style this
   cluster used).

   **`infer.zig`'s dispatch-table cluster, landed (2026-07-08, same
   session).** `unify.zig`'s `mktvar`/`NTV` took `heap: *Heap` first (their
   own real callers — 2 in `unify.zig` itself, ~109 in `infer.zig` — needed
   the same scripted fix once converted); `infer.zig`'s own `cons`/`ap`/
   `ap2`/`tf`/`tf2`/`tf3`/`tf4`/`lt`/`pairType` followed the same way. One
   scripted pass across the whole file (insert `heap, ` as the first
   argument to every bare call to any of these ten names, careful to handle
   the zero-extra-argument case — `NTV()` → `NTV(heap, )` is invalid Zig
   syntax, needed a second pass collapsing `NTV(heap, )` → `NTV(heap)`)
   left only **2 real compile errors**, both genuinely-ambient functions
   with no receiver in their own call chain: `genlstatType()` (2 callers,
   both with `heap` in scope — converted to take it) and `tsetup()` (1
   caller, `compiler/setup.zig`'s `miraSetup`, itself deliberately ambient
   — `tsetup` stays ambient too, matching `miraSetup`'s own "many far-flung
   callers, some with no receiver at all" reason). Ambient
   `heap_mod.heap()` sites in `infer.zig`: ~150 → 1 (just `tsetup`'s single
   remaining internal read). `zig build test`: all 253 unit tests +
   integration suite + spine differential/golden corpus green — no
   dedicated extra stress test needed, since none of these are self-
   recursive on unbounded runtime data (`tf`/`tf2`/`tf3`/`tf4` bottom out in
   3-4 static calls each; `NTV()` itself doesn't recurse). `layer_check.py`:
   0 new violations. `scorecard.sh`: no regression. This was the single
   largest slice of the whole Phase 4 step 5 effort, and it went through
   essentially mechanically — the scoping pass's read (every real call site
   already sits within a `heap`-scoped function) held for all but 2 of
   ~260 combined call sites across `infer.zig`/`unify.zig`.

   **`parser/codegen.zig`'s file-wide cluster, landed (2026-07-08, same
   session) — the last of the three.** Unlike the other two clusters, this
   file's *outer* functions (`codegenExpr`, `codegenScript`, …) were
   themselves ambient too, not just their leaf helpers — so closing it
   required threading `heap` through all ~20 of the file's own functions
   (`h`/`t`/`tp`/`tg`/`ap`/`ap2`/`ap3`/`mkcons`/`mklabel`/`mklambda`/
   `mkpair`/`mktcons`/`bigscanZ`/`makeHere`/`isConstructorWord`/
   `codegenTypeVar`/`codegenType`/`opWord`/`codegenGuarded`/
   `floatLiteralOverflow`/`codegenString`/`codegenPattern`/`codegenExpr`/
   `codegenLhsExpr`/`codegenRhs`/`codegenLocalDef`/`buildLdefs`/
   `applyWhereDefs`/`codegenDef`/`codegenTypeSpec`/`codegenTypeDecl`/
   `codegenScript`) and, at the true boundary, through `semantics/modules.zig`'s
   own `%include`-processing chain (`processIncludes`/`processOneInclude`/
   `compileBindings`/`applyExportsAndAliases`) — traced back to confirm it
   terminates at `parser_api.zig`'s `runParsedTokens`, which already had
   `heap_ptr`. (`nameWord` was the one function checked and found *not* to
   need it — it only touches the symbol table, never a heap cell directly.)

   Same scripted-pass approach as the other two clusters (insert `heap_ptr, `
   as the first argument to every bare call of any of the ~30 target names,
   handling `floatLiteralOverflow()`'s zero-extra-argument case the same way
   `NTV()` needed). Left only 4 real compile errors: three "unused function
   parameter" cases (`bigscanZ`/`codegenTypeVar`/`floatLiteralOverflow` called
   `big.scanHex`/`heap.make`/`setup.syntax` directly with the old
   `heap.heap()` rather than through one of the ~30 scripted names, so the
   newly-added `heap_ptr` parameter went unused until those specific call
   sites were fixed by hand) and one real external-caller fixup
   (`parser_api.zig`'s two `codegenExpr`/`codegenScript` call sites and two
   `processIncludes` call sites — the production ones passing `heap_ptr`,
   the test-only `parseWithNew` passing `heap.heap()` ambiently, matching
   established convention for test-only paths). A follow-up sweep also found
   and fixed ~21 more `heap.heap()` reads left over *inside* now-`heap_ptr`-
   scoped functions (calls to already-heap-threaded external functions like
   `match.genlhs`/`trans.declare`/`trans.specify`/`types_mod.redtvars`/
   `reduce_mod.head` that weren't in the scripted names list, so the pass
   correctly left them alone but they were still passing the ambient
   singleton instead of the now-available `heap_ptr`) — `codegen.zig` is now
   the *only* one of the three clusters with a literal zero non-test ambient
   sites; `modules.zig` reached zero too.

   `zig build test`: all 253 unit tests + integration suite + spine
   differential/golden corpus green throughout every fixup round.
   `layer_check.py`: 0 new violations. `scorecard.sh`: ambient singleton-
   accessor call sites 690 → 683 (this cluster's clean-up included several
   `.method()`-chained calls — `heap.heap().validate()`/`.nill`/
   `.current_file` — that the scorecard's regex *does* catch, unlike the
   argument-passing style the other two clusters were mostly made of).

   **All three dispatch-table clusters are now done.** A final full-codebase
   sweep (2026-07-08, same session) found one more small, real fix
   (`io/files.zig`'s `sameFile`/`inodeId`, 2 callers in `module_loader.zig`,
   both with `heap` — converted) and confirmed every other remaining
   `heap_mod.heap()`/`heap.heap()` site in the whole codebase is one of:
   - **Test-only** — `testutil.zig` (the shared test harness — its
     `expectReducesTo`/`expectInt`/etc. helpers are deliberately simple 2-arg
     calls, not receiver-threaded), `reduce_test.zig`, `parser_tests.zig`,
     and inline `test "..."` blocks scattered through otherwise-fully-
     threaded files (`spine.zig`, `bignum.zig`, `lower.zig`, `combinators.zig`,
     `depend.zig`, …). None of these run in the production path.
   - **Individually-reviewed, no-receiver-anywhere leaf cases** — `mkindex`
     (`lower.zig`), `cons`/`fileinfo` (`lex.zig`, ~9 callers each), `outstats`
     (`reduce_rt.zig`), `dumpOb` (`graph/dump.zig`, deliberately ambient per
     its own doc comment — the dumpOb stack-depth story from earlier this
     phase).
   - **`miraSetup`/`tsetup`** (`compiler/setup.zig`/`semantics/infer.zig`) —
     re-examined at the end of this sweep with a sharper question than
     before: not just "does this have many ambient callers" but "does the
     *production* path (`mainEntry` → `miraSetup`) still touch the singleton
     even though `mainEntry` itself now receives `heap` explicitly?" **Yes.**
     `mainEntry` has `heap: *Heap` as a parameter now, but still calls
     `setup.miraSetup()` (no arguments), which internally reads
     `heap_mod.heap()` — for the single-`Interp`-per-process case today this
     is the *same* value, so it's not a correctness bug, but it *is* exactly
     the kind of gap the two-`Interp` isolation test (step 6) exists to
     catch: two concurrent `Interp`s would both have their `miraSetup()` call
     read whichever one happens to be `current_interp` at that moment, not
     necessarily their own. Fixing it means threading `heap` through
     `miraSetup`/`tsetup` and the ~15+ test-harness `freshInterp()`-style
     helpers that also call them with no natural `heap` binding today — a
     different, more invasive shape of work than anything landed so far
     this phase (changing a widely-used test convention, not just a
     production call chain), and not yet started.

   **Bottom line for the singleton-accessor gate:** every *production* call
   path except `miraSetup`/`tsetup` is now fully receiver-threaded from
   `main()` down to `reduce()`. `miraSetup`/`tsetup` is the one remaining
   real gap standing between here and a literal zero, and it's the right
   next thing to scope before attempting step 6, since the two-`Interp` test
   would fail on exactly this gap today.

   **Landed (2026-07-12): `miraSetup`/`tsetup` closed out — the last real
   production gap.** Turned out much smaller than the "~15+ test-harness
   helpers" the sweep speculated: `miraSetup()` had exactly 6 real call
   sites, and `tsetup()` had exactly 1 (`miraSetup` itself). Converted:
   - `compiler/setup.zig`: `pub fn miraSetup(heap: *Heap) void` (was
     zero-arg, read `heap_mod.heap()` internally). Its own body already used
     a local `heap` identifier throughout, so the only internal change was
     the now-redundant `setupheap()` free-function call becoming
     `heap.setupheap()` (the struct method, via Zig's automatic
     pointer-receiver dereferencing) and `tsetup()` becoming `tsetup(heap)`
     — deliberately *not* touching `setupheap()`'s other 3 (test-only)
     callers.
   - `semantics/infer.zig`: `pub fn tsetup(heap: *Heap) void` (was zero-arg,
     same pattern) — body already used `heap` consistently once the
     parameter existed.
   - The 6 real callers, each threaded a `heap` value in exactly one place
     and passed it down: `session/boot.zig`'s `mainEntry` (already had
     `heap` in scope), `testutil.zig`'s `freshInterp()`, `micro_benchmarks.zig`'s
     `main()`, `parser/parser_tests.zig`'s `resetLexerState()`,
     `eval/reduce_test.zig`'s `ensureSetup()` (all four test-harness
     bootstraps capture `heap.heap()` once at the top, matching the same
     "ambient exactly once, then threaded" shape as `main()`/`mainEntry()`
     themselves), and `compiler/setup.zig`'s own
     `test "miraSetup initialisation and primitive seeding"` block.
   - Confirmed via grep that both functions' signatures now take `heap`
     as a real parameter and neither has any remaining internal
     `heap_mod.heap()`/`heap.heap()` read — the only ambient capture left
     is the one-time bootstrap call in each test harness/entry point,
     which is the accepted, deliberate shape everywhere else in this phase.
   - `zig build` clean; full `zig build test` (253 unit tests, `mira_tests`
     integration suite, spine differential/golden corpus, `sigint_check`)
     green; `layer_check.py` unchanged ("52 allowlisted, 0 new");
     `scorecard.sh --check` shows no regression (ambient-call-site metric
     stays at 683 — this slice used the argument-passing style throughout,
     not the `.method()`-chained style the metric's regex matches, so the
     count doesn't move even though the last real gap is now closed).

   With this, **every production call path from `main()` down to `reduce()`
   and `miraSetup()`/`tsetup()` is fully receiver-threaded** — the
   remaining `heap_mod.heap()`/`heap.heap()` sites codebase-wide are all
   either test-only or the individually-reviewed no-receiver-anywhere leaf
   cases catalogued above. Step 6 (the two-`Interp` isolation test) is now
   unblocked.

   **Landed (2026-07-12): step 6, the two-`Interp` isolation test — the
   phase's own definition of done.** Added
   `test "Interp: two independent instances stay isolated when interleaved"`
   in `session/interp.zig` (previously untested — the file wasn't even in
   `main.zig`'s comptime test-aggregation list; added it there too). The
   test constructs two `Interp` values directly (bypassing the module-level
   `backing` default), then interleaves work across them by swapping
   `current_interp`:
   - `miraSetup(heap.heap())` runs once per `Interp`, each seeding its own
     heap/dictionary/primenv independently.
   - Each gets a distinct boxed bignum (111 for `a`, 222 for `b`).
   - Between checks, 2,000 `CONS` cells are churned into whichever `Interp`
     is *not* being asserted on, specifically to catch aliasing: if the two
     heaps ever shared storage (a stale cached pointer, a read that missed
     the `current_interp` swap), the churn would move or overwrite the
     other's cell and the subsequent `reduce()` would return garbage
     instead of the expected value.
   - Checks run in both directions (churn `b`, assert `a`; then churn `a`,
     assert `b`) via `reduce(heap.heap(), ap2(heap.heap(), PLUS/TIMES, ...))`
     — the same production `reduce`/`ap2`/`miraSetup` entry points threaded
     throughout this whole phase, not a special test-only path.
   - All four checks pass: `112`, `444`, then (after reverse-direction
     churn) `223` — proving the interleaved evaluation genuinely stayed
     isolated rather than coincidentally not colliding.
   - `zig build`/`zig build test` (254 unit tests now, `mira_tests`, spine/
     golden corpus, `sigint_check`) green; `layer_check.py` unchanged.
   - `scorecard.sh --check` flagged `current_interp references` rising
     47→56: expected and accepted (`--update-baseline` applied) — the test's
     entire point is to manipulate `current_interp` directly, so referencing
     it repeatedly is inherent to what it verifies, not a reintroduction of
     ambient production coupling.

   This closes Phase 4 step 6. What step 5's own text also asks for —
   literally *deleting* `heap.heap()`/`rs()`/`cs()`/`ls()`/`ev()`/`s()`/
   `interp.reset()` — was not done: the final sweep (2026-07-12, above)
   found every remaining ambient call site is either test-only or an
   individually-reviewed leaf case with no receiver anywhere in its call
   chain, and converting those (widely-used test-harness convention, small
   high-fanout leaf helpers) is a different, much larger shape of churn than
   anything gated on production correctness. The two-`Interp` test — the
   phase's stated definition of done — now passes with the accessors left
   in place for that narrower, deliberate purpose, so deleting them outright
   is deferred rather than treated as a blocking requirement.

**Gate:** singleton-accessor count = 0 in production call paths (test-only
and individually-reviewed leaf-case ambient reads remain, see above);
module-level mutable globals = 1 (the interrupt flag); DAG check green with
empty allowlist; files > 1,000 lines = 0; goldens identical; two-`Interp`
isolation test green.

**Risks:** sheer churn (~1,600 sites) — mitigated by subsystem slicing, move-only
commits separated from signature changes, and the behaviour gates making regressions
cheap to bisect.

---

### Phase 5 — Typed object model

**Goal:** `graph/value.zig` per §4.3; the untyped `Word` confined to `dump.zig`.

**Why last among the big phases:** it rewrites the same lines Phase 4 touched, but
by then every site is a method call on an explicit receiver with real errors and no
libc — each retyping is local and mechanical. Doing it earlier would mean typing
code that was about to move twice.

**Steps**

1. `Comb = enum(u16)` generated to match the existing code table (names from
   `combinator.cmbnms`; `False`/`True`/`NIL`/`NILS`/`UNDEF` are members). After
   Phase 1 the lexical token codes no longer share the value space, so the atom
   range is combinators + named atoms only — document the (unchanged) numeric
   layout in `dump.zig` as wire format.
2. `Value` (`packed struct(u64)`) + `CellRef` + `kind()`; constructors and an
   escape hatch (`fromRaw`/`toRaw`) for the migration window. The `Ref`/`classify`
   seam and `isAtom`/`fitsInByte`/`isLatin1Char` fold into it.
3. **Heap API typed:** `cons`/`ap`/`make` take and return `Value`; `hd`/`tl` return
   `Value`; typed payload accessors (`intVal`, `dblVal` — retiring `fpdatum` for one
   `@bitCast` site, `strId` — retiring the sign-negation convention for an explicit
   non-traced payload variant, `idInfo`, `fileInfo`). `Tag` (today's `NodeTag`)
   documents each variant's `hd`/`tl` payload meaning in one place.
4. **Migrate leaf-first,** each step green + benched: `reduce_core`/`spine` (machine
   registers become `Value`), combinator handlers, `bignum`, `graph/print`,
   `semantics/lower` + `infer`, `session`. The `toRaw` escape-hatch count is the
   ratchet metric; it ends at ~0 with `Word` alive only inside `dump.zig`.
5. **Perf gate every commit:** `bench-micro` + macro benchmarks. `packed
   struct(u64)` + inline methods compile to the same machine ops as raw `i64`; if a
   step regresses, inspect the hot loop before proceeding.

   **Landed (2026-07-12), step 1: `Comb`.** New `src/graph/value.zig`
   (registered in `main.zig`'s comptime test list). `Comb` is generated at
   comptime *directly from `combinator.cmbnms`* — not hand-transcribed —
   specifically so it can never drift from the numbering `word.zig`'s
   `S`/`PLUS`/`NIL`/… constants and every reducer dispatch table depend on.
   141 members (`cmbnms.len - 1`, excluding `cmbnms`'s own trailing `null`
   end-sentinel), `False`/`True`/`NIL`/`NILS`/`UNDEF` included as the plan
   specifies, numbered `0..140` matching `CMBASE + n`.
   - **Toolchain finding, worth recording for the rest of this phase:** this
     Zig version (0.16.0) has **no `@Type` builtin** — reification was split
     into per-kind builtins. The enum one is
     `@Enum(tag_type: type, mode: std.builtin.Type.Enum.Mode, field_names: []const []const u8, field_values: []const tag_type) type`
     (`mode` is `.exhaustive`/`.nonexhaustive`, replacing the old
     `is_exhaustive: bool` field; there is no `decls` parameter at all).
     Presumably `@Struct`/`@Union`/`@Pointer`/`@Vector`/`@Int` follow the
     same "per-kind, own argument list" shape — check each against a small
     throwaway file the same way (deliberately wrong arg count/types to read
     the compiler's own corrections) before assuming the old `@Type(info)`
     shape applies when step 2 gets to `Value`/`CellRef`.
   - `@setEvalBranchQuota(10_000)` needed inside the comptime block:
     `std.mem.span` on cmbnms's 141 `[*:0]const u8` entries at comptime
     exceeded the default 1000-backwards-branch budget.
   - Verified against `word.zig`'s numbering with a dedicated test spot-
     checking `S`, `PLUS`, `False`, `True`, `NIL`, `NILS`, and `UNDEF` (the
     last one below `ATOMLIMIT`), plus the member count. `Comb` has no
     callers yet — it's step 1 only, additive and inert; nothing in the
     production path reads it.
   - `zig build`/`zig build test` (255 unit tests, integration suite,
     spine/golden corpus, `sigint_check`) green; `layer_check.py`/
     `scorecard.sh --check` unchanged (this step added a type, not a
     C-accent removal, so no tracked metric was expected to move).

   **Landed (2026-07-12), step 2: `CellRef`/`Kind`/`Value`.** Added to
   `graph/value.zig`, still purely additive — no production caller yet.
   - `CellRef = enum(u32)` wraps a raw cell-index `Word`. `of`/`toWord` are
     free: `Heap.h`/`.t`/`.getTag` already subscript their column arrays with
     the cell's `Word` directly (confirmed by reading `heap.zig`), so there's
     no offset to apply — a `CellRef`'s numeric value is exactly the `Word`
     it wraps, just given a type a cell *count* can't be confused with.
   - `Kind = union(enum) { imm: u8, comb: Comb, cell: CellRef }` — the
     `Comb`/`CellRef`-typed successor to `word.classify`'s
     `Value{ .imm / .atom / .ref }`. Only the names changed for two of the
     three (`.atom`→`.comb`, `.ref`→`.cell`): `.imm` deliberately stays a
     single ambiguous `u8` rather than splitting into `char`/`small` as
     §4.3's illustrative sketch shows, because the bits themselves can't
     tell a bare Latin-1 char from a small int/index — same ambiguity
     `word.classify`'s own doc comment already documents. A `char` reader
     that also covers non-Latin-1 code points needs the cell's tag
     (`UNICODE` vs bare), i.e. heap access — that's a step 3/4 typed
     accessor, not something a raw, heap-independent `Kind` can do.
   - `Value = packed struct(u64) { raw: i64 }` — bit-identical to the `Word`
     it replaces (confirmed: `packed struct(u64)` over one `i64` field is 8
     bytes, same layout), so `.x` dump files and the reducer's bit tricks
     are untouched by this step. `fromRaw`/`toRaw` are the migration-window
     escape hatch named in §4.3; `imm`/`comb`/`cell` are the typed
     constructors; `kind()` reads a `Value` back into its `Kind`.
   - Round-trip tests cover all three roles both ways (`fromRaw(word.S).kind()
     == .{.comb=.S}`, `Value.comb(.PLUS) == Value.fromRaw(word.PLUS)`, same
     for `.imm`/`.cell`) plus `toRaw` as the exact inverse of `fromRaw`.
   - `zig build`/`zig build test` (257 unit tests now, integration suite,
     spine/golden corpus, `sigint_check`) green; `layer_check.py`/
     `scorecard.sh --check` unchanged (additive again — no `Word` call site
     converted yet, so the `toRaw`-count ratchet mentioned in step 4 hasn't
     started moving; that begins at step 3, the heap-API retyping).

   **Landed (2026-07-12), step 3a: typed heap-graph accessors, coexisting
   with the `Word` API.** `graph/value.zig` gained `hOf`/`tOf`/`makeOf`/
   `consOf`/`apOf`/`tagOf`/`setTagOf` — the `Value`-typed successors of
   `Heap.h`/`.t`/`.make`/`.cons`/`eval/reduce_core.zig`'s `ap`/`.getTag`/
   `.setTag`.
   - **Scope decision, worth recording:** the plan's own wording ("Heap API
     typed: cons/ap/make take and return Value") reads as an in-place
     retype of the existing methods. Read literally, that's a single
     Zig-enforced atomic edit — every call site across the whole codebase
     (`reduce_rt`/`spine`/every combinator handler/`bignum`/`print`/`lower`/
     `infer`/`match`/`unify`/`dump`/`module_loader`/`codegen`/session
     state — easily 1,000+ sites, an order of magnitude past the largest
     single cluster this project has converted so far, `infer.zig`'s ~150)
     would have to change in the same commit, because Zig has no function
     overloading and no partial typing. Doing that in one pass risks
     exactly the kind of large, unreviewable, hard-to-bisect diff this
     project's own cadence (small green commits, gated by build+test every
     step) exists to avoid. Instead this step follows the precedent already
     set by Phase 1 (the native `syntax/` pipeline was built and proven
     *beside* the legacy lexer for 7 steps before the legacy path was
     deleted in step 8) and by Phase 4 step 5 (ambient accessors coexisted
     with threaded receivers until every real call site was converted):
     new `*Of` functions coexist with the unchanged `Word`-typed `Heap`
     methods; step 4 migrates callers onto them one subsystem at a time;
     `Heap.h`/`.t`/`.cons`/`.make` are renamed/removed only once nothing
     references the `Word` form — "no parallel half-migrations" means a
     shim is gone by the *end* of the phase that introduced it, not
     instantly.
   - `apOf` is defined in `graph/value.zig` itself (not imported from
     `eval/reduce_core.zig`) to keep `graph/` a leaf layer per §4.1 — `ap`
     is just `make(.AP, x, y)`, so nothing from `eval/` was actually needed.
   - Test builds a `CONS`, an `AP`, and a `PAIR`-retagged-to-`LABEL` cell
     entirely through the typed accessors, then cross-checks every read
     against the existing `Word`-typed API on the *same* cells — the point
     being "coexist without diverging," not just "compiles."
   - One scorecard false positive found and fixed: a test-local variable
     named `c` (for "cell") false-positived the `clib./c.` C-interop-call
     metric's regex (`\bc\.[a-zA-Z0-9_]+`, meant to catch things like
     `c.foo()` C-library calls) purely because Zig method syntax on a
     variable named `c` looks identical to that pattern. Renamed to
     `cell_val`; not a real regression, just a naming collision with the
     metric's own regex.
   - `zig build`/`zig build test` (258 unit tests, integration suite,
     spine/golden corpus, `sigint_check`) green; `layer_check.py` unchanged;
     `scorecard.sh --check` clean after the rename above.

   **Landed (2026-07-12), step 3b: typed payload accessors — closing out
   step 3.** Added to `graph/value.zig`:
   - `intVal`/`intOf` wrap `bignum.zig`'s `toInt`/`fromInt` unchanged.
     Finding worth recording: every Miranda integer boxes as an `INT`
     bignum-digit-chain cell regardless of magnitude — there is no
     bare-immediate small-int shortcut the way there is for chars (an
     earlier test draft assumed one and failed with "expected .imm, found
     .cell"; fixed by testing against the actual behavior). Signatures use
     `i64`, not `bignum.toInt`'s own wider C-style return type, to avoid
     introducing a new C-style integer type at this boundary — the
     scorecard's `c_int`/`c_long`/etc. metric tracks that count toward zero
     outside `os.zig`, and a literal type-name mention even inside a doc
     comment counts too (the metric is a blind text grep, not
     syntax-aware) — both found and fixed before landing.
   - `dblVal`/`dblOf`/`setDblOf` wrap `heap.zig`'s `getDbl`/`stoDbl`/`setdbl`
     unchanged. §4.3's "retiring `fpdatum` for one `@bitCast` site" is real
     — `Word` is unconditionally 8 bytes now, so the union's 4-byte-split
     branch is dead code — but deliberately deferred rather than bundled
     here: that's an edit to already-working, GC-adjacent bit-level code
     this project's own working notes already flag as fragile, and it
     deserves its own focused pass once a caller actually migrates onto
     `dblVal`/`dblOf` (step 4), not a drive-by inside an additive step.
   - `asFileNode`/`fileNodeOf` and `asIdentifier`/`identifierOf` bridge
     `Value` to the *existing* `Heap.FileNode`/`Heap.Identifier` domain
     wrappers (`§4.3`'s "fileInfo"/"idInfo") — those single-field
     Word-wrapping structs already existed before this phase (heap.zig's
     "Domain types (C2)" seam), so there was no new accessor logic to
     write, only a `Value`-typed way in and out.
   - `strId` is deliberately given **no** `Value` integration, and the plan
     doc now says why in the file itself: a string-table id is a raw `Word`
     that only ever appears in specific known payload slots of specific
     cell kinds, never as a general reducer `Value` — forcing a `.strid`
     branch into `Kind`'s classification would blur the boundary
     `Value.kind()`'s own doc comment already draws ("marked spine words
     and sentinels — negative — are not values, mask them off first") for
     no real gain. `strtab.zig`'s `strBits`/`strOf` remain the right typed
     accessors for that payload, untouched.
   - Two scorecard false positives found and fixed during this slice (both
     from the metric being a blind text grep, not syntax-aware): the
     `c_longlong` doc-comment mention above, and (same lesson repeated) a
     test constant compared with `@as(c_longlong, ...)` before being
     switched to `@as(i64, ...)` to match the retyped signature.
   - `zig build`/`zig build test` (260 unit tests, integration suite,
     spine/golden corpus, `sigint_check`) green; `layer_check.py` unchanged;
     `scorecard.sh --check` clean.

   **This closes step 3.** `graph/value.zig` now has the complete typed
   surface §4.3 asked for — `Comb`/`CellRef`/`Kind`/`Value`, the graph
   accessors (`hOf`/`tOf`/`makeOf`/`consOf`/`apOf`/`tagOf`/`setTagOf`), and
   the payload accessors (`intVal`/`intOf`, `dblVal`/`dblOf`/`setDblOf`,
   `asFileNode`/`fileNodeOf`, `asIdentifier`/`identifierOf`) — all coexisting
   with the unchanged `Word`-typed originals, all additive, zero production
   callers yet. Step 4 (migrate real subsystems onto this surface, leaf-first:
   `reduce_core`/`spine` first per the plan's own order) is next.

   **Investigation (2026-07-12), before touching `reduce_core`/`spine`: is
   the "marked spine word" risk real?** `ReductionCtx.e` (the focus register
   step 4 names first) sometimes triggers `abnormal(ctx.e)` — a negative-
   `Word` check — in `reduce.zig`'s `dispatchNonCombinatorHead`, and
   `Value.kind()` explicitly assumes clean, non-negative input. Before
   retyping the registers, traced every path that can set `ctx.e`/`.hold`/
   `.args`, since a wrong assumption here would be a real hot-path
   correctness bug. Finding: the risk is **dead architecture, not live data
   flow**. `spine.zig`'s own module doc confirms the old in-graph pointer-
   reversal encoding (which genuinely did borrow a cell's `hd`/`tl` bits to
   store a tagged "previous stack top" pointer — the actual source of the
   historical "marked word" concern) was fully replaced by the explicit
   `Spine.Frame { node: Word, via_tl: bool }` struct: `via_tl` is a real,
   separate `bool` field, not a sign-bit trick on `node`. `ctx.s` (the old
   register that used to carry the `BACKSTOP` sentinel) no longer exists in
   `ReductionCtx` at all. Every live path that sets `ctx.e` (`Spine.downLeft`/
   `.upLeft`/`.upRight`, and the `STRCONS`/`ID` dispatch cases, which read a
   name node's bound-value tail) reads a genuine graph value, never a marked
   one. The one remaining `abnormal(ctx.e)` check is a corruption/invariant-
   violation safety net ("BLACK HOLE" = "this should be structurally
   impossible") — the same category as `heap.badval`'s "flags values outside
   the plausible heap range" — not business logic `Value.kind()` needs to
   handle correctly. Conclusion: retyping the registers to `Value` is safe;
   `abnormal`/`isXxx` predicates just become raw `.toRaw() < 0` /
   `tagOf(heap, v) == .X` checks that never call `.kind()` at all, preserving
   the exact same defensive semantics.

   **Landed (2026-07-12), step 4a: `spine.zig` — the first non-additive
   consumer of the typed surface.** `Spine.Frame.node` and every `Spine`
   method (`downLeft`/`downRight`/`downright`/`upLeft`/`upleft`/`upRight`/
   `popNodeOnly`/`pushRaw`/`markAllRoots`) now carry `Value` instead of
   `Word` — genuinely retyped, not wrapped. Scope, deliberately bounded: the
   plan's step 4 bullet lists `reduce_core`/`spine` together, but
   `ReductionCtx.e`/`.hold`/`.args` (and every combinator handler across
   `combinators.zig`/`ready.zig`/`lex.zig`/`io.zig` that touches them —
   ~94 call sites) are **not** retyped in this slice; only `Spine` itself
   is. `Spine`'s entire external call-site surface turned out to be small
   and fully enumerable — grepped for it rather than assumed: `reduce_core
   .zig`'s four wrappers (`downLeft`/`downRight`/`upLeft`/`upRight`),
   `combinators.zig`'s `handleTRY`/`handleFAIL` (the two handlers that
   manipulate the spine directly), and two bare `.isEmpty()` checks
   (`reduce.zig`, `reduce_rt.zig`) needing no change at all. Every one of
   those (still-`Word`-typed) callers converts at the boundary via
   `Value.fromRaw`/`.toRaw()` — `ctx.e` itself stays `Word` until
   `ReductionCtx` is retyped in a later slice.
   - Bit-identical by construction: `Value` is `packed struct(u64) { raw: i64
     }`, so every `fromRaw`/`toRaw` pair the boundary needed is a free
     reinterpretation, not a real conversion — the reducer's actual
     behavior is untouched, only the type flowing through `spine.zig`'s own
     API changed.
   - Verification went beyond "it compiles": ran `zig build bench` before
     any edit and after, three times each. Reduction *counts* (the number
     of rewrite steps taken, not just wall-clock time) matched exactly
     across every run, before and after — Ackermann(3,8) 30,652,009,
     Fibonacci(30) 28,907,260, Prime Sieve 671,945 — the strongest
     available signal that the migration changed representation, not
     behavior. Throughput stayed within normal run-to-run noise (Ackermann
     ~51-64 M reductions/s, Fibonacci ~70-72, Prime Sieve ~32, matching the
     pre-migration baseline's same ranges).
   - Also fixed as a prerequisite (own commit, `27b5c94`): `zig build bench`
     itself was broken two ways before this slice could even get a baseline
     — `bench_micro_module` was missing the `zigline` import
     `bench_mira_module` already had, and underneath that,
     `micro_benchmarks.zig`'s `benchAllocation`/`benchGC` still called the
     old 3-arg `heap.make(.CONS, x, y)`, stale since Phase 4 threaded a
     `heap_ptr` receiver through the free function — never caught because
     `micro_benchmarks.zig` isn't part of any `zig build`/`zig build test`
     target, only the rarely-run `bench-micro` one.
   - `zig build`/`zig build test` (260 unit tests, integration suite,
     spine/golden corpus, `sigint_check`) green; `layer_check.py`/
     `scorecard.sh --check` unchanged.

   **Landed (2026-07-13), step 4b: `ReductionCtx.e`/`.hold`/`.args` retyped
   to `Value`, cascading through the entire combinator dispatch layer.**
   `reduce_core.zig`'s register file and every accessor/classifier/rewrite
   helper it defines (`hdGet`/`hdSet`/`tlGet`/`tlSet`/`getTag`/`setTag`/
   `downLeft`/`downRight`/`downright`/`upLeft`/`upleft`/`upRight`/`GETARG`/
   `getarg`/`simpl`/`abnormal`/every `isXxx`/`idVal`/every `rewriteToXxx`/
   `ap`/`apTwo`/`cons`/`ap2`/`neg`/`poz`/`pnVal`/`getId`/`constrName`/
   `suppressed`/`forceDbl`/`coerceDbl`/`bigzero`) now take/return `Value`.
   Cascaded through `reduce.zig`'s main dispatch loop (`switch (ctx.e.toRaw())
   { word.S => ..., }` — switches on the raw bits, since `word.*` combinator
   constants aren't migrated), `reduce_rt.zig`'s `streamRead` (the one
   function there that touches `ctx.e`/`.args` directly — its own private
   `Word`-typed `t`/`h`/`tp`/`rewriteToNil`/`rewriteToCons` duplicates stayed
   untouched, converting at the boundary), and every handler in
   `combinators.zig`/`ready.zig`/`combinators/lex.zig`/`combinators/io.zig`.
   - **Scope decision:** `reduce()`'s own public signature stayed
     `Word`-in/`Word`-out — it's called from hundreds of sites across every
     subsystem, not just the reducer, so retyping it is a separate, much
     larger cascade left for later. Added `reduceVal`/`headVal`/`forceVal`/
     `getstringVal`/`badcaseErrorVal`/`confErrorVal` — thin `Value`-typed
     wrappers over the still-`Word`-typed `reduce`/`head`/`force`/
     `getstring`/`badcaseError`/`confError` — and scripted a rename of every
     `reduce.reduce(`/`.head(`/`.force(`/`.getstring(`/`.badcaseError(`/
     `.confError(` call across the four handler files onto them, since the
     callers already had `Value`-typed arguments in hand.
   - **Mechanical pattern, used almost everywhere:** every bare `word.CONST`
     passed where a `Value` was now expected became `Value.fromRaw(word.CONST)`;
     every `Value` compared against a `word.CONST` became `.toRaw() ==`/`!=`;
     calls into not-yet-migrated subsystems (`bignum`'s `toInt`/`fromInt`/
     `add`/`sub`/`mul`/`div`/`mod`/`pow`/`negate`/`toFloat`/`parseString`/
     `toDecimalList`/`toHexList`/`toOctalList`/`fromFloat`/`ln`/`log10`,
     `heap`'s `getDbl`/`setdbl`/`stoDbl`/`stoChar`/`stosmallint`/`make`,
     `strtab`, `reduce_rt`'s `compare`/`numplus`/`wrapPtr`/`piperrmess`/
     `memclass`/`lexstate`/`gResidue`/`parseCloseError`) converted at the
     boundary (`.toRaw()` in, `Value.fromRaw(...)` wrapping the result out).
     Scripted where the pattern was uniform (regex passes per file, the same
     technique used throughout Phase 4's big clusters); the rest — several
     dozen sites where a bare char literal needed `Value.imm(')')` instead
     of `Value.fromRaw(...)`, where a local variable turned out to be a
     genuine scalar counter rather than a graph value (`handleMKSTRICT`'s
     strictness count, `handleDROP`'s/`handleSUBSCRIPT`'s decrementing
     index) and needed decoding once via `.toRaw()` rather than converting
     at every use, or where two helper functions (`lex.zig`'s/`ready.zig`'s
     own private `lastarg`/`lastArg` wrappers) needed their own return type
     changed — were fixed by hand, compiler-error-driven, one `zig build`
     cycle at a time.
   - Also touched as direct fallout: `testutil.zig`'s `ap`/`ap2`/`cons`/
     `list`/`str` (the shared test harness — kept `Word`-in/`Word`-out at
     its own public boundary, converting via `Value.fromRaw`/`.toRaw()`
     internally, exactly like `reduce()` itself), `reduce_test.zig`'s local
     `ap`/`ap2` helpers and one direct `reduce.cons` call, `session/interp.zig`'s
     two-`Interp` isolation test's `reduce.ap2` calls, and one inline test
     in `combinators.zig` itself (`handleITERATE`'s).
   - **Verification, not just "it compiles":** full `zig build test` (260
     unit tests, `mira_tests` integration suite, spine differential/golden
     corpus — every golden case, every `miralib/ex/` program — `sigint_check`)
     green. `zig build bench` run repeatedly (with normal spacing — see the
     flakiness note below) both before and after: reduction *counts*
     matched the pre-migration baseline exactly every clean run
     (Ackermann(3,8) 30,652,009; Fibonacci(30) 28,907,260; Prime Sieve
     671,945), the strongest available signal that behavior, not just
     representation, is unchanged. Throughput stayed in the same noisy
     ranges as every prior bench check this phase.
   - **Benchmark-harness flakiness found, not caused by this slice:**
     running `zig build bench` twice in immediate succession (no gap)
     intermittently produces a spurious "7 reductions" result for both
     Ackermann and Fibonacci simultaneously — `tests/benchmark_runner.zig`
     writes the *same* temp path (`./tests/golden/bench_tmp.m`) for every
     benchmark and re-invokes the binary through it; back-to-back `zig
     build bench` calls appear to race that shared file. Confirmed
     pre-existing (reproduced identically during this same segment's
     earlier `zig build bench` fix, before any register retyping) and
     confirmed harmless: spacing invocations by even ~1 second (sequential
     shell commands, not literally simultaneous) reproduces the correct
     reduction counts every time. Not fixed here — out of scope for a
     type-migration slice — but worth flagging for whoever next touches
     the bench harness.
   - `layer_check.py` unchanged. `scorecard.sh --check` found one real,
     expected regression: `[*:0] C-string types` rose 227→228, from the new
     `getstringVal` wrapper's own signature (`cmd: ?[*:0]const u8`) — a
     legitimate byproduct of adding one more C-string-typed function during
     the migration, not a new C-accent introduced gratuitously; baseline
     updated.
   - Full commit-by-commit reconstruction of every intermediate scripted
     pass and hand-fix is in the commit history, not repeated here; this
     note covers the shape and verification, not a blow-by-blow.

   **Landed (2026-07-13), step 4c: `bignum` — typed wrappers, not an
   in-place retype.** Scoped `bignum.zig` before touching it: ~66 external
   call sites, but internally the file has **hundreds** more (its own
   ~23-test inline suite alone builds fixtures via 45 `fromInt`/41 `toInt`
   calls), and every one of `add`/`sub`/`mul`/`div`/`mod`/`negate`/`cmp`
   works through raw `*Word` cell mutation (`digitPtr`/`restPtr`,
   carry/borrow digit-chain logic) — exactly the kind of delicate,
   bit-level code this project doesn't touch as a drive-by in a type-
   migration pass (the same caution already applied to `heap.zig`'s
   `fpdatum` trick, see step 3b's `dblVal` note). Retyping it in place
   would be a cascade comparable to or larger than step 4b's, spent on the
   file most sensitive to a subtle carry-logic mistake.
   - Instead, extended the same pattern step 3b already established for
     `intVal`/`intOf` (which already wrap `bignum.toInt`/`.fromInt`) to the
     rest of `bignum.zig`'s public API: `isNatVal`/`negateVal`/`addVal`/
     `subVal`/`cmpVal`/`mulVal`/`divVal`/`modVal`/`powVal`/`toFloatVal`/
     `fromFloatVal`/`lnVal`/`log10Val`/`parseStringVal`/`toDecimalListVal`/
     `toHexListVal`/`toOctalListVal` — all in `graph/value.zig`, all thin
     `Value`-in/`Value`-out shims over the unchanged `Word`-typed
     originals. `bignum.zig` itself was not opened for editing at all.
   - One layer-check catch worth recording: the first draft of this
     slice's test reached `*Bignum` via
     `@import("../session/interp.zig").current_interp.big` directly from
     `graph/value.zig` — a genuine new `graph → session` edge (`graph`'s
     own layer rule is "may import nothing outside itself"), not grand-
     fathered the way `bignum.zig`'s *own* identical read already is
     (`src/graph/bignum.zig -> src/session/interp.zig` is in
     `layer_allowlist.txt`; `value.zig`'s equivalent wasn't). Fixed by
     calling `big.bn()` — `bignum.zig`'s own existing convenience
     accessor — instead of reaching into `interp.zig` a second, independent
     way; zero new allowlist entries needed.
   - `zig build`/`zig build test` (261 unit tests, integration suite,
     spine/golden corpus, `sigint_check`) green; `layer_check.py` clean
     after the fix above; `zig build bench` reduction counts still match
     the pre-migration baseline exactly. `scorecard.sh --check` found one
     small, accepted regression: `c_int/c_long/c_uint/c_ulong` rose 164→166
     — `cmpVal`/`parseStringVal` mirror `bignum.cmp`/`.parseString`'s own
     pre-existing `c_int` return/param exactly (no new C-style type
     introduced, just one more signature naming the same type); baseline
     updated.
   - No caller migrated onto these wrappers in this slice — `ready.zig`/
     `combinators.zig`/`reduce_core.zig` keep calling `bignum.zig` directly
     via `.toRaw()` at the boundary (established in step 4b). Swapping them
     onto `addVal`/`subVal`/etc. is a pure readability follow-up, not
     required for correctness, and deliberately left for later so this
     slice stayed additive and low-risk like steps 1-3.

   **Scoped (2026-07-13), `graph/print`: found genuinely nothing to do yet
   — recorded rather than acted on.** `print.zig`'s only external callers
   are `graph/dump.zig` (`castPtr`, 3 sites), `semantics/type_errors.zig`
   (`charname`, 1 site), and `eval/reduce_rt.zig` (`charname`/`outTerm`, 5
   sites) — every one of them a **still-`Word`-typed** local (`dump.zig`'s
   own wire-format walk, `type_errors.zig`'s own private `getTag`/`h`/`t`
   helpers, `reduce_rt.zig`'s own `e`/`hold_val`/`ptr[i]`/`lh(...)`
   locals). Retyping `print.zig`'s public functions to `Value` right now
   would mean every one of those 9 call sites immediately wraps its
   already-`Word` local in `Value.fromRaw(...)` just to satisfy the new
   signature, then `print.zig` immediately unwraps it again internally —
   pure boilerplate, no actual type-safety gained, because *none* of
   `print.zig`'s current callers hold a real `Value` in hand yet. This is
   different from `bignum`'s wrapper layer (step 4c), which had genuine
   `Value`-typed callers ready to use it immediately (`ready.zig`/
   `combinators.zig` post-step-4b). `print.zig` becomes a good candidate
   again once `reduce_rt.zig` and/or `semantics/type_errors.zig` migrate
   their own locals onto `Value` — at that point its callers will already
   have a `Value` to pass, and retyping stops being boilerplate. No code
   changed in this scoping pass.

   **Same check applied to `semantics/lower` + `infer` and `session`: same
   answer.** `lower.zig`'s/`infer.zig`'s own `cons`/`ap`/`ap2`/`ap3`/`tf`-
   family functions were heap-*threaded* back in Phase 4 step 5 (an
   explicit `heap: *Heap` parameter instead of reading the singleton), but
   never re-*typed* — they're still `Word`-in/`Word`-out. Their callers
   (`codegen.zig`, `match.zig`, `unify.zig`, `type_errors.zig`,
   `module_loader.zig`, `repl.zig`, `setup.zig`, `lex.zig`) are every one
   of them compile-time front-end code — the parser/codegen/type-checker/
   module-loader pipeline — and **none of it has been touched by `Value`
   at all**, since this phase's work so far is confined to the `graph`/
   `eval` layers (the runtime reducer side), not `semantics`/`parser`/
   `compiler` (the compile-time side). Retyping `lower`/`infer` right now
   would hit the identical "boilerplate wrapping, no real caller benefit"
   problem `print.zig` did. "`session`" has the same root cause one layer
   further out still: nothing in `session/` holds a bare graph `Word` in a
   way `Value` would improve — it's `*Heap`/`*RuntimeState`/etc. struct
   wiring, not individual value payloads.
   - **What this actually means for the rest of step 4:** the plan's
     listed remaining items aren't independent, pick-any-one slices — they
     collectively describe *the entire compile-time front end*
     (`semantics/*`, `parser/codegen.zig`, `compiler/*`), which would need
     to move onto `Value` together (mutually, since they all call each
     other) before any one piece of it stops being boilerplate. That's a
     genuinely different, and likely larger, undertaking than everything
     landed in steps 1-4c combined — closer in shape to Phase 4's own
     god-file-split scale than to a single bounded slice.

   **Landed (2026-07-13), step 4d: `reduce_rt.zig`'s own public API retyped
   onto `Value`.** Revisited the "boilerplate, no benefit" conclusion above
   with a sharper distinction: it applies to callers that are themselves
   unmigrated (the front end), but `reduce_rt.zig` is squarely inside the
   already-migrated `eval` layer, and its callers — `reduce_core.zig`'s own
   `reduceVal`/`headVal`/`forceVal`/`getstringVal`/`badcaseErrorVal`/
   `confErrorVal` wrappers (step 4b) — exist *specifically* to bridge a gap
   that closing this file's own retype eliminates outright. Retyped:
   `wrapPtr`/`unwrapPtr`, `badcaseError`/`confError`/`parseCloseError`,
   `getstring`, `outHere`, `numplus`, `gResidue`, `memclass`/`lexfail`/
   `lexstate`, `piperrmess`, `compare`, `force`/`head`, `apfile`/
   `closefile`/`outf`/`print`/`output`. `streamRead` itself was already
   `Value`-clean from step 4b (the one function here taking the whole
   `ReductionCtx`); its own `op`/return stay `Word` (protocol/action codes,
   not graph values, same category as `ctx.action: c_int`).
   - This file's own private `Word`-typed duplicate leaf helpers
     (`getTag`/`setTag`/`h`/`t`/`hp`/`tp`/`lh`/`forceDbl`/`cons`/`ap`/
     `datapair`/`digit0`/`stosmallint`/`rewriteToValue`/`rewriteToNil`/
     `setcell`/`rewriteToCons`) were deliberately **not** touched — same
     reasoning as `reduce_core.zig`'s own leaf layer: every public function
     unwraps its `Value` parameter to a local `Word` once at the top (or,
     for the two genuinely self-recursive functions, `force`/`gResidue`,
     was renamed to a private `xxxRaw` and given a thin `Value` wrapper
     instead, so the recursive body needed zero changes), then the
     function body runs exactly as before against these unchanged private
     helpers.
   - Closed the loop in `reduce_core.zig`: its own `headVal`/`forceVal`/
     `getstringVal`/`badcaseErrorVal`/`confErrorVal` wrappers (built in
     step 4b specifically because `reduce_rt.zig` was still `Word`-typed
     then) became trivial passthroughs — kept under their original names
     so none of the ~80 already-fixed call sites across
     `combinators.zig`/`ready.zig`/`combinators/lex.zig`/`combinators/io.zig`
     needed a second rename.
   - Cascaded into a small, genuinely external ring: `compiler/
     module_loader.zig` (4 `outHere` sites), `parser/codegen.zig` (2 `head`
     sites — `head`'s only outside-the-reducer callers, confirming the
     step-4-scoping note's premise that the front end mostly doesn't touch
     `Value` yet, except at this one seam), and `session/repl.zig` (2
     `output` sites, 1 `getstring` site) — all fixed with `Value.fromRaw`
     at the boundary, since none of those three files are otherwise
     migrated.
   - `zig build`/`zig build test` (261 unit tests, integration suite,
     spine/golden corpus, `sigint_check` — the spurious quirk showed once,
     confirmed clean via the binary directly, then green again on rerun)
     green; `zig build bench` reduction counts still match the
     pre-migration baseline exactly; `layer_check.py`/`scorecard.sh --check`
     both clean, no regression at all this time.

   This closes the `eval` layer's own remaining gap from step 4b — every
   function `combinators.zig`/`ready.zig`/`combinators/lex.zig`/
   `combinators/io.zig` call, whether defined in `reduce_core.zig` or
   `reduce_rt.zig`, is now genuinely `Value`-typed, with the `reduceVal`-
   style wrapper layer reduced to pure naming convenience (not a real
   type-conversion boundary anymore) for four of its six members.

   **Remaining for step 4:** `reduce()`/`reducer/reduce.zig`'s own
   `Word`-in/`Word`-out signature (called from hundreds of sites well
   beyond the reducer — `reduceVal` is the one wrapper still doing a real
   conversion); the compile-time front end as one connected unit
   (`semantics/lower.zig`/`infer.zig`/`unify.zig`/`type_errors.zig`/
   `depend.zig`/`symbols.zig`, `parser/codegen.zig`,
   `compiler/module_loader.zig`/`setup.zig`/`dump.zig`) — genuinely larger
   than everything landed in steps 1-4d combined, being tackled file-by-file
   starting with the smallest, most self-contained pieces rather than in one
   pass (see `semantics/match.zig` below, the first slice landed);
   `graph/print.zig` (unblocks once the front end migrates). `bignum.zig`'s
   own internals (in-place retype rather than the wrapper layer landed in
   step 4c) and `reduce_rt.zig`'s own private duplicate leaf helpers remain
   unconverted by design.

   **Step 4e — front end, first slice (`semantics/match.zig`), landed
   (2026-07-13):** re-scoped the "front end must move as one unit" premise
   from the step-4-scoping note: it's true that no *sub-slice* within the
   front end has an already-`Value`-typed caller, but that only means each
   slice's callers need `Value.fromRaw`/`.toRaw()` boundary wrapping (same
   as every other slice this phase, e.g. `bignum.zig` wrapped from
   `ready.zig` in step 4c, `reduce_rt.zig` wrapped from `module_loader.zig`/
   `codegen.zig`/`repl.zig` in step 4d) — not that the whole 8,306-line
   cluster must convert atomically. Converted `match.zig`'s 3 public
   functions to take/return `Value`: `scanpattern`/`genlhs` (self-recursive
   — renamed bodies to private `scanpatternRaw`/`genlhsRaw`, kept
   `Word`-typed, added thin `Value`-typed public wrappers, matching the
   rename+wrapper pattern from `reduce_rt.zig`'s `gResidue`/`force` in step
   4d) and `transtries` (not self-recursive — unwrapped once at the top,
   body unchanged, mirroring the `reduce_rt.zig` non-recursive functions).
   Fixed the 3 external call sites: `lower.zig`'s `declare` (`scanpattern`)
   and `codegen` (`transtries`, `.TRIES` case) and `codegen.zig`'s two
   `genlhs` sites (`.listcomp`'s `.generator`/`.sequence_generator` arms) —
   all wrapped with `Value.fromRaw`/`.toRaw()` at the boundary since
   `lower.zig`/`codegen.zig` themselves remain `Word`-typed. `codegen.zig`
   already imported `Value`; `lower.zig` needed a new import (`const Value
   = @import("../graph/value.zig").Value;`). `zig build`/`zig build test`
   (full suite, spine/golden corpus) green; `layer_check.py`/
   `scorecard.sh --check` both clean, no regression. This is the first
   slice of the front-end migration — proof the "boundary wrapping"
   technique scales down into this cluster the same way it did everywhere
   else in Phase 5; more files follow the same pattern.

   **Step 4f — front end, second slice (`semantics/depend.zig`), landed
   (2026-07-13):** the generic sorted-set/dependency-analysis module —
   `remove1`/`setdiff`/`add1`/`newadd1`/`UNION`/`intersection`/`member`/
   `typesfirst`/`tsort`/`msc`/`rembvars`/`deps`/`redtfr`/`alfasort`, 14
   public functions total. Unlike `match.zig`'s 3-call-site fanout, these
   functions are called from ~90 sites across 9 files (`graph/dump.zig`,
   `compiler/dump.zig`, `compiler/module_loader.zig`, `semantics/lower.zig`,
   `semantics/infer.zig`, `semantics/type_errors.zig`, `semantics/match.zig`,
   `session/boot.zig`, `session/commands.zig`) — comparable in scale to
   `reduce_rt.zig`'s step-4d cascade, not `match.zig`'s trivial case. Given
   the functions' own tight interdependency (`tsort`/`msc`/`deps` all call
   each other and `add1`/`UNION`/`setdiff`/`member`/`remove1` internally), a
   partial in-file split (converting only the low-fanout functions) would
   have meant manually tracking, for every internal cross-call, whether the
   callee was migrated yet — riskier than converting the whole file at
   once. Applied the rename+wrapper pattern uniformly: every function's
   existing `Word`-based body moved verbatim into a private `fooRaw` twin
   (internal cross-calls stay within the `Raw` family, so no wrapping noise
   leaked into the bodies), with a thin public `Value`-typed wrapper at each
   boundary. Two exceptions kept `Word`/`i64` return types since they're
   scalar flags, not graph values: `member` (0/1 membership flag) and
   `remove1` (0/1 hit/miss flag, plus its `*Word` in-out set pointer became
   `*Value`). Fixed all ~90 external call sites across the 9 files with
   `Value.fromRaw`/`.toRaw()` boundary wrapping (`Value` needed a fresh
   import in `compiler/dump.zig`, `graph/dump.zig`, `semantics/infer.zig`,
   `semantics/type_errors.zig`, `session/boot.zig`, `session/commands.zig`;
   already present in the others). One genuine wrapper-elimination (not
   just relocation) found in `eval/combinators/lex.zig`'s two
   `handle_LEX_TRY1`/`handle_LEX_TRY1_` call sites: `hd_hd_hd_arg1` and
   `ctx.args[1]` were already `Value` in the migrated eval layer, so
   `types.member(...)` no longer needs `.toRaw()` on either argument —
   confirmation the technique pays down real boilerplate, not just moves
   it. `zig build`/`zig build test` (full 261-test suite + integration +
   spine/golden corpus) green; `zig build bench` reduction counts still
   exactly match baseline (Ackermann(3,8)=30,652,009,
   Fibonacci(30)=28,907,260, Prime Sieve(500)=671,945);
   `layer_check.py`/`scorecard.sh --check` both clean, no regression.

   **Front-end cluster re-measured after steps 4e/4f (2026-07-13):**
   the same 11 files from the step-4-scoping note, re-measured:
   `lower.zig` 1761L/48 pub fns, `infer.zig` 1709/25, `unify.zig` 322/19,
   `type_errors.zig` 533/22, `depend.zig` 559/14 (**migrated**),
   `symbols.zig` 339/0, `match.zig` 201/3 (**migrated**),
   `codegen.zig` 825/2, `module_loader.zig` 716/2, `setup.zig` 264/8,
   `graph/dump.zig` 1176/22 — 8,405 lines/165 pub fns total, essentially
   unchanged from the original 8,306/~164 measurement (the small growth is
   doc comments plus the private `Raw`-twin helpers steps 4e/4f added,
   which don't count as `pub`). 760 lines/17 pub fns (~9%, match.zig +
   depend.zig) are now `Value`-typed at their public boundary; **7,645
   lines/148 pub fns across 9 files remain.** `scorecard.sh --check`
   confirms no tracked metric regressed — no baseline bump needed this
   round. Next-slice candidates checked and rejected: `unify.zig`
   (164 external call sites, all from `infer.zig` itself — converting it
   now would just relocate wrapping boilerplate into `infer.zig`, to be
   redone when `infer.zig` converts) and `type_errors.zig` (38 sites, same
   problem, mostly from `infer.zig`/`lower.zig`). `infer.zig`'s own public
   API splits in two: 11 functions (`sterilise`/`printelement`/
   `cyclicAbstr`/`txchange`/`repT1`/`repT`/`fixType`/`checkfbs`/
   `checkcolfn`/`genbnft`/`checktype`) have zero external callers — a
   `match.zig`-shaped next slice — but its core accessors (`getId`/
   `idType`/`idWho`/`tInfo`/`isCompoundType`/`isVarType`/`tArity`) are
   called 50-78 times each from nearly every front-end file (they function
   like `graph/value.zig`'s `hOf`/`tOf` primitives) and need a closer look
   at what each actually returns (graph value vs. bare tag/sentinel)
   before typing — a materially bigger, riskier undertaking than either
   slice landed so far, deliberately not started this session.

   **Step 4g — front end, third slice (`infer.zig`'s 11 zero-caller
   functions), landed (2026-07-13), done as part of
   [GO_MIGRATION.md](GO_MIGRATION.md) Phase 1** (that plan's own step 1
   names finishing this exact migration as a load-bearing prerequisite for
   Go-readiness, not just Zig polish). Re-verified all 11 first: zero
   callers anywhere outside `infer.zig` itself, confirmed by grep, not
   assumed from the earlier scoping note. Of the 11, only 8 actually cross
   a `Word`/graph-value boundary and needed retyping —
   `checkfbs`/`checkcolfn`/`genbnft` take no `Word` parameter and return
   `void`, so there was nothing to convert for them at all (a real finding,
   not busywork skipped): `checkfbs` only needed its one internal call to
   `fixType` repointed at the new `fixTypeRaw` twin. Applied the
   rename+wrapper pattern to the 8 that do: `sterilise`, `printelement`,
   `cyclicAbstr` (return stays `Word` — a 0/1 flag, not a graph value,
   matching `depend.zig`'s `member`/`remove1` precedent from step 4f),
   `txchange`, `repT1`/`repT` (self- and mutually-recursive — `repT` calls
   `repT1Raw` directly, not the new public `repT1`, avoiding a pointless
   wrap/unwrap round trip), `fixType` (self-recursive), and `checktype`.
   All internal callers (`metaTcheck`, the cycle-report branch, `abstrCheck`,
   `etype`'s `.CONSTRUCTOR` case, `checkfbs`) — themselves still
   `Word`-typed, unmigrated front-end code — were repointed at the private
   `Raw` twins directly, the same "no wrapping noise leaks into
   not-yet-migrated callers" reasoning as every earlier slice.

   **Bug found and fixed, not just carried forward:** `checktype`
   (distinct from the real production entry point `checktypes`) had never
   been called from anywhere in the codebase — the exact reason it was
   flagged as zero-external-caller in the first place — and Zig's lazy
   semantic analysis (a `pub fn` is only type-checked if something reaches
   it) meant its body had silently never compiled: `cs.TYPERRS = 0;` is
   missing the call parens on the `cs()` singleton accessor (`cs` is a
   function value, not a struct; every other reference in the file
   correctly writes `cs().TYPERRS`). This is exactly the risk the
   cross-cutting test-coverage note above predicted in the abstract
   ("any future port translates fastest against an existing test") made
   concrete: without a test, this function would have been translated
   verbatim into Go, and Go — with eager, non-lazy compilation — would
   have caught the equivalent mistake at `go build` time regardless, just
   with no way to know whether the *behavior* being ported was ever
   correct in the first place. Fixed both occurrences (the reset and the
   final flag check) in the same edit that gave this function its first
   real caller.
   - Added one test per retyped function (`sterilise`, `printelement`,
     `cyclicAbstr`, `txchange`, `repT1`, `repT`, `fixType`, `checktype` —
     8 new tests), each exercising a safe, self-contained case rather than
     the full domain logic (e.g. `repT1`/`repT` test the "no substitution
     needed" identity path, not a real multi-formal type substitution;
     `printelement` smoke-tests both branches since this codebase has no
     stdout-capture harness to assert printed text against). The deeper
     paths these functions cover in real use (cyclic `==` detection, actual
     type-argument substitution, dump-load index fixup) remain exercised
     only indirectly, via the golden/regression corpus's own type-checking
     coverage — noted as a gap, not claimed as covered.
   - `zig build` (exe) and `zig build test` (289 unit tests, up from 281;
     full integration + spine/golden corpus, sigint, smoke) all green;
     `zig build bench` reduction counts unchanged (Ackermann(3,8)=30,652,009,
     Fibonacci(30)=28,907,260, Prime Sieve(500)=671,945 — this is
     compile-time front-end code, not the reducer hot path, so no change
     was expected). `scorecard.sh --check` flagged three metrics: two
     (`c_int`-family 166→168, `[*:0]` 228→231) were pre-existing drift
     already present on `main` before this slice (confirmed by stashing
     this change and re-running the check against a clean tree) — baseline
     was already stale, not something this step caused or should silently
     paper over; the third (`ambient singleton-accessor call sites`
     683→686) is this step's own new tests calling `heap_mod.heap()` three
     times, the same "the test's own point requires this accessor, not a
     production regression" reasoning already accepted for
     `current_interp references` in Phase 4 step 6. Baseline updated to
     168/231/686 with this justification recorded here, not silently.

   **Front-end cluster re-measured after step 4g:** `infer.zig`'s 8 newly
   `Value`-typed functions plus `depend.zig`/`match.zig` from steps 4e/4f
   bring the migrated share of the 11-file/8,405-line cluster to
   3 files/~980 lines at their public boundary; **8 files/~7,425 lines
   remain** (`lower.zig`, the bulk of `infer.zig` — including its
   50-78-call-site core accessors flagged as the next, materially larger
   undertaking — `unify.zig`, `type_errors.zig`, `symbols.zig`,
   `codegen.zig`, `module_loader.zig`, `setup.zig`, `graph/dump.zig`).

   **Step 4h — `semantics/symbols.zig`'s `SymbolTable`/`PrivateNames`
   methods, landed (2026-07-13), done as part of
   [GO_MIGRATION.md](GO_MIGRATION.md) Phase 1.** Not one of the 11-file
   cluster's own members by the earlier measurement, but flagged there as
   "0 pub fns" only because that count used a `^pub fn` (unindented,
   top-level) grep that misses methods nested inside a struct —
   `symbols.zig` in fact has 11 real methods, 7 of which cross a
   `Word`/graph-value boundary. Chosen over `infer.zig`'s own core
   accessors (the plan's previously-flagged next candidate) after checking
   actual external fanout first: `getId`/`idType`/`idWho`/`tInfo` are
   called 50-78 times *each*, almost entirely from `lower.zig`/`unify.zig`/
   `type_errors.zig` — none of them migrated — so converting those
   accessors now would add `.fromRaw()`/`.toRaw()` wrapping at ~400+ call
   sites that gets redone the moment those files themselves convert, the
   exact "premature slice creates rework" trap the plan's own step-4
   scoping note already identified for `unify.zig`/`type_errors.zig`
   directly. `symbols.zig`'s methods, by contrast, have only ~15 external
   call sites total across 4 files (`parser/lex.zig` ×3 call sites within
   `name`/`makeId`/`findid`, `semantics/modules.zig` ×4, `parser/codegen.zig`
   ×2, `compiler/dump.zig` ×2) — comparable in scale to `match.zig`'s
   3-site slice from step 4e, not `depend.zig`'s ~90-site or the rejected
   accessors' ~400+-site shape.
   - Retyped in place (no rename+wrapper split needed — none of these
     seven methods are self- or mutually-recursive, so a direct signature
     change plus inline `.toRaw()`/`Value.fromRaw()` at each method's own
     boundary was simpler than the free-function pattern used elsewhere):
     `SymbolTable.intern`/`.find`/`.createFresh` now return `!Value`/
     `?Value`; `.rebind`/`.bind` take `new_id`/`id: Value`;
     `PrivateNames.make`/`.get` take/return `Value`. Internal storage
     (`table: std.StringHashMapUnmanaged(Word)`, `table: std.ArrayList(Word)`)
     deliberately left `Word`-typed — only the public method boundary
     changed, matching every earlier slice's "representation stays, type
     changes" principle. Raw hashmap access bypassing these methods
     entirely (`parser/lex.zig`'s `completeIds`/`mkprivate`, iterating/
     mutating `symbols.syms().table` directly) is unaffected, confirmed by
     inspection — it never goes through the now-retyped method surface.
   - All ~15 external call sites fixed with `Value.fromRaw()`/`.toRaw()`
     boundary wrapping (new `Value` import added to `parser/lex.zig` and
     `semantics/modules.zig`; already present in `parser/codegen.zig` and
     `compiler/dump.zig`) — same technique as every prior step.
   - Updated all 10 of the file's own existing unit tests to the new
     signatures (`@as(?Word, ...)` → `@as(?Value, ...)`, raw integer
     literals like `999`/`42`/`777`/`55` passed to `rebind`/`bind` wrapped
     in `Value.fromRaw(...)`) — no new tests needed, since this file
     already had full coverage of every method before this step.
   - `zig build`/`zig build test` (289 unit tests, unchanged count — this
     step edited existing tests, added none; full integration + spine/
     golden corpus, sigint, smoke) all green; `zig build bench` reduction
     counts unchanged (Ackermann(3,8)=30,652,009, Fibonacci(30)=28,907,260,
     Prime Sieve(500)=671,945). `scorecard.sh --check` clean — no baseline
     change needed this time (unlike step 4g, this slice's wrapping is all
     `.toRaw()`/`Value.fromRaw()` method calls, not new
     `heap_mod.heap()`-style ambient accessor reads, so the
     ambient-singleton metric didn't move).

   **Step 4i — `compiler/setup.zig`'s `primdef`/`predef`, landed
   (2026-07-13), done as part of [GO_MIGRATION.md](GO_MIGRATION.md) Phase
   1.** Even safer than step 4h: checked real fanout first (same discipline
   as every slice this phase) and found `primdef`/`predef` have **zero**
   external callers — both are called only from `primlib`/`privlib`/`stdlib`,
   all three in this same file. `setup.zig`'s other 6 `pub fn`s
   (`syntax`/`acterror`/`primlib`/`privlib`/`stdlib`/`miraSetup`) take no
   `Word` parameter at all (string/error/orchestration signatures only), so
   they were never candidates for this phase — a `checkfbs`-shaped finding,
   not an oversight.
   - Retyped `primdef`/`predef`'s `v`/`t_val` params from `Word` to `Value`
     directly (no rename+wrapper split — neither function is recursive).
     Both bodies call `heap.tp(...)`/`heap.h(...)` and
     `heap_mod.constructor(heap, v, x)`, all still `Word`-typed (`heap.zig`'s
     public API retyping is a separate, much larger, not-yet-started item
     in this same phase) — `.toRaw()` at each of those three call points.
   - Since there is no external boundary to wrap, "verifying the retype"
     meant actually converting all ~50 call sites across `primlib`/
     `privlib`/`stdlib` (every built-in and stdlib identifier the
     interpreter bootstraps) to pass `Value.fromRaw(...)` rather than a
     bare `Word` — the only way this change is real rather than a signature
     nobody exercises (the exact lesson step 4g's `checktype` bug already
     taught: an unconverted call site is a compile that never happens, not
     a proof of correctness). Handled as one deliberate full-block rewrite
     rather than a scripted substitution — several call sites pass
     multi-argument nested expressions as `v` (`abi.make_typ(heap, 0, 0,
     word.synonym_t, word.num_t)`, `abi.ap2(heap, word.FOLDR, word.APPEND,
     NIL)`, `abi.stoDbl(abi.DBL_MAX) catch unreachable`, `mktiny()`), which
     a blind regex/sed pass over "wrap the last two comma-separated
     arguments" would have mis-split on the nested commas.
   - This is, in effect, the interpreter's entire built-in/stdlib bootstrap
     surface (every combinator/type pairing `True`/`False`/`num`/`char`/
     `bool`/`offside`/`hd`/`tl`/`map`/`filter`/`foldr`/`sin`/`cos`/... gets
     registered through) now running through `Value` at its call sites,
     even though the two functions themselves are the only "migrated" unit
     — a good example of a slice being small in *declared* surface (2
     functions) but real in *exercised* surface (~50 sites, every one
     actually run by `miraSetup()` on every process start and every test
     via `tu.freshInterp()`).
   - `zig build`/`zig build test` (289 unit tests; full integration +
     spine/golden corpus, sigint, smoke — the spurious `zig build test`
     quirk from `docs/ZIG_NATIVE_PLAN.md`'s own testing notes showed once,
     confirmed clean on immediate rerun) all green; `zig build bench`
     reduction counts unchanged (Ackermann(3,8)=30,652,009,
     Fibonacci(30)=28,907,260, Prime Sieve(500)=671,945). `scorecard.sh
     --check` clean, no baseline change.

   **Step 4j — `parser/codegen.zig`'s `codegenExpr`, landed (2026-07-13),
   done as part of [GO_MIGRATION.md](GO_MIGRATION.md) Phase 1.** The
   largest single function converted so far in this phase (~160 lines, a
   recursive-descent switch over all 18 `ast.Expr` variants) — chosen
   because, unlike `unify.zig`/`type_errors.zig`, its external fanout is
   tiny (exactly **one** real external caller, `parser_api.zig`'s
   `evaluateRepl`-adjacent expression-eval path) even though its *internal*
   fanout is large: ~40 self- and mutually-recursive references across
   `codegenExprRaw` itself and the private `codegenGuarded` helper (guarded
   right-hand-side compilation). Confirmed by checking every call site, not
   assumed from the function's size.
   - Applied the rename+wrapper pattern exactly as at every self-recursive
     site this phase (`repT1`/`fixType` in step 4g): the entire ~370-line
     body renamed `fn codegenExprRaw` (now private — nothing outside this
     file may reach the `Word`-typed form), all 40 in-file references
     (self-recursion plus `codegenGuarded`'s calls into it) mechanically
     renamed to match via a whole-file substitution scoped to this one
     identifier (verified safe first: `codegenExpr(` appeared nowhere else
     in the file as a substring of a different name). A new
     `pub fn codegenExpr(...) Value` wrapper added immediately after the
     renamed body, calling it once and wrapping the result.
   - `codegenScript` (the file's other `pub fn`, the whole-script codegen
     entry point) stays `Word`/`void`-typed and unmigrated — its own single
     internal call (the `.eval` top-level-item case) was mechanically
     renamed to `codegenExprRaw` by the same substitution, same "internal
     unmigrated callers use the Raw twin directly" rule as every prior
     step.
   - The one real external call site (`parser_api.zig`'s expression-eval
     path) wrapped with `.toRaw()` — `Value` was already imported there
     from earlier phase work, no new import needed.
   - **Correction, worth recording:** `graph/dump.zig` (1176 lines/22 pub
     fns), still listed as one of "8 files remaining" in the front-end
     cluster measurement above, is not actually a `Value`-retyping target
     at all — [ZIG_NATIVE_PLAN §4.1](ZIG_NATIVE_PLAN.md) explicitly names
     it as `Word`'s permanent final home ("the only home of `Word` at the
     end," since the `.x` wire format is pinned bit-for-bit and must not
     change shape). Confirmed by reading its callers (`os.zig`,
     `compiler/dump.zig`, `compiler/module_loader.zig`,
     `session/commands.zig`, `session/repl.zig` — session/format-layer
     code, not the compile-time front end this cluster measurement was
     tracking) — it was swept into the 8,405-line measurement because it's
     *entangled with* the front end today, not because it's *meant to
     become* `Value`-typed. The real remaining front-end surface is 7
     files, not 8: `lower.zig`, the bulk of `infer.zig` (its 50–78-call-
     site core accessors, still the biggest identified risk, still not
     attempted), `unify.zig`, `type_errors.zig`, the rest of `codegen.zig`
     (`codegenDef`/`codegenTypeSpec`/`codegenTypeDecl`/`codegenGuarded`
     and friends — all still `Word`-typed, `codegenExpr` was one function
     within this file, not the whole file), `module_loader.zig` (its 2
     `pub fn`s, `loadfile`/`mkincludes`, take no `Word`-graph-value
     parameter at all — a `checkfbs`-shaped non-candidate, checked and
     confirmed, not skipped by oversight).
   - `zig build`/`zig build test` (289 unit tests; full integration +
     spine/golden corpus — 69 golden/spine `PASS` lines confirmed, zero
     `FAIL`; sigint; smoke) all green; `zig build bench` reduction counts
     unchanged (Ackermann(3,8)=30,652,009, Fibonacci(30)=28,907,260, Prime
     Sieve(500)=671,945). `scorecard.sh --check` clean, no baseline change.

   **Step 4k — `infer.zig`'s `genlstatType`/`typeOf`, landed (2026-07-13),
   done as part of [GO_MIGRATION.md](GO_MIGRATION.md) Phase 1.** A second
   pass over `infer.zig`'s remaining `pub fn` list (beyond the 7 core
   accessors and the 11 already handled in step 4g) turned up two more
   genuine candidates that the earlier "core accessors are the only thing
   left, and they're risky" framing had missed: `genlstatType` (builds/
   caches the `filestat` result type — 1 internal caller plus 1 external,
   `parser/lex.zig`) and `typeOf` (the inferred type of an expression — 3
   external callers, **all in `session/repl.zig`**, none in the
   `unify.zig`/`type_errors.zig`/`lower.zig` cluster that motivated
   rejecting the core accessors). `tsetup`/`checktypes`, the other two
   previously-unchecked `pub fn`s, confirmed as non-candidates the same way
   `checkfbs`/`checkcolfn`/`genbnft` were in step 4g — no `Word` parameter
   crosses their boundary at all.
   - Both retyped directly, no rename+wrapper split needed (neither is
     recursive): `genlstatType(heap) Value` (was `Word`, no parameter to
     convert), `typeOf(heap, x: Value) Value` (was `Word`/`Word`).
   - Fixed all 4 external call sites: `parser/lex.zig`'s `mklexvar`
     (`.toRaw()` at the assignment, `genlstatType` reached through an
     existing `const genlstatType = types.genlstatType;` alias — the alias
     itself needed no change, only its one call site); `session/repl.zig`'s
     `obey`/`evaluateRepl`/the REPL's type-check-on-redisplay path (3 sites,
     `Value.fromRaw()` in, `.toRaw()` out at each — `Value` was already
     imported there from earlier phase work).
   - **Flaky-harness note, not a regression:** this step's `zig build test`
     run hit a *different* instance of the project's known flaky-test-
     harness pattern than the main-tests one `docs/ZIG_NATIVE_PLAN.md`'s
     testing notes already document — `sigint_check` failed with
     `BrokenPipe` under `zig build test`'s runner once, then passed cleanly
     (exit 0) when the same built binary was invoked directly by hand, and
     a full `zig build test` rerun afterward was clean end to end (69
     golden/spine `PASS`, sigint `PASS`, smoke `PASS`, zero `FAIL`) —
     treated as the harness flake it demonstrably is, not silently ignored:
     confirmed by running the exact failing binary standalone before
     concluding it wasn't `session/repl.zig`'s freshly-edited REPL paths
     actually breaking under signal interruption.
   - `zig build`/`zig build test` (289 unit tests; 69 golden/spine `PASS`,
     zero `FAIL`; sigint; smoke) all green on the confirming rerun; `zig
     build bench` reduction counts unchanged (Ackermann(3,8)=30,652,009,
     Fibonacci(30)=28,907,260, Prime Sieve(500)=671,945). `scorecard.sh
     --check` clean, no baseline change.

**Gate:** no `Word` outside `graph/dump.zig`; no numeric range tests on values;
goldens + differential + bench green; GC invariant (mark follows `hd`/`tl` only for
cell-payload tags) now *type-enforced* rather than convention-enforced.

**Risks:** the reducer hot loop (mitigated by leaf-first order + bench ratchet);
dump compat (mitigated by keeping the bit layout and round-trip goldens).

---

### Cross-cutting: test-coverage investment for future portability (2026-07-13)

Asked to prioritize work that would specifically help a *future* rewrite of
this codebase in another language (e.g. Go), independent of finishing Phase
5/6 first. Reasoned from the scorecard: growing per-function test coverage
(then 265/1267 fns, ~21%) is the single highest-leverage, language-agnostic
investment — any future port translates fastest against an existing test to
verify each function against, rather than a prose spec to reinterpret; this
codebase's own "one inline test per function" convention already provides
the pattern, just not the density. Second priority: finishing the collapse
of ambient singleton access (683 call sites, Phase 4's own still-open goal)
since Go idiom strongly favors explicit dependency passing over the
`cs()`/`rt.rs()`/`current_interp`-style globals a port would otherwise have
to redesign by hand. Third: keep pushing `Value`/`Kind` (Phase 5) so the
320 remaining raw `== NIL`/`!= NIL` Word-sentinel comparisons — Zig's
untyped-integer trick for a tagged union, which Go has no equivalent
shortcut for — end up behind one typed API instead of scattered raw
comparisons. `setjmp`/`longjmp` (Phase 3) and the `os.zig` C-interop floor
were already judged in good shape; a Go port reimplements the floor with
`os`/`syscall` regardless, and there was nothing further to do there.

Landed a first slice against priority one: **`eval/reduce_core.zig`**, the
reduction machine's shared primitive layer (`ReductionCtx`, every accessor/
classifier/rewrite/allocator helper `combinators.zig`/`ready.zig`/
`combinators/lex.zig`/`combinators/io.zig` call as `reduce.*`) — chosen
because it was the largest fully-`Value`-typed file with **zero** existing
tests (68 functions), foundational to every single reduction step, and
already fully retyped this session (Phase 5 steps 4b/4d), so no test needed
`.toRaw()`/`Value.fromRaw()` noise to work around a still-`Word`-typed
signature. Added 13 grouped test blocks (mirroring `graph/value.zig`'s and
`eval/spine.zig`'s established "test the cluster, not each one-line
accessor separately" convention), covering: the `hdGet`/`hdSet`/`tlGet`/
`tlSet`/`getTag`/`setTag`/`tlPtr` accessor group; the `ReductionCtx`-level
spine wrappers `downLeft`/`downRight`/`downright`/`upLeft`/`upleft`/
`upRight` (via a new `testCtx()` helper wiring up a real `ReductionCtx` the
same way `reduce()` itself does); `GETARG`/`getarg`; `simpl`; `abnormal` +
all twelve `isXxx` classifiers + `idVal`; the `rewriteToValue`/`Nil`/`Fail`/
`Failure`/`ConsHead`/`Cons`/`ExistingTail` family; `ap`/`apTwo`/`cleanPtr`;
`rewriteToMatchResult`/`rewriteToIntMatchResult`/`rewriteToString`; `cons`/
`ap2`; `neg`/`poz`/`pnVal`/`getId`/`constrName`/`suppressed`; `forceDbl`/
`coerceDbl`; `rewriteToCompareEq`/`Neq`/`Gt`/`Ge`; `bigzero`/`getsmallint`.

Two bugs caught and fixed while writing these (both in the test code, not
the production functions under test): (1) `testCtx()` originally called
`ctx.spine.register(&ctx.eval.gc_roots_head)` *inside* the helper and
returned `ReductionCtx` by value — the registered pointer pointed into
`testCtx`'s own stack frame, which is gone by the time the caller's copy is
used, corrupting the GC-roots list (`unregister` aborted on an assertion
failure). Fixed by having `testCtx()` build everything *except* registration,
and registering at the call site once `ctx` is at its final (stable) address
— the same "register after the struct is at its final address" constraint
`spine.zig`'s own tests already follow, just not yet written down as a rule
here. (2) A `rewriteToValue` test initially read `hdGet`/`tlGet` back
through the *same* `Value` variable the rewrite had just overwritten (by
design, `rewriteToValue` rewrites `expr.*` to point at the new value, not
the original cell) — reading through the post-rewrite value tried to
dereference a bogus low heap index, hitting uninitialized (`0xAA`-pattern)
memory. Fixed by capturing the original cell reference in a separate
`const` before the rewrite and asserting the in-place mutation through that.

`zig build`/`zig build test` (274 unit tests, up from 261; full integration
+ spine/golden corpus) green (`sigint_check`'s spurious quirk showed once,
confirmed clean via the binary directly per the known harness flake);
`zig build bench` reduction counts unchanged (test-only addition, no
production code touched); `scorecard.sh --check` shows the `test blocks /
fn definitions` metric moving 265/1267 (20%) → 278/1269 (21%), a genuine
improvement, no other metric regressed. This is one file of many with zero
or thin coverage (`infer.zig` 65 fns/0 tests, `unify.zig` 32/0,
`type_errors.zig` 30/0, `graph/heap.zig` 89-fn gap/16 tests, `graph/dump.zig`
39-fn gap/1 test — see the file-by-file gap ranking computed this session);
continuing this investment in a future session should work down that list,
prioritizing files that (like this one) are already fully `Value`-typed so
tests don't fight an in-progress migration.

---

### Phase 6 — Surface polish & docs

**Goal:** the remaining C accents, the build script, and the documentation.

**Steps**

1. **Types:** `c_int`/`c_long` → `i32`/`i64`/`usize`/`bool` everywhere outside
   `os.zig`; int-flags (`initialising`, `echoing`, `listing`, `verbosity`,
   `rechecking`, `sorted`, `collecting`) → `bool` or two-state enums; counters →
   `u64`.
2. **Buffers & strings:** `linebuf`/`ebuf`/`pnlim` fixed arrays → slices with
   allocators (paths via `std.fs` limits, not `pnlim`); `[*:0]` only at the
   `execve` boundary inside `os.zig`.
3. **Naming glossary** (added to `ARCHITECTURE.md`): domain vocabulary stays
   (`hd`/`tl`, combinator names, offside, spine, `NIL`); C artifacts get Zig names
   decided once in the glossary and applied mechanically — e.g. `SPACELIMIT` →
   `Config.heap_limit`, `okprel` → `prelude_ok`, `baded` → `editor_invalid`,
   `rfl` → `reload_files`, `detrop` → a named meaning. One rename per commit
   group, goldens green (renames must not leak into user-visible text).
4. **build.zig:** one `addMiraModule(b, .{ .optimize, .strict, ... })` helper
   generating the normal/strict/bench module matrix from a loop; test registration
   table-driven. Behaviour of `check`/`strict`/`bench` steps unchanged.
5. **Docs:** rewrite `ARCHITECTURE.md` around the final tree (state, layering,
   value model, error model, testing cadence); update `PARSER.md` (native lexer) and
   `REDUCER_ARCHITECTURE.md`; closing entries in `ZIG_MIGRATION.md`/`CHANGES.md`;
   flip this plan's checkboxes and mark it historical.

**Gate:** the §1 checklist fully ticked; scorecard at its documented floor
(`os.zig`-only exceptions); `zig build strict` green.

---

## 6. Working cadence

- **Commit discipline:** move-only commits separate from signature changes separate
  from behaviour-affecting changes (there should be none of the latter). Every
  commit builds and passes `zig build check`.
- **Phase gates:** `check` + `strict` + `test-golden` + `test-regression` +
  `test-sigint` + `bench` within noise, then update `scripts/scorecard.baseline`
  downward in the phase's closing commit.
- **The suites are the spec.** When a phase step and a golden case disagree, the
  golden case wins; changing a golden requires demonstrating the C reference agrees.
- **No parallel half-migrations:** a temporary shim (C-format printf shim, legacy
  lexer flag, `toRaw` escape hatch) must be deleted by the end of the phase that
  introduced it. The scorecard ratchet enforces the direction.
