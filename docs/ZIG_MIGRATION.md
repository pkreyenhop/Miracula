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
│  Phase 5: Zig Parser     │  ◄── Next Phase: Replace yacc rules.y with pure Zig parser
└─────────────┬────────────┘
              │
              ▼
┌──────────────────────────┐
│  Phase 6: Pure Zig       │  ◄── Final Phase: Remove libc linking entirely
└──────────────────────────┘
```

### Phase 5: Pure Zig Parser
* **Goal**: Replace the legacy yacc-based grammar compiler (`rules.y`, `y.tab.c`, `y.tab.h`) with a hand-written or parser-combinator-based pure Zig parser.
* **Impact**: Will allow removing the Berkeley yacc (`byacc`) build tool dependency and clean up all remaining `@cInclude` references to macro-coupled C headers in the compiler modules.

### Phase 6: Pure Zig Implementation
* **Goal**: Fully eliminate C code from the project.
* **Impact**: The executable can be compiled without linking the C standard library (`exe.linkLibC()`), resulting in a completely portable, static, pure-Zig binary.
