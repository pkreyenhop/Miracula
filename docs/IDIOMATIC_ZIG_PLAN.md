# Miranda Zig Refactor – Phase 7: Idiomatic Zig Modernization

## Objective

Transform Miracula from a direct C-to-Zig translation into an idiomatic, maintainable Zig
codebase while preserving identical runtime behaviour. All seven clusters are now complete.

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

---

### Cluster G: Module Graph Repair (Planned)

*Goal: Eliminate the remaining linker-as-module-system connections by giving every Zig module
a proper `@import` dependency graph. The two structural blockers are the `heap.zig ↔ main.zig`
circular import and the reducer subsystem's handler dispatch through the C-ABI linker.*

---

#### G1 — Break the `heap.zig ↔ main.zig` circular dependency ✅

**Why it exists.** `heap.zig` imports `main.zig` to access `RuntimeState` (`rs.*`) and
miscellaneous state aliases (`main.files`, `main.SGC`, `main.get_id`, …). But `main.zig`
imports `heap.zig` for domain types and accessors. This circle forces the 8 "stuck" export
vars (`nill`, `loading`, `compiling`, `errs`, `errline`, `obsuffix`, `SYNERR`, `commandmode`)
to live in `main.zig` rather than `RuntimeState`, and it forces `heap.zig` to declare them
as `extern var` rather than reading them from a named import.

**Solution: extract a new `src/runtime/core_state.zig`.**

`core_state.zig` is a leaf module with no imports from the Miracula tree. It holds exactly
the 8 C-ABI-constrained export vars:

```zig
// src/runtime/core_state.zig
pub export var nill: Word = 0;
pub export var loading: c_int = 0;
pub export var compiling: c_int = 1;
pub export var errs: Word = 0;
pub export var errline: Word = 0;
pub export var obsuffix: [*:0]const u8 = "x";
pub export var SYNERR: Word = 0;
pub export var commandmode: Word = 0;
```

**`runtime_state.zig` becomes self-hosting.** Move `pub var rs: RuntimeState = .{}` from
`main.zig` into `runtime_state.zig`. This makes `RuntimeState` and its singleton available
without importing `main.zig`.

**Dependency changes:**
- `heap.zig`: replace `@import("../main.zig")` with
  `@import("runtime_state.zig")` (for `rs`) and `@import("core_state.zig")` (for the 8
  stuck vars). Replace all `main.rs.*` with `rt.rs.*`. Replace bare `compiling`, `nill`, etc.
  with `core.compiling`, `core.nill`, etc.
- `main.zig`: remove `pub export var` for the 8 stuck vars; re-export them from `core_state.zig`
  via `pub const nill = &core_state.nill` or simply include `core_state.zig` in the comptime
  block. Keep `pub var rs` as an alias `pub const rs = &rt.rs` for backward compat, or update
  all callers.
- `parser_api.zig`: import `core_state.zig` instead of using `extern var SYNERR` /
  `extern var commandmode`.

**Remaining `main.*` uses in `heap.zig`** (non-rs, non-stuck-var):
- `main.files`, `main.SGC`, `main.TABSTRS`, `main.ND`, `main.newtyps`, `main.speclocs`,
  `main.rv_script`, `main.algshfns` — these are `pub extern var` aliases in main.zig pointing
  to state owned by `types.zig`, `trans.zig`, etc. Convert to direct `extern var` declarations
  in `heap.zig` (they are already C-ABI-visible from their source modules).
- `main.get_id(x)` — an inline function; inline its body directly in heap.zig
  (`@ptrFromInt(@as(usize, @intCast(h(h(h(x))))))`) since heap.zig owns `h()`.
- `main.get_fil(x)` — similarly inline.
- `main.fm_time()`, `main.unlinkx()` — import `io/files.zig` directly; no circular dependency.
- `main.dump.internals` — declare `extern var internals: Word` (already exported from dump.zig).

*DoD:* `heap.zig` no longer contains `@import("../main.zig")`. Build clean, test baseline
maintained. `main.zig` shrinks by 8 `pub export var` declarations.

---

#### G2 — Reducer subsystem: direct dispatch (eliminate ~84 extern fn ↔ export fn pairs)

**Why it exists.** `reducer/reduce.zig` dispatches to 84 handler functions via `extern fn`
declarations in `c_abi.zig` (`zig_handleS`, `handle_G_ALT`, etc.) that resolve through the
linker to `export fn` in `reducer/combinators.zig`, `reducer/io.zig`, `reducer/lex.zig`, and
`reducer/ready.zig`. All four handler modules already `@import("reduce.zig")` for
`ReductionCtx` — the dependency direction already exists; the call direction just goes via
the linker instead of a direct call.

**Solution:** make `reducer/reduce.zig` import its handler modules directly.

