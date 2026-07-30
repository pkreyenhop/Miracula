# Miracula — Go Port Plan

> **Goal:** get the Zig codebase into a state where an *autonomous agent* can
> port it to Go **mechanically** (no design decisions left) and
> **unsupervised** (no human in the loop, and no all-or-nothing feedback loop —
> every unit of work has an immediate, automatic pass/fail signal).
>
> This is the single plan of record. It supersedes and replaces the retired
> `GO_MIGRATION.md`, `zig2goprep.md`, the three `GO_*_INVENTORY`/`CORRESPONDENCE`
> docs, and `ZIG_NATIVE_PLAN.md` (all deleted; see git history). Only the
> strictly-required content survives here; the Zig-native readability/polish
> goals those docs also carried are out of scope.

---

## 1. Invariants — the specification

The following never change; they are the port's acceptance test:

- **Miranda semantics**, as pinned by the golden corpus, the C-differential
  suite (`tests/regression.zig`), and the smoke / sigint / spine-differential
  suites. **These suites are the spec.** They run against a compiled binary's
  stdin/stdout/exit code and don't care which language produced it — the whole
  reason preparing in Zig first is worth doing: every golden and differential
  case, and the `.x` wire format, stay byte-identical gates whether the binary
  under test is `zig build`'s or a future `go build`'s.
- **The `.x` dump format** — bit-compatible; all format knowledge stays in
  `graph/dump.zig`.
- **Miranda domain vocabulary** — `hd`/`tl`, combinator names (`S`, `K`, `TRY`,
  `U_`…), `NIL`, offside, spine, private names.
- **The execution model** — SK-combinator graph reduction over the explicit
  spine stack, mark-sweep GC, lazy semantics.

This plan changes *shape and tooling*, never behaviour. Every commit keeps
`zig build check && zig build strict && zig build test-golden && zig build
test-regression` green.

## 2. Background — completed groundwork

The following are **done** and are what makes a mechanical port plausible at
all. They are recorded here so in-source provenance comments referencing this
plan have a home; no further work is required on them.

- No `setjmp`/`longjmp`/`jmp_buf` anywhere (Go has no non-local jumps).
- One pure-Zig front end; the YACC/C lexer and parser are gone (one lexer and
  one parser to port, no C bridge).
