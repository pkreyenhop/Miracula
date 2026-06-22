# Miracula — Data-Model Redesign Plan

> File name note: created as `docs/REDESIGN_DATA_MODEL.md` to match the existing
> `IDIOMATIC_ZIG_PLAN.md` / `ARCHITECTURE.md` / `ZIG_MIGRATION.md` convention.
>
> **Rewritten 2026-06-23** after the R7.3 / R8.1 work surfaced findings that materially
> change the remaining plan (see *Findings that revise the original plan*). The original
> linear R0→R8 plan is preserved in condensed form under *Completed phases* and *Progress log*.

## Objective

Replace the inherited **C-heap data model** with an idiomatic Zig one, and in doing so
eliminate the C-isms that the [IDIOMATIC_ZIG_PLAN](IDIOMATIC_ZIG_PLAN.md) found to be *inherent
to the current model*:

1. the **C-heap data model** — `Word = c_long` conflated as cell-handle / atom / int / char,
   stored in parallel arrays `hd[x*2]`, `tl[x*2]`, `tag[x]`;
2. the **linker-as-module-system** pattern — `extern fn` / `extern var` / `export fn` used to
   call between *internal* Zig modules, a habit carried over from the C port;
3. **`clib.` / `c.`** call sites;
4. **`callconv(.c)`** and C-callbacks (signal handlers, `main_entry`).

### Definition of Done *(revised)*

A reviewer sees a typed node store (`std.MultiArrayList` / typed handles), allocator-managed
memory, `std.Io` / `std.fs` I/O, interned `[]const u8` strings, and Zig error unions.

This is a **standalone pure-Zig binary**: nothing external (no C, no yacc/lex, no shared
library) links against it, so the *honest* C-ABI target is:

* `extern fn` / `extern var` declaring **internal** symbols → **0** (use `@import`);
* `export fn` → **0** (no external linker consumers exist);
* `clib.` / `c.` → **0**;
* `callconv(.c)` → **1** — a single documented signal trampoline (the OS delivers signals via
  the C ABI; that boundary alone is irreducible — see Track A4);
* the **only** remaining FFI is the OS syscall surface (`open`/`read`/`write`/`fork`/`sigaction`/
  `stat`/…), expressed through **`std.posix` / `std.c`**, not bespoke `extern fn`.

> The earlier DoD assumed `main_clib.zig` was an irreducible boundary that could never shrink.
> That was wrong: 52 of its 63 `extern fn` are the internal anti-pattern, and the genuine libc
> calls have `std.posix` equivalents. "Zero C-ABI" is therefore *one documented trampoline plus a
> thin `std.posix` syscall layer*, not a large irreducible `main_clib`.

---

## Where things stand (2026-06-23)

| Layer | State |
|-------|-------|
| Safety net (R0) | ✅ Golden corpus (44 cases, byte-identical), scorecard, dump round-trip |
| C-stdlib shim → `std` (R1) | ✅ Complete — `clib.`/`c.` call sites = **0** |
| Heap encapsulation (R2) | ✅ `Heap` object; raw cell access confined to `heap.zig` (metric = 0) |
| Storage = `MultiArrayList` (R3) | ✅ `Cell{ tag: NodeTag, hd, tl }`; `*2`/dual-pointer arithmetic gone |
| Typed handles (R4.1/4.2/4.5) | ✅ `word.Ref`, `isAtom`/`fitsInByte` classifiers; `Word = i64` (not `c_long`) |
| Linker-as-module-system (R7.3) | ✅ `extern fn` 322 → **19** (syscall floor); `c_abi.zig` **deleted** (R8.1) |
| Track A1 — main_clib externs | ✅ 52 internal `extern fn` → `@import`; main_clib at 11 libc externs |
| Track A2 — `extern var` | ✅ **0** — all 30 globals accessed via owner module |
| Track A3 — `export fn` | ✅ 174 → **3** (only the still-extern-referenced bridges remain) |
| Track A4 — signals / `callconv` | ⬜ Next — `callconv(.c)` = 13 (mostly gratuitous), target 1 |
| `Value` union (R4.3/4.4) | ⬜ Deferred — the deep core (Track B2) |
| Tracing GC (R5) | ⬜ Planned (Track B3) |
| String interning (R6) | ⬜ Planned — 132 `[*:0]`-as-`Word` casts remain (Track B1) |

