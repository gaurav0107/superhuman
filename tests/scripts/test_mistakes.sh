# tests/scripts/test_mistakes.sh
#!/usr/bin/env bash
set -euo pipefail
export CLAUDE_PLUGIN_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
source "$CLAUDE_PLUGIN_ROOT/scripts/lib/mistakes.sh"

tmpdir=$(mktemp -d)
SD="$tmpdir/state"
WD="$tmpdir/work"
OR="apache/airflow"
mkdir -p "$SD" "$WD"

record_mistake "$SD" "$WD" "$OR" "builder:ci_gate" "ruff failed on tests/foo.py"
[ -f "$SD/mistakes.md" ] || { echo "FAIL: file not created"; exit 1; }

grep -q "^## " "$SD/mistakes.md"                || { echo "FAIL: missing H2"; exit 1; }
grep -q "tag=builder:ci_gate" "$SD/mistakes.md" || { echo "FAIL: missing tag"; exit 1; }
grep -q "repo=apache/airflow" "$SD/mistakes.md" || { echo "FAIL: missing repo"; exit 1; }
grep -q "ruff failed" "$SD/mistakes.md"         || { echo "FAIL: missing body"; exit 1; }

record_mistake "$SD" "$WD" "$OR" "builder:smoke" "import error"
[ "$(grep -c '^## ' "$SD/mistakes.md")" = "2" ] || { echo "FAIL: not append-only"; exit 1; }

echo "OK test_mistakes.sh"
