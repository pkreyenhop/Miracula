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
`main()`, every subsystem reaching its state through the narrowest struct(s) it
actually needs — `*Heap`, `*Bignum`, `*ReductionCtx`, a purpose-built bundle, or
(for the orchestration/driver layer, where it's genuinely appropriate)
`*Interp` — **zero** module-scope mutable `var`/`export var` in non-FFI code save
one `current_interp: *Interp` used only by signal handlers (documented). See
Phase 5 below for why "narrowest struct" rather than "thread `*Interp`
everywhere" is the resolved design, and for the tiered, checkpointed plan to get
there (partially — Tier 3 may remain permanently out of scope by design).
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

### Phase 5 — Thread narrow substructures, not the whole `*Interp` *(revised 2026-07-01)* — ⬜ **deferred, re-scoped**

**Still deferred by the 2026-06-24 decision** (the practical payoff — encapsulation
+ a resettable `interp` for test isolation — is already captured at Phase 4; the
remaining benefit of any further threading is multiple independent interpreter
instances / re-entrancy, not needed today). This section **resolves an ambiguity**
in the original Phase 5 wording ("taking/holding `*Interp` … *or* a threaded first
parameter") in favour of the narrower option, and records the entanglement survey
that grounds *why*, so a future resumption doesn't have to re-derive it.

**Why narrow, not the monolith.** Threading the full `*Interp` through every
subsystem gives back exactly the readability problem de-globalization is meant to
fix: since almost every function in an interpreter touches *some* state, most call
sites would gain an `interp: *Interp` parameter that is only ever forwarded, not
read — boilerplate, not a narrower signature. The real win — a function signature
that shows *exactly* which state it touches — only materializes if each subsystem
takes the smallest struct(s) it actually needs (`*Heap`, `*Bignum`, a
purpose-built context, …), not the nine-struct aggregate.

**This is not hypothetical — it's already the pattern in one subsystem.** The
reducer's rewrite-handler layer (`combinators.zig`, `ready.zig`, `reducer/lex.zig`,
`io.zig`) already takes `ctx: *ReductionCtx` — a purpose-built bundle, not
`*Interp` — for nearly everything. An audit of what these files *still* touch via
ambient global access, beyond `ctx`, found:

| File | fns | external-singleton fields touched beyond `ctx` |
|------|----:|--------------------------------------------------|
| `combinators.zig` | 48 | **0** |
| `reducer/lex.zig` | 33 | **0** |
| `reducer/io.zig` | 4 | **0** |
| `ready.zig` | 6 | **2** (`rt.rs.UTF8`, `rt.rs.linebuf` — scratch buffers) |

i.e. this subsystem is already ~98% narrowly-threaded by accident of the B2(b)
`Spine` cutover, which only had to design `ReductionCtx` for the reducer's own
needs (`e`/`spine`/`hold`/`args`/`action`) and happened to leave almost nothing
else ambient.

**Entanglement survey (2026-07-01), to calibrate expectations for everything
else.** For each remaining subsystem: does it depend on at most one *other*
struct (clean — narrow threading is a clean win), or does it routinely need
several simultaneously (entangled — narrow threading degenerates into passing
3–5 pointers, or a bundle nearly as wide as `Interp`)?

| Subsystem | Home struct | External deps | Verdict |
|-----------|------------|----------------|---------|
| `big.zig` (Bignum) | none (module constants) | `Heap` only (7 cell-accessor call sites) | **Clean** |
| `strtab.zig` (StringTable) | `StringTable` | none | **Clean** |
| reducer rewrite handlers | `ReductionCtx` (now owns `heap: *Heap`, Tier 1.5 ✅) | `RuntimeState` (2 scratch fields in `ready.zig`, Tier 2 ✅ — documented exception, deliberately left ambient) | **Done** |
| `heap.zig` | `Heap` | `LexState` (58 sites, dict buffer), `RuntimeState`, `CompilerState`, `CoreState` — 133 fns total, only 11 already self-threaded | **Entangled** |
| `types.zig` / `trans.zig` / `lex.zig` / `module_loader.zig` (compiler+parser core) | `CompilerState`/`LexState` | type info, source location, heap cells, and lexer state simultaneously, pervasively | **Entangled** |
| `repl.zig` / `commands.zig` / `startup.zig` (driver) | — | legitimately needs most of the interpreter to dispatch commands | **Not a narrowing candidate** — this layer *should* look Interp-shaped |

**Revised strategy — three tiers, with a checkpoint before the hard tier:**

1. **Tier 1 — clean leaves. ✅ Done (2026-07-01).** `big.zig`: every function now
   takes an explicit `*Heap` (turned out to be nearly all of them, not just ~7
   sites — a bignum is a chain of heap cells, so even the leaf digit accessors
   needed it) plus `*Bignum` for the 7 functions touching the division-remainder/
   log-cache scratch. `strtab.zig`: took just `self: *StringTable` as predicted —
   `strBits`/`strOf`/`privatize`/`deinit` all threaded, with a private
   `ensureInit(self)` replacing the old ambient lazy-init check. Actual call-site
   count: big.zig 53 (close to the ~59 estimate), strtab.zig **67** — wider than
   bignum despite having *zero* external struct dependencies (every identifier/
   pathname intern or resolve in the parser/compiler/runtime goes through it).
   Both `bn`/`heap.heap`/`strtab.table` stay as package-level convenience
   constants so callers have something to pass in — Tier 3 (making those
   singletons themselves non-global) is separately scoped and deferred.
   *DoD met: zero ambient-singleton reads in `big.zig`/`strtab.zig`; 48/48 golden,
   166/166 unit tests, 7/7 spine-corpus, lint clean.* While smoke-testing,
   surfaced one pre-existing, unrelated bug (hex/octal literals like `0xff`/
   `0o777` parse to the wrong value — confirmed via `git stash` to predate this
   work) — flagged as a separate follow-up, not fixed here.
2. **Tier 1.5 — `ReductionCtx.heap` (2026-07-01) ✅ done, larger than expected.**
   Attempting to schedule "reducer" as its own small step (per the original
   `bignum → reducer → heap/GC → …` ordering) revealed those two aren't
   separable: `reduce_core.zig`'s own primitives (`hdGet`/`hdSet`/`tlGet`/
   `tlSet`/`getTag`/`setTag`/`ap`/`ap2`/`cons`/`rewriteToXxx`/…) are thin
   wrappers directly over `heap.zig`'s own `Heap.h`/`Heap.hp`/`Heap.make`/etc.
   methods (which were already self-threaded, just never called with an
   explicit pointer at this boundary). Since `ReductionCtx` is already threaded
   through every reducer rewrite-handler, the fix was to give it a `heap: *Heap`
   field and have the ~45 leaf primitives in `reduce_core.zig` take an explicit
   `heap: *Heap` parameter — functions that already carry `ctx` pass `ctx.heap`
   through rather than gaining a second parameter. `reducer/reduce.zig` (the
   engine loop) initialises `ctx.heap` once per `reduce()` call from the
   (still-global) `heap.heap` singleton. Updated ~500 call sites across
   `combinators.zig`, `ready.zig`, `io.zig`, `reducer/lex.zig`,
   `reducer/reduce.zig`, plus `testutil.zig`'s and `reduce_test.zig`'s own
   `ap`/`ap2`/`cons` test-helper wrappers (kept their existing 2/3-arg public
   signatures — hundreds of test call sites elsewhere were untouched).
   **This does *not* thread `heap.zig` itself** — its own methods were already
   `self`-taking; this step only stopped the *reducer's* call sites from
   reaching the global singleton to get that `self`. Threading `heap.zig`'s
   ~432 call sites system-wide (compiler/parser/driver too) remains full Tier 3.
   *DoD met: `zig build check` (build + 176 unit tests + 48/48 golden +
   spine-corpus stress + sigint + smoke) all green; lint at the 17-warning
   pre-existing baseline; manual smoke test of `fib 27`/`map`/an undefined-name
   error (forked-child isolation still correct) all behave correctly.*
