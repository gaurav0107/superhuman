#!/usr/bin/env bash
set -euo pipefail
export CLAUDE_PLUGIN_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

SCRIPT="$CLAUDE_PLUGIN_ROOT/scripts/builder/push_force_with_lease.sh"

# ── helpers ──────────────────────────────────────────────────────────────────
pass() { printf 'PASS %s\n' "$1"; }
fail() { printf 'FAIL %s: %s\n' "$1" "$2" >&2; exit 1; }

# ── build a git shim ──────────────────────────────────────────────────────────
TMPDIR_TEST=$(mktemp -d)
SHIM_LOG="$TMPDIR_TEST/git_calls.log"
SHIM="$TMPDIR_TEST/git"

cat > "$SHIM" <<'EOF'
#!/usr/bin/env bash
echo "$@" >> "$GIT_SHIM_LOG"
exit 0
EOF
chmod +x "$SHIM"

# ── Test A: --branch foo --remote origin → git push --force-with-lease origin foo ──
rm -f "$SHIM_LOG"
export GIT_SHIM_LOG="$SHIM_LOG"
PATH="$TMPDIR_TEST:$PATH" \
  CLAUDE_PLUGIN_ROOT="$CLAUDE_PLUGIN_ROOT" \
  bash "$SCRIPT" --branch foo --remote origin
grep -q "push --force-with-lease origin foo" "$SHIM_LOG" \
  || fail "Test A" "shim log missing expected git invocation"
pass "Test A"

# ── Test B: --remote upstream → exit 2 BEFORE git is called ──────────────────
rm -f "$SHIM_LOG"
rc=0
PATH="$TMPDIR_TEST:$PATH" \
  CLAUDE_PLUGIN_ROOT="$CLAUDE_PLUGIN_ROOT" \
  bash "$SCRIPT" --branch foo --remote upstream 2>/dev/null || rc=$?
[ "$rc" -eq 2 ] || fail "Test B" "expected exit 2, got $rc"
[ ! -f "$SHIM_LOG" ] || ! grep -q "push" "$SHIM_LOG" \
  || fail "Test B" "git push was invoked but should not have been"
pass "Test B"

# ── Test C: missing --branch → exit 2 ────────────────────────────────────────
rc=0
PATH="$TMPDIR_TEST:$PATH" \
  CLAUDE_PLUGIN_ROOT="$CLAUDE_PLUGIN_ROOT" \
  bash "$SCRIPT" --remote origin 2>/dev/null || rc=$?
[ "$rc" -eq 2 ] || fail "Test C" "expected exit 2, got $rc"
pass "Test C"

# ── cleanup ───────────────────────────────────────────────────────────────────
rm -rf "$TMPDIR_TEST"

echo "OK test_push.sh"
