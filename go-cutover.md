# Miranda Go Production Cutover Plan

## 1. Purpose

This document is the execution plan for turning the current Go translation into
the production Miranda interpreter and cutting the project over from the Zig
executable to a Go executable named `mira`.

It is written for an autonomous implementation agent. Follow the phases in
order, satisfy every entry and exit condition, and commit and push after each
milestone passes. Do not interpret the existing translation status as evidence
of production completeness.

The current repository has:

- a complete mechanical translation ledger (`0 pending units`);
- Go packages corresponding to the planned package DAG;
- stage oracle plumbing and selected stage implementations;
- a Zig reference implementation and extensive parity fixtures;
- no production Go `mira` command;
- placeholder behavior in critical Go paths, including setup, parsing,
  evaluation, boot, and the REPL.

The migration is complete only when the Go `mira` binary independently runs
Miranda programs with the required observable behavior, passes the complete
parity and production gates, is the default installed binary, and can be built
without compiling Zig.

## 2. Non-negotiable outcome

At cutover, all of the following must be true:

1. `go build -o zig-out/bin/mira ./cmd/mira` produces the production binary on
   macOS ARM64.
2. The binary starts with the checked-in `miralib`, loads `prelude` and
   `stdenv.m`, loads user scripts, accepts interactive and piped input, and
   produces reference-compatible results.
3. The Go binary passes every applicable golden, regression, differential,
   integration, stress, interruption, dump, and platform-contract test.
4. The Go binary does not call, embed, execute, or dynamically load the Zig
   interpreter. Oracle commands may use the pinned reference only in tests.
5. The normal production build does not require Zig.
6. Only macOS ARM64 is supported. Other operating systems or architectures fail
   at build time with the repository's explicit unsupported-target mechanism.
7. The Go race detector passes all tests that exercise concurrent interpreter
   instances and platform services.
8. Generated files are reproducible and the working tree remains clean after
   generation and tests.
9. Installation, documentation, version reporting, and release packaging point
   to the Go binary.
10. The Zig implementation remains available as a reference until the final
    cutover commit passes and is tagged. Its later deletion is a separate,
    explicitly authorized cleanup.

## 3. Source of truth and precedence

Use these sources in this order when behavior is unclear:

1. Observable output, error output, exit status, filesystem effects, and signal
   behavior of the pinned reference described by
   `tests/reference/manifest.json`.
2. Existing fixtures in `tests/golden`, `tests/oracle/fixtures`, the regression
   corpus, and `tests/mira_tests.zig`.
3. The production Zig implementation under `src`.
4. Machine-readable rules in `spec/go_translation_rules.json` and the package
   mapping in `spec/go_translation_manifest.json`.
5. Historical comments and prose documentation.

Never make a fixture pass by replaying its expected output, detecting fixture
filenames, or invoking the reference implementation from production Go code.
The Go implementation must compute the result from the supplied source and
input.

If the reference and a checked-in expected file disagree, stop that milestone,
reproduce the discrepancy, and fix the fixture or document an intentional
compatibility change before continuing.

## 4. Supported scope

### Included

- macOS ARM64 command-line Miranda interpreter;
- interactive and non-interactive REPL operation;
- source loading, literate source, directives, typechecking, lowering, graph
  evaluation, printing, standard library loading, `.x` dumps, commands, and
  batch modes used by the current tests;
- `-lib`, `MIRALIB`, `.mirarc`, script argument, `-exports`, `-sources`, and
  `-make` behavior present in the reference;
- file, process, signal, editor, terminal, UTF-8, and timing behavior behind the
  typed platform boundary;
- `fdate`, `just`, and `menudriver` only to the extent required by build,
  installation, library generation, or current supported workflows.

### Excluded

- Linux and non-ARM64 support;
- semantic redesign of Miranda;
- performance rewrites that change observable laziness or error timing;
- deletion of the Zig reference before cutover;
- broad repository cleanup unrelated to the Go production path.

