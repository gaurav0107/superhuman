#!/usr/bin/env bash
set -euo pipefail
export CLAUDE_PLUGIN_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CAP_SH="$CLAUDE_PLUGIN_ROOT/scripts/orchestrator/daily_cap.sh"

tmpdir=$(mktemp -d)
GD="$tmpdir/.superhuman/global"
mkdir -p "$GD"
NOW="2026-05-18T12:00:00Z"

# No log yet -> under cap.
HOME="$tmpdir" bash "$CAP_SH" --now "$NOW" >/dev/null || { echo "FAIL no log"; exit 1; }

# pull/1 and pull/2 opened in the last 24h (pull/2 twice: run exit + later sweep row,
# counts once). pull/3 is old but got a fresh sweep row today: must not count.
# A row without pr_url (no_eligible_issue) never counts.
cat > "$GD/merge_outcomes.jsonl" <<'EOF'
{"repo":"a/a","pr_url":"https://github.com/a/a/pull/3","outcome":"plateau","ts":"2026-05-01T00:00:00Z"}
{"repo":"a/a","pr_url":"https://github.com/a/a/pull/1","outcome":"plateau","closed_at":"2026-05-18T01:00:00Z"}
{"repo":"a/a","pr_url":"https://github.com/a/a/pull/2","outcome":"merge_ready","closed_at":"2026-05-17T13:00:00Z"}
{"repo":"a/a","pr_url":"https://github.com/a/a/pull/2","outcome":"merged","closed_at":"2026-05-18T11:00:00Z"}
{"repo":"a/a","pr_url":"https://github.com/a/a/pull/3","outcome":"merged","closed_at":"2026-05-18T11:00:00Z"}
{"repo":"a/a","outcome":"no_eligible_issue","ts":"2026-05-18T11:00:00Z"}
EOF

SUPERHUMAN_MAX_PRS_PER_DAY=3 HOME="$tmpdir" bash "$CAP_SH" --now "$NOW" >/dev/null \
  || { echo "FAIL 2 opened, cap 3 should pass"; exit 1; }

set +e
SUPERHUMAN_MAX_PRS_PER_DAY=2 HOME="$tmpdir" bash "$CAP_SH" --now "$NOW" >/dev/null
rc=$?
set -e
[ "$rc" = "4" ] || { echo "FAIL cap 2 rc: $rc (want 4)"; exit 1; }

SUPERHUMAN_MAX_PRS_PER_DAY=0 HOME="$tmpdir" bash "$CAP_SH" --now "$NOW" >/dev/null \
  || { echo "FAIL cap 0 should disable"; exit 1; }

set +e
HOME="$tmpdir" bash "$CAP_SH" --bogus >/dev/null 2>&1
rc=$?
set -e
[ "$rc" = "10" ] || { echo "FAIL bad arg rc: $rc (want 10)"; exit 1; }

echo "OK test_daily_cap.sh"
