import os
import sys
import json

# Add parent directory of this script to sys.path
sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

from regression import TEST_CASES, run_binary, parse_stats

def main():
    original_bin = "./mira_original"
    if not os.path.exists(original_bin):
        print(f"Error: Original binary {original_bin} not found.")
        sys.exit(1)
        
    os.makedirs("tests/reducer/golden", exist_ok=True)
    
    for tc in TEST_CASES:
        name = tc["name"]
        print(f"Capturing golden baseline for: {name} ... ", end="")
        res = run_binary(original_bin, tc)
        
        if res["timeout"]:
            print("TIMEOUT")
            sys.exit(1)
            
        stats, other_err = parse_stats(res["stderr"])
        
        # Write stdout
        with open(f"tests/reducer/golden/{name}.stdout", "w") as f:
            f.write(res["stdout"])
            
        # Write stderr
        with open(f"tests/reducer/golden/{name}.stderr", "w") as f:
            f.write(res["stderr"])
            
        # Write stats
        with open(f"tests/reducer/golden/{name}.stats", "w") as f:
            json.dump(stats, f, indent=2)
            
        print("Done")

if __name__ == "__main__":
    main()
