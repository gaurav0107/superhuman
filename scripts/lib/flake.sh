#!/usr/bin/env bash
# Flake classification + hit recording. flake_signatures.md is
# cross-repo, append-only (~/.superhuman/global/).

classify_as_flake() {
  local sig_file="$1" log_file="$2"
  [ -f "$sig_file" ] || return 1
  [ -f "$log_file" ] || return 1
  local patterns
  patterns=$(awk '/^- pattern: `/ {
    sub(/^- pattern: `/, "")
    sub(/`$/, "")
    print
  }' "$sig_file")
  [ -z "$patterns" ] && return 1
  while IFS= read -r pat; do
    [ -z "$pat" ] && continue
    if grep -E -q "$pat" "$log_file" 2>/dev/null; then
      return 0
    fi
  done <<< "$patterns"
  return 1
}

record_flake_hit() {
  local sig_file="$1" name="$2" repo="$3" ts="$4"
  printf -- '- last_hit: %s repo=%s signature=%s\n' "$ts" "$repo" "$name" >> "$sig_file"
}
