#!/usr/bin/env python3
"""Black-box acceptance tests for the production Go command boundary."""

from __future__ import annotations

import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]


class GoCommandTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.temporary = tempfile.TemporaryDirectory(prefix="miracula-command-")
        cls.binary = Path(cls.temporary.name) / "mira"
        subprocess.run(
            [
                sys.executable,
                str(ROOT / "tools/package.py"),
                "build",
                "--output",
                str(cls.binary),
            ],
            cwd=ROOT,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=120,
            check=True,
        )

    @classmethod
    def tearDownClass(cls) -> None:
        cls.temporary.cleanup()

    def run_mira(self, *args: str) -> subprocess.CompletedProcess[bytes]:
        environment = {"HOME": self.temporary.name, "PATH": os.environ.get("PATH", "")}
        return subprocess.run(
            [self.binary, *args],
            cwd=self.temporary.name,
            env=environment,
            input=b"/q\n",
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=10,
            check=False,
        )

    def test_build_identity(self) -> None:
        result = self.run_mira("--build-info")
        self.assertEqual(result.returncode, 0)
        self.assertIn(b"implementation=go\n", result.stdout)
        self.assertIn(b"target=darwin/arm64\n", result.stdout)
        self.assertEqual(result.stderr, b"")

    def test_version(self) -> None:
        result = self.run_mira("-version")
        self.assertEqual(result.returncode, 0)
        self.assertRegex(result.stdout, rb"^2\.067 last revised [0-9]{4}-[0-9]{2}-[0-9]{2}\n$")
        self.assertEqual(result.stderr, b"")

    def test_full_version(self) -> None:
        result = self.run_mira("-V")
        self.assertEqual(result.returncode, 0)
        self.assertRegex(
            result.stdout,
            rb"^2\.067 last revised [0-9]{4}-[0-9]{2}-[0-9]{2}\ngo-production-build\nXVERSION 83\n$",
        )

    def test_invalid_option(self) -> None:
        result = self.run_mira("-wat")
        self.assertEqual(result.returncode, 1)
        self.assertEqual(result.stdout, b"")
        self.assertEqual(result.stderr, b'mira: unknown flag "-wat"\n')

    def test_too_many_arguments(self) -> None:
        result = self.run_mira("one", "two")
        self.assertEqual(result.returncode, 1)
        self.assertEqual(result.stderr, b"mira: too many args\n")


if __name__ == "__main__":
    unittest.main()
