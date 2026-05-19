# tests/scripts/test_regen_cooldown.sh
#!/usr/bin/env bash
set -euo pipefail
export CLAUDE_PLUGIN_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

tmpdir=$(mktemp -d)
GD="$tmpdir/.superhuman/global"
mkdir -p "$GD"
LOG="$GD/merge_outcomes.jsonl"

# Repo A: 2 negatives, 0 merged in 180d → 90d cooldown
# Repo B: 1 suspicious_halt → 180d cooldown
# Repo C: 1 merged → no cooldown
NOW="2026-05-18T00:00:00Z"
cat > "$LOG" <<'EOF'
{"repo":"a/a","outcome":"closed_no_merge","closed_at":"2026-04-01T00:00:00Z"}
{"repo":"a/a","outcome":"abandoned","closed_at":"2026-05-01T00:00:00Z"}
{"repo":"b/b","outcome":"suspicious_halt","closed_at":"2026-05-10T00:00:00Z"}
{"repo":"c/c","outcome":"merged","closed_at":"2026-05-01T00:00:00Z"}
{"repo":"c/c","outcome":"closed_no_merge","closed_at":"2026-04-01T00:00:00Z"}
EOF

HOME="$tmpdir" bash "$CLAUDE_PLUGIN_ROOT/scripts/scorer/regen_cooldown.sh" --now "$NOW"

CD="$GD/repo_cooldown.json"
[ -f "$CD" ] || { echo "FAIL: no cooldown file"; exit 1; }
jq -e '.cooldowns | map(.repo) | index("a/a")' "$CD" >/dev/null || { echo "FAIL: a/a missing"; exit 1; }
jq -e '.cooldowns | map(.repo) | index("b/b")' "$CD" >/dev/null || { echo "FAIL: b/b missing"; exit 1; }
jq -e '.cooldowns | map(.repo) | index("c/c") == null' "$CD" >/dev/null || { echo "FAIL: c/c should not be cooled"; exit 1; }

echo "OK test_regen_cooldown.sh"
