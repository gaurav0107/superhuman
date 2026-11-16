#!/usr/bin/env bash
# record_regression.sh --repo OWNER/REPO --rule-id ID
#                      --kind (shipped_violation|maintainer_reraise) [--pr-url URL] [--ts ISO]
# Append-only JSONL to ~/.superhuman/global/lesson_regressions.jsonl — the
# "known enforced rule violated at submission / re-raised by a maintainer" alarm.
# Writers: lesson-distiller (maintainer_reraise), merge-probability-scorer (shipped_violation).
set -euo pipefail
# Not exported by the harness (template variable only), so derive it from $0.
export CLAUDE_PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(CDPATH= cd "$(dirname "$0")/../.." && pwd)}"
source "${CLAUDE_PLUGIN_ROOT}/scripts/lib/state.sh"

REPO=""; RULE_ID=""; KIND=""; PR_URL=""; TS=""
while [ $# -gt 0 ]; do
  case "$1" in
    --repo)    REPO="$2"; shift 2 ;;
    --rule-id) RULE_ID="$2"; shift 2 ;;
    --kind)    KIND="$2"; shift 2 ;;
    --pr-url)  PR_URL="$2"; shift 2 ;;
    --ts)      TS="$2"; shift 2 ;;
    *) echo "record_regression.sh: unknown arg: $1" >&2; exit 2 ;;
  esac
done
[ -n "$REPO" ]    || { echo "--repo required" >&2; exit 2; }
[ -n "$RULE_ID" ] || { echo "--rule-id required" >&2; exit 2; }
case "$KIND" in
  shipped_violation|maintainer_reraise) : ;;
  *) echo "record_regression.sh: --kind must be shipped_violation|maintainer_reraise" >&2; exit 2 ;;
esac
[ -n "$TS" ] || TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)

GD=$(global_dir); mkdir -p "$GD"
LOG="$GD/lesson_regressions.jsonl"
jq -nc --arg rid "$RULE_ID" --arg repo "$REPO" --arg pr "$PR_URL" --arg kind "$KIND" --arg ts "$TS" \
  '{rule_id: $rid, repo: $repo, pr_url: $pr, kind: $kind, ts: $ts}' >> "$LOG"
