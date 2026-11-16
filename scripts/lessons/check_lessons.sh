#!/usr/bin/env bash
# check_lessons.sh --cards CARDS_JSON --context CTX_JSON [--enforce-min 0.75]
# Runs each DETERMINISTIC card's registry check against the diff context.
# stdout: {"violations":[{id,rule}],"advisories":[{id,rule}],"checked":N}
# exit 0 = no enforced rule violated; exit 1 = >=1 enforced rule violated.
# Enforced = status==active AND confidence>=enforce-min AND scope in {repo,global}.
# Semantic cards are ignored here (scorer LLM pass handles them).
set -euo pipefail
# Not exported by the harness (template variable only), so derive it from $0.
export CLAUDE_PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}"
source "${CLAUDE_PLUGIN_ROOT}/scripts/lib/state.sh"
source "${CLAUDE_PLUGIN_ROOT}/scripts/lib/lesson_checks.sh"

CARDS=""; CTX=""; EMIN="0.75"
while [ $# -gt 0 ]; do
  case "$1" in
    --cards)       CARDS="$2"; shift 2 ;;
    --context)     CTX="$2"; shift 2 ;;
    --enforce-min) EMIN="$2"; shift 2 ;;
    *) echo "check_lessons.sh: unknown arg: $1" >&2; exit 2 ;;
  esac
done
[ -n "$CTX" ] && [ -f "$CTX" ] || { echo "check_lessons.sh: --context FILE required" >&2; exit 2; }
printf '%s' "$EMIN" | grep -qE '^[0-9]+(\.[0-9]+)?$' || { echo "check_lessons.sh: --enforce-min must be numeric" >&2; exit 2; }
if [ -z "$CARDS" ] || [ ! -f "$CARDS" ]; then
  echo '{"violations":[],"advisories":[],"checked":0}'
  exit 0
fi

ctx_json=$(cat "$CTX")
violations="[]"; advisories="[]"; checked=0

while IFS= read -r card; do
  [ -n "$card" ] || continue
  kind=$(printf '%s' "$card" | jq -r '.kind')
  [ "$kind" = "deterministic" ] || continue
  cid=$(printf '%s' "$card" | jq -r '.check.id // ""')
  [ -n "$cid" ] || continue
  cargs=$(printf '%s' "$card" | jq -c '.check.args // {}')
  checked=$((checked + 1))
  if run_check "$cid" "$cargs" "$ctx_json"; then
    continue
  fi
  enforced=$(printf '%s' "$card" | jq -r --argjson emin "$EMIN" \
    '(.status == "active" and .confidence >= $emin and (.scope == "repo" or .scope == "global"))')
  entry=$(printf '%s' "$card" | jq -c '{id: .id, rule: .rule}')
  if [ "$enforced" = "true" ]; then
    violations=$(printf '%s' "$violations" | jq -c --argjson e "$entry" '. + [$e]')
  else
    advisories=$(printf '%s' "$advisories" | jq -c --argjson e "$entry" '. + [$e]')
  fi
done < <(jq -c '.[]' "$CARDS")

jq -nc --argjson v "$violations" --argjson a "$advisories" --argjson c "$checked" \
  '{violations: $v, advisories: $a, checked: $c}'

[ "$(printf '%s' "$violations" | jq 'length')" -eq 0 ] && exit 0 || exit 1
