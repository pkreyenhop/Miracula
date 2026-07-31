# Go Migration Readiness Plan

## Purpose

This document is the execution plan for preparing Miracula for an automated,
unsupervised translation from Zig to Go.

The preparation is complete only when a translation agent can port one bounded
unit at a time, obtain an immediate automated pass/fail result for that unit,
and make no architectural, representation, ownership, platform, or compatibility
decisions of its own.

This plan was derived from the source code, build definition, test programs, and
observed test behavior. Existing design and migration Markdown files are not
inputs to this plan.

## Scope and non-goals

This plan contains work that is strictly required before an unsupervised Go
translation. It does not require general Zig cleanup, stylistic modernization,
renaming for taste, performance improvements, or replacement of working
algorithms with preferred Go libraries.

In particular:

- Preserve Miranda behavior.
- Preserve command-line, stdin, stdout, stderr, exit-status, signal, filesystem,
  and generated-file behavior.
- Preserve the `.x` file format byte for byte.
- Preserve the graph-reduction model and lazy semantics.
- Preserve bignum behavior and formatting during the initial port.
- Do not combine readiness work with the Go translation.
- Do not change observable behavior merely to make the implementation more
  idiomatic.

## Current baseline

At the time this plan was written:

- `zig build check --summary all` succeeds.
- The check runs 250 main tests, 66 parser tests, integration tests, smoke tests,
  SIGINT tests, and spine stress tests.
- The source import-cycle detector reports one strongly connected component
  containing 62 source files.
- The full `check` target does not run every compatibility suite.
- The differential regression program exits successfully when its reference
  binary is absent.
- Runtime graph cells can contain native stream pointers encoded as integers.
- Heap root discovery includes a conservative scan of the native stack.
- The raw `Word` representation remains pervasive.
- Most internal tests are Zig-only and cannot test an incomplete Go port.

Before changing readiness-sensitive behavior, record a clean baseline:

```sh
git status --short
zig version
zig build check --summary all
zig build strict --summary all
zig build test-golden --summary all
zig build test-regression --summary all
python3 scripts/import_cycles.py -v
python3 scripts/layer_check.py
```

If a required reference binary is absent, the baseline is incomplete. Do not
record a skipped differential run as a passing baseline.

## Rules for the preparation agent

1. Work in the phase order below. A later phase may depend on an earlier phase's
   representation or test harness.
2. Keep observable behavior unchanged unless a phase explicitly says otherwise.
3. Make small commits. Each commit must leave the mandatory readiness gate
   green.
4. Add the test or oracle before changing the behavior it will protect.
5. Never regenerate expected output from the implementation under test without
   comparing it with the pinned reference implementation.
6. Treat a skipped test, missing reference, missing fixture, timeout, or
   nondeterministic result as failure.
7. Do not silently add allowlist entries for cycles, layering violations,
   pointer conversions, raw values, or nondeterministic output.
8. Preserve unrelated working-tree changes.
9. When the source does not determine a behavior, stop and add a characterization
   test against the pinned reference before implementing a choice.
10. Do not start the Go port while any readiness exit criterion remains open.

## Definition of the mandatory readiness gate

Create one command:

```sh
zig build go-ready --summary all
```

It must run all of the following:

- Debug build and unit tests.
- Strict build and unit tests.
- Executable integration tests.
- Golden stdout/stderr/exit-status tests.
- Differential tests against the pinned reference executable.
- `.x` compatibility tests.
- SIGINT and process-control tests.
- Spine and forced-GC stress tests.
- Per-stage oracle verification.
- Determinism checks.
- Import-cycle check with a zero-cycle requirement.
- Layering/package-boundary checks.
- Prohibited-representation checks.
- macOS ARM64 platform contract tests.

The gate must fail when:

- the reference executable is missing or has the wrong checksum;
- an expected fixture is missing;
- a test is skipped;
- a child times out;
- output differs;
- a verifier cannot parse its input;
- a nondeterminism check differs between runs; or
- a readiness metric exceeds its zero/allowlisted target.

