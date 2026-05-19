#!/usr/bin/env bash
set -euo pipefail
export CLAUDE_PLUGIN_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
source "$CLAUDE_PLUGIN_ROOT/scripts/lib/state.sh"

SCHEMA="$CLAUDE_PLUGIN_ROOT/schemas/smoke_registry.schema.json"
tmpdir=$(mktemp -d)

cat > "$tmpdir/ok.json" <<'EOF'
{
  "repo": "apache/airflow",
  "generated_at": "2026-05-01T12:00:00Z",
  "layers": [
    {
      "name": "django_check",
      "cmd": "python manage.py check --fail-level WARNING",
      "cwd": ".",
      "timeout_s": 60
    },
    {
      "name": "pytest_smoke_dir",
      "cmd": "pytest tests/smoke -x --no-cov -q",
      "cwd": ".",
      "timeout_s": 60
    }
  ]
}
EOF
validate_json "$SCHEMA" "$tmpdir/ok.json" || { echo "FAIL valid"; exit 1; }

echo '{}' > "$tmpdir/bad.json"
validate_json "$SCHEMA" "$tmpdir/bad.json" 2>/dev/null && { echo "FAIL bad accepted"; exit 1; }

echo "OK test_schema_smoke_registry.sh"