```zig
// reducer/reduce.zig
const combinators = @import("combinators.zig");
const io_handlers = @import("io.zig");
const lex_handlers = @import("lex.zig");
const ready = @import("ready.zig");
```

Replace each `clib.zig_handleS(@ptrCast(&ctx))` call with `combinators.handleS(&ctx)` (etc.).
Remove `export` from all handler functions; make them `pub fn`. Remove the ~84 `pub extern fn`
declarations from `c_abi.zig`. Remove the `extern fn handle_ready_state` declaration from
`reducer/reduce.zig`.

`ReductionCtx` can lose `extern struct` and become a plain `pub const ReductionCtx = struct`
since it no longer crosses an ABI boundary — unless `handle_ready_state` (in `ready.zig`,
currently `export fn`) is called from C code. Verify first.

*DoD:* `c_abi.zig` loses ~84 `pub extern fn zig_handle*` / `pub extern fn handle_*` lines.
All reducer handler calls in `reduce.zig` are direct Zig calls. Build clean.

---

#### G3 — Migrate `lex.zig` state to a `LexState` struct ✅

**Why it matters.** `lex.zig` owns ~40 `export var` globals (`fileq`, `margstack`, `col`,
`gvars`, `lexvar`, `namebucket`, `dicp`, `dicq`, `common_stdin`, …). These are reached by
`heap.zig` (15 vars), `trans.zig`, `module_loader.zig`, and others via `extern var`. This is
the same pattern that was fixed for runtime state in B1 (`RuntimeState`).

**Solution:** create `src/parser/lex_state.zig` with a `LexState` struct and
`pub var ls: LexState = .{}`. Consolidate all the `export var` globals into `ls`. Update all
callers to use `lex_mod.ls.field`. The linker symbols disappear; cross-module access becomes
a typed struct field read.

This is analogous to B1 but for the parser/lexer subsystem. Approximate scope:
- ~40 fields move into `LexState`
- Call sites in `heap.zig`, `trans.zig`, `module_loader.zig`, `types.zig`, `setup.zig`, and
  the reducer modules need updating
- After G3, many of `heap.zig`'s remaining `extern var` (currently pointing at lex.zig vars)
  become `lex_mod.ls.field` reads — a direct `@import` path exists since heap.zig won't
  import main.zig after G1

*Constraint:* `lex.zig` already imports `main.zig`. After G1 moves `rs` into `runtime_state.zig`,
verify that `lex.zig`'s import of `main.zig` doesn't reintroduce a cycle.

*DoD:* `lex.zig` has zero `export var`. `LexState` has a default-value test. Build clean.

---

#### G4 — Convert heap accessor `extern fn` calls to direct imports

**Why it matters.** Functions defined in `heap.zig` as `export fn` (`make`, `gc`, `sto_char`,
`charname`, `get_dbl`, `sto_dbl`, …) are called from `lex.zig`, `codegen.zig`, `big.zig`,
`setup.zig`, and `reduce.zig` via `extern fn` declarations — either declared locally or pulled
from `c_abi.zig`. After G1 breaks the heap ↔ main cycle, these modules can import `heap.zig`
directly without creating new circular dependencies.

For each affected module:
1. Add `const heap = @import("../runtime/heap.zig")` (adjust path as needed).
2. Replace local `extern fn make(…)` / `clib.make(…)` with `heap.make(…)`.
3. Remove the now-unused `export` keyword from the heap functions (where safe — some may still
   need to be C-ABI-visible for `main_clib.zig` compatibility).

*Constraint:* Do not remove `export` from heap functions that are declared in `main_clib.zig`
as `pub extern fn` — those are called by the legacy C-ABI test harness. Audit before removing.

*DoD:* `lex.zig`, `codegen.zig`, `big.zig`, `setup.zig`, `reduce.zig` no longer have
`extern fn make` / `extern fn gc` / `extern fn sto_char` local declarations. Build clean.

---

#### Dependency order

```
G1 (break heap ↔ main cycle)
 └─► G4 (heap accessor direct imports — needs G1 so heap isn't circular)
G3 (LexState) — independent of G1/G2, but benefits from G1 being done first
G2 (reducer dispatch) — independent, can be done at any time
```

Recommended sequence: **G1 → G2 → G3 → G4**, committing after each.

---

## Phase 8: Deep Idiomatic Zig & Code Modernization (Planned)

### Objective

Building on the modular boundaries established in Phase 7, this phase eliminates the remaining C-style patterns, FFI coupling, and platform assumptions to produce a fully native, type-safe, and standard-adhering Zig codebase.

---

### Cluster H: Complete Elimination of `extern var` and `extern fn` Module Coupling

*Goal: Replace remaining linker-based symbol coupling with clean Zig import graphs and state structs.*

