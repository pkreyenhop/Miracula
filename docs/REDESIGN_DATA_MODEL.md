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
| Linker-as-module-system (R7.3) | ✅ `extern fn` 322 → **14** (syscall floor); `c_abi.zig` **deleted** (R8.1) |
| Track A1 — main_clib externs | ✅ 52 internal `extern fn` → `@import`; main_clib at 11 libc externs |
| Track A2 — `extern var` | ✅ **0** — all 30 globals accessed via owner module |
| Track A3 — `export fn` | ✅ 174 → **3** (only the still-extern-referenced bridges remain) |
| Track A4a — strip gratuitous `callconv` | ✅ `callconv(.c)` 13 → **6** (genuine signal boundary) |
| Track A4b — recovery redesign | ⬜ Re-scoped — design-bearing (SIGFPE synchronous; reducer unwind; unverifiable by golden) |
| `Value` union (R4.3/4.4) | ◐ B2(a) seam started — `word.Value`/`classify`; char boundary migrated (Track B2) |
| Tracing GC (R5) | ⬜ Planned (Track B3) |
| String interning (R6) | ✅ Done — nodes hold an interned `StrId` (`strtab.zig`); node-string casts → **0** (Track B1) |

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
| Strings | interned `StrId` (negated index into a `StringTable`) stored in `id`/`fil` nodes | `runtime/strtab.zig` |
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
  *Follow-up done:* `fork`/`isatty`/`getcwd`/`chdir`/`sysconf` moved to `std.c` bindings
  (extern fn 19 → 14). The 6 left in `main_clib` are the genuine no-std-equivalent floor — the
  `setjmp`/`longjmp` recovery family (×5, clears with A4b) and `times` (no `std.c.times`/`tms` in
  0.16).

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

* **A4a — Strip gratuitous `callconv(.c)`.** ✅ **Done.** Dropped the C calling convention on the
  pure-Zig char-class predicates (`okid`/`okulid`/`okpath`/`hash`/`isconstrname`), `kollect`'s
  param type, `walktype`'s callback (in A3), and `main_entry` (called from `main.zig`'s `pub fn
  main`, not by C). `callconv(.c)` 13 → **6**.

* **A4b — Recovery redesign (re-scoped; *not* a mechanical sweep).** The remaining 6 `callconv(.c)`
  are the genuine OS-signal boundary: handlers `reset`/`fpe_error`/`dieclean`/`sigdefer` and the
  two saved-old-handler pointer-cast types. Reaching the original "`callconv(.c)` = 1" target was
  going to replace `sigsetjmp`/`siglongjmp`-on-`rs.env` with an atomic flag. Examining the code
  shows this is **design-bearing and partly infeasible as written**, so it is re-scoped:
  * **SIGFPE is a *synchronous* CPU fault** (FP overflow mid-instruction). It cannot be
    cooperatively polled; recovery is either `siglongjmp` from the handler (current) or wrapping
    every float/bignum op in `feclearexcept`/`fetestexcept` checks — a large arithmetic rewrite.
  * **SIGINT unwinds the reducer.** `reset`'s `siglongjmp` aborts a running evaluation; replacing
    it with a flag means the hot `reduce()` loop (returns `Word`, not `!Word`) must poll and
    propagate `error.Interrupted` through the whole reduction call graph — an R4.3-sized change to
    the hottest code.
  * **The golden corpus cannot verify signal behaviour** (it never raises SIGINT/SIGFPE), so any
    recovery rewrite is unverifiable by the automated suite and needs dedicated manual testing.

  *Therefore:* `callconv(.c)` = **6** is the realistic floor under the current architecture; the
  flag-based redesign is deferred to a focused, manually-tested effort (design note first), and is
  better treated as **Track B-class** work (risky, representation-adjacent) than a mechanical
  Track-A sweep. The `setjmp`/`longjmp` libc externs in `main_clib` stay until then.

> **End of Track A (A1–A4a):** the *mechanical* C-ism elimination is essentially complete —
> `extern fn` = syscall floor, `extern var` = 0, `export fn` = 3 (extern-referenced bridges),
> `callconv(.c)` = 6 (genuine signal boundary). Driving `callconv` to 1 and `export fn`/the libc
> externs to their final floor depends on the A4b recovery redesign, which is design-bearing.

### Track B — Representation *(deep, design-bearing; after Track A)*

