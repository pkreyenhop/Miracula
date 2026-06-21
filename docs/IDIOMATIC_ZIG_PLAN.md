# Miranda Zig Refactor – Phase 7: Idiomatic Zig Modernization

## Objective
Transform the Miracula codebase from a successful C-to-Zig translation into an idiomatic, maintainable Zig codebase while preserving identical behavior.

---

## Key Findings

**Finding 1: The `export var`/`extern var` pattern is the real architectural problem.**
Almost all `pub extern fn` declarations in `main_clib.zig` (52 of 55) are already implemented in Zig via `export fn`. The only true C dependencies are `setjmp`, `longjmp`, and `siglongjmp` — all three are standard libc calls that will never move. The `export var`/`extern var` pattern throughout the codebase is not C interop. It is Zig using the linker symbol table as a module system: `repl.zig` has 57 `extern var` declarations to reach state that lives in `main.zig`. This is the root cause of the tight coupling the original plan was trying to fix, but it isn't named anywhere in the original plan.

**Finding 2: The remaining work in `main.zig` is much larger than the completed work.**
Two major extraction targets remain untouched: the `command()` dispatch block (~383 lines) and the `loadfile`/`undump`/`makedump`/compiler-setup block (~1200 lines). Together they represent ~55% of the file. Extracting them using the current `export var` pattern would just move the problem without fixing it.

**Finding 3: The original step ordering has unacknowledged dependencies.**
- Step 2 (RuntimeState) requires stable module boundaries from Step 1 to know what each module owns.
- Step 5 (booleans) requires Step 2 (RuntimeState) so flags are no longer exported via the linker.
- Step 8 (accessor methods) requires Step 6 (domain types) to have receiver types.
- Steps 9 and 10 (docs, tests) should be woven into each step, not deferred.

**Finding 4: Steps 6, 7, 8 have lower ROI than the architectural steps.**
Introducing domain-type wrappers (`FileNode`, `NodeRef`, etc.) and converting string pointers to slices touch every call site in the codebase. These are worth doing, but scoped conservatively and deferred until the architecture is stable.

---

## Execution Plan

Work is organized into four clusters based on dependency. Each cluster is a prerequisite for the next. Embedded tests are a hard requirement for the Definition of Done (DoD) in Clusters A and B.

### Cluster A: Architecture & Module Boundaries (Blocker for all work)
*Goal: Eliminate the linker-as-module-system anti-pattern and reduce `main.zig` to a composition root.*

* **A1: Replace `extern var` in `repl.zig`**
    * *Status:* **Complete**
    * *Details:* Replaced 57 `extern var` declarations with `@import("main.zig")`.
* **A2: Extract `commands.zig`**
    * *Status:* **Complete**
    * *Details:* Extracted `command()` dispatcher and helpers. `main.zig` reduced to ~2200 lines.
* **A3: Extract Compiler Initialization (`src/compiler/setup.zig`)**
    * *Status:* **Complete**
    * *Details:* Extract `mira_setup`, `primdef`, `predef`, `primlib`, `privlib`, and `stdlib`.
    * *DoD:* `main()` successfully calls the extracted setup without linker errors. Includes at least one `test` block.
* **A4: Extract Source Loader (`src/compiler/module_loader.zig`)**
    * *Status:* **Complete**
    * *Details:* Extract `loadfile`, `mkincludes`, and path tracking.
    * *DoD:* Can successfully load and parse a basic `.m` script. Includes at least one `test` block for file resolution.
* **A5: Extract State Dumping (`src/compiler/dump.zig`)**
    * *Status:* **Complete (2026-06-20)**
    * *Details:* Extracted `undump`, `makedump`, `fixexports`, `unfixexports`, `readoption`, `sigdefer` into `dump.zig`. Also extracted filesystem helpers (`fm_time`, `normal`, `filecopy`, etc.) into `src/io/files.zig`. Fixed 9 build errors from the agent: `syntax()`/`acterror()`/`yysterm` restored to `setup.zig`; all `export fn` in `commands.zig` made `pub`; `isconstructor`/`isvariable` corrected to use `isconstrname()`.
    * *Note:* `main.zig` is now 338 lines — not yet under 200. Remaining content is global state declarations (needed for C ABI export) and `pub const` aliases for the extracted modules. The <200 goal requires B1 (RuntimeState consolidation).

