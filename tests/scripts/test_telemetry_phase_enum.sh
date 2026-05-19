#!/usr/bin/env bash
set -euo pipefail
export CLAUDE_PLUGIN_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
source "$CLAUDE_PLUGIN_ROOT/scripts/lib/telemetry.sh"

tmpdir=$(mktemp -d)
TF="$tmpdir/run_telemetry.jsonl"

emit_telemetry "$TF" "scorer" 1 38 "ok" '{"final_score":72}' || { echo "FAIL allowed"; exit 1; }
[ "$(wc -l < "$TF" | tr -d ' ')" = "1" ] || { echo "FAIL append"; exit 1; }
jq -e '.phase=="scorer"' "$TF" >/dev/null || { echo "FAIL phase value"; exit 1; }

if emit_telemetry "$TF" "not-a-phase" 1 1 "ok" 'null' 2>/dev/null; then
  echo "FAIL: bad phase should reject"; exit 1
fi
[ "$(wc -l < "$TF" | tr -d ' ')" = "1" ] || { echo "FAIL: bad phase appended"; exit 1; }

echo "OK test_telemetry_phase_enum.sh"
