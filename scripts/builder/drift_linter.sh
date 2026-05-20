#!/usr/bin/env bash
# drift_linter.sh --state-dir D --workdir W --owner-repo R --issue-number N --diff-base BASE
# Step 5 sub-checks: 5a newsfragment, 5b removed-symbol, 5c provider-leak.
# All three are WARN-level: failures are recorded but exit 0 (none block push).
# Source: agents/builder.md Step 5 (lines 475-554).
set -euo pipefail
: "${CLAUDE_PLUGIN_ROOT:?CLAUDE_PLUGIN_ROOT must be set}"
source "${CLAUDE_PLUGIN_ROOT}/scripts/lib/state.sh"
source "${CLAUDE_PLUGIN_ROOT}/scripts/lib/mistakes.sh"

SD=""
WD=""
OR=""
IN=""
BASE=""

while [ $# -gt 0 ]; do
  case "$1" in
    --state-dir)    SD="$2";   shift 2 ;;
    --workdir)      WD="$2";   shift 2 ;;
    --owner-repo)   OR="$2";   shift 2 ;;
    --issue-number) IN="$2";   shift 2 ;;
    --diff-base)    BASE="$2"; shift 2 ;;
    *) echo "drift_linter.sh: unknown arg: $1" >&2; exit 2 ;;
  esac
done

[ -z "$SD" ]   && { echo "--state-dir required"    >&2; exit 2; }
[ -z "$WD" ]   && { echo "--workdir required"      >&2; exit 2; }
[ -z "$OR" ]   && { echo "--owner-repo required"   >&2; exit 2; }
[ -z "$IN" ]   && { echo "--issue-number required" >&2; exit 2; }
[ -z "$BASE" ] && { echo "--diff-base required"    >&2; exit 2; }

# ---------------------------------------------------------------------------
# 5a: Newsfragment filename matches issue number
# ---------------------------------------------------------------------------
check_5a() {
  local news_files
  news_files=$(git -C "$WD" diff --name-only "$BASE"...HEAD \
    | grep -E '(newsfragments|changes|changelog\.d)/' || true)

  if [ -n "$news_files" ]; then
    for nf in $news_files; do
      local base
      base=$(basename "$nf")
      if ! echo "$base" | grep -qE "^${IN}[.-]"; then
        echo "WARN review-drift: newsfragment $nf does not start with #$IN"
        record_mistake "$SD" "$WD" "$OR" "builder:review-drift" \
          "newsfragment $nf should start with $IN"
      fi
    done
  fi
}

# ---------------------------------------------------------------------------
# 5b: Removed-symbol echo in commit body
# ---------------------------------------------------------------------------
check_5b() {
  local removed
  removed=$(git -C "$WD" diff "$BASE"...HEAD \
    | grep -E '^-\s*(def|class|function|fn) [A-Za-z_][A-Za-z0-9_]*' \
    | sed -E 's/^-[[:space:]]*(def|class|function|fn) ([A-Za-z_][A-Za-z0-9_]*).*/\2/' \
    | sort -u || true)

  if [ -z "$removed" ]; then
    return 0
  fi

  local commit_body
  commit_body=$(git -C "$WD" log -1 --format=%B)

  for sym in $removed; do
    if echo "$commit_body" | grep -qw "$sym"; then
      echo "WARN review-drift: removed symbol '$sym' still referenced in commit body"
      record_mistake "$SD" "$WD" "$OR" "builder:review-drift" \
        "removed symbol $sym still named in commit message; reword or keep the symbol"
    fi
  done
}

# ---------------------------------------------------------------------------
# 5c: Base-layer files don't name provider-scoped identifiers
# ---------------------------------------------------------------------------
check_5c() {
  local providers_dir="$WD/providers"
  if [ ! -d "$providers_dir" ]; then
    return 0
  fi

  # Portable alternative to -printf '%f\n': use find + basename via a loop
  local providers=""
  while IFS= read -r d; do
    providers="$providers $(basename "$d")"
  done < <(find "$providers_dir" -mindepth 1 -maxdepth 1 -type d | head -50)

  if [ -z "$providers" ]; then
    return 0
  fi

  local core_edits
  core_edits=$(git -C "$WD" diff --name-only "$BASE"...HEAD \
    | grep -v '^providers/' || true)

  if [ -z "$core_edits" ]; then
    return 0
  fi

  for cf in $core_edits; do
    for prov in $providers; do
      if git -C "$WD" diff "$BASE"...HEAD -- "$cf" \
           | grep -qiE "(^|[^A-Za-z0-9_])$prov([^A-Za-z0-9_]|$)"; then
        echo "WARN review-drift: core file $cf mentions provider '$prov'"
        record_mistake "$SD" "$WD" "$OR" "builder:review-drift" \
          "$cf references provider '$prov' — keep provider names out of core"
        break
      fi
    done
  done
}

# ---------------------------------------------------------------------------
# Main: run all checks, accumulate — none block push
# ---------------------------------------------------------------------------
check_5a
check_5b
check_5c

exit 0
