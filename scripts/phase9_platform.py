#!/usr/bin/env python3
"""Verify the portable platform boundary and supported-target contract."""

from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "src"
MANIFEST = ROOT / "tests" / "phase9_platform_contract.json"

ALLOWED_NATIVE = {
    "io/platform.zig",
    "io/process.zig",
    "io/signals.zig",
    "eval/stream.zig",
    "os.zig",
    "os_scanf.zig",
    "platform/c_compat.zig",
}


def main() -> None:
    contract = json.loads(MANIFEST.read_text(encoding="utf-8"))
    assert contract["schema"] == 1
    assert contract["supported_targets"] == ["aarch64-macos"]
    assert set(contract["services"]) == {
        "filesystem_metadata", "process_spawn_wait", "pipes_and_streams",
        "shell_execution", "signal_notification", "terminal_detection_and_size",
        "monotonic_clock", "environment_lookup", "executable_lookup",
    }
    assert contract["process"]["shell_fallback"] == "/bin/sh"
    assert contract["process"]["command_argument"] == "-c"
    assert contract["process"]["outcomes"] == ["exited", "signaled"]
    assert contract["process"]["errors"] == [
        "SpawnFailed", "WaitFailed", "TimedOut", "Interrupted",
    ]
    for key in (
        "stdout_stderr_separate", "close_parent_pipe_ends_before_wait",
        "eof_after_child_closes_writer", "consume_pipes_before_wait",
        "cleanup_on_interrupt_or_timeout", "inherits_environment",
        "inherits_working_directory",
    ):
        assert contract["process"][key] is True

    platform_contract = (SRC / "io/platform_contract.zig").read_text()
    for marker in (
        "pub const Services", "pub const ProcessRequest",
        "pub const ProcessOutcome", "pub const ProcessError",
        "pub const Signal", "pub const TerminalInfo",
    ):
        assert marker in platform_contract, f"missing platform contract: {marker}"
    assert "std.posix" not in platform_contract
    assert "c_int" not in platform_contract

    offenders = []
    for path in SRC.rglob("*.zig"):
        rel = path.relative_to(SRC).as_posix()
        if rel in ALLOWED_NATIVE or rel.startswith("tools/"):
            continue
        text = path.read_text(encoding="utf-8")
        if "std.posix" in text or "std.os.linux" in text:
            offenders.append(rel)
    assert not offenders, f"native OS types escaped platform implementation: {offenders}"

    signals = (SRC / "io/signals.zig").read_text()
    assert "handler: usize" not in signals
    for path in SRC.rglob("*.zig"):
        if path.relative_to(SRC).as_posix() in ALLOWED_NATIVE:
            continue
        text = path.read_text(encoding="utf-8")
        assert "signals(" not in text
        assert "abi.fork()" not in text
        assert "abi.wait(" not in text

    workflow = (ROOT / ".github/workflows/go-ready.yml").read_text()
    assert "ubuntu" not in workflow.lower()
    assert "runs-on: macos-15" in workflow
    assert "zig build go-ready --summary failures" in workflow
    print("phase 9 platform boundary verified: typed services, signals, processes, and macOS CI")


if __name__ == "__main__":
    main()
