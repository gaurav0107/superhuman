#!/usr/bin/env bash
# tests/scripts/test_install.sh
# Verifies install.sh wires up all three plugins (and honours --skip-ecc / --codex)
# without touching the real ~/.claude or ~/.codex. Uses --dry-run + a stub claude.
set -euo pipefail
export CLAUDE_PLUGIN_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
INSTALL="$CLAUDE_PLUGIN_ROOT/install.sh"

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

# Stub `claude` so PATH lookup succeeds without a real CLI.
mkdir -p "$tmpdir/bin"
cat > "$tmpdir/bin/claude" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$tmpdir/bin/claude"
export CLAUDE_BIN="$tmpdir/bin/claude"

# --- default run: all three plugins present -----------------------------------
out=$(HOME="$tmpdir" bash "$INSTALL" --dry-run 2>&1)

echo "$out" | grep -q 'marketplace add https://github.com/obra/superpowers' \
  || { echo "FAIL: superpowers marketplace missing"; exit 1; }
echo "$out" | grep -q 'plugin install superpowers@superpowers' \
  || { echo "FAIL: superpowers install missing"; exit 1; }
echo "$out" | grep -q 'plugin install everything-claude-code@everything-claude-code' \
  || { echo "FAIL: ECC install missing"; exit 1; }
echo "$out" | grep -q 'plugin install superhuman@superhuman' \
  || { echo "FAIL: superhuman install missing"; exit 1; }

# --- --skip-ecc: ECC omitted, others still present ----------------------------
out_skip=$(HOME="$tmpdir" bash "$INSTALL" --dry-run --skip-ecc 2>&1)
if echo "$out_skip" | grep -q 'plugin install everything-claude-code@'; then
  echo "FAIL: --skip-ecc still installed ECC"; exit 1
fi
echo "$out_skip" | grep -q 'plugin install superhuman@superhuman' \
  || { echo "FAIL: --skip-ecc dropped superhuman"; exit 1; }

# --- --codex: clones + symlinks the skill (dry-run prints the commands) --------
out_codex=$(HOME="$tmpdir" bash "$INSTALL" --dry-run --codex 2>&1)
echo "$out_codex" | grep -q 'git clone https://github.com/gaurav0107/superhuman' \
  || { echo "FAIL: --codex did not clone"; exit 1; }
echo "$out_codex" | grep -q 'ln -s .*/skills/superhuman' \
  || { echo "FAIL: --codex did not symlink skill"; exit 1; }

# --- missing claude CLI: prints manual slash-command fallback -----------------
out_noclaude=$(HOME="$tmpdir" CLAUDE_BIN="$tmpdir/bin/nonexistent-claude" \
  bash "$INSTALL" --dry-run 2>&1)
echo "$out_noclaude" | grep -q '/plugin install superpowers@superpowers' \
  || { echo "FAIL: no-claude fallback missing slash command"; exit 1; }

echo "OK test_install.sh"
