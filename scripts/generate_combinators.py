#!/usr/bin/env python3
"""Generate the combinator vocabulary from its language-neutral definition."""

from __future__ import annotations

import argparse
import json
import re
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCHEMA = ROOT / "spec" / "combinators.json"
OUTPUT = ROOT / "src" / "graph" / "combinator_generated.zig"


def bootstrap() -> dict:
    source = (ROOT / "src/graph/combinator.zig").read_text(encoding="utf-8")
    if "pub const cmbnms: [" not in source:
        source = subprocess.check_output(
            ["git", "show", "HEAD:src/graph/combinator.zig"],
            cwd=ROOT,
            text=True,
        )
    table = source.split("pub const cmbnms", 1)[1].split("};", 1)[0]
    names = re.findall(r'^\s*"([^"]+)",$', table, re.MULTILINE)
    if len(names) != 141:
        raise SystemExit(f"expected 141 combinator names, found {len(names)}")
    entries = []
    for offset, name in enumerate(names):
        if offset <= 95:
            dispatch = "evaluation"
        elif offset <= 109:
            dispatch = "grammar"
        elif offset <= 130:
            dispatch = "lexer"
        elif offset <= 137:
            dispatch = "control"
        else:
            dispatch = "sentinel"
        entries.append({
            "stable_name": name,
            "display_name": name,
            "aliases": [],
            "offset": offset,
            "value": 306 + offset,
            "dispatch": dispatch,
        })
    return {"schema": 1, "base": 306, "entries": entries}


def validate(data: dict) -> None:
    if data.get("schema") != 1 or data.get("base") != 306:
        raise SystemExit("unsupported combinator schema or base")
    entries = data.get("entries", [])
    if len(entries) != 141:
        raise SystemExit("combinator schema must contain 141 entries")
    names = set()
    for offset, entry in enumerate(entries):
        if entry["offset"] != offset or entry["value"] != data["base"] + offset:
            raise SystemExit(f"non-canonical numbering at entry {offset}")
        if entry["stable_name"] in names:
            raise SystemExit(f"duplicate combinator name {entry['stable_name']}")
        names.add(entry["stable_name"])
        if not entry["dispatch"]:
            raise SystemExit(f"missing dispatch metadata at entry {offset}")
    word_source = (ROOT / "src/graph/word.zig").read_text(encoding="utf-8")
    for entry in entries:
        pattern = rf"pub const {re.escape(entry['stable_name'])}: Word = CMBASE \+ {entry['offset']};"
        if re.search(pattern, word_source) is None:
            raise SystemExit(
                f"word constant diverges from canonical entry: {entry['stable_name']}"
            )


def render(data: dict) -> str:
    entries = data["entries"]
    lines = [
        "//! GENERATED FILE — run `python3 scripts/generate_combinators.py --write`.",
        "//! Canonical source: spec/combinators.json.",
        "",
        f"pub const base: i64 = {data['base']};",
        f"pub const count: usize = {len(entries)};",
        "",
        "pub const Comb = enum(u16) {",
    ]
    lines.extend(f"    {entry['stable_name']} = {entry['offset']}," for entry in entries)
    lines.extend(["};", ""])
    for entry in entries:
        lines.append(f"pub const {entry['stable_name']}: i64 = {entry['value']};")
    lines.extend(["", "pub const cmbnms: [count + 1]?[*:0]const u8 = .{"])
    lines.extend(f'    "{entry["display_name"]}",' for entry in entries)
    lines.extend(["    null,", "};", ""])
    return "\n".join(lines)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--bootstrap", action="store_true")
    parser.add_argument("--write", action="store_true")
    parser.add_argument("--output", type=Path, default=OUTPUT)
    args = parser.parse_args()
    if args.bootstrap:
        SCHEMA.parent.mkdir(parents=True, exist_ok=True)
        SCHEMA.write_text(json.dumps(bootstrap(), indent=2) + "\n", encoding="utf-8")
    data = json.loads(SCHEMA.read_text(encoding="utf-8"))
    validate(data)
    generated = render(data)
    if args.write:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(generated, encoding="utf-8")
        print(f"wrote {args.output}")
        return 0
    if not args.output.exists() or args.output.read_text(encoding="utf-8") != generated:
        print("generated combinator output is stale; run with --write")
        return 1
    print(f"combinator artifact verified: {len(data['entries'])} stable entries")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