---

## Findings that revise the original plan

These emerged while executing R7.3 / R8.1 and change *what* remains and *in what order*.

1. **Circular `@import` works for functions — so `extern fn`/`extern var` between internal
   modules were never required.** Zig imports are lazy/comptime; only a by-value *type-size*
   cycle fails. The pervasive `extern fn`/`export fn` linker-symbol pattern (incl. the
   `trans↔types` and `reduce_core↔reduce` "cycles") was a C-port habit. Converting
   `extern fn foo` → `const foo = module.foo` is mechanical and golden-safe. This is the lever
   for the entire remaining FFI cleanup.

2. **This is a pure-Zig project — there is no C / yacc / lex compilation unit.** `build.zig`
   links no `.c`/`.y`/`.l` sources. Consequences:
   * `yyparse` (and `yylval` as a global) are **dead** — the parser is fully Zig (`lex.zig`).
   * **`export fn` is almost entirely gratuitous** — nothing external links against these
     symbols. 174 `export fn` exist; only genuine *entry points / OS callbacks* need it.
   * **`callconv(.c)` is mostly gratuitous** — most of the 11 are pure-Zig function pointers
     (char-class predicates `okid`/`okulid`/`okpath`/`hash`, `walktype`'s callback,
     `main_entry`). Only the `sigaction` signal handler genuinely needs it.

3. **`main_clib.zig` is *not* the irreducible boundary.** Of its 63 `extern fn`, **52 are the
   internal anti-pattern** (`make`, `codegen`, `UNION`, `findid`, `gc`, `instantiate`, … all
   defined in Zig elsewhere) and only **11 are genuine libc** — of which `fork`/`isatty`/
   `getcwd`/`chdir`/`times`/`sysconf` have `std.posix`/`std.c` equivalents, leaving just the
   `setjmp`/`longjmp`/`sigsetjmp`/`siglongjmp` recovery family as special (and Track A4 removes
   even that). So `main_clib` can be **slimmed to a small `std.posix` wrapper**, not preserved
   whole.

4. **The deep, deferred work is purely *representational* and independent of the FFI cleanup.**
   `R4.3/R4.4` (the `Value` union distinguishing char vs small-int immediates), `R5` (tracing
   GC), and `R6` (string interning) change *how data is stored*, not how modules call each
   other. They are gated on design, not on the linker cleanup — and vice-versa. This lets the
   two tracks proceed independently.

5. **Deleting shims surfaces latent bugs the linker hid.** `c_abi.zig` carried three stale type
   constants (`algebraic_t`/`abstract_t`/`placeholder_t`) that *disagreed* with `word.zig`, and
   a loose `getenv_error` signature that masked a real type mismatch. Loose `extern` decls hide
   drift; converting to typed `@import` aliases forces it into the open. Expect more of this as
   `main_clib`'s externs are converted.

---

## Current model (baseline facts, captured 2026-06-21)

| Aspect | Today | File |
|--------|-------|------|
| Value type | `Word = i64` (was `c_long`), still conflated handle/atom/int/char | `runtime/word.zig` |
| Cell store | `std.MultiArrayList(Cell)`, `Cell{ tag: NodeTag, hd: Word, tl: Word }` | `runtime/heap.zig` |
| Allocation | `make(tag,h,t)` free-list scan + sign-bit mark-sweep `gc()` | `runtime/heap.zig` |
| Atoms | `NIL=CMBASE+138`, combinators `< CMBASE`, chars `0..255` | `runtime/word.zig` |
| Numbers | bignums = chains of `INT` cells (15-bit digits); doubles = 2 Words reinterpreted | `runtime/big.zig` |
| Strings | `[*:0]` C pointer cast into a `Word`, stored in `id`/`fil` nodes | `runtime/heap.zig` |
| I/O | `std.fs` / `std`-based; bespoke `FILE` machinery now in `word.zig` | `runtime/word.zig` |
| Recovery | `sigsetjmp`/`siglongjmp` on `rs.env` for SIGINT/SIGFPE | `driver/repl.zig` |

## Strategy

**Strangler-fig, peripheral-first**, every step keeping `zig build` green and the **full test
suite + golden corpus** byte-identical, each one PR-sized with a concrete DoD. Two now-independent
tracks remain:

