# Mira performance roadmap

This document is an implementation plan for improving Mira's performance without
changing Miranda language semantics, observable REPL behavior, lazy evaluation,
error ordering, or supported platform scope. The production target is macOS on
Apple Silicon.

## Working rules

Complete the milestones in order unless profiling demonstrates that a later
milestone dominates runtime. Each milestone must leave the repository in a
passing state.

For every optimization:

1. Record a reproducible baseline before changing code.
2. Add or extend a benchmark that represents the workload being optimized.
3. Preserve a correctness test alongside the benchmark.
4. Compare `ns/op`, `B/op`, and `allocs/op` using multiple benchmark samples.
5. Run `make verify` before considering the milestone complete.
6. Reject changes that improve a microbenchmark by weakening laziness, interrupt
   handling, overflow behavior, type safety, diagnostics, or streamed output.

Use a stable machine with background activity minimized. Record the Go version,
commit, architecture, and command with every result. Prefer:

```sh
go test ./internal/application -run '^$' -bench . -benchmem -count 10 > before.txt
# apply the implementation
go test ./internal/application -run '^$' -bench . -benchmem -count 10 > after.txt
benchstat before.txt after.txt
```

If `benchstat` is unavailable, retain both raw result files and compare medians.
Do not add a non-Go build dependency.

## Representative workloads

Maintain benchmarks for at least these scenarios:

- cold startup with an empty `script.m`;
- startup with a valid compiled artifact;
- parsing and typechecking a large Miranda source file;
- `fib 22` and `fib 32` using pattern equations;
- `sum [1..1000000]`;
- `reverse [1..1000000]`;
- `take 100000 [1..]` with streamed rendering;
- nested `map`, `filter`, `foldl`, and `foldr` calls;
- repeated evaluation of the same REPL expression;
- a large integer arithmetic workload;
- a pattern-heavy recursive function;
- interruption of an infinite computation or output stream.

Store Go benchmarks beside the owning package. Test fixtures belong under
`testdata/`. Benchmarks must validate their result so an incorrect fast path
cannot appear as a performance improvement.

## Milestone 1: establish profiles and budgets

### Objective

Create a trustworthy baseline and identify the actual CPU and allocation
hotspots before changing evaluator architecture.

### Implementation

- Expand `internal/application/performance_test.go` to cover the representative
  workloads above.
- Add startup benchmarks in `internal/commandapp` or the narrowest package that
  can exercise boot behavior without spawning unnecessary processes.
- Capture CPU and memory profiles for Fibonacci, large-list processing, startup,
  and repeated REPL evaluation.
- Document the top functions by CPU time, allocation count, and retained bytes.
- Establish non-flaky performance budgets. Budgets should detect order-of-
  magnitude regressions rather than minor machine noise.

Example profiling commands:

```sh
go test ./internal/application -run '^$' -bench BenchmarkEvaluatePatternFib32 \
  -benchtime 5s -cpuprofile cpu.out -memprofile mem.out
go tool pprof -top cpu.out
go tool pprof -top -alloc_objects mem.out
```

### Completion criteria

- Every representative workload has a correctness-checking benchmark.
- Baseline results and the top measured bottlenecks are recorded in this file or
  a linked results document.
- `make verify` passes.

### Baseline recorded 2026-08-02

Environment: Apple M4, `darwin/arm64`, Go toolchain selected by `go.mod`, commit
`99304e1`. Results are medians of three one-iteration samples; these workloads
are intentionally large, so later comparisons must use the same benchmark
arguments.

| Workload | ns/op | B/op | allocs/op |
| --- | ---: | ---: | ---: |
| Pattern Fibonacci 32 | 581,210,542 | 20,880 | 104 |
| Cold startup | 12,457,083 | 138,121,872 | 10,376 |
| Warm startup | 11,932,541 | 138,119,912 | 10,369 |
| Parse and typecheck 1,000 definitions | 12,788,708 | 32,932,624 | 137,274 |
| Repeated `sum [1..100]` | 55,583 | 117,616 | 900 |
| `sum [1..1000000]` | 215,510,667 | 984,130,728 | 5,000,433 |
| 256-bit arithmetic | 57,084 | 96,504 | 480 |
| `reverse [1..1000000]` | 218,494,750 | 1,896,202,208 | 3,000,478 |
| `take 100000 [1..]` forced to its last item | 15,053,250 | 107,486,232 | 300,438 |
| Higher-order list pipeline | 62,515,375 | 206,703,192 | 1,050,834 |
| Pattern matching over 1,000 items | 62,399,042 | 209,403,280 | 58,037 |