The gate is the definition of “Go ready.” Individual existing commands may
remain, but none may be required knowledge for the future translation agent.

The former `scripts/scorecard.sh` and its ratchet baseline were retired when
the earlier Zig-native cleanup plan was superseded. Its style and cleanup
metrics are not Go-readiness criteria. Use only `zig build go-ready --summary
all` for the readiness decision.

---

# Phase 1 — Pin a trustworthy executable specification

## 1.1 Pin the reference executable

The differential test currently looks for `./mira_original` and succeeds when
it is absent. Replace this convention with an explicit reference configuration.

Required work:

1. Choose a reference Zig commit that passes all existing tests.
2. Build reference binaries for supported host platforms in the required
   optimization mode.
3. Store each binary in an artifact location or document a reproducible,
   immutable retrieval mechanism.
4. Commit a manifest containing:
   - source commit;
   - Zig version;
   - target triple;
   - optimization mode;
   - binary SHA-256;
   - `miralib` content/version SHA-256;
   - fixture schema version.
5. Add a verifier that checks the binary and library hashes before tests run.
6. Change `tests/regression.zig` so missing or mismatched references fail.
7. Pass candidate binary, reference binary, and library directory as explicit
   arguments. Do not embed repository-relative candidate names in the runner.

Acceptance criteria:

- Removing the reference binary makes `zig build go-ready` fail.
- Replacing one byte in the reference binary makes it fail before executing
  comparisons.
- The differential runner cannot report success without executing at least one
  comparison.
- Its final output reports the number of executed, passed, failed, and skipped
  cases; skipped must be zero.

## 1.2 Make process comparisons complete

Every executable case must independently compare:

- stdout bytes;
- stderr bytes;
- process exit status;
- termination by signal;
- files created, modified, or removed;
- relevant file contents and permissions;
- timeout behavior.

Do not normalize output unless the normalization itself is specified and tested.
Existing filtering of trace or counter lines must be made explicit per suite.
User-visible whitespace must remain significant.

Acceptance criteria:

- A test fixture that changes only stderr fails.
- A fixture that changes only exit status fails.
- A fixture that creates an unexpected file fails.
- A hung candidate is killed and reported as failure.

## 1.3 Put all compatibility suites in the mandatory gate

Wire `test-golden` and `test-regression` into `go-ready`; do not assume
`zig build check` covers them. Retain the existing check target if other
workflows use it.

Acceptance criteria:

- Deliberately corrupting one golden file fails `go-ready`.
- Deliberately substituting a behaviorally different candidate fails
  `go-ready`.

---

# Phase 2 — Build language-neutral, per-stage oracles

An incomplete Go program cannot use Zig unit tests that import internal Zig
functions. Every future Go package therefore needs a fixture format and
standalone verifier that do not depend on Zig source types.

## 2.1 Define the oracle protocol

Create a versioned, deterministic interchange format. JSON Lines is acceptable
if byte encoding, field order, number representation, escaping, and ordering
are fixed. A small binary format is also acceptable, but it must be documented
and independently parseable.

Every record must include:

- schema version;
- stage name;
- case ID;
- input identity/hash;
- success or typed failure;
- deterministic stage payload;
- ordered diagnostics with severity, message, file, start/end offsets,
  line, and column where applicable.

Do not serialize pointer addresses, allocator details, timings, hash values,
or Zig type names.

## 2.2 Add stage drivers and fixtures

Create standalone drivers for these seams:

1. Source preprocessing:
   - literate-source transformation;
   - `%insert` expansion;
   - source positions and included-file identities.
2. Lexing and directives:
   - token kind;
   - exact token bytes/value;
   - source span;
   - directive payload;
   - diagnostics.
3. Layout:
   - complete post-layout token sequence and spans.
4. Parsing:
   - complete AST with explicit variant names;
   - stable node/child order;
   - diagnostics and recovery result.
5. Module and symbol processing:
   - resolved includes;
   - aliases;
   - exports;
   - private/fresh symbol identities represented by stable dense IDs.