3. **Tier 2 — tidy the existing `ReductionCtx` precedent. ✅ Done (2026-07-01),
   resolved as "document, don't fold".** Checked the breadth of `ready.zig`'s
   two remaining ambient touches before deciding: `rt.rs.linebuf` is also used
   in `commands.zig`/`reduce.zig`/`lex.zig`/`parser_tests.zig`/`dump.zig`, and
   `rt.rs.UTF8` also in `startup.zig`/`commands.zig`/`reduce.zig`/`lex.zig` —
   both are whole-interpreter shared state, not reducer-local. Folding them
   into `ReductionCtx` (the reducer's *own* register file) would have been a
   category error, not a narrowing. Added a doc note on `ReductionCtx` itself
   recording this as a deliberate exception rather than an oversight, so a
   future reader doesn't re-litigate it.
   *DoD met: the exception is explicitly documented; no code change needed;
   `zig build` clean.*
4. **Tier 3 — the entangled subsystems: stop and re-evaluate, don't proceed by
   default.** `heap.zig`, `types.zig`, `trans.zig`, `lex.zig`, `module_loader.zig`
   each touch 3+ external structs pervasively. A single narrow struct doesn't fit
   here; the realistic options are (a) a purpose-built bundle per subsystem (e.g.
   a `CompileCtx` grouping the 3–4 structs the compiler pipeline actually uses
   together — narrower than all nine, but wide enough that the "exactly what this
   touches" clarity mostly evaporates), or (b) leave these on ambient global
   access permanently and treat Tier 1–2 as the actual, complete scope of narrow
   threading in this codebase. **Recommendation: do not commit to Tier 3 up
   front.** Land Tier 1–2, observe whether the signature clarity was worth the
   ~59-call-site churn in practice, and only then decide whether a `CompileCtx`
   bundle for Tier 3 is worth designing — it is a genuinely different, harder
   question than Tier 1–2 (bundle design, not mechanical threading), and forcing
   it into the same PR-sized mechanical pattern as Tier 1 would understate its
   risk.

**Sequencing:** `big.zig` ✅ → `strtab.zig` ✅ → `ReductionCtx.heap` ✅ (Tier 1.5) →
`ready.zig` tidy-up ✅ (Tier 2) → checkpoint (Tiers 1/1.5/2 done) → **Tier 3
committed to** (explicit user decision, overriding the "do not commit by
default" recommendation above) → **`setup.zig` increment ✅ done (2026-07-05),
first concrete file.**
Each subsystem is its own PR, golden-gated (the full 48-case corpus + unit suite
+ spine-corpus stress checks + lint), with a reducer-loop timing check (reuse
the ad hoc `fib(N)` comparison method used for the B2(b) `Spine` cutover and the
B3 GC rewrite) for anything touching the hot path.

**Tier 3, increment 1 — `setup.zig` ✅ done (2026-07-05).** Chosen as the
smallest/most tractable starting file (254 lines, ~15 heap-touch patterns,
vs. 800+ in `trans.zig`/`types.zig`). `primdef`/`predef`/`primlib`/`privlib`/
`stdlib` now take an explicit `heap: *Heap` first parameter, threaded through
each other; `miraSetup()` itself keeps its old zero-arg public signature and
grabs the ambient singleton once internally (`const heap = heap_mod.heap;`),
mirroring exactly how `reducer/reduce.zig`'s `reduce()` seeds `ctx.heap` —
this meant all 5 external callers of `miraSetup()` needed no changes; only
`module_loader.zig`'s two `setup.privlib()`/`setup.stdlib()` call sites needed
an explicit `heap.heap` argument added.

Also converted 3 free functions in `heap.zig` that `setup.zig` calls
(`constructor`, `isconstructor`, `addtoenv` — confirmed via grep to have only
4 external call sites, all in `setup.zig`) to take an explicit `Heap`/`*Heap`
parameter.

**Gotcha for future Tier 3 increments:** these 3 functions live *outside* the
`Heap` struct's own block (which spans `heap.zig` lines 93–638). Zig's
`x.method(...)` call sugar only resolves against declarations physically
inside the type's block — giving a free function a `self`/`heap` parameter
does **not** make `heap.constructor(...)` work as method-call syntax. The
compiler error is misleading (`"method invocation only supports up to one
level of implicit pointer dereferencing"`, suggesting a deref problem) but the
real fix is to call these as regular qualified functions: `constructor(heap,
...)` from within `heap.zig` itself (bare name, same file), or
`heap_mod.constructor(heap, ...)` from another file (module-qualified). Of
`heap.zig`'s 99 functions, ~74 are free functions outside the struct — expect
to hit this repeatedly as Tier 3 proceeds into `heap.zig` itself.

*DoD met: `zig build` clean; `zig build test` — 176/176 unit tests pass (run
`main-tests` directly per [[zig-build-test-listen-quirk]] rather than trusting
the `--listen` wrapper's exit code); `zig build check` — sigint check, 48/48
golden spine-differential checks, and smoke tests all green (the one
`BrokenPipe` seen on an initial `zig build test` run was a pre-existing timing
flake in `sigint_check.zig`'s child-stdin write, confirmed by 3 clean reruns
of `zig build test-sigint` in isolation — not caused by this change); lint at
16 warnings (pre-existing baseline, no new warnings); manual smoke test of
`True & False`, `show`, list comprehensions, and string concat (all exercise
primitives seeded by `setup.zig`'s `primlib`/`privlib`/`stdlib`) all correct.*

**Tier 3, increment 2 — `repl.zig` ✅ done (2026-07-05).** Confirmed before
starting that `repl.zig`'s ~18 `heap.`-prefixed touches split into two very
different categories: most (`heap.idVal`/`idType`/`idWho`/`getId`/`srcUpdate`/
`resetgcstats`/`utf8test`, plus the free-function `h`/`t`/`tp` aliased at the
top of the file) resolve to *free functions declared outside the `Heap`
struct* in `heap.zig` (confirmed via `grep -n "pub fn h(\|pub fn t(\|pub fn
tp("` — each has both a struct method at lines 93-638 and an unrelated
free-function of the same name further down, e.g. `h`'s method at line 147 vs.
its free function at line 647). Those still take no `Heap` argument at all and
were left alone — converting them is a `heap.zig`-wide change (used pervasively
elsewhere), not specific to this file. Only the handful of genuine
`heap.heap.X` accesses (`.files`, `.validate()`, `.nogcs`, `.getTag()`) were
in scope: threaded an explicit `heap: *Heap` parameter through `commandLoop`,
`obey`, `evaluateRepl`, and the local `getTag` helper. `process`/`announce`/
`reset`/`dieClean`/`fpeError`/`edWarn`/`getLine`/`badEditor`/`parseLine`
needed no change — the last three don't touch the struct at all, and `reset`/
`dieClean`/`fpeError` are OS signal-handler callbacks (`callconv(.c)`) whose
signature can't be changed regardless.

Each of `commandLoop`/`obey`/`evaluateRepl` turned out to have exactly one
external call site (`startup.zig:163`, `repl.zig`'s own `abi.obey` alias, and
`parser_api.zig:92` respectively) — confirmed by grep before converting, since
the whole point of threading is moot if a "cascade" is really just one call
site restating the ambient singleton one frame up. Went ahead anyway per
explicit instruction to do it for completeness/consistency rather than skip
low-value files.

*DoD met: `zig build` clean; 176/176 unit tests (main-tests run directly);
`zig build check`-equivalent (`zig build test`, which subsumes it) green —
48/48 golden spine-differential checks, sigint check, smoke tests; lint at 16
warnings (no new ones); manual smoke test of expression evaluation (`fib 27`,
`show 42`, `concat`), the `?name` identifier-info path (both undefined-name
diagnosis and a defined-primitive lookup) all correct. The interactive `??`
path (which additionally forks a real editor via `commands.editfile`) hangs
under piped/non-tty stdin regardless of this change — pre-existing behavior,
not a regression, and already covered independently by
`parser_tests.zig`'s `"syntax error sets errcol and editfile expands column
placeholder"` unit test, which calls `commands.editfile` directly.*

**Tier 3, increment 3 — `dump.zig` ✅ done (2026-07-05).** Real cascading
depth this time, unlike `repl.zig`. Same split as always: most of the ~126
`heap.`-prefixed touches are free-function ambient calls (`idVal`/`idType`/
`getId`/`filDefs`/`tInfo`/`getHere`/`tClass`/`alfasort`/`cons`/`srcUpdate`/
`unload`, plus `t`/`h`/`tp`/`hp`) and stay unconverted; only the genuine
`heap.heap.X` struct accesses (`.files`, `.stackp`, `.dstack`, plus the local
`getTag`/`setTag` helpers) were threaded. This meant adding `heap: *Heap` to
8 functions: `getTag`/`setTag` (the local helpers), `unpainted`, `privatise`,
`publicise`, `readoption`, `fixtype`, `undump`, `makedump`, `fixexports`,
`unfixexports` — `paint`/`unpaint` needed no change (ambient-only).

`undump` turned out to be the real cascade: 10 external call sites across 4
files (`repl.zig` x2, `startup.zig` x5, `commands.zig` x2, `module_loader.zig`
x1), the widest external surface of any function converted so far in Tier 3.
Every call site already had `heap`/`heap.heap` in scope locally (either the
module import or, in `repl.zig`'s `commandLoop`, the `heap: *Heap` parameter
from increment 2), so no further cascading was needed — one-line fixes
throughout. `readoption`'s single external caller (`types.zig:2684`, itself
a large not-yet-converted Tier 3 file) likewise already had `heap` imported.

**Process note — a sed mishap worth recording for future increments.** The
mechanical rewrite (`s/heap\.heap\./HEAPFIELD./g` then `s/heap\./heap_mod./g`
then restore `HEAPFIELD.` → `heap.`) was first attempted with a `\b` word
boundary (`s/\bheap\./heap_mod./g`) to be "safe" — this **silently no-op'd**
the entire middle substitution, because BSD/macOS `sed` (unlike GNU sed)
does not support `\b` in its regex dialect at all; it's read as two literal
characters that never match, so the command exits 0 having changed nothing.
Caught by noticing `heap.cons(...)` calls that should have become
`heap_mod.cons(...)` were untouched. The fix was to drop `\b` entirely —
safe here because after the first pass removes every `heap.heap.` occurrence,
there's no other identifier ending in "heap" immediately before a bare
`heap.` in this file (checked via `grep -n "[a-zA-Z0-9_]heap\."` before
reverting and redoing). Second gotcha from the same rewrite: the plain
`s/heap\./heap_mod./g` also matched inside the import string itself
(`@import("../runtime/heap.zig")` contains the substring `heap.`), corrupting
it to `heap_mod.zig`, a nonexistent file — caught immediately by the "file
modified externally" diff view and fixed by hand. Both are worth checking
for on every remaining Tier 3 file before trusting a bulk sed's exit code.

*DoD met: `zig build` clean; 176/176 unit tests (main-tests run directly);
`zig build test` (which subsumes `check`) green — 48/48 golden, spine-corpus
stress, sigint, smoke; lint at 16 warnings, no new ones; manual smoke test of
the dump/undump cycle (deleted `script.x`, ran the interpreter to force a
fresh compile + `makedump`, confirmed `script.x` was created, then ran again
to exercise the `undump`-from-cache path — both runs produced identical,
correct output for `fib`/`add1`).*

**Tier 3, increment 4 — `commands.zig` ✅ done (2026-07-05).** Same split as
every increment so far: most of the ~47 touches are ambient free-function
calls (`idVal`/`idType`/`idWho`/`getId`/`getHere`/`tClass`/`filDefs`/
`getFil`/`filTime`/`filShare`/`alfasort`/`cons`/`reverse`/`tp`/`h`/`t`/
`srcUpdate`/`badval`/`makeFil`), left unconverted. Threaded `heap: *Heap`
through the local `getTag` helper and the 4 functions that touch
`heap.heap.files` directly: `cmdFiles` (private, called once from
`command`), `command` (pub — threads into `cmdFiles`), `allnamescom` (pub).
`namescom`/`cmdEdit`/`editfile`/`finger`/`diagnose` needed no change
(ambient-only). External call sites: `repl.zig`'s `commandLoop` (2 sites,
already had `heap` in scope from increment 2) and `parser_tests.zig`'s
`/editor` command test (2 sites, passing `heap.heap` since that test has no
existing `*Heap` in scope).

**Second sed-adjacent gotcha, distinct from `dump.zig`'s:** this time the
bulk `heap.heap.` → `heap.` / `heap.` → `heap_mod.` rewrite was run *after*
a manual edit had already converted `getTag`'s body to `heap.getTag(x)`
(using the new parameter). The bulk sed doesn't know `heap` is now a local
parameter shadowing the module import — it just sees the literal text
`heap.getTag` and rewrites it to `heap_mod.getTag`, silently clobbering the
manual edit back to the ambient form. Caught by the compiler (`unused
function parameter`), not by inspection. **Lesson for remaining
increments:** run the mechanical bulk rewrite *first*, across the whole
file, before doing any by-hand `heap: *Heap` parameter threading — don't
interleave the two, since the bulk pass can't distinguish "text that
happens to say heap." from "a parameter named heap already in scope."
Also re-confirmed the `dump.zig` gotcha applies again here: a bare
`heap.heap` (the ambient singleton passed as a plain argument, not
`heap.heap.field`) isn't caught by the `heap.heap.` → placeholder trick
either, since there's no trailing dot — it needs the same by-hand fixup
as the import-string collision.

*DoD met: `zig build` clean; 176/176 unit tests (main-tests run directly);
`zig build test` green — 48/48 golden, spine-corpus stress, sigint, smoke;
lint at 16 warnings, no new ones; manual smoke test of `/files`, `/find fib`,
and bare `?` (`allnamescom`) all producing correct output (file listing,
type + definition location, full name listing split into stdenv/script
sections).*

**Tier 3, increment 5 — `startup.zig` ✅ done (2026-07-05).** Same pattern:
most of the ~31 touches are ambient free-function calls (`utf8test`/
`filDefs`/`alfasort`/`t`/`h`/`cons`/`tp`/`hp`/`getId`/`theVal`), left
unconverted. Threaded `heap: *Heap` through the local `getTag` helper and
the 4 functions touching `heap.heap.files` directly: `mainEntry`,
`runExportsMode`, `runSourcesMode`, `runMakeMode`. `mainEntry` is the
process's real root (`main.zig` calls it exactly once) so it keeps its old
signature and grabs the ambient singleton once internally
(`const heap = heap_mod.heap;`), exactly mirroring `reduce()`/`miraSetup()` —
no external caller needed updating. The three `run*Mode` functions are
private helpers called only from within `mainEntry`, so they got an
explicit `heap: *Heap` parameter threaded from that one grab point.

*DoD met: `zig build` clean; 176/176 unit tests (main-tests run directly);
`zig build test` green — 48/48 golden, spine-corpus stress, smoke (one
`sigint_check` `SIGABRT` seen on the full-suite run was the same pre-existing
timing flake documented in earlier increments, confirmed by 3 clean reruns
of `zig build test-sigint` in isolation); lint at 16 warnings, no new ones;
manual smoke test of `fib 27`/`show 42` correct.*

**Tier 3, increment 6 — `module_loader.zig` ✅ done (2026-07-05).** The
widest cascade yet: `loadfile` (the pub entry point most of this file exists
to support) has **12 external call sites** across `repl.zig` (2),
`commands.zig` (3 — 2 in `cmdFiles`, 1 in `editfile`), `dump.zig` (4, inside
`undump`), and `parser_tests.zig` (3, test code). Every site already had
`heap`/`heap.heap` reachable locally (either an existing `heap: *Heap`
parameter from an earlier increment, or the ambient module import), so this
was mechanical one-line fixes throughout — no further cascading needed.
Threaded `heap: *Heap` through: the local `getTag` helper, `loadfile`,
`resolveExportFileList`, `computeBereavedNames`, `reportUnusedDefinitions`
(uses `getTag` 4x), and `mkincludes` (the other `pub` entry point, no
external callers besides `loadfile` itself — uses `getTag` 4x, plus
`heap.heap.files`/`stackp`/`dstack`). `resolveExports` and
`reportBereavedExports` needed no change (ambient-only). Followed the
"bulk sed first, manual threading second" lesson from `commands.zig`
throughout — no clobbering this time.

*DoD met: `zig build` clean; 176/176 unit tests (main-tests run directly);
`zig build test` green — 48/48 golden, spine-corpus stress, sigint, smoke
all passed cleanly (no flake this run); lint at 16 warnings, no new ones;
manual smoke test of `fib 27` and `/files` (which drives `loadfile`'s
file-listing path) both correct.*

**Tier 3, increment 7 — `lex.zig` ✅ done (2026-07-05), the deepest cascade in
Tier 3.** Investigation before starting revealed this file breaks the pattern
of every prior increment: its `heap.heap.X` touches route through 5 local
wrapper functions (`h`/`hp`/`t`/`tp`/`getTag`) and `getch()` — the innermost
character-reading primitive, called from ~70 internal sites across nearly
every lexer state-machine function. Explicitly confirmed via user decision
("do the full cascade anyway") before proceeding, given this was qualitatively
riskier than repl.zig/dump.zig/commands.zig/module_loader.zig/startup.zig
(all shallow 1-2 level chains; this one required threading through deeply
nested call graphs with no existing scaffolding, exactly the "entangled
subsystem" case the plan document originally flagged this file as).

A transitive-closure script found **44 of the file's 80 functions**
transitively touch the struct (not the ~134 raw grep-hit estimate — that
number undercounts, since most of the 44 functions call `h`/`t`/etc.
multiple times each). Threaded `heap: *Heap` through all 44, in dependency
order (leaves first: `h`/`hp`/`t`/`tp`/`getTag`/`getch`, up through
`getlitch`/`identifier`/`directive`/`numeral`/`hexnumeral`/`octnumeral`/
`string`/`charclass`/`findid`/`name`/`yylex`/`layout`/`resetLex`/
`resetState`/etc.). External cascade touched **10 other files**:
`lex_bridge.zig`, `parser_api.zig`, `parser_tests.zig`, `repl.zig`,
`commands.zig`, `startup.zig`, `setup.zig`, `trans.zig`, `types.zig`,
`codegen.zig`, `lineedit.zig`, and `heap.zig` itself (which calls back into
`lex.zig`'s `name()` — a real circular dependency between the two modules).
Every call site outside `lex.zig`/`repl.zig`/`commands.zig`/`startup.zig`
(which already had `heap: *Heap` params from earlier increments) fetches the
ambient singleton at the call site (`heap.heap`/`heap_mod.heap`), since none
of those files have been converted yet themselves.

**Two new mechanical-editing gotchas found and fixed, worth recording for
`trans.zig`/`types.zig`:**
1. **The transitive-closure discovery script only matched lines starting
   with `(pub )?fn NAME(`, silently missing `inline fn NAME(` declarations.**
   This missed `tryCh` (an inline lookahead helper called from
   `lexSymbolOrOperator`), causing a "use of undeclared identifier 'heap'"
   compile error inside it. Also caused 3 functions (`getStderr`, `cleanup`,
   `errclass`) to be **incorrectly flagged** as needing `heap` — their own
   bodies don't touch the struct at all; they were pulled into the closure by
   a same-named-caller confusion in the script's regex matching. Caught by
   the compiler's "unused function parameter" error in each case; fixed by
   reverting their signatures and call sites back to heap-free.
2. **BSD `sed`'s global substitution doesn't overlap adjacent matches**, so a
   pattern like `s/([^a-zA-Z0-9_.])h\(/\1h(heap, /g` applied to a deeply
   nested call like `h(h(h(x)))` only converts every *other* occurrence
   (the regex engine consumes the matched prefix character, so the next `h(`
   immediately after can't be matched against — its own "preceding
   character" was already consumed by the prior match). This produced
   `h(heap, h(h(heap, x)))` instead of the correct
   `h(heap, h(heap, h(heap, x)))` in several spots (`getId`, `charclass`,
   the `setupFile`/`lexEndOfFile`/`resetLex` family's shared
   `h(h(ls.fileq))` idiom). All caught by the compiler's "expected 2
   argument(s), found 1" errors and fixed by hand — not a silent
   correctness bug, but worth checking for directly (search for the
   pattern `heap, h(h(` / `heap, t(t(` etc.) rather than trusting the sed's
   exit code on any file with deeply nested short-name wrapper calls.

*DoD met: `zig build` clean; 176/176 unit tests (main-tests run directly);
`zig build test` green — 48/48 golden (including `hex_oct_literals`),
spine-corpus stress, sigint, smoke; lint at 16 warnings, no new ones;
thorough manual smoke test given the lexer's central role: `fib 27`, hex
(`0x1F`) and octal (`0o17`) numerals, string and char literals, list
literals, `/files`, `?fib` (type + location lookup), bare `?`
(`allnamescom`), and undefined-name diagnosis all correct.*

**Tier 3, increment 8 — `trans.zig` ✅ done (2026-07-05), the widest single-file
conversion in Tier 3.** Investigation (requested by the user before starting,
given lex.zig showed touch-count alone underestimates true scope) found this
file breaks the pattern of every increment except `lex.zig`: its local
`h`/`hp`/`t`/`tp`/`getTag` wrappers plus `codegen`/`validate`'s direct struct
touches transitively reach **86 of the file's 100 functions** — essentially
the entire file, not a contained subset. Confirmed via explicit user decision
("do the full cascade anyway") before proceeding, since several of those 86
functions (`genlhs`, `irrefutable`, `compzf`, `block`, `declare`, `specify`,
`declType`, `declconstr`, `getspecloc`, `mktuple`, `tclos`, `sortrel`,
`genshfns`, `same`, `lastlink`) are directly aliased and called from
`types.zig` and `parser/codegen.zig`, meaning this increment forced real
(if shallow — ambient-singleton-fetch-at-call-site) threading work into both
of those files too, not just call-site patches.

Threaded bottom-up: `h`/`hp`/`t`/`tp`/`getTag` first, then the ~25 small
per-field accessors (`getId`/`idWho`/`idType`/`idVal`/`typeArity`/`typeClass`/
`typeInfo`/`dlhs`/`dval`/etc.), then the ~55 larger `pub` functions
(`abstract`/`abstr`/`combine`/`scanpattern`/`transtries`/`genlhs`/`declare`/
`declType`/`specify`/`block`/`sort`/`sortrel`/`codegen`/etc.), finishing with
`genshfns`/`validate`. External cascade touched **8 other files**:
`module_loader.zig`, `types.zig`, `repl.zig`, `main.zig`, `parser/codegen.zig`,
`runtime/reduce.zig` (the reducer's own `parseLine` caller — confirmed it
already had `ctx.heap` from Tier 1.5, so this was a one-line fix), and
`runtime/reducer/reduce_test.zig`.

**The `lex.zig` nested-call sed under-conversion bug (BSD sed's
non-overlapping-match semantics missing every other occurrence in calls like
`h(h(h(x)))`) recurred extensively here — worse than in `lex.zig`, since this
file's small field-accessor functions are almost entirely built from 2-4-level
nested `h`/`t` chains** (`getId`'s `h(h(h(x)))`, `typeArity`'s `h(h(t(x)))`,
`typeShowFn`'s `t(h(t(x)))`, `typeInfo`'s `t(t(t(x)))`, `tShowfn`/`tClass`/
`tInfo`'s similar triple chains, several `COND`-abstraction recognizers in
`abstr`/`combine` built from `getTag(t(h(x)))`-style lookaheads, `less1`'s
inner comparison, `nclchk`'s hold/rhs traversal, `transzf`'s self-recursive
call). None were caught by review — **all ~15 were caught by the Zig
compiler's "expected N argument(s), found N-1" error**, one rebuild-fix cycle
at a time, which is the reliable way to catch this class of bug on files this
nesting-heavy: don't trust the sed's exit code, rebuild and let the compiler
enumerate every remaining occurrence.

**A new, distinct gap found in the transitive-closure discovery script:**
it missed `less1` and `decl1` — both are functions whose calls to already-
converted functions (`h`/`t`/`idVal`) should have added them to the closure,
but weren't detected in the first pass for reasons not fully root-caused
(possibly a script bug in the iteration, not a structural blind spot like
`inline fn` was for `lex.zig`). Lesson holds regardless: **the compiler is the
authoritative check, not the discovery script** — run `zig build` after the
mechanical rewrite and trust its "undeclared identifier" / "expected N
arguments" errors to find every function the script's heuristics missed.

*DoD met: `zig build` clean; 176/176 unit tests (main-tests run directly);
`zig build test` green — 48/48 golden (including `hex_oct_literals`),
spine-corpus stress, sigint, smoke; lint at 16 warnings, no new ones;
thorough manual smoke test covering the core compiler pipeline this touched:
`fib 27`, a user-defined algebraic type with pattern matching over its
constructors (`tree ::= Leaf | Node tree num tree`; `depth Leaf = 0; depth
(Node l n r) = 1 + max2 (depth l) (depth r)`), a `where`-clause binding, a
list-pattern recursive function (`g (x:xs) = x + g xs`), and a list
comprehension (`[x*x | x <- [1..5]]`) — all correct via a script file (the
REPL's "syntax error" response to typing multi-clause/`where` definitions
directly at the interactive prompt is pre-existing, unrelated behavior, not
a regression — confirmed by loading the same definitions from a `.m` file).*

**Tier 3, increment 9 — `types.zig` ✅ done (2026-07-05), the final Tier 3
file and the widest single-file conversion of the whole effort.** Its local
`h`/`hp`/`t`/`tp`/`getTag` wrappers plus direct struct touches transitively
reached **99 of the file's 108 functions**, edging out `trans.zig`'s 86/100.
Threaded bottom-up: leaves first, then the ~30 small field accessors
(`idType`/`idVal`/`idWho`/`tArity`/`tClass`/`tInfo`/`dlhs`/`dval`/etc.), then
the larger `pub` functions (`unify`/`etype`/`conforms`/`checktype`/
`checktypes`/`subsumes`/`redtvars`/`outType`/etc.).

Several functions were missed by the transitive-closure script and only
caught by compiler errors after the mechanical rewrite: `remove1`, `add1`,
`newadd1`, `typeError1`–`typeError7`, `outType1`, `outType2`, `outFormal1`,
`repT1`, `subsu1`, `unify1` all needed `heap` added by hand. `cons` was
initially (incorrectly) added to the 99-set by the closure script's
propagation logic — reverted once the compiler flagged its `heap` parameter
as unused (it only calls the ambient `make`, never touches the struct).
`walktype`'s callback parameter type also had to change from
`*const fn (Word) Word` to `*const fn (*Heap, Word) Word` since all four of
its callbacks (`ult`/`lmap`/`mapup`/`mapdown`) gained a `heap` parameter.

**The external cascade was the widest yet**, because several of
`types.zig`'s functions (`add1`, `member`, `UNION`, `intersection`,
`setdiff`, `sayhere`, `printlist`, `reportType`, `typeOf`, `typesfirst`,
`redtvars`, `outType`, `subsumes`, `instantiate`, `deps`) are ambient
general-purpose utilities called pervasively from other files. Fixing their
call sites touched **9 other files**: `trans.zig`, `module_loader.zig`,
`dump.zig`, `commands.zig`, `repl.zig`, `startup.zig`, `parser/codegen.zig`,
`heap.zig` (which calls `member`/`add1` on its own bare singleton), and
`runtime/reducer/lex.zig` (via `ctx.heap`).

**A real regression was found and fixed during verification — the most
important finding of this entire Tier 3 effort.** `inferType` (the function
that type-checks self-referential/recursive definitions) had a line where
`idType(h(x1))` (one level of `h`) was over-converted to
`idType(heap, h(heap, h(heap, x1)))` (two levels) during an earlier batch
fix for the nested-call under-conversion bug. This compiled cleanly, passed
`zig build`, all 176 unit tests, all 48/48 golden cases, the spine-corpus
stress suite, the sigint check, and the smoke tests — **and was caught by
none of them**. It was only caught by `zig build test-mira`'s integration
suite, whose `"example script fib"` case failed with `cannot apply char to
num` — because `miralib/ex/fib.m` is self-recursive and the golden/spine
corpus's own `custom_fib`/`fib.m` cases happened to hit a **stale
`script.x`/`.x` dump-cache file** that silently masked the bug by skipping
recompilation. Root-caused via a minimal repro
(`countdown 0 = 0; countdown n = countdown (n-1)`, confirmed correct against
the pre-`types.zig` commit via `git stash`) and fixed by removing the extra
`h()` wrap.

**This is the critical lesson for any future nested-call mechanical rewrite
of this kind:** the sed under-conversion bug (documented in the `lex.zig`
and `trans.zig` sections above) can go in *either* direction — under- or
over-conversion — and only under-conversion (wrong argument count) is
reliably caught by the compiler. Over-conversion (extra, syntactically-valid
levels of `h`/`t`/etc.) type-checks fine and silently produces wrong
*runtime* behavior; catching it requires either exercising the actual code
path with a real test, or better, an automated structural check. Developed
and validated one here: **for each function, count `h(`/`t(`/`hp(`/`tp(`/
`getTag(` call occurrences in the pre-edit backup vs. the post-edit file —
the counts must match exactly per function.** Running this check against
`types.zig`, `trans.zig`, and `lex.zig` after the `inferType` fix confirmed
**zero remaining mismatches across all three files** — recommended as a
standard verification step for any future increment of this kind, run
*before* relying on the test suite alone.

*DoD met: `zig build` clean; 176/176 unit tests (main-tests run directly);
`zig build test` green — 48/48 golden (including `hex_oct_literals`),
spine-corpus stress, sigint, smoke; **`zig build test-mira` green (1/1,
including the `"example script fib"` integration case that caught the
regression)**; lint at 16 warnings, no new ones; thorough manual smoke test
(with `script.x` deliberately removed each time to force a fresh compile,
not a stale dump-cache hit): `fib 27` via `script.m` (196418), the
`countdown` self-recursion repro (0), a user-defined algebraic type with
constructor pattern matching (`tree ::= Leaf | Node tree num tree`; `depth`
returns 1 for a single-node tree), a list comprehension (`[1,4,9,16,25]`),
`/files`, and `?name` lookup — all correct.*

---

## Tier 3 complete (2026-07-05)

All 9 increments of the revised Phase 5 / Tier 3 effort are done, verified,
committed, and pushed: `setup.zig`, `repl.zig`, `dump.zig`, `commands.zig`,
`startup.zig`, `module_loader.zig`, `lex.zig`, `trans.zig`, `types.zig`.
Every function that transitively touches the `Heap` struct (fields or
methods) in the compiler/parser/driver stack now takes an explicit
`heap: *Heap` parameter instead of reaching into the `heap.heap` ambient
singleton; the ~74 free functions living outside the `Heap` struct in
`heap.zig` itself remain ambient by design (a `heap.zig`-wide change, out of
scope for this effort — documented as its own boundary in the increment 1
note above).

Recurring lessons worth carrying into any future mechanical rewrite of this
shape: (1) run the bulk textual rewrite across a whole file *before* any
by-hand parameter threading, never interleaved; (2) BSD `sed`'s non-
overlapping-match semantics silently mis-convert deeply nested same-name
calls in *either* direction — verify with the per-function call-count
technique above, not just a successful build; (3) a transitive-closure
discovery script based on regex will miss `inline fn` declarations and the
occasional function whose only heap-need is calling something else in the
closure (`less1`, `decl1`, `remove1`, etc.) — the compiler's "undeclared
identifier" and "unused parameter" errors are the authoritative backstop,
not the discovery script; (4) some functions get pulled into the closure
incorrectly by the script's propagation logic even though they never touch
heap themselves (`getStderr`, `cleanup`, `errclass`, `cons`) — the compiler's
"unused function parameter" error catches these too, and they should be
reverted rather than padded with a discard.
* **Irreducible exception (unchanged):** OS signal handlers run on the C ABI and
  cannot take any explicit parameter; they read a single `current_interp: *Interp`
  set on entry — the one documented global, analogous to `errno` and the A4
  signal trampoline.
* *DoD per subsystem: no ambient-global-singleton access outside the subsystem's
  own threaded struct(s) (or an explicitly documented exception); golden green.*

### Phase 5, Tier 4 — the other four structs (`rs`/`ls`/`cs`/`core`/`eval`)
*(in progress, 2026-07-05 — explicit user decision to pursue the full Phase 6
effort despite both plan docs framing it as optional/deferred)*

Tier 3 threaded `*Heap` only. Deleting the global (Phase 6) requires *every*
aggregated struct in `Interp` to stop being reached ambiently, not just
`heap`. A fresh survey (grepping each owner-module accessor across `src/`)
found the remaining scope is **larger than all of Tier 3 combined**:

| Struct | Accessor | Ambient touches | Files |
|--------|----------|-----------------:|------:|
| `RuntimeState` | `rt.rs.*` | 814 | 19 |
| `LexState` | `ls.*` | 979 | 14 |
| `CompilerState` | `cs.*` | 516 | 12 |
| `CoreState` | `core_state.s.*` | 143 | 14 |
| `EvalState` | `reduce.ev.*` | 45 | few |
| **Total** | | **~2,500** | (overlapping — fewer distinct files) |

(`big`/`strtab` — Tier 1, done. `heap` — Tier 3, done. `rt.allocator`/`rt.gpa`/
`rt.io`/`rt.environ` are the confirmed-permanent bootstrap exception per
`interp.zig`'s own doc comment — process-wide by nature, not aggregated
per-request state, out of scope forever.)

**Sequencing:** smallest first, same discipline as Tier 3 (bulk textual
rewrite of a whole file before any by-hand parameter threading, verify with
`zig build`, run the **per-function `h`/`t`/`hp`/`tp`/`getTag`-style
call-count check is N/A here** since these structs aren't reached through
nested nested-wrapper calls the way `Heap` cells are — the risk profile is
different (see below) — full test suite including `zig build test-mira`,
manual smoke test, commit, push, update this doc. Order: `EvalState` (45,
smallest) → `CoreState` (143) → `CompilerState` (516) → `RuntimeState` (814)
→ `LexState` (979, largest).

**Different risk profile than Tier 3.** Tier 3's bug (the `inferType`
over-conversion) came from mis-nesting `h(t(x))`-style Heap-cell accessor
chains during mechanical rewrites — these four structs are accessed as flat
field reads (`rt.rs.exports`, `cs.CLASHES`, `ls.dicp`), not nested nested
calls, so that specific class of bug doesn't apply here. The real risk this
tier: many of these fields are read *and written* from deep inside
long-lived call chains (parser state, compiler diagnostics, REPL prompt
state) with no natural "the caller already has this" shortcut the way
`ctx.heap` did for the reducer — expect several already-encountered patterns
to recur (functions needing a new struct parameter threaded through many
existing callers; `abi.*`-aliased functions in `main_clib.zig` needing their
call sites tracked down; test files needing the ambient singleton fetched
explicitly).

**`EvalState` (45 touches) — done, 2026-07-05.** Added `eval: *EvalState` to
`ReductionCtx` (mirroring `heap`'s Tier 1.5 field) and threaded it through
`reduce.zig`'s I/O-directive family (`output`/`print`/`outf`/`apfile`/
`closefile`), `streamRead`/`stdinError`, and the two `combinators.zig` handlers
that touched `ev` directly (`handleERROR`, `handleWAIT`). External callers
that don't have a narrower value in scope (`repl.zig`'s `obey`/`evaluateRepl`)
pass the ambient `reduce.ev` global directly at the call site, the same
pattern already used for `heap.heap` in `parser_api.zig` — Tier 3/4 threading
makes functions stop reading ambient state *internally*, it doesn't require
erasing every ambient read at every call site (that's Phase 6's job once the
global itself goes away). Three call sites were confirmed as legitimate
permanent exceptions and left untouched: `outstats()` (reads `ev.cycles`
ambiently — reachable from the `dieClean` signal handler, same class as
Tier 3's `setup.zig` exceptions), `heap.zig`'s `bases()` GC-root scanner
(reads `reduce.ev.outfilq`/`waiting` plus every other still-ambient struct —
it's the conservative-stack-scan root function, fired from arbitrary
allocation sites with no natural caller to thread through), and
`reduce_test.zig`'s `interp.reset()` test (deliberately asserts on the
ambient singleton). Verified: `zig build` clean, `zig build lint` (16-warning
baseline, no new), direct `main-tests` binary run (176/176), `zig build
test-mira` (0 exit), `zig build test-golden` (43/44 — the one failure,
`script_syntax_err`, reproduces identically on the pre-Tier-4 commit via
`git stash`, so it's a pre-existing unrelated bug, not a regression; flagged
separately). Manual smoke test of the `Tofile`/`Stdout`/`Closefile` redirect
dance and the `readvals` stdin path (via golden's `lazy_io_readvals`) behaved
identically before and after.

**`CoreState` (143 touches, 14 files) — done, 2026-07-05.** Threaded
`core: *CoreState` through the tractable, low-fan-out call chains: `outHere`,
`unlinkObject`, the `loadfile`/`undump`/`makedump`/`mkincludes`/
`resolveExportFileList`/`resolveExports`/`computeBereavedNames`/
`reportBereavedExports`/`reportUnusedDefinitions` cluster (module_loader.zig
+ dump.zig), `checkfbs`/`checktypes` (types.zig), `cmdFiles`/`cmdEdit`/
`command` (commands.zig), and `commandLoop`/`obey`/`evaluateRepl`/`parseLine`
(repl.zig). External callers with no narrower value in scope pass the
ambient `core_state.s` global directly, same as `EvalState`'s pattern.

The bigger finding this tier: most of `CoreState`'s remaining touches turned
out to belong to a *pervasive ambient cluster* that doesn't get threaded at
all, extending Tier 3's `setup.zig` exception into a real category rather
than a one-off. Left untouched, by function:
- **Signal handlers** (must stay zero-arg): `repl.zig`'s `fpeError` (SIGFPE)
  and `reset` (SIGINT), both `callconv(.c)`.
- **The `syntax`/`acterror` error-reporting cluster**: `setup.zig`'s
  `syntax`/`acterror` (40+ call sites across `lex.zig`/`trans.zig` — Tier 3
  precedent), plus everything that sets `core.errs`/`core.SYNERR` immediately
  before calling into that cluster (`trans.zig`'s `nclchk`/`declconstr`/
  `specify`/`arityCheck`/`declType`/`decl1`/`declare`/`respecError`/
  `nameclash`) — these are mutually recursive with the already-ambient
  reporters, so threading `core` through them would just plumb a param to
  a function that reads the global anyway three lines later.
- **The lexer/parser/codegen hot path**: `lex.zig`'s `getch`/`errclass`/
  `yylex`/`lexSymbolOrOperator`/`identifier`/`resetLex`/`resetState`,
  `trans.zig`'s `codegen` (34 call sites) and `genlhs`, `types.zig`'s
  `sayhere` (20+ call sites)/`typeError2`/`outFormal1`/`etypeId` (embedded in
  the 27-call-site `etype` dispatcher) — called thousands of times per
  script; threading here would cascade into the entire parse/typecheck/
  codegen pipeline for fields (`commandmode`/`compiling`/`SYNERR`/`errs`)
  that are genuinely global compilation-session status, not per-request
  state a caller would ever plausibly vary.
- **`codegen.zig`**: already fully ambient in Tier 3 (no `heap`/`core` params
  anywhere in this file), so its `core_state.s.nill` reads stay consistent
  with that.
- **Test files** (`reduce_test.zig`, `parser_tests.zig`): assert on the
  ambient singleton directly, same as `EvalState`'s test.

Verified the same way as `EvalState`: `zig build` clean, `lint` at the
16-warning baseline, direct `main-tests` binary 176/176, `test-mira` exit 0,
`test-golden` 43/44 (same pre-existing `script_syntax_err` failure), and a
byte-identical manual REPL smoke test (`1+2` / syntax-error recovery / `/f`)
diffed against the pre-CoreState commit via `git stash`.

**`CompilerState` (~419 touches, 10 files) — done, 2026-07-05.** Same shape as
`CoreState`: threaded `comp: *CompilerState` through the already-`core`-
threaded cluster (`loadfile`/`resolveExports`/`computeBereavedNames`/
`reportBereavedExports`/`mkincludes` in module_loader.zig; `undump`/
`makedump`/`readoption` in dump.zig; `checkfbs`/`checktypes` in types.zig;
`cmdFiles`/`command`/`allnamescom` in commands.zig; `commandLoop`/`obey`/
`evaluateRepl` in repl.zig) plus a new cluster discovered this tier in
`heap.zig`'s binary dump/undump serializer: `dumpScript`/`loadScript`/
`bindparams`/`unscramble`/`loadDefs`/`unload`/`okdump`/`geterrlin` — all
tractable because their callers are the same already-threaded functions
above. External callers with no narrower value pass the ambient `cs`
singleton directly (`cs` was already every file's local alias for
`compiler_state.cs`, same role `core_state.s` played for `CoreState`).

Confirms the CoreState-tier finding rather than complicating it: the
remaining ~236 touches (`types.zig` 202, `trans.zig` 34) are the
type-checker's own working state (`NEW`/`SUBST`/`tvcount`/`ATNAMES`/etc.) —
not occasional reads but the substitution/unification machinery's core
mutable state, read and written from inside the `etype`/`etypeAtom`/
`metaTcheck`/`compDeps`/`abstrCheck`/`mcheckfbs`/`inferType` family, which is
one giant mutually-recursive component (`etype` alone has 27 call sites,
`etypeAtom` 30 internal touches). This is the same ambient-exception shape
as Tier 3's `bases()`/`gc()` for the heap: a core recursive algorithm's
state, not per-request data a caller would parameterize. Left ambient,
unchanged.

Also found (and fixed in-place, not a regression — heap.zig aliases the
`core_state` import as `core` rather than `core_state`, so the Tier-4-
increment-two grep for `core_state\.s\.` silently missed it): `okdump`/
`geterrlin`/`dumpScript`/`loadScript` also touch `core.s.*` directly, now
threaded alongside their new `comp` params in the same pass. `bases()`/
`gc()`/`makeSlow()`'s own `core.s.*` reads stay ambient, matching Tier 3/4's
GC-root/hot-allocator precedent.

Verified identically to the prior two increments: `zig build` clean, `lint`
at the 16-warning baseline, direct `main-tests` binary 176/176, `test-mira`
exit 0, `test-golden` 43/44 (same pre-existing failure), and a byte-identical
manual REPL smoke test (arithmetic / syntax-error recovery / `%include` of a
missing file / `/f`) diffed against the pre-CompilerState commit via
`git stash`.

**`RuntimeState` (~700 touches, 19 files) — done, 2026-07-05.** The biggest
tractable-vs-ambient split of the four increments so far — `rt.rs` is used
far more broadly than `core`/`comp` (identity atoms, file paths, CLI-derived
config, GC roots), so the tractable cluster came out much larger, not
smaller. Threaded `rs: *RuntimeState` through:
- The full `module_loader.zig` cluster (**all 7 functions**, not a subset —
  every one of `loadfile`/`resolveExportFileList`/`resolveExports`/
  `computeBereavedNames`/`reportBereavedExports`/`reportUnusedDefinitions`/
  `mkincludes` touches `rt.rs` somewhere, unlike the Core/CompilerState
  passes which skipped a couple of these).
- `dump.zig`: `undump`/`makedump`/`readoption`/`fixexports`/`unfixexports`.
- `heap.zig`'s binary-dump cluster: `dumpScript`/`loadScript`/`loadDefs`/
  `unload`, plus `srcUpdate` (a new tractable single-hop found this tier —
  all 5 callers already had `rs` in scope from the driver-level threading
  below).
- The full driver layer: `commands.zig`'s entire non-hot-path surface
  (`filequote`/`namescom`/`cmdFiles`/`cmdEdit`/`command`/`manaction`/
  `editfile`/`finger`/`allnamescom`) and `repl.zig`'s `commandLoop`/`obey`/
  `evaluateRepl`/`parseLine`/`edWarn`/`badEditor` — i.e. essentially every
  function in both files except the two signal handlers.
- `types.zig`'s `checktypes` (extending the Tier-4-increment-two `comp`
  threading with one more param).
- **New for this tier:** `ReductionCtx` gained an `rs: *RuntimeState` field
  (mirroring `heap`/`eval`), which made `reducer/ready.zig`'s three
  `ctx`-having handlers (`handleReadyState`/`handleReadyGETENV`/
  `handleReadyNUMVAL`, 15 touches total) and `reduce.zig`'s `streamRead`/
  `print`/`output` tractable at **zero new parameters** — same "the ctx is
  already everywhere" leverage that made Tier 1.5's `heap` field free.

Confirms the pattern from the prior two increments for the remainder:
`startup.zig` (189, almost entirely `mainEntry`/`parseFlags`/the
`run*Mode` bootstrap functions — none of which have ever threaded any
struct, matching `miraSetup`'s own precedent), `lex.zig` (62, the tokenizer
hot path), `heap.zig`'s remaining 50 (`bases`/`gc`/`makeSlow`/`growHeap`/
`setupheap`/`resetheap`/`BIGTOP` — the GC/allocator internals, plus test
blocks), `trans.zig` (29, the `declare`/`specify`/`codegen` cluster —
mutually recursive with the already-ambient `syntax`/`acterror`), `setup.zig`
(27, `miraSetup` itself), `types.zig`'s remaining 9 and `codegen.zig`'s 8
(the `etype`/`sayhere`/`outType` family and `codegen.zig`'s already-fully-
ambient convention), `parser_api.zig`'s 8 (`parseCurrentNew`, the parser's
own hot entry point), and `main.zig`/`micro_benchmarks.zig` (the true
process entry points, which have never threaded anything). All left
unchanged, same reasoning as before: pervasive fan-out into a core
recursive/hot-path component, not per-request data.

One near-miss caught before it shipped: `parser_tests.zig:432`'s
`commands.editfile("test.m", 42, 17)` compiles fine under plain `zig build`
(test files aren't part of the default install graph) but only surfaces
under `zig build test` — a reminder that this increment's tractable-vs-
ambient sweep needs the test build to be authoritative, not just the
install build.

Verified identically to the prior three increments: `zig build` clean,
`lint` at the 16-warning baseline, `zig build test` (which caught and fixed
the `parser_tests.zig` miss above) with direct `main-tests` binary 176/176,
`test-mira` exit 0, `test-golden` 43/44 (same pre-existing `script_syntax_err`
failure), and a byte-identical manual REPL smoke test diffed against the
pre-RuntimeState commit via `git stash`.

**`LexState` (~660 touches, 14 files) — done, 2026-07-05. Tier 4 complete.**
The last and largest struct by the original estimate, but the smallest
actual increment of the four: `lex.zig` itself (the tokenizer) owns 599 of
the ~660 touches and is the hot path already established ambient for every
other struct, so almost the whole struct's nominal size was already
"priced in." The tractable remainder was exactly the same already-threaded
cluster as the other three increments, extended by one more parameter:
- `module_loader.zig`: `loadfile`/`resolveExportFileList`/`mkincludes`.
- `dump.zig`: `fixexports`/`unfixexports`/`privatise`/`publicise` (a new
  small cluster this tier — `privatise`/`publicise` are `fixexports`/
  `unfixexports`'s only callees, so threading cascaded one hop deeper than
  in prior increments).
- `heap.zig`'s binary-dump cluster, now including `geterrlin` (missed as
  tractable in the RuntimeState pass since its `LexState` touches weren't
  scanned for until this tier).
- `commands.zig`'s `is`/`cmdFiles`/`cmdEdit`/`command` and `repl.zig`'s
  `commandLoop`/`parseLine` — the last driver-layer functions with any
  remaining ambient struct touches at all.

One naming wrinkle distinct from the other three structs: `core`/`comp`/`rs`
never collided with anything because they shadow the *module* names
(`core_state`/`compiler_state`/`rt`), not the singleton accessors (`.s`/
`cs`/`rt.rs`). `ls`, however, *is* the singleton accessor's own name in
every file (`const ls = lex_state.ls;`), so a parameter named `ls` is a
compile error ("function parameter shadows declaration of 'ls'"). Every new
`*LexState` parameter this tier is named `lexs` instead, with call sites
falling back to the ambient `ls` global exactly where `EvalState`/
`CoreState`/etc. fell back to their own ambient globals — the pattern is
identical, only the local name differs.

Confirms the same shape as the other three for the remainder: `startup.zig`
(bootstrap, never threaded), `heap.zig`'s `bases()` (GC-root scan, already
ambient), `files.zig`'s `makeAbsolute` (1 caller, `mainEntry`, bootstrap),
`lex_bridge.zig`'s `mapToken` (the new-pipeline per-token hot path, mirrors
`lex.zig`'s own), `trans.zig`/`codegen.zig` (the `declare`/`codegen`/`genlhs`
cluster, already ambient), and `setup.zig` (`miraSetup`). All left
unchanged.

