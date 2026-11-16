#!/usr/bin/env bash
# decay_lessons.sh --store FILE [--now ISO] [--retire-max 0.25] [--decay-days 180] [--decay-step 0.1]
# Age-based decay (sole caller: lesson-distiller). A card not confirmed within
# decay-days loses decay-step confidence (floored at 0); a card whose confidence
# falls below retire-max, or whose age exceeds 2*decay-days, is retired. Cards
# with no last_confirmed are left untouched. Rewrites the store.
set -euo pipefail
# Not exported by the harness (template variable only), so derive it from $0.
export CLAUDE_PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(CDPATH= cd "$(dirname "$0")/../.." && pwd)}"
source "${CLAUDE_PLUGIN_ROOT}/scripts/lib/state.sh"

STORE=""; NOW=""; RETIRE="0.25"; DAYS="180"; STEP="0.1"
while [ $# -gt 0 ]; do
  case "$1" in
    --store)      STORE="$2"; shift 2 ;;
    --now)        NOW="$2"; shift 2 ;;
    --retire-max) RETIRE="$2"; shift 2 ;;
    --decay-days) DAYS="$2"; shift 2 ;;
    --decay-step) STEP="$2"; shift 2 ;;
    *) echo "decay_lessons.sh: unknown arg: $1" >&2; exit 2 ;;
  esac
done
[ -n "$STORE" ] || { echo "--store required" >&2; exit 2; }
[ -f "$STORE" ] || exit 0     # nothing to decay
[ -n "$NOW" ] || NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)

# integer days between an ISO timestamp ($1) and NOW; 0 on parse failure.
age_days() {
  python3 - "$NOW" "$1" <<'PY'
import sys, datetime
def parse(s): return datetime.datetime.fromisoformat(s.replace('Z', '+00:00'))
try:
    print(max(0, (parse(sys.argv[1]) - parse(sys.argv[2])).days))
except Exception:
    print(0)
PY
}

tmpf="${STORE}.tmp.$$"; : > "$tmpf"
trap 'rm -f "$tmpf"' EXIT
while IFS= read -r card || [ -n "$card" ]; do
  [ -n "$card" ] || continue
  lc=$(printf '%s' "$card" | jq -r '.last_confirmed // ""')
  if [ -z "$lc" ]; then
    printf '%s\n' "$card" >> "$tmpf"
    continue
  fi
  age=$(age_days "$lc")
  printf '%s\n' "$(printf '%s' "$card" | jq -c \
    --argjson age "$age" --argjson days "$DAYS" --argjson step "$STEP" --argjson retire "$RETIRE" '
    (if $age > $days then .confidence = ([ (.confidence - $step), 0 ] | max) else . end)
    | (if (.confidence < $retire or $age > ($days * 2)) then .status = "retired" else . end)')" >> "$tmpf"
done < "$STORE"
mv "$tmpf" "$STORE"
