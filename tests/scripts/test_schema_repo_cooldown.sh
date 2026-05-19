#!/usr/bin/env bash
set -euo pipefail
export CLAUDE_PLUGIN_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
source "$CLAUDE_PLUGIN_ROOT/scripts/lib/state.sh"

SCHEMA="$CLAUDE_PLUGIN_ROOT/schemas/repo_cooldown.schema.json"
tmpdir=$(mktemp -d)

cat > "$tmpdir/ok.json" <<'EOF'
{
  "version": 1,
  "generated_at": "2026-05-02T00:00:00Z",
  "cooldowns": [
    {
      "repo": "example-org/example-repo",
      "negative_outcomes_180d": 2,
      "last_merged_at": null,
      "cooldown_until": "2026-08-02T00:00:00Z",
      "triggering_outcomes": ["closed_no_merge", "abandoned"]
    }
  ]
}
EOF
validate_json "$SCHEMA" "$tmpdir/ok.json" || { echo "FAIL valid"; exit 1; }

echo '{}' > "$tmpdir/bad.json"
validate_json "$SCHEMA" "$tmpdir/bad.json" 2>/dev/null && { echo "FAIL bad accepted"; exit 1; }

echo "OK test_schema_repo_cooldown.sh"
