# Go Compatibility Exceptions

The production Go Miranda interpreter has the following two representation
exceptions. Neither changes Miranda source semantics or program output.

## GO-COMPAT-001: `/count` implementation metrics

- Owner: Miranda maintainers.
- Surface: `-count`, `/count`, and `/set count`.
- Historical behavior: reported implementation-specific graph-rewrite and
  heap-cell counters.
- Go behavior: reports interpreted AST-node reductions and value-producing
  nodes using the same labels and stream format.
- Rationale: the former implementation-specific raw numbers have no stable
  cross-runtime meaning; the feature remains a truthful relative-work
  diagnostic for the active runtime.
- Proof: command and golden tests verify every count line and field.
- Expiry: permanent unless a language-neutral work metric is standardized.

## GO-COMPAT-002: compiled dump encoding

- Owner: Miranda maintainers.
- Surface: generated `.x` cache files.
- Historical behavior: serialized implementation-specific graph cells and
  tagged machine words.
- Go behavior: stores a versioned source digest and source payload for safe,
  deterministic validation and reload.
- Rationale: `.x` files are disposable caches, and encoding raw runtime
  pointers would be unsafe and architecture-coupled.
- Proof: dump tests cover creation, permissions, stale rejection, corruption,
  byte-stable reuse, and equivalent source-only/dump-assisted execution.
- Expiry: permanent; incompatible or stale dumps are rebuilt from source.

New exceptions may be added only under the policy below.

An exception may be added only when historical behavior is unsuitable for the
supported macOS ARM64 product and the change has been explicitly approved.
Each exception must contain:

- a stable identifier and owner;
- the affected command, language feature, or platform behavior;
- the historical behavior and the proposed behavior;
- user impact and rationale;
- a focused test proving the intentional difference;
- an approval record;
- an expiry condition or a decision that the difference is permanent.

Expected-output files must not be changed to hide an unapproved difference.
Temporary implementation gaps, test flakes, timeouts, and performance problems
are not compatibility exceptions.
