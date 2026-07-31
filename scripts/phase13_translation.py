#!/usr/bin/env python3
"""Generate and validate the mechanical source-to-Go translation contract."""

from __future__ import annotations

import argparse
import json
import posixpath
import re
from pathlib import Path

import phase6_architecture as architecture

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "src"
RULES_PATH = ROOT / "spec" / "go_translation_rules.json"
MANIFEST = ROOT / "spec" / "go_translation_manifest.json"

DECL_RE = re.compile(
    r"(?m)^[ \t]*(?:pub[ \t]+)?(?:export[ \t]+|extern[ \t]+|inline[ \t]+|noinline[ \t]+)*"
    r"(?:(fn)[ \t]+([A-Za-z_][A-Za-z0-9_]*)|const[ \t]+([A-Za-z_][A-Za-z0-9_]*)[ \t]*=[ \t]*(?:(?:packed|extern)[ \t]+)?(struct|enum|union|opaque|error)\b)"
)
TYPE_ALIAS_RE = re.compile(
    r"(?m)^[ \t]*(?:pub[ \t]+)?const[ \t]+([A-Za-z_][A-Za-z0-9_]*)[ \t]*=[ \t]*"
    r"((?:i|u|f)[0-9]+|usize|isize|c_int|anyerror|(?:[A-Za-z_][A-Za-z0-9_]*\.)*[A-Z][A-Za-z0-9_]*[a-z][A-Za-z0-9_]*)[ \t]*;"
)
IMPORT_RE = re.compile(r'@import\("([^"]+\.zig)"\)')
TEST_FILE_RE = re.compile(r"(?:^|/)(?:[^/]+_test\.zig|testutil\.zig)$")

PACKAGE_ORACLES = {
    "protocol": ["dump"],
    "platformsvc": ["reduce"],
    "graphstore": ["lower", "dump"],
    "syntaxfront": ["source", "lex", "layout", "parse"],
    "semantics": ["module", "typecheck", "lower"],
    "evaluation": ["reduce"],
    "application": ["module", "reduce"],
    "commandapp": ["reduce"],
    "devtools": ["reduce"],
}
PACKAGE_INTERFACES = {
    "protocol": ["CanonicalCodec"],
    "platformsvc": ["PlatformServices", "ProcessServices"],
    "graphstore": ["GraphStore", "ResourceRegistry"],
    "syntaxfront": ["SourcePipeline"],
    "semantics": ["ModuleResolver", "TypeChecker"],
    "evaluation": ["Evaluator"],
    "application": ["Interpreter"],
    "commandapp": ["Command"],
    "devtools": ["Tool"],
}


def mask_non_code(source: str) -> str:
    chars = list(source)
    i = 0
    while i < len(chars):
        if source.startswith("//", i):
            end = source.find("\n", i)
            end = len(source) if end < 0 else end
            chars[i:end] = " " * (end - i)
            i = end
        elif source.startswith("/*", i):
            end = source.find("*/", i + 2)
            end = len(source) - 2 if end < 0 else end
            chars[i : end + 2] = " " * (end + 2 - i)
            i = end + 2
        elif chars[i] in {'"', "'"}:
            quote = chars[i]
            i += 1
            while i < len(chars) and chars[i] != quote:
                if chars[i] == "\\":
                    chars[i] = " "
                    i += 1
                if i < len(chars) and chars[i] != "\n":
                    chars[i] = " "
                i += 1
            i += 1
        else:
            i += 1
    return "".join(chars)


def in_test_block(masked: str, offset: int) -> bool:
    stack: list[bool] = []
    pending_test = False
    token_re = re.compile(r"\btest\b|[{}]")
    for token in token_re.finditer(masked, 0, offset):
        if token.group() == "test":
            pending_test = True
        elif token.group() == "{":
            stack.append(pending_test or (stack[-1] if stack else False))
            pending_test = False
        else:
            if stack:
                stack.pop()
    return bool(stack and stack[-1])


def go_name(name: str) -> str:
    parts = [part for part in name.split("_") if part]
    return "".join(part if part.isupper() else part[:1].upper() + part[1:] for part in parts)


def target_decl_name(path: Path, name: str) -> str:
    prefix = go_name(path.stem)
    translated = go_name(name)
    return translated if translated == prefix else prefix + translated


def oracle_commands(package: str) -> list[dict]:
    return [
        {
            "stage": stage,
            "command": f"python3 tests/oracle/oracle.py verify --stage {stage} --producer ./miracula-go-oracle",
        }
        for stage in PACKAGE_ORACLES[package]
    ]


