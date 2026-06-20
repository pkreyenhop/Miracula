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
* **Outcome**:
  - All `@cImport` / `@cInclude` statements have been removed from the Zig source files.
  - A custom, pure-Zig C standard library shim was implemented in `src/runtime/main_clib.zig` to resolve standard Unix symbols (POSIX/file-io/string functions) directly against the OS.
  - Linked C math library `libm` has been entirely replaced with native `std.math` equivalents.
  - The build target `link_libc` has been disabled on macOS, where the OS linker implicitly links `libSystem.dylib`.
  - The binary successfully cross-compiles cleanly to statically linked ELF binaries on Linux (`x86_64-linux-musl`) and Mach-O binaries on macOS (`aarch64-macos`).
  - Fixed compilation of the C test harness in `tests/utf8_tests.c` under the pure-Zig transition.

---

## 💻 Target Platform Build Status

We verify cross-compilation and linking for both required target platforms:

| Target Platform | Compiler Build | Test Suite Build / Execution | Status |
| :--- | :--- | :--- | :--- |
| **Intel 64-bit Linux** (`x86_64-linux`) | **Successful** (Static ELF Binary) | Verification builds pass | Green |
| **Apple Silicon macOS** (`aarch64-macos`) | **Successful** (Dynamic Mach-O) | Native execution: All 21 tests pass | Green |

---

## 🛠️ Technical Details of Libc Removal

### 1. Zig-Native C Standard Library Shim (`src/runtime/main_clib.zig`)
Rather than referencing external libc libraries, standard POSIX functions required by the legacy runtime are implemented in pure Zig:
- **`FILE*`-based stdio**: Backed by custom `FILE` structures wrapping file descriptors via `std.posix` system calls. Implements `fopen`, `fclose`, `getc`, `putc`, `fgets`, `fputs`, `fread`, `fwrite`, and custom `printf`/`fprintf`/`sprintf`/`fscanf` parsers.
- **Memory Management**: Implements `malloc`, `calloc`, `realloc`, and `free` using `std.heap.page_allocator`.
- **String utilities**: Pure-Zig implementations of `strlen`, `strcmp`, `strncmp`, `strcpy`, `strcat`, etc.
- **Process controls**: Pure-Zig shims for `fork`, `wait`, `pipe`, `dup2`, `exec` using `std.posix.system` syscalls.

### 2. Dependency Auditing & Binary Verification
* **macOS Arm64 Verification**:
  Running `otool -L zig-out/bin/mira` confirms that the binary depends **only** on `/usr/lib/libSystem.B.dylib`, which is standard for macOS system call interfaces.
* **Linux x86_64 Verification**:
  Running `file zig-out/bin/mira` when building for `x86_64-linux-musl` confirms a fully `statically linked` ELF binary, depending on zero dynamic library configurations.