* **Track A (mechanical, bounded):** finish removing the linker-as-module-system pattern and the
  gratuitous C-ABI annotations. Enabled *now* by the circular-`@import` finding; low risk,
  golden-gated, high metric-yield. Largely independent of the heap representation.
* **Track B (deep, design-bearing):** the representational changes — string interning, the
  `Value` union, the tracing GC. Higher risk; each wants a short design note first.

Do **Track A first** (it is mostly mechanical and finishes the C-ism story), then Track B, then
close out (Track C). The tracks may interleave where it helps, but Track A's low-risk wins should
not wait behind Track B's design work.

---

## Completed phases (condensed)

* **R0** — golden corpus (44 cases), data-model scorecard, dump round-trip test. ✅
* **R1** — entire `clib` C-stdlib shim replaced with Zig `std` (memory, strings, output, input,
  files, process/env, misc). `clib.`/`c.` call sites **2821 → 0**. ✅
* **R2** — `Heap` struct owns the store; raw `hd[`/`tl[`/`tag[` access confined to `heap.zig`
  (metric **290 → 0**). ✅
* **R3** — storage swapped to `std.MultiArrayList(Cell)` with a typed `NodeTag` enum; the
  interleaved `*2` layout and the dead `hd`/`tl`/`tag` mirror are gone. ✅
* **R4.1/4.2** — `word.Ref` handle newtype + named classifiers (`isAtom`, `fitsInByte`,
  `isLatin1Char`); magic-threshold comparisons (`< ATOMLIMIT`, `< 256`) metric **→ 0**. ✅
* **R4.5** — `Word = c_long` retired for native `i64`. ✅
* **R7.3** — linker-as-module-system removal (partial): `extern fn` **322 → 71** via
  circular-`@import` aliasing; dissolved the `trans↔types` and `reduce_core↔reduce` "cycles". ✅
* **R8.1** — **`c_abi.zig` deleted** (−557 lines); 516 `abi.X`/`shim.X` refs across 15 files
  redirected to real modules; c_abi-only symbols relocated to honest owners. ✅

---

## Remaining roadmap (new sequence)

### Track A — Finish the C-ABI / linker cleanup *(mechanical, bounded, do first)*

