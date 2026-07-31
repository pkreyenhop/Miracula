# Pinned executable oracle

`manifest.json` and `artifacts/` are the immutable Phase 1 executable
specification.

The binaries were built from source commit
`620b7495165c5801b73fb39b6e4cba8c55277932` with compiler version `0.16.0`
and `ReleaseSafe` optimization:

```sh
zig build -Doptimize=ReleaseSafe -Dtarget=aarch64-macos
zig build -Doptimize=ReleaseSafe -Dtarget=x86_64-linux-musl
```

The exact binaries are committed because linked output contains
nondeterministic metadata and a same-source rebuild is not guaranteed to have
the same whole-file checksum. Git is therefore the immutable retrieval
mechanism: checkout the manifest's containing commit to retrieve the exact
artifact.

Verify the artifact selected for the current host, the pinned source commit,
and the Miranda library:

```sh
zig build verify-reference
```

Run all Phase 1 compatibility checks:

```sh
zig build go-ready --summary all
```

Do not replace a binary or update a checksum as part of an ordinary behavior
change. Pinning a new oracle requires an intentional baseline change: run the
complete pre-pin suite, record the new source/compiler/target metadata, replace
both supported artifacts, update their checksums and the library checksum, and
review the resulting behavior independently.
