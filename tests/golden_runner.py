#!/usr/bin/env python3
import os
import subprocess
import sys
import difflib

def clean_output(text):
    lines = []
    for line in text.splitlines():
        if line.startswith("||reductions =") or line.startswith("[TRACE]") or line.startswith("[ALLOC]") or line.startswith("[DIAG"):
            continue
        lines.append(line)
    return "\n".join(lines).strip()

def main():
    binary_path = "./zig-out/bin/mira"
    if len(sys.argv) > 1:
        binary_path = sys.argv[1]

    if not os.path.exists(binary_path):
        print(f"Error: Binary {binary_path} not found.")
        sys.exit(1)

    golden_dir = "./tests/golden"
    if not os.path.exists(golden_dir):
        print(f"Error: Golden directory {golden_dir} not found.")
        sys.exit(1)

    expected_files = sorted([f for f in os.listdir(golden_dir) if f.endswith(".expected")])
    if not expected_files:
        print("Error: No expected files found.")
        sys.exit(1)

    failed = False
    for ef in expected_files:
        name = ef[:-9]
        print(f"Verifying golden test: {name} ... ", end="")

        script_path = ""
        m_path = os.path.join(golden_dir, f"{name}.m")
        if os.path.exists(m_path):
            script_path = m_path

        in_path = os.path.join(golden_dir, f"{name}.in")
        if not os.path.exists(in_path):
            print(f"FAIL (missing {name}.in)")
            failed = True
            continue

        with open(in_path, "r") as f:
            stdin_content = f.read()

        with open(os.path.join(golden_dir, ef), "r") as f:
            expected_stdout = f.read().strip()

        expected_stderr_path = os.path.join(golden_dir, f"{name}.expected_err")
        expected_stderr = ""
        if os.path.exists(expected_stderr_path):
            with open(expected_stderr_path, "r") as f:
                expected_stderr = f.read().strip()

        cmd = [binary_path, "-lib", "./miralib", "-hush"]
        if script_path:
            cmd.append(script_path)

        proc = subprocess.run(
            cmd,
            input=stdin_content,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=5
        )

        actual_stdout = clean_output(proc.stdout)
        actual_stderr = clean_output(proc.stderr)

        if actual_stdout != expected_stdout:
            print("FAIL (stdout mismatch)")
            print("Diff:")
            diff = difflib.unified_diff(
                expected_stdout.splitlines(),
                actual_stdout.splitlines(),
                fromfile="expected",
                tofile="actual"
            )
            print("\n".join(diff))
            failed = True
            continue

        if actual_stderr != expected_stderr:
            print("FAIL (stderr mismatch)")
            print("Expected stderr:")
            print(expected_stderr)
            print("Actual stderr:")
            print(actual_stderr)
            failed = True
            continue

        print("PASS")

    if failed:
        print("Golden verification failed.")
        sys.exit(1)
    else:
        print("All golden verification tests passed successfully!")
        sys.exit(0)

if __name__ == "__main__":
    main()
