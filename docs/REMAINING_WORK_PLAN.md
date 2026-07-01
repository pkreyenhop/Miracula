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
| R9 | Break up longest fns: `reduce`(213), `loadfile`(331), `yylex`(343), `mainEntry`(412), `etype`(608), `handleReadyState`(813) | ARCH Part B | ◐ |
| R10 | Unify error channel (`MiraError` / `SYNERR` sentinels / `return NIL`) | ARCH Part B | ⏳ |
| J1 | Error unions for `SyntaxError`/`LoadError` (**overlaps R10**) | TESTABILITY | ⬜ |
| J2 | Standardise "dump stats then die" panics | TESTABILITY | ⬜ |
| A4b | Recovery redesign — SIGFPE synchronous, reducer unwind (**overlaps R10 step 3**) | REDESIGN | ⬜ |
| B2 | Option (a): char boundary done, range-test sites in `trans`/`types`/`reduce` remain. Option (b): `reducer/spine.zig` built + shadow-validated live against 51 real-program checks (0 mismatches) — blast radius found larger than documented (TRY/FAIL backtracking, `streamRead`'s C-ABI copy), both now shadow-covered; the actual dispatch cutover itself is not started | REDESIGN | ◐ |
| B3 | Tracing GC (after B2) | REDESIGN | ⬜ |
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

## The open decision (blocks Phases 4–5)

**B2's direction must be chosen explicitly:**
* **(a)** finish the incremental typed-`Value` boundary (already started) — range
  tests → 0 at value reads/writes; spine encoding stays raw. Medium effort,
  type-safety win.
* **(b)** repivot the "hard core" to an explicit typed spine stack — higher value
  (also unblocks B3 + A4b), comparable risk.
* **(c)** defer B2; do B3 / close-out first.

This plan assumes **(a)** for Phase 2 (it is in flight and low-risk) and notes
where **(b)** would reshape Phases 4–5.

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

### Phase 2 (option b) — Repivot the hard core: explicit spine stack ◐ *(Steps 1–2 done 2026-07-01; cutover not started)*

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
the corpus stays at `take 150`.

**Remaining before a cutover could be considered:**
1. Migrate `combinators.zig`'s `handleTRY`/`handleFAIL` and `runtime/reduce.zig`'s
   `streamRead` to actually *run on* `Spine` (today they still run pointer reversal
   for real; only the shadow observes them) — they can't stay on the old encoding
   once cells stop carrying bookkeeping.
2. Swap `reduce()`'s main loop and `ReductionCtx.s`/`.hold` for a per-call `Spine`
   (threading `rt.allocator`, already used elsewhere for growable scratch, e.g.
   `dstack`).
3. Measure: there is no agreed perf budget yet, and the DoD requires "a
   reduction-loop micro-benchmark within the agreed budget" — `src/micro_benchmarks.zig`
   currently covers allocation/GC/interning, not the reducer loop, so that benchmark
   needs writing first to get real numbers before/after.
4. Re-run golden + the differential harness + the benchmark; only then swap the live
   path. (The differential harness stops being useful as a *safety net* the moment
   `Spine` becomes the thing being tested rather than the shadow — at that point
   correctness rests on golden + the unit suite, same as everywhere else.)

This is multiple dedicated sessions of work, not a single increment — treat it as
its own initiative once Step 1's groundwork (done) is built on.

### Phase 3 — R9 function-splitting *(per-function, independent of Phase 2 — may interleave)*
Extract named steps one function at a time, easiest → hardest, golden after each:
`reduce`(213) → `loadfile`(331) → `yylex`(343) → `mainEntry`(412) → `etype`(608) →
`handleReadyState`(813). Each shares heavy local/register state, so each is an
individual, carefully-validated extraction.

### Phase 4 — The error/recovery cluster (R10 + J1 + J2 + A4b) *(design-bearing — the linchpin)*
1. **Coverage first.** Add golden/integration cases that exercise the error paths
   (syntax error mid-script, SIGINT during reduction, divide-by-zero) — none exist
   today, and the mechanism can't be safely changed without them.
2. **R10-Step 1** *(no behaviour change)*: wrap the sentinel reads/writes behind
   named helpers (`raiseSyntaxError(node)`, `currentErrorNode()`); unit-test.
3. **R10-Step 2 + J1**: convert `return NIL`-as-failure leaf fns and
   `SyntaxError`/`LoadError` onto `MiraError!T`, propagating `try` up to the nearest
   `setjmp`/`longjmp` boundary. Individually golden-checkable.
4. **Design decision** (R10-Step 3 + A4b): pick the recovery model —
   * (a) **keep `setjmp`/`longjmp`** for signal + top-level REPL recovery (the
     C-port's deliberate model) and unify only the *non-recovery* reporting onto
     error unions; or
   * (b) **replace `longjmp`** with end-to-end error propagation (large; must
     re-prove async-signal safety and that partial heap mutations unwind correctly).
   Fold **J2** (standardise the fatal-panic path) in here.

   Recommended: Steps 1–2 as a dedicated PR; Step 3 as a separate, reviewed design
   proposal.

### Phase 5 — B3 tracing GC *(after B2)*
Replace the sign-bit free-list mark-sweep with a precise tracing collector over the
`Ref` graph: explicit typed root set, mark/sweep rebuilding the free list from a
side `std.DynamicBitSet` (drops the tag sign-bit trick, making `NodeTag` fully
exhaustive). *DoD: precise-root unit tests + GC stress test stable; golden green.*
If B2 option **(b)** was taken, the spine-stack rework lands before this and supplies
the precise roots.

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
Phase 0 (hygiene + C1) ─┐
Phase 1 (R3)            ├─ independent, do first
Phase 2 (B2 opt a) ─────┤   (Phase 2 ∥ Phase 3)
Phase 3 (R9 splits) ────┘
        │
        ▼
Phase 4 (R10 + J1 + J2 + A4b)  ── design decision (a/b) on recovery model
        │
        ▼
Phase 5 (B3 GC)  ── needs B2; unblocked further by B2 option (b)
        │
        ▼
Phase 6 (Ph5 → Ph6)  ── largest; defer unless multi-instance required
        │
        ▼
Phase 7 (C2 docs)
```

**Behaviour remains unchanged throughout** — verified by the golden corpus, the
unit suite, and `zig build lint` at every commit.
