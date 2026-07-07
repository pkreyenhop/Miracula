#!/usr/bin/env bash
#
# scorecard.sh — the single Zig-native-migration scorecard
# (docs/ZIG_NATIVE_PLAN.md Phase 0).
#
# Consolidates the four retired scripts (idiomatic-check.sh,
# readability-check.sh, shared-state-check.sh, test-coverage-check.sh — kept
# only as historical references, see their headers) plus the new metrics from
# the plan's §1 "definition of done" checklist and §3 baseline table:
#
#   - C-ism elimination: extern fn/[*:0]/c_int/c_long/ptr-casts, the printf
#     family, setjmp/longjmp, clib./c. call sites, callconv(.c)
#   - Shared-state elimination: module-scope mutable globals, ambient
#     singleton-accessor call sites
#   - Structure: files > 1000 lines, @import cycles
#   - Readability/testability (carried over): snake_case fns, doc coverage,
#     test-per-fn ratio
#
# Ratchet rule (see plan Phase 0 step 2): every count in scripts/scorecard.baseline
# may only go DOWN. `scripts/scorecard.sh --check` fails the build if any
# metric has risen; a commit that lowers a count must update the baseline in
# the same commit (`scripts/scorecard.sh --update-baseline`).
#
# Usage:
#   scripts/scorecard.sh                  # human-readable summary table
#   scripts/scorecard.sh -v                # also list every matching site
#   scripts/scorecard.sh --check           # machine check against the baseline; exit 1 on regression
#   scripts/scorecard.sh --update-baseline # rewrite the baseline from current counts
#
set -euo pipefail
cd "$(dirname "$0")/.."

SRC=src
BASELINE=scripts/scorecard.baseline

MODE=summary
VERBOSE=0
for arg in "$@"; do
    case "$arg" in
        -v) VERBOSE=1 ;;
        --check) MODE=check ;;
        --update-baseline) MODE=update ;;
        *) echo "usage: $0 [-v] [--check|--update-baseline]" >&2; exit 2 ;;
    esac
done

# FFI exemption: the C-shim, standalone tools, and the test harness
# legitimately use C types/pointers/globals and are excluded from every
# C-ism / shared-state metric (not from the structure or readability ones).
FFI_EXEMPT='src/os\.zig|src/runtime/c_abi\.zig|src/tools/'
TEST_EXEMPT='testutil\.zig|_tests?\.zig'
NONFFI_EXEMPT="${FFI_EXEMPT}|${TEST_EXEMPT}"

zg() { grep -rnE --include='*.zig' "$1" "$SRC" 2>/dev/null | grep -vE "$FFI_EXEMPT" || true; }
zg_nontest() { grep -rnE --include='*.zig' "$1" "$SRC" 2>/dev/null | grep -vE "$NONFFI_EXEMPT" || true; }
drop_ffi_sig() { grep -vE 'extern (fn|var)|export fn|callconv\(\.c\)' || true; }
count() { printf '%s' "$1" | grep -c . || true; }

declare -a NAMES COUNTS TARGETS DETAILS

add_metric() { # name count target detail
    NAMES+=("$1"); COUNTS+=("$2"); TARGETS+=("$3"); DETAILS+=("$4")
}

# ---------------------------------------------------------------------------
# Category 1: C-ism elimination (target: confined to the FFI shim
# src/os.zig, moved from src/runtime/os.zig in Phase 4 step 1).
# ---------------------------------------------------------------------------
m=$(zg 'c_int|c_long|c_uint|c_ulong' | drop_ffi_sig)
add_metric "c_int/c_long/c_uint/c_ulong (non-FFI)" "$(count "$m")" "0 outside os.zig" "$m"

m=$(zg '\[\*:0\]' | drop_ffi_sig)
add_metric "[*:0] C-string types (non-FFI)" "$(count "$m")" "0 outside os.zig" "$m"

m=$(grep -rnE --include='*.zig' 'extern fn ' "$SRC" || true)
add_metric "extern fn declarations" "$(count "$m")" "syscall floor only (os.zig)" "$m"

m=$(grep -rnE --include='*.zig' 'extern var ' "$SRC" || true)
add_metric "extern var declarations" "$(count "$m")" "0" "$m"

