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

1. Standalone utilities. `fdate.c` has been replaced by `fdate.zig`,
   `just.c` has been replaced by `just.zig`, and `menudriver.c` has been
   replaced by `menudriver.zig`.
2. UTF-8 runtime support. `utf8.c` has been replaced by `utf8.zig`.
3. Signal handling. `signals.c` has been replaced by `signals.zig`.
4. Build metadata. `version.c` has been replaced by `version.zig`.
5. Combinator names. `cmbnms.c` has been replaced by `cmbnms.zig`.
6. Big integers. `big.c` has been replaced by `big.zig`. The interpreter suite
   covers large signed arithmetic, `div`/`mod` laws, comparison, `showhex`, and
   `numval`.
7. Steer leaf helpers. `steer_helpers.zig` now owns list reversal helpers,
   source timestamp checks, simple file copying, `.m` suffix detection,
   expression sizing, and terminal width probing.
8. Data leaf helpers. `data_helpers.zig` now owns character boxing/unboxing,
   identifier here-info extraction, destructive list append, alias-name lookup,
   definition-list sorting, character-name formatting, and floating output
   formatting.
9. Lexer leaf helpers. `lex_helpers.zig` now owns identifier character
   classification, constructor-name detection, and dictionary hashing.
10. Translation relation helpers. `trans_helpers.zig` now owns relation lookup,
   transitive closure, set difference, address-order sorting helpers,
   repeated-name membership checks, structural equality, pattern-id extraction,
   tuple-pattern reconstruction, pattern irrefutability/fallibility checks, and
   constructor-value extraction. It also owns simple list tail,
   translated-RHS here-info lookup helpers, repeated zf generator expansion,
   bracket-abstraction combinator rewrite helpers, single-variable bracket
   abstraction, and list-variable abstraction. Pattern binding scans for
   top-level declarations are also in
   `trans_helpers.zig`, along with lazy local-pattern rewrites and zf
   comprehension compilation. Spec-location lookup and literal type-name
   recognition are also exported from the helper object, as is lhs pattern
   normalisation for generators, grammar left-factor rewriting, and
   abstract-type show-function validation. Local where-clause name clash
   checking and declaration diagnostic helpers are also exported from Zig for
   C callers, along with local `let`/`letrec` compilation wrappers and `tries`
   fallback compilation. Show-function construction is also a Zig export.
11. Type ordered-set helpers. `types_helpers.zig` now owns destructive
   insertion, removal, union, difference, intersection, membership, and the
   `NEW` side-effect wrapper used by grammar analysis.
12. Heap/data internals, after dump/undump and GC stress tests are strong.
13. Lexer, translator, and typechecker.
14. Reducer last, after the C decomposition plan has explicit context and action
   boundaries.
