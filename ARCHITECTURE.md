# Architecture

This repository builds the Miranda interpreter, `mira`, plus a few small
support utilities. The code is mostly C, with parser and combinator tables
generated from source inputs.

## Build Layout

- `Makefile` builds `mira`, `miralib/menudriver`, and the example `.x` files.
- `make check` is the main local verification target. It runs a clean C build
  with Criterion-backed integration tests, checks standalone header syntax in
  C, and builds standalone tools.
- `make cxx` force-rebuilds `mira` and `miralib/menudriver` with `clang++`
  as C++26. This is a compatibility check; the normal build remains C.
- `make zig-cc` and `make zig-cxx` force-rebuild `mira` and
  `miralib/menudriver` with `zig cc` and `zig c++`, respectively. `make
  check-zig` runs both, and `make check` includes that target. The Zig targets
  use a project-local `.zig-cache/` so builds do not depend on a writable user
  cache.
- `rules.y` is the yacc grammar. It generates `y.tab.c` and `y.tab.h` with
  Berkeley yacc (`byacc`); GNU bison is not compatible with this grammar.
- `gencdecs` generates `cmbnms.c` and `combs.h`, which define combinator names
  and numeric ids shared by the compiler and reducer.
- `miralib/` contains the Miranda standard environment, prelude, manual, and
  example scripts.
- `tests/mira_tests.c` contains Criterion tests that run the built `mira`
  binary with isolated temporary homes. Use `make test` for just the Criterion
  suite or `make check` for the broader local gate.
- `runtime.h` defines the core `word` scalar type used by the C runtime.
- `platform.h` centralizes shared system includes and portability shims used by
  the runtime headers.

Generated files are checked in. Prefer changing `rules.y` or `gencdecs` inputs
and regenerating rather than hand-editing generated outputs.

## Startup Flow

`steer.c` owns process startup and the top-level control loop:

1. `main()` parses command-line flags, locates `miralib`, reads settings, and
   initializes global runtime state.
2. `mira_setup()` initializes the heap, typechecker state, private names, and
   bigint package.
3. The prelude and standard environment are loaded from `miralib/`.
4. The requested script is compiled or undumped.
5. The command loop reads expressions or `/commands`, parses them, typechecks
   them, translates them, and sends them to the reducer.

`version.c` is built with Makefile-generated defines for version, host, and
source revision date metadata.

## Compiler Pipeline

The main source pipeline is:

1. `lex.c` reads source text and command input. It handles tokens, layout
   rules, numeric and string literals, dictionary storage for names, `%include`
   and `%insert`, and static pathname resolution.
2. `rules.y` / `y.tab.c` parses Miranda scripts and expressions into heap
   objects using the shared data representation from `data.h`.
3. `types.c` performs type inference, synonym expansion, abstract type checks,
   dependency analysis, and undefined-name reporting.
4. `trans.c` translates typed Miranda definitions into SK-style combinator
   graphs.
5. `reduce.c` evaluates combinator graphs and implements primitive operations,
   I/O primitives, printing, and runtime error handling.

Compilation and evaluation share a large amount of global state. Be careful
when changing call order or error paths, because many subsystems assume that
`steer.c` has initialized globals in the historical order.

## Runtime Representation

All Miranda values are represented as `word`, defined in `data.h`.

- Small atoms live below `ATOMLIMIT`.
- Heap objects are indexes at or above `ATOMLIMIT`.
- Object tags are stored in `tag[]`.
- Object payloads are stored in interleaved `hd[]` and `tl[]` words.
- Constructors such as `ap`, `cons`, `lambda`, `pair`, and `strcons` are macros
  around `make()`.

`data.c` owns heap allocation, garbage collection support, object dumping and
undumping, identifier storage, and common object printing helpers.

`big.c` owns Miranda arbitrary-precision integers. A bigint is an `INT` chain
using base `IBASE`, with sign stored in the first digit word.

`utf8.c` converts between Unicode code points and UTF-8 byte sequences for the
lexer and runtime character I/O paths.

## Reduction And I/O

`reduce.c` is the graph reducer. It performs lazy evaluation over combinator
graphs and implements built-in functions. File, terminal, environment, numeric,
string, list, and exception-like runtime behaviors converge here.

Because reducer primitives can allocate, force thunks, print output, and touch
process state, changes in `reduce.c` should be covered by integration tests
that run through `mira`, not just by compilation.

## Type System

`types.c` owns typechecking state and error reporting. It tracks dependency
graphs, abstract type declarations, type variables, unresolved names, show
function generation hooks, and type substitutions.

`trans.c` depends on typecheck output. Avoid moving translation earlier in the
pipeline unless the typechecker invariants are preserved.

## Utilities

- `fdate.c` reads a filename from stdin and prints its last modification date.
  The Makefile uses this to maintain the source revision date.
- `menudriver.c` is a standalone browser for the installed manual tree.
- `just.c` is a standalone text justification utility used by documentation
  tooling.
- `signals.c` wraps `sigaction()` so the rest of the old code can keep using
  BSD-style signal semantics through `signals()`.

## Maintenance Notes

- Keep generated parser and combinator files synchronized with their sources.
- Prefer small integration tests that drive `mira` through stdin; they exercise
  the real lexer, parser, typechecker, translator, reducer, and library loading
  path.
- Avoid changing heap macros casually. Many files assume `hd(x)`, `tl(x)`, and
  `tag[x]` are cheap lvalue operations.
- Be cautious with compiler optimization. The project notes that garbage
  collection behavior can be sensitive to optimization level and platform.
- When adding strict compiler flags, distinguish portability warnings from real
  behavioral changes. This code intentionally targets a wide set of Unix-like
  systems and C compilers.
