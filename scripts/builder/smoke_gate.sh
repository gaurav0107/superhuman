#!/usr/bin/env bash
# smoke_gate.sh --state-dir D --changed-file FILE --workdir W --owner-repo R
# CHANGED FILE is a newline-delimited list of changed files (relative to repo root).
set -euo pipefail
# Not exported by the harness (template variable only), so derive it from $0.
export CLAUDE_PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}"
source "${CLAUDE_PLUGIN_ROOT}/scripts/lib/state.sh"
source "${CLAUDE_PLUGIN_ROOT}/scripts/lib/mistakes.sh"

SD=""; CHF=""; WD=""; OR=""
while [ $# -gt 0 ]; do
  case "$1" in
    --state-dir)    SD="$2"; shift 2 ;;
    --changed-file) CHF="$2"; shift 2 ;;
    --workdir)      WD="$2"; shift 2 ;;
    --owner-repo)   OR="$2"; shift 2 ;;
    *) echo "smoke_gate.sh: unknown arg: $1" >&2; exit 2 ;;
  esac
done

REG="$SD/smoke_registry.json"
[ -f "$REG" ] || { echo "smoke_gate.sh: no registry, skipping" >&2; exit 0; }
[ -f "$CHF" ] || { echo "smoke_gate.sh: no changed-file" >&2; exit 2; }

# Read layers in registry order
layers=$(jq -c '.layers[]' "$REG")

# Detect "any python file changed" / "any node file changed" — drives layer selection
has_py=0; has_js=0
while IFS= read -r f; do
  case "$f" in
    *.py)        has_py=1 ;;
    *.js|*.ts)   has_js=1 ;;
  esac
done < "$CHF"

while IFS= read -r layer; do
  name=$(echo "$layer" | jq -r .name)
  cmd=$(echo "$layer"  | jq -r .cmd)
  cwd=$(echo "$layer"  | jq -r .cwd)
  timeout=$(echo "$layer" | jq -r .timeout_s)

  # Per-layer relevance heuristic. Conservative: when in doubt, run it.
  case "$name" in
    python_import_root|django_check|flask_app_import|fastapi_app_import|pytest_smoke_dir)
      [ "$has_py" -eq 0 ] && continue
      ;;
    node_require_root)
      [ "$has_js" -eq 0 ] && continue
      ;;
  esac

  set +e
  ( cd "$WD/$cwd" && timeout "$timeout" bash -c "$cmd" )
  rc=$?
  set -e
  if [ "$rc" -ne 0 ]; then
    record_mistake "$SD" "$WD" "$OR" "builder:smoke_gate" "layer '$name' failed (rc=$rc, cmd=$cmd)"
    exit 2
  fi
done <<< "$layers"

exit 0
