#!/usr/bin/env bash
# historical_blend.sh --rubric-01 X --merge-log FILE --repo OWNER/REPO --weight W
# Emits {merge_estimate_01, rubric_01, weight, blended} on stdout (blended on 0..10).
# Source: merge-probability-scorer.md Step 3a. Fixes the unbalanced paren bug
# from line ~257 of the original (audit §18).
set -euo pipefail
# Not exported by the harness (template variable only), so derive it from $0.
export CLAUDE_PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(CDPATH= cd "$(dirname "$0")/../.." && pwd)}"

RUBRIC_01=""
MERGE_LOG=""
REPO=""
W="0.3"

while [ $# -gt 0 ]; do
  case "$1" in
    --rubric-01) RUBRIC_01="$2"; shift 2 ;;
    --merge-log) MERGE_LOG="$2"; shift 2 ;;
    --repo)      REPO="$2"; shift 2 ;;
    --weight)    W="$2"; shift 2 ;;
    *) echo "historical_blend.sh: unknown arg: $1" >&2; exit 2 ;;
  esac
done

[ -z "$RUBRIC_01" ] && { echo "--rubric-01 required" >&2; exit 2; }
[ -z "$REPO" ]      && { echo "--repo required" >&2; exit 2; }

source "${CLAUDE_PLUGIN_ROOT}/scripts/lib/state.sh"

# Merged vs concluded PRs for this repo, each PR once (its latest row: the sweep's
# merged/closed_no_merge supersedes the run's own plateau/merge_ready exit).
# Run-exit reasons are not PR outcomes and stay out of the denominator.
# Laplace-ish: (m + 1) / (n + 2).
counts=$(jq -s --arg r "$REPO" "$OUTCOMES_JQ"'
  map(select(.repo == $r)) | latest_per_pr
  | map(select(.outcome | IN("merged","closed_no_merge")))
  | {merged: (map(select(.outcome == "merged")) | length),
     total:  length}
' "$MERGE_LOG" 2>/dev/null || echo '{"merged":0,"total":0}')

m=$(echo "$counts" | jq -r .merged)
n=$(echo "$counts" | jq -r .total)

MERGE_EST=$(python3 -c "print(round(($m + 1) / ($n + 2), 4))")
BLENDED=$(python3 -c "print(round(10 * ((1-$W) * $RUBRIC_01 + $W * $MERGE_EST), 2))")

jq -nc \
  --argjson est "$MERGE_EST" \
  --argjson rub "$RUBRIC_01" \
  --argjson w   "$W" \
  --argjson b   "$BLENDED" \
  '{merge_estimate_01:$est, rubric_01:$rub, weight:$w, blended:$b}'
