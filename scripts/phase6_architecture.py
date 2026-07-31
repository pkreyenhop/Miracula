#!/usr/bin/env python3
"""Build and verify the acyclic Go package/state migration contract."""

from __future__ import annotations

import argparse
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "src"
MANIFEST = ROOT / "tests" / "phase6_package_map.json"

PACKAGES = {
    "protocol": [],
    "platformsvc": ["protocol"],
    "graphstore": ["protocol", "platformsvc"],
    "syntaxfront": ["protocol", "platformsvc", "graphstore"],
    "semantics": ["protocol", "platformsvc", "graphstore", "syntaxfront"],
    "evaluation": ["protocol", "platformsvc", "graphstore"],
    "application": [
        "protocol", "platformsvc", "graphstore", "syntaxfront",
        "semantics", "evaluation",
    ],
    "commandapp": ["protocol", "platformsvc", "application"],
    "devtools": ["protocol", "platformsvc"],
}

STATE = {
    "rs": ["application", "runtime_state.rs"],
    "heap": ["graphstore", "heap.heap"],
    "lex": ["syntaxfront", "lex_state.ls"],
    "comp": ["semantics", "compiler_state.cs"],
    "core": ["application", "core_state.s"],
    "io": ["platformsvc", "word.io"],
    "eval": ["evaluation", "reduce_rt.ev"],
    "big": ["graphstore", "bignum.bn"],
    "strtab": ["graphstore", "strtab.table"],
    "lineedit": ["application", "editor.state"],
    "symbols": ["semantics", "symbols.syms"],
    "make": ["application", "make_state.make"],
    "bnf": ["syntaxfront", "bnf_state.bnf"],
    "show": ["semantics", "show_fns.show"],
    "repl": ["application", "repl_session.session"],
    "config": ["application", "config_state.config"],
    "script": ["application", "script_store.store"],
}

SINGLETON_RE = re.compile(
    r"\b(?:current_interp|heap\(\)|rs\(\)|cs\(\)|ls\(\)|"
    r"\.s\(\)|\.ev\(\)|\.bn\(\)|\.syms\(\)|\.make\(\)|\.bnf\(\)|"
    r"\.session\(\)|\.config\(\)|\.store\(\))"
)


def destination(rel: str) -> str:
    if rel in {"graph/word.zig", "graph/value.zig", "graph/semantic_types.zig",
               "graph/combinator.zig", "runtime/errors.zig"}:
        return "protocol"
    if rel == "main.zig":
        return "commandapp"
    if rel.startswith("tools/") or rel == "testutil.zig":
        return "devtools"
    if rel.startswith("io/") or rel in {"os.zig", "os_scanf.zig"}:
        return "platformsvc"
    if rel.startswith("graph/") or rel in {"eval/resources.zig", "eval/stream.zig"}:
        return "graphstore"
    if rel.startswith("syntax/") or rel.startswith("parser/"):
        return "syntaxfront"
    if rel.startswith("semantics/"):
        return "semantics"
    if rel.startswith("eval/"):
        return "evaluation"
    if rel == "session/commands.zig":
        return "commandapp"
    return "application"


def build_manifest() -> dict:
    files = {}
    singleton_sites = {}
    for path in sorted(SRC.rglob("*.zig")):
        rel = path.relative_to(SRC).as_posix()
        files[rel] = destination(rel)
        count = len(SINGLETON_RE.findall(path.read_text()))
        if count:
            singleton_sites[rel] = count
    return {
        "schema": 1,
        "translation_order": list(PACKAGES),
        "packages": {
            name: {"may_import": deps, "go_path": f"internal/{name}"}
            for name, deps in PACKAGES.items()
        },
        "files": files,
        "state": {
            field: {"owner": value[0], "legacy_accessor": value[1],
                    "go_rule": "constructor or receiver parameter"}
            for field, value in STATE.items()
        },
        "process_globals": {
            "allowed": ["runtime.interrupt_flag"],
            "go_race_gate": "go test -race ./...",
        },
        "legacy_singleton_upper_bounds": singleton_sites,
    }


def cycle(packages: dict) -> list[str] | None:
    visiting: set[str] = set()
    done: set[str] = set()

    def visit(name: str, path: list[str]) -> list[str] | None:
        if name in visiting:
            return path[path.index(name):] + [name]
        if name in done:
            return None
        visiting.add(name)
        for dep in packages[name]["may_import"]:
            found = visit(dep, path + [dep])
            if found:
                return found
        visiting.remove(name)
        done.add(name)
        return None

    for name in packages:
        found = visit(name, [name])
        if found:
            return found
    return None


def verify(actual: dict, expected: dict) -> list[str]:
    errors = []
    if expected.get("schema") != 1:
        return ["unsupported phase 6 package-map schema"]
    if set(actual["files"]) != set(expected["files"]):
        missing = sorted(set(actual["files"]) - set(expected["files"]))
        stale = sorted(set(expected["files"]) - set(actual["files"]))
        errors.extend(f"unmapped production file: src/{x}" for x in missing)
        errors.extend(f"stale package mapping: src/{x}" for x in stale)
    for rel, package in actual["files"].items():
        if expected["files"].get(rel) != package:
            errors.append(f"package destination changed: src/{rel}")
    forbidden = {"common", "util", "shared", "misc"}
    bad = forbidden.intersection(expected["packages"])
    if bad:
        errors.append("forbidden catch-all package: " + ", ".join(sorted(bad)))
    found_cycle = cycle(expected["packages"])
    if found_cycle:
        errors.append("target package cycle: " + " -> ".join(found_cycle))
    for rel, count in actual["legacy_singleton_upper_bounds"].items():
        baseline = expected["legacy_singleton_upper_bounds"].get(rel)
        if baseline is None:
            errors.append(f"new ambient-state owner: src/{rel}")
        elif count > baseline:
            errors.append(f"singleton use increased: src/{rel} {baseline} -> {count}")
    if set(expected["state"]) != set(STATE):
        errors.append("Interp field ownership is incomplete")
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
        f"phase 6 migration DAG verified: {len(expected['packages'])} packages, "
        f"{len(expected['files'])} files, zero target cycles"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
