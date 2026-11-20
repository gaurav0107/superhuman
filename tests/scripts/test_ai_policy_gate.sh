#!/usr/bin/env bash
# tests/scripts/test_ai_policy_gate.sh
set -euo pipefail
export CLAUDE_PLUGIN_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SCRIPT="$CLAUDE_PLUGIN_ROOT/scripts/orchestrator/ai_policy_gate.sh"
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT

fail() { echo "FAIL: $1"; exit 1; }
# want <expected-rc> <label> <file-in-repo> <policy text>   (empty text = no file)
want() {
  local d="$tmp/$2" rc=0 out
  mkdir -p "$d/$(dirname "$3")"
  [ -z "$4" ] || printf '%s\n' "$4" > "$d/$3"
  out=$(bash "$SCRIPT" --repo o/r --dir "$d") || rc=$?
  [ "$rc" = "$1" ] || fail "$2: rc $rc, want $1 ($out)"
  if [ "$1" = 6 ]; then printf '%s' "$out" | grep -qF "NO_AI_POLICY: o/r — $3:" || fail "$2: reason not recorded ($out)"; fi
}

# Prohibiting policies -> exit 6, with the file and sentence quoted.
want 6 prohibit-plain   CONTRIBUTING.md 'We do not accept AI-generated contributions.'
want 6 prohibit-wrapped CONTRIBUTING.md 'Please don’t submit pull requests
written with ChatGPT or other LLMs.'
want 6 prohibit-bullet  .github/CONTRIBUTING.md '## Rules
- No AI-generated code
- Every PR needs tests'
want 6 prohibit-aipolicy AI_POLICY.md 'The use of generative AI tools is prohibited for contributions to this project.'
want 6 prohibit-coc     CODE_OF_CONDUCT.md 'Pull requests produced by LLMs will be closed.'

# Disclosure-only policies -> eligible (superhuman's PR footer already discloses).
want 0 disclose-must    CONTRIBUTING.md 'If you use AI tools, you must disclose it in the PR description.'
want 0 disclose-undiscl CONTRIBUTING.md 'We do not accept undisclosed AI-generated contributions.'

# No policy at all -> eligible.
want 0 no-files         CONTRIBUTING.md ''
want 0 no-ai-mention    CONTRIBUTING.md 'Run the tests before opening a PR. We do not accept PRs without tests.'

# Conservative edges: permissive, conditional, and the yt-dlp "ai inside chains" regression.
want 0 permissive       CONTRIBUTING.md 'AI tools are fine, but we don'"'"'t accept PRs without a linked issue.'
want 0 conditional      CONTRIBUTING.md 'Low-effort AI-generated PRs will be closed.'
want 0 substring-ai     CONTRIBUTING.md 'Do not use .get chains; maintainers will not accept them.'

# Config errors are never verdicts.
rc=0; bash "$SCRIPT" --dir "$tmp" >/dev/null 2>&1 || rc=$?; [ "$rc" = 10 ] || fail "missing --repo: rc $rc"
rc=0; bash "$SCRIPT" --repo o/r --dir "$tmp/nope" >/dev/null 2>&1 || rc=$?; [ "$rc" = 10 ] || fail "bad --dir: rc $rc"

echo "OK test_ai_policy_gate.sh"
