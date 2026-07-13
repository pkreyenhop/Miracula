# `union(enum)` inventory — Go representation per site

Part of [GO_MIGRATION.md](GO_MIGRATION.md) Phase 0 (§5.3). 15 sites, measured
2026-07-13.

[GO_MIGRATION.md §5.3](GO_MIGRATION.md) recommended one canonical pattern
("tagged struct, not interface-per-variant") for hot-path types. Looking at
all 15 sites individually, that recommendation holds for the reducer's value
types but is **wrong for the AST** — Go's own standard library (`go/ast`)
represents a heterogeneous tree exactly the way this codebase's `Expr`/`Pat`/
`TypeExpr` already do (a node holding `*Expr`/`*Pat` children), via an
**interface implemented by one concrete struct per variant**, not a tagged
struct. The AST is cold (built once per script, walked a handful of times,
never touched by the reduction hot loop), so the allocation + dynamic-dispatch
cost the hot-path recommendation exists to avoid doesn't apply. Two patterns,
chosen by the same test used everywhere else in this plan: does this type
appear in the reduction hot path?

## Pattern 1 — tagged struct (hot path / fixed-width payloads)

A `Kind`/tag field plus a struct wide enough for every variant's payload.
Preserves bit-for-bit layout and avoids per-value heap allocation.

| Site | Payload shape | Go form |
| --- | --- | --- |
| `graph/value.zig:102` `Kind` (`imm: u8`, `comb: Comb`, `cell: CellRef`) | 3 small scalars | `type Kind struct { Tag KindTag; Imm uint8; Comb Comb; Cell CellRef }` — the reducer's hottest classification type, runs on every reduction step |
| `graph/word.zig:138` `Value` (`imm: u8`, `atom: Word`, `ref: Ref`) | 3 small scalars | **not ported** — this is the pre-Phase-5 `classify()` seam that `graph/value.zig`'s `Kind` above supersedes (per ZIG_NATIVE_PLAN §4.3, "the existing `Ref`/`classify()` seam is the embryo of this and is absorbed by it"). Expected to be deleted once [GO_MIGRATION.md Phase 1](GO_MIGRATION.md) finishes retyping onto `Value`/`Kind` — re-check this row is gone (not just superseded) before the real port starts |
| `syntax/lexer.zig:497` `EscapeErrorKind` (7 no-payload variants + `unrecognised_escape: u8`) | tiny enum, one with a byte payload | `type EscapeErrorKind struct { Tag EscapeErrorTag; Byte uint8 }` — small and scanned once per escape sequence; tagged struct is simpler than an interface here even though it's not hot-path, since every variant but one carries zero payload |
| `syntax/lexer.zig:509` `Escape` (`char: u21`, `elided`, `err: EscapeErrorKind`) | one rune or the error above | `type Escape struct { Tag EscapeTag; Char rune; Err EscapeErrorKind }` — same reasoning, pairs with the row above |

## Pattern 2 — interface + one concrete struct per variant (cold, tree-shaped AST)

Matches `go/ast`'s own convention. Each variant becomes a named struct
implementing a marker method; fields that were `*TypeExpr`/`*Expr`/`*Pat`
children become the interface type directly (no pointer needed — Go
interface values are already reference-shaped).

