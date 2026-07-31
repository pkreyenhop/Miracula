#!/usr/bin/env python3
"""Verify the single production front-end and directive ownership contract."""

from __future__ import annotations

import argparse
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "src"
MANIFEST = ROOT / "tests" / "phase7_frontend_inventory.json"
IMPORT_RE = re.compile(r'@import\(\s*"([^"]+\.zig)"\s*\)')

STAGES = {
    "source": ["syntax/source.zig", "source-oracle"],
    "lex": ["syntax/lexer.zig", "lex-oracle"],
    "layout": ["syntax/layout.zig", "layout-oracle"],
    "token": ["syntax/token_filter.zig", "lex-oracle"],
    "ast": ["syntax/ast.zig", "parse-oracle"],
    "parse": ["syntax/parser.zig", "parse-oracle"],
    "graph_codegen": ["parser/codegen.zig", "lower-oracle"],
    "module_directives": ["semantics/modules.zig", "module-oracle"],
    "entry": ["parser/parser_api.zig", "source-oracle"],
}

DIRECTIVES = {
    "include": {
        "owner": "semantics/modules.zig",
        "behavior": "parse structured include, recursively load, bind aliases and detect cycles",
        "test": "directive_include",
    },
    "export": {
        "owner": "semantics/modules.zig",
        "behavior": "parse export parts and apply the module export surface",
        "test": "directive_export_scope",
    },
    "free": {
        "owner": "syntax/directives.zig",
        "behavior": "capture the signature block as a structured front-end directive",
        "test": "directives.Scanner free",
    },
    "insert": {
        "owner": "syntax/source.zig",
        "behavior": "recursively splice source bytes before tokenization",
        "test": "insert_directive",
    },
    "list": {
        "owner": "syntax/directives.zig",
        "behavior": "recognized compatibility no-op",
        "test": "directives.Scanner compatibility ownership",
    },
    "nolist": {
        "owner": "syntax/directives.zig",
        "behavior": "recognized compatibility no-op",
        "test": "directives.Scanner compatibility ownership",
    },
    "bnf": {
        "owner": "syntax/directives.zig",
        "behavior": "recognized compatibility no-op; grammar extension is not translated as a second parser",
        "test": "directives.Scanner compatibility ownership",
    },
    "lex": {
        "owner": "syntax/directives.zig",
        "behavior": "recognized compatibility no-op; lexer extension is not translated as a second lexer",
        "test": "directives.Scanner compatibility ownership",
    },
    "unknown": {
        "owner": "syntax/directives.zig",
        "behavior": 'stdout diagnostic: syntax error: unknown directive "%<name>"',
        "test": "lex_err_unknown_directive",
    },
}

SERVICE_FILES = {
    "parser/lex.zig": [
        "identifier dictionary and name interning",
        "source stream open/close lifecycle",
        "private-name and lexer-variable graph constructors",
    ],
    "parser/lex_state.zig": [
        "file queue and module compilation state",
        "dictionary-related compiler roots",
    ],
    "parser/parser_api.zig": [
        "sole production parse entry and pipeline orchestration",
    ],
    "parser/codegen.zig": [
        "AST-to-graph construction only",
    ],
}


def imports(path: Path) -> set[Path]:
    text = path.read_text()
    if path == SRC / "main.zig":
        text = text.split("comptime {", 1)[0]
    result = set()
    for match in IMPORT_RE.finditer(text):
        target = (path.parent / match.group(1)).resolve()
        if target.is_file() and SRC.resolve() in target.parents:
            result.add(target)
    return result


def reachable() -> list[str]:
    todo = [(SRC / "main.zig").resolve()]
    seen: set[Path] = set()
    while todo:
        path = todo.pop()
        if path in seen:
            continue
        seen.add(path)
        todo.extend(imports(path) - seen)
    return sorted(path.relative_to(SRC.resolve()).as_posix() for path in seen)


def build_manifest() -> dict:
    all_files = sorted(path.relative_to(SRC).as_posix() for path in SRC.rglob("*.zig"))
    live = reachable()
    return {
        "schema": 1,
        "production_entrypoints": ["main.zig:main", "parser/parser_api.zig:parseCurrent"],
        "pipeline": {
            name: {"owner": value[0], "oracle": value[1]}
            for name, value in STAGES.items()
        },
        "directives": DIRECTIVES,
        "retained_parser_services": SERVICE_FILES,
        "reachable_files": live,
        "nonproduction_files": sorted(set(all_files) - set(live)),
    }


def verify(actual: dict, expected: dict) -> list[str]:
    errors = []
    if expected.get("schema") != 1:
        return ["unsupported phase 7 inventory schema"]
    for key in ("reachable_files", "nonproduction_files"):
        if actual[key] != expected.get(key):
            errors.append(f"front-end reachability changed: {key}")
    owners = [stage["owner"] for stage in expected["pipeline"].values()]
    if len(owners) != len(set(owners)):
        errors.append("two production stages claim the same implementation owner")
    if set(expected["pipeline"]) != set(STAGES):
        errors.append("production stage inventory is incomplete")
    if set(expected["directives"]) != set(DIRECTIVES):
        errors.append("directive ownership inventory is incomplete")
    elif expected["directives"] != DIRECTIVES:
        errors.append("directive owner or behavior changed without inventory update")
    expected_pipeline = {
        name: {"owner": value[0], "oracle": value[1]}
        for name, value in STAGES.items()
    }
    if expected.get("pipeline") != expected_pipeline:
        errors.append("front-end stage owner/oracle mapping changed")
    if expected.get("retained_parser_services") != SERVICE_FILES:
        errors.append("retained parser service classification changed")
    for name, directive in expected["directives"].items():
        if not directive.get("owner") or not directive.get("behavior") or not directive.get("test"):
            errors.append(f"directive lacks owner/behavior/test: {name}")
    parser_api = (SRC / "parser/parser_api.zig").read_text()
    required = [
        'return parseCurrentNative(heap_ptr);',
        '@import("../syntax/source.zig")',
        '@import("../syntax/lexer.zig")',
        '@import("../syntax/layout.zig")',
        '@import("../syntax/parser.zig")',
    ]
    for marker in required:
        if marker not in parser_api:
            errors.append(f"authoritative front-end marker missing: {marker}")
    if "lex_bridge.zig" in actual["reachable_files"]:
        errors.append("obsolete lexer bridge is production reachable")
    return errors


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--write", action="store_true")
    args = parser.parse_args()
    actual = build_manifest()
    if args.write:
        MANIFEST.write_text(json.dumps(actual, indent=2, sort_keys=True) + "\n")
        print(f"wrote {MANIFEST.relative_to(ROOT)}")
        return 0
    expected = json.loads(MANIFEST.read_text())
    errors = verify(actual, expected)
    if errors:
        print("\n".join(errors))
        return 1
    print(
        "phase 7 front-end verified: one pipeline, "
        f"{len(expected['reachable_files'])} reachable files, "
        f"{len(expected['directives'])} directive owners"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
