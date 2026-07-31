#!/usr/bin/env python3
"""Fail closed if native-stack GC scanning or Phase 4 root controls regress."""

from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]

checks = {
    "runtime cstack root": "cstack",
    "stack-address cast": "@ptrCast(@alignCast(&p))",
    "compiler root reflection": "std.meta.fields(compiler_state.CompilerState)",
}

production = "\n".join(
    path.read_text(errors="replace")
    for path in (ROOT / "src").rglob("*.zig")
)

failures = [label for label, needle in checks.items() if needle in production]

required = {
    "scoped single root": "pub fn root(",
    "scoped root slice": "pub fn rootSlice(",
    "dynamic root list": "pub fn rootList(",
    "forced every-N GC": "force_gc_every",
    "named GC checkpoint": "pub fn gcCheckpoint(",
    "registered reducer roots": "markAllRoots(reduce.ev().gc_roots_head",
}
roots_text = (ROOT / "src/graph/roots.zig").read_text()
heap_text = (ROOT / "src/graph/heap_cells.zig").read_text()
combined = roots_text + heap_text
failures.extend(label for label, needle in required.items() if needle not in combined)

if failures:
    for failure in failures:
        print(f"phase 4 root check failed: {failure}", file=sys.stderr)
    raise SystemExit(1)

print("phase 4 explicit-root architecture verified")