| Site | Variant count | Notes |
| --- | ---: | --- |
| `syntax/ast.zig:12` `TypeExpr` | 7 (`type_var`, `type_name`, `arrow`, `type_app`, `tuple`, `list`, `void_t`) | `type TypeExpr interface { isTypeExpr() }`; `TypeVar`, `TypeName`, `Arrow{From, To TypeExpr}`, `TypeApp{Func TypeExpr; Args []TypeExpr}`, `TupleType([]TypeExpr)`, `ListType{Elem TypeExpr}`, `VoidType{}` |
| `syntax/ast.zig:35` `Literal` | 4 (`int`, `float`, `string`, `char`) | `type Literal interface { isLiteral() }`; `IntLit(string)` (keeps source digits, per the existing comment — bignum built later), `FloatLit(float64)`, `StringLit(string)`, `CharLit(rune)` |
| `syntax/ast.zig:47` `Qualifier` | 3 (`generator`, `sequence_generator`, `guard`) | `type Qualifier interface { isQualifier() }`; `Generator{Pat Pat; Source Expr}`, `SequenceGenerator{Pat Pat; Source, Step Expr}`, `Guard{Pred Expr}` |
| `syntax/ast.zig:57` `Expr` | 18 variants | `type Expr interface { isExpr() }`; one struct per variant (`Name`, `CName`, `LiteralExpr`, `Application`, `Infix`, `Neg`, `Length`, `ListNil`, `ListExpr`, `TupleExpr`, `Typed`, `Where`, `Cond`, `SectionRight`, `SectionLeft`, `OpFunc`, `Range`, `ListComp`) — the largest single translation unit in the AST, but each variant is a direct field-for-field struct, no logic |
| `syntax/ast.zig:99` `Pat` | 8 (`wildcard`, `name`, `cname`, `literal`, `cons_pat`, `list`, `tuple`, `application`) | `type Pat interface { isPat() }`; mirrors `Expr`'s pattern |
| `syntax/ast.zig:128` `Rhs` | 2 (`expr`, `guarded`) | `type Rhs interface { isRhs() }`; `ExprRhs(Expr)`, `GuardedRhs([]Guard)` — `Guard` itself is already a plain struct (not a union), no change needed |
| `syntax/ast.zig:163` `TypeDecl` | 3 (`synonym`, `algebraic`, `abstype`) | `type TypeDecl interface { isTypeDecl() }`; `Synonym`, `Algebraic`, `Abstype` structs |
| `syntax/ast.zig:190` `TopLevel` | 6 (`definition`, `type_spec`, `type_decl`, `eval`, `include`/`export_list`/`free_directive` legacy-bridge shapes, `directive`) | `type TopLevel interface { isTopLevel() }`; **note the 3 legacy-bridge variants (`include`, `export_list`, `free_directive`) are dead weight already flagged in ZIG_NATIVE_PLAN's Phase 1 step 5 corrections as superseded by the native `.directive` variant** — confirm during Phase 2 (directory consolidation) of GO_MIGRATION.md whether they're deletable in Zig *before* porting, so the Go port doesn't need to carry three unused struct types |
| `syntax/token_filter.zig:157` `DirectiveAlias` | 2 (`rename`, `suppress`) | `type DirectiveAlias interface { isDirectiveAlias() }`; `Rename{New, Old string}`, `Suppress(string)` |
| `syntax/token_filter.zig:181` `Directive` | 5 (`include`, `export_list`, `free`, `unsupported`, `unknown`) | `type Directive interface { isDirective() }`; note the existing `deinit(gpa)` method (frees `.include`'s `aliases` slice) has no Go equivalent to port — Go's GC reclaims it, delete the method rather than translate it (§5.7's allocator-dropping principle applies to explicit frees too) |
| `semantics/modules.zig:50` `ExportPart` | 4 (`all`, `name`, `exclude`, `file`) | `type ExportPart interface { isExportPart() }`; `AllExports{}`, `NamedExport(string)`, `ExcludedExport(string)`, `FileExport(string)` |

## Decision record

- **Two patterns, chosen by hot-path-or-not**, not one universal rule as
  originally drafted in GO_MIGRATION.md §5.3 — that section should be updated
  to point here rather than restate "always tagged struct."
- Every `isXxx()` marker method is a zero-cost empty method, matching
  `go/ast`'s own `exprNode()`/`stmtNode()` convention — chosen for
  consistency with an existing, well-known Go idiom rather than invented
  fresh.
- `graph/word.zig:138`'s `Value` union is the only site with an open
  precondition (must confirm deletion, not just supersession, before the
  real port) — every other row is a closed decision.
