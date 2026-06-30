# Miracula — Idiomatic-Architecture & Readability Plan

> **Goal:** reshape the project so it reads like a *native Zig* project rather than
> a C port translated into Zig — **without changing observable behaviour**. Every
> step is gated by the golden corpus (44 byte-identical cases), `zig build test`,
> and `zig build lint`.

This plan sits alongside the completed/earlier plans and picks up the remaining
*architectural* (not syntactic) work:
[READABILITY_PLAN](READABILITY_PLAN.md) (naming + docs — done),
[IDIOMATIC_ZIG_PLAN](IDIOMATIC_ZIG_PLAN.md) (Clusters A–G),
[SHARED_STATE_PLAN](SHARED_STATE_PLAN.md) (state aggregation),
[REDESIGN_DATA_MODEL](REDESIGN_DATA_MODEL.md) (typed values / Track B),
[TESTABILITY_PLAN](TESTABILITY_PLAN.md) (per-function tests).

## Overall assessment

| Axis | State |
|------|-------|
| Zig syntax | Excellent |
| Documentation | Excellent (every module has `//!`; every public symbol has `///`) |
| Type safety | Good |
| Architecture | **Transitional** ← the remaining work |
| Overall idiomatic Zig | ~8/10 |

The remaining work is reducing **C-style architectural patterns**: a god-namespace
root module, a giant re-export layer, migration-era import aliases, raw-integer
domain codes, and duplicated definitions.

## Refactoring principles

* **Never change observable behaviour.** Golden stays byte-identical at every step.
* **Prefer smaller modules over larger files.**
* **Prefer namespaces over flattened APIs.**
* **Remove a compatibility layer only after all callers have migrated.**
* **Preserve documentation that adds semantic value;** never delete docs merely to
  shrink a file.
* **Work per-module, one commit at a time, golden-gated** (the cadence the rename,
  doc, and test passes used).

---

# Part A — Make `main.zig` idiomatic Zig

> **Status (done): Priorities 1, 2, 3, 4, 6, 7, 10 ✅.** The ~108-symbol re-export layer
> was dissolved over 8 golden-gated commits — all **1457** `main.X` references
> migrated to the owning modules (`heap`/`cs`/`rs`/constants/`errors`/the helper
> relocations/the cross-module functions). **No file imports `main` any more.**
> `main.zig` shrank **336 → 56 lines** (header + 4 imports + `main()` + the
> comptime test block). The inline helpers `get_id`/`get_fil` moved to `heap.zig`;
> `getStd*` callers go to `abi` directly. A `miranda.zig` public namespace was
> *not* added — the interpreter is an executable with no external public API, so
> the dissolved re-exports needed no replacement.
> Priority 3 (the `r7_*` import prefixes) is now also done — all ~127 uses across 13
> files dropped to clean module names, with the duplicate-import merges and the
> ambiguous `r7_reduce` cases (`engine` / `reduce_rt`) handled explicitly.
> Priority 4 (raw tag codes → `NodeTag`) is done too: `NodeTag` is now the single
> source of truth (the `ATOM`…`TCONS` `Word` consts derive from it via
> `@intFromEnum`), and every domain tag read across the tree (~126 comparisons + the
> reducer dispatch + 12 switches) is typed `.TAG`, including the hot reducer paths.
> The local `const TAG: u8` redeclarations in types/lex/trans/big are deleted; the
> only `u8`-returning reader left is the low-level `Heap.getTag` storage accessor.
> `make(TAG, …)` writes use the canonical `word.TAG`; numeric tag diagnostics keep
> `@intFromEnum`.
> **Part A is now complete.** Remaining idiomatic work lives in Part B (R1 reducer
> de-dup, R2 reducer camelCase, R4 `bool` predicates, R7–R10).

## Problem

`main.zig` currently acts as executable entry point **and** compatibility layer
**and** public API **and** namespace **and** constant definitions **and** test
aggregation **and** module re-export. That is not idiomatic Zig. (Measured: it
re-exports **~108 symbols**.)

## Target

Reduce `main.zig` to **imports + `main()` + test aggregation**; everything else
moves to its owning module or a dedicated public-API module.

```
src/
    main.zig        // ~30–50 lines: entry point + comptime test block
    miranda.zig     // the public namespace, if a public API is wanted
    runtime/ compiler/ parser/ driver/ io/
```

### Priority 1 — Reduce the responsibilities of `main.zig`
Shrink it to entry point + test aggregation. Everything else moves out gradually.

### Priority 2 — Replace the giant re-export layer
Today: `pub const foo = module.foo;` × hundreds. Prefer callers using the namespace
directly — `startup.readRc(...)` / `runtime.heap.cons(...)` instead of
`main.readRc(...)`. Keep only re-exports that are genuinely the intended public API.

