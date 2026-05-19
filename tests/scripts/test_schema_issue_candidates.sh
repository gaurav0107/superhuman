#!/usr/bin/env bash
set -euo pipefail
export CLAUDE_PLUGIN_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
source "$CLAUDE_PLUGIN_ROOT/scripts/lib/state.sh"
SCHEMA="$CLAUDE_PLUGIN_ROOT/schemas/issue_candidates.schema.json"
tmpdir=$(mktemp -d)
cat > "$tmpdir/ok.json" <<'EOF'
{
  "repo": "apache/airflow",
  "generated_at": "2026-04-24T11:45:00Z",
  "candidates": [
    {"number": 65685, "title": "x", "score": 23, "type": "bug", "labels": ["bug"], "skip_reason": null, "notes": "..."}
  ],
  "skipped": [{"number": 65123, "reason": "docs-only"}]
}
EOF
validate_json "$SCHEMA" "$tmpdir/ok.json" || { echo "FAIL"; exit 1; }
echo "OK test_schema_issue_candidates.sh"
