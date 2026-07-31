#!/usr/bin/env python3
"""Capture and verify canonical per-stage migration oracles."""

from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import shlex
import subprocess
import sys
from typing import Any

from protocol import ProtocolError, STAGES, canonical_bytes, load_jsonl, validate_record, write_jsonl

ROOT = Path(__file__).resolve().parents[2]
DEFAULT_FIXTURES = ROOT / "tests" / "oracle" / "fixtures"
DEFAULT_PRODUCER = ROOT / "tests" / "oracle" / "producer.py"


def field_diff(expected: Any, actual: Any, path: str = "$") -> str | None:
    if type(expected) is not type(actual):
        return f"{path}: expected type {type(expected).__name__}, got {type(actual).__name__}"
    if isinstance(expected, dict):
        if tuple(expected) != tuple(actual):
            return f"{path}: expected fields {tuple(expected)!r}, got {tuple(actual)!r}"
        for key in expected:
            difference = field_diff(expected[key], actual[key], f"{path}.{key}")
            if difference:
                return difference
        return None
    if isinstance(expected, list):
        if len(expected) != len(actual):
            return f"{path}: expected {len(expected)} items, got {len(actual)}"
        for index, (left, right) in enumerate(zip(expected, actual)):
            difference = field_diff(left, right, f"{path}[{index}]")
            if difference:
                return difference
        return None
    if expected != actual:
        return f"{path}: expected {expected!r}, got {actual!r}"
    return None


def run_producer(command: list[str], stage: str, cases: Path) -> list[dict[str, Any]]:
    completed = subprocess.run(
        [*command, "--stage", stage, "--cases", os.fspath(cases)],
        cwd=ROOT,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
        check=False,
    )
    if completed.returncode:
        raise ProtocolError(
            f"producer exited {completed.returncode}: "
            f"{completed.stderr.decode('utf-8', 'backslashreplace')}"
        )
    records: list[dict[str, Any]] = []
    for line_number, raw in enumerate(completed.stdout.splitlines(keepends=True), 1):
        if not raw.endswith(b"\n"):
            raise ProtocolError(f"producer line {line_number}: missing newline")
        try:
            record = json.loads(raw.decode("ascii"))
        except (UnicodeDecodeError, json.JSONDecodeError) as error:
            raise ProtocolError(f"producer line {line_number}: invalid JSON: {error}") from error
        validate_record(record, stage)
        if canonical_bytes(record) != raw:
            raise ProtocolError(f"producer line {line_number}: non-canonical encoding")
        records.append(record)
    ids = [record["case_id"] for record in records]
    if ids != sorted(ids) or len(ids) != len(set(ids)):
        raise ProtocolError("producer records must have unique, sorted case IDs")
    return records


def producer_command(value: str | None) -> list[str]:
    if value:
        return shlex.split(value)
    return [sys.executable, os.fspath(DEFAULT_PRODUCER)]


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("operation", choices=("capture", "verify"))
    parser.add_argument("--stage", required=True, choices=STAGES)
    parser.add_argument("--producer", help="external producer command")
    parser.add_argument("--fixtures", type=Path, default=DEFAULT_FIXTURES)
    args = parser.parse_args()
    expected_path = args.fixtures / f"{args.stage}.jsonl"
    cases_path = args.fixtures / "cases.json"
    try:
        actual = run_producer(producer_command(args.producer), args.stage, cases_path)
        if args.operation == "capture":
            write_jsonl(expected_path, actual, args.stage)
            print(f"captured {len(actual)} {args.stage} oracle cases")
            return 0
        expected = load_jsonl(expected_path, args.stage)
        if len(expected) != len(actual):
            raise ProtocolError(
                f"{args.stage}: expected {len(expected)} records, got {len(actual)}"
            )
        for wanted, observed in zip(expected, actual):
            case_id = wanted["case_id"]
            if observed["case_id"] != case_id:
                raise ProtocolError(
                    f"{args.stage}: expected case {case_id!r}, got {observed['case_id']!r}"
                )
            difference = field_diff(wanted, observed)
            if difference:
                raise ProtocolError(f"{args.stage}/{case_id}: {difference}")
        print(f"verified {len(actual)} {args.stage} oracle cases")
        return 0
    except (ProtocolError, subprocess.TimeoutExpired, OSError) as error:
        print(f"oracle verification failed: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
