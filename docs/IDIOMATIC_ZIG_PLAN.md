# Miranda Zig Refactor – Phase 7: Idiomatic Zig Modernization

## Objective
Transform the Miracula codebase from a successful C-to-Zig translation into an idiomatic, maintainable Zig codebase while preserving identical behavior.

---

## 🛠️ Step-by-Step Refactoring Priority

### 1. Split `main.zig` into Logical Modules
* **Objective**: Reduce [main.zig](file:///Users/pkreyenhop/src/experiments/Miracula/src/main.zig) from a monolithic dumping ground to a thin composition root and entry point.
* **Target Structure**:
  - `src/main.zig` (Entry point and initialization wrapper)
  - `src/driver/startup.zig` (Command-line argument parsing and startup orchestration)
  - `src/driver/repl.zig` (Interactive read-eval-print loop execution)
  - `src/driver/commands.zig` (REPL colon commands and compiler driver invocations)
  - `src/compiler/module_loader.zig` (Miranda source file loading and dependency parsing)
  - `src/compiler/exports.zig` (Verification of type/symbol exports)
  - `src/compiler/dependency_graph.zig` (Where-block dependency sort and letrec bindings)
  - `src/filesystem/file_registry.zig` (I/O structures, path tracking, and stat helpers)

---

### 2. Introduce `RuntimeState`
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

---

### 3. Encapsulate Heap Access
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

---

### 4. Replace Magic Constants with Enums
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

---

### 5. Replace Integer Flags with Booleans
* **Objective**: Replace legacy integer flags (0 and 1) with native Zig `bool` types.
* **Flags**:
  - `compiling`, `loading`, `echoing`, `listing`, `strictif`, `tracing`, `debugging`
* **Target**:
  ```zig
  compiling: bool = true,
  echoing: bool = false,
  listing: bool = false,
  ```

---

### 6. Introduce Domain-Specific Types
* **Objective**: Replace the pervasive use of raw `Word` integers in public API boundaries with semantic wrapper types.
* **Examples**:
  - **Files**: `const FileNode = struct { handle: Word };`
  - **Identifiers**: `const Identifier = struct { node: Word };`
  - **Types**: `const TypeRef = struct { node: Word };`
  - **Heap Objects**: `const NodeRef = struct { index: Word };`

---

### 7. Modernize String Usage (Reduce C String usage)
* **Objective**: Replace null-terminated C pointers (`[*:0]const u8`, `?[*:0]u8`) with standard Zig slices (`[]const u8` or `[:0]const u8`) for internal manipulation. Convert to C pointers only at external FFI boundaries.

---

### 8. Replace Accessor Functions with Structs
* **Objective**: Replace procedural C-style field accessor helper functions with methods/properties on Zig structures.
* **Examples**:
  - `id_type(id)` -> `id.typ`
  - `id_val(id)` -> `id.val`
  - `fil_time(file)` -> `file.modified_time`

---

### 9. Expand Documentation Standards
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

---

### 10. Expand Embedded Test Coverage
* **Objective**: Move tests out of separate runner structures and write them directly in the modules they test, adjacent to the logic, verifying code invariants inline.
