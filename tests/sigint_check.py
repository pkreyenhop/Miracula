#!/usr/bin/env python3
"""Integration check: SIGINT delivered mid-reduction must not crash or hang
the interpreter.

commandLoop() forks a child process per evaluated expression (process() /
evaluateRepl() in src/driver/repl.zig); the child installs dieClean() as its
own SIGINT handler while the parent ignores SIGINT until the child exits.
Ctrl-C during a long computation should therefore: kill only the forked
child (printing "<<...interrupt>>" and exiting 0), leaving the parent REPL
loop alive and able to accept further input.

This is not part of golden_runner.py's byte-identical-output model (timing-
and signal-dependent), so it lives as its own small harness.

Uses fib(32) as the slow computation, timed to take ~1s under a ReleaseFast
build. Build with `zig build -Doptimize=ReleaseFast` before running this --
a Debug build is ~60x slower (fib(32) takes ~60s), which will blow the 10s
communicate() timeout below and report a spurious hang.
"""
import os
import signal
import subprocess
import sys
import time


def main():
    binary_path = "./zig-out/bin/mira"
    if len(sys.argv) > 1:
        binary_path = sys.argv[1]

    if not os.path.exists(binary_path):
        print(f"Error: Binary {binary_path} not found.")
        sys.exit(1)

    script_dir = os.path.dirname(os.path.abspath(__file__))
    fib_path = os.path.join(script_dir, "sigint_corpus", "slow_fib.m")

    proc = subprocess.Popen(
        [binary_path, "-lib", "./miralib", "-hush", fib_path],
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        preexec_fn=os.setsid,
    )

    proc.stdin.write("fib 32\n\n")
    proc.stdin.flush()
    time.sleep(0.3)  # let the forked child start reducing

    pgid = os.getpgid(proc.pid)
    os.killpg(pgid, signal.SIGINT)

    time.sleep(0.3)
    proc.stdin.write("2 + 2\n\n/q\n")
    proc.stdin.flush()

    try:
        out, err = proc.communicate(timeout=10)
    except subprocess.TimeoutExpired:
        proc.kill()
        proc.communicate()
        print("FAIL: mira did not exit after SIGINT + further input (hung)")
        sys.exit(1)

    if "<<...interrupt>>" not in err:
        print("FAIL: expected interrupt notice not seen in stderr")
        print("--- stderr ---")
        print(err)
        sys.exit(1)

    if "4" not in out:
        print("FAIL: parent REPL did not survive to evaluate '2 + 2' after the interrupt")
        print("--- stdout ---")
        print(out)
        sys.exit(1)

    if proc.returncode != 0:
        print(f"FAIL: mira exited with code {proc.returncode} instead of 0")
        sys.exit(1)

    print("PASS: SIGINT during reduction killed only the forked child; parent REPL survived and kept evaluating.")


if __name__ == "__main__":
    main()
