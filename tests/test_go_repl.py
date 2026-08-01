#!/usr/bin/env python3
"""Black-box checks for the production Go Miranda REPL."""

from pathlib import Path
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]


class GoReplTests(unittest.TestCase):
    def test_piped_expression_has_no_prompt_and_recovers(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            binary = Path(temporary) / "mira"
            subprocess.run(
                ["go", "build", "-o", binary, "./cmd/mira"],
                cwd=ROOT,
                check=True,
            )
            result = subprocess.run(
                [binary, "-lib", ROOT / "miralib", "-hush"],
                cwd=ROOT,
                input=b"1 div 0\n1+2\n/q\n",
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                check=True,
            )
            self.assertEqual(result.stdout, b"3\n")
            self.assertEqual(result.stderr, b"\nprogram error: attempt to divide by zero\n")


if __name__ == "__main__":
    unittest.main()