6. Type inference/checking:
   - normalized type representation;
   - substitutions where externally relevant;
   - sorted diagnostics.
7. Lowering/code generation:
   - graph expressed using stable cell IDs and named tags, or the canonical
     `.x` bytes where appropriate.
8. Reduction:
   - result graph/value;
   - stdout/stderr/exit outcome;
   - reduction trace when needed to distinguish behavior.
9. Dump/load:
   - input bytes;
   - decoded protocol records;
   - re-encoded bytes;
   - reconstructed graph using stable IDs.

For every stage provide:

```sh
zig build capture-<stage>-oracle
zig build verify-<stage>-oracle
```

Capture commands are maintainer operations. Verification commands are mandatory
and read-only.

## 2.3 Cover errors, not only successful inputs

Each oracle corpus must include:

- empty input;
- minimum valid input;
- representative valid programs;
- every syntax/directive/tag variant;
- malformed and truncated input;
- integer and buffer boundaries;
- non-ASCII/byte-oriented source cases;
- nested includes/inserts;
- cycles and missing files;
- type errors;
- runtime errors;
- interrupts and child-process errors where relevant.

## 2.4 Prove that the oracle can validate a non-Zig producer

For each stage, make the verifier consume a file or subprocess output. It must
not call the Zig implementation directly to obtain “actual” results.

Acceptance criteria:

- A trivial external fixture producer can be substituted for the stage driver.
- Changing any semantic field in an actual record fails verification with the
  case ID and field-level difference.
- Every production package planned for Go maps to at least one stage verifier.
- A package can be translated and verified before the final Go executable
  exists.

---

# Phase 3 — Eliminate native pointers from graph values

The graph currently stores `Stream*` addresses as integer `Word` payloads.
This representation is not valid in ordinary Go and must be removed before
translation.

## 3.1 Inventory pointer-bearing values

Search for and classify every:

- `@intFromPtr`;
- `@ptrFromInt`;
- `os.ptrInt`;
- `os.ptrFrom`;
- integer cast of `Stream*` or another pointer;
- graph cell documented or used as a pointer wrapper.

For each site record:

- pointer type;
- graph tag/field used;
- owner;
- creation path;
- lookup path;
- close/free path;
- checkpoint/reset/GC behavior.

The inventory is complete only when automated search finds no unclassified
site.

## 3.2 Add an interpreter-owned resource table

Implement typed opaque IDs, at minimum:

```text
StreamID
```

If other pointer classes are discovered, give each a distinct ID type or use a
tagged `ResourceID`; do not use one untyped integer namespace.

The table must:

- allocate a stable nonzero ID;
- resolve an ID to the resource;
- distinguish missing, closed, and wrong-kind IDs;
- close a resource exactly once;
- invalidate IDs on interpreter teardown;
- define behavior across interpreter checkpoint/restore;
- prevent stale IDs from resolving to an unrelated reused resource, for example
  by using generation counters or never reusing IDs during an interpreter
  lifetime.

Graph cells store only the numeric ID, never the pointer.

## 3.3 Convert all stream paths

Convert:

- input and output stream combinators;
- `fileq` and `outfilq`;
- `READ`, `READB`, `WAIT`, and `STARTREADVALS` paths;
- parser/current-stream state;
- standard streams;
- child-process pipe streams;
- cleanup on EOF, error, interrupt, reset, and normal completion.

Tests must force graph GC while each resource-bearing value is live.

Acceptance criteria:

- No production graph cell contains a native pointer representation.
- `rg 'ptrInt|ptrFrom|@intFromPtr|@ptrFromInt' src` reports only explicitly
  allowlisted platform/signal implementation sites.
- Resource-table tests cover double close, stale ID, wrong kind, checkpoint,
  reset, EOF, error, and interrupt.
- Existing executable behavior remains byte-identical.

---

# Phase 4 — Replace native-stack scanning with explicit GC roots

`Heap.bases` currently scans words between two native stack addresses. Go
goroutine stacks are movable and cannot be scanned this way.

