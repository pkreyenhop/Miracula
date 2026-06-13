# Miracula

Miracula is a modern, high-performance implementation of the **Miranda** programming language, migrated to the **Zig** programming language. 

The project's goal is to transition the original, historical C codebase into an idiomatic, pure-Zig implementation with clean module boundaries, solid cross-compilation support, and zero legacy build headaches.

---

## Current Status

* **✔ Runtime Migrated to Zig**: The garbage-collected graph reduction runtime is fully rewritten and functioning in Zig.
* **✔ Unified Zig Build System**: Replaced the legacy Makefiles and build scripts with `build.zig`.
* **✔ Modular Source Structure**: Reorganized the source tree into logical packages (runtime, compiler, parser, and IO subsystems).
* **✔ Tests Passing**: The test suites and regression scripts pass completely.
* **⚠ Legacy Yacc Parser**: The semantic actions are in Zig, but `rules.y` remains the source of truth, compiling to C parser structures.
* **⚠ libc Linked**: libc remains linked to support the legacy parser and platform abstractions.

---

## Repository Layout

* [src/runtime](file:///Users/pkreyenhop/src/Miracula/src/runtime) — The graph reduction engine, big integers, and heap/garbage collector.
* [src/compiler](file:///Users/pkreyenhop/src/Miracula/src/compiler) — The typechecker, code generator, and translation structures.
* [src/parser](file:///Users/pkreyenhop/src/Miracula/src/parser) — Lexer and semantic actions bridging the yacc-generated parser.
* [src/io](file:///Users/pkreyenhop/src/Miracula/src/io) — UTF-8 and signals platform IO abstractions.
* [tests](file:///Users/pkreyenhop/src/Miracula/tests) — Integration, golden, and regression tests.
* [miralib](file:///Users/pkreyenhop/src/Miracula/miralib) — Miranda standard environment prelude and libraries.

---

## Building

To build the `mira` executable:

```bash
zig build
```

This compiles the executable and places it in `zig-out/bin/mira`.

---

## Running Tests

To run all native unit and integration tests:

```bash
zig build test --summary all
```

---

## Target Platforms

Miracula officially supports and cross-compiles for:
* **Apple Silicon macOS** (`aarch64-macos`)
* **Intel 64-bit Linux** (`x86_64-linux`)

---

## Current Migration Roadmap

| Phase | Description | Status |
| --- | --- | --- |
| **Phase 1** | Runtime Migration to Zig | **Complete** ✔ |
| **Phase 2** | Source Modularization | **Complete** ✔ |
| **Phase 3** | Unified Build System | **Complete** ✔ |
| **Phase 4** | libc Dependency Reduction | **Complete** ✔ |
| **Phase 5** | Pure Zig Parser (No Yacc/C) | *Planned* |
| **Phase 6** | Pure Zig Implementation (No libc) | *Planned* |
