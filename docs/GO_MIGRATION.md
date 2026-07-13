# Miracula — Go Migration Readiness Plan

> **Goal:** get the Zig codebase into a state where translating it to Go is
> **mechanical** — module-by-module, close to 1:1, with no per-file design
> decisions left to make during the port itself. This document plans the
> *preparation*, not the port. It does not schedule a single line of Go.
>
> **Created:** 2026-07-13.

---

## 1. Relationship to ZIG_NATIVE_PLAN.md

[ZIG_NATIVE_PLAN.md](ZIG_NATIVE_PLAN.md) is already doing most of the work this
plan needs, for its own reasons (making the codebase read as idiomatic native
Zig). Every one of its goals happens to also be a Go-readiness requirement:

| ZIG_NATIVE_PLAN goal | Why it's also Go-readiness |
| --- | --- |
| No `setjmp`/`longjmp` (Phase 3, **done**) | Go has no non-local jumps at all; this must already be gone, not translated |
| One front end, no C lexer (Phase 1, **done**) | there is exactly one lexer to port, not a lexer plus a bridge |
| No ambient singletons, explicit receivers (Phase 4, **substantially done**) | Go has no comptime-ambient-state trick; every dependency must already arrive as a parameter |
| `@import` DAG, no cycles (Phase 4, **done**, `layer_check.py`-enforced) | Go's compiler *rejects* import cycles outright — an existing cycle would block `go build` on day one of the port |
| Typed `Value`/`Comb`/`CellRef`, no bare `Word` threshold checks (Phase 5, **in progress**) | translating a raw `if (x < ATOMLIMIT)` into Go perpetuates a bug magnet; translating a `switch (v.kind())` does not |
| Structured `MiraError`/`Diagnostics`, no `SYNERR` flags (Phases 2–3, **done**) | Go's `(T, error)` idiom maps directly onto Zig error unions; it does not map onto a scattered flag-and-check-later pattern |
| `std.Io` writers, no libc `FILE*` (Phase 2, **done**) | Go I/O is `io.Writer`/`io.Reader`; the old `FILE*`-in-a-cell hack has no Go equivalent to translate to, it just has to already be gone |
| `[*:0]`/`c_int`/`extern fn` confined to `os.zig` (Phase 2/6, **in progress, see §3**) | Go has no C string/int types at all outside `cgo`, which this project does not want |

**This plan does not repeat that work.** Instead it: (a) names exactly which
*remaining* ZIG_NATIVE_PLAN items are load-bearing prerequisites vs. which are
orthogonal Zig polish, and (b) covers the decisions ZIG_NATIVE_PLAN never had
to make, because they only exist at the Zig→Go boundary — sum types, comptime
generics, comptime-generated enums, package-name collisions with Go's
standard library, and what to do with the hand-rolled bignum and allocator
threading once Go's GC is available.

## 2. What does NOT change

Same as [ZIG_NATIVE_PLAN.md §2](ZIG_NATIVE_PLAN.md): Miranda semantics as
pinned by the golden/differential/spine/sigint/smoke suites, the `.x` dump
format, Miranda domain vocabulary (`hd`/`tl`, combinator names, offside,
spine, private names), and the SK-combinator graph-reduction execution model.
**The test suites are the specification for the eventual port, exactly as
they are for the Zig-native rearchitecture** — they run against a compiled
binary's stdin/stdout/exit code and don't care what language produced it.
That reusability is the whole reason preparing in Zig first is worth doing:
every golden case, every differential case, and the `.x` wire format stay
byte-identical gates whether the binary under test is `zig build`'s or a
future `go build`'s.

## 3. Baseline (measured 2026-07-13)

Numbers from `scripts/scorecard.sh` plus targeted greps, current `main`:

