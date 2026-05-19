#!/usr/bin/env bash
# Shared state helpers. Sourced by every script under scripts/.

state_dir() {
  local owner_repo="$1"
  local slug="${owner_repo/\//-}"
  echo "$HOME/.superhuman/repos/$slug"
}

global_dir() {
  echo "$HOME/.superhuman/global"
}

atomic_write_json() {
  local path="$1" content="$2"
  local tmp="${path}.tmp.$$"
  mkdir -p "$(dirname "$path")"
  printf '%s' "$content" | jq . > "$tmp" && mv "$tmp" "$path"
}

require_lock() {
  local repo="$1" expected="$2"
  local dir
  dir=$(state_dir "$repo")
  local lock
  lock=$(jq -r .lock_holder "$dir/current_contribution.json" 2>/dev/null || echo "")
  if [ "$lock" != "$expected" ]; then
    echo "ERROR: expected lock_holder=$expected, got $lock" >&2
    return 1
  fi
}

validate_json() {
  local schema="$1" data="$2"
  if command -v python3 >/dev/null 2>&1 && python3 -c 'import jsonschema' 2>/dev/null; then
    python3 - "$schema" "$data" <<'PY'
import json, sys, jsonschema
schema = json.load(open(sys.argv[1]))
data = json.load(open(sys.argv[2]))
jsonschema.validate(data, schema)
PY
    return $?
  fi
  local req
  req=$(jq -r '.required // [] | .[]' "$schema")
  for k in $req; do
    jq -e --arg k "$k" 'has($k)' "$data" >/dev/null || {
      echo "validate_json: missing required field: $k" >&2
      return 1
    }
  done
  return 0
}
