# Miracula — Shared-State Elimination Plan

> A phased plan to remove implicit global mutable state, turning the interpreter
> into an explicit, injectable `Interp` value. Finishes the goal that
> [IDIOMATIC_ZIG_PLAN](IDIOMATIC_ZIG_PLAN.md) *Cluster B* opened ("Eliminate
> implicit global state") but left at the consolidation stage. Companion to
> [REDESIGN_DATA_MODEL](REDESIGN_DATA_MODEL.md) (the value/heap representation),
> which is largely orthogonal but complementary (B3's precise GC roots want an
> `Interp`-owned root set).

## Objective

Today the interpreter *is* a process-global singleton. Replace it with an
explicit `Interp` struct that **owns** all interpreter state, is **injectable**
(so callers/tests construct independent instances), and carries **no
module-scope mutable globals** — except a single documented `*Interp` pointer for
OS signal delivery (signals arrive on the C ABI and cannot take a parameter,
exactly the irreducible boundary noted for the A4 trampoline).

### Why (motivation)

* **Test isolation.** The concrete pain: `reducer/reduce_test.zig` could not use
  the full `mira_setup()` because its global mutations corrupted the
  order-sensitive parser snapshot tests; it had to fall back to a minimal,
  hand-picked setup. Every test that touches interpreter state is fragile for
  the same reason. An injectable `Interp` makes each test construct a fresh,
  private instance.
* **Re-entrancy / multiple instances.** Embedding the interpreter, evaluating
  two programs, or running the type-checker beside a reducer are all impossible
  while state is global.
* **Reasoning & ownership.** Explicit ownership replaces "who mutated `rs.X`?"
  with a value you can see, pass, and `deinit`.

### Definition of Done *(end state)*

A reviewer sees `var interp = Interp.init(gpa); defer interp.deinit();` in
`main()`, every subsystem reaching its state through `self: *Interp` (or a
threaded `*Interp`), **zero** module-scope mutable `var`/`export var` in non-FFI
code save one `current_interp: *Interp` used only by signal handlers (documented).
`zig build` green and the **golden corpus byte-identical** at every step.

---

## Where things stand (inventory, 2026-06-23)

Measured over `src` (excluding `src/tools/` and the FFI shims):

| State | Form today | Owner | Access sites |
|-------|-----------|-------|--------------|
| `RuntimeState` | ✅ struct, singleton `rs` | `runtime_state.zig` | **~675** (`rs.*`) |
| `LexState` | ✅ struct, singleton `ls` | `lex_state.zig` | **~818** (`ls.*`) |
| `Heap` | ✅ struct, singleton `heap` | `heap.zig` | **~432** (`heap.*`) |
| `CompilerState` | ✅ struct, singleton `cs` | `compiler_state.zig` | (typecheck) |
| allocator / io / environ / gpa | ⬜ 4 loose globals | `runtime_state.zig` | ~25 |
| core/error state | ⬜ **8 loose `export var`** (`nill`, `loading`, `compiling`, `errs`, `errline`, `obsuffix`, `SYNERR`, `commandmode`) | `core_state.zig` | **~148** |
| heap/GC/dict scratch | ⬜ **~16 loose `export var`** (`SPACE`, `listp`, `files`, `current_file`, `cellcount`, `claims`, `nogcs`, `dstack`, `stackp`, `collecting`, `dlim`, `prefix`, `preflen`, `PNBASE`, `CFN`, `charname_buffer`) | `heap.zig` | — |
| reducer/eval state | ⬜ **6 loose `export var`** (`stdinuse`, `outfilq`, `waiting`, `s_out`, `errtrap`, `cycles`) | `reduce.zig` | — |
| I/O (`FILE` pool, std streams, writers) | ⬜ ~10 loose globals | `word.zig` | — |
| bignum constants | ⬜ `big_one`, `logIBASE`, `log10IBASE`, … | `big.zig` | — |
| interned strings | ✅ struct-ish, module-global `table` | `strtab.zig` | — |

**Totals (`scripts/shared-state-check.sh`, 2026-06-23):** **92** column-0 mutable
globals (35 gratuitous `export var`); 4 already-grouped singleton structs;
**~2,100 singleton access sites** (`ls`/`rs`/`heap`/`core_state`). The
consolidation half (group → struct) is *partly* done (B1/B2 of the idiomatic
plan); the **de-globalization** half is entirely open and is where the value is.

> **Key enabler (from Track A2).** Almost all access already routes through the
> *owner module* (`main.rs.X` → `rt.rs.X`, `heap.h(...)`, `ls.X`), not via stray
> `extern var`. That means re-pointing an owner's singleton at an `Interp` field
> (Phase 3) is a localized change, **not** a 2,100-site edit — only Phase 5
> (true threading) touches call sites en masse.

---

## Strategy

Strangler-fig, **byte-identical golden at every step**, each step PR-sized with a
concrete DoD. The phases are ordered so that **value lands early**: the
test-isolation win arrives at Phase 4, *before* the expensive threading of
Phase 5 — so the plan can stop after Phase 4 with most of the benefit if the
full threading is judged not worth its churn.

Two independent halves:

* **Consolidate (Phases 1–3, mechanical/bounded):** strip the C-ABI `export`,
  fold every loose global into an owner struct, then aggregate the owner
  singletons into one `Interp`. Low risk, golden-gated.
* **De-globalize (Phases 4–6, design-bearing):** make `Interp` injectable, then
  thread it and delete the global. Phase 5 is the large one.

---

## Phases

### Phase 0 — Inventory, metric, safety net *(no code change)* ✅
* The inventory table above is the baseline.
* **Metric:** `scripts/shared-state-check.sh` counts *non-FFI module-scope mutable
  globals* (column-0 `var`/`pub var`/`export var`). **Baseline = 92** (of which
  **35** are gratuitous `export var` — Phase 1's target); end target **1** (the
  signal pointer). Run with `-v` to list every site.
* **Safety net:** verified green at baseline — `zig build` + golden **44/44** +
  unit suite **42/42**. An `Interp`-isolation test is added in Phase 4 as the
  proof object.
* *DoD: ✅ this document + `scripts/shared-state-check.sh` reporting the baseline,
  with the corpus green.*

### Phase 1 — Strip gratuitous `export var` → `var` *(mechanical, low-risk)* ✅
The loose globals were mostly `pub export var` — C-port leftovers. This is a
pure-Zig binary with no external linker consumers (established by Track A2/A3,
which drove `extern var` → 0 and `export fn` → 3), so `export` was gratuitous and
also *blocked* moving these into struct fields. Converted `export var` → `var`
across 8 files (`heap`/`reduce`/`core_state`/`big`/`dump`/`version`/`combinator`/
`setup`), keeping the owner-module access pattern; removed the stale
`extern var`/`export var` bridge comments in `main.zig`/`core_state.zig`.
* *DoD: ✅ non-FFI `export var` **35 → 0**; golden 44/44 byte-identical; tests 42/42.*

### Phase 2 — Group the remaining loose globals into owner structs *(encapsulation; per-module, each its own PR)* — ◐ **4 of 5 done**
Mirror the existing `RuntimeState`/`CompilerState` pattern. No threading yet —
each becomes a field of a single module-owned struct singleton.
* **2a `CoreState`** ✅ — wrapped `core_state.zig`'s 8 vars into `CoreState` +
  singleton `core_state.s`; 148 sites (`core_state.X` + the `core.X` alias) → `.s.X`.
* **2c `IoState`** ✅ — consolidated `word.zig`'s scattered I/O globals (writer
  caches + buffers, the 3 std `FILE` streams, the `FILE` pool) into `IoState` +
  `word.fio`.
