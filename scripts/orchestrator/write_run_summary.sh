#!/usr/bin/env bash
# write_run_summary.sh --repo R --outcome O [--iterations N] [--pr-url U] --completed-at TS --exit-reason WHY
# Writes ~/.superhuman/repos/<slug>/run_summary.json on every terminal state.
# Per audit §4: this is single-source-of-truth for /contribute-loop
# (merge_outcomes.jsonl is only written on normal terminal states).
set -euo pipefail
# Not exported by the harness (template variable only), so derive it from $0.
export CLAUDE_PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(CDPATH= cd "$(dirname "$0")/../.." && pwd)}"
source "${CLAUDE_PLUGIN_ROOT}/scripts/lib/state.sh"

REPO=""; OUT=""; ITER="0"; PR=""; TS=""; REASON=""
while [ $# -gt 0 ]; do
  case "$1" in
    --repo)         REPO="$2"; shift 2 ;;
    --outcome)      OUT="$2"; shift 2 ;;
    --iterations)   ITER="$2"; shift 2 ;;
    --pr-url)       PR="$2"; shift 2 ;;
    --completed-at) TS="$2"; shift 2 ;;
    --exit-reason)  REASON="$2"; shift 2 ;;
    *) echo "write_run_summary.sh: unknown arg: $1" >&2; exit 2 ;;
  esac
done
[ -z "$REPO" ] && { echo "--repo required" >&2; exit 2; }
[ -z "$OUT" ]  && { echo "--outcome required" >&2; exit 2; }
[ -z "$TS" ]   && TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)

dir=$(state_dir "$REPO")
content=$(jq -nc \
  --arg out "$OUT" --argjson iter "$ITER" \
  --arg pr "$PR" --arg ts "$TS" --arg reason "$REASON" \
  '{outcome:$out, iterations:$iter, pr_url:(if $pr=="" then null else $pr end),
    completed_at:$ts, exit_reason:$reason}')
atomic_write_json "$dir/run_summary.json" "$content"

# Best-effort adoption telemetry (opt-out). Backgrounded + fully swallowed so it
# can never block or fail the run. See scripts/lib/usage_ping.sh and TELEMETRY.md.
"${CLAUDE_PLUGIN_ROOT}/scripts/lib/usage_ping.sh" \
  --pr-url "$PR" --outcome "$OUT" >/dev/null 2>&1 & disown 2>/dev/null || true
