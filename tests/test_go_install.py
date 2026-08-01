#!/usr/bin/env python3
"""Installed-product and deterministic-release smoke tests."""

from __future__ import annotations

import hashlib
import os
from pathlib import Path
import subprocess
import sys
import tarfile
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
PACKAGER = ROOT / "scripts/package_go.py"


class InstalledProductTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory(prefix="miracula-install-")
        self.root = Path(self.temporary.name)
        self.destdir = self.root / "stage"
        self.prefix = Path("/opt/miracula")
        subprocess.run(
            [sys.executable, PACKAGER, "install", "--prefix", self.prefix, "--destdir", self.destdir],
            cwd=ROOT, check=True, timeout=120,
        )
        self.binary = self.destdir / "opt/miracula/bin/mira"

    def tearDown(self) -> None:
        self.temporary.cleanup()

    def run_mira(self, input_bytes: bytes, *arguments: str) -> subprocess.CompletedProcess[bytes]:
        environment = {"HOME": str(self.root / "home"), "PATH": os.environ.get("PATH", "")}
        return subprocess.run(
            [self.binary, *arguments], cwd=self.root, env=environment, input=input_bytes,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=20, check=False,
        )

    def test_installed_binary_finds_packaged_library(self) -> None:
        result = self.run_mira(b"1+2\n/q\n", "-hush")
        self.assertEqual((result.returncode, result.stdout, result.stderr), (0, b"3\n", b""))
        info = self.run_mira(b"", "--build-info")
        self.assertEqual(info.returncode, 0)
        self.assertIn(b"implementation=go\n", info.stdout)
        self.assertNotIn(b"unknown", info.stdout)
        help_result = self.run_mira(b"/h\n/q\n", "-hush")
        self.assertEqual(help_result.returncode, 0)
        self.assertIn(b"SUMMARY OF MAIN AVAILABLE COMMANDS", help_result.stdout)

    def test_installed_script_execution(self) -> None:
        script = self.root / "square.m"
        script.write_text("square x = x*x\n", encoding="utf-8")
        result = self.run_mira(b"square 12\n/q\n", "-hush", str(script))
        self.assertEqual((result.returncode, result.stdout, result.stderr), (0, b"144\n", b""))

    def test_uninstall_removes_only_installed_product(self) -> None:
        sentinel = self.destdir / "opt/miracula/keep-me"
        sentinel.write_text("user data", encoding="utf-8")
        subprocess.run(
            [sys.executable, PACKAGER, "uninstall", "--prefix", self.prefix, "--destdir", self.destdir],
            cwd=ROOT, check=True,
        )
        self.assertFalse(self.binary.exists())
        self.assertFalse((self.destdir / "opt/miracula/lib/miralib").exists())
        self.assertTrue(sentinel.exists())

    def test_archive_is_deterministic_and_excludes_developer_artifacts(self) -> None:
        environment = dict(os.environ, SOURCE_DATE_EPOCH="1700000000")
        first, second = self.root / "first.tar.gz", self.root / "second.tar.gz"
        for output in (first, second):
            subprocess.run(
                [sys.executable, PACKAGER, "archive", "--output", output],
                cwd=ROOT, env=environment, check=True, timeout=120,
            )
        self.assertEqual(hashlib.sha256(first.read_bytes()).digest(), hashlib.sha256(second.read_bytes()).digest())
        with tarfile.open(first, "r:gz") as archive:
            names = archive.getnames()
        self.assertIn("miracula/bin/mira", names)
        self.assertTrue(any(name.endswith("/miralib/prelude") for name in names))
        self.assertFalse(any(name.endswith(".x") or "__pycache__" in name for name in names))


if __name__ == "__main__":
    unittest.main()