### Cluster B: State Encapsulation (Depends on Cluster A)
*Goal: Eliminate implicit global state via dependency injection.*

* **B1: Introduce `RuntimeState` Struct**
    * *Status:* **Complete**
    * *Details:* `src/runtime/runtime_state.zig` created. ~75 moved vars consolidated into `RuntimeState` struct; singleton `pub var rs: RuntimeState = .{}` in `main.zig`. All callers converted from `extern var` / `main.foo` to `main.rs.foo`. 8 "stuck" vars remain as `pub export var` in `main.zig` (nill, loading, compiling, errs, errline, obsuffix, SYNERR, commandmode) because parser_api.zig cannot safely re-import main. `strictif` converted from `Word` to `bool`. Build clean, pre-existing test baseline maintained.
* **B2: Encapsulate Heap Access (`src/runtime/heap.zig`)**
    * *Status:* **Complete**
    * *Details:* Removed `pub const h/t/hp/tp` aliases from `main.zig`. All callers now use `main.heap.h(...)` etc. directly. Build clean.

### Cluster C: Type Safety & Domain Modeling (Depends on Cluster B)
*Goal: Leverage Zig's type system at the newly established API boundaries.*

* **C1: `NodeTag` Enum**
    * *Status:* **Complete**
    * *Details:* Added `pub const NodeTag = enum(u8) { ATOM=0, ..., TCONS=22, _ }` to `c_abi.zig`. Non-exhaustive (`_`) because GC marking temporarily negates tag bytes (sign-bit trick), producing values outside the defined range. Integer aliases kept for backward compatibility with `make(t: u8, ...)` calls. `pub fn getTag(x: Word) c.NodeTag` added to `heap.zig` as the typed read boundary (`@enumFromInt(tag[x])`). Internal heap code and all callers unchanged — they continue to use raw `tag[x] == CONS` comparisons (comptime-int coercion applies). Build clean, test baseline maintained.
* **C2: API Boundary Domain Types**
    * *Status:* **Complete (2026-06-21)**
    * *Details:* Added `FileNode`, `Identifier`, `TypeRef`, and `NodeRef` as `pub const` structs in `heap.zig`, each wrapping a single `.word: Word` field. Re-exported from `main.zig`. Existing procedural accessor functions (`fil_time`, `id_type`, etc.) are unchanged — the types wrap them via methods (see D2). Internal heap.zig implementation code and all existing call sites are unmodified, following the C1 precedent of adding a typed boundary without breaking the existing API.
    * *Constraint:* Apply *only* to `RuntimeState` fields and `pub` function signatures in `heap.zig`. Do not attempt to convert internal implementation code.

### Cluster D: Ergonomics (Can be done incrementally)
*Goal: Modernize internal syntax and improve codebase discoverability.*

* **D1: Internal String Slices**
    * *Status:* **Complete (2026-06-21)**
    * *Details:* Converted `is()`, `filequote()` (commands.zig) and `missparam()` (startup.zig) from `[*:0]const u8` to `[:0]const u8`. Call sites updated (`std.mem.span()` at the two points where C-originated pointers enter). Remaining `pub export fn` parameters kept as `[*:0]const u8` (FFI boundary). Functions whose callers are predominantly C-originated strings (`fileExists`, `inodev`) left unconverted — the conversion would add noise at every call site without reducing total `std.mem.span` count.
* **D2: Domain Methods**
    * *Status:* **Complete (2026-06-21)**
    * *Details:* Methods added to all four domain types in `heap.zig`:
      - `FileNode`: `.time()`, `.share()`, `.defs()`, `.inodev()`, `.sameAs(other)`
      - `Identifier`: `.typ()`, `.val()`, `.who()`, `.isConstructor()`, `.isVariable()`, `.isFreeId()`, `.addToEnv()`
      - `TypeRef`: `.class()`, `.info()`
      - `NodeRef`: (wrapper only; specialized types preferred)
      Each method delegates to the existing procedural accessor. New code can use `id.typ()` style; existing call sites are unmodified.
* **D3: Documentation**
    * *Status:* **Complete (2026-06-21)**
    * *Details:* Added `///` doc comments to all `pub` declarations in `src/io/files.zig`, `src/runtime/runtime_state.zig` (struct + key fields), `src/compiler/setup.zig` (primdef/predef/primlib/privlib/stdlib/mira_setup), `src/compiler/dump.zig` (internals/tlost/fixexports/unfixexports/fixtype/undump/makedump/sigdefer/readoption), and `src/compiler/module_loader.zig` (loadfile/mkincludes). Comments focus on invariants, ownership, and non-obvious contracts.


