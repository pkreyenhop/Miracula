# Miranda Zig Refactor – Phase 7: Idiomatic Zig Modernization

## Objective
Transform the Miracula codebase from a successful C-to-Zig translation into an idiomatic, maintainable Zig codebase while preserving identical behavior.

---

## Improved Plan (2026-06-20)

### Key Findings

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

### Revised Execution Order

Work is organized into four clusters based on dependency. Each cluster is a prerequisite for the next.

---

#### Cluster A — Fix the Import Architecture (Prerequisite for all other work)

**A1 (New step): Replace `export var`/`extern var` with `@import()` sharing**

The goal is to eliminate the linker-as-module-system anti-pattern. Concretely:
- Create `src/runtime/globals.zig` as a staging module that owns all the state currently scattered across `main.zig` as `export var`
- Move the ~83 `export var` globals from `main.zig` into `globals.zig`
- Replace the 57 `extern var` declarations in `repl.zig` and startup.zig's direct field accesses with `const g = @import("../runtime/globals.zig")`
- This is a purely mechanical refactor — no behavior changes

*Definition of done*: No `export var` or `extern var` declarations remain for application-level state. The only remaining linker exports are `export fn` functions that are part of a deliberate public API.

**A2: Finish the module split (original Step 1 completion)**

With globals consolidated in `globals.zig`, the remaining extractions are safe:
- Extract `src/driver/commands.zig`: `command()` and its helpers (`editfile`, `xschars`, `filequote`, `finger`, `diagnose`, `allnamescom`, `namescom`, `manaction`) — ~550 lines total
- Extract `src/compiler/module_loader.zig`: `loadfile`, `undump`, `makedump`, `mkincludes`, `fixexports`, `unfixexports`, `primdef`, `predef`, `primlib`, `privlib`, `stdlib`, `mira_setup`, and all the related paint/hash helpers — ~1200 lines total

After these two extractions, `main.zig` should be under 200 lines: the entry point `main()`, the `RuntimeState` initialization stub, and thin composition glue.

*Definition of done*: `main.zig` < 200 lines. No business logic in `main.zig`. Each extracted module has at least one embedded `test` block for its primary function.

---

#### Cluster B — Replace `globals.zig` with `RuntimeState` (original Step 2)

`globals.zig` is a temporary staging point. Once all modules use `@import()` to reach it, replace it with a proper struct:

```zig
// src/runtime/runtime_state.zig
pub const RuntimeState = struct {
    compiling: bool = true,
    loading: bool = false,
    echoing: bool = false,
    listing: bool = false,
    strictif: bool = true,
    primenv: Word = NIL,
    current_script: ?[:0]const u8 = null,
    spacelimit: Word = 2500000,
    dicspace: Word = 100000,
    // ...
};
```

Thread `*RuntimeState` through `commandloop`, `command`, `loadfile`, `undump` etc. as a parameter. This eliminates the module-level global and makes ownership explicit.

*Definition of done*: `globals.zig` is deleted. All state lives in a `RuntimeState` instance allocated in `main()`. No module-level mutable state remains except `const` constants and C ABI bridge buffers.

**B1: Remove the duplicated h/t/hp/tp from main.zig (original Step 3)**

Currently `pub fn h/t/hp/tp` exist in `main.zig` (as public functions) AND as private copies in `heap.zig`. Now that `RuntimeState` is in place, also collapse the duplicated accessor functions (`id_type`, `id_val`, `id_who`, `fil_time`, `fil_share`, `fil_defs`, `t_class`, `dval`, `dlhs`) into a single location — they're duplicated across `main.zig` and `heap.zig`.

Remove the `pub fn h/t/hp/tp` from `main.zig` entirely. Callers that need heap access should reach through the canonical `heap.zig` interface.

Introduce the `Heap` struct in `heap.zig` for use at API boundaries (not for all internal callers — the private `h/t/hp/tp` inside `heap.zig` are fine to keep as file-private helpers):

```zig
pub const Heap = struct {
    pub fn head(node: Word) Word { return h(node); }
    pub fn tail(node: Word) Word { return t(node); }
    pub fn setHead(node: Word, val: Word) void { hp(node).* = val; }
    pub fn setTail(node: Word, val: Word) void { tp(node).* = val; }
};
```

*Definition of done*: `main.zig` has no `h/t/hp/tp` definitions. No duplicated accessor functions exist across files.

---

#### Cluster C — Type Safety (original Steps 4, 5, 6)

These can be done in parallel or in any order within the cluster. All depend on Cluster B being complete.

**C1 (original Step 5): Replace integer flags with booleans**

With flags living in `RuntimeState` (a Zig struct, not exported via linker), they can be `bool`:

