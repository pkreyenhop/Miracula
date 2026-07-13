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
- [x] Every `anytype` parameter has a documented resolution (§5.2) — see
      [GO_ANYTYPE_INVENTORY.md](GO_ANYTYPE_INVENTORY.md) (Phase 0, 2026-07-13).
- [x] Every `union(enum)` has been mapped to a documented Go pattern (§5.3) in
      a checked-in table — see [GO_UNION_INVENTORY.md](GO_UNION_INVENTORY.md)
      (Phase 0, 2026-07-13; revised the plan from one canonical pattern to two,
      chosen by hot-path-or-not).
- [x] The `Comb` enum's comptime-generation strategy has a Go equivalent
      decided (§5.4, Phase 0, 2026-07-13: `go:generate`) — not yet prototyped;
      prototyping happens at Phase 5 (the dry-run translation), not Phase 0.
- [x] Every Zig error set member has a named Go counterpart in a checked-in
      correspondence table (§5.5) — see
      [GO_ERROR_CORRESPONDENCE.md](GO_ERROR_CORRESPONDENCE.md) (Phase 0,
      2026-07-13).
- [x] The bignum and allocator-threading questions (§5.6, §5.7) are decided,
      not open (Phase 0, 2026-07-13).
- [ ] All user-facing behaviour stays byte-identical throughout every step of
      this plan (golden corpus + differential suite + spine + sigint +
      smoke) — this plan changes *shape*, never behaviour, same discipline as
      ZIG_NATIVE_PLAN.

## 5. Go-specific decisions (things ZIG_NATIVE_PLAN never had to decide)

### 5.1 Package layout and stdlib name collisions

**Decided (Phase 0, 2026-07-13).** Target Go module layout, directly off
[ZIG_NATIVE_PLAN §4.1](ZIG_NATIVE_PLAN.md)'s tree, with two renames forced by
Go stdlib collisions and one forced by Go's own `os` package:

| Zig directory | Go package | Why |
| --- | --- | --- |
| `src/graph/` | `graph` | no collision |
| `src/syntax/` | `syntax` | no collision |
| `src/semantics/` | `semantics` | no collision |
| `src/eval/` | `eval` | no collision |
| `src/session/` | `session` | no collision |
| `src/io/` | `mirio` | Go stdlib owns `io` |
| `src/runtime/` | `mrt` | Go stdlib owns `runtime` |
| `src/os.zig` (the POSIX floor) | `platform` | Go stdlib owns `os`; this file's *purpose* — "the one place OS syscalls live" — is better served by a name that doesn't fight the import of Go's actual `os` package everywhere else |
| `src/tools/fdate.zig`, `just.zig`, `menudriver.zig` | `cmd/fdate`, `cmd/just`, `cmd/menudriver` | each is a standalone binary today (per ZIG_MIGRATION.md Phase 1); Go convention puts those under `cmd/`, one package per binary, rather than a shared `tools` package — settled in favor of the idiomatic form since nothing forces the shared-package shape |

This table is a one-time decision; every later phase step references it
instead of re-deciding.

### 5.2 `anytype` resolution

19 sites, 9 files (§3 table). Go has generics (type parameters with
constraints) but not Zig's comptime duck-typing, and not overloading by name.

**Decided (Phase 0, 2026-07-13):** [GO_ANYTYPE_INVENTORY.md](GO_ANYTYPE_INVENTORY.md)
resolves all 19 sites into five categories, not the two anticipated above.
The two biggest surprises: 11 of 19 are the single "printf-style formatting"
pattern (`comptime fmt, args: anytype` → Go's `format string, args ...any`,
already the stdlib idiom — zero design left), and 4 more (`os.zig`'s hand-
rolled `sscanf`/`fscanf`) turn out to have a direct Go stdlib replacement
(`fmt.Sscanf`/`fmt.Fscanf`) — a deletion, not a translation. `heap.zig`'s
`constructor` resolves as originally sketched, split into
`ConstructorWord`/`ConstructorInt`/`ConstructorStr`. `strtab.strBits`
(1 site) is expected to collapse to a single concrete type once Phase 1's
c-string cleanup lands. See the inventory for the full per-site table.

### 5.3 `union(enum)` → Go pattern

Go has no sum types. Pick a small number of canonical patterns and apply them
consistently, rather than deciding per call site during the port (that's
exactly the kind of decision this whole plan exists to front-load).