### Cluster E: Control Flow & Error Handling (Deferred)
*Goal: Eliminate C standard library dependencies (`setjmp`, `longjmp`, `siglongjmp`) by replacing non-local control flow with Zig's native error unions.*

* **E1: Define Domain Errors**
    * *Status:* **Complete (2026-06-21)**
    * *Details:* Created `src/runtime/errors.zig` with `pub const MiraError = error{ SyntaxError, TypeCheckAbort, HeapExhausted, LoadError, EvaluationInterrupted }`. Each variant documents its invariants and the signal-handler constraint. Re-exported as `pub const MiraError` from `main.zig`; module included in the `comptime` block.
* **E2: Error Union Signatures & Bubbling**
    * *Status:* **Complete (2026-06-21)**
    * *Details:* Two setjmp/longjmp sites converted:
      1. `gc()` in `heap.zig`: The `setjmp`/`longjmp` pair was a self-contained "local return" within the same stack frame — removed both, gc() now returns normally. The jmp_buf import is no longer referenced in heap.zig.
      2. `types.zig` type-checker abort path: Removed `export var env1`, `export fn types_abort()`, and the `setjmp` wrapper in `checktypes()`. Converted `meta_tcheck`, `etype`, `conforms`, `comp_deps`, `abstr_check`, `abstr_mcheck`, `mcheckfbs` to `!Word`/`!void` return types. Error propagates via `try`; callers that cannot propagate use `catch return` / `catch {}`. `export fn checktypes() void` catches with a labeled `outer:` block.
      Signal-handler paths (`sigsetjmp`/`siglongjmp` on `rs.env` for SIGINT/SIGFPE) are unchanged — POSIX signal handlers are asynchronous and cannot propagate Zig errors.
* **E3: Top-Level Error Handling — Signal-Handler Constraint Documentation**
    * *Status:* **Complete (2026-06-21)**
    * *Details:* The `commandloop` recovery point (`sigsetjmp(&rs.env, 1)`) and signal handlers (`reset`, `fpe_error`) in `repl.zig` CANNOT be converted to Zig error unions. POSIX signal handlers are asynchronous — the handler fires on any call stack, making stack-unwinding error propagation impossible. The `sigjmp_buf rs.env` field in `RuntimeState` MUST remain. This constraint is documented in `errors.zig` (preamble), in the `rs.env` field doc comment in `runtime_state.zig`, and in this plan. No code change is possible or appropriate for this site. All actionable setjmp/longjmp sites have been addressed in E2.

### Cluster F: Linker-Symbol Elimination & Code Health (Depends on Cluster E)
*Goal: Finish removing the linker-as-module-system anti-pattern from the compiler modules, clean up stale artifacts, expand test coverage, and audit remaining Word-typed boolean fields.*

* **F1: Eliminate `extern var` from `types.zig`**
    * *Status:* **Complete (2026-06-21)**
    * *Details:* `types.zig` already `const main = @import("../main.zig")` but still has 10 `extern var` declarations for symbols that are all `pub` in `main.zig` (`hd`, `tl`, `tag`, `errs`, `errline`, `nill`, `compiling`, `commandmode`, `files`, `SYNERR`). Replace every `extern var` with a reference via `main.*`. This eliminates the last linker-symbol reads in the type checker and makes all state access explicit.
    * *Scope:* types.zig only. Do not touch trans.zig, lex.zig, or heap.zig in this step.

* **F2: Selective `extern var` → `@import` in `trans.zig` and `module_loader.zig`**
    * *Status:* **Complete (2026-06-21)**
    * *Actual outcome:* Converted 10/14 extern vars in trans.zig and 12/19 in module_loader.zig. Remaining non-convertible vars: trans.zig keeps `idsused` (parser/lex.zig), `cook_stdin`/`common_stdin`/`common_stdinb` (C-side); module_loader.zig keeps `fileq` (lex.zig), `c`/`col` (C-side), `ALIASES`/`TSUPPRESSED`/`DETROP`/`MISSING` (not pub in main).
    * *Details:* Both files already import `main`. A subset of their `extern var` declarations refer to `pub` symbols in `main.zig`. Convert only those; leave vars that live in `lex.zig` or other modules without a circular-safe import path. Expected wins: `errs`, `nill`, `compiling`, `commandmode`, `SYNERR`, `files`, `current_file`, `ND`, `hd`, `tl`, `tag` in trans.zig; `current_file`, `ND`, `exportfiles`, `stackp`, `dstack`, `lfrule`, `polyshowerror`, `FBS`, `tag`, `hd`, `tl` in module_loader.zig (those that are `pub` in main).
    * *Constraint:* Do not add new `@import` edges that would create circular dependencies.