m=$(zg '@intFromPtr|@ptrFromInt')
add_metric "@intFromPtr / @ptrFromInt (non-FFI)" "$(count "$m")" "0" "$m"

m=$(zg '\bprintf\(|\bfprintf\(|\bsprintf\(|word\.print\(|word\.printErr\(')
add_metric "printf-family calls (non-FFI)" "$(count "$m")" "0 (Phase 2)" "$m"

m=$(grep -rnE --include='*.zig' 'setjmp|longjmp|jmp_buf' "$SRC" || true)
add_metric "setjmp/longjmp/jmp_buf mentions" "$(count "$m")" "0 (Phase 3)" "$m"

m=$(grep -rnE --include='*.zig' '\b(clib|c)\.[a-zA-Z0-9_]+' "$SRC" | grep -vE "$FFI_EXEMPT" || true)
add_metric "clib./c. call sites (non-FFI)" "$(count "$m")" "0" "$m"

m=$(grep -rnE --include='*.zig' 'callconv\(\.c\)' "$SRC" || true)
add_metric "callconv(.c) usage" "$(count "$m")" "signal trampoline only" "$m"

m=$(zg '== NIL|!= NIL')
add_metric "sentinel == NIL / != NIL (non-FFI)" "$(count "$m")" "reduced (Phase 5)" "$m"

m=$(zg '\bfork\(\)|\bwait\(')
add_metric "fork()/wait() call sites (non-FFI)" "$(count "$m")" "0 (Phase 3)" "$m"

# ---------------------------------------------------------------------------
# Category 2: shared-state elimination
# ---------------------------------------------------------------------------
m=$(grep -rnE --include='*.zig' '^(pub )?(export )?var [A-Za-z_]' "$SRC" 2>/dev/null | grep -vE "$NONFFI_EXEMPT" || true)
add_metric "module-scope mutable globals (non-FFI)" "$(count "$m")" "1 (interrupt flag)" "$m"

m=$(grep -rnE --include='*.zig' '\b(heap\.heap\(\)|rs\(\)|cs\(\)|ls\(\)|ev\(\)|s\(\))\.' "$SRC" 2>/dev/null | grep -vE "$NONFFI_EXEMPT" || true)
add_metric "ambient singleton-accessor call sites" "$(count "$m")" "0 (Phase 4)" "$m"

m=$(grep -rnE --include='*.zig' 'current_interp' "$SRC" 2>/dev/null || true)
add_metric "current_interp references" "$(count "$m")" "0 (Phase 4)" "$m"

# ---------------------------------------------------------------------------
# Category 3: structure
# ---------------------------------------------------------------------------
big_files=$(find "$SRC" -name '*.zig' -exec wc -l {} \; | awk '$1 > 1000 {print $2 ": " $1 " lines"}')
add_metric "files > 1000 lines" "$(count "$big_files")" "0 (Phase 4)" "$big_files"

cycles_out=$(python3 scripts/import_cycles.py "$SRC" -v 2>/dev/null || true)
cycles_n=$(printf '%s\n' "$cycles_out" | head -1 | grep -oE '[0-9]+$' || echo 0)
add_metric "@import cycles" "$cycles_n" "0 (Phase 4)" "$cycles_out"

layer_out=$(python3 scripts/layer_check.py "$SRC" 2>&1 || true)
layer_n=$(printf '%s\n' "$layer_out" | head -1 | grep -oE '[0-9]+ new' | grep -oE '^[0-9]+' || echo 0)
add_metric "unallowed §4.1 layer violations" "$layer_n" "0 (Phase 4)" "$layer_out"

# ---------------------------------------------------------------------------
# Category 4: readability / testability (carried over, informational)
# ---------------------------------------------------------------------------
EXEMPT_FN='fn handle_?[A-Z]|fn tab_complete'
m=$(grep -rnE --include='*.zig' '^[[:space:]]*(pub )?(export )?fn [a-z][a-zA-Z0-9]*_' "$SRC" 2>/dev/null | grep -vE "$FFI_EXEMPT" | grep -vE "$EXEMPT_FN" || true)
add_metric "C-style (snake_case) fn definitions" "$(count "$m")" "0" "$m"

