#!/usr/bin/env python3
"""Canonical, language-neutral stage-oracle protocol."""

from __future__ import annotations

import hashlib
import json
from pathlib import Path
from typing import Any, Iterable

SCHEMA_VERSION = 1
STAGES = (
    "source",
    "lex",
    "layout",
    "parse",
    "module",
    "typecheck",
    "lower",
    "reduce",
    "dump",
)
SEVERITIES = {"error", "warning", "note"}
OUTCOMES = {"success", "failure"}
TOP_LEVEL_FIELDS = (
    "schema_version",
    "stage",
    "case_id",
    "input",
    "outcome",
    "payload",
    "diagnostics",
)
DIAGNOSTIC_FIELDS = (
    "severity",
    "message",
    "file",
    "start",
    "end",
    "line",
    "column",
)
PAYLOAD_FIELDS = {
    "source": ("bytes_base64", "files", "positions"),
    "lex": ("tokens", "directives"),
    "layout": ("tokens",),
    "parse": ("ast", "recovered"),
    "module": ("includes", "aliases", "exports", "symbols"),
    "typecheck": ("types", "substitutions"),
    "lower": ("roots", "cells"),
    "reduce": (
        "value",
        "graph",
        "stdout_base64",
        "stderr_base64",
        "exit",
        "trace",
    ),
    "dump": (
        "input_base64",
        "records",
        "encoded_base64",
        "graph",
    ),
}


class ProtocolError(ValueError):
    pass


def canonical_bytes(value: Any) -> bytes:
    return (
        json.dumps(
            value,
            ensure_ascii=True,
            allow_nan=False,
            separators=(",", ":"),
            sort_keys=False,
        )
        + "\n"
    ).encode("ascii")


def input_identity(data: bytes) -> dict[str, Any]:
    return {
        "encoding": "bytes",
        "length": len(data),
        "sha256": hashlib.sha256(data).hexdigest(),
    }


def _exact_fields(value: dict[str, Any], fields: tuple[str, ...], where: str) -> None:
    if tuple(value) != fields:
        raise ProtocolError(
            f"{where}: fields must be ordered exactly as {fields!r}; "
            f"got {tuple(value)!r}"
        )


