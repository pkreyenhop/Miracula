#!/usr/bin/env bash
#
# shared-state-check.sh — scorecard for docs/SHARED_STATE_PLAN.md.
#
# Counts non-FFI module-scope mutable globals — the single metric the
# shared-state plan drives from its baseline down to 1 (the `current_interp`
# pointer required by C-ABI signal delivery). Every phase verifies its progress
# against this number rather than a judgement call.
#
# FFI exemption: the C-shim files and standalone tools legitimately use C
# globals and are excluded.
#
# Test-harness exemption: testutil.zig / *_test.zig / *_tests.zig are never
# linked into the `mira` executable (only main.zig's comptime test-aggregation
# block imports them, and every other importer is itself full of `test "..."`
# blocks) - their one-time-setup guard flags (e.g. testutil.zig's `ready`) are
# test-harness bookkeeping about the ambient singleton, not interpreter state
# that would ever need to live in `Interp` for a second instance to exist.
#
# Usage:   scripts/shared-state-check.sh        # summary + by-file breakdown
#          scripts/shared-state-check.sh -v      # also list every matching site
#
set -euo pipefail

cd "$(dirname "$0")/.."

SRC=src
EXEMPT='src/runtime/main_clib.zig|src/runtime/c_abi.zig|src/tools/|testutil\.zig|_tests?\.zig'

# Module-scope (column-0) mutable globals: `var X`, `pub var X`, `export var X`,
# `pub export var X`. Indented `var` (function locals) is intentionally ignored.
globals() {
    grep -rnE --include='*.zig' '^(pub )?(export )?var [A-Za-z_]' "$SRC" 2>/dev/null \
        | grep -vE "$EXEMPT" || true
}

all="$(globals)"
total=$(printf '%s' "$all" | grep -c . || true)
exported=$(printf '%s' "$all" | grep -cE ':[0-9]+:(pub )?export var ' || true)

echo "Shared-state scorecard  ($(date +%Y-%m-%d))   [FFI shims, src/tools & test harness excluded]"
echo "--------------------------------------------------------------------------------"
printf '%-52s %5s   %s\n' "module-scope mutable globals" "$total" "target 1 (signal ptr)"
printf '%-52s %5s   %s\n' "  ↳ gratuitous \`export var\` (Phase 1 target)" "$exported" "target 0"
echo "--------------------------------------------------------------------------------"
echo "by file:"
printf '%s\n' "$all" | sed -E 's/:[0-9]+:.*//' | sort | uniq -c | sort -rn

if [ "${1:-}" = "-v" ]; then
    echo
    echo "all sites:"
    printf '%s\n' "$all" | sed 's/^/  /'
fi
