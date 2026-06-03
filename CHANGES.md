# Changes From Original Checkout

This file summarizes the current working-tree changes relative to the original
repository checkout.

## Build And Tooling

- Added a repeatable `clang-format` configuration in `.clang-format`.
- Added a `test` target to `Makefile` that builds `mira` and runs the
  integration test suite.
- Added `check`, `check-c`, `check-tools`, and `check-cxx` Makefile targets
  so local verification exercises the strict C build, tests, standalone
  tools, and C++ compatibility build.
- Added `check-headers` to syntax-check the project headers under both the
  strict C warning profile and the C++ compatibility profile.
- Introduced named Makefile lists for interpreter objects, core objects,
  runtime headers, and header-check includes to reduce duplicated build rules.
- Fixed object-list handling so `signals.o` is an explicit prerequisite of the
  main interpreter link.
- Added explicit `fdate` and `just` build rules so utility programs are checked
  with the same warning profile as the main interpreter.
- Earlier cleanup added C++ and Zig C compatibility targets; these have now
  been superseded by the canonical `build.zig` build.
- Routed Zig builds through a project-local `.zig-cache/` and made `cleanup`
  remove it.
- Added Zig-owned clean/check/tool targets so build products are managed through
  `build.zig`.
- Added `warnings.md` and a `warning-audit` Makefile target to start cleanup
  Phase 1 by documenting current warning suppressions and exposing selected
  warning debt without `-Werror`.
- Updated the default Clang C profile from C11 to C2y, the latest C mode
  accepted by the installed Clang.
- Converted project-owned legacy octal integer literals to equivalent hex
  constants so the C2y build stays warning-clean.
- Scoped Zig-specific C warning adjustments to the Zig build.
- Changed the default `make check` path to delegate to `zig build check`.
- Added smoke coverage for compile-time degradation, very long literals, and
  compilation/runtime paths that must trigger garbage collection.
- Added a timeout-bounded standard library load smoke test to catch gross
  startup or standard-environment speed regressions.
- Added `version.h` for build/version metadata, made `menudriver.c` helper
  definitions consistently file-local, and later replaced `fdate.c` with
  `fdate.zig`.
- Later replaced `just.c` with `just.zig`.
- Later replaced `utf8.c` with `utf8.zig`.
- Made `big.c`'s division remainder state and digit-conversion helper
  file-local.
- Made `data.c`'s dump/load filename cursor and private-name relocation base
  file-local.
- Removed `reduce.c`'s unused exported reducer step counter.
- Made `types.c`'s typechecker counters and include-location tracking state
  file-local where they are not shared with other modules.
- Made lexer-only helpers and character-class tracking state in `lex.c`
  file-local, and removed its unused nonterminal-name predicate.
- Made `steer.c` command-line, editor, recheck, and library-version
  bookkeeping state file-local where it is only used by the driver.
- Made additional `steer.c` driver-only buffers, parser jump state, keyword
  metadata, and display bookkeeping file-local.
- Made `lex.c` lexer-local layout, prefix, literate-mode, prelude, and
  private-name capacity state file-local while preserving shared GC roots.
- Made additional `steer.c` driver-only command flags file-local while
  preserving GC/runtime-visible state, and removed their public declarations
  from `allexterns`.
- Removed duplicate `dicp` and `vdate` declarations from `allexterns`.
- Declared shared lexer column state in `lex.h`, made lexer-only echo stack and
  underlined-identifier helper file-local, and removed unused `PREL`.
- Removed redundant local extern declarations for shared dictionary and lexer
  state in handwritten sources.
- Removed the redundant local `col_fn` extern from `types.c`.
- Started the `reduce()` decomposition by adding terminal rewrite helpers and
  applying them to behaviour-preserving constant/value rewrites.
- Expanded the initial `reduce()` helper pass across list and stream EOF
  rewrites that do not allocate replacement values.
- Continued the `reduce()` helper pass through grammar, lexer, and ready
  selector rewrites that return constants or already-computed values.
- Continued the `reduce()` helper pass through ready control, predicate, zip,
  and constructor-display rewrites while preserving allocation order.
