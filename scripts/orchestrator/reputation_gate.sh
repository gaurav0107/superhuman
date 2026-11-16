#!/usr/bin/env bash
# reputation_gate.sh --repo OWNER/REPO [--now ISO_TS]
# Exit 0 = eligible. 1 = blocklisted. 2 = in cooldown. 3 = locked.
# 5 = we already have SUPERHUMAN_MAX_OPEN_PRS_PER_REPO (default 2) open PRs there.
# Exit 10 = config error, not a verdict. Must stay distinct from 1/2/3: callers
# drop a repo on any nonzero code, so reusing a verdict code for a config error
# would drop repos for a reason unrelated to them. Callers abort on 10.
set -euo pipefail

EX_CONFIG=10

# Derive the plugin root from this script's own location when the environment does
# not carry it. CLAUDE_PLUGIN_ROOT is a *template* variable: the harness expands it
# into agent and command markdown, so every caller invokes this script by absolute
# path — but it is never exported into the shell, so the script cannot read it back.
# Demanding it here made the gate exit 10 ("misconfigured") on the first candidate
# and abort the entire scan, for every caller that used the documented snippet.
#
# scripts/orchestrator/reputation_gate.sh -> ../.. is the plugin root.
if [ -z "${CLAUDE_PLUGIN_ROOT:-}" ]; then
  CLAUDE_PLUGIN_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd) || {
    echo "reputation_gate.sh: CONFIG ERROR: cannot resolve plugin root from \$0=$0" >&2
    echo "  This is NOT a verdict about the repo." >&2
    exit "$EX_CONFIG"
  }
fi
if [ ! -r "${CLAUDE_PLUGIN_ROOT}/scripts/lib/state.sh" ]; then
  echo "reputation_gate.sh: CONFIG ERROR: cannot read" \
       "${CLAUDE_PLUGIN_ROOT}/scripts/lib/state.sh" >&2
  exit "$EX_CONFIG"
fi
# shellcheck source=/dev/null
source "${CLAUDE_PLUGIN_ROOT}/scripts/lib/state.sh"

if ! command -v jq >/dev/null 2>&1; then
  echo "reputation_gate.sh: CONFIG ERROR: jq not found on PATH." >&2
  exit "$EX_CONFIG"
fi

REPO=""
NOW=""
# Check arity before touching $2: under `set -u` a flag with no value dies on
# the unbound $2 and exits 1, i.e. the "blocklisted" verdict.
need_value() {
  [ "$2" -ge 2 ] && return 0
  echo "reputation_gate.sh: CONFIG ERROR: $1 requires a value" >&2
  exit "$EX_CONFIG"
}

while [ $# -gt 0 ]; do
  case "$1" in
    --repo) need_value --repo "$#"; REPO="$2"; shift 2 ;;
    --now)  need_value --now  "$#"; NOW="$2";  shift 2 ;;
    *) echo "reputation_gate.sh: CONFIG ERROR: unknown arg: $1" >&2; exit "$EX_CONFIG" ;;
  esac
done
[ -z "$REPO" ] && { echo "reputation_gate.sh: CONFIG ERROR: --repo required" >&2; exit "$EX_CONFIG"; }
[ -z "$NOW" ]  && NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)

GD=$(global_dir)
BL="$GD/repo_blocklist.json"
CD="$GD/repo_cooldown.json"

# Blocklist: highest authority
if [ -f "$BL" ]; then
  reason=$(jq -r --arg r "$REPO" --arg now "$NOW" '
    .blocked[]? | select(.repo == $r)
    | select(.expires_at == null or .expires_at > $now)
    | .reason' "$BL" 2>/dev/null | head -1)
  if [ -n "$reason" ]; then
    echo "BLOCKED: $REPO — $reason"
    exit 1
  fi
fi

# Cooldown
if [ -f "$CD" ]; then
  until_ts=$(jq -r --arg r "$REPO" '
    .cooldowns[]? | select(.repo == $r) | .cooldown_until // empty' \
    "$CD" 2>/dev/null | head -1)
  if [ -n "$until_ts" ] && [ "$until_ts" \> "$NOW" ]; then
    echo "COOLDOWN: $REPO until $until_ts"
    exit 2
  fi
fi

# Active lock
SD=$(state_dir "$REPO")
CUR="$SD/current_contribution.json"
if [ -f "$CUR" ]; then
  holder=$(jq -r '.lock_holder // empty' "$CUR" 2>/dev/null)
  if [ -n "$holder" ] && [ "$holder" != "null" ]; then
    # A run that dies (closed session, context limit, crash) never clears
    # lock_holder, and no pid survives across Bash tool calls to probe. So the lock
    # expires: no run writes its state file for longer than the TTL.
    ttl_h="${SUPERHUMAN_LOCK_TTL_HOURS:-6}"
    age_s=$(python3 -c 'import os,sys,datetime as d
now=d.datetime.fromisoformat(sys.argv[2].replace("Z","+00:00")).timestamp()
print(int(now-os.path.getmtime(sys.argv[1])))' "$CUR" "$NOW")
    if [ "$age_s" -lt $((ttl_h * 3600)) ]; then
      echo "LOCKED: $REPO — held by $holder"
      exit 3
    fi
    echo "STALE LOCK: $REPO — $holder idle ${age_s}s (> ${ttl_h}h); treating as free" >&2
  fi
fi

# Etiquette: don't pile PRs onto one project. Counts our open PRs there live.
# A failed lookup does not block (the cap is courtesy, not safety).
max_open="${SUPERHUMAN_MAX_OPEN_PRS_PER_REPO:-2}"
if [ "$max_open" -gt 0 ]; then
  if open=$(gh pr list --repo "$REPO" --author @me --state open --json number --jq length 2>/dev/null); then
    if [ "$open" -ge "$max_open" ]; then
      echo "OPEN_PR_CAP: $REPO — $open open PRs (cap $max_open)"
      exit 5
    fi
  else
    echo "reputation_gate.sh: WARN: could not count open PRs for $REPO; cap not applied" >&2
  fi
fi

echo "ELIGIBLE: $REPO"
exit 0
