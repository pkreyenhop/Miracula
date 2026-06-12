#!/usr/bin/env python3
import subprocess
import sys
import os
import re
import tempfile

TEST_CASES = [
    {
        "name": "arithmetic_1_plus_2",
        "input": "1+2\n/q\n"
    },
    {
        "name": "factorial_10",
        "input": "product [1..10]\n/q\n"
    },
    {
        "name": "map_double",
        "input": "map (2*) [1..5]\n/q\n"
    },
    {
        "name": "big_integers",
        "input": "12345678901234567890 + 10\n2^80\n/q\n"
    },
    {
        "name": "lazy_lists_and_strings",
        "input": "take 5 [1..]\nreverse [1,2,3]\nzip2 [1,2,3] [4,5,6]\n\"abc\" ++ \"def\"\n/q\n"
    },
    {
        "name": "fibonacci_script",
        "script_path": "miralib/ex/fib",
        "input": "fib 10\n/q\n"
    },
    {
        "name": "user_defined_script",
        "script_content": "square x = x*x\ntwice f x = f (f x)\npairup x y = (x,y)\n",
        "input": "square 12\ntwice square 2\npairup 1 2\n/q\n"
    }
]

def parse_stats(stderr_data):
    # Stats line looks like:
    # ||reductions = 2, cells claimed = 5, no of gc's = 0, cpu = 0.00
    stats = {}
    other_stderr = []
    for line in stderr_data.splitlines():
        if line.startswith("||"):
            match = re.search(r"reductions = (\d+), cells claimed = (\d+), no of gc's = (\d+)", line)
            if match:
                stats["reductions"] = int(match.group(1))
                stats["cells_claimed"] = int(match.group(2))
                stats["no_of_gcs"] = int(match.group(3))
        else:
            if not (line.startswith("[TRACE]") or line.startswith("[ALLOC]") or line.startswith("[DIAG")):
                other_stderr.append(line)
    return stats, "\n".join(other_stderr)

def run_binary(binary_path, test_case):
    temp_file = None
    cmd = [binary_path, "-lib", "miralib", "-hush", "-count"]
    
    if "script_content" in test_case:
        temp_file = tempfile.NamedTemporaryFile(mode="w", suffix=".m", delete=False)
        temp_file.write(test_case["script_content"])
        temp_file.close()
        cmd.append(temp_file.name)
    elif "script_path" in test_case:
        cmd.append(test_case["script_path"])
        
    try:
        proc = subprocess.run(
            cmd,
            input=test_case["input"],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=10
        )
        return {
            "stdout": proc.stdout,
            "stderr": proc.stderr,
            "returncode": proc.returncode,
            "timeout": False
        }
    except subprocess.TimeoutExpired:
        return {
            "stdout": "",
            "stderr": "",
            "returncode": -1,
            "timeout": True
        }
    finally:
        if temp_file:
            try:
                os.remove(temp_file.name)
            except OSError:
                pass

def main():
    original_bin = "./mira_original"
    refactored_bin = "./zig-out/bin/mira"
    
    if not os.path.exists(original_bin):
        print(f"Error: Original binary {original_bin} not found. Please build it first.")
        sys.exit(1)
        
    if not os.path.exists(refactored_bin):
        print(f"Error: Refactored binary {refactored_bin} not found. Please build it first.")
        sys.exit(1)
        
    failed = False
    
    for tc in TEST_CASES:
        name = tc["name"]
        print(f"Running test: {name} ... ", end="")
        
        orig_res = run_binary(original_bin, tc)
        ref_res = run_binary(refactored_bin, tc)
        
        if orig_res["timeout"]:
            print("FAIL (Original binary timed out)")
            failed = True
            continue
            
        if ref_res["timeout"]:
            print("FAIL (Refactored binary timed out - killed after 10 seconds)")
            failed = True
            continue
            
        if orig_res["returncode"] != ref_res["returncode"]:
            print("FAIL (Exit code mismatch)")
            print(f"  Original: {orig_res['returncode']}")
            print(f"  Refactored: {ref_res['returncode']}")
            failed = True
            continue
            
        if orig_res["stdout"] != ref_res["stdout"]:
            print("FAIL (Stdout mismatch)")
            print("--- Original Stdout ---")
            print(orig_res["stdout"])
            print("--- Refactored Stdout ---")
            print(ref_res["stdout"])
            failed = True
            continue
            
        orig_stats, orig_other_err = parse_stats(orig_res["stderr"])
        ref_stats, ref_other_err = parse_stats(ref_res["stderr"])
        
        if orig_other_err != ref_other_err:
            print("FAIL (Stderr mismatch, excluding stats)")
            print("--- Original Stderr ---")
            print(orig_other_err)
            print("--- Refactored Stderr ---")
            print(ref_other_err)
            failed = True
            continue
            
        # Compare stats if they exist
        stats_mismatch = False
        for key in ["reductions", "cells_claimed", "no_of_gcs"]:
            orig_val = orig_stats.get(key)
            ref_val = ref_stats.get(key)
            if orig_val != ref_val:
                print(f"FAIL (Stats mismatch for {key}: original={orig_val}, refactored={ref_val})")
                stats_mismatch = True
                
        if stats_mismatch:
            failed = True
            continue
            
        print("PASS")
        
    if failed:
        sys.exit(1)
    else:
        print("All verification tests passed successfully!")
        sys.exit(0)

if __name__ == "__main__":
    main()