- Continued the `reduce()` helper pass through more core, grammar, lexer,
  environment, numeric, and merge terminal rewrites without moving allocations.
- Added a reducer helper for terminal `CONS` rewrites that preserve the
  existing tail pointer.
- Added a reducer helper for identity rewrites that continue through the
  current node's existing tail without replacing `tl(e)`.
- Added a reducer helper for `CONS` rewrites whose head and tail values are
  already computed locals or constants.
- Added comparison-specific reducer helpers for match and equality/order
  rewrites while preserving the original mutation-before-compare order.
- Added a string-conversion reducer helper for display rewrites that must
  mutate the expression head before calling `str_conv()`.
- Extended `make warning-audit` to include standalone tools as well as `mira`.
- Switched the default C compile profile to Clang C23 with
  `-Wall -Wextra -Wpedantic`.
- Linked the Zig C++ compatibility build with `-nostdlib++`, because the code
  is C source compiled as C++ and does not use C++ standard-library symbols.
  This avoids warning output from Zig rebuilding bundled libc++ during links.
- Replaced the Makefile-driven build with `build.zig`. The Makefile is now a
  compatibility wrapper around Zig targets and no longer invokes `clang`
  directly.
- Removed replaced C implementation files `fdate.c` and `utf8.c`; the active
  implementations are `fdate.zig` and `utf8.zig`.
- Replaced `just.c` with `just.zig` and added Zig unit coverage for ordinary
  paragraph wrapping plus frozen-line preservation.
- Replaced `signals.c` with `signals.zig`.
- Replaced `version.c` with `version.zig`; build metadata now flows through
  Zig build options while preserving the existing C header ABI.
- Replaced `cmbnms.c` with `cmbnms.zig`; the generated combinator-name table is
  now a Zig object linked into the interpreter.
- Replaced `menudriver.c` with `menudriver.zig` and added Zig unit coverage for
  shell quoting and executable-mode detection.
- Replaced `big.c` with `big.zig`; the arbitrary-precision integer package now
  uses the existing C heap/object ABI from Zig.
- Moved selected `steer.c` leaf helpers into `steer_helpers.zig` while
  preserving their C ABI entry points.
- Moved selected `data.c` leaf helpers into `data_helpers.zig` while preserving
  their C ABI entry points; this now includes character helpers, alias-name
  lookup, definition-list sorting, and diagnostic character-name formatting.
- Moved selected `lex.c` pure helpers into `lex_helpers.zig` and added Zig unit
  coverage for their classification behavior.
- Moved selected `trans.c` relation and ordered-set helpers into
  `trans_helpers.zig` while preserving their C ABI entry points; this now also
  owns repeated-name membership checks, structural equality, pattern-id
  extraction, tuple-pattern reconstruction, pattern irrefutability/fallibility
  checks, constructor-value extraction, simple list-tail lookup, and
  translated-RHS here-info lookup; it also owns repeated zf generator
  expansion, bracket-abstraction combinator rewrites, single-variable bracket
  abstraction, and list-variable abstraction, plus pattern binding scans for
  top-level declarations and lazy local-pattern rewrites. Zf comprehension
  compilation, spec-location lookup, literal type-name recognition, lhs pattern
  normalisation, and grammar left-factor rewriting now live there too, along
  with abstract-type
  show-function validation, local where-clause name clash checking, and
  declaration diagnostic helpers. Local `let`/`letrec` compilation wrappers
  and `tries` fallback compilation are now Zig exports too, along with
  show-function construction.
- Moved shared type/parser ordered-set helpers into `types_helpers.zig` while
  preserving the existing C ABI entry points and `NEW` side effect.

## Tests

- Added `tests/smoke.sh`, an integration smoke suite that runs the built
  interpreter with an isolated temporary `HOME`.
- Replaced the `make test` shell smoke runner with a Zig integration test
  module in `tests/mira_tests.zig`.
