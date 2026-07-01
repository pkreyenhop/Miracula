#!/usr/bin/env python3
"""spine_differential_check.py -- differential validation for the explicit
spine stack (src/runtime/reducer/spine.zig), B2 option (b) / Phase 2 of
docs/REMAINING_WORK_PLAN.md.

Runs real Miranda programs through the interpreter with MIRA_VALIDATE_SPINE=1
set, which drives a shadow Spine in lockstep with the live pointer-reversal
primitives (reduce_core.zig's downLeft/downRight/upLeft/upRight, plus
combinators.zig's handleTRY/handleFAIL) and aborts via std.debug.assert on the
first mismatch (see spine.zig's "Shadow-validation hooks" section).

This is *not* a correctness check on program output -- the golden corpus
already covers that. It only asks: did the shadow ever disagree with the live
mechanism? A clean (non-signal, non-panic) exit means no.

Two corpora:
  1. Every tests/golden/*.m + *.in pair (reusing the existing fixtures).
  2. A curated set of real programs from miralib/ex/ (deep recursion, guarded
     multi-equation functions -- which pervasively exercise TRY/FAIL --
     algebraic types, lazy infinite streams), chosen for shapes the golden
     corpus doesn't stress. Two miralib/ex/*.m files (ack.m, queens.m) and
     hanoi.m use n+k patterns that this interpreter's parser/compiler
     currently rejects outright (a genuine, separate, pre-existing bug,
     unrelated to the reducer) -- ack.m is swapped for
     tests/spine_corpus/ack_nk_free.m; queens.m/hanoi.m are skipped.
"""
import os
import subprocess
import sys

MIRA = "./zig-out/bin/mira"
GOLDEN_DIR = "./tests/golden"
EX_DIR = "./miralib/ex"
SPINE_CORPUS_DIR = "./tests/spine_corpus"

# (script path, stdin expression). Sizes are chosen to stay under
# miralib/ex/primes.m's pre-existing, unrelated crash past ~a few hundred
# terms (a separate bug -- not this harness's concern; confirmed to crash
# identically with validation off).
EX_CORPUS = [
    (f"{EX_DIR}/fib.m", "fib 27"),
    (f"{EX_DIR}/quicksort.m", "qsort testdata"),
    (f"{EX_DIR}/treesort.m", "treesort testdata"),
    (f"{EX_DIR}/primes.m", "#(take 150 primes)"),
    (f"{EX_DIR}/hamming.m", "take 30 ham"),
    (f"{EX_DIR}/topsort.m", "topsort [(1,2),(2,3),(1,3),(4,1)]"),
    (f"{SPINE_CORPUS_DIR}/ack_nk_free.m", "ack 3 6"),
]

CRASH_MARKERS = ("panic", "uncaught signal", "Assertion failed", "SIGABRT", "SIGILL", "SIGSEGV")


def run(script_path, stdin_content, env):
    cmd = [MIRA, "-lib", "./miralib", "-hush"]
    if script_path:
        cmd.append(script_path)
    # Drop any stale compiled-script cache so each run recompiles from source.
    x_path = None
    if script_path:
        base, _ = os.path.splitext(script_path)
        x_path = base + ".x"
        if os.path.exists(x_path):
            os.remove(x_path)
    try:
        proc = subprocess.run(
            cmd, input=stdin_content, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            text=True, timeout=30, env=env,
        )
    finally:
        if x_path and os.path.exists(x_path):
            os.remove(x_path)
    return proc


def check(name, proc):
    combined = (proc.stdout or "") + (proc.stderr or "")
    if proc.returncode < 0 or any(m in combined for m in CRASH_MARKERS):
        print(f"Spine differential check: {name} ... FAIL")
        print(f"  exit code: {proc.returncode}")
        print(f"  output: {combined.strip()[-2000:]}")
        return False
    print(f"Spine differential check: {name} ... PASS")
    return True


def main():
    if not os.path.exists(MIRA):
        print(f"Error: binary {MIRA} not found. Run `zig build` first.")
        sys.exit(1)

    env = dict(os.environ)
    env["MIRA_VALIDATE_SPINE"] = "1"

    failed = False

    if os.path.isdir(GOLDEN_DIR):
        expected_files = sorted(f for f in os.listdir(GOLDEN_DIR) if f.endswith(".expected"))
        for ef in expected_files:
            name = ef[:-len(".expected")]
            in_path = os.path.join(GOLDEN_DIR, f"{name}.in")
            if not os.path.exists(in_path):
                continue
            m_path = os.path.join(GOLDEN_DIR, f"{name}.m")
            script_path = m_path if os.path.exists(m_path) else None
            with open(in_path) as f:
                stdin_content = f.read()
            proc = run(script_path, stdin_content, env)
            if not check(f"golden/{name}", proc):
                failed = True

    for script_path, expr in EX_CORPUS:
        if not os.path.exists(script_path):
            print(f"Spine differential check: {script_path} ... SKIP (not found)")
            continue
        stdin_content = f"{expr}\n\n/q\n"
        proc = run(script_path, stdin_content, env)
        if not check(f"{script_path} : {expr}", proc):
            failed = True

    if failed:
        print("Spine differential check FAILED -- the shadow spine disagreed "
              "with the live pointer-reversal mechanism somewhere above.")
        sys.exit(1)
    print("All spine differential checks passed -- no shadow/live mismatch "
          f"across {len(EX_CORPUS)} miralib/ex programs and the golden corpus.")
    sys.exit(0)


if __name__ == "__main__":
    main()
