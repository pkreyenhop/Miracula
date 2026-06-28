# Miracula — Testability Plan

> **Goal:** at least one inline `test` under every function definition — a test that
> both *verifies* and *explains* the function. Prioritise work that improves
> **testability** and **encapsulation** so that goal is actually reachable.
> Tracked by `scripts/test-coverage-check.sh`.

This plan also consolidates **everything still unachieved across the other plan
docs** and reprioritises it through the testability lens.

## Where things stand (2026-06-29)

| Axis | State |
|------|-------|
| Test blocks vs functions | **49 / 1091 (4%)** — most behaviour is covered only end-to-end (golden 44, the `mira_tests` integration suite), not per-function |
| Naming + documentation | ✅ 100% (readability pass) — every fn is idiomatically named and documented, so tests can focus purely on behaviour |
| Encapsulation | one resettable `interp` aggregate (shared-state Phase 4 ✅); **39** module-scope mutable globals remain (target 1); `interp.reset()` is the test-isolation primitive |
| Reducer / module graph | ✅ direct dispatch (G2), no `extern fn` handler pairs; circular `@import` cycles dissolved |

The two enablers are already in place: **(a)** behaviour is pinned by the golden
corpus, so adding tests can't silently change semantics, and **(b)** `interp.reset()`
gives each test a clean slate. The gap is simply that the tests haven't been
written, and a few stateful functions are still awkward to exercise in isolation.

## Unachieved items across all plans (consolidated)

