#!/usr/bin/env python3
"""Exercise the production rollback procedure in an isolated install prefix."""

from __future__ import annotations

import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class RollbackTests(unittest.TestCase):
    def test_installed_go_binary_can_be_replaced_by_verified_reference(self) -> None:
        with tempfile.TemporaryDirectory(prefix="miracula-rollback-") as temporary:
            stage = Path(temporary) / "stage"
            prefix = Path("/opt/miracula")
            subprocess.run(
                [sys.executable, "scripts/package_go.py", "install", "--prefix", prefix, "--destdir", stage],
                cwd=ROOT, check=True, timeout=120,
            )
            install_root = stage / "opt/miracula"
            binary = install_root / "bin/mira"
            go_info = subprocess.run(
                [binary, "--build-info"], stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                check=True, timeout=10,
            )
            self.assertIn(b"implementation=go\n", go_info.stdout)
            subprocess.run(
                [sys.executable, "scripts/install_reference_rollback.py", "--install-root", install_root],
                cwd=ROOT, check=True, timeout=30,
            )
            environment = dict(os.environ, MIRALIB=str(install_root / "lib/miralib"))
            reference_version = subprocess.run(
                [binary, "-version"], env=environment, stdout=subprocess.PIPE,
                stderr=subprocess.PIPE, check=True, timeout=10,
            )
            self.assertTrue(reference_version.stdout.startswith(b"2.067 last revised"))
            preserved = install_root / "bin/mira-go-failed"
            self.assertTrue(preserved.is_file())
            preserved_info = subprocess.run(
                [preserved, "--build-info"], stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                check=True, timeout=10,
            )
            self.assertIn(b"implementation=go\n", preserved_info.stdout)


if __name__ == "__main__":
    unittest.main()
