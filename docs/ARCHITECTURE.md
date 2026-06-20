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
    │        Parser         │  (parser.zig, pratt.zig, lex_bridge.zig, lex.zig)
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

1. **Parser**: Reads the source input, lexes tokens, and builds the Abstract Syntax Tree (AST) representing definitions, types, and expressions.
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
* **`reduce.zig`**: The entry point for the C-ABI runtime wrapper.
* **`combinator.zig`**: Contains the generated combinator names table `cmbnms`.
* **`reducer/`**: The core graph reduction engine modules:
  - **`reduce.zig`**: The central graph reduction loop and DSW spine traversal.
  - **`combinators.zig`**: Implements execution rules for built-in combinators (e.g. `S`, `K`, `I`, `COND`).
  - **`ready.zig`**: Handles operator evaluation and stack unwinding.
  - **`lex.zig`**: Implements grammar and lexer reduction rules.
  - **`io.zig`**: Implements stream and file IO reduction rules.
* **`big.zig`**: Provides arbitrary-precision integer arithmetic and helper methods for converting floating-point values to bigint components.

### 3. Parser Subsystem (`src/parser/`)
* **`parser.zig`**: Implements a recursive-descent parser covering grammar structures (scripts, declarations, local definitions, type specs).
* **`pratt.zig`**: Implements a Pratt parser for expressions using the Miranda operator binding-powers table.
* **`ast.zig`**: Defines the stateless AST representations in pure Zig.
* **`codegen.zig`**: Lowers AST structures into active heap cell graphs.
* **`lex.zig` & `lex_bridge.zig`**: Handles layout-sensitive indentation, comments, lexical tokens, and bridge stream buffering.

### 4. IO Subsystem (`src/io/`)
* **`utf8.zig`**: Standard console and file character transcoding support.
* **`signals.zig`**: System interrupt and signal registrations.
* **`platform.zig`**: Core target-platform abstraction layer for macOS/Linux system files, thread-local error codes, and user privileges.
