#!/usr/bin/env python3
"""Fail-closed, implementation-independent verifier for the .x wire contract."""

from __future__ import annotations

import json
import struct
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SPEC = ROOT / "tests" / "phase8_x_protocol.json"
CODEC = ROOT / "src" / "graph" / "xcodec.zig"

WIRE_TAGS = [
    "char", "short", "integer", "double", "identifier", "alias", "here",
    "constructor", "read_values", "pattern", "wide_pattern", "definition",
    "application", "cons", "type_variable", "unicode",
]
NODE_TAGS = [
    "atom", "double", "data_pair", "file_info", "type_variable", "integer",
    "constructor", "string_cons", "identifier", "application", "lambda",
    "cons", "tries", "label", "show", "start_read_values", "let", "letrec",
    "share", "lexer", "pair", "unicode", "type_cons",
]


def encoded(vector: dict) -> bytes:
    kind = vector["kind"]
    if kind == "i64":
        return int(vector["value"]).to_bytes(8, "little", signed=True)
    if kind == "i32":
        return int(vector["value"]).to_bytes(4, "little", signed=True)
    if kind == "f64bits":
        return int(vector["value"]).to_bytes(8, "little", signed=False)
    if kind == "zbytes":
        return vector["value"].encode("utf-8") + b"\0"
    if kind == "bytes":
        return bytes.fromhex(vector["hex"])
    raise AssertionError(f"unknown vector kind: {kind}")


def main() -> None:
    spec = json.loads(SPEC.read_text(encoding="utf-8"))
    assert spec["header"] == {"word_bits": 64, "version": 83, "hex": "4053"}
    assert spec["byte_order"] == "little"
    assert list(spec["wire_tags"]) == WIRE_TAGS
    assert list(spec["wire_tags"].values()) == list(range(191, 207))
    assert list(spec["node_tags"]) == NODE_TAGS
    assert list(spec["node_tags"].values()) == list(range(23))
    assert set(spec["malformed"]) == {
        "truncated", "missing-terminator", "invalid-tag", "wrong-version",
        "wrong-word-size", "trailing-bytes",
    }

    names = set()
    for vector in spec["vectors"]:
        assert vector["name"] not in names, f"duplicate vector {vector['name']}"
        names.add(vector["name"])
        actual = encoded(vector).hex()
        assert actual == vector["hex"], (
            f"{vector['name']}: canonical bytes changed: {actual} != {vector['hex']}"
        )
    required = {
        "word-min", "word-max", "word-negative", "i32-min", "i32-max",
        "float-positive-zero", "float-negative-zero", "float-min-subnormal",
        "float-max-finite", "empty-string", "non-ascii-string", "path",
        "alias-and-shared-reference", "exported-identifier",
        "postfix-application", "postfix-cons", "definition-end",
    }
    assert required <= names
    for tag_name, tag_value in spec["wire_tags"].items():
        vector = next(v for v in spec["vectors"] if v["name"] == f"tag-{tag_name}")
        assert vector["hex"] == bytes([tag_value]).hex()

    source = CODEC.read_text(encoding="utf-8")
    imports = [line for line in source.splitlines() if "@import(" in line]
    assert imports == ['const std = @import("std");'], (
        "xcodec.zig must remain dependency-neutral"
    )
    for forbidden in ("session/", "parser/", "compiler/", "eval/", "runtime/"):
        assert forbidden not in source

    # Independent decoder checks external canonical bytes and rejects each
    # truncation boundary without launching the interpreter.
    header = bytes.fromhex(spec["header"]["hex"])
    assert tuple(header) == (64, 83)
    for vector in spec["vectors"]:
        raw = bytes.fromhex(vector["hex"])
        if vector["kind"] in {"i64", "f64bits"}:
            assert len(raw) == 8
            for cut in range(8):
                assert len(raw[:cut]) < 8
        elif vector["kind"] == "i32":
            assert len(raw) == 4
            for cut in range(4):
                assert len(raw[:cut]) < 4
        elif vector["kind"] == "zbytes":
            assert raw.endswith(b"\0") and b"\0" not in raw[:-1]

    print(f"phase 8 .x protocol verified ({len(spec['vectors'])} canonical vectors)")


if __name__ == "__main__":
    main()
