#!/usr/bin/env bash
#
# idiomatic-check.sh — Phase 9 "idiomatic Zig" scorecard (plan step L0).
#
# Emits the eight measurable metrics from docs/IDIOMATIC_ZIG_PLAN.md so that
# every Phase 9 micro-step can verify its own progress against a number rather
# than a judgement call.
#
# FFI exemption: the C-shim files and standalone tools legitimately use C
# types / pointers / snake_case names and are excluded from every metric.
#
# Usage:   scripts/idiomatic-check.sh           # summary table
#          scripts/idiomatic-check.sh -v         # also list the matching lines
#
set -euo pipefail

cd "$(dirname "$0")/.."

VERBOSE=0
[ "${1:-}" = "-v" ] && VERBOSE=1

SRC=src

# Files that are legitimately C-ABI / standalone and exempt from all metrics.
EXEMPT='src/runtime/main_clib.zig|src/runtime/c_abi.zig|src/tools/'

# grep helper: search *.zig under src, drop exempt files.
zg() { grep -rnE --include='*.zig' "$1" "$SRC" 2>/dev/null | grep -vE "$EXEMPT" || true; }

# Drop lines that are genuine FFI signatures (extern/export/callconv .c).
drop_ffi() { grep -vE 'extern (fn|var)|export fn|callconv\(\.c\)' || true; }

metric() { # name  count  target  lines
    local name="$1" count="$2" target="$3"; shift 3
    printf '%-3s %-44s %5s   %s\n' "$IDX." "$name" "$count" "$target"
    if [ "$VERBOSE" = 1 ] && [ -n "${1:-}" ]; then
        printf '%s\n' "$1" | sed 's/^/      /'
        echo
    fi
}

echo "Idiomatic-Zig scorecard  ($(date +%Y-%m-%d))   [FFI shims & src/tools excluded]"
echo "------------------------------------------------------------------------------"
printf '%-3s %-44s %5s   %s\n' "#" "metric (non-FFI scope)" "count" "target"
echo "------------------------------------------------------------------------------"

IDX=1
m1=$(zg 'c_int|c_long|c_uint' | drop_ffi)
metric "internal c_int/c_long/c_uint" "$(printf '%s' "$m1" | grep -c . || true)" "0" "$m1"

IDX=2
m2=$(zg '\[\*:0\]' | drop_ffi)
metric "[*:0] on Zig-only signatures" "$(printf '%s' "$m2" | grep -c . || true)" "enumerated" "$m2"

IDX=3
m3=$(zg '\?\?\[\*\]Word|\[\*\]Word' | drop_ffi)
metric "[*]Word / ?[*]Word non-FFI" "$(printf '%s' "$m3" | grep -c . || true)" "enumerated" "$m3"

IDX=4
m4=$(zg '== NIL|!= NIL')
metric "sentinel == NIL / != NIL" "$(printf '%s' "$m4" | grep -c . || true)" "reduced" "$m4"

IDX=5
m5=$(zg 'return NIL')
metric "return NIL as error signal" "$(printf '%s' "$m5" | grep -c . || true)" "0" "$m5"

IDX=6
m6=$(zg 'clib\.exit\(1\)')
metric "bare clib.exit(1) (use fatal())" "$(printf '%s' "$m6" | grep -c . || true)" "0" "$m6"

IDX=7
# file-private fn (not pub/export) whose name contains an underscore
m7=$(grep -rnE --include='*.zig' '^[[:space:]]*fn [a-z][a-zA-Z0-9]*_' "$SRC" 2>/dev/null \
       | grep -vE "$EXEMPT" || true)
metric "file-private snake_case fn" "$(printf '%s' "$m7" | grep -c . || true)" "exemptions" "$m7"

IDX=8
m8=$(zg '= undefined' | drop_ffi)
metric "= undefined initialisers" "$(printf '%s' "$m8" | grep -c . || true)" "audited" "$m8"

echo "------------------------------------------------------------------------------"
echo "Run with -v to list the matching source lines for each metric."
