#!/usr/bin/env bash
set -euo pipefail
export CLAUDE_PLUGIN_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
source "$CLAUDE_PLUGIN_ROOT/scripts/lib/state.sh"

SCHEMA="$CLAUDE_PLUGIN_ROOT/schemas/repo_profile.schema.json"
tmpdir=$(mktemp -d)

cat > "$tmpdir/ok.json" <<'EOF'
{
  "repo": "apache/airflow",
  "generated_at": "2026-04-24T11:45:00Z",
  "default_branch": "main",
  "language": "python",
  "commit_convention": "conventional",
  "pr_title_format": "component: short description",
  "pr_body_sections": ["Summary", "Test plan", "Checklist"],
  "test_runner": "pytest",
  "lint_commands": ["ruff check .", "mypy ."],
  "closes_syntax": "Closes #N",
  "dco_required": false,
  "cla_required": false,
  "reviewer_norms_summary": "x",
  "sampled_prs": [12345]
}
EOF
validate_json "$SCHEMA" "$tmpdir/ok.json" || { echo "FAIL valid"; exit 1; }

echo '{}' > "$tmpdir/bad.json"
validate_json "$SCHEMA" "$tmpdir/bad.json" 2>/dev/null && { echo "FAIL bad accepted"; exit 1; }

echo "OK test_schema_repo_profile.sh"
