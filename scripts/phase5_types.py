#!/usr/bin/env python3
"""Fail-closed typed-value translation contract.

Every remaining raw-value site must have an exact target representation in
the Go translation manifest. There is no count-based compatibility ratchet.
"""

from __future__ import annotations

import argparse
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "src"
MANIFEST = ROOT / "tests" / "phase5_type_inventory.json"
TRANSLATION_MANIFEST = ROOT / "spec" / "go_translation_manifest.json"

PATTERNS = {
    "word": re.compile(r"\bWord\b"),
    "from_raw": re.compile(r"\bfromRaw\s*\("),
    "to_raw": re.compile(r"\btoRaw\s*\("),
}


def owner(path: str) -> str:
    part = path.split("/", 1)[0]
    return {
        "graph": "graph-and-codec",
        "eval": "reducer",
        "syntax": "syntax",
        "parser": "syntax-and-codegen",
        "semantics": "type-and-lowering",
        "compiler": "module-integration",
        "session": "session-integration",
        "runtime": "runtime-state",
        "io": "platform-io",
    }.get(part, "platform-support")


def inventory() -> dict:
    files: dict[str, dict] = {}
    for source in sorted(SRC.rglob("*.zig")):
        rel = source.relative_to(SRC).as_posix()
        text = source.read_text()
        counts = {name: len(pattern.findall(text)) for name, pattern in PATTERNS.items()}
        if any(counts.values()):
            files[rel] = {"owner": owner(rel), **counts}
    return {
        "schema": 1,
        "policy": (
            "Compatibility counts are upper bounds. The Go translator maps "
            "each file through its owner and semantic_types.zig; it must not "
            "translate a raw i64 by numeric inference."
        ),
        "typed_vocabulary": [
            "Value", "CellRef", "Comb", "ImmediateByte", "TokenKind", "NodeTag",
            "StringID", "StreamID", "ProcessID", "ProcessStatus", "SourceID",
            "FileID", "ModuleID", "Count", "Index", "SourceOffset", "RawDumpWord",
        ],
        "files": files,
    }


def verify(actual: dict, expected: dict) -> list[str]:
    errors: list[str] = []
    if expected.get("schema") != 1:
        errors.append("unsupported phase 5 inventory schema")
        return errors
    for path, current in actual["files"].items():
        baseline = expected["files"].get(path)
        if baseline is None:
            errors.append(f"new raw compatibility owner: src/{path}")
            continue
        if current["owner"] != baseline["owner"]:
            errors.append(f"owner changed without manifest update: src/{path}")
        for metric in PATTERNS:
            if current[metric] != baseline[metric]:
                errors.append(f"src/{path}: {metric} inventory is stale")
    if set(actual["files"]) != set(expected["files"]):
        errors.append("phase 5 file inventory is stale")
    return errors


def verify_translation_targets(actual: dict) -> list[str]:
    manifest = json.loads(TRANSLATION_MANIFEST.read_text())
    sources = {item["source_file"]: item for item in manifest["sources"]}
    errors = []
    for path, counts in actual["files"].items():
        source = sources.get(path)
        mapped = source.get("compatibility", {}).get("raw_value_sites", {}) if source else {}
        for metric in PATTERNS:
            sites = mapped.get(metric, [])
            if len(sites) != counts[metric] or any(not site.get("target") for site in sites):
                errors.append(f"src/{path}: {metric} sites lack exact Go targets")
    return errors


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--write", action="store_true")
    args = parser.parse_args()
    actual = inventory()
    if args.write:
        MANIFEST.write_text(json.dumps(actual, indent=2, sort_keys=True) + "\n")
        print(f"wrote {MANIFEST.relative_to(ROOT)}")
        return 0
    expected = json.loads(MANIFEST.read_text())
    errors = verify(actual, expected)
    errors.extend(verify_translation_targets(actual))
    if errors:
        print("\n".join(errors))
        return 1
    vocabulary = (SRC / "graph" / "semantic_types.zig").read_text()
    value_model = (SRC / "graph" / "value.zig").read_text()
    token_model = (SRC / "syntax" / "token_filter.zig").read_text()
    resource_model = (SRC / "eval" / "resources.zig").read_text()
    word_model = (SRC / "graph" / "word.zig").read_text()
    locations = vocabulary + value_model + token_model + resource_model + word_model
    missing = [name for name in expected["typed_vocabulary"] if name not in locations]
    if missing:
        print("missing typed vocabulary: " + ", ".join(missing))
        return 1
    print(
        "phase 5 typed boundary verified: "
        f"{len(actual['files'])} compatibility owners, every site has an exact Go target"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
