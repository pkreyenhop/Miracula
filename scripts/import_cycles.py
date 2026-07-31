#!/usr/bin/env python3
"""import_cycles.py — detect @import cycles among src/**/*.zig files.

Used by scripts/scorecard.sh (informational baseline metric today) and, from
docs/GoReady.md Phase 4 onward, as the enforced module-layering gate:
once the target tree lands, this script's cycle list must be empty (checked
into an allowlist that only shrinks) for `zig build check` to pass.

Only edges to other in-tree .zig files are tracked; package imports (`std`,
`version_options`, `zigline`, `build_options`, ...) have no `.zig` suffix and
are ignored, since they're leaves by construction.

Usage:
    scripts/import_cycles.py [root]      # default root: src
    scripts/import_cycles.py -v [root]   # also print each cycle's file list
"""
import re
import sys
from pathlib import Path

IMPORT_RE = re.compile(r'@import\(\s*"([^"]+\.zig)"\s*\)')

EXCLUDED = re.compile(r"(?:^|/)(?:[^/]+_test\.zig|testutil\.zig|micro_benchmarks\.zig)$")


def production_text(text: str) -> str:
    """Remove test blocks while preserving production import spellings."""
    chars = list(text)
    masked = list(text)
    i = 0
    while i < len(chars):
        if text.startswith("//", i):
            end = text.find("\n", i)
            end = len(chars) if end < 0 else end
            masked[i:end] = " " * (end - i)
            i = end
        elif text.startswith("/*", i):
            end = text.find("*/", i + 2)
            end = len(chars) - 2 if end < 0 else end
            masked[i : end + 2] = " " * (end + 2 - i)
            i = end + 2
        elif chars[i] == '"':
            i += 1
            while i < len(chars) and chars[i] != '"':
                if chars[i] == "\\":
                    i += 1
                i += 1
            i += 1
        else:
            i += 1
    code = "".join(masked)
    for match in reversed(list(re.finditer(r"(?m)^[ \t]*test\b[^{]*\{", code))):
        depth = 1
        pos = match.end()
        while pos < len(code) and depth:
            if code[pos] == "{":
                depth += 1
            elif code[pos] == "}":
                depth -= 1
            pos += 1
        chars[match.start() : pos] = " " * (pos - match.start())
    return "".join(chars)


def build_graph(root: Path) -> dict[Path, set[Path]]:
    graph: dict[Path, set[Path]] = {}
    for f in root.rglob("*.zig"):
        rel = f.relative_to(root).as_posix()
        if EXCLUDED.search(rel):
            continue
        text = production_text(f.read_text(encoding="utf-8", errors="replace"))
        edges = set()
        for m in IMPORT_RE.finditer(text):
            target = (f.parent / m.group(1)).resolve()
            if target.exists():
                edges.add(target)
        graph[f.resolve()] = edges
    return graph


def find_sccs(graph: dict[Path, set[Path]]) -> list[list[Path]]:
    """Tarjan's SCC algorithm; returns components with more than one node
    (a self-loop, i.e. a file importing itself, would also count but cannot
    happen for @import) — i.e. the real import cycles."""
    index_counter = [0]
    stack: list[Path] = []
    lowlink: dict[Path, int] = {}
    index: dict[Path, int] = {}
    on_stack: dict[Path, bool] = {}
    result: list[list[Path]] = []

    def strongconnect(v: Path):
        index[v] = index_counter[0]
        lowlink[v] = index_counter[0]
        index_counter[0] += 1
        stack.append(v)
        on_stack[v] = True

        for w in graph.get(v, ()):
            if w not in index:
                strongconnect(w)
                lowlink[v] = min(lowlink[v], lowlink[w])
            elif on_stack.get(w):
                lowlink[v] = min(lowlink[v], index[w])

        if lowlink[v] == index[v]:
            component = []
            while True:
                w = stack.pop()
                on_stack[w] = False
                component.append(w)
                if w == v:
                    break
            if len(component) > 1:
                result.append(component)

    sys.setrecursionlimit(10000)
    for v in list(graph.keys()):
        if v not in index:
            strongconnect(v)
    return result


def main():
    argv = sys.argv[1:]
    verbose = "-v" in argv
    argv = [a for a in argv if a != "-v"]
    root = Path(argv[0]) if argv else Path("src")

    graph = build_graph(root)
    cycles = find_sccs(graph)

    print(f"import cycles under {root}: {len(cycles)}")
    if verbose:
        for i, comp in enumerate(sorted(cycles, key=len, reverse=True), 1):
            print(f"  cycle {i} ({len(comp)} files):")
            for f in sorted(comp):
                try:
                    print(f"    {f.relative_to(Path.cwd())}")
                except ValueError:
                    print(f"    {f}")


if __name__ == "__main__":
    main()
