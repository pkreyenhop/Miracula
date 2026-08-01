#!/usr/bin/env python3
"""Acceptance tests for the Go production-cutover contract."""

from __future__ import annotations

import json
import os
from pathlib import Path
import stat
import subprocess
import sys
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))

import go_cutover  # noqa: E402
import run_go_differential  # noqa: E402


class CutoverStatusTests(unittest.TestCase):
    def write_status(self, root: Path, states: dict[str, str]) -> Path:
        spec = root / "spec"
        spec.mkdir(parents=True, exist_ok=True)
        path = spec / "go_cutover_status.json"
        path.write_text(
            json.dumps({"schema": 1, "milestones": states}), encoding="utf-8"
        )
        (spec / "go_translation_status.json").write_text(
            json.dumps({"schema": 1, "units": {"bootstrap": "complete"}}),
            encoding="utf-8",
        )
        return path

    def test_repository_contract_is_valid(self) -> None:
        self.assertEqual(go_cutover.validate(), [])
        self.assertEqual(go_cutover.first_pending(), "09-full-parity")

    def test_unknown_status_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            states = dict.fromkeys(go_cutover.MILESTONES, "pending")
            states["00-contract"] = "started"
            status = self.write_status(root, states)
            errors = go_cutover.validate(status, root)
            self.assertTrue(any("invalid cutover status" in item for item in errors))

    def test_ordered_completion_is_enforced(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            states = dict.fromkeys(go_cutover.MILESTONES, "pending")
            states["01-production-command"] = "complete"
            status = self.write_status(root, states)
            errors = go_cutover.validate(status, root)
            self.assertTrue(any("complete after an earlier pending" in item for item in errors))

    def test_completed_translation_is_required(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            states = dict.fromkeys(go_cutover.MILESTONES, "pending")
            status = self.write_status(root, states)
            (root / "spec/go_translation_status.json").write_text(
                json.dumps({"schema": 1, "units": {"bootstrap": "pending"}}),
                encoding="utf-8",
            )
            errors = go_cutover.validate(status, root)
            self.assertTrue(any("incomplete units" in item for item in errors))

    def test_parser_placeholder_fails_when_parser_claims_complete(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            states = dict.fromkeys(go_cutover.MILESTONES, "pending")
            for milestone in go_cutover.MILESTONES[:4]:
                states[milestone] = "complete"
            status = self.write_status(root, states)
            for relative in go_cutover.CONTRACT_FILES:
                path = root / relative
                path.parent.mkdir(parents=True, exist_ok=True)
                path.touch()
            main = root / "cmd/mira/main.go"
            main.parent.mkdir(parents=True, exist_ok=True)
            main.write_text("package main\n", encoding="utf-8")
            parser = root / "internal/syntaxfront/parser.go"
            parser.parent.mkdir(parents=True, exist_ok=True)
            parser.write_text(
                'return Script{"script", []Definition{}}, nil\n', encoding="utf-8"
            )
            errors = go_cutover.validate(status, root)
            self.assertTrue(any("known placeholder" in item for item in errors))


class CandidateIdentityTests(unittest.TestCase):
    def executable(self, root: Path, name: str, body: str) -> Path:
        path = root / name
        path.write_text(f"#!/bin/sh\n{body}\n", encoding="utf-8")
        path.chmod(path.stat().st_mode | stat.S_IXUSR)
        return path

    def test_go_identity_is_accepted(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            candidate = self.executable(
                root, "candidate", "printf 'implementation=go\\nversion=test\\n'"
            )
            reference = self.executable(root, "reference", "exit 0")
            run_go_differential.verify_candidate(candidate, reference)

    def test_reference_candidate_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            reference = self.executable(root, "reference", "exit 0")
            with self.assertRaisesRegex(
                run_go_differential.CandidateError, "pinned Zig reference"
            ):
                run_go_differential.verify_candidate(reference, reference)

    def test_unidentified_candidate_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            candidate = self.executable(root, "candidate", "printf 'Miranda\\n'")
            reference = self.executable(root, "reference", "exit 0")
            with self.assertRaisesRegex(
                run_go_differential.CandidateError, "implementation=go"
            ):
                run_go_differential.verify_candidate(candidate, reference)

    def test_excessive_identity_output_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            candidate = self.executable(
                root,
                "candidate",
                f"dd if=/dev/zero bs={run_go_differential.IDENTITY_OUTPUT_LIMIT + 1} count=1 2>/dev/null",
            )
            reference = self.executable(root, "reference", "exit 0")
            with self.assertRaisesRegex(
                run_go_differential.CandidateError, "output limit"
            ):
                run_go_differential.verify_candidate(candidate, reference)


class CandidateBuildTests(unittest.TestCase):
    def test_build_replaces_stale_candidate(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            output = Path(temporary) / "mira-go"
            output.write_text("stale", encoding="utf-8")
            result = subprocess.run(
                [
                    sys.executable,
                    str(ROOT / "scripts/build_go_candidate.py"),
                    "--output",
                    str(output),
                ],
                cwd=ROOT,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                timeout=10,
                check=False,
            )
            self.assertEqual(result.returncode, 0, result.stderr.decode())
            self.assertNotEqual(output.read_bytes(), b"stale")
            identity = subprocess.run(
                [output, "--build-info"],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                timeout=5,
                check=False,
            )
            self.assertEqual(identity.returncode, 0)
            self.assertIn(b"implementation=go\n", identity.stdout)

if __name__ == "__main__":
    unittest.main()
