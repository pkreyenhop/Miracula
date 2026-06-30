# Miracula — Readability Plan (idiomatic names + documentation)

> A module-by-module pass to make the C-ported codebase read like idiomatic Zig:
> rename C-style symbols to Zig conventions and document every module, function,
> type, field, and notable constant — **behaviour-preserving** (golden corpus
> byte-identical at every step). Tracked by `scripts/readability-check.sh`.

## Objective

The interpreter was ported from C Miranda, so it carries C-isms in its names:
`snake_case` functions (`sto_int`, `bigtodbl`, `fm_time`), terse abbreviations
(`poz`, `msd`, `dicp`), and sparse documentation. This pass makes each module
idiomatic and self-explaining without changing behaviour.

## Conventions (idiomatic Zig)

* **Functions** → `camelCase`, dropping the redundant module prefix
  (`big.bigplus` → `big.add`, `big.sto_int` → `big.fromInt`). Constructors read
  `fromX` / build, converters `toX`.
* **Variables / parameters / fields** → `snake_case`.
* **Types** → `TitleCase`; **error sets / enums** → `TitleCase` members.
* **Documentation** → `///` doc comments on the module (`//!` header), every
  `pub` function, every type and its fields, and non-obvious private helpers;
  `//` line comments on magic constants and tricky steps.
* **FFI exemption** — `runtime/main_clib.zig` (the libc/syscall shim) and
  `src/tools/` keep their C names deliberately; excluded from the metric.
* **Convention exemptions** — names that mirror an external/constant identifier
  stay as-is (still documented): the POSIX-macro helpers (`WIFSIGNALED`,
  `WTERMSIG`) and the reducer dispatch handlers `handle_<COMBINATOR>`, whose
  snake suffix matches the uppercase `word.<COMBINATOR>` constant (e.g.
  `word.G_ALT` → `handle_G_ALT`) and keeps the dispatch table grep-aligned.

## Approach (per module, golden-gated)

Two phases, each ending green, so a rename bug can't hide behind a doc change:

1. **Rename** — mechanical, word-boundary `perl` substitutions that preserve the
   algorithms (no transcription), applied to the module *and* every external call
   site in lock-step. Then `zig build` + **golden byte-diff** + tests.
2. **Document** — module header, per-function/type/field doc comments, constant
   comments. (Comments can't change behaviour; a quick build confirms syntax.)

This is exactly the workflow proven on `big.zig` (the first module): 23 public +
~14 private renames, 59 external call sites updated, full docs, golden 44/44.

## Metric

`scripts/readability-check.sh` reports two numbers (FFI shim & tools excluded):

| Metric | Baseline (2026-06-24) | Now (2026-06-30) | Target |
|--------|----------------------:|-----------------:|-------:|
| C-style (`snake_case`) fn definitions | 175 | **2** (both exempt/flagged — see below) | 0 |
| documented fn definitions | 146/879 (16%) | **882/894 (98%)** | ~100% |
| modules complete (renamed **and** documented) | 1/44 | ~44/45 | all |

**The readability pass is essentially complete** — every function outside the FFI
shim and the intentional `handle_<COMBINATOR>` dispatch convention is idiomatically
named and documented, behaviour-preserving (golden byte-identical at every step).
The check script reports **2 residual `snake_case` fn defs** and **12 undocumented**
fns, accounted for as follows (no further rename pass is scheduled here):

* **`driver/lineedit.zig` `tab_complete`** — a **convention exemption** (like the
  `handle_<COMBINATOR>` handlers): the name is dictated by `zigline`, which reflects
  over the handler struct's decls and calls a method *named* `tab_complete`. Keep as
  is; it should be added to the metric's exemption list.
* **`runtime/heap.zig` `get_fil`** — a snake holdover whose camelCase target name
  (`getFil`) is **already taken by two private helpers** (`heap.zig:1329`,
  `parser/lex.zig:180`) that read the same file-name field via the *pre-interning*
  `castPtr` path rather than `strtab.strOf`. Renaming it blindly collides and masks a
  representation split — so it is flagged for the dedup/investigation pass tracked in
  [REMAINING_WORK_PLAN.md](REMAINING_WORK_PLAN.md) (Phase 1, with R3/B1), **not** a
  mechanical rename here.
* The 12 undocumented fns are minor residue (e.g. `word.zig` 51/55, `repl.zig` 14/16)
  — a light doc top-up, not blocking.

Run `scripts/readability-check.sh` for the live numbers.

(The "Now" snake figure also reflects the reducer-handler exemption added to the
metric, which removed ~37 dispatch handlers from the count.)

A module is *complete* when its `snake_case` fn count is 0 **and** its functions
carry doc comments. The script's per-file rows (`snake  doc/fns  file`) show where
the work is; a `0`-snake module may still need a documentation pass.

Done so far: `big.zig`, `io/files.zig`, `driver/repl.zig`, `driver/startup.zig`,
`runtime/reducer/io.zig`, `runtime/reducer/ready.zig`,
`runtime/reducer/combinators.zig`, `runtime/reduce.zig`.

## Module inventory & status

> **The per-module inventory below was retired (2026-06-30).** It tracked the
> rename/doc pass module-by-module while it was in flight and had gone stale (it
> showed several modules as `◐ doc pass pending` that had since reached 100%, and
> predated `driver/lineedit.zig`). The pass is now driven by the two aggregate
> numbers in the **Metric** table above plus the live `scripts/readability-check.sh`
> per-file rows; the only remaining items are the two named there (`tab_complete`
> exemption, `get_fil` dedup). There is no per-module work left to track separately.

## Suggested order

Small / self-contained first (low risk, build the habit), then the heavy
domain modules:

```
big.zig ✅ → io/files, driver/repl, driver/startup, reducer/io, reducer/ready,
reducer/combinators, reduce.zig → parser/lex, reducer/lex
→ heap.zig → compiler/trans → compiler/types   (the three biggest, last)
→ doc-review sweep over the 0-snake modules
```

## Risk

| Risk | Mitigation |
|------|------------|
| a rename corrupts a subtle algorithm | renames are mechanical (no transcription); golden byte-diff + tests after every module |
| a rename hits a string/comment | post-rename grep for the new token inside `"`…`"` / `//` (caught two such on `big.zig`'s neighbours during 2b/2c) |
| public-API rename misses a call site | rename module + callers in one pass; build fails loudly on any miss |
| name choice churn | conventions above fixed up front; module prefix supplies context, so names stay short |
