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

## State: one aggregated `Interp`, owned explicitly (Phase 6, 2026-07-05)

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
```

`main()` owns the interpreter it runs: `src/main.zig` constructs an `Interp` as a local
(`var interp_storage: Interp = .{};`, living for the process's whole run) and points the one
remaining process-wide pointer at it: `current_interp = &interp_storage;`. Every owning
module's singleton is now a function reading through that pointer rather than a `const`
computed against a fixed address, so the ~2,100 pre-existing `owner.singleton.field` access
sites became `owner.singleton().field` (mechanical, but a real rewrite — not something a
`const` could paper over once the backing `Interp` could move):

```zig
// runtime_state.zig
pub inline fn rs() *RuntimeState { return &@import("interp.zig").current_interp.rs; }
// compiler_state.zig
pub inline fn cs() *CompilerState { return &@import("../runtime/interp.zig").current_interp.comp; }
// lex_state.zig
pub inline fn ls() *LexState { return &@import("../runtime/interp.zig").current_interp.lex; }
// core_state.zig
pub inline fn s() *CoreState { return &@import("interp.zig").current_interp.core; }
```

`current_interp` defaults to `&backing`, a real zero-initialized `Interp` living in
`interp.zig` itself — the test binary (`main-tests`) never runs `main()`, so it needs a valid
interpreter from the first access, exactly like the old `pub var interp` singleton provided
one automatically. This means `interp.zig` still holds two module-scope globals
(`backing`, `current_interp`), not the theoretical minimum of one: reaching exactly one would
require `current_interp` to start `undefined`, which is unsafe for any code path that doesn't
run through `main()`'s explicit construction first.

`interp.reset()` (`current_interp.* = .{};`) gives every unit test a pristine interpreter
without relying on ad-hoc per-module re-init — every owner accessor re-reads
`current_interp` at call time, so replacing its pointee (not its address) is enough; no
pointer anywhere goes stale. Only the startup bootstrap infrastructure
(`allocator`/`io`/`gpa`/`environ` in `runtime_state.zig`) sits outside `Interp`, since it is
set once at process start and never reset.

The one genuinely irreducible global left is the *class* `current_interp` belongs to: OS
signal handlers (`dieClean`/`reset`/`fpeError` in `repl.zig`, `sigdefer` in `dump.zig`) are
delivered through the C ABI to a fixed-signature callback that cannot take parameters, so
they read `current_interp`-derived accessors (`rt.rs()`, `core_state.s()`, …) directly rather
than through a threaded parameter — the same exception this document already carved out for
the A4 signal trampoline.

`scripts/scorecard.sh` tracks the scorecard this section describes (the history lived in
the retired `SHARED_STATE_PLAN` document; see git history). Removing the ambient
`current_interp` access pattern entirely is Phase 4 of
[GO_PORT_PLAN.md](GO_PORT_PLAN.md).

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
| `interp.zig` | The `Interp` aggregate struct and `current_interp`, the one process-wide pointer `main()` sets; see "State" above. |
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
| `compiler_state.zig` | `CompilerState` struct — mutable typechecker and translator state. Accessed via `compiler_state.cs()`, which reads through `current_interp.comp`. |
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
| `lex_state.zig` | `LexState` struct — mutable lexer state, accessed via `lex_state.ls()`, which reads through `current_interp.lex`. |
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

**Signal-handler recovery (current state).** `reset()`, `dieClean()`, and
`fpeError()` in `repl.zig` (plus `sigdefer()` in `dump.zig`) are POSIX signal handlers,
requiring the C calling convention (`callconv(.c)`) and calling `siglongjmp(&rt.rs.env, 1)`
to restore a REPL/batch-mode recovery point. Every `siglongjmp` call is
signal-handler-triggered — there is no ordinary-control-flow `longjmp` usage anywhere.
POSIX signal handlers are asynchronous and cannot unwind the Zig call stack or propagate an
error union, so as long as recovery happens *inside the handler*, `setjmp`/`longjmp` must
stay. [GO_PORT_PLAN.md](GO_PORT_PLAN.md) Phase 3 removes the premise instead: handlers
only set an atomic interrupt flag, the reduce loop polls it and returns
`error.EvaluationInterrupted`, and the `setjmp`/`longjmp` family is deleted.

**`MiraError` coverage.** `error.TypeCheckAbort` is the only `MiraError` variant currently
wired to Zig error union propagation (in `types.zig`). The remaining variants (`SyntaxError`,
`HeapExhausted`, `LoadError`, `EvaluationInterrupted`) document intent but were deliberately
not converted: surveying the actual `SYNERR`/`errs`/`errline` sentinel usage found `errs`/
`errline` serve two unrelated purposes (a first-syntax-error-location recorder, and an
unconditionally-overwritten current-compile-position breadcrumb used later for runtime error
reporting) — unifying them under a shared error-union path was judged too risky as an
in-place edit. [GO_PORT_PLAN.md](GO_PORT_PLAN.md) Phase 2 resolves it structurally
instead: the two purposes get two named homes (a `Diagnostics` value and an explicit
`last_position` breadcrumb).

---

## Testing cadence

Four independent gates, each catching a different class of regression; a change is not
considered verified until all four are green (or the failure is a known, already-flagged
pre-existing issue — see below):

1. **Inline unit tests** (`zig build` compiles them in; run the `main-tests` binary directly
   — see the `--listen=-` quirk note below). Verify individual functions in isolation; the
   project convention is one `test` block per function (see the fn-prefixed-name + `Tests:`
   doc-comment convention), tracked by the scorecard's test-per-fn ratio.
2. **Golden corpus** (`zig build test-golden`, `tests/golden/`) — byte-exact stdout/stderr
   for a fixed `.in`/`.m` → `.expected`/`.expected_err` corpus, regenerated with
   `zig build generate-golden` and reviewed before committing. This is the primary
   behaviour-preservation gate for the [GO_PORT_PLAN.md](GO_PORT_PLAN.md) phases: a
   phase's golden diff should be empty (or, for a deliberate bug fix, a reviewed,
   intentional change to exactly the affected case). Phase 0 of that plan added coverage
   for literate scripts, `%insert`, and lexer error wording ahead of Phase 1's front-end
   rewrite; `%include`/`%export`/`%free` fixtures (`directive_include`/
   `directive_include_alias`/`directive_export_scope`/`directive_free`) were left
   deliberately unpinned until the library mechanism was actually implemented
   (Phase 1 step 5's "harder half" — pinning "feature absent" isn't useful), then pinned
   once real (2026-07-06, see [GO_PORT_PLAN.md](GO_PORT_PLAN.md)).
3. **C-differential regression** (`zig build test-regression`, `tests/regression.zig`) —
   runs the same inputs through both `./mira_original` (a separately built reference C
   Miranda, not part of this repo) and the Zig binary, comparing stdout/stderr and the
   `-count` reduction/GC statistics exactly. Skips gracefully (exit 0) when
   `./mira_original` isn't present, which is the case in most dev/CI sandboxes today — the
   test cases are still maintained (extended in Phase 0 to cover the same new surfaces as
   the golden corpus) so the coverage is ready whenever a reference binary is available.
4. **Integration suites** — `test-sigint` (SIGINT recovery), `test-spine` (differential
   stress-testing the reduction spine), `test-smoke` (REPL smoke tests). Each is a plain
   executable run via `addRunArtifact`, not the `zig build test` protocol, so they don't hit
   the quirk below.

**The `--listen=-` quirk.** `zig build test`/`zig build check`/`zig build strict` drive the
`addTest`-based binaries (`main-tests`, `parser-tests`, `mira-tests`, `utf8-tests`,
`just-tests`, `menudriver-tests`) through Zig's test-server IPC protocol
(`--listen=-`). In this project's sandboxed dev environment that protocol has been observed
to hang indefinitely (zero CPU, no output) well after the binary itself has finished
compiling and would otherwise run in milliseconds — a build-harness/environment
interaction, not a test failure. When `zig build check`/`test` appears stuck, kill it and
verify directly instead: `find .zig-cache -name main-tests -type f -perm +111` (take the
one with the newest mtime) and run it with no arguments — it prints `All N tests passed.`
on success. `zig build test-golden`/`test-regression`/`test-sigint`/`test-spine`/`test-smoke`
are unaffected (plain executables, not `addTest`) and can be run directly as normal build
steps.

**Ratchet.** `scripts/scorecard.sh` (`--check` against `scripts/scorecard.baseline`,
`--update-baseline` to record improvement) tracks every C-ism/shared-state/structure metric
this document and [GO_PORT_PLAN.md](GO_PORT_PLAN.md) discuss — see that plan's Phase 0
for the full metric list. It fails the build if a tracked count rises.

---

## Remaining Modernization Opportunities

See [GO_PORT_PLAN.md](GO_PORT_PLAN.md) for the current plan (it supersedes the
retired REMAINING_WORK_PLAN / SHARED_STATE_PLAN / REDESIGN_DATA_MODEL documents). As of
this writing:

- **Done:** the mechanical C-ism elimination (Track A), string interning (B1), the spine
  cutover (B2 option (b)), the tracing GC (B3), all six R9 function-splits, the Phase 4
  error/recovery-model audit (R10-Step 3 / A4b / J2 resolved; J1 and the remaining
  `SYNERR`/`errs`/`errline` sentinel-wrapping deliberately not pursued — see above), and
  the shared-state consolidation — every owner-module singleton now reads through
  `current_interp`, `main()` constructs the `Interp` it runs explicitly, and the ~2,100
  call sites across the codebase were rewritten accordingly (see "State" above).
- **Open, small:** the line-editor subsystem (`driver/lineedit.zig`) and a handful of
  test-only initialization guards still hold their own module-scope state rather than
  living in `Interp` (tracked by `scripts/scorecard.sh`).
- **Open, small:** a handful of reducer handlers remain untested (`show`/`MATCH`/`GENSEQ`,
  `TRY`/`FAIL` backtracking) and several pre-existing, unrelated bugs are flagged but not
  yet fixed (a divide-by-zero in `-make`'s failure report on long paths; a crash evaluating
  `system "..."` at the REPL prompt; a dump-cache bug that silently masks a script's syntax
  error on the second run against an unchanged file; an off-by-one that reports line 0
  instead of line 1 for a syntax error on a script's first line, `tests/golden/script_syntax_err`).
- **Done:** `%include`/`%export`/`%free` (the Miranda library mechanism, manual §27) —
  implemented against the native front end (`semantics/modules.zig`'s `processIncludes`,
  wired into `parser_api.zig`), not the legacy pipeline (which never wired these up end to
  end at all — `codegen.zig:808` no-oped all three AST node kinds, and `lex_bridge.zig`
  dropped the `%include` pathname payload so even a bare `%include "x"` failed to parse;
  reproduced on the shipped `miralib/ex/polish.m` example on a clean `main` checkout before
  this work). See [GO_PORT_PLAN.md](GO_PORT_PLAN.md) Phase 1 step 5 for the design and
  the two real bugs found landing it.
