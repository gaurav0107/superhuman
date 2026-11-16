#!/usr/bin/env bash
# append_score.sh --repo OWNER/REPO --score JSON_BLOB
# Atomically appends score to current_contribution.json scores[].
set -euo pipefail
# Not exported by the harness (template variable only), so derive it from $0.
export CLAUDE_PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}"
source "${CLAUDE_PLUGIN_ROOT}/scripts/lib/state.sh"

REPO=""
SCORE=""

while [ $# -gt 0 ]; do
  case "$1" in
    --repo)  REPO="$2"; shift 2 ;;
    --score) SCORE="$2"; shift 2 ;;
    *) echo "append_score.sh: unknown arg: $1" >&2; exit 2 ;;
  esac
done

[ -z "$REPO" ] && { echo "--repo required" >&2; exit 2; }
[ -z "$SCORE" ] && { echo "--score required" >&2; exit 2; }

dir=$(state_dir "$REPO")
file="$dir/current_contribution.json"
[ -f "$file" ] || { echo "no current_contribution.json at $file" >&2; exit 2; }

new=$(jq --argjson s "$SCORE" '.scores += [$s]' "$file")
atomic_write_json "$file" "$new"
