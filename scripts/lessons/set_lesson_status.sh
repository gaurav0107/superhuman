#!/usr/bin/env bash
# set_lesson_status.sh --store FILE --card-id ID --status (active|demoted|retired)
#                      [--confidence C] [--reason TEXT] [--now ISO]
# Judgment-driven status transition for ONE rule card (sole caller: lesson-distiller).
# This is the ONLY sanctioned way to demote an enforced rule (active->demoted) or
# revive a demoted one (demoted->active). merge_cards.sh DELIBERATELY refuses to let
# a merged candidate flip .status (a safety property: a crafted review comment must
# not be able to flip an enforced rule by re-merging it), so contradiction-demotion
# and demoted->active re-confirmation route through this dedicated, auditable script
# instead. Matches the card by exact .id, optionally overrides confidence, appends
# --reason to evidence, refreshes last_confirmed, and rewrites the store atomically.
# Aborts (exit 1) if the card is absent or the store has a malformed line — the
# distiller only calls this after reading the target card, so absence is a real bug.
# VERIFY UNDER bash, NOT zsh (bash 3.2 is authoritative for scripts).
set -euo pipefail
# Not exported by the harness (template variable only), so derive it from $0.
export CLAUDE_PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(CDPATH= cd "$(dirname "$0")/../.." && pwd)}"
source "${CLAUDE_PLUGIN_ROOT}/scripts/lib/state.sh"

STORE=""; CARD_ID=""; STATUS=""; CONF=""; REASON=""; NOW=""
while [ $# -gt 0 ]; do
  case "$1" in
    --store)      STORE="$2"; shift 2 ;;
    --card-id)    CARD_ID="$2"; shift 2 ;;
    --status)     STATUS="$2"; shift 2 ;;
    --confidence) CONF="$2"; shift 2 ;;
    --reason)     REASON="$2"; shift 2 ;;
    --now)        NOW="$2"; shift 2 ;;
    *) echo "set_lesson_status.sh: unknown arg: $1" >&2; exit 2 ;;
  esac
done
[ -n "$STORE" ]   || { echo "--store required" >&2; exit 2; }
[ -n "$CARD_ID" ] || { echo "--card-id required" >&2; exit 2; }
case "$STATUS" in
  active|demoted|retired) : ;;
  *) echo "set_lesson_status.sh: --status must be active|demoted|retired" >&2; exit 2 ;;
esac
[ -f "$STORE" ] || { echo "set_lesson_status.sh: store not found: $STORE" >&2; exit 1; }
[ -n "$NOW" ] || NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)
# optional confidence must be a number in [0,1] if provided
if [ -n "$CONF" ]; then
  printf '%s' "$CONF" | grep -qE '^(0(\.[0-9]+)?|1(\.0+)?)$' \
    || { echo "set_lesson_status.sh: --confidence must be a number in [0,1]" >&2; exit 2; }
fi

found=""; tmpf="${STORE}.tmp.$$"; : > "$tmpf"
trap 'rm -f "$tmpf"' EXIT
# `|| [ -n "$line" ]` processes a final line with no trailing newline; without it
# read returns 1 at EOF on a partial line and that card is silently dropped.
while IFS= read -r line || [ -n "$line" ]; do
  [ -n "$line" ] || continue
  printf '%s' "$line" | jq -e . >/dev/null 2>&1 \
    || { echo "set_lesson_status.sh: malformed line in store $STORE" >&2; exit 1; }
  if [ -z "$found" ] && [ "$(printf '%s' "$line" | jq -r '.id // ""')" = "$CARD_ID" ]; then
    line=$(printf '%s' "$line" | jq -c \
      --arg status "$STATUS" --arg now "$NOW" --arg reason "$REASON" --arg conf "$CONF" '
      .status = $status
      | .last_confirmed = $now
      | (if $conf   != "" then .confidence = ($conf | tonumber)                 else . end)
      | (if $reason != "" then .evidence   = (((.evidence // []) + [$reason]) | unique) else . end)')
    found=1
  fi
  printf '%s\n' "$line" >> "$tmpf"
done < "$STORE"

[ -n "$found" ] || { echo "set_lesson_status.sh: no card with id=$CARD_ID in $STORE" >&2; exit 1; }
mv "$tmpf" "$STORE"
