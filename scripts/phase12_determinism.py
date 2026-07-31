#!/usr/bin/env python3
"""Audit unordered iteration and verify cross-process fixture determinism."""

from __future__ import annotations

import json
import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "src"
INVENTORY = ROOT / "tests" / "phase12_unordered_inventory.json"
ORACLE = ROOT / "tests" / "oracle" / "oracle.py"
CASES = ROOT / "tests" / "oracle" / "fixtures" / "cases.json"
STAGES = ("source", "lex", "layout", "parse", "module", "typecheck", "lower", "reduce", "dump")
ITERATOR_RE = re.compile(r"\.(keyIterator|valueIterator|iterator)\s*\(")
FUNCTION_RE = re.compile(r"^\s*(?:pub\s+)?fn\s+([A-Za-z_][A-Za-z0-9_]*)\s*\(", re.MULTILINE)
UNSTABLE_FIELDS = {
    "address",
    "allocator_id",
    "elapsed",
    "elapsed_ns",
    "hash",
    "map_hash",
    "pid",
    "pointer",
    "process_id",
    "temp_path",
    "temporary_path",
}


def function_at(text: str, offset: int) -> str | None:
    matches = list(FUNCTION_RE.finditer(text, 0, offset))
    return matches[-1].group(1) if matches else None


def unordered_sites() -> dict[str, str]:
    found: dict[str, str] = {}
    for path in sorted(SRC.rglob("*.zig")):
        rel = path.relative_to(SRC).as_posix()
        text = path.read_text(encoding="utf-8")
        for match in ITERATOR_RE.finditer(text):
            kind = match.group(1)
            owner = function_at(text, match.start())
            key = f"{rel}:{owner}:{kind}" if owner else f"{rel}:{kind}"
            if key in found:
                raise SystemExit(f"ambiguous unordered-iteration owner: {key}")
            found[key] = ""
    return found


def reject_unstable_fields(value: object, location: str) -> None:
    if isinstance(value, dict):
        for key, child in value.items():
            if key.lower() in UNSTABLE_FIELDS:
                raise SystemExit(f"{location}: unstable identity field {key!r}")
            reject_unstable_fields(child, f"{location}.{key}")
    elif isinstance(value, list):
        for index, child in enumerate(value):
            reject_unstable_fields(child, f"{location}[{index}]")


def first_difference(left: Path, right: Path) -> str | None:
    left_files = sorted(path.relative_to(left) for path in left.rglob("*") if path.is_file())
    right_files = sorted(path.relative_to(right) for path in right.rglob("*") if path.is_file())
    if left_files != right_files:
        missing = sorted(set(left_files) - set(right_files))
        added = sorted(set(right_files) - set(left_files))
        return f"output tree differs: missing={missing}, added={added}"
    for rel in left_files:
        wanted = (left / rel).read_bytes()
        actual = (right / rel).read_bytes()
        if wanted == actual:
            continue
        limit = min(len(wanted), len(actual))
        offset = next((i for i in range(limit) if wanted[i] != actual[i]), limit)
        if offset == limit:
            return f"{rel}: first difference at byte {offset} (length {len(wanted)} != {len(actual)})"
        return (
            f"{rel}: first difference at byte {offset} "
            f"(0x{wanted[offset]:02x} != 0x{actual[offset]:02x})"
        )
    return None


def capture_tree(destination: Path, run: int) -> None:
    fixtures = destination / "fixtures"
    fixtures.mkdir(parents=True)
    (fixtures / "cases.json").write_bytes(CASES.read_bytes())
    pairs = [
        ("MIRACULA_DETERMINISM_ALPHA", "alpha"),
        ("MIRACULA_DETERMINISM_BETA", "beta"),
        ("MIRACULA_DETERMINISM_GAMMA", "gamma"),
    ]
    if run % 2:
        pairs.reverse()
    environment = dict(os.environ)
    for key, value in pairs:
        environment[key] = value
    for stage in STAGES:
        subprocess.run(
            [
                sys.executable,
                os.fspath(ORACLE),
                "capture",
                "--stage",
                stage,
                "--fixtures",
                os.fspath(fixtures),
            ],
            cwd=ROOT,
            env=environment,
            stdout=subprocess.DEVNULL,
            check=True,
            timeout=30,
        )
    subprocess.run(
        [
            sys.executable,
            "scripts/generate_combinators.py",
            "--write",
            "--output",
            os.fspath(destination / "generated" / "combinator_generated.zig"),
        ],
        cwd=ROOT,
        env=environment,
        stdout=subprocess.DEVNULL,
        check=True,
        timeout=30,
    )


def main() -> int:
    inventory = json.loads(INVENTORY.read_text(encoding="utf-8"))
    if inventory.get("schema") != 1 or inventory.get("byte_order") != "unsigned UTF-8 bytes, ascending":
        raise SystemExit("unsupported Phase 12 unordered-iteration inventory")
    found = unordered_sites()
    expected = inventory["sites"]
    if set(found) != set(expected):
        removed = sorted(set(expected) - set(found))
        added = sorted(set(found) - set(expected))
        raise SystemExit(f"unordered-iteration audit changed: removed={removed}, added={added}")

    for path in sorted((ROOT / "tests" / "oracle" / "fixtures").glob("*.json*")):
        documents = (
            [json.loads(line) for line in path.read_text(encoding="utf-8").splitlines() if line]
            if path.suffix == ".jsonl"
            else [json.loads(path.read_text(encoding="utf-8"))]
        )
        for index, document in enumerate(documents):
            reject_unstable_fields(document, f"{path.name}[{index}]")

    with tempfile.TemporaryDirectory(prefix="miracula-determinism-") as temporary:
        base = Path(temporary)
        runs = [base / f"run-{number}" for number in range(3)]
        for number, destination in enumerate(runs):
            capture_tree(destination, number)
        for candidate in runs[1:]:
            difference = first_difference(runs[0], candidate)
            if difference:
                raise SystemExit(f"cross-process determinism failure: {difference}")

    print(
        f"phase 12 determinism verified: {len(expected)} unordered iteration sites audited; "
        f"{len(STAGES)} stage captures and generated protocol data identical across 3 processes"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
