#!/usr/bin/env bash
# parse_workflows.sh WORKFLOW_FILE [WORKFLOW_FILE ...]
# Emits each `run:` value on stdout, one logical command per line.
# Classification (allowed vs denied) is NOT done here — agent prompt handles
# classification per audit §7.
set -euo pipefail
: "${CLAUDE_PLUGIN_ROOT:?CLAUDE_PLUGIN_ROOT must be set}"

if ! command -v yq >/dev/null 2>&1; then
  echo "parse_workflows.sh: yq required" >&2
  exit 2
fi

for wf in "$@"; do
  [ -f "$wf" ] || continue
  yq -r '.. | select(has("run")) | .run' "$wf" 2>/dev/null | \
    awk 'NF { print }'
done
