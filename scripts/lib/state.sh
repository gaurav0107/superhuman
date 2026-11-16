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
  # Announce the degradation. This fallback checks TOP-LEVEL required keys only and
  # cannot see inside an array, so every nested constraint goes unchecked: a
  # shortlist whose `repos[]` rows are missing `repo` or `scores.final` validates
  # clean here. Callers must assert their own row invariants, and can only know to
  # do so if the degradation is visible. Silence makes an unvalidated document look
  # validated.
  echo "validate_json: WARN: python3 jsonschema not available — falling back to a" >&2
  echo "  top-level required-key check. Nested constraints (array rows, sub-objects)" >&2
  echo "  are NOT validated. Install it with: python3 -m pip install jsonschema" >&2

  # Read one field per line. `for k in $req` would need the shell to split an
  # unquoted expansion; zsh does not, and this file is SOURCED, so it runs in the
  # caller's shell — zsh on macOS, where the whole field list arrives as one word
  # and a valid document is rejected. This is the fallback path whenever
  # `python3 -m jsonschema` is absent.
  local req k
  req=$(jq -r '.required // [] | .[]' "$schema")
  while IFS= read -r k; do
    [ -n "$k" ] || continue
    jq -e --arg k "$k" 'has($k)' "$data" >/dev/null || {
      echo "validate_json: missing required field: $k" >&2
      return 1
    }
  done <<EOF
$req
EOF
  return 0
}

# jq defs shared by readers of merge_outcomes.jsonl. Rows were written by several
# generations of the orchestrator: the timestamp is closed_at, ts or recorded_at,
# and one PR can have several rows (the run's own exit, then the sweep's merged /
# closed_no_merge). Readers must count each PR once, by its latest row.
# shellcheck disable=SC2034
OUTCOMES_JQ='
  def row_ts: (.closed_at // .ts // .recorded_at // "1970-01-01T00:00:00Z");
  def row_epoch: row_ts | sub("\\.[0-9]+"; "") | sub("Z$"; "") | strptime("%Y-%m-%dT%H:%M:%S") | mktime;
  def latest_per_pr:
    map(select((.pr_url // "") == ""))
    + (map(select((.pr_url // "") != "")) | group_by(.pr_url) | map(last));
'