**Decided (Phase 0, 2026-07-13), revising the single-pattern recommendation
below:** [GO_UNION_INVENTORY.md](GO_UNION_INVENTORY.md) found that "always
tagged struct" is wrong for the AST. **Two** patterns, chosen by whether the
type appears in the reduction hot path:

- **Tagged struct** (`Kind` field + a struct wide enough for every variant)
  for hot-path, fixed-width types: `graph/value.zig`'s `Kind`,
  `syntax/lexer.zig`'s `Escape`/`EscapeErrorKind`. Preserves bit layout,
  avoids per-value allocation, matches ZIG_NATIVE_PLAN §4.3's stated
  preference for these specific types.
- **Interface + one concrete struct per variant** for cold, tree-shaped
  types — all 11 AST/directive unions (`syntax/ast.zig`'s 8, `token_filter.zig`'s
  2, `modules.zig`'s `ExportPart`). This matches Go's own `go/ast` package
  convention exactly (`Expr` as an interface, `*ast.BinaryExpr` etc. as
  implementers) — the AST is built once per script and walked a handful of
  times, so the allocation/dispatch cost the tagged-struct pattern exists to
  avoid for the reducer doesn't apply here, and the interface form is both
  more idiomatic and a closer structural match to the existing `*Expr`/`*Pat`
  child-pointer fields.
- One site (`graph/word.zig`'s pre-Phase-5 `Value`/`classify` seam) is not
  ported at all — superseded by `graph/value.zig`'s `Kind`, expected deleted
  by the time Phase 1 of this plan finishes.

See the inventory for the full 15-site table and the reasoning per row.

### 5.4 `Comb`'s comptime generation

`graph/value.zig`'s `Comb = enum(u16)` is generated at **Zig comptime**
directly from `combinator.cmbnms` (see ZIG_NATIVE_PLAN Phase 5 step 1's
landed entry) specifically so it can never drift from the numbering every
reducer dispatch table depends on. Go has no comptime reflection over a
runtime slice.

**Decided (Phase 0, 2026-07-13): `go:generate`.** A small Go generator
program reads `combinator.cmbnms`'s Go-side translation (a plain
`[]string`, the Go form of the Zig source-of-truth slice) and emits
`comb_gen.go` with `const` values via `go:generate go run
./internal/gen/comb`, run once and checked in like any other generated Go
file. This preserves the "generated, can't drift" property `Comb`'s Zig
implementation was specifically built for (rejected the hand-transcribe
alternative for the same reason the Zig version wasn't hand-transcribed
either: `cmbnms` is unlikely to change, but the whole point of generating
was drift-proofing, and that property is worth keeping across the port, not
just at origin). Verification carries over unchanged: the same spot-check
test (`S`, `PLUS`, `False`, `True`, `NIL`, `NILS`, `UNDEF`, plus member
count) the Zig version already has, ported alongside.

### 5.5 Error-set correspondence

Five Zig error sets exist today: `word.ReduceError` (`Interrupted`,
`FloatOverflow`), `runtime.errors.MiraError`, `semantics.modules.ModuleError`,
`parser.parser_api.ParseError`, `syntax.pratt.ParseError`. Zig error unions
(`E!T`) map onto Go's `(T, error)` idiom directly — that correspondence is
not in question.

**Decided (Phase 0, 2026-07-13):** [GO_ERROR_CORRESPONDENCE.md](GO_ERROR_CORRESPONDENCE.md)
uses the custom-type form (`type XxxError struct { Kind XxxErrorKind; ... }`)
as originally recommended, one per set, each in the Go package matching its
Zig home (`graph`, `session`, `semantics` ×2, `syntax`). Two findings worth
noting here: `MiraError`'s `EvaluationInterrupted` member is already a
documented-unused placeholder in the Zig source and is flagged for likely
non-porting (re-verify at port time); `pratt.ParseError`'s `OutOfMemory`
member is dropped entirely, the first concrete case of §5.7's
allocator-plumbing-disappears principle actually removing an error variant,
not just a function parameter. See the correspondence doc for the full
per-set table.

### 5.6 Bignum: port or replace with `math/big`?

`graph/bignum.zig` (1,088 lines) is a hand-rolled arbitrary-precision
integer implementation with Miranda-specific formatting rules (`show`'s
output format is part of the golden-pinned behaviour).

**Decided (Phase 0, 2026-07-13): port the existing implementation
mechanically first; do not swap to `math/big` in the same pass.** Swapping
libraries changes formatting/rounding/edge cases in ways the differential
suite would need to re-validate from scratch, which is exactly the kind of
behaviour-affecting change this plan's "shape never behaviour" discipline
exists to avoid. A `math/big` swap, if wanted, is a legitimate *follow-up*
once the mechanical port is golden-verified byte-identical — out of scope
for this plan and for the port it prepares.

### 5.7 Allocator threading: keep or drop?

18 files thread `std.mem.Allocator` explicitly (a Zig idiom with no
motivating equivalent once Go's GC is available).

**Decided (Phase 0, 2026-07-13): drop it at translation time, not preserve
it.** Each `alloc: std.mem.Allocator` parameter simply disappears from the
Go signature; call sites use `make`/`append`/`new` directly. This is a
*simplification* that happens naturally, one call site at a time, during
translation — it does not need its own prep phase, but it does mean the
"mechanical" claim for this project is "mechanical modulo
mechanically-droppable allocator plumbing," worth stating explicitly so
nobody expects a literal `Allocator` interface to appear in the Go code.
Confirmed by [GO_ERROR_CORRESPONDENCE.md](GO_ERROR_CORRESPONDENCE.md)'s
`pratt.ParseError` row and [GO_UNION_INVENTORY.md](GO_UNION_INVENTORY.md)'s
`token_filter.Directive` row: this principle already removes one error-set
member and one hand-written `deinit` method during the Phase 0 inventory
work, before the port has even started.

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

**Phase 0 complete (2026-07-13).** All four artifacts landed. Two findings
changed the plan's own text rather than just filling in blanks:

- **§5.3's "one canonical `union(enum)` pattern" was wrong.** Working through
  all 15 sites individually (not just the two illustrative examples §5.3
  originally cited) showed the AST unions (11 of 15) need an
  interface-per-variant representation matching Go's own `go/ast` convention,
  not the tagged-struct form that's correct for the reducer's hot-path types.
  §5.3 above now states two patterns, chosen by hot-path-or-not, and
  [GO_UNION_INVENTORY.md](GO_UNION_INVENTORY.md) records which of the 15
  sites gets which. This is exactly the kind of correction this phase exists
  to catch before, not during, the real port.
- **The allocator-drop principle (§5.7) already has two concrete
  consequences**, found while inventorying, not invented in §5.7 itself:
  `syntax/pratt.zig`'s `ParseError` loses its `OutOfMemory` member (no Go
  allocation-failure error to carry), and `token_filter.zig`'s `Directive`
  loses its hand-written `deinit` method (Go's GC reclaims what it freed).
  Both recorded in their respective inventories rather than treated as
  surprises to rediscover later.
- No code changed, as the gate requires — all three inventories and this
  document's own §5 updates are additive documentation.

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

**Started (2026-07-13).** First slice landed against step 1: `infer.zig`'s
11 zero-external-caller functions (`sterilise`/`printelement`/`cyclicAbstr`/
`txchange`/`repT1`/`repT`/`fixType`/`checkfbs`/`checkcolfn`/`genbnft`/
`checktype`) — the exact next-slice candidate ZIG_NATIVE_PLAN's own Phase 5
step 4 notes had already identified and left unstarted. Full details,
including a pre-existing compile-blocking bug this slice's first-ever test
for `checktype` caught (Zig's lazy analysis had never compiled that
function's body, since it had zero callers before this), are recorded as
"Step 4g" in [ZIG_NATIVE_PLAN.md](ZIG_NATIVE_PLAN.md) rather than duplicated
here — this plan tracks *that* the load-bearing work is progressing, not
the mechanical detail of each slice. `heap.zig`'s public API, `lower.zig`'s
remaining ~1,761 lines, and the rest of `infer.zig` (including its
50–78-call-site core accessors, flagged as materially larger and riskier)
are still ahead. Step 2 (the `c_int`/`[*:0]` sweep) has not been started;
scorecard now shows 168/231 for those two metrics (up from the 166/228
recorded in this plan's §3 baseline — pre-existing drift from before this
session, not caused by step 1's work, confirmed by re-running the scorecard
against a clean pre-session tree before attributing it).

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
