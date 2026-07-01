# Miracula — Remaining-Work Plan (consolidated, sequenced)

> A single roll-up of every item still open across the project's plan docs, put
> into a dependency-correct order. Each step stays **behaviour-preserving** and is
> gated by the golden corpus (44 byte-identical cases), `zig build test`, and
> `zig build lint` — the cadence every landed refactor has used.

This plan does not replace the source plans; it sequences their *open* items and
records the cross-plan entanglements that decide the order. As items land, update
the status here **and** in the owning plan.

Source plans:
[IDIOMATIC_ARCHITECTURE_PLAN](IDIOMATIC_ARCHITECTURE_PLAN.md) (Part A done; Part B
partial),
[REDESIGN_DATA_MODEL](REDESIGN_DATA_MODEL.md) (Track A done; Track B/C open),
[SHARED_STATE_PLAN](SHARED_STATE_PLAN.md) (Phases 1–4 done; 5–6 deferred),
[TESTABILITY_PLAN](TESTABILITY_PLAN.md) (tiers substantially complete),
[READABILITY_PLAN](READABILITY_PLAN.md) (done),
[IDIOMATIC_ZIG_PLAN](IDIOMATIC_ZIG_PLAN.md) (done — Clusters A–Q all ✅).

## What is already complete (no action)

* **READABILITY_PLAN** — naming (0 C-style fn defs) + docs (100%). Only its
  module-inventory table is stale (see Phase 0).
* **IDIOMATIC_ZIG_PLAN** — Clusters A–Q all ✅.
* **IDIOMATIC_ARCHITECTURE_PLAN Part A** (`main.zig` dissolved) and Part B
  R1/R2/R4/R5/R6/R8.
* **REDESIGN Track A** (C-ABI / linker cleanup): `extern fn` 322→14 syscall floor,
  `extern var`→0, `export fn`→3, `callconv(.c)`→6.
* **SHARED_STATE Phases 1–4** (state aggregated into one `Interp`).

## Open inventory

| ID | Item | Owner plan | State |
|----|------|-----------|:-----:|
| R3 | Single source for core constants. **✅ Done** — `*_t` numbering bug fixed (`c2d98fc`); last atom-constant copies `CONST`/`FREE` aliased (`34480dc`); only the decoupled state-module `CMBASE` remains by design. | ARCH Part B | ✅ |
| R7 | Cryptic helpers — out-printers + `ctx.e/s/hold` decision done; **numbered helpers remain** (`typeError1-8`, `outType1/2`, `parseType1/2`, `parsePatV1-3`, `add1`/`remove1`/`newadd1`/`less1`/`decl1`) | ARCH Part B | ◐ |
| R9 | Break up longest fns: `reduce`(213), `loadfile`(331), `yylex`(343), `mainEntry`(412), `etype`(608), `handleReadyState`(813). **✅ Done** — all six extracted. | ARCH Part B | ✅ |
| R10 | Unify error channel (`MiraError` / `SYNERR` sentinels / `return NIL`). Recovery-model decision made (keep `setjmp`/`longjmp`, see Phase 4); sentinel-wrapping steps deliberately not pursued (dual-purpose `errs`/`errline` risk vs. marginal gain). | ARCH Part B | ◐ |
| J1 | Error unions for `SyntaxError`/`LoadError` (**overlaps R10**) — not pursued, see Phase 4 | TESTABILITY | ⬜ |
| J2 | Standardise "dump stats then die" panics — **resolved as no-op**: audit found the fatal-panic path is fine as-is (see Phase 4) | TESTABILITY | ✅ |
| A4b | Recovery redesign — SIGFPE synchronous, reducer unwind (**overlaps R10 step 3**). **✅ Resolved**: every `longjmp` call site is signal-handler-triggered (SIGINT/SIGFPE only); option (a) — keep `setjmp`/`longjmp` — is the only viable mechanism, not a stylistic choice. | REDESIGN | ✅ |
| B2 | Option (a): char boundary done, range-test sites in `trans`/`types`/`reduce` remain (not started). Option (b): **✅ done** — `reduce_core.zig`'s spine primitives, `combinators.handleTRY`/`handleFAIL`, and `runtime/reduce.zig`'s `streamRead` all run on the explicit `Spine` for real; two real bugs (a `via_tl`-boundary correctness gap, a ~15x perf regression) found and fixed post-cutover | REDESIGN | ◐ |
| B3 | Tracing GC (after B2) | REDESIGN | ✅ |
| C1 | Final data-model scorecard | REDESIGN | ⬜ |
| C2 | Rewrite `ARCHITECTURE.md` / `ZIG_MIGRATION.md` to the new model | REDESIGN | ⬜ |
| Ph5 | Thread `*Interp` through the call graph (~2,100 sites) | SHARED_STATE | ⬜ |
| Ph6 | Delete the global `interp`; `main` constructs it (needs Ph5) | SHARED_STATE | ⬜ |
| Tests | A few reducer handlers untested (show/MATCH/GENSEQ, TRY/FAIL backtracking) | TESTABILITY | ◐ |
| Docs | Stale READABILITY inventory table; ARCHITECTURE "Remaining Opportunities" lists K2 (done) | several | ◐ |

