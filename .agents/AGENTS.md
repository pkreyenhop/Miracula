# Miranda Interpreter Refactoring Guidelines (Zig)

## Core Philosophy
1. **The Compiler is the Linter:** Avoid suggesting external tools unless absolutely necessary. Rely on static analysis, `comptime`, and type safety.
2. **Exhaustiveness Over Else:** Favor `switch` expressions over `if/else` chains. Never include an `else` branch in a `switch` over an `enum` or `union` unless it is strictly required. Let the compiler catch missing branches.
3. **Safety by Default:** Discourage the use of `.` (pointer dereference) and `?` (optional unwrap) outside of explicit safety blocks. Enforce payload captures (`if (opt) |val|` or `switch (union) { .tag => |payload| ... }`).

## Coding Standards to Enforce

### 1. Control Flow
- **Replace `if` chains with `switch`:** If a variable is being checked against multiple values or ranges, mandate a `switch`.
- **Switch as an Expression:** Always prefer assigning variables via a `switch` expression rather than declaring an uninitialized `var` and assigning it inside branches.
- **Labeled Blocks:** For complex boolean evaluations that cannot be a switch, use labeled blocks (`blk: { ... }`) to cleanly resolve values.

### 2. Data Modeling
- **Tagged Unions:** Represent AST nodes or variant types strictly using `union(enum)`. 
- **Opaque Types:** Where appropriate, use opaque types for internal compiler states to prevent illegal cross-contamination of data structures.

### 3. Error Handling
- **No Manual Error Checks:** Forbid code like `if (err == error.X)`. Mandate `try` or catch-blocks that explicitly handle the error set.
- **Error Sets:** Group related errors into descriptive error sets rather than using generic errors.

### 4. Metaprogramming & Intrinsics
- **Use `@compileLog` for Debugging:** Never use `std.debug.print` to debug type issues. Force the use of `@compileLog` to inspect types during compilation.
- **Avoid `@branchHint`:** Treat `@branchHint` as a last resort. Demand proof from a profiler (like `samply` or `perf`) before allowing its use.
- **SIMD and Math:** When dealing with tight loops, evaluate if `@reduce`, `@shuffle`, or Fused Multiply-Add (`@mulAdd`) can replace scalar operations.
