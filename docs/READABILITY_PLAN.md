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

| Metric | Baseline (2026-06-24) | Now | Target |
|--------|----------------------:|----:|-------:|
| C-style (`snake_case`) fn definitions | 175 | **0 ✅** | 0 |
| documented fn definitions | 146/879 (16%) | **873/873 (100%) ✅** | ~100% |
| modules complete (renamed **and** documented) | 1/44 | **44/44 ✅** | 44/44 |

**The readability pass is complete.** Every function across the codebase (outside
the FFI shim and the intentional `handle<COMBINATOR>` dispatch convention) is now
idiomatically named *and* carries a doc comment, with a `//!` header on every
module — all of it behaviour-preserving (golden 44/44 byte-identical at every
step). Run `scripts/readability-check.sh` to confirm `0` snake fns and `100%`
documented.

(The "Now" snake figure also reflects the reducer-handler exemption added to the
metric, which removed ~37 dispatch handlers from the count.)

A module is *complete* when its `snake_case` fn count is 0 **and** its functions
carry doc comments. The script's per-file rows (`snake  doc/fns  file`) show where
the work is; a `0`-snake module may still need a documentation pass.

Done so far: `big.zig`, `io/files.zig`, `driver/repl.zig`, `driver/startup.zig`,
`runtime/reducer/io.zig`, `runtime/reducer/ready.zig`,
`runtime/reducer/combinators.zig`, `runtime/reduce.zig`.

## Module inventory & status

Status: ✅ done · ◐ partial · ⬜ todo. "snake" = C-style fn defs remaining
(rename size); "doc" = documented-fn ratio (doc size).

### runtime/ (the core)
| Module | snake | doc | status |
|--------|------:|----:|:------:|
| `big.zig` | 0 | 47/51 | ✅ |
| `heap.zig` | 0 | 17/138 | ◐ (renamed; doc pass pending) |
| `reduce.zig` | 0 | 33/33 | ✅ |
| `word.zig` | 0 | — | ◐ (names ok; doc review) |
| `strtab.zig` · `interp.zig` · `trace.zig` | 0 | high | ◐ (recently written; light review) |
| `combinator.zig` · `core_state.zig` · `errors.zig` · `runtime_state.zig` · `version.zig` | 0 | mixed | ⬜ (doc review) |

### runtime/reducer/
| Module | snake | doc | status |
|--------|------:|----:|:------:|
| `reduce.zig` · `reduce_core.zig` | 0 | commented | ◐ (commented this session; name review) |
| `reducer/lex.zig` | 33† | 0/33 | ⬜ (†mostly exempt handlers) |
| `combinators.zig` | 0 | 48/48 | ✅ |
| `io.zig` | 0 | 4/4 | ✅ |
| `ready.zig` | 0 | 1/1 | ✅ |
| `trace.zig` · `reduce_test.zig` | 0 | high | ◐ |

### parser/
| Module | snake | doc | status |
|--------|------:|----:|:------:|
| `lex.zig` | 0 | 0/71 | ◐ (renamed; doc pass pending) |
| `parser.zig` · `pratt.zig` · `ast.zig` · `diagnostics.zig` · `token_filter.zig` · `codegen.zig` · `parser_api.zig` · `lex_bridge.zig` · `lex_state.zig` | 0 | mixed | ◐/⬜ (newer Zig; doc review) |

### compiler/
| Module | snake | doc | status |
|--------|------:|----:|:------:|
| `types.zig` | 0 | 0/122 | ◐ (renamed; doc pass pending) |
| `trans.zig` | 0 | 0/112 | ◐ (renamed; doc pass pending) |
| `setup.zig` | 0 | 6/9 | ◐ (renamed) |
| `module_loader.zig` · `dump.zig` · `compiler_state.zig` | 0 | mixed | ⬜ (doc review) |

### driver/ · io/ · root
| Module | snake | doc | status |
|--------|------:|----:|:------:|
| `driver/startup.zig` | 0 | 10/10 | ✅ |
| `driver/repl.zig` | 0 | 15/15 | ✅ |
| `driver/commands.zig` | 0 | low | ⬜ |
| `io/files.zig` | 0 | 10/10 | ✅ |
| `io/platform.zig` · `io/signals.zig` · `io/utf8.zig` | 0 | mixed | ◐ |
| `main.zig` | 0 | low | ⬜ (doc review) |

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