```zig
compiling: bool = true,
loading: bool = false,
echoing: bool = false,
listing: bool = false,
strictif: bool = true,
```

Anywhere that currently assigns `0` or `1` to these fields becomes `false` or `true`. Comparisons like `if (loading != 0)` become `if (loading)`.

*Definition of done*: No flag fields in `RuntimeState` have type `c_int` or `Word`.

**C2 (original Step 4): Replace tag constants with a `NodeTag` enum**

All node tag values (`ATOM`, `DOUBLE`, `AP`, `CONS`, `INT`, `ID`, etc.) are currently raw `u8` constants in `c_abi.zig`. Replace with:

```zig
pub const NodeTag = enum(u8) {
    atom = 0, double = 1, datapair = 2, fileinfo = 3, tvar = 4,
    int = 5, constructor = 6, strcons = 7, id = 8, ap = 9,
    lambda = 10, cons = 11, // ...
};
```

All `tag.?[@intCast(x)] == c.AP` comparisons become `tag.?[@intCast(x)] == .ap`. Since tag arrays are `[*]u8`, use `@enumFromInt`/`@intFromEnum` at the read/write boundaries.

*Note*: This is the highest-churn step in the cluster — tag comparisons appear in `heap.zig`, `reduce.zig`, `main.zig`, and the reducer submodules. Scope it file-by-file.

**C3 (original Step 6): Domain-specific wrapper types — scoped narrowly**

The original plan proposes `FileNode`, `Identifier`, `TypeRef`, `NodeRef` wrappers for all `Word` values. This is correct in principle but has enormous call-site churn. Scope this step to the public API surface only:

- `RuntimeState` fields that hold semantic values (`primenv: Word` → `primenv: NodeRef`)  
- Return types of `heap.zig` public functions
- Do not attempt to convert internal implementation code

*Definition of done for this step*: Public API boundaries in `RuntimeState` and `Heap` use typed wrappers. Internal `Word` use is acceptable.

---

#### Cluster D — Ergonomics (original Steps 7, 8, 9; lower priority)

These are independent and can be done incrementally. They do not block any cluster above.

**D1 (original Step 7): String slices at internal boundaries**

Replace `[*:0]const u8` with `[:0]const u8` for internal function parameters where the sentinel-terminated slice is owned by Zig (not passed directly to C). Convert to raw pointer only at the FFI call sites in `main_clib.zig`. Do not attempt to convert dictionary pointers (`dicp`, `dicq`) — those are C-managed memory.

**D2 (original Step 8): Accessor methods on domain types**

Once C3 exists, move `id_val`, `id_type`, `id_who` onto an `Identifier` struct, `fil_time`, `fil_share`, `fil_defs` onto `FileNode`, etc. This removes the final procedural accessor functions.

**D3 (original Step 9): Documentation**

Add `///` doc comments to every `pub` declaration in `runtime_state.zig`, `heap.zig`, `module_loader.zig`, `commands.zig`, and `repl.zig`. Document invariants, ownership, and failure modes. Do this module by module as each one stabilizes.

---

#### Throughout — Tests (original Step 10)

Do not defer tests. Add at least one `test` block per module when it is created or significantly modified:
- `commands.zig`: test `diagnose()` with known keyword strings
- `module_loader.zig`: test `makeFilNode` helpers
- `runtime_state.zig`: test default initialization values
- `heap.zig`: expand existing single test to cover `make`, `gc`-marking basics, `sto_dbl`/`get_dbl` roundtrip

---

### Revised Summary Table

| Cluster | Step | Title | Depends on |
|---------|------|-------|------------|
| A | A1 (New) | Replace export var / extern var with @import() | — |
| A | A2 | Finish module split (commands + module_loader) | A1 |
| B | B | Introduce RuntimeState; delete globals.zig | A2 |
| B | B1 | Remove duplicate h/t/hp/tp; introduce Heap struct | B |
| C | C1 | Replace integer flags with booleans | B |
| C | C2 | Replace tag constants with NodeTag enum | B1 |
| C | C3 | Domain-specific types at API boundaries (scoped) | B1, C1 |
| D | D1 | String slices at internal boundaries | C |
| D | D2 | Accessor methods on domain types | C3 |
| D | D3 | Documentation | each module stable |
| — | — | Tests | woven throughout |

---

## Progress Summary (as of 2026-06-20)

| Step | Title | Status |
|------|-------|--------|
| 1 | Split `main.zig` into Logical Modules | Partial (~25%) |
| 2 | Introduce `RuntimeState` | Not started |
| 3 | Encapsulate Heap Access | Not started |
| 4 | Replace Magic Constants with Enums | Not started |
| 5 | Replace Integer Flags with Booleans | Not started |
| 6 | Introduce Domain-Specific Types | Not started |
| 7 | Modernize String Usage | Not started |
| 8 | Replace Accessor Functions with Structs | Not started |
| 9 | Expand Documentation Standards | Not started |
| 10 | Expand Embedded Test Coverage | Minimal |