| Source plan | Item | Status | Testability relevance |
|-------------|------|:------:|-----------------------|
| SHARED_STATE | Phase 5 — thread `*Interp` through the call graph | ⬜ deferred | **High** (independent/parallel instances) — but *not required* for serial per-fn tests (`reset()` suffices); ~2,100 sites |
| SHARED_STATE | Phase 6 — delete the global `interp`; `main` constructs it | ⬜ | depends on P5 |
| SHARED_STATE | residual loose globals (gpa/allocator/io/environ + the 39) | ◐ | **Med** — fewer globals = simpler, more isolatable units |
| REDESIGN | Track B2 — `Value` union (typed values) full migration | ◐ char boundary only | **Med** — typed reads make assertions precise |
| REDESIGN | Track B3 — tracing GC | ⬜ | Low (representational; large) |
| REDESIGN | Track A4b — recovery (SIGFPE/reducer unwind) redesign | ⬜ | Low (design-bearing, unverifiable by golden) |
| IDIOMATIC/ARCH | J1 — error unions for `SyntaxError`/`LoadError` | ⬜ | **Med** — errors-as-values are directly testable vs `SYNERR` sentinels |
| IDIOMATIC/ARCH | J2 — standardise the "dump stats then die" panics | ⬜ | Low |
| IDIOMATIC/ARCH | I1 (slices), I3/N (optionals) | analysed → no-op | n/a |
| READABILITY | inventory table stale (shows ◐; actually 100%) | ◐ doc only | n/a (doc hygiene) |
| ARCHITECTURE | "Remaining Opportunities" lists K2 as todo (it's ✅) | ◐ doc only | n/a (doc hygiene) |

## Prioritised backlog

### P0 — Testability harness *(do first; unblocks everything below)*

1. **`testutil` helper** (e.g. `src/testutil.zig`, test-only): a `freshInterp()`
   that does `interp.reset(); lex.setupdic(); setup.miraSetup();` (the proven
   `reduce_test` recipe), small **graph builders** (`intNode`, `cons`, `ap`,
   `str`), and **assert helpers** (`expectInt`, `expectList`, `expectReducesTo`).
   This makes a per-function test two or three lines instead of twenty.
2. **Conventions** (write into this doc / CONTRIBUTING): tests live in an inline
   `test "<fn>: <behaviour>"` block beside the function; each test is a *minimal,
   readable example* (it doubles as documentation); reset/`freshInterp` between
   tests that touch global state; pure functions need no setup.
3. **Metric**: `scripts/test-coverage-check.sh` (added) — drives the 4% → ~100%.

### P1 — Per-function tests, module-by-module *(the goal)*

Same cadence as the rename/doc passes: one module at a time, golden-gated,
committed per module. Ordered by **testability** (cheapest, highest-confidence
first), so momentum builds before the stateful modules:

* **Tier A — pure leaves (no interp state):** `word.zig` (classify, the C-string
  + ctype helpers), `big.zig` (arithmetic — deterministic given the heap),
  `strtab.zig`, `combinator.zig`, `errors.zig`, `version.zig`,
  `parser/token_filter.zig`, `parser/ast.zig`, `parser/pratt.zig` (has 7 — finish
  it).
* **Tier B — heap/graph, deterministic with a fresh heap:** `heap.zig`
  (cells/accessors/GC/dump round-trip), `reduce.zig` (`numplus`/`compare`/`force`/
  `getstring`), `reducer/combinators.zig` + `reducer/lex.zig` + `reducer/ready.zig`
  (rewrite rules — exercise via tiny graphs, as `reduce_test` already does).
* **Tier C — stateful (need `freshInterp`):** `parser/lex.zig`, `compiler/types.zig`
  (inference), `compiler/trans.zig` (codegen), `parser/codegen.zig`,
  `parser/parser_api.zig`, `compiler/{setup,module_loader,dump}.zig`,
  `driver/{commands,repl,startup}.zig`.

Trivial one-line accessors (`h`/`t`/`hp`/`tp`) can be covered by a single
"accessors round-trip" test rather than one each — the metric denominator counts
them, but the spirit is *meaningful* coverage.

### P2 — Encapsulation that improves testability

* **Fold the residual globals** (`gpa`/`allocator`/`io`/`environ`, then the rest
  of the 39) into `interp`. Incremental, mechanical, shrinks the global surface a
  unit test must reason about. *(SHARED_STATE Phase 2 tail / Phase 3 residual.)*
* **SHARED_STATE Phase 5 — thread `*Interp`.** Lets tests construct *independent*
  interpreter instances (no shared global, parallel-safe). High value for a test
  suite, but large (~2,100 sites, hot reducer) — and **not a prerequisite** for
  P1, since `reset()` already isolates serial tests. Schedule only once parallel
  or re-entrant testing is actually wanted; do it per-subsystem with a reducer
  benchmark. Phase 6 (delete the global) follows.

### P3 — Representational / error-model *(testability-adjacent)*

* **REDESIGN Track B2 — finish the `Value` union.** Typed reads (`.imm`/`.atom`/
  `.ref`) make test assertions exact instead of `Word`-comparisons. Medium.
* **J1 — `MiraError` for `SyntaxError`/`LoadError`.** Replacing the `SYNERR`/
  `errs` sentinels with error unions makes parser/loader failures directly
  assertable (`try expectError(...)`). Medium.
* **J2 — standardise panics**; **Track B3 — tracing GC**; **Track A4b — recovery
  redesign.** Larger/design-bearing; defer behind the above.

### P4 — Doc hygiene *(quick wins)*

* Refresh the `READABILITY_PLAN.md` inventory table (it still shows `◐` for
  heap/lex/types/trans, which are now 100% documented).
* Refresh `ARCHITECTURE.md` "Remaining Modernization Opportunities" (K2/naming is
  done; I1/I3/N were analysed as no-ops).

## Metric

`scripts/test-coverage-check.sh` reports test blocks, function definitions, and
the per-module ratio (FFI shim + tools excluded):

| Metric | Baseline (2026-06-29) | Target |
|--------|----------------------:|-------:|
| test blocks | 49 | — |
| function definitions | 1091 | — |
| tests-per-fn ratio | **4%** | ~100% |

## Suggested first step

Land **P0** (the `testutil` harness + conventions), then take **`word.zig`** as
the first P1 module — it's pure, foundational, and every other test will lean on
the values it defines.