| Metric | Count | Where it concentrates |
| --- | ---: | --- |
| `[*:0]` C-string types (must be 0 outside `os.zig`) | 289 | `os.zig`(37), `session/commands.zig`(31), `parser/lex.zig`(26), `session/config.zig`(18), `graph/heap.zig`(13), `compiler/module_loader.zig`(12), `session/boot.zig`(11), `graph/strtab.zig`(11) |
| `c_int`/`c_long`/`c_ulong` (must be 0 outside `os.zig`) | 289 | `os.zig`(85), `graph/bignum.zig`(53), `eval/reduce_rt.zig`(17), `session/commands.zig`(12), `session/config.zig`(11), `eval/stream.zig`(11) |
| `extern fn` (must be `os.zig`-only) | 5 files | `os.zig`, `io/utf8.zig`, `io/signals.zig`, `io/platform.zig`, **`eval/reduce_rt.zig`** ← the one out-of-place site |
| `anytype` parameters | 19 sites, 9 files | `os.zig`(6), `eval/stream.zig`(4), `syntax/lexer.zig`(2), `syntax/directives.zig`(2), one each in `menudriver.zig`/`parser.zig`/`runtime/errors.zig`/`strtab.zig`/`heap.zig` |
| `union(enum)` declarations | 15 | scattered across `graph/`, `syntax/`, `semantics/` |
| Files > 1,000 lines | 9 | `heap.zig`(1695), `lower.zig`(1761), `infer.zig`(1709), `lexer.zig`(1214), `dump.zig`(1176), `os.zig`(1145), `bignum.zig`(1088), `reduce_core.zig`(966), `reduce_rt.zig`(959) |
| Directories outside the ZIG_NATIVE_PLAN target tree | 3 | `compiler/`, `parser/`, `runtime/` — not in [ZIG_NATIVE_PLAN §4.1](ZIG_NATIVE_PLAN.md)'s target tree; still hold live code (`compiler_state.zig`, `module_loader.zig`, `lex.zig`, `codegen.zig`, `runtime_state.zig`, `errors.zig`) that hasn't been folded into `semantics/`/`syntax/`/`session/` yet |
| Go stdlib package-name collisions in current directory names | 2 | `src/io/` (Go has `io`), `src/runtime/` (Go has `runtime`) — `os.zig` as a package-*name* would also collide with Go's `os` if kept literally |

Structural facts this plan is built around:

- **The current Zig tree already resembles the Go target tree.** `syntax/`,
  `semantics/`, `graph/`, `eval/`, `session/` match [ZIG_NATIVE_PLAN
  §4.1](ZIG_NATIVE_PLAN.md)'s target layout almost file-for-file. This is the
  single biggest reason a mechanical port is plausible at all: package
  boundaries don't need to be invented, they need to be *finished* (fold
  `compiler/`/`parser/`/`runtime/` into their target homes) and *renamed*
  around two stdlib collisions.
- **Phase 5 (typed `Value`) is mid-flight.** `reduce_core`/`spine`/`match`/
  `depend`/`reduce_rt` have been retyped onto `Value` (see recent commits);
  `heap.zig`'s public API, `lower.zig`, `infer.zig`, and the combinator
  handlers have not. Until every hot-path call site reads `switch (v.kind())`
  instead of a numeric threshold check, there is nothing safe to translate
  mechanically in the reducer — a literal port of `if (x < ATOMLIMIT)` is not
  "mechanical," it's carrying a footgun into a new language.
- **The `[*:0]`/`c_int` counts have barely moved since the 2026-07-05
  baseline** (299→289, 309→289) — this is genuinely still Phase 6 work, not
  yet started at scale. It is the single largest blocker for Go readiness:
  Go's `os`/`syscall`/`strings` packages want `[]byte`/`string`, never
  null-terminated C buffers, and `c_int` has no idiomatic Go form anywhere
  outside a `cgo` boundary this project has deliberately avoided rebuilding.

## 4. Definition of done (Go-readiness checklist)

The test for every item below: **could this file be translated to Go by a
mechanical, line-by-line pass with no design questions left open?**

