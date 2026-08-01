#!/usr/bin/env python3
"""Pseudo-terminal acceptance checks for interactive-only REPL behavior."""

from __future__ import annotations

import errno
import os
from pathlib import Path
import pty
import re
import select
import signal
import subprocess
import tempfile
import time
import unittest


ROOT = Path(__file__).resolve().parents[2]


class InteractiveReplTests(unittest.TestCase):
    def test_editing_completion_timing_comments_and_logout(self) -> None:
        with tempfile.TemporaryDirectory(prefix="miracula-pty-") as temporary:
            work = Path(temporary)
            binary = work / "mira"
            script = work / "interactive.m"
            script.write_text("alpha = 1\nalphabet = 2\n", encoding="utf-8")
            subprocess.run(
                ["go", "build", "-o", binary, "./cmd/mira"],
                cwd=ROOT,
                check=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
            )
            master, slave = pty.openpty()
            environment = os.environ.copy()
            environment["HOME"] = temporary
            process = subprocess.Popen(
                [binary, "-lib", ROOT / "lib/miralib", script],
                cwd=work,
                env=environment,
                stdin=slave,
                stdout=slave,
                stderr=slave,
                start_new_session=True,
            )
            os.close(slave)
            transcript = bytearray()

            def read_until(pattern: bytes, timeout: float = 10) -> None:
                deadline = time.monotonic() + timeout
                while not re.search(pattern, bytes(transcript), re.DOTALL):
                    if time.monotonic() >= deadline:
                        self.fail(f"timed out waiting for {pattern!r}: {transcript!r}")
                    ready, _, _ = select.select([master], [], [], 0.1)
                    if not ready:
                        continue
                    try:
                        chunk = os.read(master, 4096)
                    except OSError as error:
                        if error.errno == errno.EIO:
                            break
                        raise
                    if not chunk:
                        break
                    transcript.extend(chunk)

            try:
                read_until(rb"Miranda ")
                os.write(master, b"alphab\t\n")
                read_until(rb"2\r?\n\[[0-9.]+(?:ms|s)(?:, [0-9]+ GCs?)?\] Miranda ")
                os.write(master, b"|| ignored\n")
                os.write(master, b"| unknown\n")
                read_until(rb"\x07unknown command - type /h for help")
                os.write(master, b"[1..]\n")
                read_until(rb"\[1,2,3,4,5,6,7,8,9,10,")
                process.send_signal(signal.SIGINT)
                read_until(rb"<<\.\.\.interrupt>>.*Miranda ")
                os.write(master, b"/q\n")
                read_until(rb"miranda logout")
                self.assertEqual(process.wait(timeout=5), 0)
            finally:
                os.close(master)
                if process.poll() is None:
                    process.terminate()
                    process.wait(timeout=5)


if __name__ == "__main__":
    unittest.main()
