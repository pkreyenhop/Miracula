#!/usr/bin/env python3
"""Reference external producer for the stage-oracle contract.

This executable deliberately has no Zig imports. A future package can replace
it with `--producer` and be checked before a complete replacement executable
exists.
"""

from __future__ import annotations

import argparse
import base64
import json
from pathlib import Path
import sys
from typing import Any

from protocol import STAGES, canonical_bytes, input_identity


def diagnostic(
    severity: str,
    message: str,
    file: str | None = None,
    start: int | None = None,
    end: int | None = None,
    line: int | None = None,
    column: int | None = None,
) -> dict[str, Any]:
    return {
        "severity": severity,
        "message": message,
        "file": file,
        "start": start,
        "end": end,
        "line": line,
        "column": column,
    }


def record(stage: str, case: dict[str, Any]) -> dict[str, Any]:
    raw = base64.b64decode(case["input_base64"], validate=True)
    stage_data = case["stages"][stage]
    outcome = {"kind": stage_data["outcome"]}
    if outcome["kind"] == "failure":
        outcome["failure_type"] = stage_data["failure_type"]
    return {
        "schema_version": 1,
        "stage": stage,
        "case_id": case["id"],
        "input": input_identity(raw),
        "outcome": outcome,
        "payload": stage_data["payload"],
        "diagnostics": [
            diagnostic(**item) for item in stage_data.get("diagnostics", [])
        ],
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--stage", choices=STAGES, required=True)
    parser.add_argument("--cases", type=Path, required=True)
    args = parser.parse_args()
    cases = json.loads(args.cases.read_text(encoding="utf-8"))
    for case in sorted(cases, key=lambda item: item["id"]):
        if args.stage in case["stages"]:
            sys.stdout.buffer.write(canonical_bytes(record(args.stage, case)))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