### Priority 3 — Remove transitional duplicate imports ✅ done
`const repl = …;` next to `const r7_repl = …;` (and `r7_types`, `r7_lex`, …). After
migration: one import, no duplicates, **drop the `r7_` prefixes** (measured: **~190
`r7_*` uses**). *(= Readability rec R5.)*
**Done:** all `r7_*` aliases removed; duplicate imports (`r7_word`/`r7_heap`) merged
into the existing import; ambiguous `r7_reduce` split into `engine` (the reducer
engine) and `reduce_rt` (the runtime reduce support) where the plain name was taken.

### Priority 4 — Introduce stronger domain types ✅ done
Replace raw-integer codes with enums:
```zig
pub const Tag = enum(u8) { ap = 9, cons = 11, ... };
```
Gains: type safety, exhaustive `switch`, autocomplete, clearer signatures. (The
`NodeTag` enum already exists beside the raw tag consts — migrate reads onto it and
retire the raw duplicates.) *(= Readability recs R3, R4.)*

### Priority 5 — Remove compatibility comments
A doc that says *"Re-export of `repl.evaluateRepl`"* documents the *mechanism*, not
the intent. Where a re-export must stay, document **behaviour** ("Evaluate a REPL
expression and print the result."); where Priority 2 removes the re-export, the
comment goes with it. *(Note: the current `///` re-export comments were added to
reach autodoc completeness — they are placeholders to be replaced by intent-level
docs or removed alongside their aliases.)*

### Priority 6 — Reduce section headers
Many `// Heap accessors` / `// Interactive helpers` grouping comments signal a file
that has grown too large. Move related declarations into their own module and let
the module boundary express the structure.

### Priority 7 — Shrink the public-API surface
Every exported symbol should satisfy one of: intended external API · shared project
API · a still-required compatibility shim. Everything else becomes module-local.

### Priority 8 — Keep typed wrappers *(continue — already good)*
`NodeRef`, `Identifier`, `FileNode`, `TypeRef`. Keep replacing raw `Word` handles
with typed wrappers; avoid new APIs that expose raw `Word`. *(= Readability rec R4.)*

### Priority 9 — Keep small inline helpers *(continue)*
`get_id()`, `get_fil()` and friends are preferable to C macros — keep the pattern.

### Priority 10 — Improve module layout
Target the tree above; `main.zig` ≈ 30–50 lines; `miranda.zig` becomes the public
namespace.

### Priority 11 — Documentation *(continue)*
`//!` module docs + `///` declaration docs. Good comments explain purpose,
invariants, ownership, and contracts — not the implementation. Avoid boilerplate.

### Priority 12 — Tests *(continue)*
Keep tests adjacent to the code they verify (`test "reduce/basic"` beside
`reduce`); avoid collecting unrelated tests at the bottom of large files. *(The
[TESTABILITY_PLAN](TESTABILITY_PLAN.md) convention; `reduce_test.zig`/
`parser_tests.zig` are the grandfathered exceptions.)*

---

# Part B — Readability recommendations (whole tree)

These complement Part A; the ones already implied by a Priority are cross-linked.
Each is behaviour-preserving and golden-gated.

| # | Recommendation | Evidence | Maps to |
|---|----------------|----------|---------|
| **R1** ✅ | **Collapse the `reduce.zig` ↔ `reduce_core.zig` duplication** — have the engine import the primitives instead of copying them. **Done:** 60 duplicated primitives in reduce.zig replaced with `pub const X = core.X;` re-exports (bodies verified identical / alias-name-only diffs); reduce.zig ~900 → 414 lines. | **57 primitives** duplicated "in lock-step" | — (new) |
| **R2** ✅ | **Finish snake_case → camelCase in the reducer** (`hd_get`→`hdGet`, `tl_set`, `rewrite_to_*`, `is_*`, `get_id`, `force_dbl`). **Done:** 37 helpers renamed tree-wide (~900 call sites). | ~40 names, in both reducer files | end state: "no migration-era naming" |
| **R3** ◑ | **One source of truth for core constants** — import `NIL`/`CMBASE`/tag codes from `word.zig`; delete the local copies. **Done (partial):** tag codes (via P4) + value-verified CMBASE/CONST/atom-constants/type-codes in big/lex/codegen/trans aliased to `word.*`. **Left:** broader atom-constant copies in other files; the two intentionally-decoupled state modules; the `algebraic_t`/`abstract_t`/`placeholder_t` numbering discrepancy (flagged as a separate bug — do NOT blind-merge). | **21 files** re-declare them | P4 |
| **R4** ✅ | **Return `bool` from predicates** instead of `c_int` (1/0). **Done:** the boolean predicates converted — isChar, isNat, isconstrname, okid/okulid/okpath (+ retyped the `kollect` higher-order helper), ispoly, nonGeneric, occurs, utf8test, okdump, badEditor, peekdig, nclchk. Three-valued functions (cmp/compare/sign/memclass) and the C-ABI `c_int` fns (strcmp/system/…) are correctly left `c_int`. | **65 `c_int`-returning fns** | P4, P8 |
| **R5** ✅ | **Drop the `r7_` import prefixes.** *(done in Part A / Priority 3)* | ~190 uses | **P3** |
| **R6** ✅ | **Trim the `main.*` god-namespace**; migrate call sites to the owning module. *(done in Part A)* | ~108 re-exports | **P1/P2/P7** |
| **R7** ◑ | **Rename cryptic numbered/register helpers.** **Done:** the out-printers renamed (out→outTerm, out1→outSubterm, out2→outAtom, outr→outReal). **Decided against:** renaming `ReductionCtx` fields `e`/`s`/`hold` (351 `ctx.e` uses, `.e` a hazardous sed target, and they're graph-reduction idiom) — instead added per-field doc comments (the "document the convention" path the plan endorses for `h`/`t`/`hp`/`tp`). | — | P6-adjacent |
| **R8** ✅ | **Replace the per-file `abi` shim structs.** **Done:** types.zig's 126-member shim (3 used) and trans.zig's 5-member shim (2 used) deleted; call sites point at `main_clib.*`/`word.*` directly (~130 dead lines removed). | `types.zig` (124), `trans.zig`, … | P3-adjacent |
| **R9** ◑ | **Break up the longest functions** into named steps. **Done (demonstrated):** `command()` 382 → 219 lines (extracted `cmdEdit`/`cmdFiles`). **Left:** `handleReadyState` (813), `etype` (608), `mainEntry` (412), `yylex` (343), `loadfile` (331), `reduce` (213) — each shares heavy local/register state, so each needs an individual, carefully-validated extraction. | — | "smaller modules", P12 |
| **R10** ⏳ | **Standardize the error channel** — unify the `MiraError` union, the `SYNERR`/`errs` sentinels, and `return NIL`-as-failure onto error unions. **Deliberately deferred** (see plan below): error *recovery* runs through **13 `setjmp`/`siglongjmp` sites** (`siglongjmp(&rs.env, 1)` for SIGINT/SIGFPE/syntax-error recovery), which do not map onto Zig error unions without dismantling the non-local recovery model. The 44-case golden corpus exercises error/recovery paths only sparsely, so this change cannot be safely validated the way the rest of Part B was. It warrants its own designed, reviewed change. | 3 coexisting styles | — (design-bearing) |

## Sequencing

* **Quick wins (mechanical, byte-identical):** R5 ✅, R3 ◑, R2 ✅.
* **Structural (incremental, per-module):** R1 ✅, R6/Part A ✅, R8 ✅, R4 ✅.
* **Judgment / design-bearing (do thoughtfully, last):** R7 ◑, R9 ◑, R10 ⏳, P4 ✅.

**Status:** Part A complete; Part B R1/R2/R4/R5/R6/R8 done, R3/R7/R9 partial, R10
deferred (below). Every landed step kept the unit suite (157 tests), the golden
corpus (44 byte-identical), and `zig build lint` green.

## R10 — concrete plan (the deferred error-model unification)

The interpreter currently mixes three error styles:
1. **Zig error unions** (`MiraError!T`) — already used in ~7 type-checker functions.
2. **Sentinel globals** — `SYNERR` token + `core_state.s.errs` (the offending
   node) + `acterror()`, used by the parser/compiler for syntax errors.
3. **`return NIL`-as-failure** — scattered through the graph code.
…and recovery is **non-local** via `siglongjmp(&rs.env, 1)` (13 sites: SIGINT,
SIGFPE, and the syntax-error `acterror` path all jump back to the REPL `setjmp`).

A safe migration, in order:
* **Step 1 (no behaviour change):** wrap the sentinel reads/writes behind named
  helpers (`raiseSyntaxError(node)`, `currentErrorNode()`) so the channel has one
  API before changing its mechanism. Unit-test those.
* **Step 2:** convert the `return NIL`-as-failure leaf functions (no recovery
  involved) to `MiraError!Word`, propagating `try` up to the nearest existing
  sentinel/longjmp boundary. These are individually golden-checkable.
* **Step 3 (design decision, needs review):** decide the recovery model. Either
  (a) **keep `setjmp`/`longjmp`** for signal + top-level REPL recovery (it is the
  C-port's deliberate model and is hard to beat for "abort this evaluation, return
  to prompt"), and only unify the *non-recovery* error reporting onto error unions;
  or (b) replace longjmp with error propagation end-to-end (large; must re-prove
  signal-safety and that partial heap mutations are unwound correctly).
* **Validation:** add golden/integration cases that actually exercise the error
  paths (syntax error mid-script, SIGINT during reduction, divide-by-zero) before
  touching the mechanism — today's corpus does not cover them.

Recommended: do Steps 1–2 (safe, incremental) in a dedicated PR; treat Step 3 as a
separate design proposal. Until then R10 stays open.

---

# Desired end state

The project resembles a native Zig project, not a translated C project:

* small modules · minimal compatibility layers · explicit namespaces · strong types
* little or no API flattening · a concise public API
* documentation focused on semantics, not implementation mechanics
* no duplicated imports · no migration-era naming (`r7_`, snake_case)
* `main.zig` ≈ 30–50 lines; `miranda.zig` the public namespace

**Behaviour remains unchanged throughout** — verified by the golden corpus, the
unit suite, and the integration suite at every commit.
