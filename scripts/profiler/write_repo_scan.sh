#!/usr/bin/env bash
# write_repo_scan.sh --repo OWNER/REPO --worktree DIR [--head-sha SHA] [--now ISO]
# Producer plumbing (caller: repo-profiler): run scan_structure.sh, validate the
# result against repo_scan.schema.json, and atomically publish it to
# ~/.superhuman/repos/<slug>/repo_scan.json. On invalid scan output, abort WITHOUT
# publishing (a blank/garbage scan must never ground the dossier). Prints the path.
set -euo pipefail
# Not exported by the harness (template variable only), so derive it from $0.
export CLAUDE_PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}"
source "${CLAUDE_PLUGIN_ROOT}/scripts/lib/state.sh"

REPO=""; WT=""; HEAD_SHA=""; NOW=""
while [ $# -gt 0 ]; do
  case "$1" in
    --repo)     REPO="$2"; shift 2 ;;
    --worktree) WT="$2"; shift 2 ;;
    --head-sha) HEAD_SHA="$2"; shift 2 ;;
    --now)      NOW="$2"; shift 2 ;;
    *) echo "write_repo_scan.sh: unknown arg: $1" >&2; exit 2 ;;
  esac
done
[ -n "$REPO" ] || { echo "--repo required" >&2; exit 2; }
[ -n "$WT" ] && [ -d "$WT" ] || { echo "--worktree DIR (existing) required" >&2; exit 2; }

args=(--repo "$REPO" --worktree "$WT")
[ -n "$HEAD_SHA" ] && args+=(--head-sha "$HEAD_SHA")
[ -n "$NOW" ] && args+=(--now "$NOW")
scan=$("${CLAUDE_PLUGIN_ROOT}/scripts/profiler/scan_structure.sh" "${args[@]}")

tmp=$(mktemp)
printf '%s' "$scan" > "$tmp"
if ! validate_json "${CLAUDE_PLUGIN_ROOT}/schemas/repo_scan.schema.json" "$tmp" 2>/dev/null; then
  rm -f "$tmp"
  echo "write_repo_scan.sh: scan output failed schema validation — not publishing" >&2
  exit 1
fi
rm -f "$tmp"

dir=$(state_dir "$REPO")
atomic_write_json "$dir/repo_scan.json" "$scan"
echo "$dir/repo_scan.json"
