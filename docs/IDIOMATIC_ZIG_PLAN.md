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
    * *Status:* Not started
    * *Details:* Extract `loadfile`, `mkincludes`, and path tracking.
    * *DoD:* Can successfully load and parse a basic `.m` script. Includes at least one `test` block for file resolution.
* **A5: Extract State Dumping (`src/compiler/dump.zig`)**
    * *Status:* Not started
    * *Details:* Extract `undump`, `makedump`, `fixexports`, `unfixexports`.
    * *DoD:* `main.zig` is now strictly an entry point (<200 lines). Includes at least one `test` block.

### Cluster B: State Encapsulation (Depends on Cluster A)
*Goal: Eliminate implicit global state via dependency injection.*

* **B1: Introduce `RuntimeState` Struct**
    * *Status:* Not started
    * *Details:* Create `src/runtime/runtime_state.zig`. Consolidate the ~60 remaining global statics. Thread `*RuntimeState` through the call stack (e.g., `commandloop(state: *RuntimeState)`).
    * *Optimization:* Convert flags (`compiling`, `loading`, `strictif`) to native Zig `bool` types during struct creation. (Casts to `c_int` can occur at the FFI boundary if needed).
    * *DoD:* `globals.zig` is deleted. No module-level mutable state remains except `const` constants and C ABI bridge buffers.
* **B2: Encapsulate Heap Access (`src/runtime/heap.zig`)**
    * *Status:* Not started
    * *Details:* Remove the duplicated `pub fn h/t/hp/tp` from `main.zig`. Introduce the `Heap` struct for API boundaries.
    * *DoD:* `main.zig` has no `h/t/hp/tp` definitions. No duplicated accessor functions exist across files. Expanding existing single test to cover basic `make` and `gc`-marking is completed.

### Cluster C: Type Safety & Domain Modeling (Depends on Cluster B)
*Goal: Leverage Zig's type system at the newly established API boundaries.*

* **C1: `NodeTag` Enum**
    * *Status:* Not started
    * *Details:* Replace raw `u8` constants (`ATOM`, `AP`, `CONS`) in `c_abi.zig` with a typed `NodeTag = enum(u8)`. Apply `@enumFromInt` at read/write boundaries.
* **C2: API Boundary Domain Types**
    * *Status:* Not started
    * *Details:* Introduce `FileNode`, `Identifier`, `TypeRef`, and `NodeRef` as single-item structs wrapping `Word`.
    * *Constraint:* Apply *only* to `RuntimeState` fields and `pub` function signatures in `heap.zig`. Do not attempt to convert internal implementation code.

### Cluster D: Ergonomics (Can be done incrementally)
*Goal: Modernize internal syntax and improve codebase discoverability.*

* **D1: Internal String Slices**
    * *Status:* Not started
    * *Details:* Replace `[*:0]const u8` with `[:0]const u8` for internal function parameters. Convert to C pointers only at external FFI boundaries.
* **D2: Domain Methods**
    * *Status:* Not started
    * *Details:* Move procedural accessors (e.g., `id_type(id)`) onto their respective structs (e.g., `id.typ`). Depends on C2.
* **D3: Documentation**
    * *Status:* Not started
    * *Details:* Add `///` docs to all `pub` declarations in the newly split modules, specifically calling out invariants and ownership.

---

## Progress Summary

| Cluster | Step | Title | Status |
|---------|------|-------|--------|
| A | A1 | Replace `extern var` in `repl.zig` with `@import()` | **Complete** |
| A | A2 | Extract commands.zig from main.zig | **Complete** |
| A | A3 | Extract Compiler Initialization (setup.zig) | **Complete** |
| A | A4 | Extract Source Loader (module_loader.zig) | Not started |
| A | A5 | Extract State Dumping (dump.zig) | Not started |
| B | B1 | Introduce RuntimeState (includes boolean conversion) | Not started |
| B | B2 | Encapsulate Heap Access | Not started |
| C | C1 | NodeTag Enum | Not started |
| C | C2 | API Boundary Domain Types | Not started |
| D | D1 | Internal String Slices | Not started |
| D | D2 | Domain Methods | Not started |
| D | D3 | Documentation | Not started |
