#!/usr/bin/env bash
# push_force_with_lease.sh --branch B [--remote R]
# Hard refusal if --remote is "upstream". Always uses --force-with-lease.
set -euo pipefail
: "${CLAUDE_PLUGIN_ROOT:?CLAUDE_PLUGIN_ROOT must be set}"

BRANCH=""; REMOTE="origin"
while [ $# -gt 0 ]; do
  case "$1" in
    --branch) BRANCH="$2"; shift 2 ;;
    --remote) REMOTE="$2"; shift 2 ;;
    *) echo "push_force_with_lease.sh: unknown arg: $1" >&2; exit 2 ;;
  esac
done

[ -z "$BRANCH" ] && { echo "--branch required" >&2; exit 2; }

if [ "$REMOTE" = "upstream" ]; then
  echo "REFUSE: cannot push to upstream — fork-only policy" >&2
  exit 2
fi

git push --force-with-lease "$REMOTE" "$BRANCH"
