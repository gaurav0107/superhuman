#!/usr/bin/env bash
set -euo pipefail
export CLAUDE_PLUGIN_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
source "$CLAUDE_PLUGIN_ROOT/scripts/lib/state.sh"
SCHEMA="$CLAUDE_PLUGIN_ROOT/schemas/current_contribution.schema.json"
tmpdir=$(mktemp -d)

# notes = string
cat > "$tmpdir/a.json" <<'EOF'
{
  "repo": "apache/airflow",
  "issue_number": 65685,
  "branch": "fix/65685",
  "iteration": 1,
  "max_iterations": 6,
  "score_threshold": 95,
  "scores": [
    {"iteration": 1, "ts": "2026-04-24T11:15:00Z",
     "dimensions": {"correctness": 7},
     "raw": 78, "final": 72, "plateaued": [], "caps_applied": [],
     "notes": "weakest dim: tests"}
  ],
  "lock_holder": "opensource-contributor",
  "started_at": "2026-04-24T11:00:00Z",
  "pr_url": null
}
EOF
validate_json "$SCHEMA" "$tmpdir/a.json" || { echo "FAIL string notes"; exit 1; }

# notes = object
jq '.scores[0].notes = {"reason": "weak", "dim": "tests"}' "$tmpdir/a.json" > "$tmpdir/b.json"
validate_json "$SCHEMA" "$tmpdir/b.json" || { echo "FAIL object notes"; exit 1; }

echo "OK test_schema_current_contribution.sh"
