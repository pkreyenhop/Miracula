import subprocess
import sys
import os

env = os.environ.copy()
env["UPDATE_SNAPSHOTS"] = "1"

cmd = ["zig", "build", "test"]

try:
    print("Running zig build test with UPDATE_SNAPSHOTS=1...")
    process = subprocess.Popen(cmd, stdout=sys.stdout, stderr=sys.stderr, env=env)
    process.wait(timeout=15)
    print("Completed successfully.")
except subprocess.TimeoutExpired:
    print("\n--- TIMED OUT ---")
    process.kill()
    sys.exit(1)
except Exception as e:
    print("Error:", e)
    sys.exit(1)
