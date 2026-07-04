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

Next candidates, in roughly ascending difficulty: `startup.zig` (862 lines,
~31 touches), `module_loader.zig` (690, ~232), `lex.zig` (2079, ~134), then
the two hardest: `trans.zig` (1830, ~807) and `types.zig` (2736, ~788).
* **Irreducible exception (unchanged):** OS signal handlers run on the C ABI and
  cannot take any explicit parameter; they read a single `current_interp: *Interp`
  set on entry — the one documented global, analogous to `errno` and the A4
  signal trampoline.
* *DoD per subsystem: no ambient-global-singleton access outside the subsystem's
  own threaded struct(s) (or an explicitly documented exception); golden green.*

### Phase 6 — De-globalize & document *(close-out; conditional on Tier 3)*
Delete the global `var interp`; `main()` constructs it explicitly
(`var interp = Interp.init(gpa); defer interp.deinit(); return interp.run(args);`).
Update [ARCHITECTURE.md](ARCHITECTURE.md) to drop the "singleton" language and
describe the `Interp` ownership model + the lone signal-delivery exception.

This is only reachable if Tier 3 of the revised Phase 5 happens — deleting the
global requires *every* subsystem (including the entangled compiler/heap tier)
to have stopped reaching it ambiently. If Tier 3 is judged not worth its bundle-
design cost after the Tier 1–2 checkpoint, Phase 6 stays permanently deferred
alongside it; Tier 1–2 alone do not remove enough ambient access to make deleting
`interp` sound.
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
