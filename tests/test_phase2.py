#!/usr/bin/env python3
"""Acceptance tests for the language-neutral stage-oracle verifier."""

from __future__ import annotations

import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import textwrap
import unittest

ROOT = Path(__file__).resolve().parents[1]
ORACLE = ROOT / "tests" / "oracle" / "oracle.py"
FIXTURES = ROOT / "tests" / "oracle" / "fixtures"


class Phase2Acceptance(unittest.TestCase):
    def run_oracle(
        self, stage: str, fixtures: Path, producer: Path | None = None
    ) -> subprocess.CompletedProcess[str]:
        command = [
            sys.executable,
            str(ORACLE),
            "verify",
            "--stage",
            stage,
            "--fixtures",
            str(fixtures),
        ]
        if producer is not None:
            command.extend(["--producer", f"{sys.executable} {producer}"])
        return subprocess.run(
            command,
            cwd=ROOT,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=False,
        )

    def test_external_non_zig_producer_is_accepted(self) -> None:
        result = self.run_oracle("lex", FIXTURES)
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_semantic_mutation_reports_case_and_field(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            temp = Path(directory)
            shutil.copytree(FIXTURES, temp / "fixtures")
            producer = temp / "mutate.py"
            producer.write_text(
                textwrap.dedent(
                    f"""\
                    import json, subprocess, sys
                    command = [{sys.executable!r}, {str(ROOT / "tests/oracle/producer.py")!r}, *sys.argv[1:]]
                    result = subprocess.run(command, stdout=subprocess.PIPE, check=True)
                    records = [json.loads(line) for line in result.stdout.splitlines()]
                    records[0]["payload"]["tokens"][0]["kind"] = "changed"
                    for record in records:
                        print(json.dumps(record, ensure_ascii=True, allow_nan=False, separators=(",", ":"), sort_keys=False))
                    """
                ),
                encoding="utf-8",
            )
            result = self.run_oracle("lex", temp / "fixtures", producer)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("empty", result.stderr)
            self.assertIn("$.payload.tokens[0].kind", result.stderr)

    def test_noncanonical_field_order_fails(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            temp = Path(directory)
            shutil.copytree(FIXTURES, temp / "fixtures")
            path = temp / "fixtures" / "source.jsonl"
            first = json.loads(path.read_text(encoding="ascii").splitlines()[0])
            first = {"stage": first.pop("stage"), **first}
            path.write_text(
                json.dumps(first, separators=(",", ":")) + "\n",
                encoding="ascii",
            )
            result = self.run_oracle("source", temp / "fixtures")
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("fields must be ordered", result.stderr)

    def test_missing_fixture_fails_closed(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            temp = Path(directory)
            shutil.copytree(FIXTURES, temp / "fixtures")
            (temp / "fixtures" / "dump.jsonl").unlink()
            result = self.run_oracle("dump", temp / "fixtures")
            self.assertNotEqual(result.returncode, 0)

    def test_invalid_schema_version_fails(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            temp = Path(directory)
            shutil.copytree(FIXTURES, temp / "fixtures")
            path = temp / "fixtures" / "module.jsonl"
            lines = path.read_text(encoding="ascii").splitlines()
            record = json.loads(lines[0])
            record["schema_version"] = 999
            lines[0] = json.dumps(record, separators=(",", ":"))
            path.write_text("\n".join(lines) + "\n", encoding="ascii")
            result = self.run_oracle("module", temp / "fixtures")
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("unsupported version", result.stderr)

    def test_every_stage_has_success_and_failure_coverage(self) -> None:
        cases = json.loads((FIXTURES / "cases.json").read_text(encoding="utf-8"))
        for stage in (
            "source",
            "lex",
            "layout",
            "parse",
            "module",
            "typecheck",
            "lower",
            "reduce",
            "dump",
        ):
            outcomes = {
                case["stages"][stage]["outcome"]
                for case in cases
                if stage in case["stages"]
            }
            self.assertIn("success", outcomes, stage)
            self.assertIn("failure", outcomes, stage)

    def test_every_planned_package_maps_to_a_known_stage(self) -> None:
        mapping = json.loads(
            (ROOT / "tests/oracle/package-map.json").read_text(encoding="utf-8")
        )
        known = {
            "source", "lex", "layout", "parse", "module",
            "typecheck", "lower", "reduce", "dump",
        }
        self.assertTrue(mapping)
        for package, stages in mapping.items():
            self.assertTrue(stages, package)
            self.assertTrue(set(stages) <= known, package)


if __name__ == "__main__":
    unittest.main()
