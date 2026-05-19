# tests/scripts/test_record_outcome.sh
#!/usr/bin/env bash
set -euo pipefail
export CLAUDE_PLUGIN_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

tmpdir=$(mktemp -d)

HOME="$tmpdir" bash "$CLAUDE_PLUGIN_ROOT/scripts/scorer/record_outcome.sh" \
  --repo apache/airflow \
  --pr-url https://github.com/apache/airflow/pull/65685 \
  --outcome merged \
  --iterations 3 \
  --closed-at 2026-04-28T09:12:00Z \
  --final-scores '{"correctness":9,"test_coverage":8}'

LOG="$tmpdir/.superhuman/global/merge_outcomes.jsonl"
[ -f "$LOG" ] || { echo "FAIL log not created"; exit 1; }
[ "$(wc -l < "$LOG" | tr -d ' ')" = "1" ] || { echo "FAIL line count"; exit 1; }
jq -e '.outcome=="merged"' "$LOG" >/dev/null || { echo "FAIL outcome"; exit 1; }

echo "OK test_record_outcome.sh"
