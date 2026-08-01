# Miranda Go production cutover

Miracula's production `mira` command is now the Go implementation. The normal
build, installation, and release archive no longer require Zig.

## Supported system

This release supports **macOS on 64-bit ARM (Apple Silicon) only**. Linux,
Intel macOS, and other operating-system or architecture combinations fail the
production build explicitly; they are not migration targets.

## Product changes

- `make`, `make install`, release archives, and the default `zig build`
  artifact select the Go `mira`.
- The historical Zig implementation remains available only to developers as
  `make reference` / `zig-out/bin/mira-zig-reference` and as the pinned parity
  oracle.
- Installed binaries locate the packaged `miralib` relative to the executable;
  `MIRALIB` and `-lib` remain supported overrides.
- Release metadata records the source commit and revision date reproducibly.
- Go `.x` files are safe, disposable caches. Zig cache bytes and Go cache bytes
  are intentionally different and are regenerated from source when needed.
- `/count` retains its public format but reports Go runtime work rather than
  Zig graph-cell internals. Details are in `GoCompatibilityExceptions.md`.

## Verification record

Milestones 09 and 10 passed three fresh candidate runs, the pinned executable
differential, all nine stage oracles, Go unit and race tests, the full golden
and integration suites, deep-spine and interrupt stress, forced-allocation
checks, installed-product smoke tests, and deterministic archive tests.

Milestone 11 and the complete local `zig build go-ready --summary failures`
release gate passed on 1 August 2026. The clean, synchronized production head
was `bdd2a00c8290f4af4db53be085b151329614d66e` and is published as the annotated
tag `go-cutover-2.067`. A resource-bound hosted rerun was canceled; the release
decision explicitly accepted the complete local gate as the authoritative
proof.

The retained rollback reference is:

- source commit: `620b7495165c5801b73fb39b6e4cba8c55277932`
- macOS ARM64 binary SHA-256:
  `daf2d36448482b391a838b015e12954f22f9f9659db12e5d0a0e384e5a5c1a3f`
- manifest: `tests/reference/manifest.json`

## Rollback

Published history must not be rewritten. If a production regression is found,
preserve the failing Go binary and logs, add a reproducer, and revert the
default artifact selection in a new commit to the reference identity above.
For an installed-prefix emergency drill, run:

```sh
python3 scripts/install_reference_rollback.py --install-root /usr/local
```

The command verifies the pinned checksum, preserves the Go executable as
`bin/mira-go-failed`, and atomically installs the reference as `bin/mira`. This
procedure is exercised in an isolated prefix by `tests/test_go_rollback.py`.
After fixing forward, rerun Milestones 09–11 before a new cutover.

The normal tag gate is a passing remote CI run. For this cutover, the release
decision explicitly accepted the equivalent complete local gate after the
hosted Apple runner became resource-bound.
