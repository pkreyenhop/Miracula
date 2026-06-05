# Architecture

This repository builds the Miranda interpreter, `mira`, plus a few small
support utilities. The build is driven by Zig. The code is still partly C, with
parser and combinator tables generated from source inputs, but C compilation is
done through Zig's toolchain rather than a direct system `clang` invocation.

## Build Layout

- `build.zig` builds `mira`, `fdate`, `just`, `miralib/menudriver`, and the
  installed `miralib` tree. `zig build` installs outputs under `zig-out/`.
- `zig build check` is the main local verification target. It builds the
  interpreter and tools, checks standalone header syntax, runs UTF-8 module
  tests, and runs the interpreter integration suite.
- `zig build test` runs all tests. `zig build test-mira` runs just the
  interpreter integration tests.
- `zig build tools` builds the support tools.
- `zig build clean` removes Zig and legacy build outputs.
- `Makefile` is now only a compatibility wrapper around `zig build` targets.
- The Zig build defaults to `ReleaseFast` because Zig safety instrumentation
  changes the GC-sensitive C stack shape.
- `rules.y` is the yacc grammar. It generates `y.tab.c` and `y.tab.h` with
  Berkeley yacc (`byacc`); GNU bison is not compatible with this grammar.
- `gencdecs` historically generated combinator metadata. The numeric ids remain
  in `combs.h`; the active combinator-name table is now `cmbnms.zig`.
- `miralib/` contains the Miranda standard environment, prelude, manual, and
  example scripts.
- `tests/mira_tests.zig` contains integration tests that run the built `mira`
  binary with isolated temporary homes. Use `make test` for the interpreter
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

`steer_helpers.zig` exports C ABI leaf helpers used by `steer.c` and related
compiler modules, including list reversal helpers, source timestamp checks,
simple file copying, source-suffix detection, expression sizing, and terminal
width probing.

`version.zig` exports the C ABI globals for version, host, and source revision
date metadata. `build.zig` reads those values from the existing repository
metadata files and passes them into the Zig object as build options.

`cmbnms.zig` exports the C ABI `cmbnms` table consumed by `data.c` when printing
combinator objects.

`data_helpers.zig` exports small C ABI helpers formerly in `data.c`, including
character boxing/unboxing, identifier here-info extraction, destructive list
append, alias-name lookup, definition-list sorting, character-name formatting,
and floating-number output formatting. Heap allocation, GC, dump/load, and most
object printing still live in `data.c`.

`lex_helpers.zig` exports pure C ABI lexer helpers for identifier and path
character classification, constructor-name detection, and dictionary hash
bucket selection. Lexer state and tokenization remain in `lex.c`.

`trans_helpers.zig` exports C ABI relation and ordered-set helpers used by
translation, typechecking, and grammar analysis. It owns relation lookup,
transitive closure, set difference, address-order sorting helpers, repeated-name
membership checks, structural equality, pattern-id extraction, tuple-pattern
reconstruction, pattern irrefutability/fallibility checks, and
constructor-value extraction. It also owns simple list tail and translated-RHS
here-info lookup helpers used outside `trans.c`, plus repeated zf generator
expansion, bracket-abstraction combinator rewrite helpers, pattern abstraction,
and list-variable abstraction. Pattern binding scans for top-level declarations
are also in `trans_helpers.zig`, along with lazy local-pattern rewrites and zf
comprehension compilation. Spec-location lookup and literal type-name
recognition are also exported from the helper object, as is lhs pattern
normalisation for generators, grammar left-factor rewriting, and abstract-type
show-function validation. Local where-clause name clash checking is also
exported from Zig for the parser, along with declaration diagnostic helpers and
value, constructor, type, and type-specification declaration handling; local
`let`/`letrec` compilation wrappers and `tries` fallback compilation have moved
there as well, as has where-block dependency orchestration and show-function
construction. The main translation pipeline remains in `trans.c`.

`types_helpers.zig` exports C ABI ordered-set helpers shared by parser,
typechecker, translator, and steering code. It owns destructive set insertion,
removal, union, difference, intersection, membership, and the `NEW` side-effect
wrapper; type inference, substitution, abstract type checks, and type reporting
remain in `types.c`.

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

`big.zig` owns Miranda arbitrary-precision integers. A bigint is an `INT` chain
using base `IBASE`, with sign stored in the first digit word.

`utf8.zig` converts between Unicode code points and UTF-8 byte sequences for
the lexer and runtime character I/O paths.

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

- `fdate.zig` reads a filename from stdin and prints its last modification
  date.
- `menudriver.zig` is a standalone browser for the installed manual tree.
- `just.zig` is a standalone text justification utility used by documentation
  tooling.
- `signals.zig` wraps `sigaction()` so the rest of the old code can keep using
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