## Entanglements that drive the order

1. **R10 ≡ J1 ≡ A4b** all touch the same error/recovery + `setjmp`/`longjmp`
   model. Treat them as **one workstream**, not three.
2. **B2 → B3**: the tracing GC needs a clean `Ref` graph to trace. Moreover B2's
   *option (b)* (repivot pointer-reversal to an explicit spine stack) would itself
   unblock **B3's precise roots and A4b's interrupt flag** — so B2's direction is a
   fork that decides downstream work.
3. **Ph6 needs Ph5**; both are large and currently unnecessary for serial
   per-function testing (`reset()` suffices). Defer unless multi-instance becomes a
   requirement.

## The B2 decision — resolved: both (a) and (b), (b) done first

**B2's direction was originally framed as pick-one:**
* **(a)** finish the incremental typed-`Value` boundary (started) — range tests → 0
  at value reads/writes; spine encoding stays raw. Medium effort, type-safety win.
* **(b)** repivot the "hard core" to an explicit typed spine stack — higher value
  (also unblocks B3 + A4b), comparable risk.
* **(c)** defer B2; do B3 / close-out first.

In practice these are independent axes (a) is about value *representation* at the
`Heap` boundary; (b) is about the *traversal mechanism* — so both are worth doing.
**(b) is now done** (Phase 2 below: `Spine` replaced pointer reversal for real,
2026-07-01). **(a) remains open** (the range-test sites in `trans`/`types`/`reduce`
are unmigrated) and is no longer blocked on anything — pick it up whenever.
`Spine` having landed also means B3 (tracing GC) is now unblocked on real, precise
roots rather than needing its own design work first.

---

## Sequenced phases

### Phase 0 — Cheap close-outs & doc hygiene ✅ *(done 2026-06-30)*
* ✅ **READABILITY inventory** — retired the stale per-module table; corrected the
  metric to the *true* numbers (the "0 snake / 100%" claim was wrong). Live state:
  **2 snake fns, 98% documented**, accounted for as:
  * `lineedit.tab_complete` — **convention exemption** (name dictated by `zigline`
    reflection); add to the metric's exempt list.
  * `heap.get_fil` — **not** a mechanical rename: its camelCase target `getFil` is
    already used by two *private* helpers (`heap.zig:1329`, `lex.zig:180`) that read
    the file-name field via the **pre-interning `castPtr`** path instead of
    `strtab.strOf`. A blind rename collides and hides a representation split →
    folded into **Phase 1** as a dedup/investigation (with R3/B1). *(A trial rename
    was made and reverted; `src/` is unchanged.)*
