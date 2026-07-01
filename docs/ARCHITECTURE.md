# Miracula Architecture

This document describes the current architecture of Miracula (the Zig-migrated Miranda
compiler and runtime). It details the primary subsystems, their responsibilities, how data
flows through the compiler pipeline to the graph reduction execution engine, and the
representation choices (state aggregation, string interning, the reduction spine, garbage
collection) that came out of the post-migration redesign work.

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
   │       Reducer         │  reducer/reduce.zig, spine.zig, combinators.zig, ready.zig …
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
4. **Reducer** — Runs the graph reduction loop over an explicit spine stack, applying
   combinators to reach weak head normal form (WHNF).
5. **Driver/REPL** — Manages the interactive loop, user commands, startup, and signal
   recovery.

---

## State: one aggregated singleton (`Interp`)

Every piece of mutable interpreter state — runtime flags, the heap, lexer state, compiler
state, the small core-error sentinels, I/O, evaluation counters, bignum scratch, and the
string table — is a value field of one struct, `Interp` (`src/runtime/interp.zig`):

```zig
pub const Interp = struct {
    rs: RuntimeState = .{},
    heap: Heap = .{},
    lex: LexState = .{},
    comp: CompilerState = .{},
    core: CoreState = .{},
    io: IoState = .{},
    eval: EvalState = .{},
    big: Bignum = .{},
    strtab: StringTable = .{},
};

pub var interp: Interp = .{};
```

This is a **transitional aggregation**, not the final shape: it is still one global, but a
single one instead of nine independent globals. Each owning module re-points its own
package-level singleton at the matching field, so the ~2,100 pre-existing
`owner.singleton.field` access sites across the codebase are unchanged — they now read and
write through `interp` without having been touched:

```zig
// runtime_state.zig
pub const rs = &@import("interp.zig").interp.rs;
// compiler_state.zig
pub const cs = &@import("../runtime/interp.zig").interp.comp;
// lex_state.zig
pub const ls = &@import("../runtime/interp.zig").interp.lex;
// core_state.zig
pub const s = &@import("interp.zig").interp.core;
```

`interp.reset()` (`interp = .{};`) gives every unit test a pristine interpreter without
relying on ad-hoc per-module re-init — the owner-module pointers above stay valid because
`interp`'s address never changes, only its value is replaced. Only the startup bootstrap
infrastructure (`allocator`/`io`/`gpa`/`environ` in `runtime_state.zig`) sits outside
`Interp`, since it is set once at process start and never reset.

**Where this is headed** (see [REMAINING_WORK_PLAN.md](REMAINING_WORK_PLAN.md) Phase 6,
currently deferred — not required for serial per-function tests): thread `*Interp`
explicitly through the ~2,100 call sites and delete the global, letting `main` construct the
interpreter value itself. This is the largest remaining item in the redesign and is only
worth doing if the interpreter needs multiple concurrent instances in one process.

`src/main.zig` itself is now just the process entry point (~80 lines): it wires up the
allocator/IO context from `std.process.Init`, forwards to `startup.mainEntry`, and
aggregates every module's inline unit tests into the `main-tests` binary. The old
`main.<name>` re-export namespace (a single hub every module funneled through) is gone —
modules call each other directly via `@import`.

---

## The reduction engine: an explicit spine, not pointer reversal

`reducer/reduce.zig`'s main loop evaluates a combinator graph to WHNF by unwinding the
**spine** — the left-ancestor chain of `AP` (application) cells from the root down to the
head combinator — then walking back up applying rewrite rules.

