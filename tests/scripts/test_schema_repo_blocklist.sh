#!/usr/bin/env bash
set -euo pipefail
export CLAUDE_PLUGIN_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
source "$CLAUDE_PLUGIN_ROOT/scripts/lib/state.sh"

SCHEMA="$CLAUDE_PLUGIN_ROOT/schemas/repo_blocklist.schema.json"
tmpdir=$(mktemp -d)

cat > "$tmpdir/ok.json" <<'EOF'
{
  "version": 1,
  "blocked": [
    {
      "repo": "example-org/example-repo",
      "reason": "maintainer declined prior PR; do not retry",
      "added_at": "2026-05-02T00:00:00Z",
      "expires_at": null
    }
  ]
}
EOF
validate_json "$SCHEMA" "$tmpdir/ok.json" || { echo "FAIL valid"; exit 1; }

echo '{}' > "$tmpdir/bad.json"
validate_json "$SCHEMA" "$tmpdir/bad.json" 2>/dev/null && { echo "FAIL bad accepted"; exit 1; }

echo "OK test_schema_repo_blocklist.sh"
