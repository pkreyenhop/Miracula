#!/usr/bin/env python3
"""spine_differential_check.py -- stress/regression corpus for the explicit
spine stack (src/runtime/reducer/spine.zig), B2 option (b) / Phase 2 of
docs/REMAINING_WORK_PLAN.md.

`Spine` is now the interpreter's live spine-traversal mechanism (the cutover
that replaced in-graph pointer reversal). This script runs real Miranda
programs through it and checks for a clean exit (no crash signal, no panic,
no hang) -- a broader smoke test than the golden corpus's exact-output checks,
covering shapes golden doesn't stress: deep recursion, guarded multi-equation
functions (which pervasively exercise combinators.handleTRY/handleFAIL's
direct spine manipulation), algebraic types, lazy infinite streams.

It predates the cutover as a *differential* tool: an earlier version ran with
an opt-in env var that drove a shadow Spine in lockstep with the
then-still-live pointer reversal, asserting agreement on every primitive
call. That shadow-validation pass (51 checks, zero mismatches) is what gave
enough confidence to attempt the cutover, and caught two real bugs along the
way -- see git history around 71c47ae..c617ae2 for the shadow mechanism itself,
and the cutover commit for the two bugs the *live* run then caught that the
shadow's narrower coverage had not (a `via_tl`-boundary check missing from
`downright`/`upleft`/`handleTRY`/`handleFAIL`, and an algebraic-type
regression). The shadow machinery is gone now that there is nothing left to
shadow; this file keeps the corpus as an ordinary regression/smoke suite.

Two corpora:
  1. Every tests/golden/*.m + *.in pair (reusing the existing fixtures).
  2. A curated set of real programs from miralib/ex/ (deep recursion, guarded
     multi-equation functions, algebraic types, lazy infinite streams), chosen
     for shapes the golden corpus doesn't stress. Two miralib/ex/*.m files
     (ack.m, queens.m) and hanoi.m use n+k patterns that this interpreter's
     parser/compiler currently rejects outright (a genuine, separate,
     pre-existing bug, unrelated to the reducer) -- ack.m is swapped for
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
        print("Spine stress check FAILED -- see the crash/hang above.")
        sys.exit(1)
    print("All spine stress checks passed -- clean exit across "
          f"{len(EX_CORPUS)} miralib/ex programs and the golden corpus.")
    sys.exit(0)


if __name__ == "__main__":
    main()
