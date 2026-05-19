#!/usr/bin/env bash
set -euo pipefail
export CLAUDE_PLUGIN_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
source "$CLAUDE_PLUGIN_ROOT/scripts/lib/state.sh"
SCHEMA="$CLAUDE_PLUGIN_ROOT/schemas/ci_commands.schema.json"
tmpdir=$(mktemp -d)

cat > "$tmpdir/ok.json" <<'EOF'
{
  "repo": "apache/airflow",
  "generated_at": "2026-04-24T11:45:00Z",
  "workflows_scanned": [".github/workflows/ci.yml"],
  "local_runnable": [
    {"name": "lint", "cmd": "ruff check .", "timeout_s": 60, "allowlisted": true},
    {"name": "unit", "cmd": "pytest tests/unit", "timeout_s": 300, "allowlisted": true}
  ],
  "not_local_runnable": [
    {"name": "docker-e2e", "reason": "requires docker-compose with secrets"},
    {"name": "deploy", "reason": "denylist pattern: curl detected"}
  ]
}
EOF
validate_json "$SCHEMA" "$tmpdir/ok.json" || { echo "FAIL valid"; exit 1; }

echo '{}' > "$tmpdir/bad.json"
validate_json "$SCHEMA" "$tmpdir/bad.json" 2>/dev/null && { echo "FAIL bad accepted"; exit 1; }

echo "OK test_schema_ci_commands.sh"
