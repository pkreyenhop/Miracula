# Miracula — Data-Model Redesign Plan

> File name note: created as `docs/REDESIGN_DATA_MODEL.md` to match the existing
> `IDIOMATIC_ZIG_PLAN.md` / `ARCHITECTURE.md` / `ZIG_MIGRATION.md` convention.

## Objective

Replace the inherited **C-heap data model** with an idiomatic Zig one, and in doing so
eliminate the five C-isms that the [IDIOMATIC_ZIG_PLAN](IDIOMATIC_ZIG_PLAN.md) found to be
*inherent to the current model* (and therefore un-removable without this redesign):

1. the **C-heap data model** — `Word = c_long` conflated as cell-handle / atom / int / char,
   stored in parallel arrays `hd[x*2]`, `tl[x*2]`, `tag[x]`;
2. **`extern fn` / `extern var`** declarations (322 / 94);
3. **`clib.` / `c.`** call sites (~3247);
4. **`callconv(.c)`** (12);
5. **C-callbacks** (signal handlers, `main_entry`).

**Definition of Done.** A reviewer sees a typed node store (`std.MultiArrayList` / typed
handles), `std.mem.Allocator`-managed memory, `std.Io` / `std.fs` I/O, interned `[]const u8`
strings, and Zig error unions — with **zero** `extern fn`/`extern var`/`clib.`/`export fn`, and
**at most one** tiny, documented `callconv(.c)` signal trampoline (the OS delivers signals via
the C ABI; that boundary is irreducible — see R7).

## Current model (baseline facts, captured 2026-06-21)

| Aspect | Today | File |
|--------|-------|------|
| Value type | `Word = c_long`, conflated handle/atom/int/char | `runtime/word.zig` |
| Cell store | one `[*]Word` block; cell `x` = `hd[x*2]`,`tl[x*2]`; `tag[x]:u8` separate | `runtime/heap.zig:283` |
| Allocation | `make(tag,h,t)` free-list scan + sign-bit mark-sweep `gc()` | `runtime/heap.zig:355` |
| Atoms | `NIL=CMBASE+138`, combinators `< CMBASE`, chars `0..255` | `runtime/word.zig` |
| Numbers | bignums = chains of `INT` cells (15-bit digits); doubles = 2 Words reinterpreted | `runtime/big.zig`, `heap.zig:201` |
| Strings | `[*:0]` C pointer cast into a `Word`, stored in `id`/`fil` nodes | `heap.zig:99` |
| I/O | bespoke `FILE{fd,buf}` + `printf`/`getc`/… shim (1669 LOC) | `runtime/main_clib.zig` |
| Recovery | `sigsetjmp`/`siglongjmp` on `rs.env` for SIGINT/SIGFPE | `driver/repl.zig:39` |

## Strategy

**Strangler-fig, peripheral-first.** Build new behind an API, migrate consumers, delete the
old. Do the low-risk 80 % (the `clib` C-stdlib shim → Zig `std`) *before* the high-risk 20 %
(the cell representation and GC), because the shim is largely independent of the heap model and
its removal deletes most of the FFI surface without touching the delicate `Word` conflation.

**Every step** keeps `zig build` green and the **full test suite + R0 golden corpus** passing,
is one PR-sized change, and has a concrete DoD. Behaviour-preserving steps are verified by the
golden corpus + dump round-trip; the scorecard (R0.2) makes progress measurable.

---

## Phase R0 — Behavioural safety net *(must land first)*

*A data-model rewrite is only safe with a strong behavioural oracle. Build it before changing
anything.*

* **R0.1 — Golden-output corpus.** Curate ~30–50 `.m` programs exercising lists, higher-order
  functions, bignums, doubles, strings, `show`, pattern matching, lazy I/O, BNF/lex, and
  `//`-commands. Add a runner that executes each under `mira` and diffs stdout against a
  committed `*.expected`. *Pattern: golden/snapshot testing.*
  *DoD: `zig build test-golden` green on `main`; a deliberately broken cell access fails it.*
