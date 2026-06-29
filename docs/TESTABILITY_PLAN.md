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

### P0 — Testability harness ✅ *(done 2026-06-29)*

1. **`testutil` helper** — `src/testutil.zig` (test-only): `freshInterp()` (the
   proven `reduce_test` recipe: `interp.reset(); lex.setupdic(); setup.miraSetup();`,
   idempotent/one-time), graph builders (`int`, `ap`, `ap2`, `cons`, `list`, `str`),
   and reduction-aware assertions (`expectInt`, `expectList`, `expectReducesTo`,
   `expectTag`). Five self-tests double as usage examples. Wired into `main.zig`'s
   comptime block so it runs under `main-tests` (and is type-checked, but not
   emitted, in the `mira` exe). A per-function test is now ~3 lines.
2. **Conventions** — see [Test conventions](#test-conventions) below.
3. **Metric** — `scripts/test-coverage-check.sh` (added) — drives the 4% → ~100%.

### P1 — Per-function tests, module-by-module *(the goal)*

Same cadence as the rename/doc passes: one module at a time, golden-gated,
committed per module. Ordered by **testability** (cheapest, highest-confidence
first), so momentum builds before the stateful modules:

* **Tier A — pure leaves (no interp state):** `word.zig` ✅ *(classify + type
  model, the C-string helpers, ctype, FILE read core, `formatC` — 21 tests; the
  untested remainder is the stdio I/O wrappers, covered end-to-end)*; `big.zig` ✅
  *(all 23 bignum ops: arithmetic, div/mod floor semantics, float conv, the
  decimal/hex/octal scanners and list renderers — uses `freshInterp` since bignums
  live on the heap; corrected the `div` doc from "toward zero" to floor)*;
  `strtab.zig` ✅ *(intern/dedup/resolve, privatize, deinit — 4 tests)*;
  `errors.zig` (1 fn, retrofit), `parser/pratt.zig` (has 7 — finish it).
  *Skip* (no functions — just constants/types, nothing to unit-test):
  `combinator.zig`, `version.zig`, `parser/token_filter.zig`, `parser/ast.zig`.
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

## Test conventions

* **Tests go *immediately after* the function** they cover — the idiomatic Zig
  layout — not grouped at the bottom of the file. (`reduce_test.zig` and
  `parser_tests.zig` predate this and stay where they are.) Method tests go right
  after the `struct` that defines them; any test-only helper `fn`s go below the
  tests.
* **Name `"<fn>: <behaviour>"`.** e.g. `test "numplus: adds two ints"`. The name
  starts with the function name so `grep 'numplus:'` finds every test for it, and
  it reads as a sentence in test output.
* **Reference tests from the doc comment** so they show on hover (ZLS renders doc
  comments). End the function's `///` block with a `Tests:` line:
  ```zig
  /// libc `strlen` (0 for null).
  ///
  /// Tests: strlen: counts bytes up to NUL, 0 for null
  pub fn strlen(...) usize { ... }
  ```
* **A test is documentation.** Prefer one *minimal, readable* example that makes
  the function's contract obvious over an exhaustive matrix. Add edge cases as
  separate, equally small tests when they clarify behaviour (empty input,
  boundary, the bug a regression guards).
* **Pure functions need no setup.** Tier-A leaves (`word`/`big`/`strtab`
  classifiers, etc.) take literal inputs and assert directly — do **not** import
  the harness into a pure leaf.
* **Stateful functions use the harness.** Call `t.freshInterp()` first, build
  inputs with the `testutil` builders, assert with its `expect*` helpers. Name any
  identifiers/fixtures uniquely — `freshInterp()` gives a *working* interp, not
  per-test isolation, so declarations persist across tests in a binary.
* **New `main-tests` files** must be added to `main.zig`'s comptime `_ = @import`
  block (that is how the `main-tests` target discovers them); verify by running
  the binary directly (see [the build quirk](../README.md) — `zig build test`
  prints a spurious "failed command").

Harness import path is relative to the test file, e.g. from `src/runtime/heap.zig`:
`const t = @import("../testutil.zig");`.

## Metric

`scripts/test-coverage-check.sh` reports test blocks, function definitions, and
the per-module ratio (FFI shim + tools excluded):

| Metric | Baseline (2026-06-29) | Target |
|--------|----------------------:|-------:|
| test blocks | 49 | — |
| function definitions | 1091 | — |
| tests-per-fn ratio | **4%** | ~100% |

## Next step

P0 is landed. Start **P1** with **`word.zig`** — it's pure, foundational, and
every other test leans on the values it defines.
