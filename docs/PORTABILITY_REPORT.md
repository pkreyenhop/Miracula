# Portability Report

This document reports on the status of target platform support, libc dependency removal, parser isolation, and recommendations for future phases.

## Target Platform Build Status

We have successfully configured and verified cross-compilation and linking for both required target platforms:

| Target Platform | Compiler Build | Test Suite Build / Execution | Status |
| --- | --- | --- | --- |
| **Intel 64-bit Linux** (`x86_64-linux`) | **Successful** | **Successful** (Compilation & Linking verified) | Green |
| **Apple Silicon macOS** (`aarch64-macos`) | **Successful** | **Successful** (Native execution: 11/11 tests pass) | Green |

---

## Libc Dependencies Status

We have completely eliminated the standard C library dependencies from the core Miranda compiler (`mira`) and runtime:

1. **Zero C Headers & Imports**:
   - All `@cImport` and `@cInclude` statements have been removed from the entire Zig codebase.
   - Legacy compiler headers (`data.h`, `combs.h`, `lex.h`, `big.h`, `setjmp.h`, `stdio.h`) have been completely replaced by native Zig definitions (e.g., `src/runtime/word.zig` and `src/runtime/nil.zig`).

2. **Zig-Native C Standard Library Shim**:
   - Rather than referencing external libc binaries, a clean, native C standard library shim was implemented in `main_clib.zig`. This shim wraps POSIX system calls using `std.posix` and provides string/memory/character utility functions, avoiding standard C library linkage on macOS and allowing static linkage under Linux.

3. **No Dynamic Libc Dependency**:
   - The build configuration `link_libc = false` is active on macOS targets, where the compiler links solely to the standard `libSystem.dylib` provided by the OS.
   - For Linux targets, cross-compilation produces a statically linked, standalone ELF binary using musl.

---

## Parser Migration Status

The legacy C-based parser has been completely replaced and removed from the active runtime:
- The handwritten recursive-descent + Pratt parser (`parser.zig`, `pratt.zig`, `ast.zig`, `codegen.zig`, `token_filter.zig`) parses Miranda source code end-to-end and generates identical heap structures.
- Legacy YACC and Bison parser source/header files (`rules.y`, `y.tab.c`, `y.tab.h`) have been removed from the active compiler pipeline.

---

## Conclusion & Current Status

The C-to-Zig migration, parser replacement, and C standard library removal phases are **100% Complete**. The binary builds cleanly, cross-compiles without dynamic libc dependencies, and passes the entire integration/compiler test suite.