* **B1 (R6) — String interning.** ✅ **Done (steps 1 & 2).**
  * *Step 1 (encapsulation) ✅* — funnelled the ~63 scattered raw casts that read/write node-stored
    identifier strings through three audited accessors in the leaf `word.zig` (`strOf`/`strOfMut`
    read, `strBits` write). Pure refactor, golden byte-identical.
  * *Step 2 (the actual interning) ✅* — a new module-global owner **`strtab.zig`** holds a
    `StringTable` (an `ArenaAllocator` of bytes + `StringHashMapUnmanaged(StrId)` dedup +
    `ArrayList([:0]const u8)` index). `strBits(bytes)` interns (de-dup by content) and returns a
    `StrId`; `strOf(strid)` resolves it. A node now stores a `StrId`, not a pointer. The accessors
    moved out of leaf `word.zig` (it stays allocator-free); the ~68 call sites became a mechanical
    `word.strOf` → `strtab.strOf` rename (decision **A** from the design note — module-global owner,
    no allocator threaded through signatures). `strOfMut` removed. De-dup is what keeps the
    re-intern-then-compare pattern (`member(list, strBits(get_id(x)))`) working now that `get_id`
    no longer returns a stable pointer.

    **Encoding — the one design-note correction.** The note assumed a *non-negative* index packed
    into the `Word`. That is unsafe: heap cell handles live in `[ATOMLIMIT, TOP())` and the GC's
    `mark` follows `hd`/`tl` of traced nodes; raw string Words sit in some *traced* slots (a
    `CONS.hd` in `exportfiles`, a `CONSTRUCTOR.tl`) and were only GC-safe because the old pointers
    were *above* `TOP()`. A small positive index would fall *inside* the cell range and be
    mis-followed. So a `StrId` is stored **negated** (`-index`): below `ATOMLIMIT`, and even after
    `mark`'s `& ~tlptrbits` it lands far above `TOP()` — `isptr()` is false either way, preserving
    GC behaviour at every slot without auditing each one. `Word` 0 stays the "no string" sentinel.

    **Findings corrected during implementation (the step-1 funnel was incomplete):**
    - *`mkprivate` mutates a node string in place* (`get_id(..)[0] += 128` to hide prelude names) —
      so design-note finding #2 ("nothing mutates a node string") was wrong. Interned bytes are
      immutable/shared, so it now re-interns the privatised form (`strtab.privatize`) and stores the
      new id back. (Finding #1 held: the namebucket dedups by *content*, so dedup is a memory win,
      not a correctness requirement.)
    - *FILE\* handles were stored in cells via `strBits` too* (`fileq`, `outfilq`) — these are
      FILE-handle-in-cell casts (out of B1 scope; read back via `@ptrFromInt`), wrongly funnelled by
      step 1. Restored to explicit raw casts at the 4 write sites.
    - *`getIdText` (`lex_bridge.zig`) read a node string via a raw `@intCast`/`@ptrFromInt`* that
      bypassed the accessors entirely; routed through `strtab.strOf`.

    *Result:* node-string pointer casts **→ 0** (every read/write goes through the table; the
    remaining ~68 `@intFromPtr`/`@ptrFromInt` are FILE-handle, pointer-arithmetic, and signal-handler
    casts — none are strings). Verified: `zig build` green; **golden 44/44 byte-identical**;
    `main-tests` **35/35** (incl. new `strtab` intern/dedup/resolve + 0-sentinel tests and the dump
    round-trip). Test inclusion wired via `main.zig`'s `comptime` import aggregator.

