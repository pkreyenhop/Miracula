#!/usr/bin/env python3
"""Prepare and verify the immutable executable used by compatibility tests."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import stat
import subprocess
import sys


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_MANIFEST = ROOT / "tests/reference/manifest.json"


class VerificationError(RuntimeError):
    pass


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def load_manifest(path: Path) -> dict:
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError as exc:
        raise VerificationError(f"reference manifest is missing: {path}") from exc
    except json.JSONDecodeError as exc:
        raise VerificationError(f"invalid reference manifest {path}: {exc}") from exc
    for field in ("fixture_schema_version", "source_commit", "zig_version", "optimization", "miralib", "platforms"):
        if field not in data:
            raise VerificationError(f"reference manifest has no {field!r} field")
    if data["fixture_schema_version"] != 1:
        raise VerificationError(
            f"unsupported fixture schema version: {data['fixture_schema_version']}"
        )
    return data


def host_platform() -> str:
    system = platform.system().lower()
    machine = platform.machine().lower()
    if system == "darwin" and machine in {"arm64", "aarch64"}:
        return "darwin-arm64"
    raise VerificationError(
        f"unsupported reference host {system}-{machine}; expected darwin-arm64"
    )


def library_files(root: Path, config: dict) -> list[Path]:
    excluded_names = set(config["excluded_generated_names"])
    excluded_suffixes = tuple(config["excluded_suffixes"])
    return sorted(
        (
            path
            for path in root.rglob("*")
            if path.is_file()
            and path.name not in excluded_names
            and not path.name.endswith(excluded_suffixes)
        ),
        key=lambda path: path.relative_to(root).as_posix(),
    )


def hash_library(root: Path, config: dict) -> tuple[str, int]:
    digest = hashlib.sha256()
    files = library_files(root, config)
    for path in files:
        relative = path.relative_to(root).as_posix()
        mode = stat.S_IMODE(path.stat().st_mode)
        digest.update(relative.encode("utf-8"))
        digest.update(b"\0")
        digest.update(f"{mode:o}".encode("ascii"))
        digest.update(b"\0")
        digest.update(path.read_bytes())
        digest.update(b"\0")
    return digest.hexdigest(), len(files)


def verify(
    manifest_path: Path,
    platform_name: str,
    binary_override: Path | None,
    library: Path,
) -> Path:
    manifest = load_manifest(manifest_path)
    try:
        platform_config = manifest["platforms"][platform_name]
    except KeyError as exc:
        raise VerificationError(f"manifest has no platform {platform_name!r}") from exc

    binary = binary_override or ROOT / platform_config["binary"]
    if not binary.is_file():
        raise VerificationError(
            f"pinned reference binary is missing: {binary}\n"
            f"run: python3 scripts/reference_oracle.py prepare --platform {platform_name}"
        )
    if not os.access(binary, os.X_OK):
        raise VerificationError(f"pinned reference is not executable: {binary}")

    actual_binary_hash = sha256_file(binary)
    if actual_binary_hash != platform_config["sha256"]:
        raise VerificationError(
            "pinned reference binary checksum mismatch:\n"
            f"  expected: {platform_config['sha256']}\n"
            f"  actual:   {actual_binary_hash}\n"
            f"  binary:   {binary}"
        )

    if not library.is_dir():
        raise VerificationError(f"Miranda library directory is missing: {library}")
    library_hash, file_count = hash_library(library, manifest["miralib"])
    if file_count != manifest["miralib"]["file_count"]:
        raise VerificationError(
            f"Miranda library file count mismatch: expected "
            f"{manifest['miralib']['file_count']}, got {file_count}"
        )
    if library_hash != manifest["miralib"]["sha256"]:
        raise VerificationError(
            "Miranda library checksum mismatch:\n"
            f"  expected: {manifest['miralib']['sha256']}\n"
            f"  actual:   {library_hash}\n"
            f"  library:  {library}"
        )

    try:
        subprocess.run(
            ["git", "cat-file", "-e", f"{manifest['source_commit']}^{{commit}}"],
            cwd=ROOT,
            check=True,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.PIPE,
            text=True,
        )
    except subprocess.CalledProcessError as exc:
        raise VerificationError(
            f"pinned source commit is unavailable: {manifest['source_commit']}"
        ) from exc

    print(
        f"reference verified: platform={platform_name} "
        f"commit={manifest['source_commit']} cases-schema={manifest['fixture_schema_version']}"
    )
    return binary.resolve()


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--manifest", type=Path, default=DEFAULT_MANIFEST, help="reference manifest"
    )
    subparsers = parser.add_subparsers(dest="command", required=True)

    verify_parser = subparsers.add_parser("verify")
    verify_parser.add_argument("--platform", default=None)
    verify_parser.add_argument("--binary", type=Path)
    verify_parser.add_argument("--library", type=Path, default=ROOT / "miralib")

    path_parser = subparsers.add_parser("path")
    path_parser.add_argument("--platform", default=None)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    try:
        platform_name = args.platform or host_platform()
        if args.command == "verify":
            verify(
                args.manifest.resolve(),
                platform_name,
                args.binary.resolve() if args.binary else None,
                args.library.resolve(),
            )
        else:
            manifest = load_manifest(args.manifest.resolve())
            print((ROOT / manifest["platforms"][platform_name]["binary"]).resolve())
    except VerificationError as exc:
        print(f"reference verification failed: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
