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

`main.zig` is intentionally thin (~267 lines). It holds:

- The 8 C-ABI-constrained `pub export var` globals (`nill`, `loading`, `compiling`, `errs`,
  `errline`, `obsuffix`, `SYNERR`, `commandmode`) that cannot move into `RuntimeState`
  because `heap.zig` and `parser_api.zig` reference them via `extern var` and cannot
  `@import main.zig` without a circular dependency.
- `pub var rs: RuntimeState` — the singleton interpreter state struct.
- `pub const` aliases re-exporting functions from all subsystem modules so callers have a
  single import point.
- `pub fn main()` — entry point that delegates immediately to the C-ABI `main_entry`.

### `src/runtime/` — Runtime Core

| File | Responsibility |
|------|----------------|
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

**Circular-dependency boundary.** `heap.zig` imports `main.zig` (for `rs` and the 8 stuck
export vars). `main.zig` imports `heap.zig` (for domain types and accessors). Any module
that imports both must do so transitively through `main.zig` only. Modules that define
`export var` state reached by `heap.zig` must keep those vars as top-level exports rather
than moving them into `RuntimeState`.

**C-ABI linker protocol.** Functions marked `export fn` are reachable across the
linker-as-module boundary. The Phase 7 refactor reduced but did not eliminate this pattern;
~350 `export fn` declarations remain in the compiler and runtime modules. New cross-module
calls should use `@import` instead.

**Signal-handler safety.** `reset()` and `fpe_error()` in `repl.zig` are POSIX signal
handlers. They call `siglongjmp(&main.rs.env, 1)` to restore the REPL recovery point.
No Zig error union can cross this path — signal handlers are asynchronous and cannot
unwind the Zig call stack.

**`MiraError` coverage.** `error.TypeCheckAbort` is the only `MiraError` variant currently
wired to Zig error union propagation. The remaining variants (`SyntaxError`, `HeapExhausted`,
`LoadError`, `EvaluationInterrupted`) document intent and are available for future work.

---

## Planned: Cluster G — Module Graph Repair

The module graph has two remaining structural problems targeted by Cluster G
(see `IDIOMATIC_ZIG_PLAN.md` for full details):

1. **`heap.zig ↔ main.zig` circular dependency (G1).** Extract `src/runtime/core_state.zig`
   for the 8 C-ABI export vars; move `pub var rs` into `runtime_state.zig`. After G1,
   `heap.zig` imports `runtime_state.zig` and `core_state.zig` directly rather than `main.zig`.

2. **Reducer dispatch via C-ABI linker (G2).** The 84 handler functions in `reducer/` are
   called from `reduce.zig` via `extern fn` / `export fn` pairs. Convert to direct `@import`
   calls within the subsystem.

3. **`lex.zig` global state (G3).** ~40 `export var` globals in `lex.zig` should be
   consolidated into a `LexState` struct (analogous to `RuntimeState` from B1).

4. **Heap accessor `extern fn` → direct imports (G4).** After G1, `lex.zig`, `codegen.zig`,
   `big.zig`, etc. can import `heap.zig` directly instead of using linker-resolved `extern fn`
   for `make`, `gc`, `sto_char`, etc.