- Named each smoke-test case so failures point at the affected behavior.
- The Zig integration tests cover:
  - standard arithmetic and standard-environment functions;
  - list output;
  - lazy list operations, list reversal, zipping, and string concatenation;
  - bigint arithmetic;
  - loading and evaluating `miralib/ex/fib`;
  - temporary user script definitions;
  - representative syntax and type error reporting.

## Documentation

- Added `ARCHITECTURE.md` describing:
  - build layout;
  - startup flow;
  - lexer/parser/typechecker/translator/reducer pipeline;
  - runtime `word` and heap representation;
  - utility programs;
  - maintenance notes.
- Added concise file-level orientation comments to all top-level C translation
  units.

## Formatting

- Formatted top-level C and header files with `clang-format`.
- The formatting pass touched both handwritten and checked-in generated files,
  including `y.tab.c` and `combs.h`.
- Formatting is the dominant source of diff volume.

## ANSI/Modern C Cleanup

- Converted old K&R-style function definitions in remaining C files to ANSI C
  prototype definitions.
- Added explicit `void` to no-argument function declarations and definitions
  across C sources, headers, and yacc source snippets.
- Updated `rules.y` and the checked-in generated `y.tab.c` to keep parser code
  consistent.
- Fixed generated parser macro call sites that were affected by mechanical
  prototype conversion.

## Header Cleanup

- Added `runtime.h` for the core `word` scalar runtime type.
- Added `platform.h` for shared system includes and portability shims.
- Made `big.h` and `lex.h` include `runtime.h` directly for their public
  `word`-based declarations.
- Added `data.h` to the header syntax gate after the initial header cleanup
  made it parseable as a top-level include.
- Added include guards to project headers that previously lacked them:
  `data.h`, `big.h`, `lex.h`, `signals.h`, and `utf8.h`.
- Reduced `data.h` coupling by moving system include order, `index`/`rindex`
  compatibility macros, and legacy `union wait` handling into `platform.h`.
- Added `runtime.h` and `platform.h` to the build source and object dependency
  lists so runtime-header edits trigger rebuilds.

## Warning Fixes

- Cleaned remaining warnings under:
  `-std=c11 -D_POSIX_C_SOURCE=200809L -Wall -Wextra -Wstrict-prototypes -Wold-style-definition -Werror=implicit-int -Werror=implicit-function-declaration`
- Switched the default C warning profile to the Zig build's C23
  `-Wall -Wextra -Wpedantic` flags.
- `utf8.zig` now owns UTF-8 conversion and fatal UTF-8 diagnostics.
- `lex.c` now compares pathname prefix sizes with matching unsigned types.
- Remaining C files now have more explicit logical grouping, fewer nested block
  comments, and fewer assignment-in-condition warnings.

## C++ Compatibility

- Moved system includes in `data.h` ahead of Miranda constructor macros so
  macros such as `pair` do not collide with C++ standard-library declarations.
- Renamed identifiers that are C++ keywords, including the public
  `decltype()` helper and locals named `new`.
- Added explicit casts for C allocation calls that C++ does not convert from
  `void *` implicitly.
- Tightened a few string APIs to accept or return `const char *` where the
  caller passes string literals.
- Verified the Zig build compiles the interpreter and menu driver.
- Updated the C++ compatibility profile from C++17 to C++26.

## Existing Local Source Edits

These changes were already present before the later documentation, formatting,
test, ANSI C, and warning-cleanup work:

- `Makefile` had local compiler-related edits.
- `data.c` changed `getword()` to cast `getc()` before shifting:
  `(word)getc(f) << s`.

They remain in the working tree.

## Generated Or Local Artifacts Present

The working tree also contains untracked local artifacts:

- `script.m`
- `*.plist` files for the top-level C/generated sources

These are present in the working tree but are not part of the intentional C
cleanup/test/documentation change set described above.

## Verification

- `make test` passes through the Zig integration test module.
- `make check` passes and delegates to `zig build check`.
- `make check-headers` passes for the project headers in C2y mode.
- `mira` builds cleanly through `build.zig`.
- `menudriver.zig` builds and is installed through `build.zig`.
- `zig build check` passes.
- `zig build tools` builds the support tools.
