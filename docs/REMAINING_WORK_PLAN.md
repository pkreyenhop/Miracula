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
| R3 | Single source for core constants. **✅ The `*_t` numbering discrepancy was a real bug — fixed (`c2d98fc`).** Remaining: atom-constant copies → `word.*`; `get_fil` dedup. (The "3 raw cell accesses" were false positives — comments.) | ARCH Part B | ◐ |
| R7 | Cryptic helpers — out-printers + `ctx.e/s/hold` decision done; **numbered helpers remain** (`typeError1-8`, `outType1/2`, `parseType1/2`, `parsePatV1-3`, `add1`/`remove1`/`newadd1`/`less1`/`decl1`) | ARCH Part B | ◐ |
| R9 | Break up longest fns: `reduce`(213), `loadfile`(331), `yylex`(343), `mainEntry`(412), `etype`(608), `handleReadyState`(813) | ARCH Part B | ◐ |
| R10 | Unify error channel (`MiraError` / `SYNERR` sentinels / `return NIL`) | ARCH Part B | ⏳ |
| J1 | Error unions for `SyntaxError`/`LoadError` (**overlaps R10**) | TESTABILITY | ⬜ |
| J2 | Standardise "dump stats then die" panics | TESTABILITY | ⬜ |
| A4b | Recovery redesign — SIGFPE synchronous, reducer unwind (**overlaps R10 step 3**) | REDESIGN | ⬜ |
| B2 | `Value` union — char boundary done (option a started); remaining range-test sites in `trans`/`types`/`reduce`; typed `Heap.hd/tl` | REDESIGN | ◐ |
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

### Phase 1 — Finish R3 + small encapsulation cleanups *(bounded, mechanical)*
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
* Then migrate the remaining atom-constant copies to `word.*` aliases. Leave the
  two intentionally-decoupled state modules as-is.
* **No raw-cell-access regression after all** — the "0 → 3" in idiomatic-check
  metric 14 is **false positives**: all three matches are *comments* mentioning
  `hd`/`tl`/`tag` (`combinators.zig:500/570` reduction rules, `word.zig:254` header),
  not real cell access. Fix is to tighten the metric-14 regex to skip comments — a
  `scripts/idiomatic-check.sh` refinement, not a code change.
* **Dedup the file-name accessor** (from Phase 0): unify `heap.get_fil` (interned
  `strtab.strOf`) with the two private `getFil` helpers (`heap.zig:1329`,
  `lex.zig:180`) that still use the pre-interning `castPtr` path — confirm they read
  the same representation, then collapse to one `getFil` and retire the snake name.

### Phase 2 — Finish B2 option (a) *(incremental, golden-gated)*
* Migrate the remaining range-test sites — `trans.zig` (`mkindex`/`getarg`-style
  `isAtom` ×3), `types.zig`, `reduce.zig` printer/`out` paths — onto
  `classify()`/`Value`.
* Add a typed `Heap.hd`/`tl` value accessor on top of `classify`.
* Closes B2 to its re-scoped DoD (range tests → 0 at value sites) and gives the
  TESTABILITY tiers precise typed reads.

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
