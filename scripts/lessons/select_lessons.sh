#!/usr/bin/env bash
# select_lessons.sh --repo OWNER/REPO [--lang L] [--changed-files FILE]
#                   [--dimensions "d1,d2"] --store FILE [--store FILE ...] [--cap N]
# Emits a ranked, capped JSON array of rule cards matching the contribution.
# Filters: scope/repo, lang, dimensions (jq); path-glob (bash case, if
# --changed-files given). Ranking: enforced first, deterministic before
# semantic, then confidence descending. retired cards are never returned.
set -euo pipefail
# Not exported by the harness (template variable only), so derive it from $0.
export CLAUDE_PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}"
source "${CLAUDE_PLUGIN_ROOT}/scripts/lib/state.sh"

REPO=""; REPO_LANG=""; CHANGED=""; DIMS=""; CAP="40"; STORES=()
while [ $# -gt 0 ]; do
  case "$1" in
    --repo)          REPO="$2"; shift 2 ;;
    --lang)          REPO_LANG="$2"; shift 2 ;;
    --changed-files) CHANGED="$2"; shift 2 ;;
    --dimensions)    DIMS="$2"; shift 2 ;;
    --cap)           CAP="$2"; shift 2 ;;
    --store)         STORES+=("$2"); shift 2 ;;
    *) echo "select_lessons.sh: unknown arg: $1" >&2; exit 2 ;;
  esac
done
[ -n "$REPO" ] || { echo "--repo required" >&2; exit 2; }

EXIST=()
for s in "${STORES[@]:-}"; do
  [ -n "$s" ] && [ -f "$s" ] && EXIST+=("$s")
done
[ "${#EXIST[@]}" -eq 0 ] && { echo '[]'; exit 0; }

if [ -n "$DIMS" ]; then
  DIMS_JSON=$(printf '%s' "$DIMS" | jq -Rc 'split(",") | map(gsub("^\\s+|\\s+$"; ""))')
else
  DIMS_JSON='[]'
fi

# Stage 1 — scope/repo, lang, dimension filter; drop retired.
STAGE1=$(jq -s \
  --arg repo "$REPO" --arg lang "$REPO_LANG" --argjson dims "$DIMS_JSON" '
  map(select(
    (if .scope == "repo" then (.match.repo == $repo) else true end)
    and (if (.match.lang // null) == null or $lang == "" then true else .match.lang == $lang end)
    and (if (.match.dimensions // []) == [] or ($dims | length) == 0 then true
         else any(.match.dimensions[]; . as $d | $dims | index($d)) end)
    and (.status != "retired")
  ))
' "${EXIST[@]}" 2>/dev/null || echo '[]')

# Stage 2 — path-glob filter (only if changed files supplied).
if [ -n "$CHANGED" ] && [ -f "$CHANGED" ]; then
  CF=()
  while IFS= read -r line; do [ -n "$line" ] && CF+=("$line"); done < "$CHANGED"
  KEPT="[]"
  while IFS= read -r card; do
    [ -n "$card" ] || continue
    npaths=$(printf '%s' "$card" | jq -r '(.match.paths // []) | length')
    if [ "$npaths" -eq 0 ]; then
      KEPT=$(printf '%s' "$KEPT" | jq -c --argjson c "$card" '. + [$c]')
      continue
    fi
    matched=""
    while IFS= read -r g; do
      [ -n "$g" ] || continue
      for f in "${CF[@]:-}"; do
        case "$f" in
          $g) matched=1 ;;
        esac
        [ -n "$matched" ] && break
      done
      [ -n "$matched" ] && break
    done < <(printf '%s' "$card" | jq -r '.match.paths[]')
    [ -n "$matched" ] && KEPT=$(printf '%s' "$KEPT" | jq -c --argjson c "$card" '. + [$c]')
  done < <(printf '%s' "$STAGE1" | jq -c '.[]')
  STAGE1="$KEPT"
fi

# Stage 3 — rank (enforced / deterministic / confidence desc) and cap.
# 0.75 mirrors ENFORCE_MIN for ranking only; it does not gate here.
printf '%s' "$STAGE1" | jq -c --argjson cap "$CAP" '
  def enforced: (.status == "active" and .confidence >= 0.75 and (.scope == "repo" or .scope == "global"));
  sort_by([ (if enforced then 0 else 1 end),
            (if .kind == "deterministic" then 0 else 1 end),
            (- .confidence) ])
  | .[:$cap]
'
