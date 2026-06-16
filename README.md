# Miracula

Miracula is a modern implementation of the **Miranda** programming language, migrated to the **Zig** programming language.

The project's goal is to transition the original, historical C codebase into an idiomatic, pure-Zig implementation with clean module boundaries, solid cross-compilation support, and zero legacy build headaches.

---

## Current Status

* **✔ Runtime Migrated to Zig**: The garbage-collected graph reduction runtime is fully rewritten and functioning in Zig.
* **✔ Unified Zig Build System**: Replaced the legacy Makefiles and build scripts with `build.zig`.
* **✔ Modular Source Structure**: Reorganized the source tree into logical packages (runtime, compiler, parser, and IO subsystems).
* **✔ Pure Zig Parser**: The YACC/C parser (`rules.y` / `y.tab.c`) has been fully replaced with a recursive-descent + Pratt parser in Zig. No C parser files are compiled.
* **✔ REPL Works Correctly**: The interactive REPL evaluates expressions with proper fork-based isolation — heavy computations (e.g. `fib 32`) do not corrupt the heap for subsequent evaluations.
* **✔ Menudriver Works**: The Miranda menu-driven help viewer (`menudriver`) is built and installed into `miralib/` by `build.zig`. Zig 0.16 `writableVector` aliasing and shell read-ahead stdin isolation bugs fixed.
* **✔ Tests Passing**: 60/61 tests pass across all suites (steer: 21, lex: 21, parser: 14, menudriver: 2, just: 2). The single known failure is a pre-existing `mira-tests` integration test.
* **⚠ libc Linked**: libc remains linked to support platform abstractions (signals, file I/O, big integers).

---

## Repository Layout

* [src/runtime](src/runtime) — Graph reduction engine, big integers, and heap/garbage collector.
* [src/compiler](src/compiler) — Typechecker, code generator, and translation structures.
* [src/parser](src/parser) — Pure Zig lexer, recursive-descent + Pratt parser, and codegen bridge to the Miranda heap.
* [src/io](src/io) — UTF-8 and signals platform IO abstractions.
* [menudriver.zig](menudriver.zig) — Miranda menu-driven help viewer; built by `zig build` and installed into `miralib/`.
* [tests](tests) — Integration, golden, and regression tests.
* [miralib](miralib) — Miranda standard environment prelude and libraries.

---

## Building

To build the `mira` executable:

```bash
zig build
```

This compiles the executable and places it in `zig-out/bin/mira`.

---

## Running

```bash
./zig-out/bin/mira            # load script.m and start REPL
./zig-out/bin/mira myfile.m   # load a script and start REPL
./zig-out/bin/mira -lib miralib miralib/stdenv.m   # load stdenv explicitly
```

---

## Running Tests

To run all native unit and integration tests:

```bash
zig build test --summary all
```

To run only the main steer tests (fastest):

```bash
zig build test-steer --summary all
```

---

## Target Platforms

Miracula officially supports and cross-compiles for:
* **Apple Silicon macOS** (`aarch64-macos`)
* **Intel 64-bit Linux** (`x86_64-linux`)

---

## Migration Roadmap

| Phase | Description | Status |
| --- | --- | --- |
| **Phase 1** | Runtime Migration to Zig | **Complete** ✔ |
| **Phase 2** | Source Modularization | **Complete** ✔ |
| **Phase 3** | Unified Build System | **Complete** ✔ |
| **Phase 4** | libc Dependency Reduction | **Complete** ✔ |
| **Phase 5** | Pure Zig Parser (No Yacc/C) | **Complete** ✔ |
| **Phase 6** | Pure Zig Implementation (No libc) | *Planned* |
