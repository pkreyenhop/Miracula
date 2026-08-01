#!/usr/bin/env python3
"""Validate ordered progress toward the production Go Miranda cutover."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import re
import sys


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_STATUS = ROOT / "spec/go_cutover_status.json"
TRANSLATION_STATUS = ROOT / "spec/go_translation_status.json"

MILESTONES = (
    "00-contract",
    "01-production-command",
    "02-runtime-graph",
    "03-source-parser",
    "04-semantics-lowering",
    "05-evaluator",
    "06-module-dump-boot",
    "07-repl-commands",
    "08-platform-integration",
    "09-full-parity",
    "10-production-packaging",
    "11-cutover",
)
STATES = {"pending", "complete"}

MILESTONE_COMMANDS = {
    "00-contract": (
        "python3 tests/test_go_cutover.py",
        "python3 scripts/go_cutover.py",
    ),
    "01-production-command": (
        "python3 scripts/build_go_candidate.py --output build/mira-go",
        "build/mira-go --build-info",
        "python3 tests/test_go_command.py",
    ),
    "02-runtime-graph": ("go test -race ./internal/protocol ./internal/graphstore",),
    "03-source-parser": (
        "go test ./internal/syntaxfront",
        "python3 tests/oracle/oracle.py verify --stage parse --producer 'go run ./cmd/miracula-go-oracle'",
    ),
    "04-semantics-lowering": (
        "go test ./internal/semantics",
        "python3 tests/oracle/oracle.py verify --stage lower --producer 'go run ./cmd/miracula-go-oracle'",
    ),
    "05-evaluator": (
        "go test ./internal/evaluation",
        "python3 tests/oracle/oracle.py verify --stage reduce --producer 'go run ./cmd/miracula-go-oracle'",
    ),
    "06-module-dump-boot": ("go test ./internal/application",),
    "07-repl-commands": (
        "go test ./internal/application ./internal/commandapp",
        "python3 tests/test_go_repl.py",
    ),
    "08-platform-integration": ("go test -race ./internal/platformsvc ./...",),
    "09-full-parity": (
        "python3 scripts/run_go_differential.py --candidate build/mira-go",
    ),
    "10-production-packaging": ("python3 tests/test_go_install.py",),
    "11-cutover": (
        "python3 tests/test_go_rollback.py",
        "complete final verification in go-cutover.md",
    ),
}

CONTRACT_FILES = (
    "go-cutover.md",
    "spec/go_cutover_status.json",
    "scripts/go_cutover.py",
    "scripts/build_go_candidate.py",
    "scripts/run_go_differential.py",
    "tests/test_go_cutover.py",
    "docs/GoCompatibilityExceptions.md",
    "docs/ReleaseNotes-GoCutover.md",
    "spec/go_cutover_evidence.json",
    "scripts/install_reference_rollback.py",
    "tests/test_go_rollback.py",
)

# These narrowly match the known scaffolding recorded in go-cutover.md. They
# activate only when the milestone responsible for replacing them is complete.
PLACEHOLDERS = {
    "01-production-command": (("cmd/mira/main.go", r"package\s+main"),),
    "03-source-parser": (
        (
            "internal/syntaxfront/parser.go",
            r'return\s+Script\{"script",\s*\[\]Definition\{\}\},\s*nil',
        ),
    ),
    "05-evaluator": (
        ("internal/evaluation/reduce.go", r"return\s+value,\s*nil"),
    ),
    "06-module-dump-boot": (
        ("internal/application/setup.go", r"Setup\(\)\s+error\s*\{\s*return\s+nil\s*\}"),
        ("internal/application/boot.go", r"Boot\(\)\s+error\s*\{\s*return\s+i\.Setup\(\)\s*\}"),
    ),
    "07-repl-commands": (
        ("internal/application/repl.go", r"fmt\.Fprintln\(out,\s*line\)"),
    ),
}


def read_json(path: Path, description: str) -> tuple[dict | None, list[str]]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError:
        return None, [f"missing {description}: {path}"]
    except json.JSONDecodeError as error:
        return None, [f"invalid {description} {path}: {error}"]
    if not isinstance(value, dict):
        return None, [f"{description} must be a JSON object"]
    return value, []


def validate(status_path: Path = DEFAULT_STATUS, root: Path = ROOT) -> list[str]:
    errors: list[str] = []
    status, status_errors = read_json(status_path, "Go cutover status")
    errors.extend(status_errors)
    if status is None:
        return errors

    if status.get("schema") != 1:
        errors.append(f"unsupported Go cutover status schema: {status.get('schema')!r}")
    milestones = status.get("milestones")
    if not isinstance(milestones, dict):
        errors.append("Go cutover status has no milestones object")
        return errors

    actual_keys = tuple(milestones)
    if actual_keys != MILESTONES:
        errors.append(
            "Go cutover milestone keys/order mismatch: expected "
            f"{list(MILESTONES)!r}, got {list(actual_keys)!r}"
        )

    found_pending = False
    for milestone in MILESTONES:
        state = milestones.get(milestone)
        if state not in STATES:
            errors.append(f"{milestone}: invalid cutover status {state!r}")
            continue
        if state == "pending":
            found_pending = True
        elif found_pending:
            errors.append(f"{milestone}: complete after an earlier pending milestone")

    translation_path = root / "spec/go_translation_status.json"
    translation, translation_errors = read_json(translation_path, "Go translation status")
    errors.extend(translation_errors)
    if translation is not None:
        units = translation.get("units")
        if not isinstance(units, dict):
            errors.append("Go translation status has no units object")
        else:
            pending = sorted(key for key, value in units.items() if value != "complete")
            if pending:
                errors.append(f"Go translation still has incomplete units: {', '.join(pending)}")

    if milestones.get("00-contract") == "complete":
        for relative in CONTRACT_FILES:
            if not (root / relative).is_file():
                errors.append(f"00-contract: missing required file {relative}")

    for milestone, checks in PLACEHOLDERS.items():
        if milestones.get(milestone) != "complete":
            continue
        for relative, pattern in checks:
            path = root / relative
            try:
                source = path.read_text(encoding="utf-8")
            except FileNotFoundError:
                errors.append(f"{milestone}: missing production file {relative}")
                continue
            if milestone == "01-production-command":
                if not re.search(pattern, source):
                    errors.append(f"{milestone}: {relative} is not a Go main package")
            elif re.search(pattern, source, re.DOTALL):
                errors.append(f"{milestone}: known placeholder remains in {relative}")

    if milestones.get("11-cutover") == "complete":
        evidence_path = root / "spec/go_cutover_evidence.json"
        evidence, evidence_errors = read_json(evidence_path, "Go cutover evidence")
        errors.extend(evidence_errors)
        manifest, manifest_errors = read_json(
            root / "tests/reference/manifest.json", "pinned reference manifest"
        )
        errors.extend(manifest_errors)
        if evidence is not None and manifest is not None:
            if evidence.get("schema") != 1:
                errors.append("11-cutover: unsupported evidence schema")
            if evidence.get("supported_target") != "darwin-arm64":
                errors.append("11-cutover: supported target must be darwin-arm64")
            reference = evidence.get("reference")
            pinned = manifest.get("platforms", {}).get("darwin-arm64", {})
            if not isinstance(reference, dict):
                errors.append("11-cutover: evidence has no reference record")
            else:
                if reference.get("source_commit") != manifest.get("source_commit"):
                    errors.append("11-cutover: reference source commit disagrees with manifest")
                if reference.get("binary_sha256") != pinned.get("sha256"):
                    errors.append("11-cutover: reference hash disagrees with manifest")
                artifact = root / str(pinned.get("binary", ""))
                if not artifact.is_file():
                    errors.append("11-cutover: pinned reference artifact is missing")
                else:
                    actual = hashlib.sha256(artifact.read_bytes()).hexdigest()
                    if actual != pinned.get("sha256"):
                        errors.append("11-cutover: pinned reference artifact checksum mismatch")
            gates = evidence.get("required_gates")
            if not isinstance(gates, list) or "verified-reference-rollback-drill" not in gates:
                errors.append("11-cutover: rollback drill evidence is missing")

    return errors


def first_pending(status_path: Path = DEFAULT_STATUS) -> str | None:
    status, errors = read_json(status_path, "Go cutover status")
    if errors or status is None or not isinstance(status.get("milestones"), dict):
        return None
    return next(
        (key for key in MILESTONES if status["milestones"].get(key) == "pending"),
        None,
    )


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--status", type=Path, default=DEFAULT_STATUS)
    parser.add_argument("--root", type=Path, default=ROOT)
    parser.add_argument(
        "--commands",
        action="store_true",
        help="print verification commands for the first pending milestone",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    status_path = args.status.resolve()
    errors = validate(status_path, args.root.resolve())
    if errors:
        for error in errors:
            print(f"go cutover validation failed: {error}", file=sys.stderr)
        return 1
    pending = first_pending(status_path)
    if pending is None:
        print("Go production cutover verified")
    else:
        print(f"Go cutover contract verified; first pending milestone: {pending}")
        if args.commands:
            for command in MILESTONE_COMMANDS[pending]:
                print(command)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
