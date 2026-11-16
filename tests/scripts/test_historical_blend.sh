# tests/scripts/test_historical_blend.sh
#!/usr/bin/env bash
set -euo pipefail
export CLAUDE_PLUGIN_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

tmpdir=$(mktemp -d)
GD="$tmpdir/global"
mkdir -p "$GD"
cat > "$GD/merge_outcomes.jsonl" <<'EOF'
{"repo":"apache/airflow","outcome":"merged","closed_at":"2026-04-01T00:00:00Z"}
{"repo":"apache/airflow","outcome":"merged","closed_at":"2026-04-15T00:00:00Z"}
{"repo":"apache/airflow","outcome":"closed_no_merge","closed_at":"2026-05-01T00:00:00Z"}
EOF

out=$(bash "$CLAUDE_PLUGIN_ROOT/scripts/scorer/historical_blend.sh" \
        --rubric-01 0.72 \
        --merge-log "$GD/merge_outcomes.jsonl" \
        --repo apache/airflow \
        --weight 0.3)

# 2/3 merged + Laplace smoothing → est ~0.6, blend = 0.7 * 0.72 + 0.3 * ~0.6 ≈ 0.684
final=$(echo "$out" | jq -r .blended)
# Must be a finite number 0..10
echo "$out" | jq -e '.blended | type == "number"' >/dev/null || { echo "FAIL not number"; exit 1; }
awk -v v="$final" 'BEGIN{ if (v<0||v>10) exit 1; }' || { echo "FAIL out of range: $final"; exit 1; }

# Each PR counts once by its latest row, and run-exit reasons stay out:
# pull/1 plateau then merged, pull/2 plateau (still open), plus a no-PR row
# -> 1 merged of 1 concluded -> estimate (1+1)/(1+2).
cat > "$GD/merge_outcomes.jsonl" <<'EOF'
{"repo":"x/y","pr_url":"https://github.com/x/y/pull/1","outcome":"plateau","ts":"2026-04-01T00:00:00Z"}
{"repo":"x/y","pr_url":"https://github.com/x/y/pull/2","outcome":"plateau","ts":"2026-04-02T00:00:00Z"}
{"repo":"x/y","outcome":"no_eligible_issue","ts":"2026-04-03T00:00:00Z"}
{"repo":"x/y","pr_url":"https://github.com/x/y/pull/1","outcome":"merged","closed_at":"2026-05-01T00:00:00Z"}
EOF
est=$(bash "$CLAUDE_PLUGIN_ROOT/scripts/scorer/historical_blend.sh" --rubric-01 0.5 \
        --merge-log "$GD/merge_outcomes.jsonl" --repo x/y --weight 0.3 | jq -r .merge_estimate_01)
[ "$est" = "0.6667" ] || { echo "FAIL dedupe estimate: $est (want 0.6667)"; exit 1; }

echo "OK test_historical_blend.sh"