Initial regression budgets are deliberately loose: no listed workload may
exceed 2x its baseline median without an explicit explanation. Targeted
milestones must improve their primary workload by at least 10% or reduce its
allocations by at least 20%; Milestone 2 retains its stronger 2x Fibonacci goal.

The Fibonacci CPU profile attributes 40.15% flat time to `evalFastScalar`,
18.94% to compiled unary-clause dispatch, 10.35% to `strconv.ParseUint`, and
6.31% to `strconv.ParseInt`. This makes repeated interpretation and numeric
literal parsing the first measured optimization target.

## Milestone 2: broaden scalar specialization

### Objective

Extend the existing integer fast path so simple numeric Miranda code avoids the
general AST evaluator.

### Implementation

- Refactor scalar compilation out of the general evaluation loop into a small,
  testable component.
- Support unary and binary numeric functions, comparisons, guards, nested calls,
  and tail positions used by common recursive functions.
- Preserve checked small-integer overflow and fall back to arbitrary precision
  arithmetic when required.
- Never eagerly evaluate an argument merely to attempt specialization. A failed
  fast-path match must preserve call-by-need behavior.
- Add counters or test hooks that prove benchmarks use the specialized path.

### Completion criteria

- Pattern-equation Fibonacci and comparable numeric workloads improve by at
  least 2x over the Milestone 1 baseline, unless profiling shows they are already
  below the agreed budget.
- Existing call-by-need, overflow, interrupt, and error tests pass.
- Unsupported expressions reliably fall back to the general evaluator.

## Milestone 3: cache REPL parsing and typing

### Objective

Avoid repeated front-end work for identical expressions and stable session
definitions.

### Implementation

- Add a bounded cache owned by the interpreter session, not a package global.
- Key expression entries by source text and the generation of the active type
  environment.
- Increment the generation whenever scripts, includes, REPL definitions,
  settings affecting parsing, or standard-library state change.
- Cache parsed syntax and inferred type information only when it is immutable or
  defensively copied.
- Set an explicit maximum entry or byte count and use deterministic eviction.
- Do not cache runtime values or failures whose result can depend on external
  state.

### Completion criteria

- Repeated expression evaluation shows a measurable reduction in allocations
  and front-end time.
- Editing, reloading, or defining a function invalidates affected entries.
- Two interpreter instances cannot observe each other's cache entries.

## Milestone 4: resolve names to symbol IDs

### Objective

Remove repeated string hashing and comparison from hot evaluation paths.

### Implementation

- Reuse or extend the existing symbol table to assign stable numeric IDs during
  compilation.
- Resolve globals, locals, constructors, and operators before evaluation.
- Keep source names in diagnostic metadata so messages and queries remain
  unchanged.
- Replace hot `map[string]` environments with symbol-indexed storage or a hybrid
  structure whose fallback handles dynamic session state.
- Benchmark lookup-heavy recursion before choosing arrays, slices, or compact
  maps.

### Completion criteria

- Profiles show string-based lookup is no longer a leading evaluator cost.
- Shadowing, includes, aliases, recursive groups, REPL definitions, and `?`/`??`
  queries retain current behavior.

## Milestone 5: introduce an executable instruction IR

### Objective

Lower parsed Miranda expressions into a compact representation that avoids
recursive interpretation of verbose syntax nodes.

### Implementation

- Design a small instruction or compact-expression IR for application, literal,
  local/global load, constructor, branch, pattern match, thunk creation, and
  return.
- Keep lowering separate from parsing, type inference, and execution.
- Start with straight-line expressions and fall back to the AST evaluator for
  unsupported nodes.
- Add disassembly support for tests and diagnostics; it need not be user-facing.
- Expand coverage incrementally until profiles justify removing fallbacks.

### Completion criteria

- The IR has deterministic golden or structural tests.
- Results match the AST evaluator across a representative corpus.
- At least the dominant expression shapes execute through the IR.
- CPU profiles show reduced recursive evaluator and syntax-node overhead.

## Milestone 6: specialize thunk storage

### Objective

Reduce closure allocation and indirect calls while preserving graph reduction
and call-by-need semantics.

### Implementation

- Measure the distribution of thunk kinds before selecting representations.
- Replace general closures where practical with tagged variants for constants,
  global references, applications, evaluated values, and black holes.
