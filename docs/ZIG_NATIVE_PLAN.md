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
entry above for why, and the re-pinned goldens. Remaining: step 8 (delete
the legacy lexer entirely).

**Deletes:** ~2,700 lines of C-ported lexing; the biggest single consumer of `FILE`,
`[*:0]`, `c_int`, and `@ptrFromInt`.

**Gate:** golden corpus byte-identical **including error wording**; token-stream
differential harness retired in the same commit that deletes the bridge;
parser-tests still build standalone (the "never import from parser-tests" C-linkage
warning in lex_bridge dies with it).

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
2. **Diagnostics.** Promote the parser's `Diagnostic{span, message}` to a shared
   `Diagnostics` type (list + counts). Replace `SYNERR`/`errs`/`errline`/`errcol`
   with it: `errs`'s second life as a "current compile position breadcrumb" for
   runtime error reporting becomes an explicit `last_position: Span` field —
   the two unrelated purposes the old survey found get two named homes.
3. **Format conversion.** Mechanically convert the ~320 C-format call sites
   (`%s`/`%d`/`%ld` → `{s}`/`{d}`), dropping the `.{.{a}}` tuple convention. Module
   by module; a temporary comptime C-format shim is permitted mid-phase and deleted
   at the end. Miranda's number printing (`%g`-family in `shownum`/`outTerm`) gets a
   dedicated `formatMiraFloat` helper replicating current output digit-for-digit
   (golden-gated).
4. **Streams.** `eval/stream.zig`: a `Stream` over `std.fs.File` with pushback,
   plus a fixed-buffer variant (replaces `fmemopen` remnants). Port `READ`/
   `READBIN`/`READVALS`, `Tofile`/`Appendfile` (`outfilq`), and dump/undump file
   I/O in `heap.zig`/`dump.zig`.
5. **Deletions.** From `word.zig`: the `FILE` struct + pool, `fopen`/`fclose`/
   `getc`/`ungetc`/`fflush`, the printf engine, ctype predicates (→ `std.ascii`),
   `strcmp`/`strlen`/`strcpy` (→ `std.mem`). `word.zig` ends ≤ ~600 lines of value
   vocabulary. Rename what's left of `main_clib.zig` to `os.zig`: signals,
   `fork`/`wait`/`execl` (until Phase 3), `sigsetjmp` (until Phase 3), rlimits.
   `malloc`-family shims die (allocator everywhere).

**Gate:** printf-family count = 0; `extern fn` reduced to the signal/process floor;
goldens byte-identical (float formatting is the watch item); scorecard `[*:0]` and
`@intFromPtr` drop sharply.

**Risks:** float-format parity (`formatMiraFloat` + goldens); output buffering/flush
order around child processes (flush before spawn; differential suite watches).

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
4. **Shell escape and editor** (`!cmd`, `/e`) → `std.process.Child` (argv built
   as slices, no `execl`/`[*:0]` juggling outside `os.zig`).
5. **Error unions end-to-end.** `loadfile`/`privlib`/`parse*`/`compile` return
   `MiraError!T`; `acterror()`/`syntax()`-style set-flag-and-continue becomes
   record-diagnostic-then-`return error.SyntaxError`. `fatal()` keeps its role for
   startup/CLI death. Delete `MiraError.EvaluationInterrupted`'s "documents intent"
   caveat — it's now real.

**Deletes:** the setjmp family and both fork sites; `unlinkme`/`sigflag` become
`errdefer` cleanup; `WIFSIGNALED`/`WTERMSIG` helpers.

**Gate:** scorecard setjmp/longjmp = 0; sigint, smoke, golden, regression suites
green; bench unchanged (checkpoint cost is per-REPL-eval, not per-reduction).

---

### Phase 4 — Composition (layering, splits, ownership)

**Goal:** the §4.1 tree with a CI-enforced import DAG; no god files; state owned by
subsystems and passed explicitly; the ambient singleton deleted.

**Steps**

1. **Moves.** Pure `git mv` into the target tree + import-path fixes. One commit,
   zero logic change.
2. **DAG check.** A small Zig tool (or script) parses `@import` edges and validates
   the layer rules; wire into scorecard. Existing cycles get a temporary allowlist
   that must shrink to empty within the phase.
3. **Split the god files** (move-only commits, one per split):
   - `heap.zig` → `graph/heap.zig` (arena, make/cons, payload accessors),
     `graph/gc.zig` (mark/sweep, dstack, root marking), `graph/dump.zig`
     (`dumpScript`/`loadScript` + XBASE), `graph/print.zig` (`outTerm`, `charname`);
     `alfasort` → `semantics/`.
   - `types.zig` → `infer.zig` / `unify.zig` / `type_errors.zig` / `depend.zig`.
   - `trans.zig` → `lower.zig` / `match.zig`.
   - `startup.zig` → `session/config.zig` (flags, `.mirarc`) + `session/boot.zig`
     (miralib resolution, version stack).
4. **Dissolve the state bags** into owners (each move = one commit):
   - `RuntimeState` → `Config` (heap limit, paths, UTF-8 flags, editor),
     `ScriptStore` (`files`, `oldfiles`, `rfl`, `includees`, `exports`,
     `embargoes`, `freeids`, `current_script`, `ld_stuff`…), `MakeState`
     (`making`/`mkexports`/`mksources`/`make_status`), `ShowFns` (the 20 `show*`
     atom fields → `std.EnumArray(ShowFn, Value)`), `ReplSession` (`lastexp`,
     `lastid`, `echoing`, `listing`, prompt, timing), `BnfState` (already reduced
     by Phase 1).
   - `CoreState`: `SYNERR`/`errs`/`errline`/`errcol` are gone (Phase 2);
     `loading`/`compiling` → a `Mode` enum on the compile context; `commandmode` →
     a parse-mode *parameter*; `nill` → a `graph` constant.
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

**Gate:** singleton-accessor count = 0; module-level mutable globals = 1 (the
interrupt flag); DAG check green with empty allowlist; files > 1,000 lines = 0;
goldens identical.

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

**Gate:** no `Word` outside `graph/dump.zig`; no numeric range tests on values;
goldens + differential + bench green; GC invariant (mark follows `hd`/`tl` only for
cell-payload tags) now *type-enforced* rather than convention-enforced.

**Risks:** the reducer hot loop (mitigated by leaf-first order + bench ratchet);
dump compat (mitigated by keeping the bit layout and round-trip goldens).

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