Verified identically to the prior increments: `zig build` clean, `lint` at
the 16-warning baseline, `zig build test` with direct `main-tests` binary
176/176, `test-mira` exit 0, `test-golden` 43/44 (same pre-existing
`script_syntax_err` failure), and a byte-identical manual REPL smoke test
diffed against the pre-LexState commit via `git stash`.

**Tier 4 is now complete: all five aggregated structs (`EvalState`/
`CoreState`/`CompilerState`/`RuntimeState`/`LexState`) have their tractable
call chains threaded as narrow, separate params, matching Tier 3's `heap`
precedent. Phase 6 (below) is now reachable.**

### Phase 6 — De-globalize & document *(mostly done, 2026-07-05)*

Per explicit user decision, pursued as the full sweep toward the DoD's literal
"= 1" rather than just the narrow "delete `var interp`" reading — both
turned out achievable with mechanical (if large) rewrites:

1. **The full-sweep pass (45 → 17 globals).** `combinator.zig`/`setup.zig`/
   `version.zig` constants that were never reassigned became `const`;
   `dump.zig`'s export-privatisation scratch and `types.zig`'s `NGT`/
   `allchars` folded into `CompilerState`; `commands.zig`/`repl.zig`'s
   display/timing scratch and `startup.zig`'s version-mismatch buffers folded
   into `RuntimeState`; `reducer/trace.zig`'s histogram and
   `reducer/spine.zig`'s GC-root-tracking state (the highest-risk single
   change — verified with the spine differential stress suite plus a
   dedicated GC-heavy diff) folded into `EvalState`.