## 5. Current-state warning

`spec/go_translation_status.json` records whether package translation units
passed their narrow translation checks. It does **not** prove production
behavior. In particular, the current Go implementation includes behavior such
as:

- `application.Interpreter.Setup` returning success without initialization;
- `syntaxfront.Parse` returning an empty script for non-empty token streams;
- `evaluation.Evaluator.Reduce` returning its input unchanged;
- `application.Interpreter.REPL` echoing non-command input;
- no `cmd/mira` package.

Do not reset the completed translation ledger. Add a distinct cutover ledger so
the two concepts cannot be conflated.

## 6. Required cutover tracking

Before production implementation, add `spec/go_cutover_status.json` with this
schema:

```json
{
  "schema": 1,
  "milestones": {
    "00-contract": "pending",
    "01-production-command": "pending",
    "02-runtime-graph": "pending",
    "03-source-parser": "pending",
    "04-semantics-lowering": "pending",
    "05-evaluator": "pending",
    "06-module-dump-boot": "pending",
    "07-repl-commands": "pending",
    "08-platform-integration": "pending",
    "09-full-parity": "pending",
    "10-production-packaging": "pending",
    "11-cutover": "pending"
  }
}
```

Allowed values are `pending` and `complete`. Add a validator at
`scripts/go_cutover.py` that:

- validates the schema and exact milestone keys;
- enforces ordered completion (no complete milestone after a pending one);
- runs or prints the verification commands associated with a milestone;
- fails if the old translation ledger has pending units;
- fails final validation if placeholder detectors match known production
  stubs;
- reports the first pending milestone;
- reports `Go production cutover verified` only when all milestones and final
  invariants pass.

The status change must be in the same commit as the implementation that passes
the milestone. Never mark a milestone complete in advance.

## 7. Working protocol for every milestone

For every milestone below:

1. Start from clean `main` synchronized with `origin/main`.
2. Read the mapped Zig source and adjacent Zig tests before editing Go.
3. Identify observable inputs, outputs, state transitions, errors, cleanup, and
   interruption points.
4. Add or strengthen Go unit tests first. Tests must fail for the current
   placeholder behavior.
5. Implement the smallest complete vertical behavior needed by the milestone.
6. Run the package tests and relevant oracle stages.
7. Run `go test ./...`, `go test -race ./...`, the DAG check, and generation
   check.
8. Run the milestone's end-to-end candidate tests against a newly built Go
   binary.
9. Run `git diff --check` and confirm generation leaves no diff.
10. Change only the current cutover milestone from `pending` to `complete`.
11. Re-run the milestone validator.
12. Commit with a message describing the completed production capability.
13. Push `main` and verify local `HEAD` equals `origin/main`.

Do not commit a milestone when tests are skipped, flaky, timing out, or passing
only with fixture-specific code. Fix the cause and rerun it.

The baseline checks after every milestone are:

```sh
go test ./...
go test -race ./...
go run ./cmd/checkdag
go generate ./...
git diff --exit-code
python3 scripts/phase13_translation.py
python3 scripts/go_cutover.py
git diff --check
```

Run every implemented stage oracle after each package-boundary change:

```sh
for stage in source lex layout parse module typecheck lower reduce dump; do
  python3 tests/oracle/oracle.py verify \
    --stage "$stage" \
    --producer 'go run ./cmd/miracula-go-oracle'
done
```

## 8. Milestone 00 — Production contract and honest gates

### Goal

Create enforceable production-completion criteria before adding more behavior.

### Work

- Add the cutover status and validator described above.
- Add a placeholder audit that checks production paths, not ordinary legitimate
  zero/nil returns. At minimum it must reject the known placeholder forms in
  setup, parser, reducer, boot, and REPL once their milestone is complete.
- Add a candidate build helper or build target that always builds
  `./cmd/mira` to a fresh path before running end-to-end tests.
- Extend `scripts/run_go_differential.py` so its candidate can be built by the
  gate or passed explicitly, and ensure it never silently uses `zig-out/bin/mira`
  left by a Zig build.
