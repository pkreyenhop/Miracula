# Miranda Zig Refactor – Phase 7: Idiomatic Zig Modernization

## Objective

Transform Miracula from a direct C-to-Zig translation into an idiomatic, maintainable Zig
codebase while preserving identical runtime behaviour. Clusters A–G (Phase 7) and the
encapsulation/formatting work of Phase 8 (H, I2, K1, K3) are complete. The remaining work is
captured as the **Phase 9 fine-grained plan** below: small, single-commit, measurable
micro-steps whose collective Definition of Done is *"a reviewer skimming any non-FFI source
file recognises the code as idiomatic Zig."*

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

### Cluster G: Module Graph Repair ✅

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

## Phase 8: Deep Idiomatic Zig & Code Modernization

### Objective

Building on the modular boundaries established in Phase 7, this phase eliminates the remaining C-style patterns, FFI coupling, and platform assumptions to produce a fully native, type-safe, and standard-adhering Zig codebase.

---

### Cluster H: Complete Elimination of `extern var` and `extern fn` Module Coupling

*Goal: Replace remaining linker-based symbol coupling with clean Zig import graphs and state structs.*

* **H1 — Encapsulate Compiler State (`CompilerState`)** ✅ *(2026-06-21)*
  Created `src/compiler/compiler_state.zig` with a `CompilerState` struct holding ~50
  compiler/typechecker globals (`FBS`, `speclocs`, `newtyps`, `algshfns`, `DETROP`, `MISSING`,
  `ALIASES`, `TSUPPRESSED`, `TYPERRS`, `current_id`, `ND`, …). Singleton `pub var cs`; accessed
  via `main.cs` (`*CompilerState`). Replaced the `export var`/`extern var` web between
  `heap.zig`, `types.zig`, and `trans.zig`.
* **H2 — Convert Compiler/Types Chains** ✅ *(2026-06-21)*
  `type_of`, `checktypes` (`types.zig`) and `codegen` (`trans.zig`) converted from
  `clib.*` linker calls to direct `@import` aliases re-exported through `main.zig`.
  Removed the three `pub extern fn` declarations from `c_abi.zig`.
* **H3 — Unlink FFI-private Heap Accessors** ✅ *(2026-06-21)*
  Stripped `export` from 20 `heap.zig` functions never referenced via `extern fn`
  (`bases`, `bindparams`, `dgrow`, `dsetup`, `dump_defs`, `dump_ob`, `getdbl`, `getint`,
  `getword`, `hdsort`, `load_defs`, `mkrel`, `out1`, `outr`, `putdbl`, `putint`, `putword`,
  `unload`, `unscramble`, `unsetids`). C-ABI-reachable accessors kept `export`.

---

### Cluster I: Native Zig Types & API Modernization

*Goal: Leverage Zig's safety features and type system at all internal API boundaries.*

* **I1 — Slices instead of Raw Pointers** ⬜ *(broken into Cluster M below)*
* **I2 — Native Integers (struct fields)** ✅ *(2026-06-21)*
  Converted the non-FFI `c_int` fields in `RuntimeState` (`UTF8`, `UTF8OUT`, `atobject`,
  `atgc`, `atcount`, `debug`, `ideep`, `sigflag`, `sorted`) and `CompilerState`
  (`lfrule`, `polyshowerror`) to native `i32`. Internal *local/var* `c_int` leftovers are
  finished in Cluster L below.
* **I3 — Optional Types** ⬜ *(broken into Cluster N below)*

---

### Cluster K: Code Style, Formatting, and Naming Standards

* **K1 — Formatting Gate** ✅ *(2026-06-21)* — `zig fmt src/` applied; build verified.
* **K2 — Naming Conventions** ⬜ *(broken into Cluster P below)*
* **K3 — Documentation** ✅ *(2026-06-21)*
  `///` doc comments added to `CompilerState` and `core_state.zig` (the structs introduced
  in Phase 8). Earlier `pub` API docs were completed in D3.

