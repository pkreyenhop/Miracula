# Error-set correspondence — Zig `error{}` → Go

Part of [GO_MIGRATION.md](GO_MIGRATION.md) Phase 0 (§5.5). 5 Zig error sets,
measured 2026-07-13.

Per [GO_MIGRATION.md §5.5](GO_MIGRATION.md)'s recommendation, each error set
becomes a small custom Go type implementing `error`, carrying a `Kind` field
— not bare sentinel `var Err... = errors.New(...)` values — because it
directly continues the structured-`Diagnostics` work ZIG_NATIVE_PLAN's Phase
2 already did (span + message, not a printed side effect plus a flag), and
`errors.As`/a `Kind()` accessor gives back the exhaustive `switch (err)`
behaviour Zig callers rely on today.

## Common shape

```go
type MiraErrorKind int

const (
    SyntaxError MiraErrorKind = iota
    TypeCheckAbort
    HeapExhausted
    LoadError
    EvaluationInterrupted
)

type MiraError struct {
    Kind    MiraErrorKind
    Span    Span   // zero value when not applicable
    Message string // present when the error carries a formatted diagnostic
}

func (e *MiraError) Error() string { return e.Message }
```

Each of the 5 sets below gets its own `Kind` enum and wrapper type, following
this shape, in its own destination package (not one giant shared error type —
that would recreate the single-`MiraError`-set-does-everything shape the Zig
side deliberately split into 5 narrower sets for cycle/ownership reasons; the
Go port should keep that split for the same reasons: `word.ReduceError` lives
in `graph/` and must not import `session/`, e.g.).

## The 5 sets

### 1. `graph/word.zig`'s `ReduceError` (2 members)

```zig
pub const ReduceError = error{ Interrupted, FloatOverflow };
```

- **Why it exists separately** (per its own doc comment): `heap.zig` needs to
  return this from `stoDbl`/`setdbl` without importing the reducer back (an
  import-cycle constraint) — the narrowest possible error set for the
  narrowest possible reason.
- **Go home:** `graph` package (matches the Zig home — this is a `graph`-leaf
  concern, confirmed by the existing cycle-avoidance comment itself).
- **Go form:** `type ReduceErrorKind int` with `Interrupted`/`FloatOverflow`;
  `type ReduceError struct { Kind ReduceErrorKind }`. No message/span payload
  needed — neither Zig variant carries one today (both are checked via
  `switch (err)` at the catch site, which prints its own fixed text).
- **Call-site pattern today:** `try stoDbl(...)` / `catch |err| switch (err)
  {...}` → Go `v, err := StoDbl(...); if err != nil { switch err.(*ReduceError).Kind { ... } }`.

### 2. `runtime/errors.zig`'s `MiraError` (5 members)

```zig
pub const MiraError = error{
    SyntaxError,
    TypeCheckAbort,
    HeapExhausted,
    LoadError,
    EvaluationInterrupted,
};
```