- Add a candidate identity test. It must prove the tested executable is the Go
  build (for example through build metadata or `mira --build-info`) without
  changing normal reference-compatible output.
- Add timeouts and output limits to all subprocess-based candidate tests.
- Document how compatibility exceptions are approved. Each exception must have
  a checked-in reason, focused test, and expiry/cutover decision.

### Acceptance

- The validator reports `00-contract` as the first pending milestone before the
  status update and `01-production-command` afterward.
- Deliberately restoring any known placeholder makes the corresponding future
  milestone check fail.
- Pointing the differential runner at a missing or Zig candidate fails closed.
- All baseline checks pass.

## 9. Milestone 01 — Production command and configuration

### Goal

Produce a real Go process with stable startup, argument parsing, error handling,
and dependency injection, even before the language pipeline is complete.

### Work

- Add `cmd/mira/main.go` as the sole Go process composition root.
- Construct `platformsvc.NativeServices`, `commandapp.Command`, streams,
  cancellation, and signal handling there.
- Move process exit selection to the command boundary. Internal packages return
  typed/wrapped errors and never call `os.Exit`.
- Implement version and build configuration in `internal/buildcfg`, generated
  or set by linker flags as appropriate. Match the reference release/version
  formatting.
- Port argument parsing and configuration precedence from `src/session/config.zig`
  and `src/session/boot.zig`:
  command flags, script selection, `-lib`, `MIRALIB`, home and library rc files,
  hush/verbosity, UTF-8, heap settings where still meaningful, and too-many-args
  failure.
- Define exit-code policy for usage errors, compilation/runtime errors,
  interrupts, and internal failures; verify against the reference.
- Ensure unsupported targets fail at compile time through
  `internal/platformsvc/target_unsupported.go`.
- Add black-box command tests that build and execute the Go binary in isolated
  temporary HOME and working directories.

### Acceptance

- `go build -o build/go-mira ./cmd/mira` succeeds on macOS ARM64.
- `build/go-mira --build-info` identifies a Go candidate.
- Version/help/invalid-option/too-many-arguments cases match expected streams
  and exit statuses.
- `GOOS=linux GOARCH=amd64 go build ./cmd/mira` fails for the explicit unsupported
  target reason.
- The command tests do not require Zig except when comparing to the reference.

## 10. Milestone 02 — Runtime values, heap, resources, and graph invariants

### Goal

Make `protocol` and `graphstore` capable of supporting the real compiler and
lazy evaluator without C pointers or hidden Zig behavior.

### Work

- Audit every symbol mapped to `protocol` and `graphstore` in
  `spec/go_translation_manifest.json` against its Zig implementation.
- Implement the complete value/tag model, checked conversions, cells, lists,
  identifiers, constructors, doubles, bignums, strings, files, streams, and
  stable resource IDs.
- Preserve exact combinator numbers and `.x` wire tags from canonical schemas.
- Implement heap allocation, mutation, checkpoint/restore, validation, explicit
  roots, and deterministic forced-collection hooks.
- Decide and document whether Go GC replaces graph collection or whether a
  logical graph collector remains necessary for Miranda semantics and heap
  limits. Preserve observable exhaustion, rollback, and resource-finalization
  behavior.
- Implement string interning and private-name semantics without unsafe native
  pointer encodings.
- Implement resource ownership and closing. Reset must deterministically close
  interpreter-owned resources.
- Port bignum arithmetic, floor division/modulo, powers, conversions, formatting,
  and overflow behavior.
- Add fuzz/property tests for codecs, cell operations, bignum laws, and
  checkpoint restoration.

### Acceptance

- Graph and protocol Zig unit cases have Go equivalents with the same vectors.
- `.x` canonical vectors round-trip and reject truncation, invalid tags, and
  trailing data.
- Two heaps can allocate, collect/reset, and mutate concurrently without shared
  state.
