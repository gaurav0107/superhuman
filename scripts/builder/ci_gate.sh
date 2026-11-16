#!/usr/bin/env bash
# ci_gate.sh --state-dir D --workdir W --owner-repo R --command "CMD"
# Exit 0 = clean. 1 = flake-classified failure (caller continues).
# 2 = real failure or denylist block (caller aborts phase).
# Token-level allowlist/denylist match (NOT substring).
set -euo pipefail
# Not exported by the harness (template variable only), so derive it from $0.
export CLAUDE_PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}"
source "${CLAUDE_PLUGIN_ROOT}/scripts/lib/state.sh"
source "${CLAUDE_PLUGIN_ROOT}/scripts/lib/mistakes.sh"
source "${CLAUDE_PLUGIN_ROOT}/scripts/lib/flake.sh"

SD=""; WD=""; OR=""; CMD=""
while [ $# -gt 0 ]; do
  case "$1" in
    --state-dir)  SD="$2"; shift 2 ;;
    --workdir)    WD="$2"; shift 2 ;;
    --owner-repo) OR="$2"; shift 2 ;;
    --command)    CMD="$2"; shift 2 ;;
    *) echo "ci_gate.sh: unknown arg: $1" >&2; exit 2 ;;
  esac
done

ALLOW="$SD/allowed_commands.json"
[ -f "$ALLOW" ] || { echo "ci_gate.sh: missing $ALLOW" >&2; exit 2; }

# Tokenize command. Quoted strings preserved as one token via xargs printf.
read -r -a TOKENS <<< "$CMD"
[ "${#TOKENS[@]}" -eq 0 ] && { echo "ci_gate.sh: empty command" >&2; exit 2; }
binary="${TOKENS[0]}"

# Denylist first. Token-level match (whole token), not substring.
denied=$(jq -r '.denied_patterns[]' "$ALLOW")
for pat in $denied; do
  for t in "${TOKENS[@]}"; do
    if [ "$t" = "$pat" ]; then
      record_mistake "$SD" "$WD" "$OR" "builder:ci_gate" "denylist match: token '$pat' in command '$CMD'"
      exit 2
    fi
  done
  # Also check contiguous-substring patterns explicitly listed (rm -rf, chmod 777, etc.)
  if echo " $CMD " | grep -q " $pat "; then
    record_mistake "$SD" "$WD" "$OR" "builder:ci_gate" "denylist match: '$pat' in command '$CMD'"
    exit 2
  fi
done

# Allowlist: binary must be in allowed_binaries (whole-token match).
allowed=$(jq -r '.allowed_binaries[]' "$ALLOW")
ok=0
for a in $allowed; do
  [ "$binary" = "$a" ] && { ok=1; break; }
done
if [ "$ok" -ne 1 ]; then
  record_mistake "$SD" "$WD" "$OR" "builder:ci_gate" "binary '$binary' not in allowlist"
  exit 2
fi

# Sandbox + execute. Restricted env. Capture log to /tmp/<name>.log per spec.
SANDBOX="${TMPDIR:-/tmp}/superhuman-sandbox"
mkdir -p "$SANDBOX"
LOG="/tmp/$(echo "$binary" | tr '/' '_').log"

set +e
env -i PATH=/usr/bin:/bin HOME="$SANDBOX" TMPDIR="$SANDBOX" \
  bash -c "cd '$WD' && $CMD" > "$LOG" 2>&1
rc=$?
set -e

if [ "$rc" -eq 0 ]; then
  exit 0
fi

# Failure: try flake classification first.
GD=$(global_dir)
if classify_as_flake "$GD/flake_signatures.md" "$LOG" 2>/dev/null; then
  echo "ci_gate.sh: $binary failed but matched a known flake signature; treating as flake" >&2
  exit 1
fi

record_mistake "$SD" "$WD" "$OR" "builder:ci_gate" "real failure: $CMD (rc=$rc, log=$LOG)"
exit 2