* **2d `EvalState`** ✅ — grouped `reduce.zig`'s `stdinuse`/`outfilq`/`waiting`/
  `s_out`/`errtrap`/`cycles` into `EvalState` + `reduce.ev`.
* **2e `Bignum`** ✅ — grouped `big.zig`'s `logIBASE`/`log10IBASE`/`big_one`/`b_rem`
  into `Bignum` + `big.bn` (`@log` isn't comptime, so the caches stay runtime); also
  deleted the **dead** module-level `SPACE`/`listp` duplicates in `heap.zig`.
* **2b `Heap` absorbs its scratch** ✅ — moved the 14 heap/GC/dictionary scratch
  globals (`files`/`current_file`/`cellcount`/`claims`/`nogcs`/`dstack`/`stackp`/
  `collecting`/`dlim`/`prefix`/`preflen`/`PNBASE`/`CFN`/`charname_buffer`) into the
  `Heap` struct. Post-Phase-3 this became a *uniform* rename after all: `heap` is
  now `&interp.heap` (one instance), so bare `X → heap.X` is correct in both
  methods (`heap.X == self.X`) and free functions; external `heap.X → heap.heap.X`.
* *Plus (beyond the original Phase-2 list, to complete `reset()` coverage):*
  **`strtab` folded into `interp`** (lazily-initialised `StringTable` field) and
  **`lex.zig`'s 16 session globals folded into `LexState`** (`prefix`/`prefixbase`/
  `inprelude`/…). So `interp.reset()` now wipes essentially all interpreter state.
