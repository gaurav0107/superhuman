#!/usr/bin/env bash
# compute_score.sh --dimensions <JSON> --caps-applied <JSON-array> --plateaued <JSON-array>
# Emits {raw, final, weighted_breakdown} on stdout.
# Cap RULES and TRIGGERS live in merge-probability-scorer.md prompt; this
# script only applies arithmetic when the prompt has decided a cap fires.
set -euo pipefail
# Not exported by the harness (template variable only), so derive it from $0.
export CLAUDE_PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(CDPATH= cd "$(dirname "$0")/../.." && pwd)}"

DIMS=""
CAPS="[]"
PLATEAUED="[]"

while [ $# -gt 0 ]; do
  case "$1" in
    --dimensions)    DIMS="$2"; shift 2 ;;
    --caps-applied)  CAPS="$2"; shift 2 ;;
    --plateaued)     PLATEAUED="$2"; shift 2 ;;
    *) echo "compute_score.sh: unknown arg: $1" >&2; exit 2 ;;
  esac
done

[ -z "$DIMS" ] && { echo "compute_score.sh: --dimensions required" >&2; exit 2; }

# Authoritative weights (sum to 100) — KEEP IN SYNC with merge-probability-scorer.md.
read -r raw final breakdown <<< "$(jq -nr \
  --argjson dims "$DIMS" \
  --argjson caps "$CAPS" \
  '
  def w: {correctness:22, test_coverage:18, historical:10,
          style:9, pr_format:9, process:9, scope:9,
          docs:5, commit:5, risk:4};
  def cap_for(applied):
    if (applied | index("process"))    then 50
    elif (applied | index("ci_health")) then 40
    else 100 end;
  ($dims | to_entries | map(.value * (w[.key] // 0) / 10) | add) as $raw
  | (if $raw > cap_for($caps) then cap_for($caps) else $raw end) as $final
  | "\($raw) \($final) \($dims)"
  ')"

jq -nc \
  --argjson raw "$raw" \
  --argjson final "$final" \
  --argjson dims "$DIMS" \
  --argjson caps "$CAPS" \
  --argjson plateaued "$PLATEAUED" \
  '{raw:$raw, final:$final, dimensions:$dims, caps_applied:$caps, plateaued:$plateaued}'
