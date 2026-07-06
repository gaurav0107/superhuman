#!/usr/bin/env bash
# superhuman — one-command installer.
#
# Installs the superhuman plugin AND its dependent plugins in one shot:
#   • superpowers            (required — planner/builder wrap its skills)
#   • everything-claude-code (ECC, recommended — language-specialist reviewers)
#   • superhuman             (this plugin)
#
# Usage (remote, the "1 command"):
#   curl -fsSL https://raw.githubusercontent.com/gaurav0107/superhuman/main/install.sh | bash
#
# Usage (local clone):
#   bash install.sh [options]
#
# Options:
#   --skip-ecc     Don't install everything-claude-code (the optional reviewer plugin).
#   --codex        Also install for Codex (clone repo + symlink the skill).
#   --dry-run      Print the commands that would run, without executing them.
#   -h, --help     Show this help and exit.
#
# Environment overrides (mostly for testing):
#   CLAUDE_BIN     Path to the `claude` CLI (default: claude).
#   CODEX_SKILLS_DIR   Where to link the Codex skill (default: ~/.codex/skills).
#   SUPERHUMAN_SRC     Where --codex clones the repo (default: ~/src/superhuman).
set -euo pipefail

REPO_URL="https://github.com/gaurav0107/superhuman"
CLAUDE_BIN="${CLAUDE_BIN:-claude}"
CODEX_SKILLS_DIR="${CODEX_SKILLS_DIR:-$HOME/.codex/skills}"
SUPERHUMAN_SRC="${SUPERHUMAN_SRC:-$HOME/src/superhuman}"

SKIP_ECC=0
DO_CODEX=0
DRY_RUN=0

# --- pretty output ------------------------------------------------------------
if [ -t 1 ]; then
  BOLD=$'\033[1m'; DIM=$'\033[2m'; GREEN=$'\033[32m'; YELLOW=$'\033[33m'
  RED=$'\033[31m'; CYAN=$'\033[36m'; RESET=$'\033[0m'
else
  BOLD=""; DIM=""; GREEN=""; YELLOW=""; RED=""; CYAN=""; RESET=""
fi
info()  { printf '%s\n' "${CYAN}==>${RESET} $*"; }
ok()    { printf '%s\n' "${GREEN}  ✓${RESET} $*"; }
warn()  { printf '%s\n' "${YELLOW}  !${RESET} $*" >&2; }
err()   { printf '%s\n' "${RED}  ✗${RESET} $*" >&2; }

usage() {
  # Print the leading comment block (lines 2..first non-comment line), stripping '# '.
  awk 'NR==1{next} /^#/{sub(/^# ?/,""); print; next} {exit}' "$0"
  exit "${1:-0}"
}

# --- args ---------------------------------------------------------------------
while [ $# -gt 0 ]; do
  case "$1" in
    --skip-ecc)        SKIP_ECC=1 ;;
    --codex)           DO_CODEX=1 ;;
    --dry-run|-n)      DRY_RUN=1 ;;
    -h|--help)         usage 0 ;;
    *) err "unknown option: $1"; usage 1 ;;
  esac
  shift
done

# Run a command, or just echo it under --dry-run.
run() {
  if [ "$DRY_RUN" = "1" ]; then
    printf '%s\n' "${DIM}+ $*${RESET}"
    return 0
  fi
  "$@"
}

# --- prerequisites ------------------------------------------------------------
# The agents shell out to these at runtime. Missing ones warn (not fatal) so the
# plugin still installs; the user can install tooling afterwards.
check_prereqs() {
  info "Checking prerequisites"
  local missing=0
  for tool in git gh jq python3; do
    if command -v "$tool" >/dev/null 2>&1; then
      ok "$tool"
    else
      warn "$tool not found — needed at runtime (see README Prerequisites)"
      missing=1
    fi
  done
  if command -v gh >/dev/null 2>&1; then
    if gh auth status >/dev/null 2>&1; then
      ok "gh authenticated"
    else
      warn "gh is not authenticated — run 'gh auth login' before contributing"
    fi
  fi
  [ "$missing" = "0" ] || warn "Some tools are missing; install them from the README before running the workflow."
}

