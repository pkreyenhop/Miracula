#!/usr/bin/env python3
"""Verify generated combinators and reflection/anytype ownership."""

from __future__ import annotations

import json
import re
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "src"
ANYTYPE = ROOT / "tests" / "phase11_anytype_inventory.json"

FN_RE = re.compile(r"\b(?:pub\s+)?fn\s+([A-Za-z_][A-Za-z0-9_]*)\s*\([^)]*anytype", re.DOTALL)


def owner_name(text: str, match: re.Match[str]) -> str:
    prefix = text[:match.start()]
    containers = list(re.finditer(r"\b(?:pub\s+)?const\s+([A-Za-z_][A-Za-z0-9_]*)\s*=\s*struct\s*\{", prefix))
    if not containers:
        return match.group(1)
    container = containers[-1]
    depth = prefix[container.end():].count("{") - prefix[container.end():].count("}")
    return f"{container.group(1)}.{match.group(1)}" if depth >= 0 else match.group(1)


def anytype_owners() -> dict[str, str]:
    expected = json.loads(ANYTYPE.read_text(encoding="utf-8"))["owners"]
    found = {}
    for path in SRC.rglob("*.zig"):
        rel = path.relative_to(SRC).as_posix()
        text = path.read_text(encoding="utf-8")
        for match in FN_RE.finditer(text):
            key = f"{rel}:{owner_name(text, match)}"
            found[key] = expected.get(key, "unclassified")
    return found


def main() -> int:
    generated = subprocess.run(
        ["python3", "scripts/generate_combinators.py"],
        cwd=ROOT,
        text=True,
        capture_output=True,
    )
    if generated.returncode != 0:
        print(generated.stdout + generated.stderr, end="")
        return 1

    expected = json.loads(ANYTYPE.read_text(encoding="utf-8"))
    if expected.get("schema") != 1:
        print("unsupported anytype inventory schema")
        return 1
    actual = anytype_owners()
    if actual != expected["owners"]:
        missing = sorted(set(expected["owners"]) - set(actual))
        added = sorted(set(actual) - set(expected["owners"]))
        if missing:
            print(f"anytype owners removed or renamed: {missing}")
        if added:
            print(f"new/unclassified anytype owners: {added}")
        return 1

    reflection_allowed = {"os.zig", "eval/stream.zig"}
    offenders = []
    for path in SRC.rglob("*.zig"):
        rel = path.relative_to(SRC).as_posix()
        if rel in reflection_allowed or rel == "graph/combinator_generated.zig":
            continue
        text = path.read_text(encoding="utf-8")
        if any(marker in text for marker in ("std.meta.fields", "@Enum(", "@typeInfo(", "@field(")):
            offenders.append(rel)
    if offenders:
        print(f"correctness-relevant reflection remains: {sorted(offenders)}")
        return 1

    schema = json.loads((ROOT / "spec/combinators.json").read_text(encoding="utf-8"))
    dispatches = {entry["dispatch"] for entry in schema["entries"]}
    if dispatches != {"evaluation", "grammar", "lexer", "control", "sentinel"}:
        print("combinator dispatch metadata is incomplete")
        return 1

    print(
        f"phase 11 generation verified: {len(schema['entries'])} combinators, "
        f"{len(actual)} classified anytype owners, no semantic reflection"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