- Forced collection/checkpoint testing passes long-list and deep-graph cases.
- `go test -race ./internal/protocol ./internal/graphstore` passes.
- Source, lower, reduce, and dump oracle stages remain green.

## 11. Milestone 03 — Source, lexer, layout, directives, and parser

### Goal

Turn Miranda source bytes into a complete, source-positioned AST using one Go
front-end path.

### Work

- Replace the empty parser with the full grammar represented by `src/syntax`,
  `src/parser`, and their tests.
- Preserve raw source bytes, literate transformation, line/column mapping, tab
  expansion, UTF-8 behavior, and diagnostic spans.
- Implement all token forms: identifiers, operators, numeric bases and floats,
  characters, strings and escapes, comments, directives, punctuation, and EOF.
- Implement offside/layout rules, bracket interactions, guarded equations,
  `where`, definitions, type declarations, algebraic types, patterns, tuples,
  lists, ranges, comprehensions, and operator associativity/precedence.
- Implement every directive with one owner: include, export, free, insert, list,
  nolist, bnf, lex, and unknown-directive diagnostics.
- Eliminate duplicate or fallback parse paths. Production compilation and the
  oracle must call the same APIs.
- Add parser recovery only where the reference continues after diagnostics.
- Port all parser snapshots and add corpus tests that parse every `.m` and
  literate source file in `miralib` and `tests`.

### Acceptance

- Non-empty valid source produces a non-empty AST.
- Invalid source produces reference-compatible diagnostics with line and column.
- Source, lex, layout, and parse oracle stages pass without fixture replay.
- Every checked-in valid Miranda source parses successfully.
- Every existing syntax/lexical golden failure matches stdout, stderr, and
  status when run through the Go candidate.

## 12. Milestone 04 — Symbols, modules, types, matching, and lowering

### Goal

Compile the parsed AST into a typed, dependency-ordered graph ready for
evaluation.

### Work

- Implement symbol interning, scopes, fresh/private names, rebinding, and source
  ownership.
- Implement module inclusion, aliases, suppression, exports, free declarations,
  dependency discovery, duplicate/name-clash handling, and unused/bereaved-name
  diagnostics.
- Implement type representation, primitive types, substitutions, unification,
  occurs checks, generalization/instantiation, signatures, synonyms, algebraic
  types, constructor types, and error rendering.
- Implement pattern validation and compilation, guarded equations, lambda and
  local-definition lowering, list/tuple/comprehension lowering, and primitive
  resolution.
- Implement dependency SCC/order behavior deterministically.
- Ensure partial compilation rolls back heap/compiler/module state so a failed
  reload cannot poison a later compile.
- Make the module and typecheck oracles use these production APIs.

### Acceptance

- Module, typecheck, and lower stage oracles pass.
- Valid corpus files compile; negative type/module fixtures fail with matching
  diagnostics.
- Algebraic data, polymorphism, recursion, local definitions, includes,
  aliases, free declarations, and exports have end-to-end candidate tests.
- Repeated failure followed by corrected reload succeeds in the same interpreter.
- Compilation order and diagnostics are deterministic across fresh processes.

## 13. Milestone 05 — Lazy graph evaluator and runtime primitives

### Goal

Evaluate compiled Miranda graphs with reference-compatible lazy semantics,
printing, errors, interruption, and resource behavior.

### Work

- Replace identity reduction with real spine reduction and graph updates.
- Port every combinator and strictness rule from `src/eval`.
- Implement application, sharing, constructors, pattern failure, alternatives,
  recursion, deep evaluation, comparison, arithmetic, floating-point behavior,
  bignums, strings, lists, and tuples.
- Implement runtime primitives for file I/O, process execution, environment,
  timing, character classes, UTF-8, read values, output, and errors.
- Preserve lazy I/O ordering and the timing of division-by-zero, pattern, and
  type/runtime errors.
- Make reduction iterative where the Zig implementation avoids native stack
  growth. Test very deep application and tuple spines.