- **Note (from the set's own doc comment):** `EvaluationInterrupted` is
  already a documented **unused placeholder** in the Zig source — reserved
  for compiler error-union work that Phase 3 step 5 never landed. Confirm at
  port time whether it's still unused; if so, **do not port it** — an unused
  enum member in Go trips `unused` lint concerns less than Zig, but there's
  no reason to carry dead surface across a rewrite. Recheck this row's status
  in [ZIG_NATIVE_PLAN.md](ZIG_NATIVE_PLAN.md) before the real port.
- **Go home:** `session` package (this is the interpreter's broadest
  domain-error set, used across command-line/startup/load paths per its own
  doc comment — matches `runtime/errors.zig`'s eventual fold into `session/`
  per [GO_MIGRATION.md Phase 2](GO_MIGRATION.md)).
- **Go form:** `MiraErrorKind` + `MiraError{Kind, Message}` per the common
  shape above — this set's variants are exactly the ones that already carry
  "the error message has already been printed" semantics (see each
  variant's doc comment in the Zig source), so `Message` should hold that
  same text for callers that want it (e.g. logging), even though the
  original Zig print already happened at the point of return.
- **`fatal()` itself:** not an error-set member, a `noreturn` print-then-exit
  helper — see [GO_ANYTYPE_INVENTORY.md](GO_ANYTYPE_INVENTORY.md) Category A,
  already resolved there.

### 3. `semantics/modules.zig`'s `ModuleError` (2 members)

```zig
pub const ModuleError = error{
    IncludeCycle,
    IncludeCompileFailed,
};
```

- **Go home:** `semantics` package (matches `%include` cycle-detection /
  compilation living in `modules.go` per the existing Zig home and the
  target tree in ZIG_NATIVE_PLAN §4.1).
- **Go form:** `ModuleErrorKind` + `ModuleError{Kind, Path string}` — add a
  `Path` field (not in the Zig set's bare error variant, but every real call
  site needs to report *which* file cycled or failed; confirm during port
  whether the Zig side already threads the path through a wrapping
  `MiraError`/print call adjacent to the `return error.IncludeCycle`, and
  fold that into the struct rather than leaving it implicit).

### 4. `parser/parser_api.zig`'s `ParseError` (2 members)

```zig
pub const ParseError = error{
    SyntaxError,
    ParseFailed,
};
```

- **Naming collision, flagged:** this set's `SyntaxError` member and
  `MiraError`'s `SyntaxError` member are **different types today** (Zig
  error sets are structurally distinct even with the same member name — no
  collision in Zig). Go has no equivalent implicit disambiguation: two
  `Kind` constants named `SyntaxError` in two different `Kind` enums in two
  different packages are fine (`session.SyntaxError` vs. `parser.SyntaxError`
  read unambiguously), but a single shared untyped constant name across
  packages would not be. Since each set gets its own `XxxKind` enum type
  per this document's common shape, this resolves itself automatically —
  flagged here so the choice not to unify these two `SyntaxError`s into one
  type is understood as deliberate, not an oversight.
- **Go home:** `semantics` package (per [GO_MIGRATION.md Phase
  2](GO_MIGRATION.md), `parser/parser_api.zig` folds into `semantics/lower.zig`'s
  territory — confirm exact destination file once Phase 2 lands, since
  `parser_api.zig` is itself mid-consolidation).
- **Go form:** `ParseErrorKind` + `ParseError{Kind, Span}` per common shape.

### 5. `syntax/pratt.zig`'s `ParseError` (3 members)

```zig
pub const ParseError = error{ UnexpectedToken, UnexpectedEof, OutOfMemory };
```

- **`OutOfMemory` is the interesting member:** in Zig this is
  `std.mem.Allocator.Error`, folded into this set because the Pratt parser's
  AST allocation can fail. Per [GO_MIGRATION.md §5.7](GO_MIGRATION.md)
  (drop explicit allocator threading — Go's GC/allocator doesn't expose
  `OutOfMemory` as a recoverable error the way Zig's explicit allocators do;
  a Go allocation failure is an unrecoverable runtime panic, not a returned
  error). **Resolution: do not port this member.** The Go `ParseError`
  set for this file has 2 members, not 3 — `UnexpectedToken`,
  `UnexpectedEof` only. This is the first concrete instance of §5.7's
  general "allocator plumbing disappears at translation time" principle
  actually removing an error-set member, not just a function parameter —
  worth having found during this inventory rather than during the port.
- **Go home:** `syntax` package (matches the Zig home exactly).
- **Go form:** `ParseErrorKind` (2 members) + `ParseError{Kind, Span}`.
  **Naming note:** this is the *second* `ParseError` type in the inventory
  (see #4) — since each lives in its own Go package (`syntax` vs.
  `semantics`), `syntax.ParseError` and `semantics.ParseError` are
  unambiguous at call sites, matching how Zig's two same-named error sets
  already coexist today without collision.

## Summary

| # | Zig set | Members | Go package | Members dropped/added |
| --- | --- | ---: | --- | --- |
| 1 | `word.ReduceError` | 2 | `graph` | none |
| 2 | `errors.MiraError` | 5 | `session` | `EvaluationInterrupted` — confirm still unused, drop if so |
| 3 | `modules.ModuleError` | 2 | `semantics` | add `Path string` field (not a member, a payload field) |
| 4 | `parser_api.ParseError` | 2 | `semantics` (pending Phase 2 consolidation) | none |
| 5 | `pratt.ParseError` | 3 | `syntax` | `OutOfMemory` dropped — no Go equivalent once allocator threading is dropped per §5.7 |

All 5 sets have a closed Go destination, shape, and member list. No open
decisions remain for this table; re-verify member 2's `EvaluationInterrupted`
status against the then-current `runtime/errors.zig` immediately before the
real port starts, since it was already flagged as possibly-stale at the time
of this writing.