* **H1 — Encapsulate Compiler State (`CompilerState`)** ⬜
  Create `src/compiler/compiler_state.zig` with a `CompilerState` struct to hold compiler/typechecker globals (`FBS`, `speclocs`, `newtyps`, `algshfns`, `DETROP`, `MISSING`, `ALIASES`, `TSUPPRESSED`, `TYPERRS`, etc.), eliminating the ~60 `extern var` references between `heap.zig` and the compiler.
* **H2 — Convert Compiler/Types Chains** ⬜
  Convert remaining `export fn`/`extern fn` pairs in `types.zig` and `trans.zig` into direct `@import` function calls.
* **H3 — Unlink FFI-private Heap Accessors** ⬜
  Remove remaining `export` keywords from heap accessors that are not called by C code or the legacy C-ABI test harness.

---

### Cluster I: Native Zig Types & API Modernization

*Goal: Leverage Zig's safety features and type system at all internal API boundaries.*

* **I1 — Slices instead of Raw Pointers** ⬜
  Audit and convert C-style raw pointers (`[*]Word`, `?[*]Word`, `[*:0]u8`) at internal boundaries to native Zig slices (`[]Word`, `[]u8`, `[:0]u8`).
* **I2 — Native Integers** ⬜
  Replace platform-dependent C types (`c_int`, `c_long`, `c_uint`) with native Zig types (`i32`, `i64`, `usize`, `u32`) where FFI boundaries are not violated.
* **I3 — Optional Types** ⬜
  Replace raw sentinel value checks (e.g. `x == NIL`) at high-level boundaries with optional types (`?Word` or custom optional domain types).

---

### Cluster J: Comprehensive Error Union Propagation

*Goal: Use Zig error sets and try/catch instead of sentinel error codes.*

* **J1 — Propagation via Error Unions** ⬜
  Refactor parser and compiler helper functions (in `parser.zig`, `codegen.zig`, `types.zig`, `trans.zig`) that currently return `NIL` or check global error flags (`SYNERR`, `errs`) to return structured `MiraError` unions.
* **J2 — Standardize Panics and Assertions** ⬜
  Replace C-style exit calls (`c.exit(1)`) or assertion printfs inside runtime/heap routines with proper error returns or structured panics.

---

### Cluster K: Code Style, Formatting, and Naming Standards

*Goal: Align the code layout and names with standard Zig design guidelines.*

* **K1 — Formatting Gate** ⬜
  Format the entire codebase via `zig fmt` and verify compilation.
* **K2 — Naming Conventions** ⬜
  Standardize internal function and variable naming from `snake_case` or run-together names (e.g. `isconstrname`, `loadfile`) to standard Zig `camelCase`.
* **K3 — Documentation** ⬜
  Ensure all public structures, methods, and functions have comprehensive `///` doc comments.

---

## Remaining Patterns

These are known, bounded issues not yet addressed. Clusters H, I, J, and K target these patterns.

| Pattern | Count | Target Cluster | Notes |
|---------|-------|----------------|-------|
| `extern var` | ~60 | H1 | Compiler globals (`FBS`, `speclocs`, etc.) and some remaining `heap.zig` globals |
| `export fn` / `extern fn` pairs | ~250 | H2, H3 | Compiler/types chains and FFI-private heap accessors |
| `[*:0]` at internal boundaries | ~340 | I1 | Can be converted to native slices `[]const u8` or `[:0]const u8` |
| `c_int` / `c_long` types | ~340 | I2 | Convert to standard types like `i32`/`i64` or `usize` |
| `= undefined` initialisations | ~100 | — | Audit for zero-init opportunities |

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
| G | G1 | Break `heap.zig ↔ main.zig` circular dependency via `core_state.zig` | ✅ Complete |
| G | G2 | Reducer direct dispatch (eliminate ~84 extern fn ↔ export fn pairs) | ✅ Complete |
| G | G3 | Migrate `lex.zig` state to `LexState` struct | ✅ Complete |
| G | G4 | Convert heap accessor `extern fn` calls to direct imports | ✅ Complete |
| H | H1 | Encapsulate Compiler State (`CompilerState`) | ✅ Complete |
| H | H2 | Convert Compiler/Types Chains | ✅ Complete |
| H | H3 | Unlink FFI-private Heap Accessors | ✅ Complete |
| I | I1 | Slices instead of Raw Pointers | ⬜ Planned |
| I | I2 | Native Integers | ✅ Complete |
| I | I3 | Optional Types | ⬜ Planned |
| J | J1 | Propagation via Error Unions | ⬜ Planned |
| J | J2 | Standardize Panics and Assertions | ⬜ Planned |
| K | K1 | Formatting Gate | ✅ Complete |
| K | K2 | Naming Conventions | ⬜ Planned |
| K | K3 | Documentation | ✅ Complete |
