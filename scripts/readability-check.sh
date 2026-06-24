#!/usr/bin/env bash
#
# readability-check.sh — progress metric for docs/READABILITY_PLAN.md.
#
# Tracks the module-by-module "idiomatic names + documentation" pass:
#   1. C-style (snake_case) function definitions  — the rename metric (→ 0)
#   2. doc-comment coverage of function definitions — the documentation metric
#
# FFI exemption: the C-shim (`main_clib.zig`) and standalone tools legitimately
# keep C names mirroring libc, and are excluded.
#
# Usage:  scripts/readability-check.sh        # summary + per-file breakdown
#         scripts/readability-check.sh -v       # also list each snake_case fn
#
set -euo pipefail
cd "$(dirname "$0")/.."

SRC=src
EXEMPT='src/tools/|src/runtime/main_clib.zig'

files() { find "$SRC" -name '*.zig' | grep -vE "$EXEMPT" | sort; }

# snake_case fn definitions in one file. `handle_<COMBINATOR>` reducer dispatch
# handlers are exempt: the snake suffix mirrors the uppercase combinator constant
# (word.G_ALT -> handle_G_ALT) and keeps the dispatch table grep-aligned.
snake() { grep -E '^[[:space:]]*(pub )?(export )?fn [a-z][a-zA-Z0-9]*_' "$1" 2>/dev/null | grep -cvE 'fn handle_[A-Z]' || true; }

# doc-commented fn defs: a `fn NAME(` whose immediately-preceding line is `///`.
doced() { awk '
  /^[[:space:]]*\/\/\//      { prev=1; next }
  /^[[:space:]]*(pub )?(export )?fn [a-zA-Z]/ { tot++; if (prev) d++; prev=0; next }
  { prev=0 }
  END { print d+0, tot+0 }' "$1"; }

total_snake=0; total_doc=0; total_fn=0
declare -a rows
while read -r f; do
  s=$(snake "$f")
  read -r d n < <(doced "$f")
  total_snake=$((total_snake + s)); total_doc=$((total_doc + d)); total_fn=$((total_fn + n))
  rows+=("$(printf '%4d  %3d/%-3d  %s' "$s" "$d" "$n" "${f#src/}")")
done < <(files)

pct=0; [ "$total_fn" -gt 0 ] && pct=$(( 100 * total_doc / total_fn ))

echo "Readability scorecard  ($(date +%Y-%m-%d))   [FFI shim & src/tools excluded]"
echo "------------------------------------------------------------------------------"
printf 'C-style (snake_case) fn definitions   %5d   target 0\n' "$total_snake"
printf 'documented fn definitions             %4d/%-4d (%d%%)   target ~100%%\n' "$total_doc" "$total_fn" "$pct"
echo "------------------------------------------------------------------------------"
printf '%s\n' "snake  doc/fns  file"
printf '%s\n' "${rows[@]}" | sort -rn

if [ "${1:-}" = "-v" ]; then
  echo; echo "snake_case fn definitions:"
  grep -rnE '^[[:space:]]*(pub )?(export )?fn [a-z][a-zA-Z0-9]*_' $(files) | sed 's/^/  /'
fi