* **A1 (R7.3b) — Dissolve `main_clib.zig`'s `extern fn` anti-pattern.** ✅ **Done.** Converted the
  52 internal-Zig `extern fn` (`make`, `codegen`, `UNION`, `findid`, `gc`, `instantiate`, …) to
  `@import` re-exports; main_clib `extern fn` 63 → 11, codebase 71 → 19. Latent drift surfaced and
  fixed (finding #5): `out_pattern` wants `*FILE` not `?*FILE`, `getstring` returns `?[*:0]u8`.
  *Remaining:* the 11 genuine libc externs (`setjmp`/`longjmp` family + `fork`/`isatty`/`getcwd`/
  `chdir`/`times`/`sysconf`) still sit in `main_clib`; moving the 6 syscalls to `std.posix` and
  retiring the `setjmp` family (A4) would finish the "thin wrapper" goal — deferred follow-up.

* **A2 (R7.4) — Eliminate `extern var` (54 → 0).** ✅ **Done.** All 30 globals now accessed via
  their owner module (`core_state` for the C-ABI-constrained 8, plus `heap`/`reduce`/`version`/
  `big`/`dump`/`combinator`); removed every `extern var` incl. main's 16 `pub extern var`
  re-exports. A Zig-token-aware replacer (skipping strings/comments) handled the bare-identifier
  rewrites; `main.X` (152 refs) redirected to `OWNER.X`. `extern var` = **0**.

* **A3 (R7.5) — Strip gratuitous `export fn` (174 → 3).** ✅ **Done.** `export fn` → `pub fn`
  everywhere except the 3 still referenced by an extern decl (`fromUTF8` ×2, `reduce_stream_read`)
  — those clear when their bridges convert. Signal handlers `reset`/`fpe_error`/`dieclean` had
  their (export-implicit) `callconv(.c)` made explicit so the OS-callback ABI survives; `walktype`'s
  gratuitous callback `callconv(.c)` was dropped. `main_entry` keeps `callconv(.c)` but loses
  `export` (called via `@import`; the real entry is `main.zig`'s `pub fn main`).

* **A4 (R7.1 + R7.2) — Signals & `callconv`.** Two parts:
  * *Strip the gratuitous `callconv(.c)`* on pure-Zig function pointers (char-class predicates
    `okid`/`okulid`/`okpath`/`hash`, `walktype`'s callback, `kollect`'s param, `main_entry`) —
    these are not FFI. *(mechanical)*
  * *Recovery redesign:* replace the `sigsetjmp`/`siglongjmp`-on-`rs.env` SIGINT/eval-abort path
    with a checked atomic flag polled by the reducer/REPL loop +
    `MiraError.EvaluationInterrupted` propagation; reduce signal handling to **one** minimal
    `callconv(.c)` trampoline registered via `std.posix.sigaction`; replace
    `main_entry(callconv(.c))` with Zig `pub fn main`. *DoD: `callconv(.c)` = 1 (documented);
    Ctrl-C during eval returns to the prompt via the flag path; golden + an interrupt test green.*

> **End of Track A:** the C-ism elimination DoD is essentially met — `extern fn` = syscall floor
> (via `std.posix`), `extern var` = 0, `export fn` = 0, `callconv(.c)` = 1. Only the
> representation (Track B) separates the project from the full redesign DoD.

### Track B — Representation *(deep, design-bearing; after Track A)*

* **B1 (R6) — String interning.** Intern identifiers/dictionary strings into a `StringTable`
  (`std.StringHashMapUnmanaged` over an arena) returning a `StrId`; `id`/`fil` nodes hold a
  `StrId`, not a pointer-as-int. *DoD: scorecard `[*:0]`-as-`Word` casts **132 → 0**; table unit
  tests + golden green.* Most bounded of the three; do it first.

* **B2 (R4.3/4.4) — `Value` union (the hard core).** Introduce a tagged representation that
  distinguishes the four roles of `Word` — chars and small ints both occupy bare values `0..255`,
  so only a union/tagged-handle can tell them apart. Migrate the reducer (R4.3) then the
  compiler/parser (R4.4) to `Ref`/`Value`. **Gate on a short design note** (union layout vs
  NaN-box/tagged-handle; performance budget for the reduction loop). *DoD: `reducer/*` and the
  compiler free of raw `Word` arithmetic; golden green on evaluation-heavy programs.*

* **B3 (R5) — Tracing GC.** Replace the sign-bit free-list mark-sweep with a precise tracing
  collector over the `Ref` graph: explicit typed root set, mark/sweep rebuilding the free list
  from a side `std.DynamicBitSet` (drops the tag sign-bit trick, making `NodeTag` fully
  exhaustive). Best after B2 (a clean `Ref` graph to trace). *DoD: precise-root unit tests + GC
  stress test stable; golden green.*

### Track C — Close-out

* **C1 (R8.2) — Final scorecard.** Against the *revised* DoD: `extern fn` = syscall floor,
  `extern var` = `export fn` = `clib.` = 0, `callconv(.c)` = 1. *DoD: `scripts/idiomatic-check.sh`
  shows the target row; document the syscall floor.*
* **C2 (R8.3) — Rewrite the data-model docs.** Update `ARCHITECTURE.md` (cell store, GC, strings,
  I/O) and `ZIG_MIGRATION.md` to describe the new model. *DoD: docs match code.*

---

## Dependency order / recommended sequence

```
Track A (mechanical, do first; mostly independent of each other):
  A1 main_clib extern fn ─┐
  A2 extern var          ├─► A3 strip export fn ─► A4 signals/callconv ─► (C-ism DoD met)
                          ┘
Track B (representation; after A, each gated on a design note):
  B1 string interning ──► B2 Value union ──► B3 tracing GC
Track C:
  C1 final scorecard ──► C2 doc rewrite
```

**Recommended order:** A1 → A2 → A3 → A4 → B1 → B2 → B3 → C1 → C2, committing each step.
A1–A3 are mechanical and may interleave/parallelise; A4 and all of Track B each warrant their own
focused session. B1 (string interning) is the lowest-risk representational change and is a good
re-entry point after Track A.

## Risk register

| Step | Risk | Mitigation |
|------|------|------------|
| A1 main_clib | latent signature drift hidden by loose externs | typed `@import` aliases force mismatches to compile errors; golden byte-diff |
| A2 extern var | mutable-alias semantics (can't `const`-alias a `var`) | access `module.X` directly; coordinate with in-flight `core_state.zig` |
| A4 signals | async-signal safety | single trampoline + atomic flag; matches IDIOMATIC_ZIG_PLAN E3 |
| B1 strings | representation change to id/fil nodes | dump round-trip (R0.3) + golden; `StringTable` unit tests |
| B2 Value union | pervasive; the hard core; hot reduction loop | design note first; per-subsystem; `Heap` seam; performance budget |
| B3 GC | use-after-free / leaks | precise-root unit tests + GC stress test |

## Notes on the irreducible boundary

The OS delivers signals through the C ABI, so **one** `callconv(.c)` trampoline must remain (A4) —
the async-signal constraint documented as E3 in
[IDIOMATIC_ZIG_PLAN.md](IDIOMATIC_ZIG_PLAN.md). Beyond that, the only C-ABI is the OS syscall
surface, which Zig exposes idiomatically through `std.posix`/`std.c` — not a bespoke `extern fn`
shim. Everything else — memory, I/O, strings, the entire cell model, all inter-module calls —
becomes pure, idiomatic Zig.

---

## Scorecard (data-model metrics)

| Metric | R0 baseline | Now (2026-06-23) | Target |
|--------|-------------|------------------|--------|
| `extern fn` declarations | 322 | **19** | syscall floor (`std.posix`) |
| &nbsp;&nbsp;↳ internal anti-pattern (convertible) | — | 0 | 0 |
| &nbsp;&nbsp;↳ genuine libc/syscall | — | ~17 (11 in `main_clib`) | small `std.posix` set |
| `extern var` declarations | 94 | **0** ✓ *(A2)* | 0 |
| `export fn` (linker symbols) | 174 | **3** *(A3; still-extern-referenced bridges)* | 0 (no external linkers) |
| `clib.` / `c.` call sites | 2821 | **0** | 0 |
| `callconv(.c)` | 12 | **13** *(A3 made 3 signal handlers explicit; A4 reduces to 1)* | 1 (signal trampoline) |
| raw `hd[`/`tl[`/`tag[` outside `heap.zig` | 290 | **0** | 0 |
| `[*:0]`-as-`Word` pointer casts | 129 | **132** | 0 (string interning, B1) |
| `Word = c_long` (value type is a C type) | yes | **no — `i64`** | `i64` |
| bare `< ATOMLIMIT` / `< 256` magic thresholds | ~23 | **0** | 0 |

---

## Progress log

**R1–R3 (foundation).** `clib`→`std` complete (`clib.`/`c.` = 0); heap encapsulated behind a
`Heap` object (raw cell access = 0); storage is now `std.MultiArrayList(Cell)` with a typed
`NodeTag` enum, the `*2`/dual-pointer arithmetic and dead mirror gone. Verified byte-identical
(golden 44/44, dump round-trip, GC-heavy eval, real dump+undump).

**R4 (partial: R4.1/4.2/4.5).** `word.Ref` handle newtype + named classifiers replace every magic
threshold (metric → 0); `Word = c_long` retired for native `i64`. **R4.3/4.4 deferred** — the
`Value` union (char vs small-int immediates) is a fat-cell change in the hottest code and is
Track B2.

**R7.3 (linker-as-module-system removal).** Key finding: circular `@import` makes cross-module
`extern fn` unnecessary. Converted `extern fn foo` → `const foo = module.foo` across
`trans`/`types`/`codegen`/`reduce_core` and every consumer file, dissolving the `trans↔types` and
`reduce_core↔reduce` "cycles". Non-shim `extern fn` 81 → 8; codebase 322 → 75 → **71**
(byte-identical). The 8 non-shim survivors are genuine syscalls + one ABI bridge + dead
`utf8.zig`.

**R8.1 (`c_abi.zig` deleted).** The 557-line "compiler ABI" hub is gone; 516 `abi.X`/`shim.X`
references redirected to real modules; relocations: `NodeTag`/tag-bit constants → `word.zig`,
`tries`/`stosmallint` → `heap.zig`, `cmbnms`/`outUTF8`/`fromUTF8` → `main_clib.zig`, `yysterm` →
`setup.zig`. Removed three stale dead constants that disagreed with `word.zig`. Byte-identical.

**Next:** Track A1 — dissolve `main_clib.zig`'s 52 internal `extern fn` the same way, slimming it
toward a `std.posix` wrapper.
