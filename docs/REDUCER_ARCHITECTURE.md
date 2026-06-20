# Miranda Graph Reducer Architecture

This document describes the architecture of the Miracula graph reduction engine, implemented in pure Zig under [src/runtime/reducer/](file:///Users/pkreyenhop/src/experiments/Miracula/src/runtime/reducer/). It details the execution model, pointer-reversing traversal engine, and garbage collection constraints.

---

## 1. Reducer State & Context

The reduction machine is stateful, utilizing a centralized `ReductionCtx` context structure defined in [src/runtime/reducer/reduce.zig](file:///Users/pkreyenhop/src/experiments/Miracula/src/runtime/reducer/reduce.zig#L6-L12):

```zig
pub const ReductionCtx = extern struct {
    e: Word,
    s: Word,
    hold: Word,
    args: [4]Word,
    action: c_int,
};
```

### Context Register Roles
* **`e` (Expression Register)**: The active expression pointer. At the start of a reduction cycle, it points to the head of the current redex. During traversal, it points to the cell currently being evaluated.
* **`s` (Spine Stack Register)**: Represents the top of the stack of traversed application (`AP`) cells. In this stackless reducer, `s` is the head pointer of the pointer-reversed path back to the root of the expression.
* **`hold` (Temporary Register)**: A scratch pointer used during node traversal transitions, cell allocations, and rewriting to temporarily hold references.
* **`args` (Argument Cache)**: A 4-element array storing arguments extracted from the spine during combinator execution.
* **`action`**: Tracks the status of the current reduction step (e.g., `ACT_NONE`, `ACT_NEXTREDEX`, `ACT_DONE`).

---

## 2. Traversal Model & Pointer Reversal

The Miranda reducer uses a **pointer-reversing, stackless graph traversal** algorithm (Deutsch-Schorr-Waite). It eliminates stack overflow risks by reversing pointers in-place inside the application cells on the heap during traversal, then restoring them when returning up the spine.

Traversal helper routines are defined in [src/runtime/reducer/reduce.zig](file:///Users/pkreyenhop/src/experiments/Miracula/src/runtime/reducer/reduce.zig#L248-L305):

1. **`downLeft(ctx)`**:
   * Walks down the left branch of an application (`AP`) cell.
   * Reverses the cell's `hd` pointer to point back to the parent cell in the spine.
   * *Mutates*: `ctx.s` becomes the current cell, `ctx.e` becomes the head of the cell, and the cell's `hd` is updated to point to the parent.

2. **`upLeft(ctx)`**:
   * Walks back up a left branch, restoring the reversed `hd` pointer of the application cell.
   * *Mutates*: `ctx.e` becomes the restored cell, and `ctx.s` becomes the grandparent.

3. **`downRight(ctx)`**:
   * Traverses down the right branch of an application cell (typically for strict operators or constructors).
   * Reverses the cell's `tl` pointer and sets `tlptrbit` on `ctx.s` to indicate a right-branch traversal.
   * *Mutates*: `ctx.s` becomes the current cell (with `clib.tlptrbit` set), and `ctx.e` becomes the tail.

4. **`upRight(ctx)`**:
   * Walks back up a right branch, restoring the reversed `tl` pointer and clearing `tlptrbit`.
   * *Mutates*: `ctx.e` becomes the restored cell, and `ctx.s` becomes the grandparent.

---

## 3. The Reduction Cycle

A complete reduction cycle (hnf evaluation) consists of four distinct phases:

```mermaid
graph TD
    A["Spine Traversal: downLeft()"] --> B[Head Node Identification]
    B --> C{Is ctx.e a combinator?}
    C -->|Yes| D[Extract Arguments / execute Combinator]
    C -->|No| E[Default / Tag Dispatch]
    D --> F[Rewrite Cell & Set action = ACT_DONE / ACT_NEXTREDEX]
    E --> F
    F --> G{ctx.s == BACKSTOP?}
    G -->|Yes| H[Return Result]
    G -->|No| I[upRight() / handle_ready_state()]
    I --> A
```

1. **Spine Traversal**: The reducer continuously executes `downLeft()` to walk down the left branch of application cells until it hits a non-`AP` cell or abnormal node.
2. **Head Node Dispatch**: The reducer inspects the head node `e` using a `switch` statement in [src/runtime/reducer/reduce.zig](file:///Users/pkreyenhop/src/experiments/Miracula/src/runtime/reducer/reduce.zig#L42-L189):
   * **Combinators**: Executes combinators (handled in [src/runtime/reducer/combinators.zig](file:///Users/pkreyenhop/src/experiments/Miracula/src/runtime/reducer/combinators.zig)).
   * **Strict Functions**: Forces reduction of arguments before execution.
   * **Lexer / Grammar / IO**: Delegates to specialized modules:
     - [src/runtime/reducer/lex.zig](file:///Users/pkreyenhop/src/experiments/Miracula/src/runtime/reducer/lex.zig)
     - [src/runtime/reducer/io.zig](file:///Users/pkreyenhop/src/experiments/Miracula/src/runtime/reducer/io.zig)
3. **Execution & Rewriting**: The combinator rewrites the redex cell in-place. If the reduction is complete, it transitions via `ACT_DONE`. If it requires further reduction, it loops via `ACT_NEXTREDEX`.
4. **Ready State Handling**: If a subtask completes, `upRight()` walks up the spine. If the tag is not `AP`, control passes to `handle_ready_state()` in [src/runtime/reducer/ready.zig](file:///Users/pkreyenhop/src/experiments/Miracula/src/runtime/reducer/ready.zig) which performs operator evaluation and stack unwinding.

---

## 4. Garbage Collection Boundaries

The Miranda runtime uses a **conservative mark-and-sweep garbage collector** implemented in [src/runtime/heap.zig](file:///Users/pkreyenhop/src/experiments/Miracula/src/runtime/heap.zig).

### Allocation APIs triggering GC
Any call to the following allocator APIs may trigger a garbage collection (`gc()`) if the heap runs out of free cells:
* `make(tag, x, y)`
* `ap(x, y)` (allocates an `AP` cell)
* `cons(x, y)` (allocates a `CONS` cell)
* `datapair(x, y)` (allocates a `DATAPAIR` cell)
* `rewrite_to_value()` / `rewrite_to_nil()` / `rewrite_to_cons()` (overwrites tags/pointers)

### GC Root Safety
The garbage collector identifies roots by scanning the C stack conservatively from the current address of the GC execution frame up to the stack base pointer `cstack` (captured when starting the reducer).
* **Safe**: Since `ReductionCtx` is a local variable on the stack, all of its active fields (`e`, `s`, `hold`, and `args[]`) reside on the stack and are scanned automatically by the garbage collector.
* **Warning**: Heap references must never be stored in global static variables or fields outside the stack context without registering them in the root bases function in [src/runtime/heap.zig](file:///Users/pkreyenhop/src/experiments/Miracula/src/runtime/heap.zig).
