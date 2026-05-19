#!/usr/bin/env bash
set -euo pipefail
export CLAUDE_PLUGIN_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
source "$CLAUDE_PLUGIN_ROOT/scripts/lib/state.sh"

out=$(state_dir "apache/airflow")
[ "$out" = "$HOME/.superhuman/repos/apache-airflow" ] || { echo "FAIL state_dir: $out"; exit 1; }

[ "$(global_dir)" = "$HOME/.superhuman/global" ] || { echo "FAIL global_dir"; exit 1; }

tmpdir=$(mktemp -d)
atomic_write_json "$tmpdir/x.json" '{"a":1}'
[ "$(jq -r .a "$tmpdir/x.json")" = "1" ] || { echo "FAIL atomic_write_json"; exit 1; }

mkdir -p "$tmpdir/.superhuman/repos/foo-bar"
echo '{"lock_holder":"x"}' > "$tmpdir/.superhuman/repos/foo-bar/current_contribution.json"
HOME="$tmpdir" require_lock "foo/bar" "x" || { echo "FAIL require_lock match"; exit 1; }
HOME="$tmpdir" require_lock "foo/bar" "y" 2>/dev/null && { echo "FAIL require_lock mismatch should fail"; exit 1; }

schema="$tmpdir/s.json"
echo '{"$schema":"https://json-schema.org/draft/2020-12/schema","type":"object","required":["a"]}' > "$schema"
echo '{"a":1}' > "$tmpdir/data.json"
validate_json "$schema" "$tmpdir/data.json" || { echo "FAIL validate_json ok"; exit 1; }
echo '{}' > "$tmpdir/data.json"
validate_json "$schema" "$tmpdir/data.json" 2>/dev/null && { echo "FAIL validate_json bad should fail"; exit 1; }

echo "OK test_state.sh"
