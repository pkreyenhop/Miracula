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
* **E3: Top-Level Error Handling**
    * *Status:* Not started
    * *Details:* Catch and handle the errors gracefully at the top-level loop (e.g., inside `commandloop`) using `catch`, replacing the `setjmp` recovery points.
    * *Constraint:* Do not begin this work until Clusters A through D are fully complete to avoid destabilizing the structural refactoring.

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
| E | E3 | Top-Level Error Handling | Not started |