- [ ] `[*:0]`, `c_int`/`c_long`/`c_ulong`, `extern fn` exist **only** in
      `os.zig` (ZIG_NATIVE_PLAN's own Phase 6 gate — adopted verbatim here,
      since it's the same requirement for a different reason).
- [ ] `Word` survives only in `graph/dump.zig` (ZIG_NATIVE_PLAN Phase 5's own
      gate) — every other file reads/writes `Value`/`Comb`/`CellRef`.
- [ ] No file over 1,000 lines (ZIG_NATIVE_PLAN §1's own bar) — kept here
      because large single-file translations produce large, unreviewable
      diffs, defeating "mechanical."
- [ ] `compiler/`, `parser/`, `runtime/` folded into `semantics/`/`syntax/`/
      `session/`/`graph/` per the ZIG_NATIVE_PLAN target tree — no directory
      exists that doesn't already have a decided Go package name (§5.1).
- [ ] Every `anytype` parameter has a documented resolution (§5.2): either
      collapsed to a small number of named non-overloaded functions, or
      flagged for a Go generic type parameter with a written-out constraint.
- [ ] Every `union(enum)` has been mapped to the one canonical Go pattern
      (§5.3) in a checked-in table — no per-site re-derivation during the port.
- [ ] The `Comb` enum's comptime-generation strategy has a Go equivalent
      decided and prototyped (§5.4), not left as "figure it out during the
      port."
- [ ] Every Zig error set member has a named Go counterpart in a checked-in
      correspondence table (§5.5).
- [ ] The bignum and allocator-threading questions (§5.6, §5.7) are decided,
      not open.
- [ ] All user-facing behaviour stays byte-identical throughout every step of
      this plan (golden corpus + differential suite + spine + sigint +
      smoke) — this plan changes *shape*, never behaviour, same discipline as
      ZIG_NATIVE_PLAN.

## 5. Go-specific decisions (things ZIG_NATIVE_PLAN never had to decide)

### 5.1 Package layout and stdlib name collisions

Target Go module layout, directly off [ZIG_NATIVE_PLAN §4.1](ZIG_NATIVE_PLAN.md)'s
tree, with two renames forced by Go stdlib collisions and one forced by Go's
own `os` package:

| Zig directory | Go package (proposed) | Why renamed |
| --- | --- | --- |
| `src/graph/` | `graph` | no collision |
| `src/syntax/` | `syntax` | no collision |
| `src/semantics/` | `semantics` | no collision |
| `src/eval/` | `eval` | no collision |
| `src/session/` | `session` | no collision |
| `src/io/` | `mirio` | Go stdlib owns `io` |
| `src/runtime/` | `mrt` | Go stdlib owns `runtime` |
| `src/os.zig` (the POSIX floor) | `platform` | Go stdlib owns `os`; this file's *purpose* — "the one place OS syscalls live" — is better served by a name that doesn't fight the import of Go's actual `os` package everywhere else |
| `src/tools/` | `tools` (or split into `cmd/fdate`, `cmd/just`, `cmd/menudriver` — Go convention puts standalone binaries under `cmd/`) | idiomatic Go, not forced |

Decide and record this table before any file moves — it's a one-time
decision, and every later phase step references it instead of re-deciding.

### 5.2 `anytype` resolution

19 sites, 9 files (§3 table). Go has generics (type parameters with
constraints) but not Zig's comptime duck-typing, and not overloading by name.
Each site needs one of two resolutions, decided per-site and recorded in
`docs/GO_ANYTYPE_INVENTORY.md` (to be created as this phase's own artifact):

- **Fixed small set of concrete types** (e.g. `heap.zig`'s `constructor(self,
  n, x: anytype)` dispatching on `Word`/`c_int`/`[*:0]const u8`): split into
  named functions (`constructorWord`, `constructorInt`, `constructorStr`) —
  the direct Go analogue of what Zig's comptime dispatch already compiles
  down to, just made explicit. Prefer this; it's the more mechanical choice.
- **Genuinely open-ended / allocator-shaped** (`os.zig`'s 6 sites,
  `stream.zig`'s 4): likely collapse away entirely once allocator threading
  is dropped (§5.7) — audit these *after* §5.7 is decided, not before.

### 5.3 `union(enum)` → Go pattern

Go has no sum types. Pick **one** canonical pattern and apply it everywhere,
rather than deciding per call site during the port (that's exactly the kind
of decision this whole plan exists to front-load):

**Recommended: tagged struct, not interface-per-variant.** A `Kind` enum
field plus a struct wide enough to hold every variant's payload — this is
already the shape `graph/value.zig`'s `Kind = union(enum) { imm: u8, comb:
Comb, cell: CellRef }` takes conceptually, and it matches this project's own
stated preference (ZIG_NATIVE_PLAN §4.3) for keeping bit layout stable rather
than growing an allocation-heavy object graph. An interface-per-variant
(`type Kind interface { isKind() }` with `Imm`/`Comb`/`Cell` structs
implementing it) is the more "idiomatic Go" answer but breaks the bit-layout
goal and adds an allocation + dynamic dispatch to a hot path (`Value.kind()`
runs on every reduction step). Reject it for hot-path types (`Value`,
`Kind`, `Diagnostics`' node kinds); it's fine for genuinely cold, rare-branch
unions if any turn up in the inventory.

Produce a table of all 15 sites with their chosen pattern before starting
the translation itself.

### 5.4 `Comb`'s comptime generation

`graph/value.zig`'s `Comb = enum(u16)` is generated at **Zig comptime**
directly from `combinator.cmbnms` (see ZIG_NATIVE_PLAN Phase 5 step 1's
landed entry) specifically so it can never drift from the numbering every
reducer dispatch table depends on. Go has no comptime reflection over a
runtime slice. Two options:

- **`go:generate` + a small generator program** reading `cmbnms`'s Go
  translation and emitting `comb_gen.go` with `const` values — keeps the
  "generated, can't drift" property, translates the *intent* rather than the
  mechanism.
- **Hand-transcribe once, pin with a test** that checks member count and a
  handful of spot values (`S`, `PLUS`, `False`, `True`, `NIL`, `NILS`,
  `UNDEF`) against `word.zig`'s numbering — simpler, matches how the Zig
  version was itself *verified* (a dedicated spot-check test), loses the
  "can't drift by construction" property.

Recommend `go:generate`, since `cmbnms` itself is unlikely to change but the
whole point of generating rather than hand-writing was drift-proofing, and
that property is worth preserving across the port, not just at origin.

### 5.5 Error-set correspondence

Five Zig error sets exist today: `word.ReduceError` (`Interrupted`,
`FloatOverflow`), `runtime.errors.MiraError`, `semantics.modules.ModuleError`,
`parser.parser_api.ParseError`, `syntax.pratt.ParseError`. Zig error unions
(`E!T`) map onto Go's `(T, error)` idiom directly — that correspondence is
not in question. What needs deciding once, not per-site:

- **Representation:** sentinel `var ErrInterrupted = errors.New(...)` values
  (simple, works with `errors.Is`) vs. a small custom `type MiraError struct
  { Kind MiraErrorKind; ... }` implementing `error` (carries structured
  data, matches the `Diagnostics{span, message}` shape ZIG_NATIVE_PLAN's
  Phase 2 already built). **Recommend the custom-type form** — it's the
  direct translation of the Diagnostics work already done, and Go's error
  wrapping (`errors.As`) gives back the typed-switch behaviour Zig's
  `switch (err)` has today.
- Produce the five-set → Go-type correspondence table before translation
  starts; it's small and mechanical once decided.

### 5.6 Bignum: port or replace with `math/big`?

`graph/bignum.zig` (1,088 lines) is a hand-rolled arbitrary-precision
integer implementation with Miranda-specific formatting rules (`show`'s
output format is part of the golden-pinned behaviour). **Recommend: port
the existing implementation mechanically first; do not swap to `math/big`
in the same pass.** Swapping libraries changes formatting/rounding/edge
cases in ways the differential suite would need to re-validate from
scratch, which is exactly the kind of behaviour-affecting change this
plan's "shape never behaviour" discipline exists to avoid. A `math/big`
swap, if wanted, is a legitimate *follow-up* once the mechanical port is
golden-verified byte-identical — not part of getting to that first
checkpoint.

### 5.7 Allocator threading: keep or drop?

18 files thread `std.mem.Allocator` explicitly (a Zig idiom with no
motivating equivalent once Go's GC is available). **Recommend: drop it at
translation time, not preserve it.** Each `alloc: std.mem.Allocator`
parameter simply disappears from the Go signature; call sites use
`make`/`append`/`new` directly. This is a *simplification* that happens
naturally, one call site at a time, during translation — it does not need
its own prep phase, but it does mean the "mechanical" claim for this project
is "mechanical modulo mechanically-droppable allocator plumbing," which is
worth stating explicitly so nobody expects a literal `Allocator` interface
to appear in the Go code.

### 5.8 Testing convention

Current convention ([memory: Test & doc conventions] — inline per-function
`test "..."` blocks immediately following the function they cover, with a
`Tests:` doc-comment cross-reference) has no exact Go equivalent — Go tests
live in a separate `_test.go` file per source file, not interleaved. Decided
mapping: one `foo.go` ↔ one `foo_test.go`, **preserve the grouping and the
`Tests:` cross-reference convention** — each `Foo_test.go` test function's
doc comment still names which production function(s) it covers, in the same
place the convention already puts that information today (immediately above
the function, referencing the test by name). This keeps the project's
existing "you can find a function's test by reading its doc comment"
property; only the file boundary changes, not the traceability.

## 6. Phases

| # | Name | Theme | Size |
| --- | --- | --- | --- |
| 0 | Decisions ledger | write down §5's tables before touching code | S |
| 1 | Finish load-bearing ZIG_NATIVE_PLAN work | Phase 5 completion, Phase 6 steps 1–2 | L |
| 2 | Directory consolidation | fold `compiler/`/`parser/`/`runtime/` into target tree, apply §5.1 renames | M |
| 3 | File-size ratchet | split every file > 1,000 lines | M |
| 4 | `os.zig` boundary sweep | move the stray `extern fn` (`reduce_rt.zig`), confirm the floor is single-file | S |
| 5 | Go readiness gate | scorecard at zero on every §4 metric; dry-run one leaf package (`graph/bignum` or `graph/strtab`) by hand-translating it to Go and running its unit tests as a proof of mechanicalness | M |

Sizes: S ≤ 1 day, M = a few days, L = 1–2 weeks. Every phase ends with `zig
build check && zig build strict && zig build test-golden && zig build
test-regression` green, exactly as ZIG_NATIVE_PLAN requires — this plan adds
readiness work, it doesn't relax that gate.

---

### Phase 0 — Decisions ledger

**Goal:** every table in §5 exists as a checked-in artifact, decided once,
before any code moves.

**Steps**
1. `docs/GO_ANYTYPE_INVENTORY.md` — the 19-site table from §5.2.
2. `docs/GO_UNION_INVENTORY.md` — the 15-site table from §5.3.
3. `docs/GO_ERROR_CORRESPONDENCE.md` — the 5-set table from §5.5.
4. Record the §5.1 package-naming table and the §5.4/§5.6/§5.7 decisions in
   this document (fold into §5 once settled — they're drafted as
   recommendations above; this step is where they become decisions).

**Gate:** four artifacts exist; no code changed.

---

### Phase 1 — Finish load-bearing ZIG_NATIVE_PLAN work

**Goal:** close the specific ZIG_NATIVE_PLAN gaps that block mechanical
translation — not all of ZIG_NATIVE_PLAN, just the load-bearing subset.

**Steps**
1. **Finish Phase 5 (typed `Value`)** per ZIG_NATIVE_PLAN's own step 4:
   migrate `heap.zig`'s public API, `lower.zig`, `infer.zig`, and the
   `eval/combinators/*` handlers onto `Value`/`Comb`/`CellRef`. Gate: `toRaw`
   escape-hatch count → 0; `Word` appears only in `graph/dump.zig`.
2. **Finish ZIG_NATIVE_PLAN Phase 6 steps 1–2** (types and buffers): every
   `c_int`/`c_long`/`c_ulong` outside `os.zig` → `i32`/`i64`/`usize`/`bool`;
   every `[*:0]` outside `os.zig` → `[]const u8`/`[:0]u8` at the minimum
   boundary that still needs a sentinel. This is the single largest
   remaining chunk of work in this whole plan (289 + 289 sites, concentrated
   in the 8 files listed in §3) — expect this to be the long pole.
3. Re-run `scripts/scorecard.sh` after each subsystem; update
   `scripts/scorecard.baseline` downward per ZIG_NATIVE_PLAN's own cadence.

**Gate:** scorecard's `[*:0]`/`c_int`-family/`toRaw` counts all at the
`os.zig`-only floor; full suite green.

---

### Phase 2 — Directory consolidation

**Goal:** `compiler/`, `parser/`, `runtime/` no longer exist as top-level
directories; every file in them has a home in `graph/`, `syntax/`,
`semantics/`, `session/`, or is deleted as dead legacy-lexer weight (per
ZIG_NATIVE_PLAN Phase 1 step 8's already-partial cleanup). Apply the §5.1
renames (`io/`→`mirio` naming decided, not yet applied; `runtime/`→`mrt`
likewise) as part of the same move, so there's one renaming pass, not two.

**Steps**
1. `compiler_state.zig`, `setup.zig`, `dump.zig`, `module_loader.zig` →
   fold into `semantics/modules.zig` (per ZIG_NATIVE_PLAN §4.1's own mapping,
   `module_loader.zig` is already named as `modules.zig`'s source) and
   `graph/dump.zig` (there are two `dump.zig`s today — `compiler/dump.zig`
   and `graph/dump.zig` — resolve the naming collision as part of this move).
2. `parser/codegen.zig`, `lex.zig`, `lex_state.zig`, `parser_api.zig` → fold
   into `semantics/lower.zig` (codegen) and confirm `lex.zig`/`lex_state.zig`
   are fully subsumed by `syntax/lexer.zig` per ZIG_NATIVE_PLAN Phase 1 step
   8's deferred cleanup, or finish that deletion here if still pending.
3. `runtime/core_state.zig`, `errors.zig`, `runtime_state.zig`, `version.zig`
   → fold into `session/interp.zig` (state) and a renamed `mrt/errors.go`-
   destined home for `MiraError`.
4. Directory move only — no logic changes — each commit is move-only per
   ZIG_NATIVE_PLAN's own commit-discipline convention.

**Gate:** `find src -maxdepth 1 -type d` matches exactly the §5.1 table;
DAG check (`layer_check.py`) still green; full suite green.

---

### Phase 3 — File-size ratchet

**Goal:** no file over 1,000 lines, so no single translation commit is
unreviewable.

**Steps**
1. Split `heap.zig` (1695), `lower.zig` (1761), `infer.zig` (1709),
   `lexer.zig` (1214), `dump.zig` (1176 — post-Phase-2 merge target),
   `os.zig` (1145), `bignum.zig` (1088), `reduce_core.zig` (966),
   `reduce_rt.zig` (959) along their existing internal section boundaries
   (most already have `// ---` or comment-delimited clusters from prior
   idiomatic-Zig splitting work — reuse those seams rather than inventing
   new ones).
2. Each split is move-only where possible (function bodies unchanged,
   only file boundaries move) — flag any split that turns out to require a
   real interface change and handle it as its own reviewable commit.

**Gate:** scorecard's "files > 1,000 lines" = 0; full suite green.

---

### Phase 4 — `os.zig` boundary sweep

**Goal:** confirm every C-boundary primitive genuinely lives in one file.

**Steps**
1. Move `eval/reduce_rt.zig`'s `extern fn fromUTF8` (the one out-of-place
   `extern fn` found in §3) behind an `os.zig`/`platform.zig` wrapper —
   `reduce_rt.zig` calls the wrapper, not the C symbol directly.
2. Re-audit `extern fn` count: should be `os.zig`-only afterward.

**Gate:** `grep -rl "extern fn" src` returns exactly one file; full suite
green.

---

### Phase 5 — Go readiness gate

**Goal:** prove the "mechanical" claim before committing to the real port,
the same way ZIG_NATIVE_PLAN's own Phase 0 turned "looks idiomatic" into a
checkable number.

**Steps**
1. Full scorecard run against the §4 checklist — every box ticked.
2. **Dry-run translation:** hand-translate one genuinely leaf package (no
   fan-in from anything except `graph/`'s own internals — `graph/strtab.zig`
   or `graph/bignum.zig` are the best candidates: small-ish, no `Interp`
   coupling, already unit-tested in isolation) to Go by hand, write the
   `_test.go` file per §5.8's convention, and confirm its tests pass
   standalone. This is the actual proof of "mechanical" — if this dry run
   surfaces a design question that isn't already answered in §5, that's a
   sign this plan is missing something, and the gap gets folded back into
   §5 before the real port starts, not discovered mid-port.
3. Write up the dry run's findings as a short addendum to this document
   (a "Phase 5 landed" entry, matching ZIG_NATIVE_PLAN's own convention for
   recording what was actually learned by doing the work, not just what was
   planned).

**Gate:** scorecard clean; dry-run package's Go tests pass; findings
recorded. **This is where GO_MIGRATION.md's own scope ends** — the actual
port (translating `graph/`→`eval/`→`semantics/`→`syntax/`→`session/`,
leaf-first, each package gated by the reused golden/differential/spine/
sigint/smoke suites run against the Go binary) is a new plan, written after
this one's gate is met, informed by whatever the dry run actually found.

---

## 7. Working cadence

Same discipline as [ZIG_NATIVE_PLAN.md §6](ZIG_NATIVE_PLAN.md): move-only
commits separate from signature changes separate from behaviour-affecting
changes (there should be none of the latter — this whole plan is shape-only).
Every commit builds and passes `zig build check`. Phase gates run the full
suite (`check`, `strict`, `test-golden`, `test-regression`, `test-sigint`,
`bench`) before the phase's closing commit updates
`scripts/scorecard.baseline` downward. The suites are the spec — if a phase
step and a golden case disagree, the golden case wins.
