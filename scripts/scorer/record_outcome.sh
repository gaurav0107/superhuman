#!/usr/bin/env bash
# record_outcome.sh --repo --pr-url --outcome --iterations --closed-at --final-scores
# Append-only JSONL to ~/.superhuman/global/merge_outcomes.jsonl.
set -euo pipefail
: "${CLAUDE_PLUGIN_ROOT:?CLAUDE_PLUGIN_ROOT must be set}"
source "${CLAUDE_PLUGIN_ROOT}/scripts/lib/state.sh"

REPO=""; PR_URL=""; OUTCOME=""; ITER=""; CLOSED_AT=""; FINAL_SCORES="{}"

while [ $# -gt 0 ]; do
  case "$1" in
    --repo)         REPO="$2"; shift 2 ;;
    --pr-url)       PR_URL="$2"; shift 2 ;;
    --outcome)      OUTCOME="$2"; shift 2 ;;
    --iterations)   ITER="$2"; shift 2 ;;
    --closed-at)    CLOSED_AT="$2"; shift 2 ;;
    --final-scores) FINAL_SCORES="$2"; shift 2 ;;
    *) echo "record_outcome.sh: unknown arg: $1" >&2; exit 2 ;;
  esac
done

GD=$(global_dir)
mkdir -p "$GD"
LOG="$GD/merge_outcomes.jsonl"

jq -nc \
  --arg pr "$PR_URL" --arg repo "$REPO" --arg out "$OUTCOME" \
  --arg ts "$CLOSED_AT" --argjson iter "$ITER" --argjson fs "$FINAL_SCORES" \
  '{pr_url:$pr, repo:$repo, outcome:$out, final_scores:$fs, iterations:$iter, closed_at:$ts}' \
  >> "$LOG"
