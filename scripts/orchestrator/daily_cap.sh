#!/usr/bin/env bash
# daily_cap.sh [--now ISO_TS]
# Exit 0 = may open another PR. 4 = SUPERHUMAN_MAX_PRS_PER_DAY (default 6, 0 = off)
# new PRs already opened in the last 24h. 10 = config error.
#
# Global, not per-repo, so it is NOT part of reputation_gate.sh: repo-finder runs
# that gate per candidate and would empty the whole shortlist once the cap hit.
# Counts each PR by its first row in merge_outcomes.jsonl, i.e. when its run
# ended. ponytail: a run still in flight is not counted yet; parallel fleets can
# overshoot by their width.
set -euo pipefail
# Not exported by the harness (template variable only), so derive it from $0.
export CLAUDE_PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(CDPATH= cd "$(dirname "$0")/../.." && pwd)}"
source "${CLAUDE_PLUGIN_ROOT}/scripts/lib/state.sh"

NOW=""
while [ $# -gt 0 ]; do
  case "$1" in
    --now) [ $# -ge 2 ] || { echo "daily_cap.sh: --now requires a value" >&2; exit 10; }
           NOW="$2"; shift 2 ;;
    *) echo "daily_cap.sh: unknown arg: $1" >&2; exit 10 ;;
  esac
done
[ -z "$NOW" ] && NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)

CAP="${SUPERHUMAN_MAX_PRS_PER_DAY:-6}"
[ "$CAP" -gt 0 ] || exit 0

LOG="$(global_dir)/merge_outcomes.jsonl"
[ -f "$LOG" ] || exit 0

opened=$(jq -s --arg now "$NOW" "$OUTCOMES_JQ"'
  ({closed_at: $now} | row_epoch) as $now_e
  | map(select((.pr_url // "") != ""))
  | group_by(.pr_url)
  | map(map(row_epoch) | min | select(. > $now_e - 86400))
  | length' "$LOG")

if [ "$opened" -ge "$CAP" ]; then
  echo "DAILY_CAP: $opened PRs opened in the last 24h (cap $CAP)"
  exit 4
fi
echo "UNDER_DAILY_CAP: $opened/$CAP"
