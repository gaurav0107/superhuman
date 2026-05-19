#!/usr/bin/env bash
# detect_smoke.sh REPO_DIR
# Emits {repo, generated_at, layers:[{name, cmd, cwd, timeout_s}]} on stdout.
set -euo pipefail
: "${CLAUDE_PLUGIN_ROOT:?CLAUDE_PLUGIN_ROOT must be set}"

REPO_DIR="${1:?repo dir required}"
[ -d "$REPO_DIR" ] || { echo "detect_smoke.sh: not a dir: $REPO_DIR" >&2; exit 2; }
cd "$REPO_DIR"

layers='[]'
add_layer() {
  local name="$1" cmd="$2" cwd="$3" timeout="$4"
  layers=$(echo "$layers" | jq \
    --arg n "$name" --arg c "$cmd" --arg w "$cwd" --argjson t "$timeout" \
    '. + [{name:$n, cmd:$c, cwd:$w, timeout_s:$t}]')
}

if [ -f setup.py ] || [ -f pyproject.toml ]; then
  pkg=$(find . -maxdepth 2 -name __init__.py -not -path '*/tests/*' 2>/dev/null | head -1)
  if [ -n "$pkg" ]; then
    pkg_name=$(dirname "$pkg" | sed 's|^\./||' | tr '/' '.')
    add_layer "python_import_root" "python -c 'import $pkg_name'" "." 30
  fi
fi

if [ -f manage.py ]; then
  add_layer "django_check" "python manage.py check" "." 60
fi

flask_mod=$(grep -rln --include='*.py' -E '^app[[:space:]]*=[[:space:]]*Flask\(' . 2>/dev/null | head -1 || true)
if [ -n "$flask_mod" ]; then
  modname=$(echo "$flask_mod" | sed 's|^\./||;s|\.py$||;s|/|.|g')
  add_layer "flask_app_import" "python -c 'from $modname import app'" "." 30
fi

fastapi_mod=$(grep -rln --include='*.py' -E '^app[[:space:]]*=[[:space:]]*FastAPI\(' . 2>/dev/null | head -1 || true)
if [ -n "$fastapi_mod" ]; then
  modname=$(echo "$fastapi_mod" | sed 's|^\./||;s|\.py$||;s|/|.|g')
  add_layer "fastapi_app_import" "python -c 'from $modname import app'" "." 30
fi

if [ -d tests/smoke ]; then
  add_layer "pytest_smoke_dir" "pytest tests/smoke" "." 120
fi

if [ -f package.json ]; then
  main_field=$(jq -r '.main // empty' package.json 2>/dev/null || true)
  if [ -n "$main_field" ]; then
    add_layer "node_require_root" "node -e \"require('./$main_field')\"" "." 30
  fi
fi

repo_slug=$(basename "$(pwd)")
generated_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)
jq -n --arg repo "$repo_slug" --arg ts "$generated_at" --argjson layers "$layers" \
  '{repo:$repo, generated_at:$ts, layers:$layers}'
