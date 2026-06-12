import os
import sys
import json

sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

from regression import TEST_CASES, run_binary, parse_stats

def main():
    refactored_bin = "./zig-out/bin/mira"
    if not os.path.exists(refactored_bin):
        print(f"Error: Refactored binary {refactored_bin} not found. Build first.")
        sys.exit(1)
        
    failed = False
    for tc in TEST_CASES:
        name = tc["name"]
        print(f"Verifying {name} against golden baseline ... ", end="")
        
        # Run refactored binary
        res = run_binary(refactored_bin, tc)
        if res["timeout"]:
            print("TIMEOUT")
            failed = True
            continue
            
        # Read golden stdout
        golden_stdout_path = f"tests/reducer/golden/{name}.stdout"
        if not os.path.exists(golden_stdout_path):
            print(f"FAIL (Golden stdout {golden_stdout_path} not found)")
            failed = True
            continue
        with open(golden_stdout_path, "r") as f:
            golden_stdout = f.read()
            
        # Read golden stderr / stats
        golden_stats_path = f"tests/reducer/golden/{name}.stats"
        if not os.path.exists(golden_stats_path):
            print(f"FAIL (Golden stats {golden_stats_path} not found)")
            failed = True
            continue
        with open(golden_stats_path, "r") as f:
            golden_stats = json.load(f)
            
        # Compare stdout
        if res["stdout"] != golden_stdout:
            print("FAIL (Stdout mismatch)")
            print("--- Golden Stdout ---")
            print(golden_stdout)
            print("--- Actual Stdout ---")
            print(res["stdout"])
            failed = True
            continue
            
        # Compare stats
        stats, other_err = parse_stats(res["stderr"])
        stats_mismatch = False
        for key in ["reductions", "cells_claimed", "no_of_gcs"]:
            golden_val = golden_stats.get(key)
            actual_val = stats.get(key)
            if golden_val != actual_val:
                print(f"FAIL (Stats mismatch for {key}: golden={golden_val}, actual={actual_val})")
                stats_mismatch = True
                
        if stats_mismatch:
            failed = True
            continue
            
        print("PASS")
        
    if failed:
        sys.exit(1)
    else:
        print("All golden verification tests passed successfully!")
        sys.exit(0)

if __name__ == "__main__":
    main()
