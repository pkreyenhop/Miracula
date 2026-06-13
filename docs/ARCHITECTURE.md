# Miracula Architecture

This document describes the high-level architecture of Miracula (the Zig-migrated Miranda compiler and runtime). It details the primary subsystems, their responsibilities, and how data flows through the compiler pipeline to the graph reduction execution engine.

---

## Compiler Pipeline and Data Flow

The lifecycle of a Miranda script or interactive expression follows this pipeline:

```text
       Source Script (.m)
               │
               ▼
   ┌───────────────────────┐
   │        Parser         │  (lex.zig, parser_bridge.c, parse_actions.zig)
   └───────────────────────┘
               │
               ▼  Abstract Syntax Tree (AST)
   ┌───────────────────────┐
   │      Translator       │  (trans.zig, types.zig)
   └───────────────────────┘
               │
               ▼  Combinator Code Graph
   ┌───────────────────────┐
   │     Graph Builder     │  (heap.zig)
   └───────────────────────┘
               │
               ▼  Heap Cells
   ┌───────────────────────┐
   │        Reducer        │  (reduce.zig)
   └───────────────────────┘
               │
               ▼  Reductions & System IO
   ┌───────────────────────┐
   │        Runtime        │  (combinator.zig, big.zig, platform.zig)
   └───────────────────────┘
```

1. **Parser**: Reads the source input, lexes tokens, and builds the initial Abstract Syntax Tree (AST) cells in the heap.
2. **Translator (Compiler)**: Typechecks the AST and performs bracket abstraction to convert user-defined functions and pattern matches into target combinator graphs.
3. **Graph Builder**: Instantiates compile-time combinator expressions into active runtime heap cells.
4. **Reducer**: Runs the main graph reduction loop, applying combinators on the graph until a weak head normal form (WHNF) is reached.
5. **Runtime**: Provides support for big integer math, garbage collection, and basic terminal/system IO.

---

## Subsystem Details

### 1. Compiler Subsystem (`src/compiler/`)
* **`types.zig`**: Implements the typechecker, type inference system, and polymorphic type validation.
* **`trans.zig`**: Translates AST nodes into target combinator graphs. It handles pattern matching compilation, list comprehensions (ZF expressions), and bracket abstraction.

### 2. Runtime Subsystem (`src/runtime/`)
* **`heap.zig`**: Manages the cell allocation space. Implements a mark-and-sweep garbage collector that scans the stack and active roots.
* **`reduce.zig`**: The central graph reduction engine. It drives the reduction loop and evaluates expressions.
* **`combinator.zig`**: Implements the execution rules for all built-in combinators (such as `S`, `K`, `I`, `COND`, arithmetic, and list operations).
* **`big.zig`**: Provides arbitrary-precision integer arithmetic and helper methods for converting floating-point values to bigint components.

### 3. Parser Subsystem (`src/parser/`)
* **`lex.zig`**: Lexical analyzer that scans characters, handles offside layout rules, and produces tokens.
* **`parse_actions.zig`**: Semantic actions implemented in Zig that compile the parsed grammar rules into AST structures.
* **`legacy/`**: Isolated legacy C parser boundary containing `y.tab.c`, `y.tab.h`, and `parser_bridge.c` which parses the grammar via Berkeley yacc.

### 4. IO Subsystem (`src/io/`)
* **`utf8.zig`**: Standard console and file character transcoding support.
* **`signals.zig`**: System interrupt and signal registrations.
* **`platform.zig`**: Core target-platform abstraction layer for macOS/Linux system files, thread-local error codes, and user privileges.