---

## Phase 9: Idiomatic Zig Finishing — Fine-Grained Plan

This phase replaces the coarse I1/I3/J/K2 bullets with small, single-commit micro-steps.
Each micro-step touches **one pattern in one (or a few) files**, makes **no behavioural
change**, and is *Done* only when `zig build` is clean and all **31 unit tests** pass.

### FFI exemption (applies to every metric below)

These boundaries legitimately use C types/pointers/`snake_case` and are **out of scope**:
`src/runtime/main_clib.zig`, `src/runtime/c_abi.zig`, any `extern fn`/`extern var`
declaration, any `export fn` or `callconv(.c)` function signature (the C runtime and the
legacy test harness call these by name and ABI), and `src/tools/*` standalone utilities.

### Definition of Done — measurable scorecard

The metrics are codified in **`scripts/idiomatic-check.sh`** (step L0). Run it for the live
count; run `-v` to list the matching source lines. FFI shims (`main_clib.zig`, `c_abi.zig`),
`src/tools/*`, and genuine `extern`/`export fn`/`callconv(.c)` signature lines are excluded.

Baseline captured 2026-06-21 (script output at L0):

| # | Metric (non-FFI scope) | Now | Target | Driven by |
|---|------------------------|-----|--------|-----------|
| 1 | internal `c_int`/`c_long`/`c_uint` (incl. `@as(c_int,…)` printf casts) | 107→95→107* | FFI-bound residual (getc/fork/wait/errno/printf casts) | L1–L3 ✅ |
| 2 | `[*:0]` on Zig-only signatures | 161→176* | enumerated (inherent C-string flow) | M (analysed: no-op) |
| 3 | `[*]Word` / `?[*]Word` non-FFI | 9 | enumerated (raw heap/stack storage) | M (analysed: no-op) |
| 4 | sentinel `== NIL` / `!= NIL` | 347 | n/a — NIL is a heap value, not absence | N (analysed: no-op) |
| 5 | `return NIL` as an error signal | 12 | n/a — all return NIL-the-value | O1 (analysed: no-op) |
| 6 | bare `clib.exit(1)` (use `fatal()`) | 46 → 30 | evaluator-abort residual | O2 |
| 7 | file-private `fn` with `snake_case` | 50 → 36 | domain-vocabulary exemptions only | P1 ✅ |
| 8 | `= undefined` initialisers (non-FFI) | 92 → 86 | audited (FFI/scratch-buffer pattern) | Q1 |
| 9 | **`export fn` (C-ABI linker symbols)** — headline | **284 → 174** | FFI-only | Q2 ✅ |

