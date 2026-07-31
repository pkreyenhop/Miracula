#!/usr/bin/env python3
"""Run the host-pinned Zig-reference differential gate for a Go candidate."""

from __future__ import annotations

import argparse
import hashlib
import os
import subprocess
import sys
from pathlib import Path

import reference_oracle

ROOT = Path(__file__).resolve().parents[1]
MANIFEST = ROOT / "tests" / "reference" / "manifest.json"
LIBRARY = ROOT / "miralib"
IDENTITY_TIMEOUT_SECONDS = 5
IDENTITY_OUTPUT_LIMIT = 64 * 1024


class CandidateError(RuntimeError):
    pass


def file_hash(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def verify_candidate(candidate: Path, reference: Path) -> None:
    if not candidate.is_file():
        raise CandidateError(f"candidate does not exist: {candidate}")
    if not os.access(candidate, os.X_OK):
        raise CandidateError(f"candidate is not executable: {candidate}")
    if candidate.samefile(reference) or file_hash(candidate) == file_hash(reference):
        raise CandidateError("candidate is the pinned Zig reference, not a Go build")
    try:
        result = subprocess.run(
            [candidate, "--build-info"],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=IDENTITY_TIMEOUT_SECONDS,
            check=False,
        )
    except subprocess.TimeoutExpired as error:
        raise CandidateError("candidate --build-info timed out") from error
    if len(result.stdout) > IDENTITY_OUTPUT_LIMIT or len(result.stderr) > IDENTITY_OUTPUT_LIMIT:
        raise CandidateError("candidate --build-info exceeded the 64 KiB output limit")
    if result.returncode != 0:
        raise CandidateError(
            f"candidate --build-info exited with status {result.returncode}"
        )
    fields: dict[str, str] = {}
    for line in result.stdout.decode("utf-8", errors="replace").splitlines():
        key, separator, value = line.partition("=")
        if separator:
            fields[key.strip()] = value.strip()
    if fields.get("implementation") != "go":
        raise CandidateError(
            "candidate --build-info did not report implementation=go"
        )


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--candidate", required=True, type=Path)
    args = parser.parse_args()
    candidate = args.candidate.resolve()
    platform_name = reference_oracle.host_platform()
    try:
        reference = reference_oracle.verify(MANIFEST, platform_name, None, LIBRARY)
        verify_candidate(candidate, reference)
    except (reference_oracle.VerificationError, CandidateError) as error:
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
