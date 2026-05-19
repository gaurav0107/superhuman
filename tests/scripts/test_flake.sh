# tests/scripts/test_flake.sh
#!/usr/bin/env bash
set -euo pipefail
export CLAUDE_PLUGIN_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
source "$CLAUDE_PLUGIN_ROOT/scripts/lib/flake.sh"

tmpdir=$(mktemp -d)
GD="$tmpdir/global"
mkdir -p "$GD"
cat > "$GD/flake_signatures.md" <<'EOF'
## signature: pip-timeout
- pattern: `ReadTimeoutError.*files\.pythonhosted\.org`
- repos: *
- first_seen: 2026-03-01
- note: mirror flakiness; not a real failure
EOF

logfile="$tmpdir/ci.log"
echo "ReadTimeoutError: HTTPSConnectionPool(host='files.pythonhosted.org')" > "$logfile"
classify_as_flake "$GD/flake_signatures.md" "$logfile" || { echo "FAIL: should be flake"; exit 1; }

echo "no flaky thing" > "$logfile"
if classify_as_flake "$GD/flake_signatures.md" "$logfile" 2>/dev/null; then
  echo "FAIL: should NOT classify"; exit 1
fi

record_flake_hit "$GD/flake_signatures.md" "pip-timeout" "apache/airflow" "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
grep -q '^- last_hit:' "$GD/flake_signatures.md" || { echo "FAIL: hit not recorded"; exit 1; }

echo "OK test_flake.sh"
