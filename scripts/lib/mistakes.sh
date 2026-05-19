#!/usr/bin/env bash
# Append-only mistakes log. Format must remain byte-equivalent to the
# pre-extraction inline definition in agents/builder.md:336-403.

# record_mistake STATE_DIR WORKDIR OWNER_REPO TAG MESSAGE
record_mistake() {
  local state_dir="$1" workdir="$2" owner_repo="$3" tag="$4" message="$5"
  local file="$state_dir/mistakes.md"
  local ts
  ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  mkdir -p "$state_dir"
  {
    printf '## %s tag=%s repo=%s\n' "$ts" "$tag" "$owner_repo"
    printf 'workdir: %s\n\n' "$workdir"
    printf '%s\n\n' "$message"
  } >> "$file"
}