- Structured diagnostics and error unions replace the old `SYNERR`
  flag-and-check-later pattern (maps directly onto Go's `(T, error)`).
- All I/O flows through `std.Io` writers/readers owned by the interpreter (maps
  onto Go's `io.Writer`/`io.Reader`; no `FILE*`-in-a-cell to translate).
- One aggregated `Interp` state value, owned explicitly and passed as a
  receiver; exactly one module-level mutable global (an atomic interrupt flag).
  Go has no comptime-ambient-state trick, so every dependency must already
  arrive as a parameter — it does.
- `@import`s form a DAG, enforced by `scripts/import_cycles.py` /
  `scripts/layer_check.py`. Go's compiler *rejects* import cycles outright, so
  this had to already hold.

## 3. Prerequisites — required code-shape work still pending

These are the only remaining *code* changes required before the port; they are
correctness prerequisites, not polish. Track each with `scripts/scorecard.sh`.

**P1 — Typed value model (`Value`/`Comb`/`CellRef`), no bare `Word` threshold
checks.** Every hot-path site must read `switch (v.kind())`, never
`if (x < ATOMLIMIT)` — a literal port of a numeric threshold check carries a
footgun into Go. Remaining surface: `heap.zig`'s public API, `lower.zig`,
the bulk of `infer.zig` (the core accessors `getId`/`idType`/`idWho`/`tInfo`,
50–78 callers each — the biggest single risk), `unify.zig`, `type_errors.zig`,
the rest of `codegen.zig`, and the `eval/combinators/*` handlers.
**Gate:** `toRaw` escape-hatch count → 0; `Word` appears only in `graph/dump.zig`.

**P2 — Confine C-isms to `os.zig`.** Every `[*:0]`, `c_int`/`c_long`/`c_ulong`,
and `extern fn` outside `os.zig` must go: `c_int`-family → `i32`/`i64`/`usize`/
`bool` (watch EOF-sentinel patterns that need to hold `-1`); `[*:0]` →
`[]const u8`/`[:0]u8` at the minimum boundary that still needs a sentinel; the
one stray `extern fn` (`eval/reduce_rt.zig`'s `fromUTF8`) moves behind an
`os.zig` wrapper. This is the long pole (hundreds of sites, concentrated in
`os.zig`, `session/commands.zig`, `parser/lex.zig`, `session/config.zig`,
`graph/heap.zig`, `compiler/module_loader.zig`, `session/boot.zig`,
`graph/strtab.zig`, `graph/bignum.zig`).
**Gate:** `grep -rl "extern fn" src` returns exactly `os.zig`; scorecard's
`[*:0]`/`c_int`-family counts at the `os.zig`-only floor.

**P3 — Directory consolidation to the target tree.** Fold the three transitional
directories into their homes so every directory has a decided Go package name
(§4.1) and no Go stdlib collision survives:
- `compiler/` (`compiler_state.zig`, `setup.zig`, `dump.zig`, `module_loader.zig`)
  → `semantics/modules.zig` and `graph/dump.zig` (resolve the two-`dump.zig`
  collision in the move).
- `parser/` (`codegen.zig`, `lex.zig`, `lex_state.zig`, `parser_api.zig`) →
  `semantics/lower.zig`; confirm `lex.zig`/`lex_state.zig` are fully subsumed by
  `syntax/lexer.zig` (delete if so).
- `runtime/` (`core_state.zig`, `errors.zig`, `runtime_state.zig`, `version.zig`)
  → `session/`.
Move-only commits, no logic change.
**Gate:** `find src -maxdepth 1 -type d` matches §4.1; DAG check green.

**P4 — File-size ratchet (recommended, not a hard gate).** Split files over
~1,000 lines along their existing internal section boundaries (`heap.zig`,
`lower.zig`, `infer.zig`, `lexer.zig`, `dump.zig`, `os.zig`, `bignum.zig`,
`reduce_core.zig`, `reduce_rt.zig`). Smaller units give the agent smaller,
independently-verifiable translation targets and localize failures. Move-only.

## 4. Go translation decisions

Front-loaded so the port makes no per-site choices. Each site's resolution is
emitted inline as a `// GO:` marker (§5.4); the tables below are the source of
truth those markers are generated from.

### 4.1 Package layout (stdlib-collision renames included)

| Zig directory / file | Go package | Note |
| --- | --- | --- |
| `src/graph/` | `graph` | — |
| `src/syntax/` | `syntax` | — |
| `src/semantics/` | `semantics` | — |
| `src/eval/` | `eval` | — |
| `src/session/` | `session` | — |
| `src/io/` | `mirio` | Go stdlib owns `io` |
| `src/runtime/` | `mrt` | Go stdlib owns `runtime` (folded into `session`/`mrt` per P3) |
| `src/os.zig` (POSIX floor) | `platform` | Go stdlib owns `os` |
| `src/tools/*.zig` (each a standalone binary) | `cmd/fdate`, `cmd/just`, `cmd/menudriver` | Go convention: one package per binary under `cmd/` |

### 4.2 `anytype` → Go (19 sites, 5 categories, all resolved)

| Category | Sites | Resolution |
| --- | --- | --- |
| **A — printf-style** `(comptime fmt, args: anytype)` | 11 (`menudriver.zig:310`, `runtime/errors.zig:87` `fatal`, `eval/stream.zig:95/166/173/182`, `syntax/parser.zig:107`, `syntax/lexer.zig:191/201`, `syntax/directives.zig:89/97`) | `(format string, args ...any)` wrapping `fmt.Sprintf`/`Fprintf`/`Printf`. `fatal` → print + `os.Exit(1)` (no `noreturn` needed). The 4 `record`/`recordStdout` sites may factor to one shared `Diagnostics.record` method — translation-time simplification, not required. |
| **B — scanf family** | 4 (`os.zig:296/404/503/668`) | **Delete**, don't port. Call sites use `fmt.Sscanf`/`fmt.Fscanf` directly. Caveat: verify each format string is within the subset Go's scanf supports (widths/specifiers differ) at `os.zig`-port time. |
| **C — variadic C call** | 1 (`os.zig:900` `execl`) | `func execl(path string, args []string) int32` — Go's `os/exec` takes `[]string`; drop the null-terminated variadic convention. |
| **D — fixed type set** | 2 (`heap.zig:1386` `constructor`; `os.zig:33` `syscallResult`) | `constructor` → three named methods `ConstructorWord`/`ConstructorInt`/`ConstructorStr`. `syscallResult` → inline at its `os.zig`-local call sites during the `platform` port. |
| **E — collapses after P2** | 1 (`strtab.zig:84` `strBits`) | After P2 unifies its callers to `[]const u8`, becomes a plain `p []const u8` parameter. Re-audit at P2 completion. |

### 4.3 `union(enum)` → Go (two patterns, chosen by hot-path-or-not)

**Pattern 1 — tagged struct** (`Tag` field + a struct wide enough for every
variant) for hot-path / fixed-width types; preserves bit layout, no per-value
allocation:
- `graph/value.zig` `Kind` (the reducer's hottest classification type).
- `syntax/lexer.zig` `EscapeErrorKind`, `Escape`.
- `graph/word.zig` `Value`/`classify` seam — **not ported**; superseded by
  `graph/value.zig`'s `Kind` (P1), expected deleted before the port.

**Pattern 2 — interface + one concrete struct per variant** (matches Go's own
`go/ast`) for the cold, tree-shaped AST/directive unions; each variant is a
struct with a zero-cost `isXxx()` marker method, child fields become the
interface type directly (no pointer):
- `syntax/ast.zig`: `TypeExpr` (7), `Literal` (4), `Qualifier` (3), `Expr` (18),
  `Pat` (8), `Rhs` (2), `TypeDecl` (3), `TopLevel` (6 — the 3 legacy-bridge
  variants `include`/`export_list`/`free_directive` are dead weight; confirm
  deletable in Zig during P3 so the port needn't carry them).
- `syntax/token_filter.zig`: `DirectiveAlias` (2), `Directive` (5 — its
  `deinit(gpa)` method has no Go equivalent; delete rather than translate, GC
  reclaims).
- `semantics/modules.zig`: `ExportPart` (4).

### 4.4 `Comb` comptime generation → `go:generate`

`graph/value.zig`'s `Comb = enum(u16)` is generated at Zig comptime from
`combinator.cmbnms` so it can't drift from the reducer's dispatch numbering. Go
has no comptime reflection over a runtime slice. **Decision:** a small
`go:generate go run ./internal/gen/comb` program reads the Go translation of
`cmbnms` (`[]string`) and emits `comb_gen.go` with `const` values, run once and
checked in. Port the existing spot-check test (`S`, `PLUS`, `False`, `True`,
`NIL`, `NILS`, `UNDEF`, plus member count) alongside.

### 4.5 Error sets → Go (5 sets, custom types)

Each set becomes a `XxxErrorKind` enum + `XxxError struct { Kind …; … }`
implementing `error`, in the Go package matching its Zig home — not one shared
type (keeps the cycle/ownership split the Zig side made deliberately).

| Zig set | Members | Go package | Change |
| --- | ---: | --- | --- |
| `word.ReduceError` (`Interrupted`, `FloatOverflow`) | 2 | `graph` | none; no payload |
| `errors.MiraError` (`SyntaxError`, `TypeCheckAbort`, `HeapExhausted`, `LoadError`, `EvaluationInterrupted`) | 5 | `session` | `+Message`; drop `EvaluationInterrupted` if still an unused placeholder at port time (verify) |
| `modules.ModuleError` (`IncludeCycle`, `IncludeCompileFailed`) | 2 | `semantics` | add `Path string` payload field |
| `parser_api.ParseError` (`SyntaxError`, `ParseFailed`) | 2 | `semantics` | `+Span`; own `Kind` type, so no clash with `MiraError.SyntaxError` |
| `pratt.ParseError` (`UnexpectedToken`, `UnexpectedEof`, `OutOfMemory`) | 3→2 | `syntax` | **drop `OutOfMemory`** (§4.6); `+Span` |

### 4.6 Standing translation-time rules

- **Bignum: port `graph/bignum.zig` mechanically as-is; do not swap to
  `math/big` in the same pass.** Its `show` formatting is golden-pinned; a
  library swap changes formatting/rounding the differential suite would have to
  re-validate. A `math/big` swap is a legitimate golden-verified *follow-up*,
  out of scope here.
- **Drop allocator threading.** Each `alloc: std.mem.Allocator` parameter
  disappears from the Go signature; call sites use `make`/`append`/`new`. This
  also removes `pratt.ParseError`'s `OutOfMemory` member and
  `token_filter.Directive`'s `deinit` method.
- **Tests:** one `foo.go` ↔ one `foo_test.go`; preserve the `Tests:`
  doc-comment cross-reference (each test's doc comment names the production
  function it covers) — only the file boundary changes, not the traceability.

## 5. Unsupervised scaffolding — the self-supervision layer

Go and Zig do not interlink, so there is no hybrid binary to diff midway: the
Go binary can't run end-to-end until the last package lands. Without the
following, that forces the worst loop for autonomy — translate everything blind,
build once at the end, diff a wall of failures with no way to localize them.
These four items give the agent an immediate, trustworthy pass/fail per unit.

### 5.1 Per-unit oracles (highest leverage)

Generalize the existing `capture-reducer-golden` / `verify-reducer-golden`
pattern to **every pipeline seam**, so each package is verified in isolation
against frozen Zig behaviour — no running end-to-end binary required.

| Stage | Package(s) | Oracle fixture | Status |
| --- | --- | --- | --- |
| Lex | `syntax/lexer` | token-per-line dump (kind + span + text) | **add** |
| Parse | `syntax/parser`, `pratt` | pretty-printed AST (deterministic node order) | **add** |
| Type-check | `semantics/infer`, `unify` | type signatures + sorted diagnostics | **add** |
| Codegen | `semantics/lower`, `codegen` | `.x` dump (already byte-stable) | reuse |
| Reduce | `eval/*` | WHNF result + spine trace | exists |

**Steps:** for lex/parse/type add a `capture-<stage>-golden`/`verify-<stage>-golden`
target pair mirroring the reducer's; freeze the serialization format
(deterministic — see §5.2); check fixtures into `tests/stage_golden/<stage>/`;
document, in one table, the exact verify command per package (the agent's
per-unit contract). **Freeze a reference binary:** tag today's `mira`
(`git tag go-port-oracle-base` + committed checksum) so the end-to-end
differential suite always has a stable reference to diff the Go binary against.

### 5.2 Determinism audit (makes byte-comparison valid)

Every oracle is a byte-comparison, sound only if identical input → identical
bytes on both sides. Three hazards, two of which **Go makes worse than Zig
today**:
- **Address-dependent output** — audit all `@intFromPtr` sites (~38); any that
  reaches a printed/dumped path must use a stable dense id (allocation-order
  index / interning slot), not the raw address.
- **Map-iteration order** — Go randomizes map iteration **by language spec,
  every run**; Zig's is merely unspecified. Audit all hash maps (~18) /
  `.iterator()` sites; any feeding output must **sort at the serialization
  boundary** (by name/id). This is the hazard most likely to silently poison
  the oracle — invisible in the Zig build, appears only after translation.
- **Timing / entropy** — triage the time/rand sites; confirm none on an
  output-affecting path (expected: none, but *verify* — an agent can't notice a
  flaky oracle the way a human running twice would).

Pin determinism at the serialization boundary in Zig, re-capture §5.1 fixtures,
and add `scripts/determinism_check.sh` that runs each capture target twice and
asserts byte-identical output. Wire into the phase gate.

### 5.3 Corpus coverage (makes "green" mean "correct")

An autonomous agent trusts the oracle completely; a source branch exercised by
no corpus input yields a green signal on a wrong translation it can't catch.
- Stand up coverage measurement (kcov or Zig coverage) reported per package.
- Per-package coverage floor; leaf packages hit first (`graph/bignum`,
  `graph/strtab`) at/near 100% of reachable branches.
- For each uncovered branch on a package about to be ported, add a corpus input
  (`.m`/`.in` pair, verified against the current Zig binary so it's correct by
  construction) — this grows the same corpus §5.1 captures from.
- Add coverage as a scorecard metric with an upward ratchet.

Ordering within prep: grow corpus (§5.3) → pin determinism (§5.2) → freeze
fixtures (§5.1), so the frozen oracle pins the newly-covered branches.

### 5.4 Efficiency levers

- **Inline `// GO:` markers**, generated *from* §4's tables (docs stay the
  single source of truth) so each decision sits on the exact line, covering
  every `anytype`/`union`/error site and every "delete, don't port" site. A
  `scripts/check_go_markers.py` asserts every table row has a live marker at its
  cited line and vice-versa (drift = build failure).
- **Machine-readable work manifest** `tests/go_port_manifest.tsv`
  (`package  deps  oracle-target  coverage-floor  status`), generated from the
  DAG so leaf-first order is correct by construction. Each row is one unit's
  full contract; `status` is the agent's own progress ledger (`ready`→`done`
  when the oracle passes) — a machine-readable "how far along is the port".
- **Go-side scaffolding:** `go.mod` + the §4.1 package skeleton (each stub's
  doc comment naming its Zig source), a Go test harness replaying §5.1 fixtures
  against a package's public API (`go test ./graph/...` = "run the oracle"), and
  a CI target running the end-to-end differential suite against the Go binary
  once `session/` lands.

## 6. Phases

| # | Name | Depends on | Size |
| --- | --- | --- | ---: |
| A | Determinism audit (§5.2) | — | M |
| B | Corpus coverage (§5.3) | — | M |
| C | Typed value model P1 (§3) | — | L |
| D | C-ism confinement P2 + `os.zig` boundary (§3) | — | L |
| E | Directory consolidation P3 + file-size P4 (§3) | — | M |
| F | Stage oracles + reference binary (§5.1) | A, B | L |
| G | Inline markers + manifest + Go scaffolding (§5.4) | E, F | M |
| H | Readiness gate | all | M |

Sizes: S ≤ 1 day, M = a few days, L = 1–2 weeks. A, B, C, D can run in
parallel. Each phase ends with the full suite (`check`, `strict`, `test-golden`,
`test-regression`, `test-sigint`, `test-spine`) plus `determinism_check.sh` and
the coverage ratchet green, then updates `scripts/scorecard.baseline` downward.

### Phase H — readiness gate (the proof)

Point an agent at one leaf package (`graph/strtab` or `graph/bignum`), its
manifest row, its `// GO:` markers, and its oracle target — and let it port that
package **unattended, with no human review of the translation**, certifying done
*only* by the oracle going green. Guard against a false green with a seeded
mutation test. If the agent gets stuck, or the oracle passes on a wrong
translation, the gap is a missing decision (→ §4), a determinism hole (→ §5.2),
or a coverage hole (→ §5.3) — fold it back before the real port. **This is where
this plan's scope ends.** The real port is the agent walking the manifest
leaf-to-root (`graph`→`eval`→`semantics`→`syntax`→`session`), each package gated
by its own oracle, the whole gated by the frozen end-to-end differential suite.

## 7. Working cadence

Tooling/fixture/shape-only commits; no behaviour change. Separate move-only
commits from signature changes. Every commit builds and passes `zig build
check`. Phase gates run the full suite. The suites — now including the stage
fixtures — are the spec; if a fixture and a golden case disagree, the golden
case wins and the fixture is regenerated. Commit and push after each phase gate.