* *DoD: all module loose globals → 0; golden green. Progress: **92 → 28** globals
  (the rest are bootstrap infra in `runtime_state` + small file-private state in
  `commands`/`startup`/`dump`/`version`).*

### Phase 3 — Aggregate the singletons into one `Interp` *(still global; transitional)* ✅
**Done.** `src/runtime/interp.zig` defines `Interp` holding the 8 interpreter-state
structs by value (`rs`/`heap`/`lex`/`comp`/`core`/`io`/`eval`/`big`) and the single
global `interp`. Each owner module's `pub var <singleton>` became
`pub const <singleton> = &@import("interp.zig").interp.<field>`, so the ~2,100
`owner.singleton.field` access sites are unchanged (they now read/write through
`interp`); the only edits were the 8 redirects + dropping `&` from the 19
`&lex_state.ls`/`&compiler_state.cs`/`&rt.rs` alias sites. The owner↔interp circular
imports compiled cleanly (no comptime size cycle, as predicted). golden 44/44
byte-identical, tests 42/42. Metric **66 → 59** (8 `var` singletons → 1 `interp`
var + 8 `const` aliases).

*Residual (deliberately out of this phase):* the bootstrap infra
(`gpa`/`allocator`/`io`/`environ` in `runtime_state.zig`), the interned `strtab`
table, and heap's still-loose scratch (2b) remain separate globals — they fold in
with 2b / a follow-up. The *interpreter state* is now one aggregate, which is what
Phase 4 (injectable) needs.

Original sketch:
```zig
pub const Interp = struct {
    gpa: std.heap.DebugAllocator(.{}) = .{},
    allocator: std.mem.Allocator,
    io: std.Io,
    environ: std.process.Environ = .empty,
    heap: Heap = .{},
    lex: LexState = .{},
    rs: RuntimeState = .{},
    core: CoreState = .{},
    comp: CompilerState = .{},
    files: IoState = .{},
    eval: EvalState = .{},
    big: Bignum = .{},
    strtab: StringTable = .{},
};
```
Replace the N global singletons with **one** transitional `pub var interp: Interp`
and re-point each owner module at its field (`pub const rs = &interp.rs`,
`heap` → `&interp.heap`, `ls` → `&interp.lex`, …). Because access goes through
the owners (A2), call sites are untouched.
* *DoD: exactly one global state aggregate; golden green.*

