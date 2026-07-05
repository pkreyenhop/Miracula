# Zig Migration Progress & Roadmap

This document outlines the history, completed milestones, target platform support, and technical implementation details for the C-to-Zig migration of the Miranda interpreter (`mira`).

---

## 📋 Completed Milestones

### ✔ Phase 1: Standalone Utilities & Leaf Helpers Migration
* Ported all standalone utilities (`fdate`, `just`, and `menudriver`) to Zig.
* Ported C leaf utility functions (UTF-8 transcoding, signal handling, and version info) to Zig modules (`utf8.zig`, `signals.zig`, `src/runtime/version.zig`).

### ✔ Phase 2: Runtime & Compiler Core Migration
* Ported the graph reduction engine, combinator execution rules, and arbitrary-precision bigint math to Zig (`reduce.zig`, `combinator.zig`, `big.zig`).
* Ported the compiler typechecker and bracket abstraction translator to Zig (`types.zig`, `trans.zig`).
* Ported the cell allocation heap and conservative stack-scanning garbage collector to Zig (`heap.zig`).
* Successfully resolved all heap corruption bugs and verified identical runtime reduction behavior.

### ✔ Phase 3: Project Modularization & Unified Build
* Reorganized the flat source layout into a structured, modular tree (`src/runtime/`, `src/compiler/`, `src/parser/`, `src/io/`).
* Replaced all historical Makefile wrappers and shell build scripts with a unified `build.zig`.
* Set up automated golden-ratio regressions and integration test gates.

### ✔ Phase 4: libc Reduction & Portability Baseline
* Conducted a thorough audit of all C library dependencies in `docs/LIBC_AUDIT.md`.
* Removed C library imports (`@cImport` and C headers) from `utf8.zig`, `signals.zig`, and `big.zig`.
* Implemented a target-conditional platform abstraction layer in `platform.zig` to handle Linux/macOS file info operations (`statx` vs `stat`), thread-local error variables, and permissions.

### ✔ Phase 5: Pure Zig Parser
* **Goal**: Replace the legacy yacc-based grammar compiler (`rules.y`, `y.tab.c`, `y.tab.h`) with a handwritten recursive-descent + Pratt parser pipeline in Zig.
* **Outcome**: The new parser (`parser.zig`, `pratt.zig`, `ast.zig`, `codegen.zig`, `token_filter.zig`) has been fully integrated and performs end-to-end parsing of Miranda source code, emitting correct `Word` heap values. All legacy parser C source and header files have been removed from the active repository.

### ✔ Phase 6: Pure Zig Implementation & libc Removal
* **Goal**: Fully eliminate C code and remove standard C library dependencies (`exe.linkLibC()`) to enable building completely portable, static/native pure-Zig binaries.
  - All `@cImport` / `@cInclude` statements have been removed from the Zig source files.
  - A custom, pure-Zig C standard library shim was implemented in `src/runtime/main_clib.zig` to resolve standard Unix symbols (POSIX/file-io/string functions) directly against the OS.
  - Linked C math library `libm` has been entirely replaced with native `std.math` equivalents.
  - The build target `link_libc` has been disabled on macOS, where the OS linker implicitly links `libSystem.dylib`.
  - The binary successfully cross-compiles cleanly to statically linked ELF binaries on Linux (`x86_64-linux-musl`), dynamically linked ELF binaries on glibc-based Linux (`x86_64-linux-gnu`), and Mach-O binaries on macOS (`aarch64-macos`).
  - Fixed compilation of the C test harness and resolved linking issues for the test suite (`utf8-tests`) under cross-compilation target environments.

### ✔ Phase 7: Idiomatic Zig Modernization *(2026-06-21)*
* **Goal**: Refactor the codebase from a direct C translation to a native, idiomatic Zig codebase.
* **Outcome**: All 24 steps across clusters A–G are complete. (Full details were tracked in the since-retired `IDIOMATIC_ZIG_PLAN` document; see git history.)
  - **Cluster A** — Monolithic `main.zig` decomposed: extracted `commands.zig`, `setup.zig`, `module_loader.zig`, `dump.zig`, `files.zig`. `repl.zig`'s 57 `extern var` declarations replaced with `@import`. `main.zig` reduced to ~267 lines (composition root + 8 C-ABI-constrained export vars).
  - **Cluster B** — `RuntimeState` struct introduced in `src/runtime/runtime_state.zig`; ~75 global variables consolidated into a single `pub var rs`. Heap array accessors (`h`/`t`/`hp`/`tp`) no longer re-exported from `main.zig`.
  - **Cluster C** — `NodeTag` non-exhaustive enum added. `FileNode`, `Identifier`, `TypeRef`, `NodeRef` domain types added as typed wrappers over heap `Word` values.
  - **Cluster D** — Internal string parameters converted from `[*:0]` to `[:0]` at appropriate boundaries. Domain type methods added. `///` doc comments added to all public API functions.
  - **Cluster E** — `MiraError` error set defined. `gc()` local setjmp/longjmp removed (was a masked `return`). `types.zig` type-checker abort chain converted to Zig error unions (`meta_tcheck`, `etype`, `conforms`, and 4 callers). Signal-handler `sigsetjmp`/`siglongjmp` paths documented as permanent (POSIX async constraint).
  - **Cluster F** — `extern var` eliminated from `types.zig` (10 vars) and reduced in `trans.zig` (10 of 14) and `module_loader.zig` (12 of 19). Stale `c_jmp` alias and pre-plan TODO blocks removed. 6 more `RuntimeState` boolean fields converted from `Word` to `bool`. Unit test count increased from 26 to 31.
  - **Cluster G** — `Module Graph Repair`: broke circular dependency between `heap.zig` and `main.zig` via `core_state.zig`, converted reducer handlers to direct calls, migrated `lex.zig` state to a `LexState` struct, and converted heap accessor `extern fn` calls to direct imports.