## 4.1 Define the root model

Create an explicit root API. It must support:

- one scoped root;
- a scoped slice of roots;
- permanent interpreter-state roots;
- registered reducer spines;
- nested/reentrant evaluation;
- safe unregistering on every error return.

A suitable shape is an interpreter-owned registry plus scoped guards, but the
exact Zig API may differ. Root ownership and lifetime must be explicit.

## 4.2 Inventory live off-heap references

Audit every function that:

- allocates graph cells;
- can trigger or indirectly trigger GC;
- retains a `Word`/`Value` in a local, state struct, collection, or foreign
  resource while allocating.

Cover at least:

- parser/codegen;
- symbol and module processing;
- inference and unification;
- lowering;
- reducer context and arguments;
- bignum temporary values;
- dump/load scratch;
- REPL/session state;
- stream operations;
- nested `readvals` parsing/evaluation;
- error and interrupt paths.

Do not rely on compile-time reflection over all integer fields to discover
roots. Declare root-bearing fields explicitly.

## 4.3 Add adversarial forced-GC tests

Add a test mode that can collect:

- on every allocation;
- every N allocations for several small N values;
- at selected named pipeline checkpoints.

Run all stage corpora in forced-GC mode. A deterministic seed/order must be used
where collection schedules vary.

## 4.4 Remove stack scanning

Only after the explicit-root corpus passes:

- delete native stack traversal from `Heap.bases`;
- delete the saved `cstack` root;
- remove stack-address comparisons;
- make unregistered off-heap graph references detectable in strict tests where
  practical.

Acceptance criteria:

- No GC code reads arbitrary native stack memory.
- No correctness path depends on stack direction or stack addresses.
- Full tests and stage oracles pass with collection on every allocation.
- Nested reduction, parsing during reduction, interrupts, and error unwinding
  leave the root registry empty except for documented permanent roots.

---

# Phase 5 — Finish the typed value and handle model

The automated translator must not infer meaning from raw `i64` values or from
numeric thresholds.

## 5.1 Define the complete type vocabulary

Use distinct types for at least:

- `Value`: runtime graph value;
- `CellRef`: heap cell handle;
- `Comb`: combinator/named atom;
- immediate byte/character where distinguishable;
- parser `TokenKind`;
- `NodeTag`;
- `StringID`;
- `StreamID`;
- process ID/status;
- source/file/module ID;
- type/declaration classification values;
- counts, indices, and source offsets when confusion is possible;
- raw dump word, confined to the wire codec.

If bit representation cannot distinguish two semantic domains, require a typed
constructor at the boundary rather than guessing during reads.

## 5.2 Convert the heap API first

All public heap methods must take and return typed values:

- allocation and constructors;
- `hd`/`tl`;
- tag access;
- identifier access;
- file/module nodes;
- numeric nodes;
- string handles;
- application and list construction;
- GC marking;
- mutation/checkpoint operations.

Raw conversion may temporarily exist in a private compatibility module, but
every use must be counted and the count may only decrease.

## 5.3 Convert callers by subsystem

Recommended order:

1. graph helpers and bignum;
2. reducer core and spine;
3. reducer combinator handlers;
4. syntax/codegen;
5. symbols/modules;
6. inference/unification;
7. lowering;
8. dump reconstruction;
9. session/compiler integration.

At each boundary replace:

- `x >= ATOMLIMIT` and related range tests with typed classification;
- `Word` sentinel overload with named values/options;
- raw integer tag comparisons with enum switches;
- untyped constructors with domain-specific constructors;
- `toRaw()`/`fromRaw()` shims with typed calls.

## 5.4 Enforce the boundary

Add automated checks:

- `Word` is allowed only in the dump codec and a short explicit constants/data
  definition if still necessary.
- `toRaw`/`fromRaw` are allowed only in the dump codec.
- `ATOMLIMIT` classification is allowed only in the low-level value decoder.
- stream IDs, PIDs, string IDs, and cell references cannot be implicitly
  interchanged.

Acceptance criteria:

