# Miracula Architecture

This document describes the high-level architecture of Miracula (the Zig-migrated Miranda
compiler and runtime). It details the primary subsystems, their responsibilities, and how
data flows through the compiler pipeline to the graph reduction execution engine.

---

## Compiler Pipeline and Data Flow

```text
       Source Script (.m)
               │
               ▼
   ┌───────────────────────┐
   │        Parser         │  parser.zig, pratt.zig, lex.zig, lex_bridge.zig
   └───────────────────────┘
               │  AST (heap Words)
               ▼
   ┌───────────────────────┐
   │      Translator       │  trans.zig, types.zig
   └───────────────────────┘
               │  Combinator graph cells
               ▼
   ┌───────────────────────┐
   │     Graph Builder     │  heap.zig, codegen.zig
   └───────────────────────┘
               │  Heap cells
               ▼
   ┌───────────────────────┐
   │       Reducer         │  reducer/reduce.zig, combinators.zig, ready.zig …
   └───────────────────────┘
               │  Output / side effects
               ▼
   ┌───────────────────────┐
   │      Driver/REPL      │  driver/repl.zig, commands.zig, startup.zig
   └───────────────────────┘
```

1. **Parser** — Lexes tokens and builds an AST represented as heap `Word` values.
2. **Translator** — Type-checks the AST and performs bracket abstraction, converting
   user-defined functions and pattern matches into combinator graphs.
3. **Graph Builder** — Allocates and links combinator cells in the heap.
4. **Reducer** — Runs the graph reduction loop, applying combinators to reach weak
   head normal form (WHNF).
5. **Driver/REPL** — Manages the interactive loop, user commands, startup, and signal
   recovery.

---

## Subsystem Details

### `src/main.zig` — Composition Root

`main.zig` is intentionally thin (~237 lines). It is the composition root and re-export hub:

- `pub extern var` aliases for the 8 C-ABI globals defined in `core_state.zig` (`nill`,
  `loading`, `compiling`, `errs`, `errline`, `obsuffix`, `SYNERR`, `commandmode`).  Callers
  using `main.X` syntax continue to compile; the linker resolves them to `core_state.zig`.
- `pub const rs: *RuntimeState = &rt.rs` — pointer to the singleton interpreter state.
- `pub const cs = &compiler_state.cs` — pointer to the singleton compiler/typechecker state.
- `pub const` aliases for compiler entry points `type_of`, `checktypes`, `codegen` (H2) and
  all other subsystem functions, so every caller can `@import("main.zig")` as a single hub.
- `pub fn main()` — entry point that delegates immediately to the C-ABI `main_entry`.

### `src/runtime/` — Runtime Core

| File | Responsibility |
|------|----------------|
| `core_state.zig` | Leaf module holding the 8 C-ABI-constrained `export var` globals (`nill`, `loading`, `compiling`, `errs`, `errline`, `obsuffix`, `SYNERR`, `commandmode`). Extracted in G1 to break the `heap.zig ↔ main.zig` circular dependency. No imports from the Miracula source tree. |
| `runtime_state.zig` | `RuntimeState` struct — all mutable interpreter state that doesn't require a C-ABI linker symbol. ~75 fields covering identity atoms, file paths, compiler flags, evaluation control, I/O flags, working buffers, and signal recovery. |
| `heap.zig` | Cell allocation space and mark-and-sweep GC. Exports typed domain wrappers (`FileNode`, `Identifier`, `TypeRef`, `NodeRef`) and accessor functions (`fil_time`, `id_type`, etc.). The `hd`/`tl`/`tag` arrays are the raw heap storage. |
| `errors.zig` | `MiraError` error set (`SyntaxError`, `TypeCheckAbort`, `HeapExhausted`, `LoadError`, `EvaluationInterrupted`). Documents the POSIX signal-handler constraint: `siglongjmp` paths cannot be replaced with error unions. |
| `word.zig` | `Word` type alias (`c_long`) and all integer tag constants (`CONS`, `AP`, `ID`, `TVAR`, …). |
| `c_abi.zig` | Thin re-export shim: pulls selected symbols from `main_clib.zig` under shorter names used by internal modules. Exports `sigjmp_buf`/`sigsetjmp`/`siglongjmp` (permanent — signal handlers require them) but not `jmp_buf`/`setjmp`/`longjmp` (removed in F3 after E2 eliminated all non-signal uses). |
| `main_clib.zig` | Pure-Zig implementations of POSIX/C-stdlib functions (`printf`, `malloc`, `strlen`, `fork`, …) used by the legacy runtime. Implements `sigjmp_buf` and the platform-conditional `sigsetjmp` binding. |
| `reduce.zig` | C-ABI entry point wrapper for the graph reducer. |
| `big.zig` | Arbitrary-precision integer arithmetic. |
| `combinator.zig` | Combinator name table `cmbnms`. |
| `version.zig` | Build-time version string. |
| `reducer/reduce.zig` | Core graph reduction loop and DSW spine traversal. |
| `reducer/combinators.zig` | Execution rules for built-in combinators (`S`, `K`, `I`, `COND`, …). |
| `reducer/ready.zig` | Operator evaluation and stack unwinding. |
| `reducer/lex.zig` | Grammar and lexer reduction rules. |
| `reducer/io.zig` | Stream and file IO reduction rules. |

### `src/compiler/` — Compiler