### ✔ Phase 8: Deep Idiomatic Zig & Code Modernization *(2026-06-21)*
* **Goal**: Eliminate remaining C-style patterns and platform assumptions to produce a fully native, type-safe, and standards-adhering Zig codebase.
* **Outcome**: Clusters H, I (I2), and K (K1, K3) complete. (Full details were tracked in the since-retired `IDIOMATIC_ZIG_PLAN` document; see git history.)
  - **Cluster H** — Compiler state encapsulated into `CompilerState` struct (`compiler_state.zig`). Key compiler functions (`type_of`, `checktypes`, `codegen`) converted from `clib.*` linker calls to direct `@import` aliases via `main.zig`. 20 FFI-private heap accessor `export` keywords removed.
  - **Cluster I (partial)** — `c_int` fields in `RuntimeState` and `CompilerState` converted to native `i32` where no C-ABI boundary is crossed.
  - **Cluster K (partial)** — `zig fmt` applied to entire codebase (K1). `///` doc comments added to `CompilerState` and `core_state.zig` exports (K3).

### ✔ Phase 9: Post-migration redesign — state, representation, GC, structure *(2026-06-23 – 2026-07-01)*
* **Goal**: With the C-to-Zig port itself complete (Phases 1–8), address the deeper
  representation and architecture questions the port had deliberately deferred: one
  aggregated state singleton instead of nine, string interning, the reduction engine's
  pointer-reversal encoding, the GC's sign-bit trick, the longest functions, and the
  error/recovery model. Tracked in the since-retired `REMAINING_WORK_PLAN` document, which
  consolidated and sequenced the open items originally spread across the
  `REDESIGN_DATA_MODEL`, `IDIOMATIC_ARCHITECTURE_PLAN`, and `SHARED_STATE_PLAN` documents
  (all retired; superseded by [ZIG_NATIVE_PLAN.md](ZIG_NATIVE_PLAN.md)).
* **Outcome**:
  - **State aggregation (SHARED_STATE Phases 1–4)** — every mutable interpreter state struct
    (`RuntimeState`, `Heap`, `LexState`, `CompilerState`, `CoreState`, `IoState`, `EvalState`,
    `Bignum`, `StringTable`) folded into one `Interp` singleton (`src/runtime/interp.zig`);
    `main.zig` dissolved to a ~80-line process entry point, its `main.<name>` re-export hub
    removed entirely (`IDIOMATIC_ARCHITECTURE_PLAN` Part A). Threading `*Interp` explicitly
    through the ~2,100 call sites (Phases 5–6) is deferred — large, and only needed for
    multi-instance use, which the current serial test model doesn't require.
  - **String interning (B1/R6)** — node-stored identifier/pathname strings moved from raw
    `[*:0]` pointers cast to `Word` to an interned `StrId` table (`strtab.zig`), deduplicating
    by content.
  - **The reduction spine (B2 option (b))** — replaced in-graph pointer reversal (which
    borrowed a cell's own `hd`/`tl` field to encode the return path, masking `& ~tlptrbits` on
    every hot-loop access) with an explicit `Spine` stack (`reducer/spine.zig`), registered as
    a precise GC root set. Found and fixed two real bugs during the cutover: a boundary-check
    semantic gap and a ~15x performance regression (fixed with a buffer pool).
  - **Tracing GC (B3/R5)** — replaced the sign-bit-on-tag-byte mark-sweep with a
    `std.DynamicBitSetUnmanaged` liveness bitmap and an explicit free list, making cell
    allocation O(1) instead of an O(n)-worst-case bump-scan, and making `NodeTag` a fully
    exhaustive enum.
  - **R9 function-splitting** — the six longest functions in the codebase (`reduce`,
    `loadfile`, `yylex`, `mainEntry`, `etype`, `handleReadyState`; up to 813 lines each)
    extracted into named steps, each independently golden-verified.
  - **Error/recovery-model decision (R10-Step 3 / A4b / J2)** — audited every
    `setjmp`/`longjmp` call site and confirmed all of them are signal-handler-triggered only;
    resolved the recovery-model question by technical necessity (`setjmp`/`longjmp` is
    permanent for SIGINT/SIGFPE recovery, not a stopgap awaiting a rewrite) rather than
    proceeding with a risky sentinel-unification refactor. See
    [ARCHITECTURE.md](ARCHITECTURE.md)'s "Key Invariants" section for the technical detail.
  - Along the way, found and flagged (not fixed, to keep each change independently
    reviewable) three pre-existing, unrelated bugs: a divide-by-zero in `-make`'s failure
    report on long file paths, a crash evaluating `system "..."` at the REPL prompt, and a
    dump-cache bug that silently masks a script's syntax error on a second, unchanged run.

