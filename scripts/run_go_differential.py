#!/usr/bin/env python3
"""Run the host-pinned Zig-reference differential gate for a Go candidate."""

from __future__ import annotations

import argparse
import subprocess
import sys
from pathlib import Path

import reference_oracle

ROOT = Path(__file__).resolve().parents[1]
MANIFEST = ROOT / "tests" / "reference" / "manifest.json"
LIBRARY = ROOT / "miralib"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--candidate", required=True, type=Path)
    args = parser.parse_args()
    candidate = args.candidate.resolve()
    if not candidate.is_file():
        parser.error(f"candidate does not exist: {candidate}")
    platform_name = reference_oracle.host_platform()
    try:
        reference = reference_oracle.verify(MANIFEST, platform_name, None, LIBRARY)
    except reference_oracle.VerificationError as error:
        print(error, file=sys.stderr)
        return 1
    return subprocess.run(
        [
            sys.executable,
            "tests/regression.py",
            "--candidate",
            str(candidate),
            "--reference",
            str(reference),
            "--library",
            str(LIBRARY),
            "--repository",
            str(ROOT),
        ],
        cwd=ROOT,
        check=False,
    ).returncode


if __name__ == "__main__":
    raise SystemExit(main())