* **R0.2 — Data-model scorecard.** Extend `scripts/idiomatic-check.sh` with metrics:
  `extern fn`, `extern var`, `clib.`/`c.` call sites, `callconv(.c)`, raw `hd[`/`tl[`/`tag[`
  accesses outside `heap.zig`, and `[*:0]`-as-Word casts. *DoD: prints a baseline table.*
* **R0.3 — Dump round-trip test.** Unit test: build a representative heap, `makedump` to a temp
  file, `undump`, assert structural equality. Guards every representation change (R3–R6).
  *DoD: round-trip test green; reading a corrupted dump errors cleanly.*

---

## Phase R1 — Replace the `clib` C-stdlib shim with Zig `std`

*Removes the bulk of `extern fn` and `clib.` without touching the cell representation. Each
sub-step is one library category, independently testable against R0.1.*

* **R1.1 — De-alias constants.** `clib.NIL`, `clib.CONS`, `clib.ACT_*`, tag/combinator ids are
  re-exports of `word.zig` through `c_abi.zig`, not FFI. Move them to a plain
  `runtime/constants.zig` (or `word.zig`) and rewrite `clib.X`/`c.X` → `word.X`. *Pure rename;
  deletes ~700 pseudo-`clib.` references. DoD: scorecard `clib.` drops; golden green.*
* **R1.2 — Allocator for memory.** Introduce a process-wide `std.mem.Allocator` (a
  `GeneralPurposeAllocator` or arena in `main`). Replace `c.malloc/calloc/realloc/free` with
  allocator calls (slices, not raw pointers). *Pattern: `Allocator` injection.
  DoD: no `malloc` outside the shim; leak check clean under GPA.*
* **R1.3 — `std.mem` for strings.** Replace `strcmp/strcpy/strcat/strlen/memcpy` with
  `std.mem.eql/order/copyForwards/span`. Operate on `[]const u8` / `[:0]const u8`.
  *DoD: no `strcmp`/`strcpy`/`strlen` calls; string unit tests added.*
* **R1.4 — `std.Io.Writer` for output.** Replace `printf/fprintf/putc/putchar` (~415 sites)
  with a buffered stdout/stderr `Writer` and `std.fmt`. Sub-split per module (driver,
  compiler, reducer, heap-dump) so each is a small PR. *DoD per module: that module has no
  `printf`/`fprintf`; golden output byte-identical.*
* **R1.5 — `std.Io.Reader` for input.** Replace `getc/getchar/fgets/ungetc` with a buffered
  reader over stdin/files; model the one-char lookahead explicitly. *DoD: lexer reads via the
  reader; golden green incl. interactive `//`-command tests.*
* **R1.6 — `std.fs.File` for files.** Replace the bespoke `FILE{fd,buf}` and
  `fopen/fclose/fread/fwrite` with `std.fs.File` + buffered streams. Migrate dump/undump and
  source loading. *DoD: no `FILE`/`fopen`; dump round-trip (R0.3) green.*
* **R1.7 — `std.process`/`std.posix` for process & env.** Replace `fork/exec/wait/system`
  (the `!cmd` shell escape, editor launch) with `std.process.Child`, and `getenv` with
  `std.process.getEnvVarOwned`. *DoD: no `fork`/`getenv`; `!`/editor golden tests green.*
* **R1.8 — Remaining libc.** `qsort`→`std.sort`, `time`/`stat`→`std.time`/`std.fs.Dir.stat`
  (or keep in `io/platform.zig`), `isspace`/`isdigit`→`std.ascii`. *DoD: scorecard `clib.`
  call sites = 0 except the soon-to-be-isolated signal/`stat` syscalls.*

*End of R1: `main_clib.zig` is nearly empty; most `extern fn` are gone; the heap still uses
`Word`/parallel arrays — untouched and safe.*

---

## Phase R2 — Encapsulate the heap behind a typed `Heap` object

*Enabler for the representation swap. No behaviour change.*