2. **The core accessor rewrite (~2,100 call sites).** All 8 owner singletons
   (`heap.heap`, `core_state.s`, `compiler_state.cs`, `lex_state.ls`,
   `runtime_state.rs`, `reduce.ev`, `big.bn`, `strtab.table`) plus
   `word.fio` changed from `pub const X = &interp.Y` (a fixed address) to
   `pub inline fn X() *T { return &current_interp.Y; }` (read through a
   pointer), and every call site rewrote `owner.singleton.field` to
   `owner.singleton().field` — done via an automated build-error-driven
   fixer after a safe bulk-regex pass for fully-qualified patterns.
3. **`main()` constructs the `Interp` explicitly**, pointing `current_interp`
   at a local that lives for the process's whole run — the literal ask in
   this section's original prose.
4. **Test-harness exemption documented** (see Scorecard) rather than forcing
   `testutil.zig`'s `ready`-style guards into `Interp`.

**Remaining:** `driver/lineedit.zig` + `word.zig`'s `readInteractiveLine`
hook (10 + 1 globals) — per explicit user decision, being threaded through
rather than left as a documented exception; this is real, separate work
(threading line-editor state through `word.zig`'s stdio read path) tracked
as its own increment, not yet started as of this write-up.

* *DoD: non-FFI module-scope mutable globals = **1** (documented); a second
  `Interp` can be constructed and run independently; golden green.* Currently
  at 17 (target 1) with the `lineedit.zig` cluster as the only remaining gap
  — `runtime_state.zig`'s 4 bootstrap globals and `interp.zig`'s 2
  (`backing`/`current_interp`) are the realistic floor per the reasoning in
  the Scorecard section, so the literal "1" isn't reachable even after
  `lineedit.zig` is threaded; revisit whether the DoD wording itself should
  be relaxed once that increment lands.

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
        Phase 5 (Tier 1–2: narrow threading) ─► checkpoint ─┬─► Tier 3 + Phase 6
                                                             └─► stop here (default)
```

Phases 1–4 are bounded and independently shippable. Phase 5's Tier 1–2 (bignum,
strtab, tidying the reducer's existing `ReductionCtx` threading) are small and
independently shippable too. Tier 3 (the entangled compiler/heap subsystems) and
Phase 6 are explicitly **not** committed to — they follow only if the Tier 1–2
checkpoint concludes the signature clarity was worth pursuing further.

## Risk register

| Phase | Risk | Mitigation |
|-------|------|------------|
| 1 | a genuine FFI consumer of an `export var` | none exist (A2/A3 proved it); golden byte-diff catches any |
| 2 | a moved field changes init order / `undefined` reads | structs default via `std.mem.zeroes`/`.{}`; per-module golden |
| 3 | re-pointing an owner singleton aliases a stale copy | one `interp` instance during transition; pointer-alias, not value-copy |
| 4 | a test's private `Interp` shares a hidden global (e.g. a `FILE` pool) | Phase 2c folds I/O in first; assert no residual global read |
| 5 (Tier 1) | ✅ materialized as expected: 53 bignum + 67 strtab call sites needed updating alongside the functions themselves | mitigated: per-subsystem + golden, mechanical sed-based replacement per call pattern, both landed clean |
| 5 (Tier 3, if pursued) | bundle-struct design for entangled subsystems is a real design question, not mechanical threading; risk of ending up as wide as `Interp` anyway | explicit checkpoint before starting; treat as its own design proposal, not a PR-sized mechanical step |
| 5 | signal handler needs interp state | single documented `current_interp` pointer (the irreducible C-ABI boundary) |

## Scorecard

Tracked by `scripts/shared-state-check.sh`.

| Metric | Baseline (Phase 0) | Now (2026-07-05) | Target |
|--------|--------------------|-----|--------|
| non-FFI module-scope mutable globals | 92 | **17** | 1 (signal pointer) |
| &nbsp;&nbsp;↳ gratuitous `export var` | 35 | **0** ✓ (Phase 1) | 0 |
| grouped state structs | 4 (`rs`/`ls`/`heap`/`cs`) | unified under one `Interp` |
| global state aggregates | 4 structs + loose globals | 0 (constructed in `main`) |
| interpreter instances constructible | 1 (implicit) | N (explicit — `main()` builds one; `Interp.init()`-shaped construction supports more) |
| golden corpus | 44/44 | 44/44 at every step |

The remaining 17, by file: `driver/lineedit.zig` (10, the line-editor
subsystem — Task 4, in progress), `runtime_state.zig` (4, the permanent
bootstrap exception: `gpa`/`allocator`/`io`/`environ`, set once at process
start, explicitly out of scope per `Interp`'s own doc comment), `interp.zig`
(2: `backing` + `current_interp` — see below), `word.zig` (1:
`readInteractiveLine`, the hook `lineedit.zig` installs — folds into Task 4).

**Why `interp.zig` holds 2, not 0, once every owner accessor reads through
`current_interp`.** `current_interp` defaults to `&backing` (a real,
zero-initialized `Interp` living in `interp.zig`) rather than `undefined`,
because the test binary (`main-tests`) never runs `main()` and needs a valid
interpreter from the very first access — exactly what the old `pub var interp`
singleton provided automatically. Reaching literally 1 would require
`current_interp: *Interp = undefined` with no safe default, which breaks
every test that doesn't first call some not-yet-invented bootstrap function.
Treated as the realistic floor for this file rather than a gap to keep
chasing.

**Test-harness exemption.** `testutil.zig` and `*_test(s).zig` files are
never linked into the `mira` executable (confirmed: only `main.zig`'s
comptime test-aggregation block imports them, and every other importer is
itself full of `test "..."` blocks) — their one-time-setup guard flags
(`ready`, `initialized`) are bookkeeping about the *ambient singleton for
test convenience*, not interpreter state a second `Interp` instance would
need. `scripts/shared-state-check.sh` now exempts them alongside the
pre-existing FFI-shim exemption.

## Notes on the irreducible boundary

OS signals are delivered through the C ABI to a fixed-signature handler that
takes no context, so a single `current_interp: *Interp` (set when an `Interp`
begins running, like `errno`'s thread-local) is the one unavoidable global.
**Implemented, 2026-07-05:** `interp.zig`'s `current_interp` is exactly this
pointer — every owner-module accessor (`heap.heap()`, `core_state.s()`, …)
reads through it, `main()` sets it to a locally-constructed `Interp`, and the
signal handlers (`repl.zig`'s `dieClean`/`reset`/`fpeError`, `dump.zig`'s
`sigdefer`) read the same accessors ambiently since they cannot take
parameters — the same category of exception documented for the A4 signal
trampoline in [REDESIGN_DATA_MODEL.md](REDESIGN_DATA_MODEL.md). Everything
else — heap, lexer, runtime, compiler, I/O, bignum, strings — is owned,
explicit `Interp` state reached through that one pointer.
