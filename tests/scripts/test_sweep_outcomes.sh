#!/usr/bin/env bash
set -euo pipefail
export CLAUDE_PLUGIN_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SWEEP="$CLAUDE_PLUGIN_ROOT/scripts/orchestrator/sweep_outcomes.sh"

tmpdir=$(mktemp -d)
GD="$tmpdir/.superhuman/global"
mkdir -p "$GD" "$tmpdir/bin" "$tmpdir/prs"
LOG="$GD/merge_outcomes.jsonl"

# Fake gh: `gh pr view <url> --json ...` prints prs/<number>.json, fails if absent.
cat > "$tmpdir/bin/gh" <<EOF
#!/usr/bin/env bash
f="$tmpdir/prs/\${3##*/}.json"
[ -f "\$f" ] && cat "\$f"
EOF
chmod +x "$tmpdir/bin/gh"
export PATH="$tmpdir/bin:$PATH"

echo '{"state":"MERGED","mergedAt":"2026-06-01T00:00:00Z","closedAt":"2026-06-01T00:00:00Z"}' > "$tmpdir/prs/1.json"
echo '{"state":"CLOSED","mergedAt":null,"closedAt":"2026-06-02T00:00:00Z"}'                    > "$tmpdir/prs/2.json"
echo '{"state":"OPEN","reviewDecision":"CHANGES_REQUESTED","mergeStateStatus":"CLEAN","statusCheckRollup":[{"conclusion":"FAILURE"}]}' > "$tmpdir/prs/3.json"
echo '{"state":"OPEN","reviewDecision":"REVIEW_REQUIRED","mergeStateStatus":"CLEAN","statusCheckRollup":[]}' > "$tmpdir/prs/4.json"
echo '{"state":"OPEN","reviewDecision":"","mergeStateStatus":"CLEAN","statusCheckRollup":[{"conclusion":"TIMED_OUT"}]}' > "$tmpdir/prs/7.json"
# prs/5.json missing -> gh fails -> skipped, retried later. pull/6 already final.
cat > "$LOG" <<'EOF'
{"repo":"a/a","pr_url":"https://github.com/a/a/pull/1","outcome":"merge_ready","iterations":3,"closed_at":"2026-05-01T00:00:00Z"}
{"repo":"a/a","pr_url":"https://github.com/a/a/pull/2","outcome":"plateau","ts":"2026-05-01T00:00:00Z"}
{"repo":"a/a","pr_url":"https://github.com/a/a/pull/3","outcome":"plateau","closed_at":"2026-05-01T00:00:00Z"}
{"repo":"a/a","pr_url":"https://github.com/a/a/pull/4","outcome":"plateau","closed_at":"2026-05-01T00:00:00Z"}
{"repo":"a/a","pr_url":"https://github.com/a/a/pull/5","outcome":"plateau","closed_at":"2026-05-01T00:00:00Z"}
{"repo":"a/a","pr_url":"https://github.com/a/a/pull/7","outcome":"plateau","closed_at":"2026-05-01T00:00:00Z"}
{"repo":"a/a","pr_url":"https://github.com/a/a/pull/6","outcome":"merged","closed_at":"2026-05-01T00:00:00Z"}
{"repo":"a/a","outcome":"no_eligible_issue","ts":"2026-05-01T00:00:00Z"}
EOF

out=$(HOME="$tmpdir" bash "$SWEEP" 2>&1)
echo "$out" | grep -q "recorded=2 open=3 unreadable=1" || { echo "FAIL counts:"; echo "$out"; exit 1; }
echo "$out" | grep -q "NEEDS YOU: https://github.com/a/a/pull/3 — changes requested, CI failing" \
  || { echo "FAIL needs-you line:"; echo "$out"; exit 1; }
echo "$out" | grep -q "NEEDS YOU: https://github.com/a/a/pull/7 — CI failing" \
  || { echo "FAIL timed-out check not reported:"; echo "$out"; exit 1; }
echo "$out" | grep -q "pull/4" && { echo "FAIL quiet open PR should not be reported"; exit 1; }

jq -se 'map(select(.pr_url == "https://github.com/a/a/pull/1")) | last
        | .outcome == "merged" and .closed_at == "2026-06-01T00:00:00Z" and .iterations == 3' "$LOG" >/dev/null \
  || { echo "FAIL pull/1 not recorded merged"; exit 1; }
jq -se 'map(select(.pr_url == "https://github.com/a/a/pull/2")) | last | .outcome == "closed_no_merge"' "$LOG" >/dev/null \
  || { echo "FAIL pull/2 not recorded closed"; exit 1; }
[ -f "$GD/repo_cooldown.json" ] || { echo "FAIL cooldowns not regenerated"; exit 1; }

# Idempotent: second sweep records nothing new.
out=$(HOME="$tmpdir" bash "$SWEEP" 2>&1)
echo "$out" | grep -q "recorded=0" || { echo "FAIL not idempotent:"; echo "$out"; exit 1; }

echo "OK test_sweep_outcomes.sh"