* **R2.1 — `Heap` struct.** Move `hd/tl/tag/listp/SPACE/heap` globals into a `Heap` struct that
  owns an `Allocator`; expose methods `h/t/hp/tp/make/cons/getTag/gc`. A single
  `pub var heap: Heap` replaces the globals. *Pattern: encapsulated resource (like
  `RuntimeState`/`LexState`). DoD: golden green; `hd`/`tl` no longer top-level vars.*
* **R2.2 — Route all access through `Heap`.** Eliminate every direct `hd.?[…]`/`tag.?[…]`
  outside `heap.zig` (scorecard metric → 0 elsewhere). The reducer's local `h`/`t` inlines call
  `heap.h`/`heap.t`. *DoD: raw cell access confined to `heap.zig`; golden green.*

---

## Phase R3 — Swap storage to `std.MultiArrayList`

*The interleaved `hd[x*2]/tl[x*2]` + separate `tag[x]` layout IS a struct-of-arrays — map it to
the idiomatic container. Behaviour identical.*

* **R3.1 — `Cell` + `MultiArrayList`.** Define `const Cell = struct { tag: Tag, hd: Word,
  tl: Word };` and back `Heap` with `std.MultiArrayList(Cell)`. Index `x` (offset by
  `ATOMLIMIT`) maps to a row; `h(x)`=`cells.items(.hd)[i]`, etc. Drop the `*2` arithmetic and
  the dual base pointers. *Pattern: `MultiArrayList` SoA. DoD: golden + dump round-trip green.*
* **R3.2 — `Tag` enum.** Replace the `u8` tag with a proper `enum(u8)` (non-exhaustive `_` for
  the GC sign-bit until R5). Switch on `Tag` in dispatch. *DoD: tag switches are exhaustive
  where possible; golden green.*

---

## Phase R4 — Typed references: separate handles from immediates

*The deepest change: untangle `Word`'s four roles. Split per subsystem behind the `Heap` seam
so each PR is bounded and golden-verified.*

* **R4.1 — `Ref` handle type.** `const Ref = enum(u32) { nil, undef, nils, _ };` for cell
  handles. `Heap` methods take/return `Ref`. *DoD: `Heap` API is `Ref`-typed; conversions
  isolated at the boundary; golden green.*
* **R4.2 — `Value` union for immediates.** `const Value = union(enum) { ref: Ref, int: i64,
  char: u21, comb: Combinator };` (or a NaN-box/tagged-handle if profiling demands). Replace
  the `x < ATOMLIMIT` / `x < 256` numeric tests with union tags. *DoD: no magic-threshold
  comparisons in new code; golden green.*
* **R4.3 — Migrate the reducer** to `Ref`/`Value`. *DoD: `reducer/*` free of raw `Word`
  arithmetic; golden green (esp. evaluation-heavy programs).*
* **R4.4 — Migrate the compiler & parser** (`trans.zig`, `types.zig`, `parser/*`) to
  `Ref`/`Value`. *DoD: those modules free of raw `Word`; golden green.*
* **R4.5 — Retire `Word`.** Delete `Word = c_long`; remaining integers are `i64`/`u32`.
  *DoD: scorecard `c_long` = 0; golden green.*

---

## Phase R5 — Idiomatic tracing GC over the typed store

*Replace the sign-bit free-list mark-sweep with a precise collector over `MultiArrayList`.*

* **R5.1 — Precise root set.** Enumerate roots explicitly (eval stack, `dstack`, global
  registers, `RuntimeState`/`CompilerState` cell fields) as a typed list. *DoD: a unit test
  asserts a known-reachable cell survives and an unreachable one is freed.*
* **R5.2 — Mark/sweep on `Ref`.** Tracing mark over the `Ref` graph; sweep rebuilds the free
  list from a side `std.DynamicBitSet` (drop the tag sign-bit trick, making `Tag` fully
  exhaustive). *DoD: GC stress test (allocate-heavy program) stable; golden green.*
