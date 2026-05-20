#!/usr/bin/env bash
# append_fleet_log.sh --fleet-id ID --repo R --outcome O --iterations N --pr-url U --completed-at TS
# Append-only JSONL to ~/.superhuman/global/fleet_runs.jsonl.
set -euo pipefail
: "${CLAUDE_PLUGIN_ROOT:?CLAUDE_PLUGIN_ROOT must be set}"
source "${CLAUDE_PLUGIN_ROOT}/scripts/lib/state.sh"

FID=""; REPO=""; OUT=""; ITER=""; PR=""; TS=""
while [ $# -gt 0 ]; do
  case "$1" in
    --fleet-id)     FID="$2"; shift 2 ;;
    --repo)         REPO="$2"; shift 2 ;;
    --outcome)      OUT="$2"; shift 2 ;;
    --iterations)   ITER="$2"; shift 2 ;;
    --pr-url)       PR="$2"; shift 2 ;;
    --completed-at) TS="$2"; shift 2 ;;
    *) echo "append_fleet_log.sh: unknown arg: $1" >&2; exit 2 ;;
  esac
done

GD=$(global_dir)
mkdir -p "$GD"
LOG="$GD/fleet_runs.jsonl"

jq -nc \
  --arg fid "$FID" --arg repo "$REPO" --arg out "$OUT" \
  --argjson iter "${ITER:-0}" --arg pr "$PR" --arg ts "$TS" \
  '{fleet_id:$fid, repo:$repo, outcome:$out, iterations:$iter, pr_url:$pr, completed_at:$ts}' \
  >> "$LOG"
