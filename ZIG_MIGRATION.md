# Zig Migration Plan

The long-term goal is to migrate the interpreter from C to Zig without losing
the current portability and behaviour baseline. The C implementation remains
the source of truth until each module has tests, a stable boundary, and a Zig
replacement that passes the same integration checks.

## Current Gate

Before and after each migration patch, run the smallest gate that covers the
changed area:

- `zig build check` for the full build and test gate.
- `zig build test` for all tests.
- `zig build test-mira` for interpreter integration tests only.
- `zig build check-headers` for standalone public-header syntax checks.
- `zig build tools` for support tools.

`build.zig` is the primary build. The Makefile is only a compatibility wrapper
around Zig targets. The build defaults to `ReleaseFast`; `ReleaseSafe` currently
changes the C stack shape enough to trip GC stress tests in the historical
runtime.

## Initial Stages

1. Keep generated C files checked in and synchronized with their sources.
2. Continue removing unsafe buffer and command construction in C before porting
   modules that use those paths.
3. Split broad public headers before exporting APIs to Zig. `data.h` is the
   primary coupling point to unwind.
4. Add stable C ABI headers only for narrow boundaries that mixed C/Zig builds
   actually need.
5. Use `build.zig` as the canonical build harness.
6. Port leaf utilities first. `fdate.zig` is the first small Zig utility and is
   built as `zig-out/bin/fdate`.
7. Add direct module tests before each runtime module port. `tests/utf8_tests.c`
   now covers valid UTF-8 codec paths, malformed input diagnostics, and
   out-of-range output diagnostics. `zig build check-migration` runs the same
   tests against `utf8.zig`.

## Port Order

Suggested order after the initial build harness:

1. Standalone utilities. `fdate.c` has been replaced by `fdate.zig`, and
   `just.c` has been replaced by `just.zig`.
2. UTF-8 runtime support. `utf8.c` has been replaced by `utf8.zig`.
3. Signal handling. `signals.c` has been replaced by `signals.zig`.
4. Build metadata. `version.c` has been replaced by `version.zig`.
5. Combinator names. `cmbnms.c` has been replaced by `cmbnms.zig`.
6. `big.c`, after focused arithmetic and conversion tests exist. The
   interpreter suite now covers large signed arithmetic, `div`/`mod` laws,
   comparison, `showhex`, and `numval`.
7. Heap/data internals, after dump/undump and GC stress tests are strong.
8. Lexer, translator, and typechecker.
9. Reducer last, after the C decomposition plan has explicit context and action
   boundaries.