# --- claude plugin install ----------------------------------------------------
# Each entry: "<marketplace source>|<plugin@marketplace>|<label>"
# The marketplace NAME (right of @) comes from each repo's marketplace.json —
# it is NOT the repo slug (superpowers-marketplace's is "superpowers-marketplace",
# ECC's is "ecc"). Verified against the live marketplace.json files.
PLUGINS=(
  "https://github.com/obra/superpowers-marketplace|superpowers@superpowers-marketplace|superpowers (required)"
  "https://github.com/affaan-m/everything-claude-code|ecc@ecc|everything-claude-code / ECC (recommended)"
  "https://github.com/gaurav0107/superhuman|superhuman@superhuman|superhuman"
)

install_claude_plugins() {
  if ! command -v "$CLAUDE_BIN" >/dev/null 2>&1; then
    warn "Claude Code CLI ('$CLAUDE_BIN') not found on PATH — skipping Claude install."
    warn "Install Claude Code, then re-run this script, or run these inside Claude Code:"
    for entry in "${PLUGINS[@]}"; do
      IFS='|' read -r src plugin label <<<"$entry"
      [ "$SKIP_ECC" = "1" ] && [[ "$plugin" == ecc@* ]] && continue
      printf '    /plugin marketplace add %s\n' "$src"
      printf '    /plugin install %s\n' "$plugin"
    done
    return 1
  fi

  info "Installing Claude Code plugins via ${BOLD}$CLAUDE_BIN${RESET}"
  for entry in "${PLUGINS[@]}"; do
    IFS='|' read -r src plugin label <<<"$entry"
    if [ "$SKIP_ECC" = "1" ] && [[ "$plugin" == ecc@* ]]; then
      warn "Skipping $label (--skip-ecc)"
      continue
    fi
    info "$label"
    # `marketplace add` is idempotent for an already-known marketplace; tolerate
    # a non-zero exit (already added) and continue to install.
    run "$CLAUDE_BIN" plugin marketplace add "$src" || warn "marketplace add returned non-zero (already added?) — continuing"
    if run "$CLAUDE_BIN" plugin install "$plugin"; then
      ok "$plugin"
    elif run "$CLAUDE_BIN" plugin install "${plugin%@*}"; then
      # Self-heal if the marketplace was renamed: install by bare plugin name,
      # letting the CLI resolve it across all known marketplaces.
      ok "${plugin%@*} (resolved without marketplace pin)"
    else
      err "failed to install $plugin"
      [[ "$plugin" == superpowers@* ]] && err "superpowers is REQUIRED — superhuman's planner/builder will fail without it."
    fi
  done
}

# --- codex install ------------------------------------------------------------
install_codex() {
  info "Installing for Codex"
  if [ ! -d "$SUPERHUMAN_SRC/.git" ]; then
    run git clone "$REPO_URL" "$SUPERHUMAN_SRC"
  else
    ok "repo already cloned at $SUPERHUMAN_SRC"
  fi
  run mkdir -p "$CODEX_SKILLS_DIR"
  local link="$CODEX_SKILLS_DIR/superhuman"
  if [ -L "$link" ] || [ -e "$link" ]; then
    ok "Codex skill already linked at $link"
  else
    run ln -s "$SUPERHUMAN_SRC/skills/superhuman" "$link"
    ok "linked $link -> $SUPERHUMAN_SRC/skills/superhuman"
  fi
  warn "Codex has no plugin marketplace: install superpowers/ECC dependencies manually if you use their skills."
}

# --- main ---------------------------------------------------------------------
main() {
  printf '%s\n' "${BOLD}superhuman installer${RESET} ${DIM}($REPO_URL)${RESET}"
  [ "$DRY_RUN" = "1" ] && warn "dry-run: no changes will be made"
  check_prereqs
  install_claude_plugins || true
  [ "$DO_CODEX" = "1" ] && install_codex
  printf '\n%s\n' "${GREEN}${BOLD}Done.${RESET}"
  printf '%s\n' "Restart Claude Code (or run ${BOLD}/reload-plugins${RESET}), then try: ${BOLD}/contribute${RESET}"
}

main
