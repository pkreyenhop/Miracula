#!/usr/bin/env python3
"""Atomically replace an installed Go mira with the pinned Zig rollback binary."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import shutil
import tempfile

ROOT = Path(__file__).resolve().parents[1]
MANIFEST = ROOT / "tests/reference/manifest.json"


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def rollback(install_root: Path) -> None:
    if platform.system() != "Darwin" or platform.machine() != "arm64":
        raise SystemExit("reference rollback supports only macOS ARM64")
    manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
    record = manifest["platforms"]["darwin-arm64"]
    reference = ROOT / record["binary"]
    actual = sha256(reference)
    if actual != record["sha256"]:
        raise SystemExit(f"reference checksum mismatch: expected {record['sha256']}, got {actual}")
    binary = install_root.resolve() / "bin" / "mira"
    if not binary.is_file():
        raise SystemExit(f"installed mira not found: {binary}")
    backup = binary.with_name("mira-go-failed")
    if backup.exists():
        raise SystemExit(f"refusing to overwrite rollback backup: {backup}")
    os.replace(binary, backup)
    with tempfile.NamedTemporaryFile(prefix=".mira-rollback-", dir=binary.parent, delete=False) as temporary:
        temporary_path = Path(temporary.name)
        with reference.open("rb") as source:
            shutil.copyfileobj(source, temporary)
    try:
        temporary_path.chmod(0o755)
        os.replace(temporary_path, binary)
    finally:
        temporary_path.unlink(missing_ok=True)
    print(f"installed pinned Zig rollback as {binary}")
    print(f"preserved failed Go binary as {backup}")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--install-root", required=True, type=Path)
    args = parser.parse_args()
    rollback(args.install_root)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