### ⏳ Phase 10: Zig-Native Rearchitecture *(planned)*
* **Goal**: Stop incrementally polishing the C translation and rearchitect toward a
  program that could have been written Zig-first: one native front end (delete the C
  lexer), native I/O and structured diagnostics (delete the libc shim), a polled
  interrupt flag (delete `setjmp`/`longjmp` and fork-per-eval), an enforced module DAG
  with explicit ownership (delete the ambient singleton), and a typed value model
  (`Value`/`Comb`/`CellRef` instead of bare `Word`).
* **Plan**: [ZIG_NATIVE_PLAN.md](ZIG_NATIVE_PLAN.md) — supersedes all earlier plan
  documents. Note it deliberately re-opens two Phase 9 "resolved by necessity" decisions
  (the `setjmp`/`longjmp` recovery floor and the deferred `*Interp` threading).

---

## 💻 Target Platform Build Status

We verify cross-compilation and linking for both required target platforms:

| Target Platform | Compiler Build | Test Suite Build / Execution | Status |
| :--- | :--- | :--- | :--- |
| **Intel 64-bit Linux** (`x86_64-linux-gnu` / `musl`) | **Successful** (Static Musl / Dynamic Glibc) | Verification builds pass (Link and compile checks successful) | Green |
| **Apple Silicon macOS** (`aarch64-macos`) | **Successful** (Dynamic Mach-O) | Native execution: All tests pass | Green |

---

## 🛠️ Technical Details of Libc Removal & Platform Compatibility

### 1. Zig-Native C Standard Library Shim (`src/runtime/main_clib.zig`)
Rather than referencing external libc libraries, standard POSIX functions required by the legacy runtime are implemented in pure Zig:
- **`FILE*`-based stdio**: Backed by custom `FILE` structures wrapping file descriptors via `std.posix` system calls. Implements `fopen`, `fclose`, `getc`, `putc`, `fgets`, `fputs`, `fread`, `fwrite`, and custom `printf`/`fprintf`/`sprintf`/`fscanf` parsers.
- **Memory Management**: Implements `malloc`, `calloc`, `realloc`, and `free` using `std.heap.page_allocator`.
- **String utilities**: Pure-Zig implementations of `strlen`, `strcmp`, `strncmp`, `strcpy`, `strcat`, etc.
- **Process controls & Compatibility**: 
  - Pure-Zig shims for `fork`, `wait`, `pipe`, `dup2`, `exec` using `std.posix.system` syscalls.
  - Target-conditional binding for `sigsetjmp`: Maps to the standard `sigsetjmp` on macOS, and directly to the internal symbol `__sigsetjmp` on Linux where `sigsetjmp` is implemented as a macro in the host C headers rather than a library symbol.
  - Linked `libc` conditionally for the integration test runner compilation when compiling for Linux targets to resolve standard external symbols (like `fork` used by `utf8-tests`).

### 2. Dependency Auditing & Binary Verification
* **macOS Arm64 Verification**:
  Running `otool -L zig-out/bin/mira` confirms that the binary depends **only** on `/usr/lib/libSystem.B.dylib`, which is standard for macOS system call interfaces.
* **Linux x86_64 Verification**:
  - Building for `x86_64-linux-musl` and running `file zig-out/bin/mira` confirms a fully `statically linked` ELF binary, depending on zero dynamic library configurations.
  - Building for `x86_64-linux-gnu` compiles and links successfully against standard glibc targets.

### 3. Known ELF Linker Issue on Recent Linux Distributions (glibc 2.43+ / GCC 15+)
When building a Debug binary on rolling-release or highly up-to-date Linux distributions (e.g., Arch Linux, Ubuntu 24.10+, Fedora), the compile/link step may fail with an ELF linker relocation error.
* **Cause**: This is due to a known upstream bug in Zig's self-hosted ELF linker ([ziglang/zig#31272](https://github.com/ziglang/zig/issues/31272)). Recent updates to glibc (2.43+) or GCC (15+) introduced `.sframe` stack trace sections containing `R_X86_64_PC64` relocations, which Zig's native self-hosted ELF linker does not yet support in Debug mode.
* **Workaround**: Force a Release build using LLVM instead of the self-hosted linker by specifying the optimization level using `-Doptimize=ReleaseSafe` (or `ReleaseFast` / `ReleaseSmall`):
  ```bash
  zig build -Doptimize=ReleaseSafe
  ```

