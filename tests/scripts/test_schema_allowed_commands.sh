#!/usr/bin/env bash
set -euo pipefail
export CLAUDE_PLUGIN_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
source "$CLAUDE_PLUGIN_ROOT/scripts/lib/state.sh"
SCHEMA="$CLAUDE_PLUGIN_ROOT/schemas/allowed_commands.schema.json"
tmpdir=$(mktemp -d)

cat > "$tmpdir/ok.json" <<'EOF'
{
  "allowed_binaries": [
    "pytest", "ruff", "mypy", "black", "flake8",
    "npm", "npx", "pnpm", "yarn", "jest", "vitest",
    "go", "cargo", "make", "bundle", "rake",
    "git", "gh", "python", "node", "bun"
  ],
  "denied_patterns": [
    "curl", "wget", ";", "|", "`", "$(", "&&",
    "rm -rf", "sudo", "chmod 777", "PATH=", "LD_"
  ]
}
EOF
validate_json "$SCHEMA" "$tmpdir/ok.json" || { echo "FAIL valid"; exit 1; }

echo '{}' > "$tmpdir/bad.json"
validate_json "$SCHEMA" "$tmpdir/bad.json" 2>/dev/null && { echo "FAIL bad accepted"; exit 1; }

echo "OK test_schema_allowed_commands.sh"