def symbols(path: Path) -> list[dict]:
    source = path.read_text(encoding="utf-8")
    masked = mask_non_code(source)
    result = []
    seen = set()
    seen_targets = set()
    declarations = [(match, None) for match in DECL_RE.finditer(masked)]
    declarations.extend((match, "type_alias") for match in TYPE_ALIAS_RE.finditer(masked))
    declarations.sort(key=lambda item: item[0].start())
    for match, forced_kind in declarations:
        if in_test_block(masked, match.start()):
            continue
        if forced_kind:
            kind = forced_kind
            name = match.group(1)
            receiver = None
            source_representation = match.group(2)
        else:
            kind = "function" if match.group(1) else match.group(4)
            name = match.group(2) or match.group(3)
            receiver = None
            source_representation = kind
            if kind == "function":
                signature = source[match.end() : match.end() + 600]
                receiver_match = re.match(
                    r"\s*\(\s*self\s*:\s*\*?(?:const\s+)?([A-Za-z_][A-Za-z0-9_]*)",
                    signature,
                )
                if receiver_match:
                    receiver = receiver_match.group(1)
        qualified = f"{receiver}.{name}" if receiver else name
        key = (kind, qualified)
        if key in seen:
            # Same-named private helpers in different lexical scopes translate
            # with their source line suffix, avoiding an implicit naming choice.
            qualified = f"{qualified}_line_{source.count(chr(10), 0, match.start()) + 1}"
            key = (kind, qualified)
        seen.add(key)
        target_symbol = (
            f"{target_decl_name(path, receiver)}.{go_name(name)}"
            if receiver
            else target_decl_name(path, qualified)
        )
        if target_symbol in seen_targets:
            target_symbol += go_name(kind)
        if target_symbol in seen_targets:
            target_symbol += f"Line{source.count(chr(10), 0, match.start()) + 1}"
        seen_targets.add(target_symbol)
        result.append({
            "source_kind": kind,
            "source_symbol": qualified,
            "source_representation": source_representation,
            "target_symbol": target_symbol,
            "representation": "go_function" if kind == "function" else f"go_{kind}",
        })
    return result


def resolve_import(rel: str, imported: str) -> str | None:
    candidate = posixpath.normpath(posixpath.join(posixpath.dirname(rel), imported))
    return candidate if (SRC / candidate).is_file() else None


def excluded_reason(rel: str) -> str | None:
    if TEST_FILE_RE.search(rel):
        return "zig_test_companion"
    if rel == "micro_benchmarks.zig":
        return "zig_benchmark_harness"
    return None


def build_manifest(rules: dict) -> dict:
    sources = []
    production_files = []
    for path in sorted(SRC.rglob("*.zig")):
        rel = path.relative_to(SRC).as_posix()
        reason = excluded_reason(rel)
        package = architecture.destination(rel)
        unit_id = f"src/{rel}"
        imports = sorted({
            resolved
            for imported in IMPORT_RE.findall(path.read_text(encoding="utf-8"))
            if (resolved := resolve_import(rel, imported)) is not None
        })
        status = "not_ported" if reason else "pending"
        if not reason:
            production_files.append(rel)
        target_file = rel.removesuffix(".zig").split("/")[-1] + ".go"
        dependency_ids = [f"src/{item}" for item in imports if excluded_reason(item) is None]
        unit_symbols = []
        for symbol in symbols(path):
            unit_symbols.append({
                **symbol,
                "target_package": package,
                "target_file": target_file,
                "dependencies": dependency_ids,
                "stage_oracles": oracle_commands(package),
                "interfaces": PACKAGE_INTERFACES[package],
                "translation_status": status,
                "platform_specific": package == "platformsvc",
                "generated": rel.endswith("_generated.zig"),
                "not_ported_reason": reason,
            })
        sources.append({
            "id": unit_id,
            "source_file": rel,
            "target_package": package,
            "target_file": target_file,
            "dependencies": dependency_ids,
            "interfaces": PACKAGE_INTERFACES[package],
            "representation": "one Go source file; declarations use the global representation rules",
            "stage_oracles": oracle_commands(package),
            "package_test": f"go test ./internal/{package}",
            "translation_status": status,
            "platform_specific": package == "platformsvc",
            "generated": rel.endswith("_generated.zig"),
            "not_ported_reason": reason,
            "symbols": unit_symbols,
        })
    package_contract = architecture.build_manifest()["packages"]
    translation_units = []
    for package in architecture.PACKAGES:
        package_sources = [
            source["id"]
            for source in sources
            if source["target_package"] == package and source["translation_status"] == "pending"
        ]
        translation_units.append({
            "id": f"package:{package}",
            "target_package": package,
            "dependencies": [f"package:{item}" for item in package_contract[package]["may_import"]],
            "source_files": package_sources,
            "package_test": f"go test ./internal/{package}",
            "stage_oracles": oracle_commands(package),
            "dag_check": "go run ./cmd/checkdag",
            "generated_check": "go generate ./... && git diff --exit-code",
            "translation_status": "pending",
        })
    return {
        "schema": 1,
        "rules": "spec/go_translation_rules.json",
        "selection_rule": "lexicographically first pending package unit whose dependencies are complete",
        "packages": package_contract,
        "production_files": production_files,
        "translation_units": translation_units,
        "sources": sources,
    }


def package_cycle(packages: dict) -> list[str] | None:
    return architecture.cycle(packages)


