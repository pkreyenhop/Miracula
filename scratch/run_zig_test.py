import subprocess
import sys

cmd = [
    "zig", "test", "src/main.zig",
    "--dep", "version_options",
    "-Mversion_options=scratch/version_options.zig",
    "-lc",
    "-I.",
    "-Isrc/parser/legacy",
    "--test-filter", "golden snapshot tests",
    "-cflags", "-std=c11", "--",
    "src/parser/legacy/y.tab.c",
    "src/parser/legacy/parser_bridge.c"
]

try:
    print(f"Running: {' '.join(cmd)}")
    process = subprocess.Popen(cmd, stdout=sys.stdout, stderr=sys.stderr)
    process.wait(timeout=15)
except subprocess.TimeoutExpired:
    print("\n--- TIMED OUT ---")
    process.kill()
except Exception as e:
    print("Error:", e)