- Add context cancellation checks at bounded intervals in long reductions and
  blocking platform operations. Convert SIGINT into the reference-compatible
  interrupted evaluation behavior without corrupting interpreter state.
- Port output formatting exactly, including parentheses, strings, lists,
  doubles, bignums, algebraic values, and infinite/lazy values limited by user
  operations.
- Make the reduce oracle use the production evaluator.

### Acceptance

- Arithmetic, bignum, algebraic, list, string, tuple, recursion, lazy-list, and
  error golden cases pass through the Go candidate.
- Deep spine and Fibonacci stress cases complete without stack overflow.
- Cancellation/SIGINT stops evaluation and the next expression can run.
- Reduction is thread-safe across independent interpreters under `go test -race`.
- The reduce oracle passes and contains no special-case fixture lookup.

## 14. Milestone 06 — Compiler setup, modules, dumps, and boot

### Goal

Boot a self-contained Go interpreter from `miralib`, load scripts, and manage
compiled `.x` artifacts.

### Work

- Implement primitive registration and all compiler/runtime initial state from
  `src/compiler/setup.zig`.
- Implement Miranda library discovery and version validation using `-lib`,
  `MIRALIB`, install locations, and repository-local `miralib` in the same
  precedence as the reference.
- Load `prelude`, privatize its internal definitions, load `stdenv.m`, and build
  the primitive environment.
- Implement source/module load, include traversal, dependency ordering,
  recompilation checks, inode/path identity where observable, and rollback.
- Implement `.x` dump read/write, option/version checks, export fixup,
  public/private identifiers, and corrupted/stale dump fallback behavior.
- Ensure source-only startup works when dumps are absent and dump-assisted
  startup is behaviorally identical.
- Implement `-exports`, `-sources`, and `-make` using production compilation.
- Ensure generated `.x` files are never accidentally committed by tests and
  are removed by the documented clean target.

### Acceptance

- A clean Go binary loads `miralib/prelude` and `miralib/stdenv.m` and evaluates
  `1+2`.
- `script.m`, example programs, includes, literate scripts, and user-defined
  scripts load and evaluate.
- Dump oracle and canonical cross-language codec tests pass.
- Dump/undump round-trip, stale dump, corrupt dump, source-only boot, and reload
  tests pass.
- Batch modes match reference output and status.
- Startup does not execute the Zig binary or require Zig artifacts.

## 15. Milestone 07 — REPL, commands, editor, and session lifecycle

### Goal

Replace the echo REPL with the production interactive and piped Miranda
session.

### Work

- Implement the actual command loop: prompt/announcement rules, initial script,
  expression parsing, compilation, evaluation, output, errors, EOF, and quit.
- Port every supported slash command from `src/session/commands.zig`, including
  help, files, load/reload, edit, names/types, settings, manual actions, and any
  command used by the corpus or documented interface.
- Preserve command abbreviations, argument parsing, quoting, confirmation,
  output streams, and failure recovery.
- Implement terminal-aware behavior while keeping piped input deterministic.
- Integrate line editing/history only behind an interface so non-interactive
  tests need no terminal. If an external Go dependency is introduced, pin it,
  justify it, and verify license/maintenance suitability.
- Implement timing and GC-count suffixes where enabled.
- Ensure each interpreter owns its state and Reset/Close releases resources.

### Acceptance

- Piped cases produce no interactive prompt when the reference does not.
- Interactive announcement/prompt and quit behavior match the reference.
- Slash-command golden cases and command-focused integration tests pass.
- Multiple evaluations, compile failures, reloads, and interrupts leave the
  session usable.
- Two independent concurrent sessions pass isolation tests under the race
  detector.

## 16. Milestone 08 — Platform and external integration

### Goal

Complete all macOS ARM64 production boundaries without leaking POSIX or process
details into language packages.

### Work

- Finish `platformsvc.Services` for files, directories, terminal detection,
  processes, environment, clocks, signals, editor launch, permissions, and
  atomic file replacement.