---

## 🛠️ Step-by-Step Refactoring Priority

### 1. Split `main.zig` into Logical Modules

**Status: Partial (~25%)**

* **Objective**: Reduce [main.zig](file:///Users/pkreyenhop/src/experiments/Miracula/src/main.zig) from a monolithic dumping ground to a thin composition root and entry point.
* **Target Structure**:
  - `src/main.zig` (Entry point and initialization wrapper)
  - `src/driver/startup.zig` (Command-line argument parsing and startup orchestration) ✅ Done
  - `src/driver/repl.zig` (Interactive read-eval-print loop execution) ✅ Done
  - `src/driver/commands.zig` (REPL colon commands and compiler driver invocations) ❌ Not done — `command()` is still in `main.zig`
  - `src/compiler/module_loader.zig` (Miranda source file loading and dependency parsing) ❌ Not done — `loadfile()`, `undump()`, `makedump()` still in `main.zig`
  - `src/compiler/exports.zig` (Verification of type/symbol exports) ❌ Not done
  - `src/compiler/dependency_graph.zig` (Where-block dependency sort and letrec bindings) ❌ Not done
  - `src/filesystem/file_registry.zig` (I/O structures, path tracking, and stat helpers) ❌ Not done

* **Notes**: `main.zig` is still 2882 lines and carries a TODO comment at the top referencing this step. The remaining extraction work is the bulk of the step.

---

### 2. Introduce `RuntimeState`

**Status: Not started**

* **Objective**: Consolidate dozens of global static variables into a structured type to make ownership clear and eliminate implicit global state.
* **Target Structure**:
  ```zig
  pub const RuntimeState = struct {
      compiling: bool,
      loading: bool,
      echoing: bool,
      listing: bool,
      strictif: bool,
      tracing: bool,
      debugging: bool,
      primenv: Word,
      current_script: ?[:0]const u8,
      // ... other static globals
  };
  ```
* **Location**: Define in a new file `src/runtime/runtime_state.zig`. Incrementally transition globals to this struct.
* **Notes**: `src/runtime/runtime_state.zig` does not exist. Approximately 60+ global variables are still scattered across `main.zig` (lines 58–200), exported via `extern var` declarations in `repl.zig` and `startup.zig`.

---

### 3. Encapsulate Heap Access

**Status: Not started**

* **Objective**: Remove the duplicated, globally exposed raw heap helper functions (`h(x)`, `t(x)`, `hp(x)`, `tp(x)`) and encapsulate them inside a clean `Heap` interface.
* **Target Structure**:
  ```zig
  pub const Heap = struct {
      pub fn head(self: *Heap, node: Word) Word;
      pub fn tail(self: *Heap, node: Word) Word;
      pub fn setHead(self: *Heap, node: Word, val: Word) void;
      pub fn setTail(self: *Heap, node: Word, val: Word) void;
  };
  ```
* **Location**: Move logic to `src/runtime/heap.zig` and replace all calls to `h(node)` and `t(node)` with methods on a `Heap` instance.
* **Notes**: `src/runtime/heap.zig` exists and contains private `h/t/hp/tp` file-scope functions (lines 65–83). However, `main.zig` still exposes `pub fn h()`, `pub fn t()`, `pub fn hp()`, `pub fn tp()` as globally accessible functions (lines 211–227) — the duplication the plan aims to remove. No `Heap` struct has been introduced. TODO comment remains at the top of `heap.zig`.

---

### 4. Replace Magic Constants with Enums

**Status: Not started**

* **Objective**: Introduce type-safe Zig `enum` representations to replace raw integers for cell tags and built-in type constants.
* **Target Structures**:
  - **Node Tags**:
    ```zig
    pub const NodeTag = enum(u8) {
        atom = 0,
        double = 1,
        datapair = 2,
        fileinfo = 3,
        tvar = 4,
        int = 5,
        constructor = 6,
        strcons = 7,
        id = 8,
        ap = 9,
        lambda = 10,
        cons = 11,
        // ...
    };
    ```
  - **Built-in Types**:
    ```zig
    pub const BuiltinType = enum(Word) {
        undef = 0,
        bool = 1,
        num = 2,
        char = 3,
        list = 4,
        // ...
    };
    ```
* **Location**: Modify declarations in `src/runtime/c_abi.zig` and uses in `heap.zig` and `reduce.zig`.
* **Notes**: All node tag constants (`ATOM`, `DOUBLE`, `AP`, `CONS`, etc.) and built-in type constants remain as raw `pub const` integers in `c_abi.zig`. TODO comment at top of `c_abi.zig` acknowledges this. `heap.zig` and `reduce.zig` compare against raw integers throughout.

---

### 5. Replace Integer Flags with Booleans

**Status: Not started**

* **Objective**: Replace legacy integer flags (0 and 1) with native Zig `bool` types.
* **Flags**:
  - `compiling`, `loading`, `echoing`, `listing`, `strictif`, `tracing`, `debugging`
* **Target**:
  ```zig
  compiling: bool = true,
  echoing: bool = false,
  listing: bool = false,
  ```
* **Notes**: All named flags are still `c_int` or `Word` in `main.zig` — `export var loading: c_int = 0`, `export var compiling: c_int = 1`, `pub export var echoing: Word = 0`, etc. (lines 86, 126–137). The C ABI export requirement (these are read by C library code) makes a direct `bool` conversion require care; this step is best tackled after Step 2 (`RuntimeState`) reduces the number of external bindings.

---

### 6. Introduce Domain-Specific Types

**Status: Not started**

* **Objective**: Replace the pervasive use of raw `Word` integers in public API boundaries with semantic wrapper types.
* **Examples**:
  - **Files**: `const FileNode = struct { handle: Word };`
  - **Identifiers**: `const Identifier = struct { node: Word };`
  - **Types**: `const TypeRef = struct { node: Word };`
  - **Heap Objects**: `const NodeRef = struct { index: Word };`
* **Notes**: Raw `Word` (`c_long`) is used uniformly across all heap objects, identifiers, file nodes, and type references. No wrapper types have been introduced anywhere in the codebase. This step depends on Step 3 (Heap struct) to be meaningful at API boundaries.

---

### 7. Modernize String Usage (Reduce C String usage)

**Status: Not started**

* **Objective**: Replace null-terminated C pointers (`[*:0]const u8`, `?[*:0]u8`) with standard Zig slices (`[]const u8` or `[:0]const u8`) for internal manipulation. Convert to C pointers only at external FFI boundaries.
* **Notes**: `main.zig`, `heap.zig`, and the driver modules use raw C pointer types (`[*:0]const u8`, `?[*:0]u8`) pervasively — for file names, identifiers, the editor string, prompt string, and all dictionary operations. Internal functions such as `get_id()`, `get_fil()`, and `is()` work with C pointers rather than slices. Some Zig-idiomatic slices appear in `io/platform.zig` and isolated helper functions, but the bulk of string handling has not been updated.

---

### 8. Replace Accessor Functions with Structs

**Status: Not started**

* **Objective**: Replace procedural C-style field accessor helper functions with methods/properties on Zig structures.
* **Examples**:
  - `id_type(id)` -> `id.typ`
  - `id_val(id)` -> `id.val`
  - `fil_time(file)` -> `file.modified_time`
* **Notes**: Procedural accessor functions (`id_type`, `id_val`, `id_who`, `fil_time`, `fil_share`, `fil_defs`, `t_class`, `t_info`, `dval`, `dlhs`, etc.) exist as duplicated copies in both `main.zig` and `heap.zig`. There are no struct types or methods in place. TODO comment remains at the top of `heap.zig`. This step logically depends on Step 6 (domain-specific types) to have receiver types to put methods on.

---

### 9. Expand Documentation Standards

**Status: Not started**

* **Objective**: Document every public function with standard Zig doc comments detailing invariants, ownership rules, failure modes, and parameters.
  ```zig
  /// Description of behavior
  ///
  /// Invariants:
  /// - `node` must be a valid allocated heap cell.
  ///
  /// Ownership:
  /// - The heap retains ownership of the return cell.
  pub fn head(self: *Heap, node: Word) Word
  ```
* **Notes**: No `///` doc comments are present on any public function in `main.zig`, `heap.zig`, or the driver modules. A handful of inline `//` implementation comments exist but do not follow the doc-comment convention. This step is best deferred until the target module structure from Steps 1–3 stabilizes, so documented APIs do not need to be rewritten after the split.

---

### 10. Expand Embedded Test Coverage

**Status: Minimal**

* **Objective**: Move tests out of separate runner structures and write them directly in the modules they test, adjacent to the logic, verifying code invariants inline.
* **Notes**: Only one embedded `test` block exists in the runtime — `test "sto_char returns atoms for Latin-1 values"` in `heap.zig` (line 1914). No other `test` blocks are present in `main.zig`, `repl.zig`, `startup.zig`, or any other runtime/compiler module. The parser subsystem has a dedicated `src/parser/parser_tests.zig`, but runtime and compiler modules have no co-located tests.
