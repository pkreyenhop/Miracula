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
- `issues/` — issue-management utilities and records

## Building

Use the build tooling supplied with the source checkout. A successful default
build produces the `mira` command and the companion utilities used by the
standard library.

Build instructions may change as the implementation evolves. The available
targets in the project build definition are the source of truth for a given
checkout.

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

Before submitting a change, run the complete verification target provided by
the project build tooling. Tests that require a reference executable must run
against the pinned reference rather than being treated as optional.

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

Behavior that depends on processes, signals, terminals, or filesystem metadata
may vary on unsupported systems.

## Compatibility

Miracula aims to preserve Miranda language behavior, interactive behavior, and
compiled object compatibility. Observable behavior is protected by
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
- the compiled object-file format.

Add or update tests for observable behavior changes. Keep generated fixtures
deterministic and avoid committing local build outputs.