| File | Responsibility |
|------|----------------|
| `compiler_state.zig` | `CompilerState` struct — all mutable typechecker and translator state extracted from `types.zig`, `trans.zig`, and `heap.zig` in H1. Accessed via `main.cs` (`*CompilerState`). No C-ABI linker symbols. |
| `types.zig` | Type checker and type inference. Uses `MiraError!T` return types; `TypeCheckAbort` propagates via `try`/`catch` rather than `setjmp`/`longjmp` (converted in E2). |
| `trans.zig` | AST → combinator graph translator. Handles pattern matching, list comprehensions, and bracket abstraction. |
| `setup.zig` | Interpreter initialisation: `mira_setup`, `primdef`, `predef`, `primlib`, `privlib`, `stdlib`. |
| `module_loader.zig` | Source file loading: `loadfile`, `mkincludes`, path tracking. |
| `dump.zig` | State persistence: `makedump`, `undump`, `fixexports`, `unfixexports`, `readoption`, `sigdefer`. |

### `src/parser/` — Parser

| File | Responsibility |
|------|----------------|
| `parser.zig` | Recursive-descent parser for declarations, type specs, local definitions, and scripts. |
| `pratt.zig` | Pratt expression parser using Miranda operator binding-power table. |
| `ast.zig` | Pure-Zig stateless AST node representations. |
| `codegen.zig` | Lowers AST structures into heap cells. |
| `lex.zig` | Layout-sensitive tokeniser; identifier and keyword classification. |
| `lex_bridge.zig` | Stream buffering bridge between lexer and parser. |
| `token_filter.zig` | Layout post-processing and comment stripping. |
| `parser_api.zig` | C-ABI bridge so the legacy runtime can call the Zig parser. |
| `diagnostics.zig` | Error message formatting and source location reporting. |
| `parser_tests.zig` | Golden-snapshot and integration regression tests. |

### `src/driver/` — REPL and CLI

| File | Responsibility |
|------|----------------|
| `repl.zig` | Interactive REPL loop (`commandloop`), expression evaluation (`obey`, `evaluate_repl`), and signal recovery. The `sigsetjmp`/`siglongjmp` on `rs.env` is the permanent SIGINT/SIGFPE recovery point. |
| `commands.zig` | `/`-command dispatcher (`command`), finger/help/stats/editor commands. |
| `startup.zig` | CLI flag parsing, `.mirarc` reading, editor and library path configuration. |

### `src/io/` — IO and Platform

| File | Responsibility |
|------|----------------|
| `files.zig` | Filesystem helpers: `fm_time`, `normal`, `same_file`, `inodev`, `fileExists`, `filecopy`, `mkabsolute`, `twidth`. |
| `utf8.zig` | UTF-8 character transcoding. |
| `signals.zig` | POSIX signal registration helpers. |
| `platform.zig` | macOS/Linux abstraction for `stat`/`statx`, thread-local errno, and privilege checks. |

---

## Key Invariants

**Circular-dependency boundary.** `heap.zig` cannot `@import` `main.zig` without creating
a cycle.  The `core_state.zig` leaf module (G1) holds the 8 C-ABI export vars that `heap.zig`
needs (`nill`, `loading`, `compiling`, `errs`, `errline`, `obsuffix`, `SYNERR`, `commandmode`),
and `runtime_state.zig` holds `pub var rs: RuntimeState`.  `main.zig` re-exports both as
`pub extern var` aliases so callers using `main.X` syntax are unaffected.

**C-ABI linker protocol.** Functions marked `export fn` are callable across the
linker-as-module boundary.  Phase 7 and Phase 8 reduced this count significantly:
- Reducer handlers (G2) converted to direct `@import` calls (~86 pairs removed).
- Heap accessors (H3) that were never referenced via `extern fn` had `export` stripped (20 functions).
- Compiler entry points `type_of`, `checktypes`, `codegen` are now reached via `main.zig`
  re-exports rather than `clib.*` linker resolution (H2).
New cross-module calls should use `@import` rather than `extern fn` / `export fn`.

**Compiler state.** All mutable typechecker and translator state lives in `CompilerState`
(`src/compiler/compiler_state.zig`), accessed via `main.cs` (a `*CompilerState` pointer).
The singleton is `pub var cs: CompilerState` in that module; `main.zig` re-exports the pointer
as `pub const cs = &compiler_state.cs`.  None of these fields are C-ABI linker symbols.

**Signal-handler safety.** `reset()` and `fpe_error()` in `repl.zig` are POSIX signal
handlers.  They call `siglongjmp(&main.rs.env, 1)` to restore the REPL recovery point.
No Zig error union can cross this path — signal handlers are asynchronous and cannot
unwind the Zig call stack.

**`MiraError` coverage.** `error.TypeCheckAbort` is the only `MiraError` variant currently
wired to Zig error union propagation.  The remaining variants (`SyntaxError`, `HeapExhausted`,
`LoadError`, `EvaluationInterrupted`) document intent and are available for future work.

---

## Remaining Modernization Opportunities

The items below are captured in `IDIOMATIC_ZIG_PLAN.md` (Clusters I1, I3, J, K2) but not
yet started.  They are higher-risk or higher-effort than the completed clusters.

- **I1 — Slices.** Replace `[*]Word` / `?[*]Word` / `[*:0]u8` at internal boundaries with
  native Zig slices (`[]Word`, `?[]Word`, `[:0]u8`).  Primary targets: the `hd`/`tl` heap
  arrays and the parser's token buffer.  High-effort: requires updating all pointer arithmetic.
- **I3 — Optional types.** Replace `NIL`-sentinel checks at high-level boundaries with
  `?Word`.  Incremental; can be done per-function.
- **J1 — Error union propagation.** Extend `MiraError` to cover `SyntaxError` and
  `LoadError`, replacing `NIL`-return patterns in the parser and module loader.
- **J2 — Standardize panics.** Replace remaining `c.exit(1)` calls with structured Zig
  `@panic` / `std.process.exit` with diagnostic messages.
- **K2 — Naming conventions.** Rename internal functions from C-style `snake_CASE` to Zig
  `camelCase`.  Large surface area; best done in a single automated pass.
