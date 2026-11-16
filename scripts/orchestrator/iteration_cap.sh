#!/usr/bin/env bash
# iteration_cap.sh --loc N
# Emits the iteration cap (3/6/10) for the given LOC delta.
set -euo pipefail
# Not exported by the harness (template variable only), so derive it from $0.
export CLAUDE_PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(CDPATH= cd "$(dirname "$0")/../.." && pwd)}"

LOC=""
while [ $# -gt 0 ]; do
  case "$1" in
    --loc) LOC="$2"; shift 2 ;;
    *) echo "iteration_cap.sh: unknown arg: $1" >&2; exit 2 ;;
  esac
done
[ -z "$LOC" ] && { echo "--loc required" >&2; exit 2; }

if   [ "$LOC" -le 50 ];  then echo 3
elif [ "$LOC" -le 200 ]; then echo 6
else echo 10
fi
