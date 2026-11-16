#!/usr/bin/env bash
# dossier_fresh.sh --repo OWNER/REPO --head-sha SHA
# Producer plumbing (caller: lesson-distiller / repo-profiler): exit 0 if the repo's
# dossier is FRESH (dossier_meta.json head_sha == SHA), exit 1 if STALE (mismatch or
# no dossier_meta). Drives the "re-scan when HEAD moved" gate.
set -euo pipefail
# Not exported by the harness (template variable only), so derive it from $0.
export CLAUDE_PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}"
source "${CLAUDE_PLUGIN_ROOT}/scripts/lib/state.sh"

REPO=""; HEAD_SHA=""
while [ $# -gt 0 ]; do
  case "$1" in
    --repo)     REPO="$2"; shift 2 ;;
    --head-sha) HEAD_SHA="$2"; shift 2 ;;
    *) echo "dossier_fresh.sh: unknown arg: $1" >&2; exit 2 ;;
  esac
done
[ -n "$REPO" ] || { echo "--repo required" >&2; exit 2; }
[ -n "$HEAD_SHA" ] || { echo "--head-sha required" >&2; exit 2; }

dir=$(state_dir "$REPO")
meta_head=$(jq -r '.head_sha // ""' "$dir/dossier_meta.json" 2>/dev/null || echo "")
if [ -n "$meta_head" ] && [ "$meta_head" = "$HEAD_SHA" ]; then exit 0; else exit 1; fi
