import subprocess
import sys

cmd = [
    "zig", "test",
    "-cflags", "-std=c11", "-Wall", "-Wextra", "-Wpedantic", "--",
    "/Users/pkreyenhop/src/Miracula/src/parser/legacy/y.tab.c",
    "/Users/pkreyenhop/src/Miracula/src/parser/legacy/parser_bridge.c",
    "-ODebug",
    "-I", "/Users/pkreyenhop/src/Miracula/.",
    "-I", "/Users/pkreyenhop/src/Miracula/src/parser/legacy",
    "-D_FORTIFY_SOURCE=0", "-D_GNU_SOURCE=1", "-D_DARWIN_C_SOURCE=1",
    "--dep", "version_options",
    "-Mroot=/Users/pkreyenhop/src/Miracula/src/main.zig",
    "-Mversion_options=/Users/pkreyenhop/src/Miracula/scratch/version_options.zig",
    "-lc",
    "--test-filter", "golden snapshot tests"
]

try:
    print(f"Running exact command...")
    process = subprocess.Popen(cmd, stdout=sys.stdout, stderr=sys.stderr)
    process.wait(timeout=15)
except subprocess.TimeoutExpired:
    print("\n--- TIMED OUT ---")
    process.kill()
except Exception as e:
    print("Error:", e)