- Production logic outside the codec does not accept or return raw `Word`.
- No production caller performs a raw cell/atom threshold check.
- All graph variants have named typed constructors and readers.
- Existing `.x` bytes and executable output remain unchanged.

---

# Phase 6 — Remove ambient interpreter state and break import cycles

Go package imports must form a DAG. Miracula currently has one 62-file strongly
connected component caused largely by state-type ownership and singleton
accessors.

## 6.1 Decide and enforce the target package DAG

Create a machine-readable package mapping for every production source file.
The exact names are less important than the direction, but the mapping must
avoid Go standard-library name collisions and define permitted dependencies.

The dependency direction should follow this shape:

```text
leaf value/protocol types
        ↓
graph and resource storage
        ↓
syntax
        ↓
semantics/lowering
        ↓
evaluation
        ↓
session/application orchestration
        ↓
commands
```

Platform services should be a leaf interface consumed from above; platform
implementations may depend on the Go standard library but not on interpreter
packages.

Where actual data flow requires callbacks in the opposite direction, define a
small interface or move orchestration upward. Do not add a reverse package
import.

## 6.2 Separate state declarations from state lookup

`Interp` must own state, but leaf packages must not import `Interp` to find
their state.

Required conversion:

- entry points construct an interpreter explicitly;
- functions receive `*Interp`, a subsystem receiver, or a narrow dependency
  interface;
- packages declare their own state types without importing the aggregate;
- aggregate construction occurs in the top-level session/application package;
- allocator, I/O, environment, and resource ownership become instance fields
  unless they are inherently process-global;
- only the atomic signal flag may remain process-global.

## 6.3 Remove singleton accessors

Eliminate production dependence on:

- `current_interp`;
- `heap.heap()`;
- `runtime_state.rs()`;
- compiler, lexer, evaluator, symbol, session, and configuration singleton
  accessors.

Do not simulate receiver threading by placing `Interp` in a package global or
`context.Context`.

## 6.4 Prove instance isolation and concurrency safety

Add tests that:

- construct two interpreters;
- run them concurrently;
- use different streams, libraries, heaps, symbols, and configuration;
- interrupt one without interrupting the other except where process signal
  semantics explicitly require it;
- run under a thread sanitizer where available on Zig;
- define the corresponding future Go `-race` requirement.

## 6.5 Make cycles a hard zero gate

Change the cycle checker from informational/baselined to strict zero.

Acceptance criteria:

- `python3 scripts/import_cycles.py -v` reports zero cycles.
- The package mapping checker reports zero forbidden edges.
- No production source imports the aggregate interpreter merely to locate
  state.
- Two interpreters pass concurrent isolation tests.
- No new all-purpose “common” package is used to conceal a cycle.

---

# Phase 7 — Establish one authoritative front-end path

Production parsing currently enters the `syntax` pipeline, while substantial
lexer/state/helper code remains under `src/parser`. The migration agent must
not choose between overlapping implementations or guess whether code is dead.

## 7.1 Build a production reachability inventory

Starting from every executable entry point:

- enumerate every reachable front-end function;
- identify test-only functions;
- identify unreachable files/functions;
- identify legacy-named helpers that are still required for symbol, stream, or
  later compiler behavior rather than lexical analysis.

Generate or maintain the inventory mechanically from imports/call references
where possible.

## 7.2 Characterize overlaps before deletion

For any two paths that appear to implement the same responsibility:

1. run both over the full front-end corpus;
2. compare language-neutral oracle output;
3. add missing cases for differences;
4. select the production behavior already used by the executable;
5. delete the non-production implementation or reduce it to uniquely required
   responsibilities.

Do not delete old code solely because of its directory or comments.

## 7.3 Resolve directive ownership

For every recognized directive, record exactly one owner and one production
behavior. Cover:

- include;
- export;
- free;
- insert;
- list/nolist;
- BNF;
- lex;
- unknown directives.

If a directive is intentionally unsupported, its exact diagnostic and exit
behavior must be captured. If it is supported through another layer, remove
the misleading unsupported representation from the production path.

