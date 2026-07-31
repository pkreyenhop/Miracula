#!/usr/bin/env python3
"""Fail-closed executable differential tests for the pinned Miranda oracle."""

from __future__ import annotations

import argparse
from dataclasses import dataclass
import hashlib
import os
from pathlib import Path
import re
import shutil
import stat
import subprocess
import sys
import tempfile


@dataclass(frozen=True)
class TestCase:
    name: str
    input: bytes
    script_content: bytes | None = None
    script_path: str | None = None
    support_files: tuple[str, ...] = ()


CASES = (
    TestCase("arithmetic_1_plus_2", b"1+2\n/q\n"),
    TestCase("factorial_10", b"product [1..10]\n/q\n"),
    TestCase("map_double", b"map (2*) [1..5]\n/q\n"),
    TestCase(
        "big_integers",
        b"12345678901234567890 + 10\n2^80\n/q\n",
    ),
    TestCase(
        "lazy_lists_and_strings",
        b'take 5 [1..]\nreverse [1,2,3]\nzip2 [1,2,3] [4,5,6]\n"abc" ++ "def"\n/q\n',
    ),
    TestCase(
        "fibonacci_script",
        b"fib 10\n/q\n",
        script_path="miralib/ex/fib.m",
    ),
    TestCase(
        "user_defined_script",
        b"square 12\ntwice square 2\npairup 1 2\n/q\n",
        script_content=b"square x = x*x\ntwice f x = f (f x)\npairup x y = (x,y)\n",
    ),
    TestCase("hex_octal_literals", b"0xff\n0x1A2B3C\n0o777\n\n/q\n"),
    TestCase(
        "literate_script",
        b"square 5\ncube 3\n\n/q\n",
        script_content=(
            b"> square x = x * x\n> cube x  = x * x * x\n\n"
            b"Prose below the code lines is not Miranda source.\n"
        ),
    ),
    TestCase(
        "insert_directive",
        b"r\n\n/q\n",
        script_content=b'%insert "directive_insert_body.txt"\n\nr = inserted_val + 1\n',
        support_files=("tests/golden/directive_insert_body.txt",),
    ),
)


@dataclass(frozen=True)
class Outcome:
    stdout: bytes
    stderr: bytes
    returncode: int
    timed_out: bool
    files: tuple[tuple[str, str, int, str], ...]


CPU_STAT = re.compile(rb"(?m)^(\|\|.*,\s*cpu\s*=\s*)[0-9]+(?:\.[0-9]+)?$")


def comparable_stderr(value: bytes) -> bytes:
    """Mask only nondeterministic CPU time; every other stderr byte is exact."""
    return CPU_STAT.sub(rb"\1<TIME>", value)


def snapshot(root: Path) -> tuple[tuple[str, str, int, str], ...]:
    entries: list[tuple[str, str, int, str]] = []
    for path in sorted(root.rglob("*"), key=lambda value: value.relative_to(root).as_posix()):
        relative = path.relative_to(root).as_posix()
        info = path.lstat()
        mode = stat.S_IMODE(info.st_mode)
        if path.is_symlink():
            entries.append((relative, "symlink", mode, os.readlink(path)))
        elif path.is_dir():
            entries.append((relative, "directory", mode, ""))
        elif path.is_file():
            entries.append(
                (relative, "file", mode, hashlib.sha256(path.read_bytes()).hexdigest())
            )
        else:
            entries.append((relative, "other", mode, ""))
    return tuple(entries)


def prepare_case(root: Path, case: TestCase, repository: Path) -> Path | None:
    for support in case.support_files:
        source = repository / support
        shutil.copy2(source, root / source.name)
    if case.script_content is not None:
        script = root / "case.m"
        script.write_bytes(case.script_content)
        return script
    if case.script_path is not None:
        return repository / case.script_path
    return None


