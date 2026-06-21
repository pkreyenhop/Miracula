# Miranda Zig Refactor – Phase 7: Idiomatic Zig Modernization

## Objective

Transform Miracula from a direct C-to-Zig translation into an idiomatic, maintainable Zig
codebase while preserving identical runtime behaviour. All six clusters are now complete.

---

## Key Findings (recorded at plan inception)

**Finding 1: The `export var`/`extern var` pattern was the root architectural problem.**
Almost all `pub extern fn` declarations in `main_clib.zig` were already implemented in Zig.
The `extern var` web was not C interop — it was Zig using the linker symbol table as a module
system. `repl.zig` alone had 57 `extern var` declarations to reach state in `main.zig`. This
was the root cause of the tight coupling and was addressed across Clusters A, B, and F.

**Finding 2: Extraction had to precede encapsulation.**
The step ordering (Cluster A before B) was critical: extracting modules first gave stable
ownership boundaries, making it safe to consolidate global state into `RuntimeState` in B1.

**Finding 3: Signal-handler paths cannot use Zig error unions.**
POSIX signal handlers (`SIGINT`/`SIGFPE`) are asynchronous — they fire on any call stack and
cannot propagate errors via stack unwinding. The `sigjmp_buf rs.env` field in `RuntimeState`
is permanent; it cannot be replaced with `error{EvaluationInterrupted}`. Documented in E3.

**Finding 4: Two setjmp/longjmp sites were actionable.**
The `gc()` local setjmp/longjmp (a masked `return`) and the `types.zig` type-checker abort
chain were fully convertible to Zig error unions. Signal-handler sites were not.

---

## Completed Work

### Cluster A: Architecture & Module Boundaries

*Goal: Eliminate the linker-as-module-system anti-pattern; reduce `main.zig` to a composition root.*

* **A1 — Replace `extern var` in `repl.zig`** ✅
  Replaced 57 `extern var` declarations with `@import("../main.zig")`.

* **A2 — Extract `src/driver/commands.zig`** ✅
  Extracted `command()` dispatcher and helpers from `main.zig`.

* **A3 — Extract `src/compiler/setup.zig`** ✅
  Extracted `mira_setup`, `primdef`, `predef`, `primlib`, `privlib`, `stdlib`.

* **A4 — Extract `src/compiler/module_loader.zig`** ✅
  Extracted `loadfile`, `mkincludes`, and path tracking.

* **A5 — Extract `src/compiler/dump.zig` and `src/io/files.zig`** ✅ *(2026-06-20)*
  Extracted `undump`, `makedump`, `fixexports`, `unfixexports`, `readoption`, `sigdefer` into
  `dump.zig`. Extracted filesystem helpers (`fm_time`, `normal`, `filecopy`, etc.) into
  `io/files.zig`. `main.zig` is now 267 lines — a composition root of `pub const` aliases
  and the 8 C-ABI-constrained `export var` declarations.

---

### Cluster B: State Encapsulation

*Goal: Eliminate implicit global state.*

* **B1 — Introduce `RuntimeState`** ✅
  Created `src/runtime/runtime_state.zig`. ~75 global variables consolidated into the
  `RuntimeState` struct; singleton `pub var rs: RuntimeState = .{}` in `main.zig`. All
  callers converted to `main.rs.field`. 8 "stuck" vars remain as `pub export var` in
  `main.zig` (`nill`, `loading`, `compiling`, `errs`, `errline`, `obsuffix`, `SYNERR`,
  `commandmode`) — `heap.zig` and `parser_api.zig` cannot safely re-import `main.zig`
  without creating a circular dependency. `strictif` converted from `Word` to `bool`.

* **B2 — Encapsulate heap array access** ✅
  Removed `pub const h/t/hp/tp` aliases from `main.zig`. All callers use
  `main.heap.h(...)` etc. directly.

---

### Cluster C: Type Safety & Domain Modeling

*Goal: Leverage Zig's type system at API boundaries.*

* **C1 — `NodeTag` enum** ✅
  Added `pub const NodeTag = enum(u8) { ATOM=0, …, TCONS=22, _ }` to `c_abi.zig`.
  Non-exhaustive (`_`) because GC mark phase temporarily negates tag bytes (sign-bit trick).
  `pub fn getTag(x: Word) NodeTag` added to `heap.zig` as the typed read boundary.