- Keep memoization and recursive-cycle behavior explicit.
- Ensure concurrent interrupt handling cannot expose partially evaluated state.
- Consider pooling only after representation changes are benchmarked; pooling
  can increase retention and GC cost.

### Completion criteria

- Allocation profiles show fewer closures or heap objects per reduction.
- Call-by-need tests prove an argument is evaluated at most once and unused
  arguments remain unevaluated.
- Recursive black-hole and interruption behavior is tested.

## Milestone 7: unify strings and character-list operations

### Objective

Avoid expensive materialization when Miranda code consumes strings as lists of
characters.

### Implementation

- Define an iterator abstraction that can traverse both compact strings and
  general lazy lists.
- Update list consumers such as `reverse`, `map`, `fold`, `take`, `drop`,
  comparison, and rendering where profiling justifies it.
- Preserve Unicode character semantics rather than treating UTF-8 bytes as
  Miranda characters.
- Materialize a character list only when program behavior requires its graph
  structure.
- Add tests mixing strings, explicit character lists, infinite lists, and
  partially consumed results.

### Completion criteria

- Large string operations allocate materially less memory.
- String/list behavior remains observationally compatible with Miranda.
- UTF-8, empty strings, comparison, and streaming tests pass.

## Milestone 8: reuse evaluator scratch storage

### Objective

Reduce short-lived allocations for calls, pattern matching, and list traversal.

### Implementation

- Profile call frames, environments, binding maps, argument slices, and iterator
  state separately.
- Prefer stack values and reusable slices before introducing `sync.Pool`.
- Clear references before returning pooled objects to avoid retaining graphs.
- Place upper bounds on retained capacity; discard unusually large buffers.
- Keep pools interpreter-local when global reuse would complicate isolation.

### Completion criteria

- Allocation count improves on pattern-heavy and higher-order benchmarks.
- Retained heap size does not grow after repeated large evaluations.
- Race tests and interpreter-isolation tests pass.

## Milestone 9: specialize standard higher-order functions

### Objective

Provide fast execution for common library pipelines while keeping ordinary
Miranda definitions authoritative and queryable.

### Implementation

- Prioritize functions supported by profiles: likely `map`, `filter`, `foldl`,
  `foldr`, `sum`, `product`, `take`, `drop`, `reverse`, and `|>`.
- Select optimized implementations after loading `stdenv.m`, while preserving
  the Miranda source locations used by `?` and `??`.
- Allow user and REPL definitions to shadow optimized standard functions.
- Fuse operations only when laziness, error timing, and interruption remain
  equivalent. Do not consume more of an infinite list than requested.
- Add fast paths for known function values or instruction IDs rather than source
  string matching where possible.

### Completion criteria

- Large finite-list and finite-prefix-of-infinite-list benchmarks improve.
- `Ctrl-C` remains responsive during optimized operations and streamed output.
- Queries still show the definitions in `stdenv.m`.

## Milestone 10: persist optimized compiled artifacts

### Objective

Make `.x` artifacts eliminate repeated parsing, type inference, symbol
resolution, and lowering during startup.

### Implementation

- Version the artifact format explicitly.
- Store dependency hashes, exported type profiles, resolved symbols, and the
  executable IR needed at runtime.
- Validate the source, compiler version, target, standard-library version, and
  every dependency before accepting an artifact.
- Treat malformed, truncated, incompatible, or stale artifacts as cache misses;
  never crash or execute unvalidated data.
- Write artifacts atomically through a temporary file and rename.
- Keep `make clean` responsible for removing all `.x` files.

### Completion criteria

- Warm startup is measurably faster than cold startup.
- Valid artifacts avoid parsing and type inference, demonstrated by test hooks or
  profiles.
- Stale and corrupted artifact tests pass.
- Reproducible builds and source-only startup remain supported.

## Final acceptance

After completing all milestones:

```sh
make verify
go test ./internal/application -run '^$' -bench . -benchmem -count 10
```

Compare final results to Milestone 1. Publish a table containing baseline and
final `ns/op`, `B/op`, and `allocs/op` for every representative workload. Note
any workload that regressed and either fix it or document a justified tradeoff.

The work is complete only when correctness gates pass, performance gains are
measured rather than assumed, and no optimization introduces a Python build
dependency or expands the supported production platform beyond macOS on Apple
Silicon.
