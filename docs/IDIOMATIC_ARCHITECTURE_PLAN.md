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

### Priority 3 — Remove transitional duplicate imports
`const repl = …;` next to `const r7_repl = …;` (and `r7_types`, `r7_lex`, …). After
migration: one import, no duplicates, **drop the `r7_` prefixes** (measured: **~190
`r7_*` uses**). *(= Readability rec R5.)*

### Priority 4 — Introduce stronger domain types
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
| **R1** | **Collapse the `reduce.zig` ↔ `reduce_core.zig` duplication** — have the engine import the primitives instead of copying them. | **57 primitives** duplicated "in lock-step" | — (new) |
| **R2** | **Finish snake_case → camelCase in the reducer** (`hd_get`→`hdGet`, `tl_set`, `rewrite_to_*`, `is_*`, `get_id`, `force_dbl`). | ~40 names, in both reducer files | end state: "no migration-era naming" |
| **R3** | **One source of truth for core constants** — import `NIL`/`CMBASE`/tag codes from `word.zig`; delete the local copies. | **21 files** re-declare them | P4 |
| **R4** | **Return `bool` from predicates** instead of `c_int` (1/0): `isChar`, `isconstrname`, `isNat`, `member`, `same`, `okid`, … | **65 `c_int`-returning fns** | P4, P8 |
| **R5** | **Drop the `r7_` import prefixes.** | ~190 uses | **P3** |
| **R6** | **Trim the `main.*` god-namespace**; migrate call sites to the owning module. | ~108 re-exports | **P1/P2/P7** |
| **R7** | **Rename cryptic numbered/register helpers** — `out`/`out1`/`out2`/`outr`/`outf` → `outTerm`/`outSubterm`/…; `ReductionCtx` fields `e`/`s`/`hold` → `focus`/`spine`/`scratch`. (Keep the Miranda-idiom `h`/`t`/`hp`/`tp`; document the convention once.) | — | P6-adjacent |
| **R8** | **Replace the per-file `abi` shim structs** (`const abi = struct { pub const printf = … }`) with one shared C-surface module or direct imports. | `types.zig` (124), `trans.zig`, … | P3-adjacent |
| **R9** | **Break up the longest functions** — `reduce()` (~220 lines), `codegen`, `yylex`, `block`, `mkshow`, `loadDefs`, `mainEntry` — into named steps (each then unit-testable). | — | "smaller modules", P12 |
| **R10** | **Standardize the error channel** — unify the `MiraError` union, the `SYNERR`/`errs` sentinels, and `return NIL`-as-failure onto error unions (plan item J1). | 3 coexisting styles | — (design-bearing) |

## Sequencing

* **Quick wins (mechanical, byte-identical):** R5 (`r7_` prefixes), R3 (constant
  de-dup), R2 (reducer rename).
* **Structural (incremental, per-module):** R1 (reducer de-dup), R6/Part A P1–P2–P7
  (dissolve `main.*`), R8 (shared C surface), R4 (`bool` predicates).
* **Judgment / design-bearing (do thoughtfully, last):** R7 (renames), R9 (function
  splitting), R10 / J1 (error model), P4 (`Tag` enum migration).

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