* **C2 — API boundary domain types** ✅ *(2026-06-21)*
  Added `FileNode`, `Identifier`, `TypeRef`, `NodeRef` as `pub const` structs in `heap.zig`,
  each wrapping `.word: Word`. Re-exported from `main.zig`. Existing procedural accessors
  unchanged; types wrap them via methods (D2).

---

### Cluster D: Ergonomics

*Goal: Modernize internal syntax and improve discoverability.*

* **D1 — Internal string slices** ✅ *(2026-06-21)*
  Converted `is()`, `filequote()` (commands.zig) and `missparam()` (startup.zig) from
  `[*:0]const u8` to `[:0]const u8`. `std.mem.span()` added at the two entry points where
  C-originated pointers arrive. FFI boundary functions kept as `[*:0]const u8`.

* **D2 — Domain methods** ✅ *(2026-06-21)*
  Methods added to all four domain types in `heap.zig`:
  - `FileNode`: `.time()`, `.share()`, `.defs()`, `.inodev()`, `.sameAs(other)`
  - `Identifier`: `.typ()`, `.val()`, `.who()`, `.isConstructor()`, `.isVariable()`,
    `.isFreeId()`, `.addToEnv()`
  - `TypeRef`: `.class()`, `.info()`
  - `NodeRef`: word wrapper only; specialised types preferred

* **D3 — Documentation** ✅ *(2026-06-21)*
  Added `///` doc comments to all `pub` declarations in `io/files.zig`,
  `runtime/runtime_state.zig`, `compiler/setup.zig`, `compiler/dump.zig`,
  `compiler/module_loader.zig`. Comments focus on invariants, ownership, and contracts.

---

### Cluster E: Control Flow & Error Handling

*Goal: Replace C setjmp/longjmp non-local exits with Zig error unions where possible.*

* **E1 — Define `MiraError`** ✅ *(2026-06-21)*
  Created `src/runtime/errors.zig` with
  `pub const MiraError = error{ SyntaxError, TypeCheckAbort, HeapExhausted, LoadError, EvaluationInterrupted }`.
  Each variant documents its invariants. Re-exported from `main.zig`.

* **E2 — Error union signatures & bubbling** ✅ *(2026-06-21)*
  Two sites converted:
  1. `gc()` in `heap.zig` — the `setjmp`/`longjmp` pair was a masked `return`; both removed.
  2. `types.zig` type-checker abort — removed `export var env1` and `export fn types_abort()`.
     Converted `meta_tcheck`, `etype`, `conforms`, `comp_deps`, `abstr_check`, `abstr_mcheck`,
     `mcheckfbs` to `MiraError!Word` / `MiraError!void`. `export fn checktypes() void` catches
     via a labeled `outer:` block; other callers use `catch return` / `catch {}`.

* **E3 — Signal-handler constraint documented** ✅ *(2026-06-21)*
  `commandloop` (`sigsetjmp`/`siglongjmp` for SIGINT/SIGFPE) cannot be converted — signal
  handlers are asynchronous and cannot propagate Zig errors. `rs.env` (`sigjmp_buf`) is
  permanent. Constraint documented in `errors.zig`, `runtime_state.zig` field comment, and
  this plan.

---

### Cluster F: Linker-Symbol Elimination & Code Health

*Goal: Finish removing `extern var` from compiler modules; clean up stale artefacts; expand tests.*

* **F1 — Eliminate `extern var` from `types.zig`** ✅ *(2026-06-21)*
  All 10 `extern var` declarations replaced by `main.*` references. `types.zig` now has zero
  `extern var`.

* **F2 — Selective `extern var` → `@import` in `trans.zig` and `module_loader.zig`** ✅ *(2026-06-21)*
  Converted 10/14 in `trans.zig` and 12/19 in `module_loader.zig`. Non-convertible remainder:
  vars owned by `lex.zig` (no safe import path) and C-side vars without Zig equivalents.