## 7.4 Remove obsolete state and APIs

After reachability and compatibility verification:

- delete unreachable lexer/parser state;
- split still-required dictionary, stream, or symbol services into accurately
  named modules;
- ensure there is one source-position model, one token model, one AST model,
  and one production parser entry path.

Acceptance criteria:

- Every front-end production function maps to a stage oracle.
- No two reachable implementations claim ownership of the same stage.
- Every directive has one tested owner.
- No migration decision depends on comments containing “legacy,” “new,” or
  “native.”

---

# Phase 8 — Extract and specify the `.x` wire protocol

The `.x` codec must be portable without translating compiler, heap, lexer, and
module-loading concerns as one unit.

## 8.1 Write an executable protocol specification

Define:

- magic/version bytes;
- word width;
- signedness;
- endianness;
- integer encoding;
- floating-point encoding;
- string/path termination and encoding;
- record/tag values;
- sentinel values;
- ordering rules;
- reference/identity numbering;
- malformed-input behavior;
- version mismatch behavior;
- whether host word size or target architecture may affect bytes.

The specification must be backed by test vectors, not prose alone.

## 8.2 Split codec from reconstruction

Create three layers:

1. byte reader/writer;
2. typed protocol records;
3. graph/compiler/module reconstruction.

The byte codec must not import session, parser, compiler, reducer, or global
interpreter state.

## 8.3 Add exhaustive fixtures

Fixtures must cover:

- every record and node tag;
- minimum/maximum and negative integers;
- floats including signed zero and boundary finite values;
- empty and non-ASCII byte strings;
- paths;
- aliases and exports;
- repeated/shared references;
- malformed tag;
- truncated input at every field boundary;
- wrong version/word size;
- trailing bytes.

## 8.4 Add cross-implementation round trips

The eventual contract is:

- Zig encode → Go decode;
- Go encode → Zig decode;
- decode then encode reproduces canonical bytes;
- reconstructed graphs are semantically equivalent.

Before Go exists, prove the verifier can consume externally supplied bytes and
that canonical fixture bytes are checked into the repository.

Acceptance criteria:

- Codec package is dependency-neutral.
- Fixture bytes do not vary across supported hosts.
- Every format branch has a test vector.
- `.x` compatibility can be verified without launching the REPL.

---

# Phase 9 — Isolate platform, process, signal, and terminal behavior

The Go translation must implement behavior, not mechanically copy POSIX calls.

## 9.1 Define service interfaces

Create narrow interfaces for:

- filesystem/stat metadata;
- process creation and waiting;
- pipes and descriptor/stream conversion;
- shell command execution;
- signals and interrupt notification;
- terminal detection and window size;
- clock used for user-visible statistics;
- environment and executable lookup.

Keep platform result types independent of Zig `c_int`, wait-status bit layouts,
and raw signal handler pointers.

## 9.2 Specify process contracts

Characterization tests must define:

- shell path and `-c` behavior;
- stdout/stderr pipe separation;
- pipe close order;
- EOF behavior;
- exit-code mapping;
- signal termination mapping;
- failed fork/spawn/exec behavior;
- child cleanup on interrupt and timeout;
- whether commands inherit environment and working directory;
- lazy stream consumption and wait ordering.

## 9.3 Replace handler addresses with typed registration

The signal API currently passes handler addresses as integers. Replace this
with typed signal registration isolated inside the platform implementation.
Interpreter code should receive an interrupt event or observe an atomic flag;
it must not manipulate handler addresses.

## 9.4 Establish supported-platform CI

The migration supports macOS ARM64 only. This target list is checked in and
validated by the Phase 9 gate. Unsupported platforms must fail clearly at
build time.

Acceptance criteria:

- No interpreter package imports POSIX/C ABI types.
- No handler or function pointer is represented as an integer outside the
  platform implementation.
- Process behavior tests pass on every supported platform.
- Platform differences are explicit implementations, not scattered compile-time
  branches.

---

