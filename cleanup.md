# Cleanup Roadmap

This document outlines a staged plan to simplify the C codebase, make it more
maintainable and extendable, reduce warning suppressions, and improve security.
The current default baseline is a warning-clean strict Clang C2y build through
`make check`. C++26, `zig cc`, and `zig c++` compatibility targets remain
available for explicit release or portability checks, but routine cleanup should
use the faster Clang C2y path. The next work should focus on removing root
causes that are currently hidden behind warning suppressions or historical
coding patterns.

## Goals

- Keep `make check` passing after every step.
- Reduce warning suppressions by replacing risky patterns with clearer APIs.
- Separate generated code from handwritten code so cleanup does not churn parser
  output unnecessarily.
- Make ownership, lifetime, and mutation boundaries visible in headers.
- Reduce global state and macro-heavy coupling before larger feature work.
- Improve input, path, command, and buffer handling so the interpreter and tools
  are safer to run on untrusted files.

## Guardrails

- Work in small patches that each preserve behavior.
- Prefer integration tests through `mira` for lexer, parser, typechecker,
  translator, reducer, and standard-library behavior.
- Do not hand-edit checked-in generated parser output except as part of a
  documented regeneration step.
- When replacing macros or global state, first add tests that exercise the old
  behavior.
- Treat security hardening as behavior-preserving unless a behavior is clearly
  unsafe and intentionally changed.

## Phase 1: Inventory And Baseline

1. Capture the current suppressed warning list from `Makefile` and classify each
   warning as mechanical, generated-code-only, historical-portability, or real
   code smell.
2. Add a short `warnings.md` or a section in this file that maps each remaining
   `-Wno-*` flag to the code pattern that requires it.
3. Add a scriptable warning audit target that builds once with the current
   suppression list and once with selected suppressions removed.
4. Keep generated files, handwritten files, and local artifacts clearly
   separated in status output and documentation.

Phase 1 has started. The warning inventory lives in `warnings.md`, and
`make warning-audit` provides the first repeatable audit target.

## Phase 2: Unsafe String And Buffer Handling

The largest security and maintainability issue is manual string construction.
The code still contains many uses of `strcpy`, `strcat`, and `sprintf` against
global or fixed-size buffers.

1. Introduce small local helpers for checked string copying, concatenation, and
   formatting. Prefer `snprintf`-style APIs that return failure on truncation.
2. Replace command and path construction in `steer.c`, `lex.c`, `data.c`,
   `menudriver.c`, `reduce.c`, and `big.c`.
3. Make buffer sizes explicit at call sites. Avoid helpers that infer capacity
   from a pointer.
4. Convert repeated path-building idioms into named helpers, for example
   library path, user rc path, object-file path, and manual path construction.
5. Add tests for long paths, long identifiers, long string output, missing
   `HOME`, missing `miralib`, and truncation/error handling.

Expected warning impact:

- Remove or reduce `-Wno-unsafe-buffer-usage`.
- Reduce conversion and signedness suppressions around string lengths.
- Remove several comments that exist only to silence compiler warnings.

## Phase 3: Command Execution Hardening

`menudriver.c` and parts of `steer.c` build shell commands by concatenating
strings. This is fragile and unsafe when paths or environment-derived values
contain shell metacharacters.

1. Inventory every `system()` and command-building path.
2. Replace shell command strings with direct process execution where practical.
   Use `fork`/`exec` on POSIX paths instead of `system()`.
3. If shell execution must remain, add quoting helpers and tests for spaces,
   quotes, semicolons, and other metacharacters in paths.
4. Validate environment-derived values such as editor, viewer, pager, `HOME`,
   and `miralib`.
5. Fail closed on malformed paths or commands, with clear user-facing errors.

Expected security impact:

- Reduce command injection risk.
- Make behavior predictable for paths containing spaces or punctuation.
- Make the manual browser safer to invoke from unusual directories.

## Phase 4: Header And Module Boundaries

Many modules expose broad globals and depend on side effects in other modules.
This makes changes risky and keeps warnings tied to global namespace pollution.

1. Split `data.h` into smaller public headers:
   - runtime value representation;
   - heap allocation and object constructors;
   - identifier dictionary APIs;
   - dump/undump APIs;
   - diagnostic and output helpers.
2. Move file-local globals and helpers to `static` where possible.
3. Add public accessor functions where direct global mutation is not required.
4. Stop exporting implementation-only globals through headers.
5. Update the header syntax gate to include each public header independently.

Expected warning impact:

- Reduce `-Wno-missing-variable-declarations`.
- Reduce `-Wno-missing-prototypes`.
- Reduce accidental namespace collisions in C++ compatibility builds.

## Phase 5: Global State Reduction

The interpreter currently relies on shared mutable globals across startup,
lexing, parsing, typechecking, translation, reduction, and output. Full
reentrancy is not required immediately, but state should be grouped so ownership
is visible.

1. Define context structs for coherent state groups:
   - runtime heap and object store;
   - lexer input and dictionary state;
   - compiler/typechecker state;
   - reducer/evaluation state;
   - process configuration and paths.
2. Start with leaf modules where the change is contained, such as `big.c` and
   standalone utilities.
3. Move initialization and reset functions onto those context structs.
4. Keep compatibility shims during migration so behavior changes are isolated.
5. Add tests around `/reload`, script loading, imports, interrupts, and command
   loop state reset before moving shared compiler state.

Expected maintainability impact:

- Easier feature extension without hidden cross-module mutation.
- Cleaner tests because state can be initialized explicitly.
- Fewer accidental dependencies on startup order.

## Phase 6: Heap Representation And Macro Cleanup

The heap and object representation rely heavily on lvalue macros such as
`hd(x)`, `tl(x)`, and constructor macros. These are fast, but they obscure
types, bounds, and side effects.

1. Document all heap invariants next to the representation definitions.
2. Replace low-risk constructor macros with `static inline` functions.
3. Add debug-only bounds checks for heap indexes and atom/object boundaries.
4. Keep hot lvalue accessors as macros until tests and profiling justify a
   safer replacement.
5. Add reducer and dump/undump tests before changing representation internals.

Expected warning impact:

- Reduce macro-expansion suppressions over time.
- Improve static analysis precision.
- Make optimizer-sensitive garbage collection behavior easier to reason about.

## Phase 7: Generated Code Boundary

Generated files such as `y.tab.c`, `y.tab.h`, and `combs.h`
increase diff volume and make cleanup hard to review.

1. Document the exact generation commands and tool versions.
2. Add a `make regenerate` target that regenerates parser and combinator files.
3. Add a check target that fails if generated files are stale.
4. Avoid broad formatting churn in generated output unless generation itself is
   updated to emit that style.
5. Keep generated-code warning suppressions separate from handwritten-code
   warning suppressions.

Expected maintainability impact:

- Smaller, more reviewable cleanup patches.
- Clearer distinction between real source changes and generated churn.

## Phase 8: Error Handling And Diagnostics

Error paths are currently mixed between global flags, direct printing, exits,
and long-running interpreter state.

1. Create a small diagnostic API for warnings, errors, and fatal failures.
2. Replace direct `printf`/`fprintf` warning calls where the warning belongs to
   the interpreter diagnostics stream.
3. Separate user-facing Miranda diagnostics from internal runtime failures.
4. Make allocation failure paths consistent and include the failed subsystem.
5. Add tests for representative syntax, type, runtime, file, and allocation-like
   errors where feasible.

Expected maintainability impact:

- Easier tests for warnings and errors.
- Less duplicated formatting.
- Cleaner future integration with tooling or editor support.

## Phase 9: Memory Ownership And Allocation

Allocation currently uses raw `malloc`, `calloc`, and `realloc` in many modules,
often with implicit ownership rules.

1. Introduce checked allocation wrappers that take element counts and sizes.
2. Replace open-coded multiplication in allocations with overflow-checked
   helpers.
3. Add ownership comments to public APIs that return allocated memory or retain
   caller-provided pointers.
4. Avoid returning pointers to mutable global scratch buffers from new APIs.
5. Add cleanup paths for standalone tools so sanitizers can distinguish leaks
   from intentional interpreter-lifetime allocations.

Expected security impact:

- Lower risk of allocation overflow.
- Clearer ownership rules.
- Better sanitizer signal.

## Phase 10: Warning Suppression Burn-Down

After the structural cleanup above, remove suppressions incrementally.

Suggested order:

1. `-Wno-missing-prototypes`
2. `-Wno-missing-variable-declarations`
3. `-Wno-unsafe-buffer-usage`
4. `-Wno-disabled-macro-expansion`
5. `-Wno-shadow`
6. conversion and signedness suppressions
7. generated-code-only suppressions moved behind generated targets

For each suppression:

1. Remove the flag locally.
2. Build with `make check`.
3. Fix warnings in one ownership area at a time.
4. Add tests when the fix changes control flow, parsing, evaluation, path
   handling, or user-visible output.
5. Commit or record the suppression removal separately from unrelated refactors.

## Phase 11: Test Expansion

The existing smoke suite is a good start, but cleanup needs broader behavior
coverage.

1. Add tests for long names, long strings, long paths, and Unicode edge cases.
2. Add tests for file loading, `%include`, `%insert`, and relative path
   handling.
3. Add tests for dump/undump and object-file invalidation.
4. Add tests for type errors, unused definitions, export list warnings, and
   parser warnings.
5. Add negative tests for unsafe or malformed environment configuration.
6. Add standalone utility tests for `just`, `fdate`, and `menudriver` where
   feasible.

## Phase 12: Static Analysis And Sanitizers

1. Add optional targets for AddressSanitizer and UndefinedBehaviorSanitizer.
2. Add a non-fatal static-analysis target, such as `clang --analyze`, once the
   main warning profile is stable.
3. Run sanitizer builds against the smoke suite and selected longer examples.
4. Track sanitizer findings in this file or a dedicated issue list until fixed.
5. Keep sanitizer flags out of the default release build.

## Suggested First Pull Requests

1. Add checked string formatting helpers and replace simple `sprintf` calls in
   `big.c` and `reduce.c`.
2. Replace command construction in `menudriver.c` with safer process execution
   or strict shell quoting.
3. Split generated-code warning handling from handwritten-code warning handling.
4. Make private helper functions and globals `static` module by module.
5. Add long-input and unsafe-path smoke tests before changing path handling.

## Definition Of Done

The cleanup effort should be considered complete when:

- `make check` passes without broad project-wide suppressions for missing
  prototypes, missing globals, unsafe buffers, and shadowing.
- Generated-code suppressions are isolated from handwritten source checks.
- All public headers can be included independently.
- Unsafe string and command construction are removed or contained behind checked
  helpers.
- Major mutable state groups are explicit and documented.
- Security-sensitive behavior has negative tests.
- New features can be added without depending on undocumented global startup
  order.