* ✅ **`ARCHITECTURE.md` "Remaining Opportunities"** — I1/I3/**K2** marked resolved
  (Clusters M/N/P); only J1/J2 remain.
* ✅ **C1 scorecard recorded** — added a dated `idiomatic-check.sh` snapshot to
  REDESIGN. C1 **stays open, blocked on A4b** (`callconv(.c)` 6→1). Two deltas noted:
  `export fn` 3→2 (good); **raw cell access outside `heap.zig` 0→3** (small
  encapsulation regression to re-confine — added to Phase 1).
* ◐ **R7** — scan found it is **not** closeable: beyond the documented `ctx.e/s/hold`
  decision and out-printer renames, real numbered helpers remain — chiefly in
  `types.zig` (`typeError1`–`typeError8`, `outType1/2`) and the parser
  (`parseType1/2`, `parsePatV1/2/3`), plus `add1`/`remove1`/`newadd1`/`less1`/`decl1`.
  (`ap2`/`ap3`/`digit0` are legitimate arity/domain suffixes — leave them.) This is
  the concrete target list for a future R7 pass; R7 stays ◐.

### Phase 1 — Finish R3 + small encapsulation cleanups ✅ *(done 2026-07-01)*
* ✅ **The `algebraic_t`/`abstract_t`/`placeholder_t` numbering discrepancy was a
  real, live bug — fixed** (commit `c2d98fc`). It was **not** cosmetic: `word.zig`
  numbered the kind codes 2/3/5 while the C-ported checker (`trans.zig`/`types.zig`)
  switches on 0/2/3, and `codegen` writes the `word.*` value that the checker reads
  back — so `word.algebraic_t=2` collided with the checker's `abstract_t=2` and
  **every user `::=` type was processed as an `abstype`** (`Green` → `<abstract ob>`;
  `tree ::= Leaf num | …` → bogus `cannot unify num with num`). Built-in `bool`
  escaped (special-cased) and the golden corpus never evaluated a user `::=` type, so
  it was invisible. Fix: renumber `word.zig` to the authoritative checker values
  (algebraic=0, synonym=1, abstract=2, placeholder=3, free=4); alias the redundant
  local consts to `word.*` (R3 closure for these codes); add regression goldens
  `algebraic_nullary` + `algebraic_param`.
* ✅ **Atom-constant copies migrated** (`34480dc`). A tree-wide sweep found only
  `CONST`/`FREE` (types.zig) still value-duplicating a `word.zig` constant; both
  aliased to `word.*`. The only remaining copy is `CMBASE` in the two deliberately
  import-decoupled state modules (`lex_state.zig`/`runtime_state.zig`) — left as-is
  by design.
* ✅ **No raw-cell-access regression after all** — the "0 → 3" in idiomatic-check
  metric 14 was **false positives** (comments mentioning `hd`/`tl`/`tag`). Fixed by
  stripping `//`-comments in the metric-14 regex (`7e7bf07`); real count is `0`.
* ✅ **File-name accessor deduped** (`093a767`). The "representation split" feared in
  Phase 0 was illusory: `castPtr` is just a thin alias for `strtab.strOf`, so all
  three readers already decode identically. Collapsed to one
  `pub fn heap.getFil(fil) ?[*:0]const u8` (non-optional sites use `orelse ""`);
  retired the `get_fil` snake name. With `tab_complete` exempted (zigline reflection
  name, `7e7bf07`), the readability snake-fn count is now a true **0**.

### Phase 2 — Finish B2 option (a) *(incremental, golden-gated; not started)*
* Migrate the remaining range-test sites — `trans.zig` (`mkindex`/`getarg`-style
  `isAtom` ×3), `types.zig`, `reduce.zig` printer/`out` paths — onto
  `classify()`/`Value`.
* Add a typed `Heap.hd`/`tl` value accessor on top of `classify`.
* Closes B2 to its re-scoped DoD (range tests → 0 at value sites) and gives the
  TESTABILITY tiers precise typed reads.

### Phase 2 (option b) — Repivot the hard core: explicit spine stack ✅ *(done 2026-07-01)*

**Step 1 — `reducer/spine.zig`, additive and inert.** ✅ Done (`71c47ae`). Built and
unit-tested an explicit, growable `Spine`/`Frame` stack as a candidate drop-in
replacement for `reduce_core.zig`'s in-graph pointer reversal
(`downLeft`/`downRight`/`upLeft`/`upRight`). Derived by tracing every read/write the
four existing primitives perform against the live `heap`: exactly one write per call
is a real graph mutation (a write-back so sharing still works); everything else is
pure bookkeeping for "what's below this frame", which the new module moves into an
explicit `Frame{node, via_tl}` instead of borrowing a cell's own `hd`/`tl` field.
Confirmed property: `downRight` does not push a new frame — it re-tags the existing
top frame (both halves of visiting one `AP` cell share it); `upRight` mirrors this by
flipping back without popping; only `upLeft` pops. Backed by a growable
`std.ArrayList`, not a fixed array — pointer reversal has *no* depth bound (the stack
is the heap), so a fixed capacity would silently turn long lazy spines (e.g.
`length [1..1000000]`) into crashes; a stress test confirms 200k-deep with no
overflow. 6 new unit tests, 163/163 total, golden/lint unaffected (the module is not
wired into `reduce()`).

**The investigation also revised the scope of the eventual cutover, upward.** The
plan's framing — "two files kept in lock-step" (`reducer/reduce.zig`,
`reducer/reduce_core.zig`) — undercounts the real blast radius. Direct, raw
manipulation of the spine encoding (`ctx.s`/`hdGet`/`tlptrbit`) was also found in:
* `combinators.zig`'s `handleTRY`/`handleFAIL` — Miranda's multi-equation
  pattern-match backtracking walks the *existing* spine in bulk directly, not just
  through the four primitives.
* `runtime/reduce.zig`'s `streamRead` — a `pub export fn` (part of the C-ABI surface)
  that inlines its own "UPLEFT" using *unmasked* `h`/`hp` accessors, relying silently
  on that particular frame having been pushed by a pure `downLeft` chain (never
  `downRight`) — an invariant that is correct but undocumented and easy to violate in
  a hand-port.

**Step 2 — shadow-validation harness, done (`d3af11d`, `c617ae2`).** Rather than a
post-hoc trace-replay (drifts the moment anything mutates the graph between recorded
calls — rewrites, allocations, recursive `reduce()` calls all happen *between* the
four primitive calls, so replaying against a stale snapshot doesn't work), built an
**inline shadow**: `spine.active`, when set, makes `reduce_core.zig`'s four
primitives (and `combinators.zig`'s `handleTRY`/`handleFAIL`, and `runtime/reduce.zig`'s
`streamRead`) drive a real `Spine` in lockstep with the live pointer-reversal
mechanism *as the program actually runs*, asserting agreement at every call. Default
`null` — zero effect on the live interpreter or any existing test.

A real safety bug turned up immediately: the shadow's first version called `Spine`'s
*write-performing* methods (`downRight`/`upLeft`/`upRight`), which are only safe when
perfectly in sync. TRY/FAIL backtracking is pervasive (every guarded multi-equation
function uses it) and the shadow *will* diverge in ways the mirroring doesn't
perfectly track — a diverged shadow performing real writes can write a real value to
the *wrong* cell, silently corrupting the live program. This reproduced immediately:
even `3+4` crashed with a heap assertion once the full prelude was loaded. Fixed by
making the shadow **read-only** (`peekDownRight`/`peekUpLeft`/`peekUpRight`, using
`heap.h`/`heap.t` — which degrade to `0` on an out-of-range index rather than
asserting — never `heap.hp`/`heap.tp`). A divergence now fails a clean, local
assertion; it can no longer corrupt the program.

`tests/spine_differential_check.py` runs the interpreter with validation on over the
full golden corpus (44 cases) plus 7 curated `miralib/ex/` programs (deep recursion,
guarded multi-equation functions, algebraic types, lazy infinite streams — shapes
golden doesn't stress): **51/51 pass, zero mismatches.** This is real evidence for
the four primitives' correctness beyond `spine_test.zig`'s hand-built cases.

*Side finding, out of scope, not fixed:* `miralib/ex/ack.m`/`queens.m`/`hanoi.m` use
n+k patterns (`ack (m+1) 0 = ...`) that this interpreter's parser/compiler currently
rejects outright ("illegal object \"1\" as head of formal") — reproduces identically
with or without spine validation, so a separate, genuine, pre-existing bug. The
differential corpus uses `tests/spine_corpus/ack_nk_free.m` (golden's `custom_ack.m`
style) in place of `ack.m`; `queens.m`/`hanoi.m` are skipped. Also,
`miralib/ex/primes.m` crashes on `take 500` (also reproduces without validation) —
the corpus stays at `take 150`. (Both spawned as separate background tasks; not
tracked further in this plan.)

**Step 3 — the cutover itself, done (`e25f241`, `f614e37`).** `ReductionCtx.s`/`.hold`'s
spine-bookkeeping role is gone; `ReductionCtx` now embeds a `spine: Spine`, and
`downLeft`/`downRight`/`upLeft`/`upRight`/`downright`/`upleft` are thin wrappers over
its methods. `combinators.handleTRY`/`handleFAIL` and `runtime/reduce.zig`'s
`streamRead` (the two extra manipulation sites Step 1 found) now run on `Spine` for
real via `pushRaw`/`popNodeOnly`, not raw `ctx.s` bit-twiddling.

**A correctness gap the cutover surfaces that pointer reversal never had to answer:**
`Heap.bases`'s conservative C-stack scan finds `ReductionCtx.e`/`.s` as Word-sized
stack slots and `mark()`'s own `hd`/`tl` walk threads through the rest of an
old-style reversed chain "for free" — but `Spine.frames` is a *separate* heap
allocation the scanner can't see into, so a cell reachable only via a `Frame.node`
could be collected mid-reduction. Fixed with an explicit root-registry
(`Spine.register`/`unregister`, LIFO-matching nested `reduce()` calls;
`Heap.bases` calls `spine.markAllRoots` alongside its existing root marking) —
this is exactly the "unblocks B3's precise GC roots" upside the original B2 audit
flagged for option (b), now realised as a requirement rather than a future nicety.

**Two real, distinct correctness bugs surfaced empirically** once this ran for real
(not just in shadow) — the shadow's narrower coverage (primitive-level agreement
only) had not caught either. Root-caused by building a throwaway git-worktree copy
of the pre-cutover commit, instrumenting both builds' primitives identically, and
diffing the per-primitive call sequence on the same failing input:
* `abnormal(ctx.s)` (`ctx.s < 0`) is true both when the spine is genuinely empty
  *and* when the top frame is a real, non-empty one tagged `via_tl=true` (same sign
  bit as `BACKSTOP`). The guarded wrappers (`downright`/`upleft`, transitively
  `getarg`) and `handleTRY`/`handleFAIL`'s own loops all relied on that coincidence
  to stop at the boundary of an outer, already-`downRight`'d ancestor — a real
  semantic distinction. `Spine.isEmpty()` alone missed it; added
  `Spine.atArgumentChainBoundary()` (empty OR top `via_tl`). Without this,
  `firstel (x:xs) = x` looped forever and `colour ::= Red | Green | Blue` printed
  garbage.
* A genuine ~15x perf regression on many-short-lived-`reduce()`-calls workloads
  (`#(take 3000 primes)`: 0.93s → 14.3s) from `Spine.init`'s frame buffer starting at
  zero capacity every call — overhead pointer reversal never paid (it borrowed graph
  cells, never the allocator). Fixed with a small buffer pool (bounded by max
  concurrent `reduce()` nesting, not call count); back to ~0.85–1.3s. Gated off under
  `builtin.is_test` — pooling across separate test functions' `std.testing.allocator`
  instances corrupted the allocator's own bookkeeping.

**Verified:** 165/165 unit tests, 44/44 golden byte-identical, 51/51
spine-stress-corpus checks (`tests/spine_differential_check.py`, now exercising the
live path — the shadow machinery is gone since there is nothing left to shadow),
lint clean. `fib 28` ~0.17s before and after the perf fix (Spine was already
*faster* than pointer reversal there — fewer total memory writes per traversal
step); `#(take 3000 primes)` 14.3s → ~1s.

Not done, and not blocking: a *formal*, permanent reduction-loop micro-benchmark
(`src/micro_benchmarks.zig` still covers only allocation/GC/interning) — the timing
numbers above were ad hoc (`/usr/bin/time` on a throwaway ReleaseFast worktree
build), sufficient to catch and fix the regression but not wired in as a
regression-guarding CI artifact. Worth adding in a follow-up if reducer performance
becomes a recurring concern.

### Phase 3 — R9 function-splitting ✅ *(done)*
Extracted named steps one function at a time, easiest → hardest, golden after each:
`reduce`(213→~90) → `loadfile`(331→142) → `yylex`(343→50) → `mainEntry`(412→110) →
`etype`(608→80) → `handleReadyState`(813→588, extracting only the five arms over
30 lines — the rest were already short and self-documenting via their combinator
constant). Each shared heavy local/register state, so each was an individual,
carefully-validated extraction (44/44 golden + full unit-test suite + spine-corpus
stress checks + lint after every one). Along the way, smoke-testing surfaced two
pre-existing, unrelated bugs (a divide-by-zero in `-make`'s failure report on long
paths; a crash evaluating `system "..."` at the prompt) — both flagged as separate
follow-ups, not fixed here.

### Phase 4 — The error/recovery cluster (R10 + J1 + J2 + A4b) ◐ *(recovery-model decision made; sentinel cleanup deliberately not pursued)*

1. **Coverage first ✅.** Added golden cases for the paths that had none: script-level
   (`.m` file) syntax errors (`script_syntax_err`, distinct from the existing
   REPL-typed `syntax_err`/`lex_err`), integer/float divide-by-zero
   (`arith_divzero`/`arith_modzero`/`double_divzero` — all report `program error:
   attempt to divide by zero` on stderr, exit 0), and a dedicated
   `tests/sigint_check.py` + `tests/sigint_corpus/slow_fib.m` for SIGINT delivered
   mid-reduction (not golden-checkable — timing/signal-dependent — so it lives
   outside `golden_runner.py`'s byte-identical model). While adding the script-syntax
   case, found a real pre-existing bug: re-running `mira` against an *unchanged*
   script with a syntax error produces no output at all on the second run (silently
   "succeeding") — `loadfile()`'s failure path calls `dump.makedump()` even when
   `SYNERR == 1`, caching an error-state dump that `undump()` then treats as fresh.
   Confirmed pre-existing (reproduces on the commit before the R9 `loadfile()`
   split); flagged as a separate follow-up, not fixed as part of this phase.

2. **Design decision (R10-Step 3 + A4b) ✅ resolved by technical necessity, not
   preference.** Audited every `setjmp`/`longjmp` call site: **both** `siglongjmp`
   calls in the entire codebase (`repl.zig`'s `fpeError()` for SIGFPE, `reset()` for
   SIGINT) live inside `callconv(.c)` signal-handler functions — there is no
   ordinary-control-flow `longjmp` usage anywhere to replace. POSIX signal handlers
   are asynchronous, so a Zig error union can never propagate out of one; option
   **(b)** ("replace `longjmp` with end-to-end error propagation") has no target in
   this codebase. **Decision: (a)** — `setjmp`/`longjmp` stays, permanently, for
   signal + top-level REPL recovery; it is the only mechanism that can recover from
   an interrupt arriving mid-instruction, not a stylistic holdover from the C port.
   This also resolves **J2** (the fatal-panic path is fine as-is; nothing to
   standardise away from signals).

3. **R10-Step 1 (sentinel-wrapping) and R10-Step 2 + J1 (`MiraError!T` conversion) —
   deliberately not pursued.** Surveyed the actual `SYNERR`/`errs`/`errline` usage
   before starting (~22 `SYNERR` write sites + ~18 read sites across 6 files; ~36
   `errs`/`errline` sites). `SYNERR` itself is a clean 3-state sentinel (0/1/2) that
   would wrap safely. But `errs`/`errline` turned out to serve **two unrelated
   purposes**: a "first syntax error's location" recorder (set-if-zero, in
   `lex.zig`/`types.zig`/`module_loader.zig`) and an unconditionally-overwritten
   "current compile position" breadcrumb (`trans.zig`, 11 sites, no guard, used
   later to report *where* a runtime error occurred — nothing to do with `SYNERR`).
   Unifying both under one `raiseSyntaxError(node)`/`currentErrorNode()` pair (the
   plan's original suggested shape) would mean adding a "first wins" guard to
   `trans.zig`'s currently-unconditional writes — a real behaviour change, not the
   "no behaviour change" the step promised. Given the recovery-model question (the
   part of R10 with genuine architectural weight) is now settled, and the remaining
   sentinel cleanup is a pure-encapsulation exercise whose main finding is "these two
   fields are secretly two different things," the decision was to stop here rather
   than either (a) force a risky unification or (b) introduce a second, more
   fragmented set of helpers for marginal clarity gain. Revisit only if `errs`/
   `errline`'s dual-purpose nature becomes an active source of bugs.

### Phase 5 — B3 tracing GC ✅ *(done)*
Replaced the sign-bit-on-tag-byte mark-sweep with a precise tracing collector:
`Heap.live: std.DynamicBitSetUnmanaged` (one bit per cell, persistent liveness
bitmap) plus an explicit `free_head` free list threaded through freed cells' own
`tl` fields. `mark()` now tests `!live.isSet(idx)` for cycle detection instead of
flipping the tag byte's sign bit; `gc()` clears the bitmap, calls `bases()`, then
rebuilds `free_head` from every unmarked cell in one sweep. `make()`'s allocation
path is now O(1) (pop `free_head`) instead of the old bump-pointer's
scan-for-a-gap. Dropped `poschar`/`negchar`/`gcpatch`/the `listp` field as dead
code, and removed `NodeTag`'s trailing `_,` catch-all — the enum is now fully
exhaustive since the new GC never stores anything but a named tag in a cell.
The `Spine` cutover already supplied the reduction-loop half of this — every
frame is an explicit, typed root (`Spine.markAllRoots`, added because the
conservative stack scan can't see into `Spine`'s own heap-allocated buffer) — so
this phase was the remaining *cell-storage* side (the sign-bit mark/sweep
itself). *DoD met: new GC stress test (long-lived list survives many forced
collections; garbage reclaimed) + all 166 unit tests + 44/44 golden + 51/51
spine-corpus stress checks + lint all green; fib(27) timing shows no regression
vs the pre-B3 baseline.*

### Phase 6 — SHARED_STATE Ph5 → Ph6 *(largest; only if multi-instance is needed)*
Thread `*Interp` through the call graph (~2,100 sites), then delete the global
`interp` and have `main` construct it. Not required for serial per-function tests.

### Phase 7 — C2 doc rewrite *(close-out)*
Once the representation work (B2/B3) settles, update `ARCHITECTURE.md` and
`ZIG_MIGRATION.md` to describe the final model (cell store, GC, strings, I/O); re-run
the C1 scorecard. *DoD: docs match code.*

---

## Dependency order (summary)

```
Phase 0 (hygiene + C1) ────────┐
Phase 1 (R3) ✅                │
Phase 2 (B2 opt b, cutover) ✅  ├─ independent, do first
Phase 2 (B2 opt a) ─────────────┤   (∥ with Phase 3)
Phase 3 (R9 splits) ✅ ─────────┘
        │
        ▼
Phase 4 (R10 + J1 + J2 + A4b) ◐ ── recovery-model decision made (a); sentinel
                                    cleanup deliberately not pursued
        │
        ▼
Phase 5 (B3 GC) ✅
        │
        ▼
Phase 6 (Ph5 → Ph6)  ── largest; defer unless multi-instance required
        │
        ▼
Phase 7 (C2 docs)
```

**Behaviour remains unchanged throughout** — verified by the golden corpus, the
unit suite, and `zig build lint` at every commit.