def validate_record(record: Any, expected_stage: str | None = None) -> None:
    if not isinstance(record, dict):
        raise ProtocolError("record: expected object")
    _exact_fields(record, TOP_LEVEL_FIELDS, "record")
    if record["schema_version"] != SCHEMA_VERSION:
        raise ProtocolError("record.schema_version: unsupported version")
    if record["stage"] not in STAGES:
        raise ProtocolError("record.stage: unknown stage")
    if expected_stage is not None and record["stage"] != expected_stage:
        raise ProtocolError(
            f"record.stage: expected {expected_stage!r}, got {record['stage']!r}"
        )
    if not isinstance(record["case_id"], str) or not record["case_id"]:
        raise ProtocolError("record.case_id: expected non-empty string")
    identity = record["input"]
    if not isinstance(identity, dict) or tuple(identity) != (
        "encoding",
        "length",
        "sha256",
    ):
        raise ProtocolError("record.input: invalid or non-canonical identity")
    if identity["encoding"] != "bytes":
        raise ProtocolError("record.input.encoding: expected 'bytes'")
    if not isinstance(identity["length"], int) or identity["length"] < 0:
        raise ProtocolError("record.input.length: expected non-negative integer")
    digest = identity["sha256"]
    if (
        not isinstance(digest, str)
        or len(digest) != 64
        or any(c not in "0123456789abcdef" for c in digest)
    ):
        raise ProtocolError("record.input.sha256: expected lowercase SHA-256")
    outcome = record["outcome"]
    if not isinstance(outcome, dict):
        raise ProtocolError("record.outcome: expected object")
    if tuple(outcome) not in (("kind",), ("kind", "failure_type")):
        raise ProtocolError("record.outcome: invalid fields or field order")
    if outcome.get("kind") not in OUTCOMES:
        raise ProtocolError("record.outcome.kind: invalid outcome")
    if outcome["kind"] == "failure":
        if not isinstance(outcome.get("failure_type"), str) or not outcome["failure_type"]:
            raise ProtocolError("record.outcome.failure_type: required for failure")
    elif "failure_type" in outcome:
        raise ProtocolError("record.outcome.failure_type: forbidden for success")
    if not isinstance(record["payload"], dict):
        raise ProtocolError("record.payload: expected object")
    expected_payload_fields = PAYLOAD_FIELDS[record["stage"]]
    _exact_fields(record["payload"], expected_payload_fields, "record.payload")
    _reject_unstable_fields(record["payload"], "record.payload")
    diagnostics = record["diagnostics"]
    if not isinstance(diagnostics, list):
        raise ProtocolError("record.diagnostics: expected array")
    for index, diagnostic in enumerate(diagnostics):
        where = f"record.diagnostics[{index}]"
        if not isinstance(diagnostic, dict):
            raise ProtocolError(f"{where}: expected object")
        _exact_fields(diagnostic, DIAGNOSTIC_FIELDS, where)
        if diagnostic["severity"] not in SEVERITIES:
            raise ProtocolError(f"{where}.severity: invalid severity")
        if not isinstance(diagnostic["message"], str):
            raise ProtocolError(f"{where}.message: expected string")
        if diagnostic["file"] is not None and not isinstance(
            diagnostic["file"], str
        ):
            raise ProtocolError(f"{where}.file: expected string or null")
        for key in ("start", "end", "line", "column"):
            if diagnostic[key] is not None and (
                not isinstance(diagnostic[key], int) or diagnostic[key] < 0
            ):
                raise ProtocolError(f"{where}.{key}: expected non-negative integer or null")
        if (
            diagnostic["start"] is not None
            and diagnostic["end"] is not None
            and diagnostic["start"] > diagnostic["end"]
        ):
            raise ProtocolError(f"{where}: start exceeds end")


def _reject_unstable_fields(value: Any, where: str) -> None:
    """Reject implementation artifacts that cannot form a portable contract."""
    forbidden = ("pointer", "address", "allocator", "timing", "zig_type")
    if isinstance(value, dict):
        for key, child in value.items():
            lowered = key.lower()
            if any(word in lowered for word in forbidden):
                raise ProtocolError(f"{where}.{key}: unstable implementation field")
            _reject_unstable_fields(child, f"{where}.{key}")
    elif isinstance(value, list):
        for index, child in enumerate(value):
            _reject_unstable_fields(child, f"{where}[{index}]")


def load_jsonl(path: Path, expected_stage: str | None = None) -> list[dict[str, Any]]:
    records: list[dict[str, Any]] = []
    with path.open("rb") as stream:
        for line_number, raw in enumerate(stream, 1):
            if not raw.endswith(b"\n"):
                raise ProtocolError(f"{path}:{line_number}: missing final newline")
            try:
                text = raw.decode("ascii")
                record = json.loads(text)
            except (UnicodeDecodeError, json.JSONDecodeError) as error:
                raise ProtocolError(f"{path}:{line_number}: invalid JSON: {error}") from error
            validate_record(record, expected_stage)
            if canonical_bytes(record) != raw:
                raise ProtocolError(f"{path}:{line_number}: non-canonical encoding")
            records.append(record)
    ids = [record["case_id"] for record in records]
    if ids != sorted(ids):
        raise ProtocolError(f"{path}: records must be sorted by case_id")
    if len(ids) != len(set(ids)):
        raise ProtocolError(f"{path}: duplicate case_id")
    return records


def write_jsonl(path: Path, records: Iterable[dict[str, Any]], stage: str) -> None:
    ordered = sorted(records, key=lambda record: record["case_id"])
    for record in ordered:
        validate_record(record, stage)
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("wb") as stream:
        for record in ordered:
            stream.write(canonical_bytes(record))
