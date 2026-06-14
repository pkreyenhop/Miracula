# Zig Migration Progress & Roadmap

This document outlines the history, completed milestones, and future plans for the C-to-Zig migration of the Miranda interpreter (`mira`).

---

## Completed Milestones

### ✔ Phase 1: Standalone Utilities & Leaf Helpers Migration
* Ported all standalone utilities (`fdate`, `just`, and `menudriver`) to Zig.
* Ported C leaf utility functions (UTF-8 transcoding, signal handling, and version info) to Zig modules (`utf8.zig`, `signals.zig`, `version.zig`).

### ✔ Phase 2: Runtime & Compiler Core Migration
* Ported the graph reduction engine, combinator execution rules, and arbitrary-precision bigint math to Zig (`reduce.zig`, `combinator.zig`, `big.zig`).
* Ported the compiler typechecker and bracket abstraction translator to Zig (`types.zig`, `trans.zig`).
* Ported the cell allocation heap and conservative stack-scanning garbage collector to Zig (`heap.zig`).
* Successfully resolved all heap corruption bugs and verified identical runtime reduction behavior.

### ✔ Phase 3: Project Modularization & Unified Build
* Reorganized the flat source layout into a structured, modular tree (`src/runtime/`, `src/compiler/`, `src/parser/`, `src/io/`).
* Replaced all historical Makefile wrappers and shell build scripts with a unified `build.zig`.
* Set up automated golden-ratio regressions and integration test gates.

### ✔ Phase 4: libc Reduction & Cross-Compilation Support
* Conducted a thorough audit of all C library dependencies in `docs/LIBC_AUDIT.md`.
* Removed C library imports (`@cImport` and C headers) from `utf8.zig`, `signals.zig`, and `big.zig`.
* Implemented a target-conditional platform abstraction layer in `platform.zig` to handle Linux/macOS file info operations (`statx` vs `stat`), thread-local error variables, and permissions.
* Configured test compilation targets in `build.zig` to resolve all linker errors, verifying clean cross-compilation for both **Intel 64-bit Linux** (`x86_64-linux`) and **Apple Silicon macOS** (`aarch64-macos`).

---

## Future Roadmap

```text
┌──────────────────────────┐
│  Phase 5: Zig Parser     │  ◄── IN PROGRESS — see docs/PARSER_MIGRATION.md
└─────────────┬────────────┘
              │
              ▼
┌──────────────────────────┐
│  Phase 6: Pure Zig       │  ◄── Final Phase: Remove libc linking entirely
└──────────────────────────┘
```

### Phase 5: Pure Zig Parser (in progress)

**Goal**: Replace the legacy yacc-based grammar compiler (`rules.y`, `y.tab.c`, `y.tab.h`) with a handwritten recursive-descent + Pratt parser pipeline in Zig.

**Detailed plan**: see [`docs/PARSER_MIGRATION_PLAN.md`](PARSER_MIGRATION_PLAN.md).

**Completed sub-phases:**
* `token_filter.zig` — full `TokenId` enum, `Token` / `Span` structs (106 lines, compiles clean)
* `ast.zig` — all AST node types: `TypeExpr`, `Expr`, `Pat`, `Def`, `TypeDecl`, `Script` (153 lines)
* `pratt.zig` — Pratt expression parser with Miranda operator-precedence table (427 lines)
* `parser.zig` — recursive-descent parser covering the core grammar (537 lines)
* `build.zig` updated — `parser-tests` binary wired into `test` and `check` steps
* `zig build` and `zig build test` both exit 0

**Remaining sub-phases:**
* Phase 7 — Lexer bridge: connect `lex.zig` output to the new `TokenStream`
* Phase 8 — Codegen: walk `ast.Script` and emit Miranda `Word` heap values
* Phase 9 — Grammar completeness: list comprehensions, sections, abstype…with, module directives
* Phase 10 — Integration: wire new parser into `main.zig` behind a build flag
* Phase 11 — Removal: delete legacy parser files once `mira-tests` passes 100%

**Impact**: Removes the Berkeley yacc (`byacc`) build tool dependency and all `@cInclude` references to macro-coupled C headers in the parser subsystem.

### Phase 6: Pure Zig Implementation
* **Goal**: Fully eliminate C code from the project.
* **Impact**: The executable can be compiled without linking the C standard library (`exe.linkLibC()`), resulting in a completely portable, static, pure-Zig binary.
