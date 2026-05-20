# tests/scripts/test_drift_linter.sh
#!/usr/bin/env bash
set -euo pipefail
export CLAUDE_PLUGIN_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

SCRIPT="$CLAUDE_PLUGIN_ROOT/scripts/builder/drift_linter.sh"

# ---------------------------------------------------------------------------
# Helper: make a temp git repo with local identity, cleaned up on exit
# ---------------------------------------------------------------------------
make_repo() {
  local dir
  dir=$(mktemp -d)
  git -C "$dir" init -q
  git -C "$dir" -c user.name="Test" -c user.email="test@example.com" \
    -c commit.gpgsign=false commit --allow-empty -q -m "initial"
  echo "$dir"
}

run_linter() {
  local sd="$1" wd="$2" issue="$3" base="$4"
  bash "$SCRIPT" \
    --state-dir "$sd" \
    --workdir   "$wd" \
    --owner-repo "test/repo" \
    --issue-number "$issue" \
    --diff-base "$base"
}

# ---------------------------------------------------------------------------
# Fixture A — 5a: newsfragment filename mismatches issue number
# ---------------------------------------------------------------------------
TMPA=$(mktemp -d)
WDA=$(make_repo)
trap 'rm -rf "$TMPA" "$WDA"' EXIT

SDA="$TMPA/state"
BASE_A=$(git -C "$WDA" rev-parse HEAD)

mkdir -p "$WDA/newsfragments"
printf 'Bug fix.\n' > "$WDA/newsfragments/9999.bugfix.rst"
git -C "$WDA" add newsfragments/9999.bugfix.rst
git -C "$WDA" -c user.name="Test" -c user.email="test@example.com" \
  -c commit.gpgsign=false commit -q -m "fix: some bug"

run_linter "$SDA" "$WDA" "12345" "$BASE_A"

[ -f "$SDA/mistakes.md" ] || { echo "FAIL A: mistakes.md not created"; exit 1; }
grep -q "builder:review-drift" "$SDA/mistakes.md" || { echo "FAIL A: tag missing"; exit 1; }
# Message should mention the mismatched fragment name (9999) or the expected issue (12345)
grep -qE "(9999|12345)" "$SDA/mistakes.md" || { echo "FAIL A: no fragment/issue reference in message"; exit 1; }

echo "PASS fixture A (5a newsfragment mismatch)"

# ---------------------------------------------------------------------------
# Fixture B — 5b: removed symbol still referenced in commit body
# ---------------------------------------------------------------------------
TMPB=$(mktemp -d)
WDB=$(make_repo)
trap 'rm -rf "$TMPA" "$WDA" "$TMPB" "$WDB"' EXIT

SDB="$TMPB/state"

# Create a file that defines removed_func, commit it — this becomes our BASE_B
printf 'def removed_func():\n    pass\n' > "$WDB/module.py"
git -C "$WDB" add module.py
git -C "$WDB" -c user.name="Test" -c user.email="test@example.com" \
  -c commit.gpgsign=false commit -q -m "add removed_func"

BASE_B=$(git -C "$WDB" rev-parse HEAD)

# Remove the function; commit body still mentions removed_func
printf '# empty\n' > "$WDB/module.py"
git -C "$WDB" add module.py
git -C "$WDB" -c user.name="Test" -c user.email="test@example.com" \
  -c commit.gpgsign=false commit -q -m "refactor: drop removed_func from module"

run_linter "$SDB" "$WDB" "42" "$BASE_B"

[ -f "$SDB/mistakes.md" ] || { echo "FAIL B: mistakes.md not created"; exit 1; }
grep -q "removed_func" "$SDB/mistakes.md" || { echo "FAIL B: removed symbol not mentioned"; exit 1; }

echo "PASS fixture B (5b removed symbol in commit body)"

# ---------------------------------------------------------------------------
# Fixture C — 5c: provider name leaks into core file
# ---------------------------------------------------------------------------
TMPC=$(mktemp -d)
WDC=$(make_repo)
trap 'rm -rf "$TMPA" "$WDA" "$TMPB" "$WDB" "$TMPC" "$WDC"' EXIT

SDC="$TMPC/state"

# Commit providers/aws/ — this becomes our BASE_C
mkdir -p "$WDC/providers/aws"
printf '# aws provider\n' > "$WDC/providers/aws/__init__.py"
git -C "$WDC" add providers/
git -C "$WDC" -c user.name="Test" -c user.email="test@example.com" \
  -c commit.gpgsign=false commit -q -m "add aws provider"

BASE_C=$(git -C "$WDC" rev-parse HEAD)

# Edit a core file that mentions aws (use import form so word boundary matches)
mkdir -p "$WDC/core"
printf 'from aws import connect\n' > "$WDC/core/connections.py"
git -C "$WDC" add core/connections.py
git -C "$WDC" -c user.name="Test" -c user.email="test@example.com" \
  -c commit.gpgsign=false commit -q -m "core: add connection helper"

run_linter "$SDC" "$WDC" "99" "$BASE_C"

[ -f "$SDC/mistakes.md" ] || { echo "FAIL C: mistakes.md not created"; exit 1; }
grep -q "aws" "$SDC/mistakes.md" || { echo "FAIL C: provider name not mentioned"; exit 1; }

echo "PASS fixture C (5c provider leak into core)"

# ---------------------------------------------------------------------------
# Fixture D — clean: no triggers; assert no mistakes recorded
# ---------------------------------------------------------------------------
TMPD=$(mktemp -d)
WDD=$(make_repo)
trap 'rm -rf "$TMPA" "$WDA" "$TMPB" "$WDB" "$TMPC" "$WDC" "$TMPD" "$WDD"' EXIT

SDD="$TMPD/state"
BASE_D=$(git -C "$WDD" rev-parse HEAD)

# A perfectly normal commit: no newsfragments, no removed symbols, no providers dir
printf 'x = 1\n' > "$WDD/app.py"
git -C "$WDD" add app.py
git -C "$WDD" -c user.name="Test" -c user.email="test@example.com" \
  -c commit.gpgsign=false commit -q -m "chore: add placeholder"

run_linter "$SDD" "$WDD" "777" "$BASE_D"

if [ -f "$SDD/mistakes.md" ]; then
  echo "FAIL D: mistakes.md should not exist for clean fixture"
  exit 1
fi

echo "PASS fixture D (clean — no mistakes)"

echo "OK test_drift_linter.sh"