\* **Metric 1 & 2 Q2 artifact.** L1–L3 genuinely cut internal `c_int` to 95, but Q2
reclassified ~110 functions from `export fn` (excluded by the scorecard's FFI filter) to
`pub fn` (counted). Those functions legitimately take C-string (`[*:0]`) and `c_int` params at
the C-heap interface — the documented metric 2 / FFI-bound-`c_int` exemptions — so the raw
counts rose even though no non-idiomatic code was added. The durable win is **metric 9**:
`export fn` (the actual C-ABI smell) fell 284 → 174.

**Domain-vocabulary exemption (metric 7).** Like the FFI exemption, a fixed set of
file-private names deliberately mirrors the public `heap.zig` accessor API and the Miranda
type-node vocabulary, so they stay `snake_case` for cross-reference with the original source
and with their `pub` counterparts: the accessor mirrors (`get_id`, `get_fil`, `get_pn`,
`pn_val`, `id_who`, `the_val`, `*_ptr`, `make_fil*`), the type predicates/constructors
(`isarrow_t`, `iscomma_t`, `islist_t`, `isvar_t`, `iscompound_t`, `t_class`, `t_info`,
`t_arity`, `t_showfn`, `bound_t`, `pair_t`), and the latin idiom `sui_generis`. P1 renames
only the genuine verb-helpers outside this set.

---

### Cluster L — Finish Native Integers (closes metric 1)

* **L0 — Add `scripts/idiomatic-check.sh`** ✅ *(2026-06-21)*
  Shell script emitting the 8-metric scorecard (with the FFI exemption baked in) and a `-v`
  mode listing matching lines. Establishes the measurable baseline (107/161/9/347/12/46/50/92)
  and makes every later micro-step self-verifying. *Risk: none (tooling only).*
* **L1 — `lex.zig` internal `c_int` → `i32`** ✅ *(2026-06-21)*
  `rawch`, `errch` → `i32`; `inprelude` → `bool` (it was a 0/1 flag — more idiomatic than a
  native int). Left as `c_int`: `anti` and `h_val`, which are the direct return values of the
  C-ABI `export fn charclass()` / `hash()` (FFI-adjacent). lex.zig `c_int` count 25 → 22.
* **L2 — `heap.zig` internal `c_int` → `i32`/`usize`** ✅ *(2026-06-21)*
  Converted the dump-serialization pair `putint`/`getint` (param, return, local `r`, and
  `@sizeOf`) from `c_int` to `i32`. `@sizeOf(i32)` == `@sizeOf(c_int)` == 4 bytes on all
  targets, so existing `.x` dumps stay compatible and the on-disk field width is now
  platform-independent by construction; callers widen the `i32` result into `Word` arithmetic
  identically. heap.zig `c_int` 16 → 11. Kept (legitimately C-bound): `extern fn` decls, the
  `export fn` returns (`is_char`, `okdump`, `src_update`, `utf8test`), the `collecting`
  `export var`, the `constructor()` type-switch case, and the `c.getc`-result sign-extension.
* **L3 — Driver/runtime internal `c_int` → `i32`/`bool`** ✅ *(2026-06-21)*
  Converted the genuinely-internal locals: `reduce.zig` `lexfail` counter `i` → `i32`;
  `commands.zig` `presym_n` manual-section table → `[_]i32`; and three 0/1 flags to idiomatic
  `bool` (`startup.zig` `badlib`, `commands.zig` `leftist`/`tdone`). Metric 1: 105 → 95.
  **Left as `c_int` (FFI-bound):** `getc`/`fork`/`wait`-result locals (`ch`, `pid`, `status`),
  `errno`/`stat`/`pipe-fd` in `platform.zig` and `ready.zig`, `argc` arithmetic and
  `@as(c_int, …)` printf casts, `ready.zig` `base` (→ `clib.strtobig`), `startup.zig` `vstack`
  (→ `strvers`), and the `reduce_action` `enum(c_int)` (an `export fn` return type).
  *DoD note: metric 1's residual is exactly this FFI-bound set, not "0".*

### Cluster M — Slices at Internal Boundaries (was I1)

**Finding (2026-06-21): this codebase has no net-positive slice conversions.** Auditing every
non-FFI `[*:0]`/`[*]Word` site showed the pointer/string surface is *inherent* to the C-heap
interpreter design, not an artefact of the C-to-Zig translation. Forcing slices would add
`.ptr` / `std.mem.span()` round-trips at every boundary **without** shrinking the surface — the
opposite of the DoD. M1–M3 are therefore recorded as analysed-no-op; **M4 (documentation) is
the deliverable.**

* **M1 — `startup.zig` string params** ✅ *(analysed — no-op, 2026-06-21)*
  Every `[*:0]` function in `startup.zig` (`main_entry`, `rc_read`, `checkversion`, `strvers`)
  is `export fn` — C-ABI, must keep many-pointers. No Zig-only candidates.
* **M2 — `commands.zig` + `module_loader.zig` string params** ✅ *(analysed — no-op, 2026-06-21)*
  The only non-`export` `[*:0]` signature is `loadfile(t_val)`, which sits mid-stream in an
  all-C-string data flow (`argv` → `rs.current_script` (`?[*:0]u8`) → `fileExists`/`openfile`/
  `make_fil`/`printf`). Converting it alone would add `std.mem.span` at ~11 callers plus `.ptr`
  at ~6 internal C-string sinks — net pointer-juggling increase. Left as `[*:0]`.
* **M3 — `[*]Word` scratch buffers** ✅ *(analysed — no-op, 2026-06-21)*
  All 9 non-FFI `[*]Word`/`?[*]Word` are raw heap/stack **storage**: `hd`/`tl`/`dstack`/`stackp`
  (`export var`), `heap`/`dlim`/`cstack`/`pnvec` (grown/indexed by pointer arithmetic), and the
  `bases()` local `p` (walks the machine C-stack via `@intFromPtr` for GC root scanning).
  None has a statically-known slice length; all are pointer-appropriate.
* **M4 — Document the enumerated pointer exception** ✅ *(2026-06-21)*
  Recorded below as an accepted exception (analogous to the FFI and domain-vocabulary
  exemptions). Metric 2/3 targets are "enumerated exceptions only", and these *are* the
  enumeration.

**Enumerated raw-pointer exception (metrics 2–3).** Idiomatic Zig keeps a raw pointer at
genuine C-FFI and raw-memory boundaries; it does not wrap every C pointer in a slice. The
accepted non-FFI pointers are:
- **C-string flow (`[*:0]`):** Miranda identifiers, filenames, and dictionary strings are
  null-terminated C strings end-to-end (heap `id`/`fil` nodes store `[*:0]`, the lexer and
  `clib` string routines consume `[*:0]`). `loadfile` and friends stay `[*:0]const u8`.
- **Heap/stack storage (`[*]Word`):** `hd`/`tl` (cell store), `dstack`/`stackp`/`dlim` (data
  stack), `heap` (base), `cstack` (combinator stack), `pnvec` (pattern-node vector) — grown
  via `realloc` and addressed by pointer arithmetic behind the `h()`/`t()` accessor API.
- **Stack-walking:** the `bases()` GC root scanner walks raw machine-stack addresses.

### Cluster N — Optional Types (was I3)

**Finding (2026-06-21): `NIL` is a first-class heap value, not an absent/null sentinel — so
optionals do not apply.** `NIL` is the nil atom (`CMBASE+138`), the Miranda empty list and the
graph terminator that the reducer evaluates directly. The 347 `== NIL`/`!= NIL` checks are
structural *value* comparisons ("is this list empty / this graph a leaf"), not "lookup
returned not-found". Wrapping them in `?Word` would be semantically wrong and would force
constant `orelse NIL` round-trips back into the Word domain. N1–N2 are analysed-no-ops.

* **N1 — `get_id` → `?[*:0]const u8`** ✅ *(analysed — no-op, 2026-06-21)*
  `get_fil` is already optional (its share-field can be 0). `get_id` returns an identifier's
  name pointer, which is **never** absent for a valid id — an optional would never be null.
* **N2 — Lookup fns `NIL`-for-absent → `?Word`** ✅ *(analysed — no-op, 2026-06-21)*
  The "not-found → NIL" lookups (`findid` and peers) are `export fn` declared `extern fn` in
  4 places — C-ABI symbols whose `Word` return cannot become `?Word`. The rest return NIL as a
  legitimate empty-list value.

### Cluster O — Error Unions & Panics (was J1/J2; closes metrics 5–6)

* **O1 — `return NIL`-as-error → `MiraError`** ✅ *(analysed — no-op, 2026-06-21)*
  All 12 `return NIL` sites return NIL as a legitimate **empty-list value**, not an error
  signal: 11 are in `export fn` translator/heap functions (`alfasort`, `codegen`, `get_ids`,
  `mktuple`, `abstract`, `scanpattern`, `block`, `conv_args`) where NIL is the correct result
  and the C-ABI return cannot be an error union anyway. The one non-`export` site, `mkincludes`,
  already signals errors through the `SYNERR` global and returns NIL as its (empty) include
  list; its single caller appends that list to `main.files`, so an error union would just
  become `catch NIL` — pure churn. The real error channels here are `SYNERR`/`errs` (sentinel
  globals consumed widely) and, for type-checking, the `MiraError.TypeCheckAbort` union already
  wired in E2.
* **O2 — Centralise fatal exits behind `fatal()`** ✅ *(2026-06-21)*
  Added `errors.fatal(fmt, args) noreturn` (re-exported as `main.fatal`) — one place that does
  `fprintf(stderr, …)` then `exit(1)`, so the diagnostic and exit status can never drift apart.
  Converted the **17 clean `fprintf(stderr,…)+exit(1)` pairs** in `startup.zig` (7, incl.
  `missparam` → `noreturn`), `repl.zig` (1), `files.zig` (1), `module_loader.zig` (5),
  `lex.zig` (2), `dump.zig` (1). Metric 6: 46 → 30.
  **Residual (documented, out of O2 scope):** the evaluator's `outstats()+exit(1)` aborts in
  `reduce.zig`/`ready.zig`/`reducer/*` (a distinct "dump stats then die" category — future
  `evalAbort()` helper), multi-step shutdowns that run cleanup between print and exit
  (`startup.zig` `libfails`, `repl.zig` `$+`), the FPE message that prints to **stdout**
  (stream-preserving), and the single canonical `exit(1)` *inside* `fatal()` itself.
* **O3 — `unreachable` audit (18 sites)** ✅ *(2026-06-21)*
  Added `heap.mallocPanic(what) noreturn` (wraps the C-ABI `void` `mallocfail`, which exits).
  Routed the **12 load-bearing `alloc(...) orelse { mallocfail(); unreachable; }`** blocks
  (6 in `heap.zig`, 6 in `lex.zig`) through it — each is now an idiomatic
  `orelse mallocPanic("what")` one-liner and the single justified `unreachable` lives only in
  `mallocPanic`. Fixed a latent bug at `ready.zig:149` (`malloc(...) orelse unreachable` — a
  real allocation failure would have hit UB) to use `mallocPanic`. The 4 `bufPrint(...) catch
  unreachable` format-asserts (fixed-size buffers) are kept with a one-line size-invariant
  justification each. (`trans.zig:1194` was a string-literal false positive.)

### Cluster P — Naming Conventions (was K2; closes metric 7)

Staged file-private-first so each commit has zero cross-module impact. **Exempt:** `export fn`,
`callconv(.c)`, any `pub fn` referenced as an extern symbol, and the metric-7
domain-vocabulary set (accessor mirrors + `_t` type predicates/constructors + `sui_generis`).
Rename only genuine Zig-internal verb-helpers and their (same-file) callers.

* **P1a — Private `fn` in `runtime/` → camelCase** ✅ *(2026-06-21)*
  `big_plus`→`bigPlus`, `big_sub`→`bigSub`, `stackp_push/pop/top/set_top`→`stackpPush/Pop/Top/SetTop`.
  Kept the accessor mirrors (`get_id`, `get_fil`, `get_pn`, `pn_val`, `*_ptr`). 14 → 8.
* **P1b — Private `fn` in `compiler/` → camelCase** ✅ *(2026-06-21)*
  `meta_tcheck`→`metaTcheck`, `comp_deps`→`compDeps`, `abstr_check`→`abstrCheck`,
  `abstr_mcheck`→`abstrMcheck`, `infer_type`→`inferType`, `reset_SUBST`→`resetSubst`.
  Kept the `t_*`/`is*_t`/`*_t` type vocabulary and accessor mirrors; `clear_SUBST` stays
  (it is an `export fn`). 31 → 25.
* **P1c — Private `fn` in `parser/` → camelCase** ✅ *(2026-06-21)*
  `make_fil_record`→`makeFilRecord` (test helper). The other three (`make_fil`, `get_id`,
  `get_fil` in `lex.zig`) are accessor-mirror exemptions. 4 → 3.
* **P1d — Private `fn` in `driver/` + `io/` → camelCase** ✅ *(2026-06-21)*
  `unlimit_stack`→`unlimitStack`. io/ had none. driver/+io → 0.
* **P2 — Non-FFI `pub fn` → camelCase** ✅ *(2026-06-21)*
  After Q2 surfaced ~135 snake_case `pub fn`, audit showed most are deliberate
  **domain vocabulary** — the combinator names (`handleS`, `handleB_p` for B′, `handleITERATE`),
  the grammar handlers mirroring `clib.G_*` constants (`handle_G_ALT`, …), the heap accessor
  mirrors (`t_class`, `id_who`, `fil_time`), and the `type_error1..8` family — all of which a
  reader cross-references against the Miranda C source and the SK-combinator set; renaming them
  would *obscure* that correspondence. The one genuine wart was the **`zig_` prefix** on the 47
  combinator handlers (added during the G2 hybrid period to avoid clashing with the then-extant
  C `handleS`). Stripped it across defs + callers in `reducer/combinators.zig`, `reduce.zig`,
  `ready.zig` (`zig_handleS` → `handleS`, …), restoring the Miranda-source names. pub-fn
  snake_case **135 → 96**; the 96 residual are exactly the documented domain-vocabulary set.
  Build clean; tests green.

*P outcome:* file-private `snake_case` fns **50 → 36** (P1); pub `snake_case` **135 → 96** (P2).
Both residuals are exactly the documented accessor-mirror / `_t`-type / combinator /
grammar-constant vocabulary that mirrors the original source — not arbitrary snake_case.

### Cluster Q — Polish (closes metric 8)

* **Q1 — `= undefined` audit** ✅ *(2026-06-21)*
  Audited all 92 non-FFI sites. The large majority are the **idiomatic FFI/scratch-output
  pattern** — C structs filled by syscalls (`Stat`, `winsize`, `tms`, `rlimit`, `Sigaction`)
  and `[N]u8` buffers filled by `sprintf`/`strcpy` before any read — where `undefined` is the
  correct, standard-Zig choice. **Change:** zero-initialised the 6 `RuntimeState` char-buffer
  **struct fields** (`PRELUDE`, `STDENV`, `linebuf`, `ebuf`, `home_rc`, `lib_rc`) via
  `std.mem.zeroes(...)` so a `.{}` singleton has no `undefined` fields and reads as the empty
  string before startup fills them — negligible cost (singleton), removes read-before-write UB
  risk. Metric 8: 92 → 86. Retained `undefined` are the documented FFI/scratch-buffer pattern
  plus the `lex_state` pointer fields (`dicp`/`dicq`/`ARGV`, set at setup, used non-optional).
* **Q2 — `export fn` → `pub fn`** ✅ *(2026-06-21)*
  Candidate set = `export fn` names minus those referenced via `extern fn` / `clib.`·`c.` /
  `callconv(.c)` / **address-taken `&fn`** (the last excludes signal-handler & dispatch-table
  callbacks the build can't catch). Converted **110 functions** across 9 files: `commands.zig`
  (7, earlier) then `types.zig`, `trans.zig`, `lex.zig`, `startup.zig`, `reduce.zig`,
  `files.zig`, `heap.zig`, `repl.zig`. Non-shim `export fn` **284 → 174**.
  **One refinement the build caught:** `ult`/`lmap`/`mapup`/`mapdown` are passed *by bare name*
  to `walktype(_, f: *const fn(Word) callconv(.c) Word)`, so they need C calling convention —
  reverted those 4 to `export fn`. (A calling-convention mismatch is a compile error, so the
  build is a complete detector for the fn-pointer case.) The residual 174 `export fn` are all
  genuinely C-ABI-bound: `extern fn`-declared, `clib.`-called, `callconv(.c)`, address-taken
  callbacks, or C-fn-pointer arguments. Build clean; full test suite (incl. integration runs of
  real `.m` programs) green.

### Sequencing

```
L0 (scorecard tooling)
 ├─► L1, L2, L3   (native ints — independent, lowest risk)
 ├─► O2, O3       (fatal/unreachable — independent, low risk)
 └─► P1a–P1d      (file-local renames — independent, low risk)
M1 → M2 → M3 → M4 (slices — medium risk, ordered)
N1 → N2           (optionals — medium risk)
O1                (error unions — medium risk)
P2, Q1, Q2        (cross-module — do after the file-local passes land)
```

Recommended start: **L0 → L1 → O2 → P1a** — all low-risk, each independently verifiable,
together they move four of the eight scorecard metrics.

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
| I | I2 | Native Integers (struct fields) | ✅ Complete |
| K | K1 | Formatting Gate | ✅ Complete |
| K | K3 | Documentation | ✅ Complete |

### Phase 9 — Fine-Grained (single-commit micro-steps)

| Cluster | Step | Title | Metric | Risk | Status |
|---------|------|-------|--------|------|--------|
| L | L0 | Add `scripts/idiomatic-check.sh` scorecard | tooling | none | ✅ Complete |
| L | L1 | `lex.zig` internal `c_int` → `i32` | 1 | low | ✅ Complete |
| L | L2 | `heap.zig` internal `c_int` → `i32` (putint/getint; 16→11) | 1 | low | ✅ Complete |
| L | L3 | Driver/runtime internal `c_int` → `i32`/`bool` (105→95) | 1 | low | ✅ Complete |
| M | M1 | `startup.zig` string params (all `export` — none convertible) | 2 | low-med | ✅ Analysed (no-op) |
| M | M2 | `loadfile` string param (net-negative — keep `[*:0]`) | 2 | low-med | ✅ Analysed (no-op) |
| M | M3 | `[*]Word` (all raw storage / stack-walk — keep `[*]`) | 3 | medium | ✅ Analysed (no-op) |
| M | M4 | Document enumerated raw-pointer exception | 3 | none | ✅ Complete |
| N | N1 | `get_id` optional (never absent — keep) | 4 | medium | ✅ Analysed (no-op) |
| N | N2 | Lookup fns `NIL`-absent (all `export fn` — keep) | 4 | medium | ✅ Analysed (no-op) |
| O | O1 | `return NIL` (all return NIL-the-value — keep) | 5 | medium | ✅ Analysed (no-op) |
| O | O2 | Centralise fatal exits behind `fatal()` | 6 | low | ✅ Complete |
| O | O3 | `unreachable` audit (18 sites) | — | low | ✅ Complete |
| P | P1a | Private `fn` in `runtime/` → camelCase (6 renamed, 14→8) | 7 | low | ✅ Complete |
| P | P1b | Private `fn` in `compiler/` → camelCase (6 renamed, 31→25) | 7 | low | ✅ Complete |
| P | P1c | Private `fn` in `parser/` → camelCase (1 renamed, 4→3) | 7 | low | ✅ Complete |
| P | P1d | Private `fn` in `driver/`+`io/` → camelCase (1 renamed) | 7 | low | ✅ Complete |
| P | P2 | Non-FFI `pub fn`: strip `zig_` wart (135→96) | 7 | medium | ✅ Complete |
| Q | Q1 | `= undefined` audit (92→86; 6 fields zero-init) | 8 | low-med | ✅ Complete |
| Q | Q2 | `export fn` → `pub fn` (110 converted; 284→174) | — | medium | ✅ Complete |
