# Portability Report

This document reports on the status of target platform support, libc dependency removal, parser isolation, and recommendations for future phases.

## Target Platform Build Status

We have successfully configured and verified cross-compilation and linking for both required target platforms:

| Target Platform | Compiler Build | Test Suite Build / Execution | Status |
| --- | --- | --- | --- |
| **Intel 64-bit Linux** (`x86_64-linux`) | **Successful** | **Successful** (Compilation & Linking verified) | Green |
| **Apple Silicon macOS** (`aarch64-macos`) | **Successful** | **Successful** (Native execution: 11/11 tests pass) | Green |

---

## Remaining Libc Dependencies

Through Phase 4, we have completed the following dependency cleanup:

1. **Pure Zig Modules**:
   - `src/io/utf8.zig`: Replaced all C library functions and headers with raw extern function declarations for `getc` and `putc`, an opaque `FILE` type, and `std.process.exit`. No `@cImport` or C headers remain.
   - `src/io/signals.zig`: Replaced all `@cImport` usages with direct references to `std.posix` structures and constants (e.g. `std.posix.sigset_t`, `std.posix.sigemptyset()`, and `std.posix.SA.RESTART`).
   - `src/runtime/big.zig`: Removed `@cImport` entirely, utilizing `std.math.log`, `std.math.log10`, `std.math.floor`, `@rem`, and the thread-local errno from the platform module.

2. **Isolated Platform Wrapper**:
   - `src/io/platform.zig`: Encapsulates all OS-specific libc dependencies such as `stat` structures (using `std.os.linux.statx` on Linux and `clib.stat` on macOS), thread-local errno access (`__errno_location` on Linux and `__error` on macOS), and process user IDs.

3. **Compiler and Runtime Core Coupling**:
   - Subsystems like `heap.zig`, `reduce.zig`, `types.zig`, and `trans.zig` still reference shared compiler headers (`data.h`, `combs.h`, `lex.h`) to read parser constants and representation structures. These headers contain macro configurations that are coupled with the yacc parser.
   - In Phase 5 and beyond, when the pure-Zig parser is introduced, these legacy structures will be completely replaced, removing all remaining `@cImport` references in the core compiler.

---

## Parser Isolation Status

The legacy yacc/bison parser (`rules.y`, `y.tab.c`, `y.tab.h`) is isolated under `src/parser/legacy/`.
- A clean bridge interface is exposed by `parser_bridge.c`.
- To prevent linker errors during cross-compilation, `build.zig` was updated so that `steer-tests` and `lex-tests` now compile and link the C parser sources and define correct platform macros (`_DARWIN_C_SOURCE` / `_POSIX_C_SOURCE`).
- This allows all tests to compile and link correctly on both Linux and macOS.

---

## Recommended Next Steps

1. **Phase 5 (Pure Zig Parser)**:
   - Introduce a hand-written or parser-combinator-based pure Zig parser.
   - Progressively migrate semantic actions from `rules.y` to the Zig parser.
2. **Phase 6 (Remove Yacc/Bison)**:
   - Completely delete `rules.y`, `y.tab.c`, and `y.tab.h`.
3. **Phase 7 (Remove Libc Entirely)**:
   - Once the C parser is removed, clean up all remaining `@cImport` references, C-style memory allocators, and math calls, achieving a 100% native pure-Zig implementation.