- Ensure all OS calls are behind injected interfaces with deterministic test
  doubles.
- Preserve shell versus direct-exec semantics and quoting rules.
- Implement SIGINT lifecycle without signal-handler data races or unsafe graph
  mutation.
- Verify UTF-8 input/output and invalid byte behavior.
- Implement production versions of required developer tools or explicitly
  remove them from the Go release if they are build-time-only and replaced by
  Go/library workflows.
- Audit file descriptors, child processes, temporary files, and goroutines for
  leaks on success, errors, cancellation, and Reset.

### Acceptance

- Platform contract tests pass with native and fake services.
- File round-trip, append, readvals, process execution, editor invocation,
  terminal/piped behavior, and SIGINT integration cases pass.
- Repeated tests show no leaked goroutines, descriptors, or child processes.
- `go test -race ./...` passes.
- Unsupported builds fail explicitly and no Linux CI/release target exists.

## 17. Milestone 09 — Full behavioral and reliability parity

### Goal

Prove the Go candidate can replace the reference for the supported production
surface.

### Required gates

Build a fresh candidate, then run all of the following against that exact path:

```sh
mkdir -p build
go build -trimpath -o build/mira-go ./cmd/mira
python3 scripts/run_go_differential.py --candidate ./build/mira-go
go test ./...
go test -race ./...
go run ./cmd/checkdag
go generate ./...
git diff --exit-code
```

Adapt the existing Zig integration and golden runners, or add language-neutral
wrappers, so the Go candidate runs:

- every case in `tests/golden`;
- every case in `tests/regression.py`;
- every scenario in `tests/mira_tests.zig`;
- the full spine/deep-reduction corpus;
- standard library and example programs;
- forced-allocation/collection and rollback stress;
- SIGINT and timeout cases;
- `.x` protocol and dump round-trips;
- source-only and dump-assisted startup;
- two-interpreter concurrent isolation;
- deterministic repeated runs.

### Performance guardrails

Capture reference and Go measurements on the same host. Correctness is the
first requirement, but prevent accidental production regressions:

- standard library startup must remain within the existing timeout;
- regression cases must finish within their per-case limits;
- memory must remain bounded for long REPL and deep-spine tests;
- no benchmark may regress catastrophically without an approved, documented
  exception.

Add Go benchmarks for reducer hot paths, parser throughput, boot, Fibonacci,
large lists, bignums, and dump loading. Use profiles to guide optimization; do
not weaken semantics for benchmark results.

### Acceptance

- Every required case passes with zero skips and zero expected failures.
- Run the full suite at least three times from clean candidate builds.
- Run a sustained REPL/stress test long enough to expose leaks and stale state.
- No production Go file imports test/oracle fixture loaders or launches the
  reference executable.
- A clean clone with Go installed can build and test the production candidate;
  Zig is needed only for explicit reference-comparison gates.

## 18. Milestone 10 — Production build, installation, and release packaging

### Goal

Make the Go program the installable, documented Miranda product while retaining
an explicit reference build for comparison.

### Work

- Add repository build targets or scripts for:
  - Go production build;
  - Go tests and race tests;
  - reference Zig build;
  - full cross-language parity;
  - install and uninstall;
  - clean, including root-level `.x` files.
- Make the default `mira` artifact the Go binary. Rename the reference artifact
  to an unambiguous test-only name such as `mira-zig-reference`.
- Package `miralib`, version files, manuals, and any required helper tools at
  paths resolved by the Go binary.
- Set reproducible version/date/commit metadata and verify `--build-info`.
- Update README and build/install documentation with Go prerequisites,
  macOS ARM64 support, library discovery, tests, and troubleshooting.
- Update CI to build and test Go first, run race tests, verify generated files,
  and run pinned reference parity on macOS ARM64.
- Add a release smoke test that installs into a temporary prefix, runs the
  installed binary outside the repository, evaluates expressions and a script,
  and exercises help/version.