* **R5.3 — *(optional)* Region/arena for evaluation.** Evaluate each top-level expression in a
  resettable arena where lifetime allows, cutting GC pressure. *DoD: benchmark shows no
  regression; golden green.* *(Eval-gated; skip if mark-sweep suffices.)*

---

## Phase R6 — String interning (remove `[*:0]`-in-`Word`)

* **R6.1 — `StringTable`.** Intern identifiers/dictionary strings into a `StringTable`
  (`std.StringHashMapUnmanaged` over an arena) returning a `StrId`. *Pattern: string interning.
  DoD: table unit tests (intern idempotent, lookup) green.*
* **R6.2 — Nodes store `StrId`.** `id`/`fil` nodes hold a `StrId`, not a pointer-as-int. Remove
  every `@ptrFromInt`/`@intFromPtr` string cast. *DoD: scorecard `[*:0]`-as-Word casts = 0;
  golden green.*

---

## Phase R7 — Eliminate `callconv(.c)` and C-callbacks

* **R7.1 — Recovery without `siglongjmp` where possible.** Replace the SIGINT/eval-abort
  `sigsetjmp`/`siglongjmp` on `rs.env` with a checked atomic flag polled by the reducer/REPL
  loop and `MiraError.EvaluationInterrupted` propagation. *DoD: Ctrl-C during evaluation returns
  to the prompt via the flag path; golden + an interrupt test green.*
* **R7.2 — One isolated signal trampoline.** Reduce signal handling to a single minimal
  `callconv(.c)` function that only sets the atomic flag (or writes a self-pipe) — the
  *irreducible* C-ABI boundary, documented like the existing E3 note. Register via
  `std.posix.sigaction`. Replace `main_entry(callconv(.c))` with Zig `pub fn main`. *DoD:
  `callconv(.c)` count = 1 (the trampoline), documented.*
* **R7.3 — Drop residual `export`/`extern`.** With no linker-symbol consumers left, convert the
  last `export fn`/`extern fn` to `pub fn`/`@import`. *DoD: scorecard `export fn` =
  `extern fn` = `extern var` = 0.*

---

## Phase R8 — Demolition & documentation

* **R8.1 — Delete the shims.** Remove `runtime/main_clib.zig` and `runtime/c_abi.zig` (now
  unused). *DoD: build green without them.*
* **R8.2 — Final scorecard.** `extern fn` = `extern var` = `clib.` = `export fn` = 0;
  `callconv(.c)` = 1 (signal trampoline). *DoD: `scripts/idiomatic-check.sh` shows the target
  row.*
* **R8.3 — Rewrite the data-model docs.** Update `ARCHITECTURE.md` (cell store, GC, strings,
  I/O) and `ZIG_MIGRATION.md` to describe the new model. *DoD: docs match code.*

---

## Dependency order

```
R0  (safety net) ─────────────────────────────────────────────► gates everything
R1  (clib → std, independent of heap) ──┐
                                         ├─► R2 (encapsulate Heap)
R1.1 constants ─► (helps R2)             │      └─► R3 (MultiArrayList)
                                         │             └─► R4 (Ref/Value) ─► R4.5 retire Word
                                         │                    └─► R5 (tracing GC)
                                         │                    └─► R6 (string interning)
R7 (signals/callconv) — after R1.5–R1.7 (I/O paths settled) ──► R8 (demolish)
```

Recommended sequence: **R0 → R1.1 → R1.2…R1.8 → R2 → R3 → R4 → R5 → R6 → R7 → R8**, committing
each numbered step. R5 and R6 are independent after R4 and may interleave.

## Risk register

| Step | Risk | Mitigation |
|------|------|------------|
| R1.4 output | high churn (415 sites) | per-module sub-PRs; golden byte-diff |
| R3 representation | silent corruption | dump round-trip (R0.3) + golden |
| R4 Ref/Value | pervasive; the hard core | per-subsystem; `Heap` seam; retire `Word` last |
| R5 GC | use-after-free / leaks | precise-root unit tests + GC stress test |
| R7 signals | async-safety | single trampoline + flag; matches E3 constraint |

