#!/usr/bin/env python3
"""Build, install, archive, and clean the production Go Miranda release."""

from __future__ import annotations

import argparse
import gzip
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tarfile
import tempfile

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_EPOCH = 0


def git_value(*arguments: str) -> str:
    result = subprocess.run(
        ["git", *arguments], cwd=ROOT, text=True, stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL, check=False,
    )
    return result.stdout.strip() if result.returncode == 0 else "unknown"


def metadata() -> tuple[str, str, str]:
    commit = git_value("rev-parse", "HEAD")
    epoch = int(os.environ.get("SOURCE_DATE_EPOCH") or git_value("show", "-s", "--format=%ct", "HEAD") or DEFAULT_EPOCH)
    date = subprocess.run(
        ["date", "-u", "-r", str(epoch), "+%Y-%m-%d"], text=True,
        stdout=subprocess.PIPE, check=True,
    ).stdout.strip()
    host = "go-production-build"
    return commit, date, host


def build(output: Path) -> None:
    commit, date, host = metadata()
    output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="miracula-build-") as temporary:
        candidate = Path(temporary) / "mira"
        ldflags = " ".join((
            "-s", "-w",
            f"-X=github.com/pkreyenhop/miracula-go/internal/buildcfg.Commit={commit}",
            f"-X=github.com/pkreyenhop/miracula-go/internal/buildcfg.VersionDate={date}",
            f"-X=github.com/pkreyenhop/miracula-go/internal/buildcfg.Host={host}",
        ))
        subprocess.run(
            ["go", "build", "-trimpath", "-buildvcs=false", "-ldflags", ldflags,
             "-o", candidate, "./cmd/mira"],
            cwd=ROOT, check=True,
        )
        os.replace(candidate, output)


def destination(prefix: Path, destdir: Path) -> Path:
    if not prefix.is_absolute():
        raise SystemExit("--prefix must be absolute")
    return destdir / prefix.relative_to(prefix.anchor)


def copy_library(target: Path) -> None:
    shutil.copytree(
        ROOT / "miralib", target, dirs_exist_ok=True,
        ignore=shutil.ignore_patterns("*.x", "__pycache__", ".DS_Store"),
    )


def install(prefix: Path, destdir: Path) -> None:
    target = destination(prefix, destdir)
    binary = target / "bin" / "mira"
    build(binary)
    library = target / "lib" / "miralib"
    copy_library(library)
    docs = target / "share" / "doc" / "miracula"
    docs.mkdir(parents=True, exist_ok=True)
    shutil.copy2(ROOT / "README.md", docs / "README.md")
    shutil.copy2(ROOT / "miralib" / "COPYING", docs / "COPYING")


def uninstall(prefix: Path, destdir: Path) -> None:
    target = destination(prefix, destdir)
    (target / "bin" / "mira").unlink(missing_ok=True)
    shutil.rmtree(target / "lib" / "miralib", ignore_errors=True)
    shutil.rmtree(target / "share" / "doc" / "miracula", ignore_errors=True)


def archive(output: Path) -> None:
    epoch = int(os.environ.get("SOURCE_DATE_EPOCH") or git_value("show", "-s", "--format=%ct", "HEAD") or DEFAULT_EPOCH)
    output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="miracula-package-") as temporary:
        staging = Path(temporary) / "miracula"
        install(Path("/"), staging)
        with output.open("wb") as raw:
            with gzip.GzipFile(filename="", mode="wb", fileobj=raw, mtime=epoch) as compressed:
                with tarfile.open(fileobj=compressed, mode="w") as tar:
                    for path in sorted(staging.rglob("*")):
                        info = tar.gettarinfo(path, arcname=(Path("miracula") / path.relative_to(staging)).as_posix())
                        info.uid = info.gid = 0
                        info.uname = info.gname = "root"
                        info.mtime = epoch
                        if info.isfile():
                            with path.open("rb") as stream:
                                tar.addfile(info, stream)
                        else:
                            tar.addfile(info)


def clean() -> None:
    for relative in ("build", ".zig-cache", "zig-out"):
        shutil.rmtree(ROOT / relative, ignore_errors=True)
    for relative in ("mira", "fdate", "just", "miralib/menudriver", "tests/utf8_tests", "tests/mira_tests"):
        (ROOT / relative).unlink(missing_ok=True)
    for path in ROOT.rglob("*.x"):
        path.unlink()


def main() -> int:
    parser = argparse.ArgumentParser()
    commands = parser.add_subparsers(dest="command", required=True)
    build_parser = commands.add_parser("build")
    build_parser.add_argument("--output", type=Path, default=ROOT / "build/mira")
    for name in ("install", "uninstall"):
        item = commands.add_parser(name)
        item.add_argument("--prefix", type=Path, default=Path("/usr/local"))
        item.add_argument("--destdir", type=Path, default=Path("/"))
    archive_parser = commands.add_parser("archive")
    archive_parser.add_argument("--output", type=Path, default=ROOT / "build/miracula-darwin-arm64.tar.gz")
    commands.add_parser("clean")
    args = parser.parse_args()
    if args.command == "build": build(args.output.resolve())
    elif args.command == "install": install(args.prefix, args.destdir)
    elif args.command == "uninstall": uninstall(args.prefix, args.destdir)
    elif args.command == "archive": archive(args.output.resolve())
    elif args.command == "clean": clean()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