- Ensure archives do not include caches, temporary dumps, root `.x` files, or
  the Zig reference unless explicitly designated as a developer artifact.

### Acceptance

- Fresh build, install, installed smoke test, uninstall, and clean all pass.
- The installed `mira` identifies as the Go production build and finds its
  packaged `miralib` without repository-relative assumptions.
- Default documentation and CI refer to the Go binary.
- Release contents and licenses are reviewed and deterministic.

## 19. Milestone 11 — Cutover

### Goal

Make one auditable change that declares the Go binary production and preserves
a safe rollback point.

### Pre-cutover checklist

- [x] Milestones 00 through 10 are complete in order.
- [x] The full parity suite passed three consecutive clean builds.
- [x] Race tests passed.
- [x] Installed-package smoke tests passed.
- [x] No skipped, quarantined, or flaky required tests remain.
- [x] All nine stage oracles pass using production package paths.
- [x] Pinned reference hashes verify.
- [x] `main` was clean and synchronized with `origin/main` at the cutover start.
- [x] The last known-good Zig reference commit and binary hash are recorded.
- [x] A rollback procedure has been tested.
- [x] Release notes clearly state macOS ARM64-only support.

The machine-readable evidence and reference identity are recorded in
`spec/go_cutover_evidence.json`. Release scope and the tested rollback procedure
are documented in `docs/ReleaseNotes-GoCutover.md`.

### Cutover change

- Make Go `mira` the default build/install/release artifact.
- Keep the Zig reference accessible only through an explicitly named developer
  or parity target.
- Set `11-cutover` to complete.
- Run the complete final verification below.
- Commit and push the cutover as a single focused commit.
- Tag the commit only after remote CI passes.

### Final verification

```sh
python3 scripts/phase13_translation.py
python3 scripts/go_cutover.py
go test ./...
go test -race ./...
go run ./cmd/checkdag
go generate ./...
git diff --exit-code
go build -trimpath -o build/mira-go ./cmd/mira
python3 scripts/run_go_differential.py --candidate ./build/mira-go
```

Also run the language-neutral golden, integration, stress, signal, installed
smoke, and clean tests created in earlier milestones. Confirm:

```sh
test "$(git rev-parse HEAD)" = "$(git rev-parse origin/main)"
test -z "$(git status --porcelain)"
```

### Rollback

If post-cutover validation fails:

1. Do not rewrite published history.
2. Revert the default build/install selection to the recorded Zig reference in
   a new commit.
3. Preserve the failing Go candidate and logs as artifacts.
4. Add a regression test reproducing the failure.
5. Fix forward, rerun all milestone 09–11 gates, and perform a new cutover.

## 20. Package completion matrix

Use this matrix to prevent gaps. “Complete” means production behavior and
end-to-end use, not merely declaration coverage.

| Go package | Required production responsibility | Primary proof |
|---|---|---|
| `internal/protocol` | values, tags, errors, semantic types, `.x` codec, generated combinators | canonical vectors and cross-language codec tests |
| `internal/platformsvc` | typed macOS services, resources, signals, processes, UTF-8, parsing | native/fake contract and integration tests |
| `internal/graphstore` | heap/cells, roots, checkpointing, strings, resources, bignums, dumps | invariant, fuzz, forced-collection, dump tests |
| `internal/syntaxfront` | source, lexing, layout, directives, complete parser/AST | four front-end oracles and corpus parse |
| `internal/semantics` | modules, symbols, inference, matching, dependency order, lowering | module/type/lower oracles and negative corpus |
| `internal/evaluation` | lazy reducer, combinators, primitives, formatting, interruption | reduce oracle, golden corpus, spine stress |
| `internal/application` | owned interpreter state, setup, boot, library/script/dump lifecycle, REPL | startup, reload, isolation, integration tests |
| `internal/commandapp` | CLI configuration, commands, streams, exit statuses | black-box executable tests |
| `internal/devtools` | required release/build helper behavior | helper parity or explicit removal decision |
| `cmd/mira` | composition root and production process lifecycle | installed binary smoke and full differential |

