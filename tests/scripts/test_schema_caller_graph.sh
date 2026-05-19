#!/usr/bin/env bash
set -euo pipefail
export CLAUDE_PLUGIN_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
source "$CLAUDE_PLUGIN_ROOT/scripts/lib/state.sh"
SCHEMA="$CLAUDE_PLUGIN_ROOT/schemas/caller_graph.schema.json"
tmpdir=$(mktemp -d)

cat > "$tmpdir/ok.json" <<'EOF'
{
  "repo": "apache/airflow",
  "issue_number": 65685,
  "generated_at": "2026-04-24T11:45:00Z",
  "target_function": "providers.fab.auth_manager.fab_auth_manager.FabAuthManager._get_auth_role_public",
  "callers": [
    {
      "location": "providers/fab/src/airflow/providers/fab/auth_manager/fab_auth_manager.py:412",
      "caller_function": "get_fastapi_middlewares",
      "execution_context": "fastapi_startup",
      "safe_under_refactor": false,
      "notes": "runs before Flask app context exists"
    }
  ],
  "contexts_found": ["flask_request", "fastapi_startup"]
}
EOF
validate_json "$SCHEMA" "$tmpdir/ok.json" || { echo "FAIL valid"; exit 1; }

echo '{}' > "$tmpdir/bad.json"
validate_json "$SCHEMA" "$tmpdir/bad.json" 2>/dev/null && { echo "FAIL bad accepted"; exit 1; }

echo "OK test_schema_caller_graph.sh"