* **B2 (R4.3/4.4) — `Value` union (the hard core).** ◐ **Design note (scoped; awaiting a
  representation decision before any code).**

  **The problem, precisely (from the code).** A `Word` (`i64`) is overloaded with four roles, told
  apart today by *numeric range* + *cell tag*, not by the value itself:
  | role | representation today | discriminator |
  |------|----------------------|---------------|
  | heap-cell handle | `>= ATOMLIMIT` (447) | `isAtom(x)` range test |
  | atom (combinator / token / named) | `256 .. ATOMLIMIT` | range tests vs `CMBASE`/`ATOMLIMIT` |
  | char | bare `0..255` (Latin-1) or a `UNICODE` cell | `is_char` = "is it in char range?" |
  | number | boxed: `INT`-cell bignum chain / `DOUBLE` cell | cell `tag` |

  The sharp edge: a bare `0..255` value is **structurally identical** whether it is the char `'A'`
  or a small-int immediate, and `getTag` is undefined on a bare value (no cell). The runtime gets
  away with this because Miranda is statically typed — the *compiler* knows each value's role and
  emits the right combinator (`CODE`/`DECODE` to cross char↔int, `cmp` dispatching on tag). So the
  ambiguity is *erased at runtime* and reconstructed from operator context. B2 re-introduces an
  explicit runtime discriminator so values are self-describing.

  **Why it is the hard core.** The reducer is a **pointer-reversal graph-reduction machine**
  (`reduce.zig` + `reducer/*.zig`, ≈4 200 lines) that encodes spine direction in the *top two bits*
  of the spine word (`tlptrbits`/`tlptrbit`) and masks them off (`x & ~tlptrbits`) on every `hd`/`tl`
  access, and uses `ctx.s < 0` (sign bit) for the reversed-pointer test. Any tagged `Value` competes
  for those same high bits and sits in the hottest loop in the program — hence the plan's
  "performance budget" caveat. Cells are `MultiArrayList(Cell{ tag: NodeTag(u8), hd: i64, tl: i64 })`,
  so widening a slot to a fat `Value` is a cross-cutting storage change.

  **The representation fork (decision needed — see options below).**
  1. **Tagged-handle / low-bit tagging** — keep `Word = i64`, steal a bit-pattern to mark
     "immediate char" vs "immediate int" vs "handle/atom". *Pros:* no cell-size change; reducer stays
     word-based. *Cons:* the value space is already dense (`0..255` chars, `257..305` tokens,
     `306..447` atoms, `>=447` cells) and the top bits are taken by `tlptrbits`; finding free bits
     ripples through `ATOMLIMIT`/`CMBASE` and the GC's `isptr` range test. Lowest memory/perf cost,
     highest "subtle bit-budget" risk.
  2. **Tagged `Value` union (fat cell)** — `union(enum){ ref, atom, char: u21, int }` stored in cells.
     *Pros:* type-safe, self-describing, the cleanest end state; matches the DoD's spirit. *Cons:*
     fattens every cell, and the pointer-reversal machine must be reworked to carry the spine mark
     beside (not inside) the value — a deep rewrite of the hot loop with a real perf/memory hit.
  3. **NaN-boxing** — pack a tag into the unused bits of an `f64`. *Pros:* one 64-bit slot, fast on
     float-heavy code. *Cons:* fights the existing integer bit-tricks (sign-bit spine, `tlptrbits`)
     and the `INT`-cell bignum design; poor fit for an integer-pointer-reversal machine. Likely
     *rejected* but listed for completeness.

  **Recommended staging (independent of which option wins).** This is not a one-shot change; the
  plan already says *per-subsystem*. Proposed order, each step golden-gated and PR-sized:
  0. **Immediate-role audit** — enumerate every site where a bare `0..255` is produced/consumed as a
     char vs as a small-int vs as an atom (this audit *is* the load-bearing design work; the DoD
     "free of raw `Word` arithmetic" can't be scoped without it).
  1. Introduce `Value` (+ `Heap` seam: typed `hd`/`tl` getters/setters) behind the existing `Word`
     API, no behaviour change.
  2. Migrate the reducer (R4.3) operation-class by operation-class (arithmetic → char ops → list ops),
     golden after each.
  3. Migrate the compiler/parser (R4.4).
  4. Drop the raw-`Word` accessors.

  **Gate.** Pick the representation (option 1/2/3) and confirm the staging before any code — the
  choice is hard to reverse once the reducer migration starts, and it sets the perf budget. *DoD
  (unchanged): `reducer/*` and the compiler free of raw `Word` arithmetic; golden green on
  evaluation-heavy programs; a reduction-loop micro-benchmark within the agreed budget.*

  **Audit (step 0) — findings that reframe B2.** Read-only enumeration of every bare-`0..255`
  immediate and its discriminator (surface: ~31 char sites, ~50 int sites — heaviest in
  `reducer/ready.zig` arithmetic — and ~14 range classifiers). Three findings change the picture:
  1. *User numbers are **always boxed** (`INT`/`DOUBLE` cells).* `stosmallint`/`big.sto_int` always
     `make(INT,…)`; arithmetic combinators return `stosmallint(…)`; `get_int` assumes a cell. So at
     runtime **char-vs-number is already disambiguated by cell tag** — there is no live char/number
     ambiguity in the reducer. The plan's "chars and small ints both occupy bare `0..255`" is true
     only of *structural* small-ints, not user numbers.
  2. *Every bare `0..255` small-int is structural and tag/context-identified:* char codes; **indices**
     (`trans.mkindex` keeps an index bare iff `< 256`, else boxes — used for subscripts / constructor
     arities); constructor tags (`CONSTRUCTOR.hd`); a packed `(line,col)` in `reducer/lex.zig`; node
     counters. The genuine char/immediate overlap is **narrow and lives in the compiler (R4.4)**, not
     the reducer — `mkindex`/`types.zig` are where a bare value's role is least self-evident.
  3. *The dominant "raw `Word` arithmetic" in the reducer is the **pointer-reversal spine encoding**,
     not value classification.* `& ~word.tlptrbits` masks every `hd`/`tl` access and `ctx.s < 0`
     tests the reversed-pointer mark. A `Value` union does **not** remove this — the DoD "free of raw
     `Word` arithmetic" is unreachable without *also* replacing pointer-reversal with an explicit
     spine stack, a separate and larger change (which would, however, also unblock B3's precise GC
     roots and A4b's interrupt flag).

  **Audit's bottom line.** As originally framed (a `Value` union to tell char from int), B2 buys
  *less* than the plan implies — boxing already separates char from number — while carrying the
  highest hot-loop risk, and it cannot meet its own DoD without the bigger pointer-reversal rework.
  Three honest directions for the decision (was "pick option 1/2/3"; the audit adds a fourth axis —
  *whether the Value union is even the right hard-core target*):
  * **(a) Re-scope B2** to a typed `Value` only at the `Heap` immediate boundary (char / index / atom
    / ref), eliminating range-based classification at value reads/writes; accept that spine encoding
    stays and reword the DoD accordingly. Medium effort, type-safety win, modest correctness gain.
    **◐ Chosen and started.** `word.Value` (`imm` / `atom` / `ref`) + `word.classify()` land the seam
    (with a unit test); the canonical char-immediate boundary is migrated — `heap.get_char`/`is_char`
    and `lex_bridge`'s string-CONS decode now `switch (classify(x))` instead of chaining
    `isAtom`/`fitsInByte`/`isLatin1Char`. Behaviour-preserving (golden 44/44 byte-identical).
    *Follow-up migration (incremental, golden-gated):* the remaining range-test sites — `trans.zig`
    (`mkindex`/`getarg`-style `isAtom` ×3), `types.zig`, `reduce.zig`'s printer/`out` paths — and a
    typed `Heap.hd`/`tl` value accessor on top of `classify`. *Reworded DoD: value reads/writes go
    through `classify`/`Value` (range tests → 0 at migrated sites); spine encoding stays raw (that is
    option **b**'s job).*
  * **(b) Repivot the "hard core"** to pointer-reversal → an explicit typed spine stack — this is what
    actually dominates raw-`Word` arithmetic and unblocks B3 + A4b. Higher value, comparable risk.
  * **(c) Defer B2**: since boxing already disambiguates char/number, do B3 (tracing GC) or the
    close-out (C1/C2) first and revisit the value representation later.

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
| `extern fn` declarations | 322 | **14** | syscall floor |
| &nbsp;&nbsp;↳ internal anti-pattern (convertible) | — | 0 | 0 |
| &nbsp;&nbsp;↳ genuine libc/syscall | — | 14 (6 in `main_clib`: `setjmp`×5 + `times`) | `setjmp` family clears with A4b |
| `extern var` declarations | 94 | **0** ✓ *(A2)* | 0 |
| `export fn` (linker symbols) | 174 | **3** *(A3; still-extern-referenced bridges)* | 0 (no external linkers) |
| `clib.` / `c.` call sites | 2821 | **0** | 0 |
| `callconv(.c)` | 12 | **6** *(A4a stripped gratuitous; floor is the genuine signal boundary)* | 1 (needs A4b recovery redesign) |
| raw `hd[`/`tl[`/`tag[` outside `heap.zig` | 290 | **0** | 0 |
| node-string `[*:0]`-as-`Word` casts | 129 | **0** ✓ *(B1: interned `StrId` via `strtab.zig`)* | 0 |
| &nbsp;&nbsp;↳ non-string `@intFromPtr`/`@ptrFromInt` (FILE-handle / ptr-arith / signal) | — | 68 | enumerated (not B1) |
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
