#!/usr/bin/env python3
"""Acceptance tests for persistent Go translation progress."""

from __future__ import annotations

import json
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))

import phase13_translation as phase13  # noqa: E402


class TranslationStatusAcceptance(unittest.TestCase):
    def setUp(self) -> None:
        self.rules = json.loads(phase13.RULES_PATH.read_text(encoding="utf-8"))
        self.statuses = phase13.load_status()

    def test_completed_package_survives_manifest_regeneration(self) -> None:
        statuses = dict(self.statuses)
        statuses["package:protocol"] = "complete"
        manifest = phase13.build_manifest(self.rules, statuses)
        self.assertEqual(
            phase13.validate(manifest, manifest, self.rules, statuses), []
        )
        protocol = next(
            unit for unit in manifest["translation_units"]
            if unit["id"] == "package:protocol"
        )
        self.assertEqual(protocol["translation_status"], "complete")
        self.assertEqual(protocol["source_files"], [])
        self.assertTrue(all(
            source["translation_status"] in {"complete", "not_ported"}
            for source in manifest["sources"]
            if source["target_package"] == "protocol"
        ))

    def test_unknown_status_is_rejected(self) -> None:
        statuses = dict(self.statuses)
        statuses["package:protocol"] = "started"
        manifest = phase13.build_manifest(self.rules, statuses)
        errors = phase13.validate(manifest, manifest, self.rules, statuses)
        self.assertIn(
            "package:protocol: invalid translation status 'started'", errors
        )


if __name__ == "__main__":
    unittest.main()
