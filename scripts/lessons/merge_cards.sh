#!/usr/bin/env bash
# merge_cards.sh --store STORE_JSONL --card-file CARD_JSON [--now ISO] [--birth 0.5] [--confirm-step 0.15]
# Dedupe-merge one candidate rule card into a JSONL store (sole caller: lesson-distiller).
# Same card_key -> bump hits, raise confidence (cap 1.0), refresh last_confirmed,
# union evidence/repos_seen, revive if retired. New key -> append with birth defaults.
# SAFETY: a deterministic card whose check.id is not in the fixed registry is forced
# to kind=semantic (its check is dropped) so it can execute nothing. Rewrites the store.
set -euo pipefail
# Not exported by the harness (template variable only), so derive it from $0.
export CLAUDE_PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(CDPATH= cd "$(dirname "$0")/../.." && pwd)}"
source "${CLAUDE_PLUGIN_ROOT}/scripts/lib/state.sh"
source "${CLAUDE_PLUGIN_ROOT}/scripts/lib/lesson_checks.sh"

STORE=""; CARD_FILE=""; NOW=""; BIRTH="0.5"; STEP="0.15"
while [ $# -gt 0 ]; do
  case "$1" in
    --store)        STORE="$2"; shift 2 ;;
    --card-file)    CARD_FILE="$2"; shift 2 ;;
    --now)          NOW="$2"; shift 2 ;;
    --birth)        BIRTH="$2"; shift 2 ;;
    --confirm-step) STEP="$2"; shift 2 ;;
    *) echo "merge_cards.sh: unknown arg: $1" >&2; exit 2 ;;
  esac
done
[ -n "$STORE" ] || { echo "--store required" >&2; exit 2; }
[ -n "$CARD_FILE" ] && [ -f "$CARD_FILE" ] || { echo "--card-file FILE required" >&2; exit 2; }
[ -n "$NOW" ] || NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)

card=$(cat "$CARD_FILE")

# SAFETY: force semantic if a deterministic card names an unknown check.
cid=$(printf '%s' "$card" | jq -r 'if .kind == "deterministic" then (.check.id // "") else "" end')
if [ -n "$cid" ] && ! is_known_check "$cid"; then
  card=$(printf '%s' "$card" | jq -c '.kind = "semantic" | del(.check)')
fi
newkey=$(card_key "$card")

mkdir -p "$(dirname "$STORE")"
[ -f "$STORE" ] || : > "$STORE"

merged=""; tmpf="${STORE}.tmp.$$"; : > "$tmpf"
trap 'rm -f "$tmpf"' EXIT
# `|| [ -n "$line" ]` processes a final line with no trailing newline (a store an
# external/manual editor may produce) — without it, read returns 1 at EOF on the
# partial line and the loop drops that card.
while IFS= read -r line || [ -n "$line" ]; do
  [ -n "$line" ] || continue
  printf '%s' "$line" | jq -e . >/dev/null 2>&1 || { echo "merge_cards.sh: malformed line in store $STORE" >&2; exit 1; }
  if [ -z "$merged" ] && [ "$(card_key "$line")" = "$newkey" ]; then
    line=$(jq -nc --argjson old "$line" --argjson new "$card" --arg now "$NOW" --argjson step "$STEP" '
      $old
      | .hits          = ((.hits // 0) + 1)
      | .confidence    = ([ (.confidence // 0) + $step, 1 ] | min)
      | .last_confirmed = $now
      | .status        = (if .status == "retired" then "active" else .status end)
      | .evidence      = (((.evidence // []) + ($new.evidence // [])) | unique)
      | .repos_seen    = (((.repos_seen // []) + ($new.repos_seen // [])) | unique)')
    merged=1
  fi
  printf '%s\n' "$line" >> "$tmpf"
done < "$STORE"

if [ -z "$merged" ]; then
  printf '%s\n' "$(printf '%s' "$card" | jq -c --arg now "$NOW" --argjson birth "$BIRTH" '
    .confidence     = (.confidence // $birth)
    | .hits         = (.hits // 1)
    | .status       = (.status // "active")
    | .created      = (.created // $now)
    | .last_confirmed = (.last_confirmed // $now)
    | .repos_seen   = (if (.repos_seen // []) == []
                       then (if (.match.repo // "") == "" then [] else [.match.repo] end)
                       else .repos_seen end)
    | .evidence     = (.evidence // [])')" >> "$tmpf"
fi

mv "$tmpf" "$STORE"