def run(
    binary: Path,
    library: Path,
    repository: Path,
    case: TestCase,
    timeout: float,
) -> Outcome:
    with tempfile.TemporaryDirectory(prefix=f"miracula-{case.name}-") as temp:
        workdir = Path(temp)
        script = prepare_case(workdir, case, repository)
        argv = [
            str(binary),
            "-lib",
            str(library),
            "-hush",
            "-count",
        ]
        if script is not None:
            argv.append(str(script))
        try:
            completed = subprocess.run(
                argv,
                cwd=workdir,
                input=case.input,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                timeout=timeout,
                check=False,
            )
            return Outcome(
                stdout=completed.stdout,
                stderr=completed.stderr,
                returncode=completed.returncode,
                timed_out=False,
                files=snapshot(workdir),
            )
        except subprocess.TimeoutExpired as exc:
            return Outcome(
                stdout=exc.stdout or b"",
                stderr=exc.stderr or b"",
                returncode=-1,
                timed_out=True,
                files=snapshot(workdir),
            )


def describe_returncode(code: int) -> str:
    if code < 0:
        return f"signal {-code}"
    return f"exit {code}"


def compare(case: TestCase, expected: Outcome, actual: Outcome) -> list[str]:
    differences: list[str] = []
    if expected.timed_out:
        differences.append("reference timed out; the oracle case is invalid")
    if actual.timed_out:
        differences.append("candidate timed out")
    if expected.returncode != actual.returncode:
        differences.append(
            "termination mismatch: reference "
            f"{describe_returncode(expected.returncode)}, candidate "
            f"{describe_returncode(actual.returncode)}"
        )
    if expected.stdout != actual.stdout:
        differences.append(
            f"stdout mismatch ({len(expected.stdout)} reference bytes, "
            f"{len(actual.stdout)} candidate bytes)"
        )
    expected_stderr = comparable_stderr(expected.stderr)
    actual_stderr = comparable_stderr(actual.stderr)
    if expected_stderr != actual_stderr:
        differences.append(
            f"stderr mismatch after CPU-time masking ({len(expected.stderr)} "
            f"reference bytes, {len(actual.stderr)} candidate bytes)"
        )
    if expected.files != actual.files:
        expected_set = set(expected.files)
        actual_set = set(actual.files)
        for entry in sorted(expected_set - actual_set):
            differences.append(f"filesystem missing/different: {entry}")
        for entry in sorted(actual_set - expected_set):
            differences.append(f"filesystem unexpected/different: {entry}")
    return differences


def existing_file(value: str) -> Path:
    path = Path(value).resolve()
    if not path.is_file():
        raise argparse.ArgumentTypeError(f"file does not exist: {value}")
    return path


def existing_dir(value: str) -> Path:
    path = Path(value).resolve()
    if not path.is_dir():
        raise argparse.ArgumentTypeError(f"directory does not exist: {value}")
    return path


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--candidate", required=True, type=existing_file)
    parser.add_argument("--reference", required=True, type=existing_file)
    parser.add_argument("--library", required=True, type=existing_dir)
    parser.add_argument("--repository", type=existing_dir, default=Path.cwd())
    parser.add_argument("--timeout", type=float, default=10.0)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    executed = 0
    passed = 0
    failed = 0
    skipped = 0

    for case in CASES:
        executed += 1
        print(f"Running differential case: {case.name} ... ", end="", flush=True)
        reference = run(
            args.reference, args.library, args.repository, case, args.timeout
        )
        candidate = run(
            args.candidate, args.library, args.repository, case, args.timeout
        )
        differences = compare(case, reference, candidate)
        if differences:
            failed += 1
            print("FAIL")
            for difference in differences:
                print(f"  {difference}")
            if reference.stdout != candidate.stdout:
                print(f"  reference stdout: {reference.stdout!r}")
                print(f"  candidate stdout: {candidate.stdout!r}")
            if reference.stderr != candidate.stderr:
                print(f"  reference stderr: {reference.stderr!r}")
                print(f"  candidate stderr: {candidate.stderr!r}")
        else:
            passed += 1
            print("PASS")

    print(
        f"Differential summary: executed={executed} passed={passed} "
        f"failed={failed} skipped={skipped}"
    )
    if executed == 0 or skipped != 0 or failed != 0:
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