* **F3 — Stale artefact cleanup** ✅ *(2026-06-21)*
  - Removed dead `const c_jmp = c` alias from `heap.zig` (setjmp gone since E2).
  - Removed pre-plan TODO comment blocks from `heap.zig` and `word.zig`.
  - Pruned `c_abi.zig` jmp re-exports to signal-only: removed `jmp_buf`/`setjmp`/`longjmp`;
    kept `sigjmp_buf`/`sigsetjmp`/`siglongjmp` (E3 constraint).

* **F4 — Boolean Word field audit** ✅ *(2026-06-21)*
  Converted 6 `RuntimeState` fields from `Word = 0` to `bool = false`:
  `magic`, `making`, `mkexports`, `mksources`, `okprel`, `nostdenv`.
  Updated all assignment and comparison sites in startup.zig, repl.zig, commands.zig,
  dump.zig, module_loader.zig, lex.zig, runtime_state.zig.
  Skipped: `rechecking` (3-valued: 0/1/2), `bereaved` (heap Word), `baded` (written by C
  runtime), `verbosity`/`initialising` (deferred).

* **F5 — Expand test coverage** ✅ *(2026-06-21)*
  Unit test count: 26 → 31. New tests:
  - `errors.zig`: all 5 `MiraError` variants are pairwise-distinct; `anyerror` coercion works.
  - `runtime_state.zig`: bool fields default to `false`; optional fields default to `null`.
  - `heap.zig`: domain-type word-preservation; comptime method-signature check
    (`FileNode.time`, `Identifier.typ`, `TypeRef.class` each resolve to `fn(T) Word`).

---

## Remaining Patterns (not addressed in this phase)

These are known, bounded issues. They are safe to leave for a future phase.

| Pattern | Location | Count | Notes |
|---------|----------|-------|-------|
| `extern var` (non-convertible) | heap.zig (62), trans.zig (4), module_loader.zig (7), others | ~130 | Vars owned by lex.zig / C runtime; need circular-dep fix or state migration |
| `export fn` (linker-as-module) | types.zig (69), trans.zig (49), heap.zig (44), lex.zig (45)… | ~350 | Functions called cross-module via linker; conversion requires establishing direct import paths |
| `[*:0]` at internal call sites | various | ~349 | FFI boundaries are correct as-is; internal helpers could use `[:0]` |
| `c_int` / `c_long` types | various | ~340 | `Word = c_long` is platform-correct; safe to alias to `i64` on known platforms |
| `= undefined` initialisations | various | ~108 | Many are buffers; worth auditing for zero-init where appropriate |

---

## Progress Summary

| Cluster | Step | Title | Status |
|---------|------|-------|--------|
| A | A1 | Replace `extern var` in `repl.zig` with `@import()` | ✅ Complete |
| A | A2 | Extract `driver/commands.zig` | ✅ Complete |
| A | A3 | Extract `compiler/setup.zig` | ✅ Complete |
| A | A4 | Extract `compiler/module_loader.zig` | ✅ Complete |
| A | A5 | Extract `compiler/dump.zig` + `io/files.zig` | ✅ Complete |
| B | B1 | Introduce `RuntimeState`; boolean audit (strictif) | ✅ Complete |
| B | B2 | Encapsulate heap array access | ✅ Complete |
| C | C1 | `NodeTag` enum | ✅ Complete |
| C | C2 | API boundary domain types | ✅ Complete |
| D | D1 | Internal string slices (`[:0]`) | ✅ Complete |
| D | D2 | Domain methods | ✅ Complete |
| D | D3 | `///` doc comments on pub API | ✅ Complete |
| E | E1 | Define `MiraError` error set | ✅ Complete |
| E | E2 | Error union signatures & bubbling | ✅ Complete |
| E | E3 | Signal-handler constraint documented | ✅ Complete |
| F | F1 | Eliminate `extern var` from `types.zig` | ✅ Complete |
| F | F2 | Selective `extern var` → `@import` in trans / module_loader | ✅ Complete |
| F | F3 | Stale artefact cleanup | ✅ Complete |
| F | F4 | Boolean Word field audit (6 fields) | ✅ Complete |
| F | F5 | Expand unit test coverage (26 → 31) | ✅ Complete |
