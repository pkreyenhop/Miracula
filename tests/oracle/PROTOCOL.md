# Stage oracle protocol, version 1

Each oracle is ASCII JSON Lines with exactly one canonical JSON object per
line. Files end in a newline and records are sorted by `case_id`. Strings use
JSON escaping with non-ASCII bytes escaped, integers use decimal notation,
floating-point NaN and infinities are forbidden, insignificant whitespace is
forbidden, and object fields use the order defined below.

The record fields, in order, are:

1. `schema_version`: integer `1`.
2. `stage`: one of `source`, `lex`, `layout`, `parse`, `module`, `typecheck`,
   `lower`, `reduce`, or `dump`.
3. `case_id`: stable, non-empty string.
4. `input`: `{encoding,length,sha256}` identifying the exact input bytes.
5. `outcome`: `{kind}` for success or `{kind,failure_type}` for a typed failure.
6. `payload`: stage-specific deterministic data.
7. `diagnostics`: ordered diagnostic objects.

Diagnostic fields are always present and ordered
`severity,message,file,start,end,line,column`. Locations unavailable for a
diagnostic are JSON `null`; offsets are zero-based byte offsets and line and
column are one-based. Diagnostic order is source order, then severity, then
message.

Stage payloads use these stable concepts:

- `source`: transformed bytes, file identities, and position mappings.
- `lex`: tokens with named kinds, exact byte values, spans, and directives.
- `layout`: the complete post-layout token sequence.
- `parse`: recursively tagged AST nodes and the recovery result.
- `module`: resolved includes, aliases, exports, and dense symbol IDs.
- `typecheck`: normalized types, externally visible substitutions, diagnostics.
- `lower`: cells ordered by dense ID with named tags and stable references.
- `reduce`: result graph/value, process outcome, streams, and optional trace.
- `dump`: input bytes, decoded records, re-encoded bytes, reconstructed cells.

Pointer values, allocator state, timings, implementation type names, and
iteration order from hash tables are forbidden. Capture commands may replace
fixtures. Verify commands only read fixtures and compare them with a producer.
All differences include the case ID and first differing field path.

## Partial Go producer

`cmd/miracula-go-oracle` is present before package translation begins. Its
`--list-stages` operation prints the implemented stages in lexical order. A
stage becomes available only when its owning translation unit registers a
producer that computes records using the translated Go package.

Requesting a stage that has not been implemented emits no JSONL, writes a
diagnostic to stderr, and exits with status 3. The Python verifier treats that
status as failure. A producer must compute its result from each case's
`input_base64`; replaying the expected `stages` payload or fixture JSONL is
forbidden.
