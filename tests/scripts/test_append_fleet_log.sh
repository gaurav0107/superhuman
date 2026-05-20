#!/usr/bin/env bash
set -euo pipefail
export CLAUDE_PLUGIN_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

tmpdir=$(mktemp -d)
HOME="$tmpdir" bash "$CLAUDE_PLUGIN_ROOT/scripts/orchestrator/append_fleet_log.sh" \
  --fleet-id fleet-x --repo a/a --outcome merged --iterations 3 \
  --pr-url https://x --completed-at 2026-05-18T00:00:00Z

LOG="$tmpdir/.superhuman/global/fleet_runs.jsonl"
[ -f "$LOG" ] || { echo "FAIL no log"; exit 1; }
[ "$(wc -l < "$LOG" | tr -d ' ')" = "1" ] || { echo "FAIL line count"; exit 1; }
jq -e '.outcome=="merged"' "$LOG" >/dev/null || { echo "FAIL outcome"; exit 1; }
echo "OK test_append_fleet_log.sh"