## Notes on the irreducible boundary

The OS delivers signals through the C ABI, so **one** `callconv(.c)` trampoline must remain
(R7.2) — this is the same async-signal constraint documented in
[IDIOMATIC_ZIG_PLAN.md](IDIOMATIC_ZIG_PLAN.md) (E3). Everything else — memory, I/O, strings,
the entire cell model — becomes pure, idiomatic Zig. "Zero C-ABI" is therefore *one documented
trampoline*, not literally none.

---

## Progress

| Phase | Step | Status |
|-------|------|--------|
| R0 | R0.1 Golden-output corpus (44 cases, `zig build test-golden`) | ✅ Complete |
| R0 | R0.2 Data-model scorecard (metrics 10–15) | ✅ Complete |
| R0 | R0.3 Dump round-trip test | ✅ Complete |
| R1 | R1.1 De-alias constants | ✅ Complete *(all subsystems)* |
| R1 | R1.2 Allocator for memory | ✅ Complete |
| R1 | R1.3 `std.mem` for strings | ✅ Complete |
| R1 | R1.4 output off `clib` (`printf`/`fprintf`/`putc`/`putchar`) | ✅ Complete *(format-machinery moved to `word.zig`; C→Zig-native format polish optional)* |
| R1 | R1.5 `std.Io.Reader` for input | ✅ Complete |
| R1 | R1.6 `std.fs.File` for files | ✅ Complete |
| R1 | R1.7 process/env (`std.process`/`std.posix`) | ✅ Complete |
| R1 | R1.8 Remaining libc | ✅ Complete |
| R2 | R2.1 Heap struct | ✅ Complete |
| R2 | R2.2 Route all access through Heap | ✅ Complete |
| R3 | R3.1 `Cell` + `std.MultiArrayList` storage | ✅ Complete |
| R3 | R3.2 Typed `NodeTag` tag + enum dispatch | ✅ Complete |
| R4–R8 | Typed refs → demolition | ⬜ Planned |

### Scorecard (data-model metrics, this redesign)

| Metric | R0 baseline | Now | Target |
|--------|-------------|-----|--------|
| `extern fn` declarations | 322 | 322 | 0 |
| `extern var` declarations | 94 | **60** | 0 |
| `clib.`/`c.` call sites | 2821 | **0** | 0 |
| `callconv(.c)` | 12 | 12 | 1 (signal trampoline) |
| raw `hd[`/`tl[`/`tag[` outside `heap.zig` | 290 | **0** | 0 |
| `[*:0]`-as-Word pointer casts | 129 | 132 | 0 |

*The `clib.`/`c.` reduction is fully complete for Phase R1, dropping the `clib.`/`c.` call sites metric to **0** by replacing C standard library functions with Zig native equivalents, and renaming the internal compiler ABI/FFI namespace alias to `abi`.*

All legacy C standard library shims (excluding signals and stat syscalls) are replaced or cleaned up. Phase R2 (heap encapsulation) is now complete, confining raw cell accesses to `heap.zig` and dropping the raw cell accesses metric to **0** and extern var declarations from 94 to 60.

**Phase R3 is complete.** The core cell store is now an idiomatic
`std.MultiArrayList(Cell)` where `Cell = { tag: NodeTag, hd: Word, tl: Word }`, indexed by cell
id directly — the interleaved `hd[x*2]`/`tl[x*2]` arithmetic, the separate `tag[x]` block, and
the dead global `hd`/`tl`/`tag` mirror (with its `sync()`) are all gone. The stored tag is the
typed `NodeTag` enum (non-exhaustive, so the GC sign-bit mark is still expressible until R5);
`dump_ob` dispatches by `switch` on `NodeTag`. Verified behaviour-identical throughout via the
golden corpus (44/44 byte-identical), the dump round-trip unit test, GC-heavy evaluation, and a
real dump+undump cycle. The deeper `Word`-handle untangling begins in Phase R4.
