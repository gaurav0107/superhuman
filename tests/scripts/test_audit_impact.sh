#!/usr/bin/env bash
set -euo pipefail
export CLAUDE_PLUGIN_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
source "$CLAUDE_PLUGIN_ROOT/scripts/lib/state.sh"

SCRIPT="$CLAUDE_PLUGIN_ROOT/scripts/orchestrator/audit_impact.sh"
SCHEMA="$CLAUDE_PLUGIN_ROOT/schemas/caller_graph.schema.json"

# Create a synthetic git repo with a function defined and called from two files
tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

git -C "$tmpdir" -c user.email=t@t -c user.name=t init -q

mkdir -p "$tmpdir/views" "$tmpdir/tasks"

cat > "$tmpdir/lib.py" <<'PY'
def calc(x):
    return x * 2
PY

cat > "$tmpdir/views/users.py" <<'PY'
from .lib import calc

def get_user_total(x):
    result = calc(x)
    return result
PY

cat > "$tmpdir/tasks/worker.py" <<'PY'
from .lib import calc

def run_job(y):
    calc(y)
PY

git -C "$tmpdir" add -A
git -C "$tmpdir" -c user.email=t@t -c user.name=t commit -qm "init"

# Run the script
bash "$SCRIPT" \
  --repo a/a \
  --workdir "$tmpdir" \
  --target-function lib.calc \
  --refactor-kind blocking_network_call \
  --out "$tmpdir/audit.json"

# Assert output file was created
[ -f "$tmpdir/audit.json" ] || { echo "FAIL: audit.json not created"; exit 1; }

# Assert callers length >= 2
count=$(jq '.callers | length' "$tmpdir/audit.json")
[ "$count" -ge 2 ] || { echo "FAIL: expected >= 2 callers, got $count"; exit 1; }

# Assert target_function
jq -e '.target_function == "lib.calc"' "$tmpdir/audit.json" >/dev/null \
  || { echo "FAIL: target_function mismatch"; exit 1; }

# Assert verdict == "unknown"
jq -e '.verdict == "unknown"' "$tmpdir/audit.json" >/dev/null \
  || { echo "FAIL: verdict should be unknown"; exit 1; }

# Assert contexts_found is an array
jq -e '.contexts_found | type == "array"' "$tmpdir/audit.json" >/dev/null \
  || { echo "FAIL: contexts_found should be array"; exit 1; }

# Validate against schema
validate_json "$SCHEMA" "$tmpdir/audit.json" \
  || { echo "FAIL: schema validation failed"; exit 1; }

echo "OK test_audit_impact.sh"