The original C port (and Miracula's first several months) encoded the spine **in the graph
itself**: descending into a cell temporarily overwrote its own `hd`/`tl` field with a
"previous stack top" pointer, tagged via the top two bits of the word (`tlptrbits`), restored
on the way back up. Every `hd`/`tl`/tag access in the hottest loop in the interpreter had to
mask those bits off, and the encoding would have permanently competed with any future typed
`Value` representation for the same high bits.

`reducer/spine.zig` replaces this with `Spine` — an explicit, heap-growable stack of
`Frame{ node, via_tl }` values, kept separate from the graph:

- No cell ever holds a borrowed value; no access needs bit-masking.
- `Spine.register()`/`unregister()` maintain a LIFO chain of every live `Spine` (nested
  `reduce()` calls each get their own, matching call nesting), so the GC's conservative stack
  scan — which cannot see into `Spine`'s own heap-allocated buffer — has an explicit,
  precise root set via `Spine.markAllRoots()`.
- A small buffer pool (keyed by allocator identity, gated off under `builtin.is_test`) avoids
  paying for a fresh empty `ArrayList` on every `reduce()` call; without it, many-small-calls
  workloads regressed ~15x.

`reduce_core.zig` is the seam every rewrite-handler module (`combinators.zig`, `ready.zig`,
`reducer/lex.zig`, `io.zig`) imports as `reduce`; it owns the `ReductionCtx` register file
(`e`, `spine`, `hold`, `args`, `action`) and the traversal/accessor/classifier/rewrite
primitives layered over `Spine`.

---

## Garbage collection: precise tracing, not a sign-bit trick

The original mark-sweep collector repurposed the sign bit of each cell's tag byte: a
negative (as a signed `i8`) tag byte meant "not yet reached this GC cycle" during marking, or
simply "garbage" between cycles. Allocation (`Heap.make`) was a bump pointer that fell back to
a linear scan-and-reuse over the whole arena once it ran off the end.

`heap.zig`'s `Heap` struct now holds:

- `live: std.DynamicBitSetUnmanaged` — a persistent, one-bit-per-cell liveness bitmap, sized
  once in `setupheap` and resized in `resetheap`.
- `free_head: Word` — an explicit free list, threaded through each free cell's own `tl` field.

`mark()` tests `!live.isSet(idx)` for cycle detection instead of flipping a sign bit.
`gc()` clears the bitmap, calls `bases()` (the conservative stack scan plus every registered
`Spine`'s precise roots), then rebuilds `free_head` in a single sweep over every cell that
stayed unmarked. `make()`'s allocation path is now O(1) — pop `free_head` — instead of the old
bump-pointer's scan-for-a-gap. Because the GC never stores anything but a named tag value in
a cell's tag byte, `NodeTag` is a fully exhaustive enum (no `_,` catch-all).

---

## String interning

Node-stored identifier and pathname strings are no longer raw pointers cast to/from `Word`.
`strtab.zig`'s `StringTable` interns every such string by content into a process-lifetime
arena and hands back a `StrId` (a table index), stored *negated* in the `Word` (`-index`,
`index >= 1`) so it can never collide with a valid heap cell handle (cell handles live in
`[ATOMLIMIT, TOP())`, and a negated index is always negative). Equal names share one `StrId`,
which is what keeps re-intern-then-compare patterns (`member(list, strBits(getId(x)))`)
working now that `getId` no longer returns a stable pointer. Three accessors in `word.zig`
(`strOf`/`strOfMut`/`strBits`) are the only place this encoding is unpacked.

---

## Subsystem Details

### `src/runtime/` — Runtime Core

| File | Responsibility |
|------|----------------|
| `interp.zig` | The `Interp` aggregate struct and its process-wide singleton (`interp`); see "State" above. |
| `core_state.zig` | Leaf module holding `CoreState` — small error/mode sentinels (`nill`, `loading`, `compiling`, `errs`, `errline`, `SYNERR`, `commandmode`). No imports from the Miracula source tree (the G1 acyclic invariant), so `heap.zig` and `parser_api.zig` can reach it without forming a cycle with `main.zig`. Plain `pub var`/struct fields — no C-ABI linker symbols; that was a historical stage, since removed. |
| `runtime_state.zig` | `RuntimeState` struct — mutable interpreter state that doesn't need the G1 leaf-module isolation: identity atoms, file paths, compiler flags, evaluation control, I/O flags, working buffers, signal recovery (`env`, the `sigjmp_buf` for `rt.rs.env`). |
| `heap.zig` | Cell allocation arena and the precise tracing GC (see "Garbage collection" above). Exports typed domain wrappers and accessor functions, and implements the `.x` dump/load (object-file) format. |
| `strtab.zig` | Interned string table (`StringTable`, `StrId`) — see "String interning" above. |
| `errors.zig` | `MiraError` error set (`SyntaxError`, `TypeCheckAbort`, `HeapExhausted`, `LoadError`, `EvaluationInterrupted`) and `fatal()`, the print-then-exit helper for unrecoverable command-line/startup/load errors. Documents the POSIX signal-handler constraint (permanent, confirmed by a full call-site audit — see "Key Invariants" below). |
| `word.zig` | `Word` type alias (`i64`) and all integer tag constants (`CONS`, `AP`, `ID`, …); `NodeTag`, the exhaustive cell-tag enum; `IoState`. |
| `main_clib.zig` | Pure-Zig implementations of POSIX/C-stdlib functions (`printf`, `malloc`, `strlen`, `fork`, `sigsetjmp`/`siglongjmp`, …) used by the legacy-shaped runtime code. The only files with a real C-ABI surface (`extern fn` to libc/syscalls, the syscall floor). |
| `reduce.zig` | `EvalState` (evaluation-time counters/services) and helpers (`print`, `force`, `getstring`, …) shared across the reducer. |
| `big.zig` | Arbitrary-precision integer arithmetic (`Bignum`). |
| `combinator.zig` | Combinator name table `cmbnms`. |
| `version.zig` | Build-time version string. |
| `reducer/reduce.zig` | The main reduction loop: unwind the spine, dispatch on the head combinator, walk back up forcing arguments. |
| `reducer/spine.zig` | `Spine`/`Frame` — the explicit spine stack (see above). |
| `reducer/reduce_core.zig` | Shared `ReductionCtx` register file and traversal/rewrite primitives, imported by every handler module below. |
| `reducer/combinators.zig` | Execution rules for built-in combinators (`S`, `K`, `I`, `COND`, arithmetic, list operations, …). |
| `reducer/ready.zig` | Dispatch once a combinator has all its arguments in hand — the "ready state" rewrite. |
| `reducer/lex.zig` | Grammar and lexer reduction rules (Miranda's built-in parser-combinator grammar feature). |
| `reducer/io.zig` | Stream and file IO reduction rules. |
| `reducer/trace.zig` | Optional per-combinator step tracing/histogram (compiled out when off). |

### `src/compiler/` — Compiler

| File | Responsibility |
|------|----------------|
| `compiler_state.zig` | `CompilerState` struct — mutable typechecker and translator state. Accessed via `compiler_state.cs`, which points into `interp.comp`. |
| `types.zig` | Type checker and type inference (`etype`, `conforms`, …). Uses `MiraError!T` return types; `TypeCheckAbort` propagates via `try`/`catch` rather than `setjmp`/`longjmp`. |
| `trans.zig` | AST → combinator graph translator. Handles pattern matching, list comprehensions, and bracket abstraction. |
| `setup.zig` | Interpreter initialisation: `miraSetup`, `primdef`, `predef`, `primlib`, `privlib`, `stdlib`. |
| `module_loader.zig` | Source file loading: `loadfile`, `mkincludes`, path tracking. |
| `dump.zig` | State persistence: `makedump`, `undump`, `fixexports`, `unfixexports`, `readoption`, `sigdefer`. |

### `src/parser/` — Parser

| File | Responsibility |
|------|----------------|
| `parser.zig` | Recursive-descent parser for declarations, type specs, local definitions, and scripts. |
| `pratt.zig` | Pratt expression parser using Miranda's operator binding-power table. |
| `ast.zig` | Pure-Zig stateless AST node representations. |
| `codegen.zig` | Lowers AST structures into heap cells. |
| `lex.zig` | Layout-sensitive tokeniser; identifier and keyword classification. |
| `lex_state.zig` | `LexState` struct — mutable lexer state, accessed via `lex_state.ls`, which points into `interp.lex`. |
| `lex_bridge.zig` | Stream buffering bridge between lexer and parser. |
| `token_filter.zig` | Layout post-processing and comment stripping. |
| `parser_api.zig` | Bridge so the legacy-shaped runtime code can call the Zig parser. |
| `diagnostics.zig` | Error message formatting and source location reporting. |
| `parser_tests.zig` | Golden-snapshot and integration regression tests. |

### `src/driver/` — REPL and CLI

| File | Responsibility |
|------|----------------|
| `repl.zig` | Interactive REPL loop (`commandLoop`); forks a child process per evaluated expression (`process`/`evaluateRepl`) so a crash or interrupt during evaluation can't take down the session; houses the signal handlers (`reset`, `dieClean`, `fpeError`). |
| `commands.zig` | `/`-command dispatcher, finger/help/stats/editor commands. |
| `startup.zig` | Process entry (`mainEntry`): CLI flag parsing, `.mirarc` reading, editor/library path configuration, the `-exports`/`-sources`/`-make` batch modes, then hands off to `repl.commandLoop`. |
| `lineedit.zig` | Interactive line editing and history (only wired up when stdin is a real TTY; piped/file stdin keeps the plain read path so the golden corpus runs unchanged). |

### `src/io/` — IO and Platform

| File | Responsibility |
|------|----------------|
| `files.zig` | Filesystem helpers: `fileMtime`, `fileExists`, `filecopy`, `makeAbsolute`, … |
| `utf8.zig` | UTF-8 character transcoding. |
| `signals.zig` | POSIX signal registration helpers. |
| `platform.zig` | macOS/Linux abstraction for `stat`/`statx`, thread-local errno, and privilege checks. |

---

## Key Invariants

**G1 — the `core_state.zig` leaf module.** `heap.zig` cannot `@import` a module that itself
imports the driver/compiler layers without creating a cycle. `core_state.zig` holds no
imports from the Miracula source tree for exactly this reason, so `heap.zig` (and
`parser_api.zig`) can reach the small error-sentinel struct it needs without cycling back
through `main.zig`/`startup.zig`.

**No C-ABI linker protocol remains for internal calls.** The historical `extern fn`/
`export fn` pairing used as a module-boundary mechanism (treating the linker as a module
system) is gone — cross-module calls use `@import` directly. `export fn` = 1 (an FFI-only
bridge in `utf8.zig`); `extern var` = 0; `clib.`/`c.` call sites = 0. The remaining
`extern fn` = 13 is the genuine libc/syscall floor in `main_clib.zig`.

**Signal-handler safety is permanent, not a stopgap.** `reset()`, `dieClean()`, and
`fpeError()` in `repl.zig` (plus `sigdefer()` in `dump.zig`) are POSIX signal handlers,
requiring the C calling convention (`callconv(.c)`) and calling `siglongjmp(&rt.rs.env, 1)`
to restore a REPL/batch-mode recovery point. An audit of every `setjmp`/`longjmp` call site
in the codebase (docs/REMAINING_WORK_PLAN.md, Phase 4) found **every** `siglongjmp` call is
signal-handler-triggered — there is no ordinary-control-flow `longjmp` usage anywhere to
replace with Zig error-union propagation. This resolves the question by technical necessity:
POSIX signal handlers are asynchronous and cannot unwind the Zig call stack or propagate an
error union, so `callconv(.c)` = 6 and the `setjmp`/`longjmp` family in `main_clib.zig` are a
permanent floor, not a temporary gap awaiting a rewrite.

**`MiraError` coverage.** `error.TypeCheckAbort` is the only `MiraError` variant currently
wired to Zig error union propagation (in `types.zig`). The remaining variants (`SyntaxError`,
`HeapExhausted`, `LoadError`, `EvaluationInterrupted`) document intent but were deliberately
not converted: surveying the actual `SYNERR`/`errs`/`errline` sentinel usage found `errs`/
`errline` serve two unrelated purposes (a first-syntax-error-location recorder, and an
unconditionally-overwritten current-compile-position breadcrumb used later for runtime error
reporting) — unifying them under a shared error-union path would risk a real behaviour
change, not just encapsulation. See Phase 4 in REMAINING_WORK_PLAN.md for the full survey.

---

## Remaining Modernization Opportunities

See [REMAINING_WORK_PLAN.md](REMAINING_WORK_PLAN.md) for the consolidated, sequenced plan and
current status of every open item. As of this writing:

- **Done:** the mechanical C-ism elimination (Track A), string interning (B1), the spine
  cutover (B2 option (b)), the tracing GC (B3), all six R9 function-splits, and the Phase 4
  error/recovery-model audit (R10-Step 3 / A4b / J2 resolved; J1 and the remaining
  `SYNERR`/`errs`/`errline` sentinel-wrapping deliberately not pursued — see above).
- **Open, deferred by design:** Phase 6 (`SHARED_STATE_PLAN`) — threading `*Interp` through
  the call graph and deleting the global singleton. Large (~2,100 call sites) and only
  valuable if the interpreter needs multiple concurrent instances in one process; not
  required for the current serial, per-function test model.
- **Open, small:** a handful of reducer handlers remain untested (`show`/`MATCH`/`GENSEQ`,
  `TRY`/`FAIL` backtracking) and two pre-existing, unrelated bugs are flagged but not yet
  fixed (a divide-by-zero in `-make`'s failure report on long paths; a crash evaluating
  `system "..."` at the REPL prompt; a dump-cache bug that silently masks a script's syntax
  error on the second run against an unchanged file).
