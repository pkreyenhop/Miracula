#!/usr/bin/env bash
#
# test-coverage-check.sh — progress metric for docs/TESTABILITY_PLAN.md.
#
# The north star is "at least one `test` per function definition" (a test that
# both verifies and documents the function). This reports, per module, the number
# of `test` blocks against the number of function definitions, plus the totals.
#
# It is a coarse proxy — a module's tests need not sit literally under each fn —
# but it tracks the gap and shows where the coverage work is. FFI shim and tools
# are excluded (same convention as the readability/shared-state scorecards).
#
set -euo pipefail
cd "$(dirname "$0")/.."

EXEMPT='src/tools/|src/runtime/main_clib.zig'
files() { { find src -name '*.zig'; find tests -name '*.zig'; } | grep -vE "$EXEMPT" | sort; }

tests_in()  { grep -cE '^[[:space:]]*test [@"]' "$1" 2>/dev/null || true; }
fns_in()    { grep -cE '^[[:space:]]*(pub )?(export )?(inline )?fn ' "$1" 2>/dev/null || true; }

total_t=0; total_f=0
declare -a rows
while read -r f; do
  t=$(tests_in "$f"); fn=$(fns_in "$f")
  total_t=$((total_t + t)); total_f=$((total_f + fn))
  [ "$fn" -gt 0 ] && rows+=("$(printf '%4d /%4d   %s' "$t" "$fn" "${f#./}")")
done < <(files)

pct=0; [ "$total_f" -gt 0 ] && pct=$(( 100 * total_t / total_f ))
echo "Test-coverage scorecard  ($(date +%Y-%m-%d))   [FFI shim & src/tools excluded]"
echo "------------------------------------------------------------------------------"
printf 'test blocks                 %5d\n' "$total_t"
printf 'function definitions        %5d\n' "$total_f"
printf 'tests-per-fn ratio          %4d%%   target ~100%% (one test per fn)\n' "$pct"
echo "------------------------------------------------------------------------------"
printf '%s\n' "tests/ fns   module"
printf '%s\n' "${rows[@]}" | sort -t/ -k1 -rn