# Phase 10 — Remove internal C-string and generic scanf semantics

## 10.1 Convert internal string ownership

Use:

- immutable byte slices for byte-oriented Miranda/source data;
- ordinary slices/strings for paths and messages;
- mutable slices plus explicit length/index for buffers;
- temporary NUL termination only at the smallest actual FFI boundary.

Replace pointer subtraction and pointer cursors with indices.

## 10.2 Replace generic scan functions

Inventory every `sscanf`/`fscanf` call and its format string. Implement a typed
parser for the actual grammar at each call site. Do not create a general Go
emulation of C scanf unless the source proves that arbitrary runtime formats
are part of the program's behavior.

Tests must cover:

- EOF;
- empty input;
- leading/trailing whitespace;
- sign;
- base prefixes;
- width limits;
- overflow;
- malformed suffix;
- float exponent variants;
- partial conversion;
- number of successful conversions.

## 10.3 Enforce the boundary

Acceptance criteria:

- Sentinel pointer string types exist only inside true FFI/platform code.
- Production parser, graph, semantics, evaluator, and session code use
  slices/strings and indices.
- `os_scanf.zig` is deleted or contains no production responsibility.
- All former format strings have direct typed tests.

---

# Phase 11 — Replace compile-time reflection and generation with explicit artifacts

## 11.1 Canonicalize combinator definitions

Create one checked-in, language-neutral combinator definition file containing:

- stable name;
- stable numeric value/order;
- aliases/display name if needed;
- arity or dispatch metadata if currently implied elsewhere.

Generate Zig constants/tables from it and verify generated files are current.
The future Go port will generate its constants from the same input.

## 11.2 Remove reflection from correctness-critical discovery

Replace reflection used to discover:

- GC roots;
- state fields requiring validation;
- protocol fields;
- behavior dispatch.

Use explicit lists or generated code from a checked-in schema. Adding a new
field must cause a compilation or generation check failure until its handling
is declared.

## 11.3 Resolve `anytype` by category

Replace correctness-relevant generic functions with:

- concrete typed functions;
- explicit overloads with distinct names;
- ordinary formatting variadics only for diagnostic formatting;
- generated code for fixed type sets.

Acceptance criteria:

- No runtime/protocol/GC semantics depend on Zig reflection.
- Generated artifacts have a single source, a regeneration command, and a
  “generated output is current” gate.
- The future Go generator can consume the same canonical data without parsing
  Zig source.

---

# Phase 12 — Guarantee deterministic fixtures and outputs

## 12.1 Audit every unordered collection

For every hash map/set iteration, determine whether iteration can influence:

- diagnostics;
- exported names;
- serialized data;
- AST/graph fixture output;
- symbol numbering;
- generated files;
- user-visible output.

Sort at the semantic output boundary using a specified byte ordering. Do not
rely on current Zig iteration order.

## 12.2 Eliminate address and timing identities

No fixture or compared output may contain:

- pointer/address values;
- allocator-dependent IDs;
- map hash values;
- elapsed time, unless the test explicitly tests timing format and masks only
  the numeric value;
- process IDs;
- temporary random paths.

Use stable dense IDs assigned by specified traversal/allocation order.

## 12.3 Add a cross-process determinism checker

For every capture driver:

1. run it in a fresh process at least three times;
2. use separate temporary directories;
3. vary environment ordering where possible;
4. compare complete output trees byte for byte.

Acceptance criteria:

- All stage fixtures and generated protocol data are byte-identical across
  repeated processes.
- Tests identify the first differing file and byte/record.
- Determinism checks are part of `go-ready`.

---

# Phase 13 — Publish the mechanical Go translation contract

This phase does not begin the translation. It removes the remaining decisions
from the future agent.

## 13.1 Produce the source-to-target manifest

For every Zig production file/function/type, record:

- target Go package;
- target Go file;
- target symbol;
- stage oracle that verifies it;
- dependencies/interfaces;
- representation mapping;
- translation status, initially `pending`;
- whether it is platform-specific, generated, or intentionally not ported.

