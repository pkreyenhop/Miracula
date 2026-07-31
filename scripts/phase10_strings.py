#!/usr/bin/env python3
"""Verify typed parsing and ratchet remaining sentinel-string migration sites."""

from __future__ import annotations

import argparse
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "src"
INVENTORY = ROOT / "tests" / "phase10_string_inventory.json"
CONTRACT = ROOT / "tests" / "phase10_parse_contract.json"

PATTERNS = {
    "sentinel_pointer": re.compile(r"\[\*:0\]"),
    "sentinel_slice": re.compile(r"\[:0\]"),
    "span_conversion": re.compile(r"\bstd\.mem\.span\("),
    "pointer_arithmetic": re.compile(r"\b(?:ptrInt|ptrFrom)\("),
}

TRUE_BOUNDARIES = {
    "os.zig",
    "io/platform.zig",
    "io/process.zig",
    "io/signals.zig",
    "eval/stream.zig",
}


def source_without_comments(text: str) -> str:
    return "\n".join(line.split("//", 1)[0] for line in text.splitlines())


def build_inventory() -> dict:
    files = {}
    for path in sorted(SRC.rglob("*.zig")):
        rel = path.relative_to(SRC).as_posix()
        text = source_without_comments(path.read_text(encoding="utf-8"))
        counts = {name: len(pattern.findall(text)) for name, pattern in PATTERNS.items()}
        if any(counts.values()):
            files[rel] = {
                "classification": "ffi_or_platform" if rel in TRUE_BOUNDARIES else "migration_compatibility",
                **counts,
            }
    return {"schema": 1, "files": files}


def verify_inventory(actual: dict, expected: dict) -> list[str]:
    errors = []
    if expected.get("schema") != 1:
        return ["unsupported string inventory schema"]
    for path, current in actual["files"].items():
        old = expected.get("files", {}).get(path)
        if old is None:
            errors.append(f"new sentinel-string owner: src/{path}")
            continue
        for name in PATTERNS:
            if current[name] > old[name]:
                errors.append(f"{name} increased: src/{path} {old[name]} -> {current[name]}")
        if current["classification"] != old["classification"]:
            errors.append(f"string ownership classification changed: src/{path}")
    return errors


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--write", action="store_true")
    args = parser.parse_args()

    actual = build_inventory()
    if args.write:
        INVENTORY.write_text(json.dumps(actual, indent=2, sort_keys=True) + "\n")
        print(f"wrote {INVENTORY.relative_to(ROOT)}")
        return 0

    expected = json.loads(INVENTORY.read_text(encoding="utf-8"))
    errors = verify_inventory(actual, expected)
    contract = json.loads(CONTRACT.read_text(encoding="utf-8"))
    if contract.get("schema") != 1 or len(contract.get("former_formats", {})) != 7:
        errors.append("former scanf format inventory is incomplete")
    required = {
        "eof", "empty", "leading_whitespace", "trailing_whitespace", "sign",
        "base_prefixes", "width_limits", "overflow", "malformed_suffix",
        "float_exponents", "partial_conversion", "successful_conversion_count",
    }
    if set(contract.get("required_cases", [])) != required:
        errors.append("typed parse test-case contract is incomplete")

    for path in SRC.rglob("*.zig"):
        text = source_without_comments(path.read_text(encoding="utf-8"))
        if re.search(r"\b(?:sscanf|fscanf)\b", text):
            errors.append(f"generic scanf responsibility remains: {path.relative_to(ROOT)}")
    if (SRC / "os_scanf.zig").exists():
        errors.append("src/os_scanf.zig still exists")

    typed = (SRC / "io/typed_parse.zig").read_text(encoding="utf-8")
    for marker in (
        'test "integer parsing covers whitespace, signs, suffixes, width, and overflow"',
        'test "float parsing covers exponent variants and strict suffix handling"',
        'test "stream tokens define EOF, whitespace, width, and conversion counts"',
        "pub fn integerAuto",
    ):
        if marker not in typed:
            errors.append(f"typed parser coverage marker missing: {marker}")

    if errors:
        print("\n".join(errors))
        return 1
    compatibility = sum(
        1 for item in expected["files"].values()
        if item["classification"] == "migration_compatibility"
    )
    print(
        "phase 10 typed parsing verified; generic scanner deleted; "
        f"{compatibility} sentinel-string owners ratcheted"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