## 21. Required test design rules

- Prefer black-box executable tests for user-visible behavior.
- Use table-driven unit tests for language rules and error cases.
- Use the same production API in tests, oracles, and the executable.
- Every bug found during migration gets a regression test before the fix.
- Every subprocess test has a timeout, captures both streams, limits output,
  checks exit status, and cleans temporary files.
- Tests use isolated HOME, working directory, environment, and library paths.
- Tests must not depend on execution order or repository-mutating artifacts.
- Do not update expected output merely because Go differs. First establish the
  reference behavior and explain any intentional compatibility decision.
- Fuzz codecs, parser token boundaries, dump corruption, and graph operations.
- Run race tests with two or more independent interpreter instances.
- Test cleanup after success, syntax/type/runtime failure, cancellation, EOF,
  and panic-equivalent internal errors.

## 22. Implementation rules

- Preserve the package DAG enforced by `cmd/checkdag`.
- Keep `cmd/mira` thin; production logic belongs in internal packages.
- Pass interpreter state explicitly. No mutable package-global interpreter.
- Use the representation, error, ownership, numeric, string, and platform rules
  in `spec/go_translation_rules.json`.
- Keep deterministic ordering whenever output or serialization is observable.
- Return errors to `commandapp`; only the command boundary prints fatal errors
  and chooses exit status.
- Use `context.Context` for cancellation, not global flags.
- Close resources deterministically; do not rely on finalizers for observable
  behavior.
- Do not use `unsafe` to recreate Zig pointer-tagging. Any unavoidable `unsafe`
  use requires a focused invariant test and written justification.
- Do not add cgo or a Zig bridge to production.
- Do not add Linux compatibility while completing this plan.
- Preserve exported translated symbols until full differential parity is
  achieved; API cleanup comes after cutover.

## 23. Commit and handoff policy

Each milestone may contain several commits, but every pushed commit must build
and pass its scoped tests. The final commit for a milestone must:

- include its tests and implementation;
- update exactly that cutover status entry;
- pass the milestone and baseline gates;
- leave no generated or temporary changes;
- be pushed before the next milestone starts.

Recommended milestone commit subjects:

```text
Define Go production cutover contract
Add production Go mira command
Complete Go runtime graph implementation
Complete Go source front end
Complete Go semantic compiler
Complete Go evaluator
Complete Go module and boot pipeline
Complete Go REPL and commands
Complete macOS platform integration
Prove Go behavioral parity
Package Go Miranda for production
Cut over mira production binary to Go
```

At any handoff, report:

- current commit and branch;
- first pending cutover milestone;
- tests last run and their results;
- any known failing case with exact reproduction command;
- whether the working tree is clean;
- whether `HEAD` equals `origin/main`.

## 24. Stop conditions

An autonomous agent must stop and request a decision only when:

- reference behavior is internally contradictory and cannot be resolved from
  fixtures or source;
- a required compatibility change would intentionally alter public behavior;
- a new third-party dependency creates a material licensing, security, or
  distribution decision;
- completion requires expanding supported platforms;
- a destructive repository operation or deletion of the Zig reference is
  proposed.

Ordinary implementation difficulty, failing tests, performance work, or a large
remaining scope are not stop conditions. Diagnose, add focused tests, fix, and
continue.

## 25. Definition of done

The Go migration is done only when:

- `scripts/go_cutover.py` reports all milestones complete;
- the freshly built Go `mira` passes the full pinned differential and all
  language-neutral suites;
- the production build/install/release path selects Go;
- the installed program works outside the checkout with packaged `miralib`;
- unsupported targets fail explicitly;
- the normal build is independent of Zig;
- the repository is clean and synchronized after generation and tests;
- remote CI passes on the cutover commit.

Zero pending entries in `spec/go_translation_status.json`, passing package
tests, or passing stage oracles alone are insufficient evidence of production
cutover.