def unit_cycle(units: list[dict]) -> list[str] | None:
    dependencies = {unit["id"]: unit["dependencies"] for unit in units}
    visiting: set[str] = set()
    complete: set[str] = set()

    def visit(unit_id: str, path: list[str]) -> list[str] | None:
        if unit_id in visiting:
            return path[path.index(unit_id) :] + [unit_id]
        if unit_id in complete:
            return None
        visiting.add(unit_id)
        for dependency in dependencies[unit_id]:
            found = visit(dependency, path + [dependency])
            if found:
                return found
        visiting.remove(unit_id)
        complete.add(unit_id)
        return None

    for unit_id in dependencies:
        found = visit(unit_id, [unit_id])
        if found:
            return found
    return None


def validate(manifest: dict, actual: dict, rules: dict) -> list[str]:
    errors = []
    if manifest.get("schema") != 1 or rules.get("schema") != 1:
        return ["unsupported Phase 13 schema"]
    if manifest != actual:
        errors.append("translation manifest is stale; run phase13_translation.py --write")
        return errors
    unit_ids = [unit["id"] for unit in manifest["translation_units"]]
    if len(unit_ids) != len(set(unit_ids)):
        errors.append("duplicate translation unit")
    known_units = set(unit_ids)
    known_sources = {source["id"] for source in manifest["sources"]}
    scheduled_sources = []
    for unit in manifest["translation_units"]:
        scheduled_sources.extend(unit["source_files"])
        for dependency in unit["dependencies"]:
            if dependency not in known_units:
                errors.append(f"{unit['id']}: unknown dependency {dependency}")
        if not unit["stage_oracles"] or not unit["package_test"]:
            errors.append(f"{unit['id']}: missing immediate verifier")
    if len(scheduled_sources) != len(set(scheduled_sources)):
        errors.append("a source file is scheduled more than once")
    expected_scheduled = {
        source["id"] for source in manifest["sources"] if source["translation_status"] == "pending"
    }
    if set(scheduled_sources) != expected_scheduled:
        errors.append("pending source scheduling is incomplete")
    symbol_ids = []
    targets = set()
    for source in manifest["sources"]:
        for dependency in source["dependencies"]:
            if dependency not in known_sources:
                errors.append(f"{source['id']}: unknown source dependency {dependency}")
        reason = source["not_ported_reason"]
        if source["translation_status"] == "not_ported":
            if reason not in rules["not_ported_reasons"]:
                errors.append(f"{source['id']}: untested not-ported reason")
            elif not rules["not_ported_reasons"][reason].get("verification_command"):
                errors.append(f"{source['id']}: not-ported reason has no test")
        elif reason is not None or source["translation_status"] != "pending":
            errors.append(f"{source['id']}: invalid initial status")
        for symbol in source["symbols"]:
            symbol_id = f"{source['id']}:{symbol['source_kind']}:{symbol['source_symbol']}"
            symbol_ids.append(symbol_id)
            required = ("target_package", "target_file", "target_symbol", "stage_oracles",
                        "interfaces", "representation", "translation_status",
                        "platform_specific", "generated", "not_ported_reason")
            if any(field not in symbol for field in required):
                errors.append(f"{symbol_id}: incomplete symbol contract")
            target = (symbol["target_package"], symbol["target_symbol"])
            if target in targets:
                errors.append(f"{symbol_id}: duplicate Go target symbol {target}")
            targets.add(target)
    if len(symbol_ids) != len(set(symbol_ids)):
        errors.append("a production symbol appears more than once")
    found_cycle = package_cycle(manifest["packages"])
    if found_cycle:
        errors.append("target package cycle: " + " -> ".join(found_cycle))
    found_unit_cycle = unit_cycle(manifest["translation_units"])
    if found_unit_cycle:
        errors.append("translation unit cycle: " + " -> ".join(found_unit_cycle))
    required_rules = {
        "errors", "optionals", "tagged_unions", "ownership", "strings", "numbers",
        "cleanup", "build", "tests", "generation", "translation_loop",
        "final_differential_command",
    }
    if not required_rules.issubset(rules) or len(rules["translation_loop"]) != 10:
        errors.append("mechanical translation rules are incomplete")
    return errors


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--write", action="store_true")
    args = parser.parse_args()
    rules = json.loads(RULES_PATH.read_text(encoding="utf-8"))
    actual = build_manifest(rules)
    if args.write:
        MANIFEST.write_text(json.dumps(actual, indent=2, sort_keys=True) + "\n", encoding="utf-8")
        print(f"wrote {MANIFEST.relative_to(ROOT)}")
        return 0
    manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
    errors = validate(manifest, actual, rules)
    if errors:
        print("\n".join(errors))
        return 1
    symbols_count = sum(len(source["symbols"]) for source in manifest["sources"])
    pending = sum(unit["translation_status"] == "pending" for unit in manifest["translation_units"])
    print(
        f"phase 13 translation contract verified: {pending} pending units, "
        f"{symbols_count} functions/types, zero package cycles"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
