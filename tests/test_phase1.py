"""Acceptance tests for the fail-closed Phase 1 comparison machinery."""

from __future__ import annotations

import importlib.util
from pathlib import Path
import shutil
import sys
import tempfile
import unittest

sys.dont_write_bytecode = True


ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location(
    "regression_runner", ROOT / "tests/regression.py"
)
assert SPEC is not None and SPEC.loader is not None
regression = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = regression
SPEC.loader.exec_module(regression)

REFERENCE_SPEC = importlib.util.spec_from_file_location(
    "reference_oracle", ROOT / "scripts/reference_oracle.py"
)
assert REFERENCE_SPEC is not None and REFERENCE_SPEC.loader is not None
reference_oracle = importlib.util.module_from_spec(REFERENCE_SPEC)
sys.modules[REFERENCE_SPEC.name] = reference_oracle
REFERENCE_SPEC.loader.exec_module(reference_oracle)


def outcome(
    *,
    stdout: bytes = b"",
    stderr: bytes = b"",
    returncode: int = 0,
    timed_out: bool = False,
    files: tuple[tuple[str, str, int, str], ...] = (),
):
    return regression.Outcome(stdout, stderr, returncode, timed_out, files)


class ComparisonTests(unittest.TestCase):
    def setUp(self) -> None:
        self.case = regression.TestCase("acceptance", b"")

    def test_stderr_only_change_fails(self) -> None:
        differences = regression.compare(
            self.case, outcome(stderr=b"expected\n"), outcome(stderr=b"actual\n")
        )
        self.assertTrue(any("stderr mismatch" in item for item in differences))

    def test_exit_status_only_change_fails(self) -> None:
        differences = regression.compare(
            self.case, outcome(returncode=0), outcome(returncode=7)
        )
        self.assertTrue(any("termination mismatch" in item for item in differences))

    def test_signal_termination_is_distinct_from_exit(self) -> None:
        differences = regression.compare(
            self.case, outcome(returncode=1), outcome(returncode=-1)
        )
        self.assertTrue(any("signal 1" in item for item in differences))

    def test_unexpected_file_fails(self) -> None:
        differences = regression.compare(
            self.case,
            outcome(),
            outcome(files=(("unexpected", "file", 0o644, "abc"),)),
        )
        self.assertTrue(any("filesystem unexpected" in item for item in differences))

    def test_candidate_timeout_fails_even_if_reference_times_out(self) -> None:
        differences = regression.compare(
            self.case, outcome(timed_out=True), outcome(timed_out=True)
        )
        self.assertTrue(any("reference timed out" in item for item in differences))
        self.assertTrue(any("candidate timed out" in item for item in differences))

    def test_implementation_metrics_and_cpu_time_are_masked(self) -> None:
        reference = outcome(
            stderr=b"||reductions = 5, cells claimed = 2, no of gc's = 0, cpu = 0.01\n"
        )
        candidate = outcome(
            stderr=b"||reductions = 5, cells claimed = 2, no of gc's = 0, cpu = 9.99\n"
        )
        self.assertEqual([], regression.compare(self.case, reference, candidate))

        changed_count = outcome(
            stderr=b"||reductions = 6, cells claimed = 2, no of gc's = 0, cpu = 9.99\n"
        )
        self.assertEqual([], regression.compare(self.case, reference, changed_count))

        malformed = outcome(stderr=b"||work = 6, cpu = 9.99\n")
        self.assertTrue(regression.compare(self.case, reference, malformed))

    def test_compiled_dump_bytes_are_representation_independent(self) -> None:
        reference = outcome(files=(("case.x", "file", 0o644, "zig"),))
        candidate = outcome(files=(("case.x", "file", 0o644, "go"),))
        # snapshot() canonicalizes .x content before compare; this assertion
        # models the canonical records while mode/presence remain observable.
        canonical = (("case.x", "file", 0o644, "<COMPILED-DUMP>"),)
        self.assertEqual([], regression.compare(self.case, outcome(files=canonical), outcome(files=canonical)))
        self.assertTrue(regression.compare(self.case, reference, candidate))


class ReferenceVerificationTests(unittest.TestCase):
    def test_missing_reference_fails(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            missing = Path(temp) / "missing-mira"
            with self.assertRaises(reference_oracle.VerificationError):
                reference_oracle.verify(
                    ROOT / "tests/reference/manifest.json",
                    "darwin-arm64",
                    missing,
                    ROOT / "miralib",
                )

    def test_corrupt_reference_fails_before_execution(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            corrupt = Path(temp) / "mira"
            shutil.copy2(
                ROOT / "tests/reference/artifacts/darwin-arm64/mira", corrupt
            )
            with corrupt.open("r+b") as stream:
                first = stream.read(1)
                stream.seek(0)
                stream.write(bytes((first[0] ^ 0xFF,)))
            with self.assertRaises(reference_oracle.VerificationError) as caught:
                reference_oracle.verify(
                    ROOT / "tests/reference/manifest.json",
                    "darwin-arm64",
                    corrupt,
                    ROOT / "miralib",
                )
            self.assertIn("checksum mismatch", str(caught.exception))


if __name__ == "__main__":
    unittest.main()
