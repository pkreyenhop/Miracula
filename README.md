# Miracula

Miracula is a modern implementation of the
[Miranda](https://en.wikipedia.org/wiki/Miranda_(programming_language))
programming language.

It provides an interactive environment, script compilation, lazy graph
reduction, arbitrary-precision integer arithmetic, module directives, and the
standard Miranda library and documentation.

## Features

- Interactive read-evaluate-print loop
- Miranda scripts and literate scripts
- Lazy evaluation through combinator graph reduction
- Pattern matching and algebraic data types
- Type inference and type checking
- Arbitrary-precision integers
- Module inclusion, exports, aliases, and free declarations
- Layout-sensitive syntax
- Saved object files for compiled scripts
- Standard environment, examples, help, and manual pages
- Command-line, batch, and interactive workflows

## Quick start

After building or installing the project, start the interactive environment:

```sh
mira
```

Load a script:

```sh
mira myfile.m
```

At the prompt, enter an expression to evaluate it:

```text
1 + 2
take 10 [1..]
```

Quit with:

```text
/q
```

If the standard library is not in its installed location, provide it
explicitly:

```sh
mira -lib /path/to/miralib myfile.m
```

The manual under `miralib/manual/` describes the available command-line and
interactive options.

## Example program

Create `fib.m`:

```miranda
fib 0 = 0
fib 1 = 1
fib n = fib (n - 1) + fib (n - 2)
```

Load it:

```sh
mira fib.m
```

Then evaluate:

```text
fib 20
```

## Repository contents

- `src/` — interpreter, parser, type checker, graph runtime, session, and
  platform services
- `miralib/` — standard environment, manual, help data, and example programs
- `tests/` — unit, integration, compatibility, golden-output, interrupt, and
  stress tests
- `docs/` — project documentation and historical notes
- `scripts/` — repository checks and maintenance utilities

## Building and installing

The production interpreter is written in Go and supports macOS on Apple
Silicon. Go 1.23 or newer is required. A normal build does not require Zig:

```sh
make
./build/mira --build-info
```

Install the binary and its standard library under `/usr/local` (or set a
different `PREFIX`):

```sh
make install PREFIX=/usr/local
make uninstall PREFIX=/usr/local
```

The installed command finds `../lib/miralib` relative to itself. `MIRALIB` and
`-lib` remain available as explicit overrides. Release archives are produced
with `make package`; set `SOURCE_DATE_EPOCH` to reproduce metadata exactly.

The historical Zig implementation is test-only during the Go cutover. Build it
explicitly as `zig-out/bin/mira-zig-reference` with `make reference`. `zig
build` also produces the Go `zig-out/bin/mira`; it does not select the Zig
interpreter as the product.

## Testing

The repository includes:

- focused subsystem tests;
- parser and lexer tests;
- executable smoke tests;
- golden stdout and stderr comparisons;
- object-file round-trip tests;
- interrupt handling tests;
- graph-reduction stress tests; and
- compatibility comparisons against a reference executable.

Before submitting a change, run `make test`, `make race`, and `make smoke`.
`make parity` compares a fresh Go binary with the pinned reference. The broader
Zig-hosted compatibility gate remains available as `zig build go-ready`.

## Standard library and examples

The `miralib/` directory contains the standard environment and the historical
Miranda documentation. Example programs are under `miralib/ex/`.

Common examples include:

- Fibonacci numbers
- Prime-number streams
- Quicksort and tree sort
- The Hamming-number sequence
- Matrices
- Arbitrary-precision arithmetic
- List and set operations

## Supported systems

The project is tested on:

- macOS on 64-bit ARM systems

Linux, Intel macOS, and other targets are explicitly unsupported and fail the
production build rather than compiling a partial interpreter.

## Compatibility

Miracula preserves Miranda language and interactive behavior. Go `.x` files
are disposable, versioned caches and are rebuilt safely when stale or from a
different implementation; see `docs/GoCompatibilityExceptions.md`. Observable behavior is protected by
golden-output, regression, and differential test suites.

The project includes material derived from the historical Miranda distribution.
See [LICENSE](LICENSE) and `miralib/COPYING` for licensing information.

## Contributing

Changes should preserve:

- language semantics;
- lazy evaluation behavior;
- standard-library compatibility;
- command-line and interactive behavior;
- diagnostic output where covered by compatibility tests; and
- safe compiled-cache lifecycle and reload behavior.

Add or update tests for observable behavior changes. Keep generated fixtures
deterministic and avoid committing local build outputs.
