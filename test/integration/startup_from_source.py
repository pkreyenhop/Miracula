#!/usr/bin/env python3
"""Verify that a clean Miranda library compiles from source at startup."""

from __future__ import annotations

import argparse
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
LIBRARY_FILES = (".version", "auxfile", "helpfile", "prelude", "stdenv.m")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("executable", type=Path)
    args = parser.parse_args()
    executable = args.executable.resolve()
    with tempfile.TemporaryDirectory(prefix="miracula-source-startup-") as directory:
        temp = Path(directory)
        library = temp / "miralib"
        library.mkdir()
        for name in LIBRARY_FILES:
            shutil.copy2(ROOT / "lib" / "miralib" / name, library / name)
        environment = dict(os.environ)
        environment["HOME"] = os.fspath(temp / "home")
        (temp / "home").mkdir()
        completed = subprocess.run(
            [os.fspath(executable), "-lib", os.fspath(library)],
            cwd=temp,
            input=b"/q\n",
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            env=environment,
            timeout=30,
            check=False,
        )
        if completed.returncode != 0:
            print(f"source startup exited {completed.returncode}")
            print(completed.stdout.decode("utf-8", "backslashreplace"))
            print(completed.stderr.decode("utf-8", "backslashreplace"))
            return 1
    print("source-only standard-library startup passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