### Phase 4 — Make `Interp` injectable *(the test-isolation payoff)* ✅ **done**
`interp.reset()` is the injection primitive the pre-threading architecture allows:
it returns the global to a pristine `Interp` (the owner pointers keep their
addresses, only the value is replaced), so a test can start from a clean slate.
A focused test (`reduce_test`'s *"interp.reset clears the aggregated state
structs"*) proves it. **The payoff is delivered:** `reduce_test` now runs the full
`mira_setup()` (the heavyweight init that used to pollute the order-sensitive
parser snapshot tests) — the minimal-setup workaround is gone — and the suite
stays green. Suite **43/43**, golden 44/44.

**Finding (the isolation chase, and where it stands).** Truly independent
instances need *threading* (`*Interp`, Phase 5) — every access still reads the
global. `reset()`'s *coverage* has since been completed: 2b (heap scratch),
`strtab`, and `lex.zig`'s session globals are all folded into `interp`, so a
`reset()` now wipes essentially all interpreter state. **Yet the full
`mira_setup`-through-`reduce_test` isolation still failed**, peeling back one
residual at a time:
  1. heap scratch unreset → *(fixed by 2b)*;
  2. `strtab` unreset → *(fixed by the fold)*;
  3. lexer `prefix`/`inprelude` unreset → *(fixed by the `LexState` fold; this
     one also needed `setupheap`/`setupdic` to precede `reset_state` in the test,
     since `reset()` nulls `prefixbase`)*;
  4. *recursion* snapshot drops the first identifier's text after a second
     `reset()` → **root-caused, then fixed:** *not an interpreter bug.* The parser
     snapshot tests captured each token's "lexeme" by reading `ls.dicp` (the
     dictionary buffer) *after* `yylex` — but `dicp` lags, and for the first token
     of a freshly-set-up dictionary it points at **uninitialised dic memory**
     (instrumented: `dic="fact\0"`, `dicp=dic+5`, lexeme = 99 KB of garbage that
     the test's ASCII filter silently drops). The recorded snapshots only held
     while the dictionary **persisted across tests**; `reset()` correctly gives a
     fresh dic, exposing the fragility (`EQUALS("0")`, `NAME("e")` were lagging
     artifacts, not real token text). **Fix:** capture the identifier text from the
     interned id node (`ls.yylval`), not `dicp`, and regenerate the 15 snapshots
     (now `NAME("square")`/`NAME("fact")`/…). The capture is now
     isolation-independent, so `reduce_test` runs full `mira_setup` and the
     snapshot tests stay green with **no parser-test `reset()` needed at all**.
The lesson: `reset()`/isolation was **correct** all along; the blocker was a
**pre-existing test fragility** (the `ls.dicp`-based capture encoded incidental
dic state). Fixing the capture both hardened the tests and delivered the payoff —
no further state work was needed. The *architectural* payoff (one resettable
`interp`, 92→28 globals) and the *practical* payoff (heavyweight test isolation)
are both landed.
* *DoD: `reset()` primitive + isolation test; `reset()` covers all aggregated
  state; `reduce_test` runs full `mira_setup` with the suite green; golden 44/44.*

### Phase 5 — Thread `*Interp` through the call graph *(design-bearing; the large one)* — ⬜ **deferred**
**Deferred by decision (2026-06-24).** Scoped against the code: even bignum (the
smallest, leaf subsystem) is 23 fns + **59 call sites** + pervasive internal
rewiring (`heap.make` → `it.heap.make`); the full job is the ~2,100-site,
6-subsystem refactor including the hot reducer, with a real per-access perf cost
there. Since the practical payoff (encapsulation + a resettable `interp` for test
isolation) is already captured, full threading — whose remaining benefit is
*multiple independent interpreter instances / re-entrancy* — is parked until that
capability is actually needed. Resume per-subsystem (`bignum → reducer → …`) with
a reducer-loop benchmark when it is.

Convert subsystems from reaching the global `interp` to taking/holding
`*Interp` (methods `self: *Interp`, or a threaded first parameter). Do it
**per-subsystem, golden-gated**, reusing the A2 token-aware replacer for the
mechanical renames. Suggested order (most-self-contained first):
`bignum → reducer → heap/GC → lexer/parser → compiler/typecheck → driver`.
This is the ~2,100-site change and spans many PRs.
* **Irreducible exception:** OS signal handlers run on the C ABI and cannot take
  `*Interp`; they read a single `current_interp: *Interp` set on entry — the one
  documented global, analogous to `errno` and the A4 signal trampoline.
* *DoD per subsystem: no global-singleton access in that subsystem; golden green.*

### Phase 6 — De-globalize & document *(close-out)*
Delete the global `var interp`; `main()` constructs it explicitly
(`var interp = Interp.init(gpa); defer interp.deinit(); return interp.run(args);`).
Update [ARCHITECTURE.md](ARCHITECTURE.md) to drop the "singleton" language and
describe the `Interp` ownership model + the lone signal-delivery exception.
* *DoD: non-FFI module-scope mutable globals = **1** (documented); a second
  `Interp` can be constructed and run independently; golden green.*

---

## Dependency order

```
Phase 1 (export→var) ─► Phase 2 (group loose globals, per-module: 2a..2e)
                                         │
                                         ▼
                        Phase 3 (aggregate → one Interp)
                                         │
                                         ▼
                        Phase 4 (injectable; fix the tests)  ◄── value lands here
                                         │
                                         ▼
        Phase 5 (thread *Interp, per-subsystem) ─► Phase 6 (delete global; docs)
```

Phases 1–4 are bounded and independently shippable. Phase 5 is the only
open-ended one; it can proceed subsystem-by-subsystem over time, and Phase 4
already delivers test isolation without it.

## Risk register

| Phase | Risk | Mitigation |
|-------|------|------------|
| 1 | a genuine FFI consumer of an `export var` | none exist (A2/A3 proved it); golden byte-diff catches any |
| 2 | a moved field changes init order / `undefined` reads | structs default via `std.mem.zeroes`/`.{}`; per-module golden |
| 3 | re-pointing an owner singleton aliases a stale copy | one `interp` instance during transition; pointer-alias, not value-copy |
| 4 | a test's private `Interp` shares a hidden global (e.g. a `FILE` pool) | Phase 2c folds I/O in first; assert no residual global read |
| 5 | 2,100-site churn; perf regression in the hot reducer loop from an extra indirection | per-subsystem + golden; benchmark the reduce loop (reuse `-Dreduce-trace`); `self` is a single pointer in a register |
| 5 | signal handler needs interp state | single documented `current_interp` pointer (the irreducible C-ABI boundary) |

## Scorecard

Tracked by `scripts/shared-state-check.sh`.

| Metric | Baseline (Phase 0) | Now | Target |
|--------|--------------------|-----|--------|
| non-FFI module-scope mutable globals | 92 | **28** (Phases 2–4: all state under one `interp`; `reset()` covers it) | 1 (signal pointer) |
| &nbsp;&nbsp;↳ gratuitous `export var` | 35 | **0** ✓ (Phase 1) | 0 |
| grouped state structs | 4 (`rs`/`ls`/`heap`/`cs`) | unified under one `Interp` |
| global state aggregates | 4 structs + loose globals | 0 (constructed in `main`) |
| interpreter instances constructible | 1 (implicit) | N (explicit) |
| golden corpus | 44/44 | 44/44 at every step |

## Notes on the irreducible boundary

OS signals are delivered through the C ABI to a fixed-signature handler that
takes no context, so a single `current_interp: *Interp` (set when an `Interp`
begins running, like `errno`'s thread-local) is the one unavoidable global. This
is the same category of exception documented for the A4 signal trampoline in
[REDESIGN_DATA_MODEL.md](REDESIGN_DATA_MODEL.md): everything else — heap, lexer,
runtime, compiler, I/O, bignum, strings — becomes owned, explicit `Interp` state.
