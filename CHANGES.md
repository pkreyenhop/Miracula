# Changes From Original Checkout

This file summarizes the current working-tree changes relative to the original
repository checkout.

## Build And Tooling

- Added a repeatable `clang-format` configuration in `.clang-format`.
- Added a `test` target to `Makefile` that builds `mira` and runs
  `tests/smoke.sh`.
- Added `check`, `check-c`, `check-tools`, and `check-cxx` Makefile targets
  so local verification exercises the strict C build, smoke tests, standalone
  tools, and C++ compatibility build.
- Added `check-headers` to syntax-check the project headers under both the
  strict C warning profile and the C++ compatibility profile.
- Introduced named Makefile lists for interpreter objects, core objects,
  runtime headers, and header-check includes to reduce duplicated build rules.
- Fixed object-list handling so `signals.o` is an explicit prerequisite of the
  main interpreter link.
- Added explicit `fdate` and `just` build rules so utility programs are checked
  with the same warning profile as the main interpreter.
- Added a `cxx` target to `Makefile` that force-rebuilds `mira` and
  `miralib/menudriver` with `clang++` as C++26.
- Added `zig-cc`, `zig-cxx`, and `check-zig` targets so the interpreter and
  menu driver also build warning-clean with `zig cc` and `zig c++`.
- Split compile and link flags in the Makefile so C++-only source flags such as
  `-x c++` do not leak into final link commands.
- Routed Zig builds through a project-local `.zig-cache/` and made `cleanup`
  remove it.
- Added an internal `clean-build-products` target so Zig checks can clean build
  outputs without deleting the active Zig cache between `zig-cc` and `zig-cxx`.
- Added `warnings.md` and a `warning-audit` Makefile target to start cleanup
  Phase 1 by documenting current warning suppressions and exposing selected
  warning debt without `-Werror`.
- Updated the default Clang C profile from C11 to C2y, the latest C mode
  accepted by the installed Clang.
- Converted project-owned legacy octal integer literals to equivalent hex
  constants so the C2y build stays warning-clean.
- Scoped `-Wno-deprecated-octal-literals` to `zig cc` builds only, because Zig's
  system header path expands glibc macros that still contain legacy octal
  literals under C2y.
- Changed the default `make check` path to run only the strict Clang C2y build,
  smoke tests, and tools. C++26 and Zig targets remain available explicitly, but
  are no longer part of the routine check loop.
- Added smoke coverage for compile-time degradation, very long literals, and
  compilation/runtime paths that must trigger garbage collection.
- Added a timeout-bounded standard library load smoke test to catch gross
  startup or standard-environment speed regressions.
- Added `version.h` for build/version metadata, made `menudriver.c` helper
  definitions consistently file-local, and moved `fdate.c` helper state behind
  `static` storage.
- Moved `just.c` utility state behind `static` storage so it no longer appears
  as accidental exported data in the warning audit.
- Made `utf8.c` decoder error-reporting state and helper function file-local.
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
- Preserved the local Makefile compiler edits that were already present:
  `CC = clang` and the adjusted `CFLAGS` line.

## Tests

- Added `tests/smoke.sh`, an integration smoke suite that runs the built
  interpreter with an isolated temporary `HOME`.
- Named each smoke-test case so failures point at the affected behavior.
- The smoke tests cover:
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
  including `y.tab.c`, `cmbnms.c`, and `combs.h`.
- Formatting is the dominant source of diff volume.

## ANSI/Modern C Cleanup

- Converted old K&R-style function definitions in `just.c` to ANSI C prototype
  definitions.
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
- Added `runtime.h` and `platform.h` to the Makefile source and object
  dependency lists so runtime-header edits trigger rebuilds.

## Warning Fixes

- Cleaned remaining warnings under:
  `-std=c11 -D_POSIX_C_SOURCE=200809L -Wall -Wextra -Wstrict-prototypes -Wold-style-definition -Werror=implicit-int -Werror=implicit-function-declaration`
- Switched the default Makefile `CFLAGS` to a Clang `-Weverything -Werror`
  warning profile.
- The `-Weverything` profile explicitly disables warning categories that are
  not actionable for this codebase without redesigning the historical heap
  macros, yacc output, global namespace, or signal-handler compatibility layer.
- `utf8.c` now uses `int` byte temporaries where EOF must be represented, and
  formats error bytes explicitly.
- `lex.c` now compares pathname prefix sizes with matching unsigned types.
- `just.c` now has explicit logical grouping, no nested block comments, no
  assignment-in-condition warning, and handles `fgets()` failure explicitly.

## C++ Compatibility

- Moved system includes in `data.h` ahead of Miranda constructor macros so
  macros such as `pair` do not collide with C++ standard-library declarations.
- Renamed identifiers that are C++ keywords, including the public
  `decltype()` helper and locals named `new`.
- Added explicit casts for C allocation calls that C++ does not convert from
  `void *` implicitly.
- Tightened a few string APIs to accept or return `const char *` where the
  caller passes string literals.
- Verified `make cxx` builds the interpreter and menu driver with `clang++`.
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

- `compile_commands.json`
- `big.zig`
- `script.m`
- `*.plist` files for the top-level C/generated sources

These are present in the working tree but are not part of the intentional C
cleanup/test/documentation change set described above.

## Verification

- `make test` passes with `smoke tests passed`.
- `make check` passes and covers the strict Clang C2y build, smoke tests, and
  tools.
- `make check-headers` passes for the project headers in C2y mode.
- `mira` builds cleanly with the default C2y `-Weverything -Werror` Makefile
  flags.
- `just.c`, `fdate.c`, and `menudriver.c` also compile cleanly with the warning
  profile.
- `make cxx` builds cleanly with `clang++` as C++26.
- `make zig-cc` builds cleanly with `zig cc`.
- `make zig-cxx` builds cleanly with `zig c++`.
