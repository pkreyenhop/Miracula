#!/usr/bin/env python3
"""Fail when an unclassified pointer/integer conversion enters production."""

from __future__ import annotations

from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
PATTERN = re.compile(r"ptrInt|ptrFrom|@intFromPtr|@ptrFromInt")
RULES = {
    "src/os.zig": "platform ABI boundary",
    "src/platform/c_compat.zig": "platform ABI boundary",
    "src/io/signals.zig": "signal-handler ABI",
    "src/session/boot.zig": "signal-handler registration",
    "src/session/repl.zig": "signal-handler registration",
    "src/graph/heap_cells.zig": "explicit dump scratch buffer boundary",
    "src/graph/dump_load.zig": "dictionary/stack buffer arithmetic",
    "src/parser/lex.zig": "dictionary/line buffer arithmetic",
    "src/session/commands.zig": "dictionary/line buffer arithmetic",
}
GRAPH_RESOURCE_FILES = {
    "src/compiler/module_loader.zig",
    "src/eval/combinators/io.zig",
    "src/eval/combinators/ready.zig",
    "src/eval/reduce_rt.zig",
    "src/parser/parser_api.zig",
}


def main() -> int:
    found: list[tuple[str, int, str, str | None]] = []
    for path in sorted((ROOT / "src").rglob("*.zig")):
        relative = path.relative_to(ROOT).as_posix()
        for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
            if not PATTERN.search(line) or line.lstrip().startswith("//"):
                continue
            found.append((relative, number, line.strip(), RULES.get(relative)))
    failures = [item for item in found if item[3] is None]
    graph_failures = [item for item in found if item[0] in GRAPH_RESOURCE_FILES]
    if failures or graph_failures:
        for path, number, line, classification in failures + graph_failures:
            print(
                f"{path}:{number}: unclassified pointer conversion"
                f"{' (' + classification + ')' if classification else ''}: {line}",
                file=sys.stderr,
            )
        return 1
    counts: dict[str, int] = {}
    for _, _, _, classification in found:
        counts[classification or "unclassified"] = counts.get(classification or "unclassified", 0) + 1
    print(f"pointer inventory verified: {len(found)} classified production sites")
    for classification, count in sorted(counts.items()):
        print(f"  {classification}: {count}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
