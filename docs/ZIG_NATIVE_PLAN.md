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
   to `lex_bridge.zig` itself. **Not yet done:** running this over the
   *whole* golden corpus mechanically (today's 8 cases were picked by hand,
   excluding scripts with this lexer's known gaps) and wiring it as a build
   step so it's a standing gate, not an ad hoc test file. Char classes
   (`` `[...]` ``, `%bnf`/`%lex`-only) and the known-excluded forms
   (`%`-directives, backtick infix names, hex-float) also still to do.
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
   block for `%include`'s bindings and `%free`'s signature). That block is
   explicitly `{`/`}`-delimited, not layout/offside-sensitive, so
   `directives.zig` can scan it by brace-depth directly off `lexer.tokenize`'s
   output, *before* `applyLayout` runs — but the free-binding/signature
   grammar (`var = exp` / `tform == type`) needs an expression/type parser
   that doesn't fully exist in `syntax/` yet. Likely shape: keep binding/spec
   RHS as raw token spans in the `Directive` value for this step, deferring
   deep parsing to whichever of `semantics/lower.zig` or the ported
   `semantics/infer.zig` needs it.
6. `semantics/symbols.zig`; `codegen.zig`/`trans.zig` id lookups rewired from
   `lex.findid`/`makeId` to it. Dump/undump round-trip goldens verify private-name
   serialization is unchanged.
7. Flip `parser_api.zig` to the native pipeline as the only path; keep the legacy
   lexer behind a build flag (`-Dlegacy-lexer`) for one commit window for
   differential debugging.
8. Delete `lex.zig`, `lex_bridge.zig`, `lex_state.zig`, the `-Dlegacy-lexer` flag,
   `LexState` from `Interp`, `fileq`/`insertdepth`/`s_in` from the parse path, and
   the dictionary-space config (`DICSPACE`, `-dic` flag: accept-and-ignore with a
   deprecation note, since `.mirarc` files may set it).

**Status as of 2026-07-06:** steps 1–3 landed and step 4 partially landed
(`syntax/source.zig`, `syntax/lexer.zig`, `syntax/layout.zig`,
`syntax/differential_test.zig` — 46 new tests total, all green, no leaks,
including 8 scripts verified byte-for-byte against the real production
tokenizer), none yet wired into `parser_api.zig`. `layout.zig` went through
two verified corrections in one session (see its step-3 entry above) — a
reminder that "looks principled" and "matches the system it must replace"
are different bars, and only the second one counts here; the differential
harness this step added is exactly the tool that would have caught both
corrections immediately instead of via manual trace-checking, and should
have been built before, not after, hand-deriving the algorithm. Remaining:
finish step 4 (whole-corpus coverage, a standing build gate rather than a
hand-picked test file), the directive/module semantics (currently
non-functional even in production, see the step-5 correction above), symbol
interning, production cutover, and deletion.

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
