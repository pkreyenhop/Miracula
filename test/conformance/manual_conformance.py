#!/usr/bin/env python3
"""Production-binary smoke corpus and manual-section coverage validator."""

import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile


ROOT = Path(__file__).resolve().parents[2]
MANIFEST = Path(__file__).with_name("manual_sections.json")


def main() -> None:
    binary = Path(sys.argv[1]).resolve()
    manifest = json.loads(MANIFEST.read_text())
    sections = manifest["sections"]
    assert [entry["section"] for entry in sections] == [str(number) for number in range(1, 35)]
    for entry in sections:
        assert entry["status"] in {"covered", "non-normative"}
        assert entry.get("tests") if entry["status"] == "covered" else entry.get("reason")

    cases = [
        ("arithmetic", "1+2", "3"),
        ("literals", "('x',0x10,0o10)", "('x',16,8)"),
        ("definitions", "sum [40,2]", "42"),
        ("lists", "take 5 ([1..] ++ [99])", "[1,2,3,4,5]"),
        ("comprehensions", "take 3 [n*n | n <- [1..]]", "[1,4,9]"),
        ("show", "reverse [1..3]", "[3,2,1]"),
    ]
    with tempfile.TemporaryDirectory() as temporary:
        script = "\n".join(expression for _, expression, _ in cases) + "\n/q\n"
        result = subprocess.run(
            [binary, "-lib", str(ROOT / "lib/miralib"), "-hush"],
            cwd=temporary,
            env={**os.environ, "HOME": temporary},
            input=script,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=True,
        )
    actual = result.stdout.splitlines()
    expected = [value for _, _, value in cases]
    if actual != expected or result.stderr:
        raise AssertionError(f"manual corpus output={actual!r} stderr={result.stderr!r}, expected={expected!r}")
    print(f"manual conformance manifest covers {len(sections)} sections; {len(cases)} production examples passed")


if __name__ == "__main__":
    main()