The manifest must be machine-readable and validated for:

- every production symbol appears exactly once;
- no target package cycle;
- every target unit has a verifier;
- every “not ported” entry has a tested reason.

## 13.2 Freeze translation rules

Specify mechanically:

- Zig error unions → Go return values and concrete error types;
- optionals → pointer/value-plus-bool/error as selected per API;
- tagged unions → selected Go representation per declared type;
- allocators → Go ownership/lifetime rule;
- slices and strings;
- enums and numeric widths;
- cleanup/defer behavior;
- panic/fatal/ordinary errors;
- build-time options;
- platform build tags;
- tests and fixture locations;
- generated-code commands.

Do not leave “choose whichever is idiomatic” instructions.

## 13.3 Define the unit translation loop

The checked-in `bootstrap` unit is already complete. It owns `go.mod`, the nine
package skeletons, the package-DAG checker, combinator generator, and the
partial-stage `miracula-go-oracle` command. Translation progress lives in
`spec/go_translation_status.json`; manifest regeneration reads that file and
must never reset completed units.

The Go oracle lists only implemented stages. Requesting an unavailable stage
must emit no records and exit 3, which the verifier treats as failure. The unit
that implements a stage registers its producer; producers compute results from
the input bytes and must not replay expected fixture payloads.

The future agent must be able to follow this exact loop:

1. Select the next manifest unit whose dependencies are complete.
2. Translate only that unit and its Go tests.
3. Run `go test` for the package.
4. Run the unit's stage-oracle verifier.
5. Run the Go package DAG check and generated-code check.
6. Mark the manifest unit complete.
7. Continue only on green.
8. Periodically run all completed-stage verifiers.
9. Build the final executable only after all required packages are complete.
10. Run the full Zig-reference differential gate against the Go executable.

Acceptance criteria:

- A scheduler can select translation order entirely from the manifest.
- No unit lacks an immediate automated test.
- No representation or ownership choice remains undocumented.
- The Go port can be paused after any unit with all completed units green.

---

# Final readiness exit criteria

All of these must be true before giving the repository to an unsupervised Go
translation agent:

- [ ] `zig build go-ready --summary all` passes.
- [ ] The pinned reference binary and library hashes are verified.
- [ ] Missing references and skipped cases are fatal.
- [ ] Every pipeline stage has a language-neutral oracle.
- [ ] Every planned Go package maps to an oracle.
- [ ] No native pointer is stored in a graph value.
- [ ] Stream/resource graph values use typed stable IDs.
- [ ] GC uses explicit roots and performs no native-stack scan.
- [ ] Forced GC on every allocation passes the full applicable corpus.
- [ ] Raw `Word` use is confined to the `.x` codec.
- [ ] No production caller classifies values with raw numeric thresholds.
- [ ] The source import graph has zero cycles.
- [ ] Interpreter state is explicitly passed/owned, not ambiently located.
- [ ] Two interpreters pass concurrent isolation tests.
- [ ] Exactly one authoritative production front-end path exists.
- [ ] Every directive has one owner and tested behavior.
- [ ] The `.x` format has an independent typed byte codec and exhaustive vectors.
- [ ] POSIX/process/signal behavior is behind typed platform interfaces.
- [ ] Platform contract tests pass on every supported target.
- [ ] Internal code no longer depends on C-string pointer conventions.
- [ ] Generic scanf behavior has been replaced by typed parsers.
- [ ] Correctness-critical reflection has been replaced by explicit/generated data.
- [ ] Combinator numbering comes from one language-neutral canonical source.
- [ ] All fixture and generated outputs are deterministic across fresh processes.
- [ ] The machine-readable source-to-target manifest covers every production symbol.
- [ ] Every target unit has fixed representation rules and a verification command.
- [ ] The existing Zig executable still matches all pinned observable behavior.

When every item is checked, the repository is ready for automated,
unsupervised, incremental translation to Go. Until then, a translation agent
would still be required to make design decisions or wait too long for reliable
feedback, which violates the purpose of this preparation.