* **F3: Stale Artifact Cleanup**
    * *Status:* Not started
    * *Details:* Remove stale code left by completed refactors:
      1. `heap.zig` line 9: `const c_jmp = c;` — this alias was used only by the `gc()` setjmp/longjmp removed in E2. Delete the alias and any remaining dead `c_jmp.*` call sites.
      2. `heap.zig` lines 1-3: TODO comment block from pre-plan era — these tasks are now complete (heap access is in B2, domain methods are in D2). Remove the comment.
      3. `word.zig` line 1: Same pre-plan TODO comment. Remove it.
      4. `c_abi.zig`: `jmp_buf`, `setjmp`, `longjmp` re-exports (lines 319-322) — only `sigjmp_buf`/`sigsetjmp`/`siglongjmp` are still needed (E3 constraint). Remove the four non-signal re-exports and fix any call sites.

* **F4: Boolean Word Field Audit**
    * *Status:* Not started
    * *Details:* B1 converted `strictif` from `Word` to `bool`. Audit remaining `Word`-typed fields in `RuntimeState` and module-level `export var` declarations that are semantically boolean (only ever assigned 0 or 1). Confirmed candidates from code inspection: `magic`, `making`, `mkexports`, `mksources`, `rechecking`, `bereaved`, `okprel`, `nostdenv`, `baded`. For each, verify all assignment sites use 0/1, convert to `bool`, update all call sites. Skip fields visible to C ABI (those that remain `export var` in main.zig).
    * *Constraint:* Only convert fields that are in `RuntimeState` (not `export var`). C-ABI-visible fields cannot change type.

* **F5: Expand Test Coverage**
    * *Status:* Not started
    * *Details:* Currently 30 test blocks project-wide, mostly in heap.zig. Add:
      1. `errors.zig` — verify each `MiraError` variant is distinct and set-intersection with `anyerror` works.
      2. `types.zig` — after F1 cleans it up, add a test that exercises the `TypeCheckAbort` error path via a mock call to `checktypes`.
      3. `runtime_state.zig` — extend the existing default-values test to cover newly converted bool fields from F4.
      4. `heap.zig` — extend domain-type round-trip tests to cover `FileNode`, `Identifier`, `TypeRef` method forwarding.
    * *Constraint:* Do not add tests that require a live heap or running interpreter — keep tests pure unit tests that compile without linking the Miranda runtime.

---
## Progress Summary

| Cluster | Step | Title | Status |
|---------|------|-------|--------|
| A | A1 | Replace `extern var` in `repl.zig` with `@import()` | **Complete** |
| A | A2 | Extract commands.zig from main.zig | **Complete** |
| A | A3 | Extract Compiler Initialization (setup.zig) | **Complete** |
| A | A4 | Extract Source Loader (module_loader.zig) | **Complete** |
| A | A5 | Extract State Dumping (dump.zig) | **Complete** |
| B | B1 | Introduce RuntimeState (includes boolean conversion) | **Complete** |
| B | B2 | Encapsulate Heap Access | **Complete** |
| C | C1 | NodeTag Enum | **Complete** |
| C | C2 | API Boundary Domain Types | **Complete** |
| D | D1 | Internal String Slices | **Complete** |
| D | D2 | Domain Methods | **Complete** |
| D | D3 | Documentation | **Complete** |
| E | E1 | Define Domain Errors | **Complete** |
| E | E2 | Error Union Signatures & Bubbling | **Complete** |
| E | E3 | Top-Level Error Handling | **Complete** |
| F | F1 | Eliminate `extern var` from `types.zig` | **Complete** |
| F | F2 | Selective `extern var` → `@import` in trans.zig / module_loader.zig | **Complete** |
| F | F3 | Stale Artifact Cleanup | Not started |
| F | F4 | Boolean Word Field Audit | Not started |
| F | F5 | Expand Test Coverage | Not started |
