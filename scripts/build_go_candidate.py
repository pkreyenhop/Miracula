#!/usr/bin/env python3
"""Build a fresh, identifiable production Go candidate."""

from __future__ import annotations

import argparse
import os
from pathlib import Path
import subprocess
import sys
import tempfile


ROOT = Path(__file__).resolve().parents[1]


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", required=True, type=Path)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    output = args.output.resolve()
    if output.exists() or output.is_symlink():
        if not output.is_file() and not output.is_symlink():
            print(f"Go candidate output is not a file: {output}", file=sys.stderr)
            return 1
        output.unlink()
    command = ROOT / "cmd/mira"
    if not (command / "main.go").is_file():
        print(
            "Go candidate build failed: cmd/mira/main.go does not exist; "
            "complete cutover milestone 01 first",
            file=sys.stderr,
        )
        return 1

    output.parent.mkdir(parents=True, exist_ok=True)
    file_descriptor, temporary_name = tempfile.mkstemp(
        prefix=f".{output.name}.", dir=output.parent
    )
    os.close(file_descriptor)
    temporary = Path(temporary_name)
    temporary.unlink()
    try:
        completed = subprocess.run(
            ["go", "build", "-trimpath", "-o", os.fspath(temporary), "./cmd/mira"],
            cwd=ROOT,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=120,
            check=False,
        )
        if completed.returncode != 0:
            sys.stdout.buffer.write(completed.stdout[: 1024 * 1024])
            sys.stderr.buffer.write(completed.stderr[: 1024 * 1024])
            return completed.returncode
        os.replace(temporary, output)
    except subprocess.TimeoutExpired:
        print("Go candidate build timed out after 120 seconds", file=sys.stderr)
        return 1
    finally:
        temporary.unlink(missing_ok=True)
    print(output)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
