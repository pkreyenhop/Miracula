#!/usr/bin/env python3
"""layer_check.py — enforce docs/ZIG_NATIVE_PLAN.md §4.1's import-layering rule.

Layer rule (CI-enforced, Phase 4): `graph` and `syntax` are leaves; `semantics`
may import `syntax` + `graph`; `eval` may import `graph`; `session` may import
everything; nothing imports `session`; only `main.zig`/`session` and
`eval/stream.zig` may import `os.zig`.

This only applies to files that have already landed in the target tree
(src/graph, src/syntax, src/semantics, src/eval, src/session, src/main.zig,
src/os.zig) -- Phase 4 step 1 was a partial move (see docs/ZIG_NATIVE_PLAN.md),
so most of the codebase still lives in the pre-Phase-4 src/runtime,
src/compiler, src/parser, src/driver, src/io directories and isn't classified
into a layer yet. An edge is only checked once BOTH its source and target
have a real layer; edges touching an unmigrated file are silently skipped
(they'll start being checked the moment that file moves).

Known violations among already-migrated files are grandfathered into
scripts/layer_allowlist.txt (one "src/a/b.zig -> src/c/d.zig" per line) --
this must shrink to empty by the end of Phase 4, per the plan's own gate.
New violations not in the allowlist fail the check.

Usage:
    scripts/layer_check.py [root]          # default root: src
    scripts/layer_check.py --update-allowlist [root]   # rewrite the allowlist
                                                        # to match today's
                                                        # violations exactly
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

IMPORT_RE = re.compile(r'@import\(\s*"([^"]+\.zig)"\s*\)')

# Directory (relative to src/) -> layer name. Top-level files are matched by
# exact relative path instead (main.zig, os.zig).
DIR_LAYERS = {
    "graph": "graph",
    "syntax": "syntax",
    "semantics": "semantics",
    "eval": "eval",
    "session": "session",
}

# layer -> set of layers it may import from (besides itself).
ALLOWED = {
    "graph": set(),
    "syntax": set(),
    "semantics": {"syntax", "graph"},
    "eval": {"graph"},
    "session": {"graph", "syntax", "semantics", "eval", "os"},
    "main": {"graph", "syntax", "semantics", "eval", "session", "os"},
    "os": set(),
}


def layer_of(rel: Path) -> str | None:
    """The target-tree layer for `rel` (a path relative to src/), or None if
    it hasn't been migrated into the target tree yet."""
    parts = rel.parts
    if rel == Path("main.zig"):
        return "main"
    if rel == Path("os.zig"):
        return "os"
    if len(parts) >= 2 and parts[0] in DIR_LAYERS:
        return DIR_LAYERS[parts[0]]
    return None


def build_edges(root: Path) -> list[tuple[Path, Path]]:
    edges = []
    for f in sorted(root.rglob("*.zig")):
        text = f.read_text(encoding="utf-8", errors="replace")
        for m in IMPORT_RE.finditer(text):
            target = (f.parent / m.group(1)).resolve()
            if target.exists():
                edges.append((f.resolve(), target))
    return edges


def load_allowlist(path: Path) -> set[tuple[str, str]]:
    if not path.exists():
        return set()
    out = set()
    for line in path.read_text().splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        a, _, b = line.partition(" -> ")
        out.add((a, b))
    return out


def main():
    argv = sys.argv[1:]
    update = "--update-allowlist" in argv
    argv = [a for a in argv if a != "--update-allowlist"]
    root = Path(argv[0]) if argv else Path("src")
    root = root.resolve()
    repo_root = root.parent
    allowlist_path = repo_root / "scripts" / "layer_allowlist.txt"

    edges = build_edges(root)
    violations = []
    # test-only imports of testutil.zig are a standing, documented exception
    # (every layer's unit tests use the shared harness) -- not a real layering
    # violation, so never flagged.
    testutil = (root / "testutil.zig").resolve()

    for src, dst in edges:
        if dst == testutil:
            continue
        src_rel = src.relative_to(root)
        dst_rel = dst.relative_to(root)
        src_layer = layer_of(src_rel)
        dst_layer = layer_of(dst_rel)
        if src_layer is None or dst_layer is None:
            continue  # at least one endpoint not yet migrated -- not checked
        if dst_layer == src_layer:
            continue  # same-layer imports are always fine
        if dst_layer in ALLOWED.get(src_layer, set()):
            continue
        violations.append((f"src/{src_rel}", f"src/{dst_rel}"))

    if update:
        lines = [
            "# layer_check.py allowlist -- grandfathered layering violations.",
            "# Format: src/a.zig -> src/b.zig (one per line). Must shrink to",
            "# empty by the end of Phase 4 (docs/ZIG_NATIVE_PLAN.md).",
            "",
        ]
        for a, b in sorted(set(violations)):
            lines.append(f"{a} -> {b}")
        allowlist_path.write_text("\n".join(lines) + "\n")
        print(f"Wrote {len(set(violations))} entries to {allowlist_path}")
        return

    allowlist = load_allowlist(allowlist_path)
    unallowed = [(a, b) for a, b in violations if (a, b) not in allowlist]
    stale = sorted(allowlist - set(violations))

    print(f"layer violations among migrated files: {len(violations)} "
          f"({len(allowlist)} allowlisted, {len(unallowed)} new)")
    if unallowed:
        print("NEW violations (not in scripts/layer_allowlist.txt):")
        for a, b in sorted(unallowed):
            print(f"  {a} -> {b}")
    if stale:
        print(f"stale allowlist entries (no longer violated -- remove them "
              f"to shrink the allowlist): {len(stale)}")
        for a, b in stale:
            print(f"  {a} -> {b}")

    if unallowed:
        sys.exit(1)


if __name__ == "__main__":
    main()
