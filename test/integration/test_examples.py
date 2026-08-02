#!/usr/bin/env python3
"""Compile and exercise every checked-in program in examples/."""

from __future__ import annotations

import os
from pathlib import Path
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parents[2]
BINARY = ROOT / "build" / "mira"
EXAMPLES = ROOT / "examples"

# Observable results documented by each example program. New example files
# must be added here so the test checks meaning, not merely successful loading.
CASES = {
    "basic.m": (
        ("add1 2", "3"),
        ("fib 12", "144"),
        ("l", "[1,2,3]"),
        ("x", "3"),
    ),
}


def main() -> None:
    files = sorted(path.name for path in EXAMPLES.glob("*.m"))
    if files != sorted(CASES):
        missing = sorted(set(files) - set(CASES))
        stale = sorted(set(CASES) - set(files))
        raise SystemExit(f"example expectations need updating: missing={missing}, stale={stale}")

    for filename in files:
        commands = "\n".join(expression for expression, _ in CASES[filename]) + "\n/q\n"
        with tempfile.TemporaryDirectory() as home:
            completed = subprocess.run(
                [str(BINARY), "-hush", str(EXAMPLES / filename)],
                input=commands,
                text=True,
                capture_output=True,
                cwd=ROOT,
                env={**os.environ, "HOME": home},
                timeout=30,
                check=False,
            )
        if completed.returncode != 0:
            raise SystemExit(f"{filename} failed:\n{completed.stdout}{completed.stderr}")
        output = [line.strip() for line in completed.stdout.splitlines() if line.strip()]
        for expression, expected in CASES[filename]:
            if expected not in output:
                raise SystemExit(
                    f"{filename}: {expression!r} did not produce {expected!r}; output={output!r}"
                )

    print(f"examples: {len(files)} program(s), all results correct")


if __name__ == "__main__":
    main()