doc_total=0; doc_done=0
while read -r f; do
    read -r d n < <(awk '
      /^[[:space:]]*\/\/\//      { prev=1; next }
      /^[[:space:]]*(pub )?(export )?fn [a-zA-Z]/ { tot++; if (prev) d++; prev=0; next }
      { prev=0 }
      END { print d+0, tot+0 }' "$f")
    doc_total=$((doc_total + n)); doc_done=$((doc_done + d))
done < <(find "$SRC" -name '*.zig' | grep -vE "$FFI_EXEMPT")
doc_pct=0; [ "$doc_total" -gt 0 ] && doc_pct=$(( 100 * doc_done / doc_total ))
add_metric "documented fn definitions" "${doc_done}/${doc_total} (${doc_pct}%)" "~100%" ""

test_total=0; fn_total=0
while read -r f; do
    t=$(grep -cE '^[[:space:]]*test [@"]' "$f" 2>/dev/null || true)
    n=$(grep -cE '^[[:space:]]*(pub )?(export )?(inline )?fn ' "$f" 2>/dev/null || true)
    test_total=$((test_total + t)); fn_total=$((fn_total + n))
done < <({ find "$SRC" -name '*.zig'; find tests -name '*.zig'; } | grep -vE "$FFI_EXEMPT")
test_pct=0; [ "$fn_total" -gt 0 ] && test_pct=$(( 100 * test_total / fn_total ))
add_metric "test blocks / fn definitions" "${test_total}/${fn_total} (${test_pct}%)" "~100%" ""

# ---------------------------------------------------------------------------
# Output
# ---------------------------------------------------------------------------
print_summary() {
    echo "Zig-native migration scorecard  ($(date +%Y-%m-%d))"
    echo "--------------------------------------------------------------------------------"
    printf '%-3s %-46s %12s   %s\n' "#" "metric" "count" "target"
    echo "--------------------------------------------------------------------------------"
    for i in "${!NAMES[@]}"; do
        printf '%-3s %-46s %12s   %s\n' "$((i+1))" "${NAMES[$i]}" "${COUNTS[$i]}" "${TARGETS[$i]}"
        if [ "$VERBOSE" = 1 ] && [ -n "${DETAILS[$i]}" ]; then
            printf '%s\n' "${DETAILS[$i]}" | sed 's/^/      /'
            echo
        fi
    done
    echo "--------------------------------------------------------------------------------"
}

# Only the strictly-numeric metrics (categories 1-3) are ratchet-checked;
# the readability/testability ones (category 4) are informational trends,
# not gates (they are meant to visibly *rise*, not fall).
RATCHET_COUNT=17

case "$MODE" in
    summary)
        print_summary
        echo "Run with -v to list matching sites, --check to gate on the baseline."
        ;;
    update)
        : > "$BASELINE"
        for i in "${!NAMES[@]}"; do
            if [ "$i" -lt "$RATCHET_COUNT" ]; then
                printf '%s\t%s\n' "${NAMES[$i]}" "${COUNTS[$i]}" >> "$BASELINE"
            fi
        done
        echo "Wrote $BASELINE ($(wc -l < "$BASELINE" | tr -d ' ') metrics)."
        ;;
    check)
        print_summary
        if [ ! -f "$BASELINE" ]; then
            echo "No baseline at $BASELINE — run --update-baseline first." >&2
            exit 1
        fi
        fail=0
        for i in "${!NAMES[@]}"; do
            [ "$i" -lt "$RATCHET_COUNT" ] || continue
            name="${NAMES[$i]}"; cur="${COUNTS[$i]}"
            base_line=$(grep -F "$name"$'\t' "$BASELINE" || true)
            if [ -z "$base_line" ]; then
                echo "WARN: no baseline entry for '$name' — treating as new metric (0)." >&2
                base=0
            else
                base="${base_line#*$'\t'}"
            fi
            if [ "$cur" -gt "$base" ]; then
                echo "REGRESSION: '$name' rose from $base to $cur" >&2
                fail=1
            fi
        done
        if [ "$fail" = 1 ]; then
            echo "scorecard check FAILED — a tracked metric regressed. See docs/ZIG_NATIVE_PLAN.md." >&2
            exit 1
        fi
        echo "scorecard check OK — no tracked metric rose above baseline."
        ;;
esac
