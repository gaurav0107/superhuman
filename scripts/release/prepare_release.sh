#!/usr/bin/env bash
# prepare_release.sh — make the working tree describe a given release version.
#
#   prepare_release.sh --current               # verify the 3 manifests agree; print the version
#   prepare_release.sh --set X.Y.Z [--date D]  # write X.Y.Z to the 3 manifests + promote CHANGELOG
#
# Pure filesystem: no network, no git. Operates on the manifests and CHANGELOG
# under $CLAUDE_PLUGIN_ROOT (default: repo root, inferred from this script's
# path). The release workflow calls it; test_prepare_release.sh points
# CLAUDE_PLUGIN_ROOT at a fixture tree.
#
# Exit: 0 ok, 10 config/usage error. 10 is distinct from any version string so a
# caller that captures stdout never mistakes an error for a version.
set -euo pipefail

die() { echo "prepare_release.sh: $*" >&2; exit 10; }

ROOT="${CLAUDE_PLUGIN_ROOT:-$(CDPATH= cd "$(dirname "$0")/../.." && pwd)}"
PLUGIN="$ROOT/.claude-plugin/plugin.json"
MARKET="$ROOT/.claude-plugin/marketplace.json"
CODEX="$ROOT/.codex-plugin/plugin.json"
CHANGELOG="$ROOT/CHANGELOG.md"

command -v jq >/dev/null 2>&1 || die "jq is required"

# Strict, anchored X.Y.Z. A glob like [0-9]*.[0-9]*.[0-9]* is not enough — it
# accepts "1.2.3-beta", "1.2.3abc", and "1.2.3; rm -rf". The workflow splices this
# value into shell/awk, so a loose check is a code-injection surface.
is_semver() { [[ "$1" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; }

read_current() { # echoes "plugin marketplace codex" versions
  [ -r "$PLUGIN" ] || die "cannot read $PLUGIN"
  [ -r "$MARKET" ] || die "cannot read $MARKET"
  [ -r "$CODEX" ]  || die "cannot read $CODEX"
  local p m c
  p=$(jq -r '.version // empty' "$PLUGIN")
  m=$(jq -r '.plugins[0].version // empty' "$MARKET")
  c=$(jq -r '.version // empty' "$CODEX")
  [ -n "$p" ] && [ -n "$m" ] && [ -n "$c" ] || die "a manifest is missing .version"
  printf '%s %s %s' "$p" "$m" "$c"
}

current() {
  local p m c
  read -r p m c <<<"$(read_current)"
  [ "$p" = "$m" ] && [ "$p" = "$c" ] \
    || die "manifests disagree: plugin=$p marketplace=$m codex=$c"
  is_semver "$p" || die "manifest version is not a valid X.Y.Z semver: $p"
  printf '%s\n' "$p"
}

write_version() { # write_version <file> <jq-set-filter> <version>
  local f="$1" filter="$2" v="$3" tmp
  tmp=$(mktemp)
  jq --arg v "$v" "$filter" "$f" > "$tmp"
  mv "$tmp" "$f"
}

# Promote CHANGELOG's [Unreleased] section into a dated version section and open
# a fresh empty [Unreleased] above it. Idempotent (a [X.Y.Z] section already
# present → no-op) and a no-op when there is no [Unreleased] heading.
promote_changelog() {
  local v="$1" d="$2" tmp
  [ -f "$CHANGELOG" ] || return 0
  grep -qE "^## \[$v\]( |\$)" "$CHANGELOG" && return 0
  grep -qE '^## \[Unreleased\]' "$CHANGELOG" || return 0
  tmp=$(mktemp)
  awk -v v="$v" -v d="$d" '
    /^## \[Unreleased\]/ && !done {
      print "## [Unreleased]"
      print ""
      print "## [" v "] — " d
      done = 1
      next
    }
    { print }
  ' "$CHANGELOG" > "$tmp"
  mv "$tmp" "$CHANGELOG"
}

set_version() {
  local v="$1" d="$2"
  is_semver "$v" || die "--set expects a semver X.Y.Z, got: $v"
  write_version "$PLUGIN" '.version = $v'            "$v"
  write_version "$MARKET" '.plugins[0].version = $v' "$v"
  write_version "$CODEX"  '.version = $v'            "$v"
  promote_changelog "$v" "$d"
  printf '%s\n' "$v"
}

MODE="" VERSION="" DATE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --current) MODE="current"; shift ;;
    --set)  [ $# -ge 2 ] || die "--set needs a value";  MODE="set"; VERSION="$2"; shift 2 ;;
    --date) [ $# -ge 2 ] || die "--date needs a value"; DATE="$2"; shift 2 ;;
    *) die "unknown argument: $1" ;;
  esac
done
[ -n "$MODE" ] || die "one of --current or --set is required"
DATE="${DATE:-$(date -u +%Y-%m-%d)}"

case "$MODE" in
  current) current ;;
  set)     set_version "$VERSION" "$DATE" ;;
esac
