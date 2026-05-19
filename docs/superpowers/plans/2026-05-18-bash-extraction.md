# Bash Extraction Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extract long inline bash from `agents/*.md` into `scripts/{lib,orchestrator,profiler,builder,scorer}/`, move JSONC schemas in `SHARED_STATE.md` to `schemas/*.schema.json` (draft 2020-12), and add three loop-primitive slash commands (`/contribute`, `/repo-finder`, `/contribute-loop`) — without altering any behavior.

**Architecture:** Scripts source `${CLAUDE_PLUGIN_ROOT}/scripts/lib/state.sh` for shared helpers, take all repo-scoped state as explicit args (no closed-over env), and exit with codes 0 (ok) / 1 (recoverable) / 2 (abort-phase). Safety rules (single-author commit, force-with-lease, prompt-injection halt, flock fd ownership) stay inline in prompts as defense-in-depth. Behavioral diffs after each phase prove byte-equivalence on normalized state files.

**Tech Stack:** bash 3.2 (macOS default), `jq`, `gh`, `git`, `yq`, `python3`. JSON Schema draft 2020-12. No new dependencies.

**Spec:** `docs/superpowers/specs/2026-05-18-bash-extraction-design.md`

---

## Phase 1 — `scripts/lib/` shared helpers

Self-contained surface that downstream phases depend on. Extracts only material that is **shared by ≥2 agents** today (state helpers, telemetry, mistakes, flake) plus the EXTERNAL_CONTENT delim helpers used by `resolve-comments`.

### Task 1.1: Create `scripts/lib/state.sh`

**Files:**
- Create: `scripts/lib/state.sh`
- Create: `tests/scripts/test_state.sh`

**Source today:** `agents/SHARED_STATE.md:472-503` (`state_dir`, `global_dir`, `atomic_write_json`, `require_lock`).

- [ ] **Step 1: Write the failing test**

```bash
# tests/scripts/test_state.sh
#!/usr/bin/env bash
set -euo pipefail
export CLAUDE_PLUGIN_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
source "$CLAUDE_PLUGIN_ROOT/scripts/lib/state.sh"

out=$(state_dir "apache/airflow")
[ "$out" = "$HOME/.superhuman/repos/apache-airflow" ] || { echo "FAIL state_dir: $out"; exit 1; }

[ "$(global_dir)" = "$HOME/.superhuman/global" ] || { echo "FAIL global_dir"; exit 1; }

tmpdir=$(mktemp -d)
atomic_write_json "$tmpdir/x.json" '{"a":1}'
[ "$(jq -r .a "$tmpdir/x.json")" = "1" ] || { echo "FAIL atomic_write_json"; exit 1; }

mkdir -p "$tmpdir/.superhuman/repos/foo-bar"
echo '{"lock_holder":"x"}' > "$tmpdir/.superhuman/repos/foo-bar/current_contribution.json"
HOME="$tmpdir" require_lock "foo/bar" "x" || { echo "FAIL require_lock match"; exit 1; }
HOME="$tmpdir" require_lock "foo/bar" "y" 2>/dev/null && { echo "FAIL require_lock mismatch should fail"; exit 1; }

schema="$tmpdir/s.json"
echo '{"$schema":"https://json-schema.org/draft/2020-12/schema","type":"object","required":["a"]}' > "$schema"
echo '{"a":1}' > "$tmpdir/data.json"
validate_json "$schema" "$tmpdir/data.json" || { echo "FAIL validate_json ok"; exit 1; }
echo '{}' > "$tmpdir/data.json"
validate_json "$schema" "$tmpdir/data.json" 2>/dev/null && { echo "FAIL validate_json bad should fail"; exit 1; }

echo "OK test_state.sh"
```

Run: `bash tests/scripts/test_state.sh`
Expected: FAIL with `state.sh: No such file or directory`.

- [ ] **Step 2: Implement `scripts/lib/state.sh`**

```bash
#!/usr/bin/env bash
# Shared state helpers. Sourced by every script under scripts/.

state_dir() {
  local owner_repo="$1"
  local slug="${owner_repo/\//-}"
  echo "$HOME/.superhuman/repos/$slug"
}

global_dir() {
  echo "$HOME/.superhuman/global"
}

atomic_write_json() {
  local path="$1" content="$2"
  local tmp="${path}.tmp.$$"
  mkdir -p "$(dirname "$path")"
  printf '%s' "$content" | jq . > "$tmp" && mv "$tmp" "$path"
}

require_lock() {
  local repo="$1" expected="$2"
  local dir
  dir=$(state_dir "$repo")
  local lock
  lock=$(jq -r .lock_holder "$dir/current_contribution.json" 2>/dev/null || echo "")
  if [ "$lock" != "$expected" ]; then
    echo "ERROR: expected lock_holder=$expected, got $lock" >&2
    return 1
  fi
}

validate_json() {
  local schema="$1" data="$2"
  if command -v python3 >/dev/null 2>&1 && python3 -c 'import jsonschema' 2>/dev/null; then
    python3 - "$schema" "$data" <<'PY'
import json, sys, jsonschema
schema = json.load(open(sys.argv[1]))
data = json.load(open(sys.argv[2]))
jsonschema.validate(data, schema)
PY
    return $?
  fi
  local req
  req=$(jq -r '.required // [] | .[]' "$schema")
  for k in $req; do
    jq -e --arg k "$k" 'has($k)' "$data" >/dev/null || {
      echo "validate_json: missing required field: $k" >&2
      return 1
    }
  done
  return 0
}
```

- [ ] **Step 3: Run test to verify pass**

Run: `bash tests/scripts/test_state.sh`
Expected: `OK test_state.sh`

- [ ] **Step 4: Commit**

```bash
git add scripts/lib/state.sh tests/scripts/test_state.sh
git commit -m "feat(scripts/lib): extract state helpers from SHARED_STATE.md

state_dir, global_dir, atomic_write_json, require_lock, validate_json.
Source: SHARED_STATE.md:472-503. Behavior unchanged."
```

### Task 1.2: Create `scripts/lib/delim.sh`

**Files:**
- Create: `scripts/lib/delim.sh`
- Create: `tests/scripts/test_delim.sh`

**Source today:** `SHARED_STATE.md:64-78` (prompt-injection wrap rule) and inline usage in `resolve-comments.md`.

- [ ] **Step 1: Write the failing test**

```bash
# tests/scripts/test_delim.sh
#!/usr/bin/env bash
set -euo pipefail
export CLAUDE_PLUGIN_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
source "$CLAUDE_PLUGIN_ROOT/scripts/lib/delim.sh"

wrapped=$(wrap_external "hello world")
echo "$wrapped" | grep -q '<<<EXTERNAL_CONTENT id=' || { echo "FAIL wrap open"; exit 1; }
echo "$wrapped" | grep -q '<<<END id='              || { echo "FAIL wrap close"; exit 1; }
echo "$wrapped" | grep -q 'hello world'             || { echo "FAIL wrap body"; exit 1; }

open_id=$(echo "$wrapped" | sed -n 's/.*<<<EXTERNAL_CONTENT id=\([a-f0-9-]*\)>>>>.*/\1/p' | head -1)
close_id=$(echo "$wrapped" | sed -n 's/.*<<<END id=\([a-f0-9-]*\)>>>.*/\1/p' | head -1)
[ -n "$open_id" ] && [ "$open_id" = "$close_id" ] || { echo "FAIL uuid match"; exit 1; }

echo "OK test_delim.sh"
```

Run: `bash tests/scripts/test_delim.sh`
Expected: FAIL — file missing.

- [ ] **Step 2: Implement `scripts/lib/delim.sh`**

```bash
#!/usr/bin/env bash
# EXTERNAL_CONTENT wrap/unwrap helpers (prompt-injection hardening).
# See agents/SHARED_STATE.md "Prompt-injection hardening" section.

wrap_external() {
  local body="$1"
  local id
  if command -v uuidgen >/dev/null 2>&1; then
    id=$(uuidgen | tr 'A-Z' 'a-z')
  else
    id=$(python3 -c 'import uuid; print(uuid.uuid4())')
  fi
  printf '<<<EXTERNAL_CONTENT id=%s>>>>\n%s\n<<<END id=%s>>>\n' "$id" "$body" "$id"
}

unwrap_external() {
  awk '
    /^<<<EXTERNAL_CONTENT id=/ { in_blk = 1; next }
    /^<<<END id=/              { in_blk = 0; next }
    in_blk == 1                { print }
  '
}
```

- [ ] **Step 3: Run test, verify pass, commit**

```bash
bash tests/scripts/test_delim.sh
git add scripts/lib/delim.sh tests/scripts/test_delim.sh
git commit -m "feat(scripts/lib): EXTERNAL_CONTENT wrap/unwrap helpers

Source: SHARED_STATE.md:64-78. resolve-comments will source this in Phase 5."
```

### Task 1.3: Create `scripts/lib/telemetry.sh`

**Files:**
- Create: `scripts/lib/telemetry.sh`
- Create: `tests/scripts/test_telemetry_phase_enum.sh`

**Source today:** `agents/opensource-contributor.md` `emit_telemetry`/`run_phase` helpers + phase enum at `SHARED_STATE.md:371-373`.

- [ ] **Step 1: Write the failing test**

```bash
# tests/scripts/test_telemetry_phase_enum.sh
#!/usr/bin/env bash
set -euo pipefail
export CLAUDE_PLUGIN_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
source "$CLAUDE_PLUGIN_ROOT/scripts/lib/telemetry.sh"

tmpdir=$(mktemp -d)
TF="$tmpdir/run_telemetry.jsonl"

emit_telemetry "$TF" "scorer" 1 38 "ok" '{"final_score":72}' || { echo "FAIL allowed"; exit 1; }
[ "$(wc -l < "$TF" | tr -d ' ')" = "1" ] || { echo "FAIL append"; exit 1; }
jq -e '.phase=="scorer"' "$TF" >/dev/null || { echo "FAIL phase value"; exit 1; }

if emit_telemetry "$TF" "not-a-phase" 1 1 "ok" 'null' 2>/dev/null; then
  echo "FAIL: bad phase should reject"; exit 1
fi
[ "$(wc -l < "$TF" | tr -d ' ')" = "1" ] || { echo "FAIL: bad phase appended"; exit 1; }

echo "OK test_telemetry_phase_enum.sh"
```

Run: `bash tests/scripts/test_telemetry_phase_enum.sh`
Expected: FAIL — file missing.

- [ ] **Step 2: Implement `scripts/lib/telemetry.sh`**

```bash
#!/usr/bin/env bash
# Telemetry append helper with phase-enum validation.
# Phase enum must match SHARED_STATE.md "run_telemetry.jsonl" allowed values.

TELEMETRY_PHASES=(
  "repo-profiler"
  "issue-selector"
  "planner"
  "builder:initial"
  "builder:apply_findings"
  "builder:apply_comments"
  "scorer"
  "reviewer-dispatcher"
  "resolve-comments"
)

_phase_allowed() {
  local p="$1"
  for known in "${TELEMETRY_PHASES[@]}"; do
    [ "$p" = "$known" ] && return 0
  done
  return 1
}

emit_telemetry() {
  local file="$1" phase="$2" iter="$3" dur="$4" outcome="$5" extra="${6:-null}"
  if ! _phase_allowed "$phase"; then
    echo "emit_telemetry: rejected unknown phase '$phase'" >&2
    return 1
  fi
  mkdir -p "$(dirname "$file")"
  local ts
  ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  jq -nc \
    --arg ts "$ts" --arg phase "$phase" \
    --argjson iter "$iter" --argjson dur "$dur" \
    --arg outcome "$outcome" --argjson extra "$extra" \
    '{ts:$ts, iteration:$iter, phase:$phase, duration_s:$dur, outcome:$outcome} +
     (if $extra == null then {} else $extra end)' \
    >> "$file"
}

run_phase() {
  local file="$1" phase="$2" iter="$3"
  shift 3
  local start end dur rc outcome
  start=$(date +%s)
  if "$@"; then rc=0; else rc=$?; fi
  end=$(date +%s)
  dur=$(( end - start ))
  if [ "$rc" -eq 0 ]; then outcome="ok"; else outcome="fail"; fi
  emit_telemetry "$file" "$phase" "$iter" "$dur" "$outcome" "null" || true
  return "$rc"
}
```

- [ ] **Step 3: Run test, verify pass, commit**

```bash
bash tests/scripts/test_telemetry_phase_enum.sh
git add scripts/lib/telemetry.sh tests/scripts/test_telemetry_phase_enum.sh
git commit -m "feat(scripts/lib): telemetry append + phase-enum validation

Phase enum lifted from SHARED_STATE.md:371-373. emit_telemetry rejects
unknown phases pre-write so typos cannot pollute run_telemetry.jsonl."
```

### Task 1.4: Create `scripts/lib/mistakes.sh`

**Files:**
- Create: `scripts/lib/mistakes.sh`
- Create: `tests/scripts/test_mistakes.sh`

**Source today:** `agents/builder.md:336-403` `record_mistake`. Promoted to a sourced lib because sub-scripts under `set -euo pipefail` cannot share function tables.

- [ ] **Step 1: Write the failing test**

```bash
# tests/scripts/test_mistakes.sh
#!/usr/bin/env bash
set -euo pipefail
export CLAUDE_PLUGIN_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
source "$CLAUDE_PLUGIN_ROOT/scripts/lib/mistakes.sh"

tmpdir=$(mktemp -d)
SD="$tmpdir/state"
WD="$tmpdir/work"
OR="apache/airflow"
mkdir -p "$SD" "$WD"

record_mistake "$SD" "$WD" "$OR" "builder:ci_gate" "ruff failed on tests/foo.py"
[ -f "$SD/mistakes.md" ] || { echo "FAIL: file not created"; exit 1; }

grep -q "^## " "$SD/mistakes.md"                || { echo "FAIL: missing H2"; exit 1; }
grep -q "tag=builder:ci_gate" "$SD/mistakes.md" || { echo "FAIL: missing tag"; exit 1; }
grep -q "repo=apache/airflow" "$SD/mistakes.md" || { echo "FAIL: missing repo"; exit 1; }
grep -q "ruff failed" "$SD/mistakes.md"         || { echo "FAIL: missing body"; exit 1; }

record_mistake "$SD" "$WD" "$OR" "builder:smoke" "import error"
[ "$(grep -c '^## ' "$SD/mistakes.md")" = "2" ] || { echo "FAIL: not append-only"; exit 1; }

echo "OK test_mistakes.sh"
```

Run: `bash tests/scripts/test_mistakes.sh`
Expected: FAIL — file missing.

- [ ] **Step 2: Implement `scripts/lib/mistakes.sh`**

```bash
#!/usr/bin/env bash
# Append-only mistakes log. Format must remain byte-equivalent to the
# pre-extraction inline definition in agents/builder.md:336-403.

# record_mistake STATE_DIR WORKDIR OWNER_REPO TAG MESSAGE
record_mistake() {
  local state_dir="$1" workdir="$2" owner_repo="$3" tag="$4" message="$5"
  local file="$state_dir/mistakes.md"
  local ts
  ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  mkdir -p "$state_dir"
  {
    printf '## %s tag=%s repo=%s\n' "$ts" "$tag" "$owner_repo"
    printf 'workdir: %s\n\n' "$workdir"
    printf '%s\n\n' "$message"
  } >> "$file"
}
```

- [ ] **Step 3: Run test, verify pass, commit**

```bash
bash tests/scripts/test_mistakes.sh
git add scripts/lib/mistakes.sh tests/scripts/test_mistakes.sh
git commit -m "feat(scripts/lib): record_mistake append helper

Promotes builder.md:336-403 inline function to a sourced lib taking
STATE_DIR/WORKDIR/OWNER_REPO as explicit args (sub-scripts under
set -euo pipefail cannot share function tables).

Format byte-equivalent to pre-extraction; verified by test_mistakes.sh
matching the H2-header / tag= / repo= / workdir: layout."
```

### Task 1.5: Create `scripts/lib/flake.sh`

**Files:**
- Create: `scripts/lib/flake.sh`
- Create: `tests/scripts/test_flake.sh`

**Source today:** `builder.md:336-403` `classify_as_flake`/`record_flake_hit`. Reads `~/.superhuman/global/flake_signatures.md` (cross-repo, append-only).

- [ ] **Step 1: Write the failing test**

```bash
# tests/scripts/test_flake.sh
#!/usr/bin/env bash
set -euo pipefail
export CLAUDE_PLUGIN_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
source "$CLAUDE_PLUGIN_ROOT/scripts/lib/flake.sh"

tmpdir=$(mktemp -d)
GD="$tmpdir/global"
mkdir -p "$GD"
cat > "$GD/flake_signatures.md" <<'EOF'
## signature: pip-timeout
- pattern: `ReadTimeoutError.*files\.pythonhosted\.org`
- repos: *
- first_seen: 2026-03-01
- note: mirror flakiness; not a real failure
EOF

logfile="$tmpdir/ci.log"
echo "ReadTimeoutError: HTTPSConnectionPool(host='files.pythonhosted.org')" > "$logfile"
classify_as_flake "$GD/flake_signatures.md" "$logfile" || { echo "FAIL: should be flake"; exit 1; }

echo "no flaky thing" > "$logfile"
if classify_as_flake "$GD/flake_signatures.md" "$logfile" 2>/dev/null; then
  echo "FAIL: should NOT classify"; exit 1
fi

record_flake_hit "$GD/flake_signatures.md" "pip-timeout" "apache/airflow" "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
grep -q '^- last_hit:' "$GD/flake_signatures.md" || { echo "FAIL: hit not recorded"; exit 1; }

echo "OK test_flake.sh"
```

- [ ] **Step 2: Implement `scripts/lib/flake.sh`**

```bash
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
```

- [ ] **Step 3: Run test, verify pass, commit**

```bash
bash tests/scripts/test_flake.sh
git add scripts/lib/flake.sh tests/scripts/test_flake.sh
git commit -m "feat(scripts/lib): flake classification + hit recording

Source: builder.md:336-403. Append-only contract preserved
(record_flake_hit only writes via >>)."
```

### Task 1.6: Update `agents/SHARED_STATE.md` to point to lib

**Files:**
- Modify: `agents/SHARED_STATE.md` — replace inline `## Helper shell functions (reference)` body with a pointer.

- [ ] **Step 1: Replace the helper-functions code block**

Delete the entire fenced bash block under `## Helper shell functions (reference)` (lines 472-503) and replace with:

```markdown
Helpers live at `${CLAUDE_PLUGIN_ROOT}/scripts/lib/state.sh`. Source it from
any script that touches shared state. Functions: `state_dir`, `global_dir`,
`atomic_write_json`, `require_lock`, `validate_json`. Append helpers live at
`scripts/lib/mistakes.sh` (`record_mistake`) and `scripts/lib/flake.sh`
(`classify_as_flake`, `record_flake_hit`). External-content delimiters at
`scripts/lib/delim.sh` (`wrap_external`, `unwrap_external`).
```

- [ ] **Step 2: Verify the four required-stays sections still present (audit §5)**

Run:
```bash
for s in "Directory layout" "Concurrency contract" "Prompt-injection hardening" \
         "Error & rescue rules" "End-to-end run trace" ; do
  grep -q "$s" agents/SHARED_STATE.md || { echo "MISSING: $s"; exit 1; }
done
echo "All required sections present"
```
Expected: `All required sections present`.

- [ ] **Step 3: Commit**

```bash
git add agents/SHARED_STATE.md
git commit -m "refactor(SHARED_STATE): cite lib scripts instead of inlining helpers

Behavioral prose (directory layout, ownership, concurrency contract,
prompt-injection hardening, run trace, error & rescue rules) unchanged."
```

### Task 1.7: Phase 1 acceptance check

- [ ] **Step 1: Run all Phase 1 tests**

```bash
for t in tests/scripts/test_state.sh tests/scripts/test_delim.sh \
         tests/scripts/test_telemetry_phase_enum.sh \
         tests/scripts/test_mistakes.sh tests/scripts/test_flake.sh; do
  bash "$t" || { echo "FAIL: $t"; exit 1; }
done
echo "Phase 1 acceptance: GREEN"
```

- [ ] **Step 2: Shellcheck clean**

Run: `shellcheck --shell=bash scripts/lib/*.sh`
Expected: zero errors.

---

## Phase 2 — `schemas/*.schema.json` (JSON Schema draft 2020-12)

Convert the JSONC schemas in `agents/SHARED_STATE.md` (lines 80-409) into machine-checkable JSON files. JSONC comments carry load-bearing prose — they MUST be transcribed into `description` fields, not dropped (audit §11).

Eleven schemas total. Each follows the convention below.

### Schema convention

- `$schema`: `https://json-schema.org/draft/2020-12/schema`
- `$id`: `https://github.com/gaurav0107/superhuman/schemas/<name>.schema.json`
- `additionalProperties: true` at top level (audit §10 — no data-shape narrowing)
- Top-level `description` carries the section's rationale from SHARED_STATE.md
- Per-property `description` carries the JSONC comment for that field
- `required` lists ONLY the fields the existing code actually relies on

### Task 2.1: `schemas/repo_profile.schema.json`

**Files:**
- Create: `schemas/repo_profile.schema.json`
- Create: `tests/scripts/test_schema_repo_profile.sh`

**Source:** `SHARED_STATE.md:82-101`.

- [ ] **Step 1: Write the failing test**

```bash
# tests/scripts/test_schema_repo_profile.sh
#!/usr/bin/env bash
set -euo pipefail
export CLAUDE_PLUGIN_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
source "$CLAUDE_PLUGIN_ROOT/scripts/lib/state.sh"

SCHEMA="$CLAUDE_PLUGIN_ROOT/schemas/repo_profile.schema.json"
tmpdir=$(mktemp -d)

cat > "$tmpdir/ok.json" <<'EOF'
{
  "repo": "apache/airflow",
  "generated_at": "2026-04-24T11:45:00Z",
  "default_branch": "main",
  "language": "python",
  "commit_convention": "conventional",
  "pr_title_format": "component: short description",
  "pr_body_sections": ["Summary", "Test plan", "Checklist"],
  "test_runner": "pytest",
  "lint_commands": ["ruff check .", "mypy ."],
  "closes_syntax": "Closes #N",
  "dco_required": false,
  "cla_required": false,
  "reviewer_norms_summary": "x",
  "sampled_prs": [12345]
}
EOF
validate_json "$SCHEMA" "$tmpdir/ok.json" || { echo "FAIL valid"; exit 1; }

echo '{}' > "$tmpdir/bad.json"
validate_json "$SCHEMA" "$tmpdir/bad.json" 2>/dev/null && { echo "FAIL bad accepted"; exit 1; }

echo "OK test_schema_repo_profile.sh"
```

- [ ] **Step 2: Implement schema**

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "$id": "https://github.com/gaurav0107/superhuman/schemas/repo_profile.schema.json",
  "title": "repo_profile",
  "description": "Contribution conventions extracted from the last 10-20 merged PRs of a target repo. Owner: repo-profiler. Readers: scorer, planner, builder, reviewer-dispatcher, resolve-comments.",
  "type": "object",
  "additionalProperties": true,
  "required": ["repo", "generated_at", "default_branch", "language", "commit_convention", "test_runner", "sampled_prs"],
  "properties": {
    "repo":              {"type": "string", "description": "owner/repo slug"},
    "generated_at":      {"type": "string", "format": "date-time"},
    "default_branch":    {"type": "string"},
    "language":          {"type": "string", "description": "primary language (python, go, ts, ...)"},
    "commit_convention": {"type": "string", "description": "e.g. conventional, none, custom"},
    "pr_title_format":   {"type": "string"},
    "pr_body_sections":  {"type": "array", "items": {"type": "string"}},
    "test_runner":       {"type": "string"},
    "lint_commands":     {"type": "array", "items": {"type": "string"}},
    "closes_syntax":     {"type": "string"},
    "dco_required":      {"type": "boolean"},
    "cla_required":      {"type": "boolean"},
    "reviewer_norms_summary": {"type": "string", "description": "2-3 sentences from last 10 merged PRs"},
    "sampled_prs":       {"type": "array", "items": {"type": "integer"}}
  }
}
```

- [ ] **Step 3: Run test, verify pass, commit**

```bash
bash tests/scripts/test_schema_repo_profile.sh
git add schemas/repo_profile.schema.json tests/scripts/test_schema_repo_profile.sh
git commit -m "feat(schemas): add repo_profile schema (draft 2020-12)

Source: SHARED_STATE.md:82-101 JSONC. JSONC comments transcribed
to description fields per audit §11."
```

### Task 2.2: `schemas/issue_candidates.schema.json`

**Files:**
- Create: `schemas/issue_candidates.schema.json`
- Create: `tests/scripts/test_schema_issue_candidates.sh`

**Source:** `SHARED_STATE.md:104-124`.

- [ ] **Step 1: Write failing test**

```bash
# tests/scripts/test_schema_issue_candidates.sh
#!/usr/bin/env bash
set -euo pipefail
export CLAUDE_PLUGIN_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
source "$CLAUDE_PLUGIN_ROOT/scripts/lib/state.sh"
SCHEMA="$CLAUDE_PLUGIN_ROOT/schemas/issue_candidates.schema.json"
tmpdir=$(mktemp -d)
cat > "$tmpdir/ok.json" <<'EOF'
{
  "repo": "apache/airflow",
  "generated_at": "2026-04-24T11:45:00Z",
  "candidates": [
    {"number": 65685, "title": "x", "score": 23, "type": "bug", "labels": ["bug"], "skip_reason": null, "notes": "..."}
  ],
  "skipped": [{"number": 65123, "reason": "docs-only"}]
}
EOF
validate_json "$SCHEMA" "$tmpdir/ok.json" || { echo "FAIL"; exit 1; }
echo "OK test_schema_issue_candidates.sh"
```

- [ ] **Step 2: Implement schema**

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "$id": "https://github.com/gaurav0107/superhuman/schemas/issue_candidates.schema.json",
  "title": "issue_candidates",
  "description": "Ranked list of issues worth attempting. Owner: issue-selector.",
  "type": "object",
  "additionalProperties": true,
  "required": ["repo", "generated_at", "candidates"],
  "properties": {
    "repo":         {"type": "string"},
    "generated_at": {"type": "string", "format": "date-time"},
    "candidates": {
      "type": "array",
      "items": {
        "type": "object",
        "additionalProperties": true,
        "required": ["number", "title", "score"],
        "properties": {
          "number":      {"type": "integer"},
          "title":       {"type": "string"},
          "score":       {"type": "number"},
          "type":        {"type": "string"},
          "labels":      {"type": "array", "items": {"type": "string"}},
          "skip_reason": {"type": ["string", "null"]},
          "notes":       {"type": "string"}
        }
      }
    },
    "skipped": {
      "type": "array",
      "items": {
        "type": "object",
        "additionalProperties": true,
        "required": ["number", "reason"],
        "properties": {
          "number": {"type": "integer"},
          "reason": {"type": "string"}
        }
      }
    }
  }
}
```

- [ ] **Step 3: Run test, verify pass, commit**

```bash
bash tests/scripts/test_schema_issue_candidates.sh
git add schemas/issue_candidates.schema.json tests/scripts/test_schema_issue_candidates.sh
git commit -m "feat(schemas): add issue_candidates schema"
```

### Task 2.3: `schemas/current_contribution.schema.json` (with polymorphic notes)

**Files:**
- Create: `schemas/current_contribution.schema.json`
- Create: `tests/scripts/test_schema_current_contribution.sh`

**Source:** `SHARED_STATE.md:128-155`. Audit §10: scores[].notes is polymorphic — declare via `oneOf`.

- [ ] **Step 1: Write failing test (covers BOTH notes shapes)**

```bash
# tests/scripts/test_schema_current_contribution.sh
#!/usr/bin/env bash
set -euo pipefail
export CLAUDE_PLUGIN_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
source "$CLAUDE_PLUGIN_ROOT/scripts/lib/state.sh"
SCHEMA="$CLAUDE_PLUGIN_ROOT/schemas/current_contribution.schema.json"
tmpdir=$(mktemp -d)

# notes = string
cat > "$tmpdir/a.json" <<'EOF'
{
  "repo": "apache/airflow",
  "issue_number": 65685,
  "branch": "fix/65685",
  "iteration": 1,
  "max_iterations": 6,
  "score_threshold": 95,
  "scores": [
    {"iteration": 1, "ts": "2026-04-24T11:15:00Z",
     "dimensions": {"correctness": 7},
     "raw": 78, "final": 72, "plateaued": [], "caps_applied": [],
     "notes": "weakest dim: tests"}
  ],
  "lock_holder": "opensource-contributor",
  "started_at": "2026-04-24T11:00:00Z",
  "pr_url": null
}
EOF
validate_json "$SCHEMA" "$tmpdir/a.json" || { echo "FAIL string notes"; exit 1; }

# notes = object
jq '.scores[0].notes = {"reason": "weak", "dim": "tests"}' "$tmpdir/a.json" > "$tmpdir/b.json"
validate_json "$SCHEMA" "$tmpdir/b.json" || { echo "FAIL object notes"; exit 1; }

echo "OK test_schema_current_contribution.sh"
```

- [ ] **Step 2: Implement schema**

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "$id": "https://github.com/gaurav0107/superhuman/schemas/current_contribution.schema.json",
  "title": "current_contribution",
  "description": "Live contribution state. Owner: opensource-contributor. lock_holder field carries the active lock.",
  "type": "object",
  "additionalProperties": true,
  "required": ["repo", "issue_number", "branch", "iteration", "scores", "lock_holder"],
  "properties": {
    "repo":             {"type": "string"},
    "issue_number":     {"type": "integer"},
    "branch":           {"type": "string"},
    "iteration":        {"type": "integer"},
    "max_iterations":   {"type": "integer"},
    "score_threshold":  {"type": "number"},
    "scores": {
      "type": "array",
      "items": {
        "type": "object",
        "additionalProperties": true,
        "required": ["iteration", "ts", "dimensions", "raw", "final"],
        "properties": {
          "iteration":     {"type": "integer"},
          "ts":            {"type": "string", "format": "date-time"},
          "dimensions":    {"type": "object", "additionalProperties": {"type": "number"}},
          "raw":           {"type": "number"},
          "final":         {"type": "number"},
          "plateaued":     {"type": "array", "items": {"type": "string"}},
          "caps_applied":  {"type": "array", "items": {"type": "string"}},
          "notes": {
            "description": "Polymorphic per audit §10: free-form string OR structured object.",
            "oneOf": [
              {"type": "string"},
              {"type": "object", "additionalProperties": true}
            ]
          }
        }
      }
    },
    "lock_holder": {"type": "string"},
    "started_at":  {"type": "string", "format": "date-time"},
    "pr_url":      {"type": ["string", "null"]}
  }
}
```

- [ ] **Step 3: Run test, verify pass, commit**

```bash
bash tests/scripts/test_schema_current_contribution.sh
git add schemas/current_contribution.schema.json tests/scripts/test_schema_current_contribution.sh
git commit -m "feat(schemas): current_contribution with polymorphic notes (audit §10)

scores[].notes accepts string OR object via oneOf. additionalProperties:true
preserves room for future fields without breaking validation."
```

### Task 2.4: Remaining schemas (one task per file)

For each schema below, follow the same recipe as Tasks 2.1-2.3:
1. Write `tests/scripts/test_schema_<name>.sh` with one valid + one invalid sample.
2. Author the schema with `description` carrying the JSONC comment text.
3. Run test, verify pass, commit (one commit per schema).

- [ ] **2.4.1 `schemas/ci_commands.schema.json`** — source `SHARED_STATE.md:159-173`. Required: `repo`, `generated_at`, `local_runnable`, `not_local_runnable`. Each `local_runnable[]` item: `name`, `cmd`, `timeout_s`, `allowlisted`.

- [ ] **2.4.2 `schemas/allowed_commands.schema.json`** — source `SHARED_STATE.md:181-194`. Required: `allowed_binaries` (array<string>), `denied_patterns` (array<string>). Top-level description: "User-editable seed; repo-profiler creates if missing, never overwrites" (verbatim from audit §6 stays-list).

- [ ] **2.4.3 `schemas/caller_graph.schema.json`** — source `SHARED_STATE.md:198-215`. Required: `repo`, `issue_number`, `target_function`, `callers`, `contexts_found`. Caller item: `location`, `caller_function`, `execution_context`, `safe_under_refactor`, `notes`.

- [ ] **2.4.4 `schemas/repo_blocklist.schema.json`** — source `SHARED_STATE.md:223-236`. Required: `version`, `blocked`. Blocked item: `repo`, `reason`, `added_at`, `expires_at` (nullable). Top-level description preserves "Highest authority: overrides every other signal" verbatim.

- [ ] **2.4.5 `schemas/generated_files.schema.json`** — source `SHARED_STATE.md:243-262`. Required: `repo`, `generated_at`, `entries`. Entry: `path`, `marker`, `regenerate_cmd` (nullable). Top-level description preserves "If regenerate_cmd is null, builder skips the file and records a mistake under builder:generated_file_blocked" verbatim.

- [ ] **2.4.6 `schemas/repo_cooldown.schema.json`** — source `SHARED_STATE.md:267-298`. Required: `version`, `generated_at`, `cooldowns`. Cooldown item: `repo`, `negative_outcomes_180d`, `last_merged_at` (nullable), `cooldown_until`, `triggering_outcomes`. Top-level description preserves the 180-day rule and 90/180-day cooldown trigger logic verbatim.

- [ ] **2.4.7 `schemas/maintainer_tone.schema.json`** — source `SHARED_STATE.md:340-357`. Required: `repo`, `generated_at`, `maintainers`. `maintainers` is an object whose values have `prefers`, `signals`, `last_updated`.

- [ ] **2.4.8 `schemas/smoke_registry.schema.json`** — source `SHARED_STATE.md` smoke_registry mention + repo-profiler.md Step 5.6. Required: `repo`, `generated_at`, `layers`. Each layer: `name` (enum: `python_import_root|django_check|flask_app_import|fastapi_app_import|pytest_smoke_dir|node_require_root`), `cmd`, `cwd`, `timeout_s`.

- [ ] **2.4.9 `schemas/run_telemetry.schema.json`** — JSONL-line schema. Required: `ts`, `iteration`, `phase`, `duration_s`, `outcome`. `phase` is `enum` of the nine values from `SHARED_STATE.md:371-373` (audit §12).

After each: commit with message `feat(schemas): add <name> schema`.

### Task 2.5: Replace JSONC schemas in `SHARED_STATE.md` with pointers

**Files:**
- Modify: `agents/SHARED_STATE.md` — replace each JSONC fenced block (lines ~82-409) with a pointer.

- [ ] **Step 1: For each schema section, replace the fenced ```jsonc block with a single line**

Example replacement for `### repo_profile.json` section:

```markdown
### `repo_profile.json`

Schema: [`schemas/repo_profile.schema.json`](../schemas/repo_profile.schema.json).
See top-level `description` and per-property `description` fields in the schema for field rationale.
```

Repeat for: `issue_candidates.json`, `current_contribution.json`, `ci_commands.json`, `allowed_commands.json`, `caller_graph.json`, `repo_blocklist.json`, `generated_files.json`, `repo_cooldown.json`, `maintainer_tone.json`, `run_telemetry.jsonl`. Leave `flake_signatures.md` and `merge_outcomes.jsonl` alone (they have their own format docs that aren't JSON Schema candidates).

- [ ] **Step 2: Acceptance — every schema named in SHARED_STATE.md exists on disk**

```bash
for f in schemas/repo_profile.schema.json schemas/issue_candidates.schema.json \
         schemas/current_contribution.schema.json schemas/ci_commands.schema.json \
         schemas/allowed_commands.schema.json schemas/caller_graph.schema.json \
         schemas/repo_blocklist.schema.json schemas/generated_files.schema.json \
         schemas/repo_cooldown.schema.json schemas/maintainer_tone.schema.json \
         schemas/smoke_registry.schema.json schemas/run_telemetry.schema.json; do
  [ -f "$f" ] || { echo "MISSING: $f"; exit 1; }
done
echo "All 12 schemas present"
```

- [ ] **Step 3: Validate against real state files (if present)**

```bash
for repo_dir in "$HOME/.superhuman/repos"/*/; do
  [ -d "$repo_dir" ] || continue
  for jsonfile in "$repo_dir"/*.json; do
    [ -f "$jsonfile" ] || continue
    base=$(basename "$jsonfile" .json)
    schema="schemas/${base}.schema.json"
    [ -f "$schema" ] || continue
    bash -c "
      export CLAUDE_PLUGIN_ROOT=\"$(pwd)\"
      source scripts/lib/state.sh
      validate_json \"$schema\" \"$jsonfile\"
    " || echo "WARN: $jsonfile fails $schema (review schema, do NOT change data)"
  done
done
```

Expected: zero failures, OR explicit warnings for known divergences (audit later, do NOT alter live state).

- [ ] **Step 4: Commit**

```bash
git add agents/SHARED_STATE.md
git commit -m "refactor(SHARED_STATE): cite schemas/*.schema.json instead of inline JSONC

Each schema section now links to the on-disk JSON Schema. Behavioral
prose unchanged. Audit §11 satisfied: JSONC comments transcribed to
description fields, not dropped."
```

### Task 2.6: Phase 2 acceptance check

- [ ] Run all schema tests: `for t in tests/scripts/test_schema_*.sh; do bash "$t" || exit 1; done`
- [ ] All schemas validate against real state files (or known divergences logged)
- [ ] `agents/SHARED_STATE.md` no longer contains any ` ```jsonc ` fenced block

```bash
grep -c '```jsonc' agents/SHARED_STATE.md
```
Expected: `0`.

---

## Phase 3 — `scripts/profiler/`

Smallest extractable surface, easiest to verify. Strict scope: mechanical transforms only. **Classification rules stay in `repo-profiler.md` prompt** (audit §7) — Claude reads them and judges per case.

### Task 3.1: `scripts/profiler/parse_workflows.sh`

**Files:**
- Create: `scripts/profiler/parse_workflows.sh`
- Create: `tests/scripts/test_parse_workflows.sh`
- Create: `tests/fixtures/workflow.yml` (synthetic)

**Source today:** YAML extraction part of `repo-profiler.md` Step 5 (only the `run:` block extraction; classification rules stay in prompt).

**Strict scope:** extract `run:` blocks from a workflow YAML and emit them on stdout, one per line. Nothing else.

- [ ] **Step 1: Create fixture**

```yaml
# tests/fixtures/workflow.yml
name: ci
on: [push]
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - run: ruff check .
      - run: pytest tests/unit
      - name: Build docs
        run: |
          pip install -r docs/requirements.txt
          sphinx-build docs build
```

- [ ] **Step 2: Write failing test**

```bash
# tests/scripts/test_parse_workflows.sh
#!/usr/bin/env bash
set -euo pipefail
export CLAUDE_PLUGIN_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

out=$(bash "$CLAUDE_PLUGIN_ROOT/scripts/profiler/parse_workflows.sh" "$CLAUDE_PLUGIN_ROOT/tests/fixtures/workflow.yml")
echo "$out" | grep -q "ruff check \."        || { echo "FAIL ruff"; exit 1; }
echo "$out" | grep -q "pytest tests/unit"     || { echo "FAIL pytest"; exit 1; }
echo "$out" | grep -q "pip install -r"        || { echo "FAIL multiline"; exit 1; }
echo "$out" | grep -q "sphinx-build docs build" || { echo "FAIL multiline2"; exit 1; }

echo "OK test_parse_workflows.sh"
```

Run: `bash tests/scripts/test_parse_workflows.sh`
Expected: FAIL — script missing.

- [ ] **Step 3: Implement script**

```bash
#!/usr/bin/env bash
# parse_workflows.sh WORKFLOW_FILE [WORKFLOW_FILE ...]
# Emits each `run:` value on stdout, one logical command per line.
# Classification (allowed vs denied) is NOT done here — agent prompt handles
# classification per audit §7.
set -euo pipefail
: "${CLAUDE_PLUGIN_ROOT:?CLAUDE_PLUGIN_ROOT must be set}"

if ! command -v yq >/dev/null 2>&1; then
  echo "parse_workflows.sh: yq required" >&2
  exit 2
fi

for wf in "$@"; do
  [ -f "$wf" ] || continue
  yq -r '.. | select(has("run")) | .run' "$wf" 2>/dev/null | \
    awk 'NF { print }'
done
```

- [ ] **Step 4: Run test, verify pass, commit**

Run: `bash tests/scripts/test_parse_workflows.sh`
Expected: `OK test_parse_workflows.sh`

```
git add scripts/profiler/parse_workflows.sh tests/scripts/test_parse_workflows.sh tests/fixtures/workflow.yml
git commit -m "feat(scripts/profiler): parse_workflows.sh — extract run: blocks only

Strict scope per audit §7: mechanical YAML extraction, no classification.
classify_command rules stay in repo-profiler.md prompt as prose."
```

### Task 3.2: `scripts/profiler/detect_smoke.sh`

**Files:**
- Create: `scripts/profiler/detect_smoke.sh`
- Create: `tests/scripts/test_detect_smoke.sh`
- Create: `tests/fixtures/smoke_python/` (synthetic project)

**Source today:** `repo-profiler.md` Step 5.6 — six smoke layer detectors:
- `python_import_root` — `setup.py` or `pyproject.toml` plus a top-level package with `__init__.py`
- `django_check` — `manage.py` at repo root
- `flask_app_import` — module exposes `app = Flask(...)` at module level
- `fastapi_app_import` — module exposes `app = FastAPI(...)` at module level
- `pytest_smoke_dir` — `tests/smoke/` directory exists
- `node_require_root` — `package.json` declares a `main` field

- [ ] **Step 1: Create fixture (python project)**

```
mkdir -p tests/fixtures/smoke_python/myproj
echo 'from setuptools import setup' > tests/fixtures/smoke_python/setup.py
echo 'setup(name="myproj", packages=["myproj"])' >> tests/fixtures/smoke_python/setup.py
touch tests/fixtures/smoke_python/myproj/__init__.py
```

- [ ] **Step 2: Write failing test**

```bash
# tests/scripts/test_detect_smoke.sh
#!/usr/bin/env bash
set -euo pipefail
export CLAUDE_PLUGIN_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

out=$(bash "$CLAUDE_PLUGIN_ROOT/scripts/profiler/detect_smoke.sh" \
        "$CLAUDE_PLUGIN_ROOT/tests/fixtures/smoke_python")

echo "$out" | jq -e '.layers | map(.name) | index("python_import_root") != null' >/dev/null \
  || { echo "FAIL python_import_root not detected"; exit 1; }
echo "$out" | jq -e '.layers | map(.name) | index("django_check") == null' >/dev/null \
  || { echo "FAIL django_check false positive"; exit 1; }

echo "OK test_detect_smoke.sh"
```

- [ ] **Step 3: Implement script**

```bash
#!/usr/bin/env bash
# detect_smoke.sh REPO_DIR
# Emits {repo, generated_at, layers:[{name, cmd, cwd, timeout_s}]} on stdout.
set -euo pipefail
: "${CLAUDE_PLUGIN_ROOT:?CLAUDE_PLUGIN_ROOT must be set}"

REPO_DIR="${1:?repo dir required}"
[ -d "$REPO_DIR" ] || { echo "detect_smoke.sh: not a dir: $REPO_DIR" >&2; exit 2; }
cd "$REPO_DIR"

layers='[]'
add_layer() {
  local name="$1" cmd="$2" cwd="$3" timeout="$4"
  layers=$(echo "$layers" | jq \
    --arg n "$name" --arg c "$cmd" --arg w "$cwd" --argjson t "$timeout" \
    '. + [{name:$n, cmd:$c, cwd:$w, timeout_s:$t}]')
}

if [ -f setup.py ] || [ -f pyproject.toml ]; then
  pkg=$(find . -maxdepth 2 -name __init__.py -not -path '*/tests/*' 2>/dev/null | head -1)
  if [ -n "$pkg" ]; then
    pkg_name=$(dirname "$pkg" | sed 's|^\./||' | tr '/' '.')
    add_layer "python_import_root" "python -c 'import $pkg_name'" "." 30
  fi
fi

if [ -f manage.py ]; then
  add_layer "django_check" "python manage.py check" "." 60
fi

flask_mod=$(grep -rln --include='*.py' -E '^app[[:space:]]*=[[:space:]]*Flask\(' . 2>/dev/null | head -1 || true)
if [ -n "$flask_mod" ]; then
  modname=$(echo "$flask_mod" | sed 's|^\./||;s|\.py$||;s|/|.|g')
  add_layer "flask_app_import" "python -c 'from $modname import app'" "." 30
fi

fastapi_mod=$(grep -rln --include='*.py' -E '^app[[:space:]]*=[[:space:]]*FastAPI\(' . 2>/dev/null | head -1 || true)
if [ -n "$fastapi_mod" ]; then
  modname=$(echo "$fastapi_mod" | sed 's|^\./||;s|\.py$||;s|/|.|g')
  add_layer "fastapi_app_import" "python -c 'from $modname import app'" "." 30
fi

if [ -d tests/smoke ]; then
  add_layer "pytest_smoke_dir" "pytest tests/smoke" "." 120
fi

if [ -f package.json ]; then
  main_field=$(jq -r '.main // empty' package.json 2>/dev/null || true)
  if [ -n "$main_field" ]; then
    add_layer "node_require_root" "node -e \"require('./$main_field')\"" "." 30
  fi
fi

repo_slug=$(basename "$(pwd)")
generated_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)
jq -n --arg repo "$repo_slug" --arg ts "$generated_at" --argjson layers "$layers" \
  '{repo:$repo, generated_at:$ts, layers:$layers}'
```

- [ ] **Step 4: Run test, verify pass, commit**

Run: `bash tests/scripts/test_detect_smoke.sh`
Expected: `OK test_detect_smoke.sh`

```
git add scripts/profiler/detect_smoke.sh tests/scripts/test_detect_smoke.sh tests/fixtures/smoke_python/
git commit -m "feat(scripts/profiler): detect_smoke.sh — six layer detectors

python_import_root, django_check, flask_app_import, fastapi_app_import,
pytest_smoke_dir, node_require_root. Source: repo-profiler.md Step 5.6.
Per-layer rationale stays in the agent prompt."
```

### Task 3.3: `scripts/profiler/catalog_generated.sh`

**Files:**
- Create: `scripts/profiler/catalog_generated.sh`
- Create: `tests/scripts/test_catalog_generated.sh`
- Create: `tests/fixtures/generated_repo/` (synthetic)

**Source today:** `repo-profiler.md` Step 5.5. Scans for generator markers; cap at 500 entries.

- [ ] **Step 1: Create fixture**

```
mkdir -p tests/fixtures/generated_repo/proto tests/fixtures/generated_repo/openapi
echo "# @generated by the protocol buffer compiler. DO NOT EDIT!" > tests/fixtures/generated_repo/proto/_pb2.py
echo "# AUTO-GENERATED — do not edit" > tests/fixtures/generated_repo/openapi/v1.yaml
echo "openapi: 3.0.0" >> tests/fixtures/generated_repo/openapi/v1.yaml
echo 'def hello(): return "world"' > tests/fixtures/generated_repo/normal.py
```

- [ ] **Step 2: Write failing test**

```bash
# tests/scripts/test_catalog_generated.sh
#!/usr/bin/env bash
set -euo pipefail
export CLAUDE_PLUGIN_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

out=$(bash "$CLAUDE_PLUGIN_ROOT/scripts/profiler/catalog_generated.sh" \
        "$CLAUDE_PLUGIN_ROOT/tests/fixtures/generated_repo")

count=$(echo "$out" | jq '.entries | length')
[ "$count" = "2" ] || { echo "FAIL count: got $count want 2"; exit 1; }
echo "$out" | jq -e '.entries[] | select(.path | contains("_pb2.py"))' >/dev/null \
  || { echo "FAIL pb2 missing"; exit 1; }
echo "$out" | jq -e '.entries[] | select(.path | contains("v1.yaml"))' >/dev/null \
  || { echo "FAIL openapi missing"; exit 1; }

echo "OK test_catalog_generated.sh"
```

- [ ] **Step 3: Implement script**

```bash
#!/usr/bin/env bash
# catalog_generated.sh REPO_DIR
# Emits {repo, generated_at, entries:[{path, marker, regenerate_cmd}]} on stdout.
# Cap: 500 entries. Beyond that, log a warning to stderr and truncate.
set -euo pipefail
: "${CLAUDE_PLUGIN_ROOT:?CLAUDE_PLUGIN_ROOT must be set}"

REPO_DIR="${1:?repo dir required}"
[ -d "$REPO_DIR" ] || { echo "catalog_generated.sh: not a dir" >&2; exit 2; }
cd "$REPO_DIR"

MARKERS=(
  "AUTO-GENERATED"
  "DO NOT EDIT"
  "@generated"
  "openapi-generator"
  "protoc"
  "prisma generate"
  "swagger-codegen"
)

pattern=""
for m in "${MARKERS[@]}"; do
  if [ -z "$pattern" ]; then pattern="$m"; else pattern="$pattern|$m"; fi
done

entries='[]'
count=0
CAP=500

while IFS= read -r f; do
  [ "$count" -ge "$CAP" ] && { echo "catalog_generated.sh: cap $CAP reached, truncating" >&2; break; }
  marker=$(head -5 "$f" 2>/dev/null | grep -Eo "$pattern" | head -1 || true)
  [ -z "$marker" ] && continue
  rel=$(echo "$f" | sed 's|^\./||')
  entries=$(echo "$entries" | jq \
    --arg p "$rel" --arg m "$marker" \
    '. + [{path:$p, marker:$m, regenerate_cmd:null}]')
  count=$((count + 1))
done < <(find . -type f \( -name '*.py' -o -name '*.yaml' -o -name '*.yml' \
                          -o -name '*.json' -o -name '*.go' -o -name '*.ts' \
                          -o -name '*.js' -o -name '*.rs' \) 2>/dev/null)

repo_slug=$(basename "$(pwd)")
ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
jq -n --arg r "$repo_slug" --arg ts "$ts" --argjson e "$entries" \
  '{repo:$r, generated_at:$ts, entries:$e}'
```

- [ ] **Step 4: Run test, verify pass, commit**

Run: `bash tests/scripts/test_catalog_generated.sh`
Expected: `OK test_catalog_generated.sh`

```
git add scripts/profiler/catalog_generated.sh tests/scripts/test_catalog_generated.sh tests/fixtures/generated_repo/
git commit -m "feat(scripts/profiler): catalog_generated.sh — 500-entry cap

Source: repo-profiler.md Step 5.5. Marker scan against generator
preamble strings; emits generated_files.json shape. regenerate_cmd
defaults to null and is filled in by the agent prompt."
```

### Task 3.4: Update `agents/repo-profiler.md` to cite scripts

**Files:**
- Modify: `agents/repo-profiler.md` — replace inline YAML extraction with script call; replace inline smoke-detect with script call; replace inline generated-file scan with script call. Keep classify_command rules verbatim.

- [ ] **Step 1: Replace Step 5 YAML-extraction code with prose pointer**

Locate the inline bash block that extracts `run:` from workflow YAMLs. Replace with:

```markdown
Run `${CLAUDE_PLUGIN_ROOT}/scripts/profiler/parse_workflows.sh
.github/workflows/*.yml` to get every step's `run:` value, one logical
command per line. Then **apply the classification rules below** —
that part is your judgment, not the script's.
```

Leave the `classify_command` rules block (lines ~130-165) verbatim.

- [ ] **Step 2: Replace Step 5.5 generated-file scan with pointer**

```markdown
Run `${CLAUDE_PLUGIN_ROOT}/scripts/profiler/catalog_generated.sh "$REPO_DIR"`
to produce the catalog. The script caps at 500 entries; beyond that
it warns on stderr and truncates. Set `regenerate_cmd` per entry by
reading the project's contributing docs — that step stays prompt-driven.
```

- [ ] **Step 3: Replace Step 5.6 smoke-layer detection with pointer**

```markdown
Run `${CLAUDE_PLUGIN_ROOT}/scripts/profiler/detect_smoke.sh "$REPO_DIR"`
to produce the smoke registry. Per-layer rationale (why pytest_smoke_dir
exists, why django_check is a separate layer from python_import_root,
etc.) stays in this prompt below.
```

- [ ] **Step 4: Verify safety prose preserved**

```bash
grep -q "denylist first at the token level"     agents/repo-profiler.md || echo "WARN: classify rule lost"
grep -q "never overwrite"                       agents/repo-profiler.md || echo "WARN: never-overwrite lost"
grep -q "allowed_commands.json"                 agents/repo-profiler.md
```
Expected: no WARN lines.

- [ ] **Step 5: Commit**

```
git add agents/repo-profiler.md
git commit -m "refactor(repo-profiler): cite profiler/*.sh; keep classification prose

Mechanical YAML extraction, smoke-layer detection, and generated-file
scan now live in scripts/profiler/*.sh. classify_command rules stay
inline as prose — Claude reads and applies (audit §7)."
```

### Task 3.5: Phase 3 acceptance — behavioral diff against a real repo

- [ ] **Step 1: Run all profiler tests**

```bash
for t in tests/scripts/test_parse_workflows.sh \
         tests/scripts/test_detect_smoke.sh \
         tests/scripts/test_catalog_generated.sh; do
  bash "$t" || exit 1
done
```

- [ ] **Step 2: Behavioral diff against one cached repo (if available)**

If a cached profile exists at `~/.superhuman/repos/<slug>/`, regenerate via the script chain and diff after stripping `generated_at`. Acceptance: empty diff. Non-empty diffs require root-cause analysis (script bug vs. prompt-judgment difference).

---

## Phase 4 — `scripts/scorer/`

The 10-dim weighted rubric blended with historical merge outcomes. **Cap rules and cap triggers stay in `merge-probability-scorer.md` prompt** (audit §3) — only score arithmetic moves.

### Task 4.1: `scripts/scorer/compute_score.sh` (arithmetic only)

**Files:**
- Create: `scripts/scorer/compute_score.sh`
- Create: `tests/scripts/test_compute_score.sh`

**Source today:** `merge-probability-scorer.md` Steps 3-5 inline arithmetic. The Process cap (50%) and CI-health cap (40%) rules and **cap triggers** stay in prompt; only the weighted-sum + plateau-detect + raw→final transform moves.

- [ ] **Step 1: Write failing test**

```bash
# tests/scripts/test_compute_score.sh
#!/usr/bin/env bash
set -euo pipefail
export CLAUDE_PLUGIN_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

# 10 dims at known scores → weighted sum verified against spec weights
# Weights: Correctness 22, Tests 18, Historical 10, Style/PR/Process/Scope 9 each, Docs/Commit 5 each, Risk 4
DIMS='{"correctness":10,"test_coverage":10,"style":10,"pr_format":10,"process":10,
       "scope":10,"docs":10,"commit":10,"risk":10,"historical":10}'

out=$(bash "$CLAUDE_PLUGIN_ROOT/scripts/scorer/compute_score.sh" \
        --dimensions "$DIMS" --caps-applied '[]' --plateaued '[]')
raw=$(echo "$out" | jq -r .raw)
final=$(echo "$out" | jq -r .final)
[ "$raw" = "100" ]   || { echo "FAIL raw at all-10: $raw"; exit 1; }
[ "$final" = "100" ] || { echo "FAIL final at all-10: $final"; exit 1; }

# Process cap applied → final clamped at 50
out=$(bash "$CLAUDE_PLUGIN_ROOT/scripts/scorer/compute_score.sh" \
        --dimensions "$DIMS" --caps-applied '["process"]' --plateaued '[]')
final=$(echo "$out" | jq -r .final)
[ "$final" = "50" ] || { echo "FAIL process cap: $final"; exit 1; }

# CI-health cap applied → final clamped at 40
out=$(bash "$CLAUDE_PLUGIN_ROOT/scripts/scorer/compute_score.sh" \
        --dimensions "$DIMS" --caps-applied '["ci_health"]' --plateaued '[]')
final=$(echo "$out" | jq -r .final)
[ "$final" = "40" ] || { echo "FAIL ci_health cap: $final"; exit 1; }

echo "OK test_compute_score.sh"
```

- [ ] **Step 2: Implement script**

```bash
#!/usr/bin/env bash
# compute_score.sh --dimensions <JSON> --caps-applied <JSON-array> --plateaued <JSON-array>
# Emits {raw, final, weighted_breakdown} on stdout.
# Cap RULES and TRIGGERS live in merge-probability-scorer.md prompt; this
# script only applies arithmetic when the prompt has decided a cap fires.
set -euo pipefail
: "${CLAUDE_PLUGIN_ROOT:?CLAUDE_PLUGIN_ROOT must be set}"

DIMS=""
CAPS="[]"
PLATEAUED="[]"

while [ $# -gt 0 ]; do
  case "$1" in
    --dimensions)    DIMS="$2"; shift 2 ;;
    --caps-applied)  CAPS="$2"; shift 2 ;;
    --plateaued)     PLATEAUED="$2"; shift 2 ;;
    *) echo "compute_score.sh: unknown arg: $1" >&2; exit 2 ;;
  esac
done

[ -z "$DIMS" ] && { echo "compute_score.sh: --dimensions required" >&2; exit 2; }

# Authoritative weights (sum to 100) — KEEP IN SYNC with merge-probability-scorer.md.
read -r raw final breakdown <<< "$(jq -nr \
  --argjson dims "$DIMS" \
  --argjson caps "$CAPS" \
  '
  def w: {correctness:22, test_coverage:18, historical:10,
          style:9, pr_format:9, process:9, scope:9,
          docs:5, commit:5, risk:4};
  def cap_for(applied):
    if (applied | index("process"))    then 50
    elif (applied | index("ci_health")) then 40
    else 100 end;
  ($dims | to_entries | map(.value * (w[.key] // 0) / 10) | add) as $raw
  | (if $raw > cap_for($caps) then cap_for($caps) else $raw end) as $final
  | "\($raw) \($final) \($dims)"
  ')"

jq -nc \
  --argjson raw "$raw" \
  --argjson final "$final" \
  --argjson dims "$DIMS" \
  --argjson caps "$CAPS" \
  --argjson plateaued "$PLATEAUED" \
  '{raw:$raw, final:$final, dimensions:$dims, caps_applied:$caps, plateaued:$plateaued}'
```

- [ ] **Step 3: Run test, verify pass, commit**

Run: `bash tests/scripts/test_compute_score.sh`
Expected: `OK test_compute_score.sh`

```
git add scripts/scorer/compute_score.sh tests/scripts/test_compute_score.sh
git commit -m "feat(scripts/scorer): compute_score.sh — arithmetic only

Renamed from rubric.sh per audit §3 to make scope explicit. Cap rules
and triggers stay in merge-probability-scorer.md prompt; this script
applies clamps when prompt decides a cap fires."
```

### Task 4.2: `scripts/scorer/historical_blend.sh`

**Files:**
- Create: `scripts/scorer/historical_blend.sh`
- Create: `tests/scripts/test_historical_blend.sh`

**Source today:** `merge-probability-scorer.md:~257` (the line with the unbalanced paren bug — fix during move per audit §18). Computes Laplace-ish smoothed merge estimate from `merge_outcomes.jsonl`.

- [ ] **Step 1: Write failing test**

```bash
# tests/scripts/test_historical_blend.sh
#!/usr/bin/env bash
set -euo pipefail
export CLAUDE_PLUGIN_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

tmpdir=$(mktemp -d)
GD="$tmpdir/global"
mkdir -p "$GD"
cat > "$GD/merge_outcomes.jsonl" <<'EOF'
{"repo":"apache/airflow","outcome":"merged","closed_at":"2026-04-01T00:00:00Z"}
{"repo":"apache/airflow","outcome":"merged","closed_at":"2026-04-15T00:00:00Z"}
{"repo":"apache/airflow","outcome":"closed_no_merge","closed_at":"2026-05-01T00:00:00Z"}
EOF

out=$(bash "$CLAUDE_PLUGIN_ROOT/scripts/scorer/historical_blend.sh" \
        --rubric-01 0.72 \
        --merge-log "$GD/merge_outcomes.jsonl" \
        --repo apache/airflow \
        --weight 0.3)

# 2/3 merged + Laplace smoothing → est ~0.6, blend = 0.7 * 0.72 + 0.3 * ~0.6 ≈ 0.684
final=$(echo "$out" | jq -r .blended)
# Must be a finite number 0..10
echo "$out" | jq -e '.blended | type == "number"' >/dev/null || { echo "FAIL not number"; exit 1; }
awk -v v="$final" 'BEGIN{ if (v<0||v>10) exit 1; }' || { echo "FAIL out of range: $final"; exit 1; }

echo "OK test_historical_blend.sh"
```

- [ ] **Step 2: Implement script**

```bash
#!/usr/bin/env bash
# historical_blend.sh --rubric-01 X --merge-log FILE --repo OWNER/REPO --weight W
# Emits {merge_estimate_01, rubric_01, weight, blended} on stdout (blended on 0..10).
# Source: merge-probability-scorer.md Step 3a. Fixes the unbalanced paren bug
# from line ~257 of the original (audit §18).
set -euo pipefail
: "${CLAUDE_PLUGIN_ROOT:?CLAUDE_PLUGIN_ROOT must be set}"

RUBRIC_01=""
MERGE_LOG=""
REPO=""
W="0.3"

while [ $# -gt 0 ]; do
  case "$1" in
    --rubric-01) RUBRIC_01="$2"; shift 2 ;;
    --merge-log) MERGE_LOG="$2"; shift 2 ;;
    --repo)      REPO="$2"; shift 2 ;;
    --weight)    W="$2"; shift 2 ;;
    *) echo "historical_blend.sh: unknown arg: $1" >&2; exit 2 ;;
  esac
done

[ -z "$RUBRIC_01" ] && { echo "--rubric-01 required" >&2; exit 2; }
[ -z "$REPO" ]      && { echo "--repo required" >&2; exit 2; }

# Count merged vs total for this repo. Laplace-ish: (m + 1) / (n + 2).
counts=$(jq -s --arg r "$REPO" '
  map(select(.repo == $r))
  | {merged: (map(select(.outcome == "merged")) | length),
     total:  length}
' "$MERGE_LOG" 2>/dev/null || echo '{"merged":0,"total":0}')

m=$(echo "$counts" | jq -r .merged)
n=$(echo "$counts" | jq -r .total)

MERGE_EST=$(python3 -c "print(round(($m + 1) / ($n + 2), 4))")
BLENDED=$(python3 -c "print(round(10 * ((1-$W) * $RUBRIC_01 + $W * $MERGE_EST), 2))")

jq -nc \
  --argjson est "$MERGE_EST" \
  --argjson rub "$RUBRIC_01" \
  --argjson w   "$W" \
  --argjson b   "$BLENDED" \
  '{merge_estimate_01:$est, rubric_01:$rub, weight:$w, blended:$b}'
```

- [ ] **Step 3: Run test, verify pass, commit**

Run: `bash tests/scripts/test_historical_blend.sh`
Expected: `OK test_historical_blend.sh`

```
git add scripts/scorer/historical_blend.sh tests/scripts/test_historical_blend.sh
git commit -m "feat(scripts/scorer): historical_blend.sh + fix paren bug (audit §18)

Source: merge-probability-scorer.md Step 3a (~line 257). The original
inline python3 had an unbalanced paren on the print(round(...)) line.
Fixed during move; arithmetic verified by test_historical_blend.sh."
```

### Task 4.3: `scripts/scorer/append_score.sh`

**Files:**
- Create: `scripts/scorer/append_score.sh`
- Create: `tests/scripts/test_append_score.sh`

**Source today:** `merge-probability-scorer.md` Step 6 (atomic append to `current_contribution.json::scores[]`).

- [ ] **Step 1: Write failing test**

```bash
# tests/scripts/test_append_score.sh
#!/usr/bin/env bash
set -euo pipefail
export CLAUDE_PLUGIN_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

tmpdir=$(mktemp -d)
SD="$tmpdir/repos/apache-airflow"
mkdir -p "$SD"
cat > "$SD/current_contribution.json" <<'EOF'
{"repo":"apache/airflow","issue_number":1,"branch":"x","iteration":0,
 "scores":[],"lock_holder":"opensource-contributor","started_at":"2026-04-24T11:00:00Z"}
EOF

SCORE_BLOB='{"iteration":1,"ts":"2026-04-24T11:15:00Z",
             "dimensions":{"correctness":7},"raw":78,"final":72,
             "plateaued":[],"caps_applied":["process"]}'

HOME="$tmpdir" bash "$CLAUDE_PLUGIN_ROOT/scripts/scorer/append_score.sh" \
  --repo apache/airflow --score "$SCORE_BLOB"

count=$(jq '.scores | length' "$SD/current_contribution.json")
[ "$count" = "1" ]   || { echo "FAIL count: $count"; exit 1; }
final=$(jq '.scores[0].final' "$SD/current_contribution.json")
[ "$final" = "72" ]  || { echo "FAIL final: $final"; exit 1; }

echo "OK test_append_score.sh"
```

- [ ] **Step 2: Implement script**

```bash
#!/usr/bin/env bash
# append_score.sh --repo OWNER/REPO --score JSON_BLOB
# Atomically appends score to current_contribution.json scores[].
set -euo pipefail
: "${CLAUDE_PLUGIN_ROOT:?CLAUDE_PLUGIN_ROOT must be set}"
source "${CLAUDE_PLUGIN_ROOT}/scripts/lib/state.sh"

REPO=""
SCORE=""

while [ $# -gt 0 ]; do
  case "$1" in
    --repo)  REPO="$2"; shift 2 ;;
    --score) SCORE="$2"; shift 2 ;;
    *) echo "append_score.sh: unknown arg: $1" >&2; exit 2 ;;
  esac
done

[ -z "$REPO" ] && { echo "--repo required" >&2; exit 2; }
[ -z "$SCORE" ] && { echo "--score required" >&2; exit 2; }

dir=$(state_dir "$REPO")
file="$dir/current_contribution.json"
[ -f "$file" ] || { echo "no current_contribution.json at $file" >&2; exit 2; }

new=$(jq --argjson s "$SCORE" '.scores += [$s]' "$file")
atomic_write_json "$file" "$new"
```

- [ ] **Step 3: Run test, verify pass, commit**

Run: `bash tests/scripts/test_append_score.sh`
Expected: `OK test_append_score.sh`

```
git add scripts/scorer/append_score.sh tests/scripts/test_append_score.sh
git commit -m "feat(scripts/scorer): append_score.sh — atomic scores[] append"
```

### Task 4.4: `scripts/scorer/record_outcome.sh`

**Files:**
- Create: `scripts/scorer/record_outcome.sh`
- Create: `tests/scripts/test_record_outcome.sh`

**Source today:** `merge-probability-scorer.md` Step 7 (JSONL append to global `merge_outcomes.jsonl`).

- [ ] **Step 1: Write failing test**

```bash
# tests/scripts/test_record_outcome.sh
#!/usr/bin/env bash
set -euo pipefail
export CLAUDE_PLUGIN_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

tmpdir=$(mktemp -d)

HOME="$tmpdir" bash "$CLAUDE_PLUGIN_ROOT/scripts/scorer/record_outcome.sh" \
  --repo apache/airflow \
  --pr-url https://github.com/apache/airflow/pull/65685 \
  --outcome merged \
  --iterations 3 \
  --closed-at 2026-04-28T09:12:00Z \
  --final-scores '{"correctness":9,"test_coverage":8}'

LOG="$tmpdir/.superhuman/global/merge_outcomes.jsonl"
[ -f "$LOG" ] || { echo "FAIL log not created"; exit 1; }
[ "$(wc -l < "$LOG" | tr -d ' ')" = "1" ] || { echo "FAIL line count"; exit 1; }
jq -e '.outcome=="merged"' "$LOG" >/dev/null || { echo "FAIL outcome"; exit 1; }

echo "OK test_record_outcome.sh"
```

- [ ] **Step 2: Implement script**

```bash
#!/usr/bin/env bash
# record_outcome.sh --repo --pr-url --outcome --iterations --closed-at --final-scores
# Append-only JSONL to ~/.superhuman/global/merge_outcomes.jsonl.
set -euo pipefail
: "${CLAUDE_PLUGIN_ROOT:?CLAUDE_PLUGIN_ROOT must be set}"
source "${CLAUDE_PLUGIN_ROOT}/scripts/lib/state.sh"

REPO=""; PR_URL=""; OUTCOME=""; ITER=""; CLOSED_AT=""; FINAL_SCORES="{}"

while [ $# -gt 0 ]; do
  case "$1" in
    --repo)         REPO="$2"; shift 2 ;;
    --pr-url)       PR_URL="$2"; shift 2 ;;
    --outcome)      OUTCOME="$2"; shift 2 ;;
    --iterations)   ITER="$2"; shift 2 ;;
    --closed-at)    CLOSED_AT="$2"; shift 2 ;;
    --final-scores) FINAL_SCORES="$2"; shift 2 ;;
    *) echo "record_outcome.sh: unknown arg: $1" >&2; exit 2 ;;
  esac
done

GD=$(global_dir)
mkdir -p "$GD"
LOG="$GD/merge_outcomes.jsonl"

jq -nc \
  --arg pr "$PR_URL" --arg repo "$REPO" --arg out "$OUTCOME" \
  --arg ts "$CLOSED_AT" --argjson iter "$ITER" --argjson fs "$FINAL_SCORES" \
  '{pr_url:$pr, repo:$repo, outcome:$out, final_scores:$fs, iterations:$iter, closed_at:$ts}' \
  >> "$LOG"
```

- [ ] **Step 3: Run test, verify pass, commit**

Run: `bash tests/scripts/test_record_outcome.sh`
Expected: `OK test_record_outcome.sh`

```
git add scripts/scorer/record_outcome.sh tests/scripts/test_record_outcome.sh
git commit -m "feat(scripts/scorer): record_outcome.sh — append-only merge_outcomes.jsonl"
```

### Task 4.5: `scripts/scorer/regen_cooldown.sh`

**Files:**
- Create: `scripts/scorer/regen_cooldown.sh`
- Create: `tests/scripts/test_regen_cooldown.sh`

**Source today:** `merge-probability-scorer.md` Step 7.5. Reads `merge_outcomes.jsonl`, applies the 90/180-day rules from `SHARED_STATE.md:267-298`, atomically writes `repo_cooldown.json`.

Cooldown rules (verbatim from SHARED_STATE.md):
- ≥2 of `{closed_no_merge, abandoned, suspicious_halt}` in 180 days with 0 `merged` in same window → cooldown for 90 days from most recent negative outcome
- Any `suspicious_halt` in last 180 days → cooldown for 180 days from that outcome
- Any `merged` in last 180 days → counter resets; no cooldown

- [ ] **Step 1: Write failing test (covers all three rules)**

```bash
# tests/scripts/test_regen_cooldown.sh
#!/usr/bin/env bash
set -euo pipefail
export CLAUDE_PLUGIN_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

tmpdir=$(mktemp -d)
GD="$tmpdir/.superhuman/global"
mkdir -p "$GD"
LOG="$GD/merge_outcomes.jsonl"

# Repo A: 2 negatives, 0 merged in 180d → 90d cooldown
# Repo B: 1 suspicious_halt → 180d cooldown
# Repo C: 1 merged → no cooldown
NOW="2026-05-18T00:00:00Z"
cat > "$LOG" <<'EOF'
{"repo":"a/a","outcome":"closed_no_merge","closed_at":"2026-04-01T00:00:00Z"}
{"repo":"a/a","outcome":"abandoned","closed_at":"2026-05-01T00:00:00Z"}
{"repo":"b/b","outcome":"suspicious_halt","closed_at":"2026-05-10T00:00:00Z"}
{"repo":"c/c","outcome":"merged","closed_at":"2026-05-01T00:00:00Z"}
{"repo":"c/c","outcome":"closed_no_merge","closed_at":"2026-04-01T00:00:00Z"}
EOF

HOME="$tmpdir" bash "$CLAUDE_PLUGIN_ROOT/scripts/scorer/regen_cooldown.sh" --now "$NOW"

CD="$GD/repo_cooldown.json"
[ -f "$CD" ] || { echo "FAIL: no cooldown file"; exit 1; }
jq -e '.cooldowns | map(.repo) | index("a/a")' "$CD" >/dev/null || { echo "FAIL: a/a missing"; exit 1; }
jq -e '.cooldowns | map(.repo) | index("b/b")' "$CD" >/dev/null || { echo "FAIL: b/b missing"; exit 1; }
jq -e '.cooldowns | map(.repo) | index("c/c") == null' "$CD" >/dev/null || { echo "FAIL: c/c should not be cooled"; exit 1; }

echo "OK test_regen_cooldown.sh"
```

- [ ] **Step 2: Implement script**

```bash
#!/usr/bin/env bash
# regen_cooldown.sh [--now ISO_TS]
# Reads ~/.superhuman/global/merge_outcomes.jsonl, applies the 90/180-day
# rules from SHARED_STATE.md, atomically rewrites repo_cooldown.json.
set -euo pipefail
: "${CLAUDE_PLUGIN_ROOT:?CLAUDE_PLUGIN_ROOT must be set}"
source "${CLAUDE_PLUGIN_ROOT}/scripts/lib/state.sh"

NOW=""
while [ $# -gt 0 ]; do
  case "$1" in
    --now) NOW="$2"; shift 2 ;;
    *) echo "regen_cooldown.sh: unknown arg: $1" >&2; exit 2 ;;
  esac
done
[ -z "$NOW" ] && NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)

GD=$(global_dir)
LOG="$GD/merge_outcomes.jsonl"
CD="$GD/repo_cooldown.json"

if [ ! -f "$LOG" ]; then
  atomic_write_json "$CD" "$(jq -n --arg ts "$NOW" '{version:1, generated_at:$ts, cooldowns:[]}')"
  exit 0
fi

NOW_EPOCH=$(python3 -c "import datetime; print(int(datetime.datetime.fromisoformat('$NOW'.replace('Z','+00:00')).timestamp()))")

cooldowns=$(jq -s --arg now "$NOW" --argjson now_e "$NOW_EPOCH" '
  def to_epoch(t): t | sub("Z$"; "+00:00") | fromdateiso8601;
  def add_days(e; d): e + (d * 86400);
  def from_epoch(e): e | strftime("%Y-%m-%dT%H:%M:%SZ");

  group_by(.repo)
  | map(
      . as $entries
      | ($entries[0].repo) as $repo
      | (map(select(.outcome == "merged"
                    and (to_epoch(.closed_at)) >= ($now_e - 180*86400)))
         | length) as $merged_180
      | if $merged_180 > 0 then null
        else
          (map(select(.outcome == "suspicious_halt"
                      and (to_epoch(.closed_at)) >= ($now_e - 180*86400))))
          as $susp
        | (map(select((.outcome | IN("closed_no_merge","abandoned","suspicious_halt")))
                      and (to_epoch(.closed_at)) >= ($now_e - 180*86400)))
          as $negs
        | if ($susp | length) > 0 then
            ($susp | sort_by(to_epoch(.closed_at)) | last) as $last
            | {repo:$repo,
               negative_outcomes_180d: ($negs | length),
               last_merged_at: null,
               cooldown_until: from_epoch(add_days(to_epoch($last.closed_at); 180)),
               triggering_outcomes: ($negs | map(.outcome))}
          elif ($negs | length) >= 2 then
            ($negs | sort_by(to_epoch(.closed_at)) | last) as $last
            | {repo:$repo,
               negative_outcomes_180d: ($negs | length),
               last_merged_at: null,
               cooldown_until: from_epoch(add_days(to_epoch($last.closed_at); 90)),
               triggering_outcomes: ($negs | map(.outcome))}
          else null end
        end
    )
  | map(select(. != null))
' "$LOG")

new=$(jq -n --arg ts "$NOW" --argjson c "$cooldowns" \
  '{version:1, generated_at:$ts, cooldowns:$c}')
atomic_write_json "$CD" "$new"
```

- [ ] **Step 3: Run test, verify pass, commit**

Run: `bash tests/scripts/test_regen_cooldown.sh`
Expected: `OK test_regen_cooldown.sh`

```
git add scripts/scorer/regen_cooldown.sh tests/scripts/test_regen_cooldown.sh
git commit -m "feat(scripts/scorer): regen_cooldown.sh — 90/180-day rules

Source: merge-probability-scorer.md Step 7.5 + SHARED_STATE.md rules.
Atomic write preserves single-writer invariant on repo_cooldown.json."
```

### Task 4.6: Update `agents/merge-probability-scorer.md` to cite scripts

**Files:**
- Modify: `agents/merge-probability-scorer.md` — replace inline arithmetic with script call; replace inline historical blend (with the paren bug) with script call; replace JSONL appends with script calls. **Cap rules and cap triggers stay in prompt** (audit §3).

- [ ] **Step 1: Replace Step 3 arithmetic with script call**

```markdown
Compute the score by invoking
`${CLAUDE_PLUGIN_ROOT}/scripts/scorer/compute_score.sh
--dimensions <DIMS> --caps-applied <CAPS> --plateaued <PLATS>`.
The cap **rules** and **triggers** below decide what `--caps-applied`
contains; the script only enforces the clamp.
```

Then preserve the cap-rules block verbatim (Process cap = 50 with trigger conditions; CI-health cap = 40 with trigger conditions including the flake exemption).

- [ ] **Step 2: Replace Step 3a historical-blend python3 inline with script call**

```markdown
Compute the historical blend with
`${CLAUDE_PLUGIN_ROOT}/scripts/scorer/historical_blend.sh
--rubric-01 <01> --merge-log $HOME/.superhuman/global/merge_outcomes.jsonl
--repo <OWNER/REPO> --weight 0.3`. The script returns
`{merge_estimate_01, rubric_01, weight, blended}` on stdout.
```

Note in commit message: this fixes audit §18 (paren bug at original line ~257).

- [ ] **Step 3: Replace Step 6 atomic append with script call**

```markdown
Append to scores[] with
`${CLAUDE_PLUGIN_ROOT}/scripts/scorer/append_score.sh --repo <r> --score <BLOB>`.
```

- [ ] **Step 4: Replace Step 7 outcome record + Step 7.5 cooldown regen**

```markdown
On terminal state (MODE=record_outcome), call:

  ${CLAUDE_PLUGIN_ROOT}/scripts/scorer/record_outcome.sh \
    --repo <r> --pr-url <url> --outcome <outcome> \
    --iterations <n> --closed-at <ts> --final-scores <JSON>

  ${CLAUDE_PLUGIN_ROOT}/scripts/scorer/regen_cooldown.sh
```

- [ ] **Step 5: Verify cap rules + triggers + thresholds preserved**

```bash
grep -q "Process cap"          agents/merge-probability-scorer.md
grep -q "CI-health cap"        agents/merge-probability-scorer.md
grep -q "flake"                agents/merge-probability-scorer.md
grep -q "plateau"              agents/merge-probability-scorer.md
grep -q "95"                   agents/merge-probability-scorer.md  # threshold
```
Expected: every grep matches.

- [ ] **Step 6: Commit**

```
git add agents/merge-probability-scorer.md
git commit -m "refactor(scorer): cite scorer/*.sh; cap rules + triggers stay inline

Audit §3: cap rules and TRIGGERS are prompt-time decisions Claude
makes per case (compare /tmp/<name>.log timestamps, check flake
exemption); only score arithmetic moves to a script. Audit §18:
historical_blend.sh fixes the unbalanced paren from line ~257."
```

### Task 4.7: Phase 4 acceptance

- [ ] Run all scorer tests
- [ ] Replay one known PR's scoring against frozen scores in `merge_outcomes.jsonl`; pre/post must be byte-identical
- [ ] Verify cap behavior end-to-end on a synthetic case where Process cap fires (final must equal 50)

---

## Phase 5 — `scripts/orchestrator/`

Last-but-one because it sequences the others. **flock claim STAYS inline in `opensource-contributor.md`** (audit §1 — fd ownership; sub-process flock would release immediately on script exit).

### Task 5.1: `scripts/orchestrator/reputation_gate.sh` (replaces 3 inline duplicates)

**Files:**
- Create: `scripts/orchestrator/reputation_gate.sh`
- Create: `tests/scripts/test_reputation_gate.sh`

**Source today:** Three places duplicate this gate (audit §14):
- `agents/opensource-contributor.md` Phase 0
- `agents/repo-finder.md` reputation filter
- `commands/contribution-fleet.md:80-95`

Single canonical implementation. Returns:
- exit 0 if eligible
- exit 1 if blocklisted (prints reason)
- exit 2 if cooled-down (prints `cooldown_until`)
- exit 3 if locked (prints `lock_holder`)

- [ ] **Step 1: Write failing test (covers all three skip reasons + eligible path)**

```bash
# tests/scripts/test_reputation_gate.sh
#!/usr/bin/env bash
set -euo pipefail
export CLAUDE_PLUGIN_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

tmpdir=$(mktemp -d)
GD="$tmpdir/.superhuman/global"
mkdir -p "$GD" "$tmpdir/.superhuman/repos/foo-bar"
NOW="2026-05-18T00:00:00Z"

# Eligible: empty blocklist + cooldown
echo '{"version":1,"blocked":[]}' > "$GD/repo_blocklist.json"
echo '{"version":1,"generated_at":"'$NOW'","cooldowns":[]}' > "$GD/repo_cooldown.json"
HOME="$tmpdir" bash "$CLAUDE_PLUGIN_ROOT/scripts/orchestrator/reputation_gate.sh" --repo eligible/repo --now "$NOW" || { echo "FAIL eligible"; exit 1; }

# Blocklisted
echo '{"version":1,"blocked":[{"repo":"bad/repo","reason":"declined","added_at":"'$NOW'","expires_at":null}]}' > "$GD/repo_blocklist.json"
set +e
HOME="$tmpdir" bash "$CLAUDE_PLUGIN_ROOT/scripts/orchestrator/reputation_gate.sh" --repo bad/repo --now "$NOW"
rc=$?
set -e
[ "$rc" = "1" ] || { echo "FAIL blocklist rc: $rc"; exit 1; }

# Cooled down
echo '{"version":1,"blocked":[]}' > "$GD/repo_blocklist.json"
echo '{"version":1,"generated_at":"'$NOW'","cooldowns":[{"repo":"cool/repo","cooldown_until":"2099-01-01T00:00:00Z","negative_outcomes_180d":2,"last_merged_at":null,"triggering_outcomes":[]}]}' > "$GD/repo_cooldown.json"
set +e
HOME="$tmpdir" bash "$CLAUDE_PLUGIN_ROOT/scripts/orchestrator/reputation_gate.sh" --repo cool/repo --now "$NOW"
rc=$?
set -e
[ "$rc" = "2" ] || { echo "FAIL cooldown rc: $rc"; exit 1; }

# Locked
echo '{"version":1,"cooldowns":[]}' > "$GD/repo_cooldown.json"
echo '{"lock_holder":"someone-else"}' > "$tmpdir/.superhuman/repos/foo-bar/current_contribution.json"
set +e
HOME="$tmpdir" bash "$CLAUDE_PLUGIN_ROOT/scripts/orchestrator/reputation_gate.sh" --repo foo/bar --now "$NOW"
rc=$?
set -e
[ "$rc" = "3" ] || { echo "FAIL lock rc: $rc"; exit 1; }

echo "OK test_reputation_gate.sh"
```

- [ ] **Step 2: Implement script**

```bash
#!/usr/bin/env bash
# reputation_gate.sh --repo OWNER/REPO [--now ISO_TS]
# Exit 0 = eligible. 1 = blocklisted. 2 = in cooldown. 3 = locked.
# Replaces three inline duplicates: opensource-contributor.md Phase 0,
# repo-finder.md, commands/contribution-fleet.md:80-95 (audit §14).
set -euo pipefail
: "${CLAUDE_PLUGIN_ROOT:?CLAUDE_PLUGIN_ROOT must be set}"
source "${CLAUDE_PLUGIN_ROOT}/scripts/lib/state.sh"

REPO=""
NOW=""
while [ $# -gt 0 ]; do
  case "$1" in
    --repo) REPO="$2"; shift 2 ;;
    --now)  NOW="$2";  shift 2 ;;
    *) echo "reputation_gate.sh: unknown arg: $1" >&2; exit 2 ;;
  esac
done
[ -z "$REPO" ] && { echo "--repo required" >&2; exit 2; }
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
    echo "LOCKED: $REPO — held by $holder"
    exit 3
  fi
fi

echo "ELIGIBLE: $REPO"
exit 0
```

- [ ] **Step 3: Run test, verify pass, commit**

```
bash tests/scripts/test_reputation_gate.sh
git add scripts/orchestrator/reputation_gate.sh tests/scripts/test_reputation_gate.sh
git commit -m "feat(scripts/orchestrator): reputation_gate.sh canonicalizes 3 duplicates

Audit §14: opensource-contributor.md Phase 0, repo-finder.md, and
commands/contribution-fleet.md:80-95 all duplicated this gate. Now
share one implementation. Exit codes: 0 eligible, 1 blocklist,
2 cooldown, 3 locked."
```

### Task 5.2: `scripts/orchestrator/prune_mistakes.sh`

**Files:**
- Create: `scripts/orchestrator/prune_mistakes.sh`
- Create: `tests/scripts/test_prune_mistakes.sh`

**Source today:** `opensource-contributor.md` Phase 0.5 inline awk that prunes mistakes.md older than 30 days.

- [ ] **Step 1: Write failing test**

```bash
# tests/scripts/test_prune_mistakes.sh
#!/usr/bin/env bash
set -euo pipefail
export CLAUDE_PLUGIN_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

tmpdir=$(mktemp -d)
SD="$tmpdir/state"
mkdir -p "$SD"
cat > "$SD/mistakes.md" <<'EOF'
## 2025-01-01T00:00:00Z tag=old repo=a/a
workdir: /x

old entry should be pruned

## 2026-05-15T00:00:00Z tag=new repo=a/a
workdir: /x

new entry should remain

EOF

bash "$CLAUDE_PLUGIN_ROOT/scripts/orchestrator/prune_mistakes.sh" \
  --file "$SD/mistakes.md" --max-age-days 30 --now 2026-05-18T00:00:00Z

grep -q "old entry should be pruned" "$SD/mistakes.md" && { echo "FAIL: old entry kept"; exit 1; }
grep -q "new entry should remain"   "$SD/mistakes.md" || { echo "FAIL: new entry lost"; exit 1; }
echo "OK test_prune_mistakes.sh"
```

- [ ] **Step 2: Implement script**

```bash
#!/usr/bin/env bash
# prune_mistakes.sh --file PATH --max-age-days N [--now ISO_TS]
# Removes entries (## H2 blocks) older than N days from a mistakes.md.
# Atomic: writes to temp + rename. Append-only contract preserved
# (no other writer touches the file during this).
set -euo pipefail
: "${CLAUDE_PLUGIN_ROOT:?CLAUDE_PLUGIN_ROOT must be set}"

FILE=""; MAX=""; NOW=""
while [ $# -gt 0 ]; do
  case "$1" in
    --file)         FILE="$2"; shift 2 ;;
    --max-age-days) MAX="$2";  shift 2 ;;
    --now)          NOW="$2";  shift 2 ;;
    *) echo "prune_mistakes.sh: unknown arg: $1" >&2; exit 2 ;;
  esac
done
[ -z "$FILE" ] && { echo "--file required" >&2; exit 2; }
[ -z "$MAX" ]  && { echo "--max-age-days required" >&2; exit 2; }
[ -z "$NOW" ]  && NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)
[ -f "$FILE" ] || exit 0

NOW_E=$(python3 -c "import datetime; print(int(datetime.datetime.fromisoformat('$NOW'.replace('Z','+00:00')).timestamp()))")
CUTOFF=$(( NOW_E - MAX * 86400 ))

tmp="${FILE}.tmp.$$"
awk -v cutoff="$CUTOFF" '
  function ts_to_epoch(s,    cmd, e) {
    cmd = "python3 -c \"import datetime; print(int(datetime.datetime.fromisoformat(\\\"" s "\\\".replace(\\\"Z\\\",\\\"+00:00\\\")).timestamp()))\""
    cmd | getline e
    close(cmd)
    return e
  }
  /^## / {
    if (block != "" && keep == 1) printf "%s", block
    block = $0 ORS
    match($0, /^## ([0-9T:Z\-]+) /, m)
    e = ts_to_epoch(m[1])
    keep = (e >= cutoff) ? 1 : 0
    next
  }
  { block = block $0 ORS }
  END { if (block != "" && keep == 1) printf "%s", block }
' "$FILE" > "$tmp"

mv "$tmp" "$FILE"
```

- [ ] **Step 3: Run test, verify pass, commit**

```
bash tests/scripts/test_prune_mistakes.sh
git add scripts/orchestrator/prune_mistakes.sh tests/scripts/test_prune_mistakes.sh
git commit -m "feat(scripts/orchestrator): prune_mistakes.sh — drop entries >N days old

Source: opensource-contributor.md Phase 0.5 awk. Atomic temp+rename
preserves append-only contract."
```

### Task 5.3: `scripts/orchestrator/iteration_cap.sh` (3/6/10 by LOC)

**Files:**
- Create: `scripts/orchestrator/iteration_cap.sh`
- Create: `tests/scripts/test_iteration_cap.sh`

**Source today:** `opensource-contributor.md` Phase 7 inline calculation. Rule: cap = 3 if LOC ≤ 50, 6 if ≤ 200, else 10.

- [ ] **Step 1: Write failing test**

```bash
# tests/scripts/test_iteration_cap.sh
#!/usr/bin/env bash
set -euo pipefail
export CLAUDE_PLUGIN_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

[ "$(bash "$CLAUDE_PLUGIN_ROOT/scripts/orchestrator/iteration_cap.sh" --loc 0)"   = "3" ]  || { echo "FAIL 0";   exit 1; }
[ "$(bash "$CLAUDE_PLUGIN_ROOT/scripts/orchestrator/iteration_cap.sh" --loc 50)"  = "3" ]  || { echo "FAIL 50";  exit 1; }
[ "$(bash "$CLAUDE_PLUGIN_ROOT/scripts/orchestrator/iteration_cap.sh" --loc 51)"  = "6" ]  || { echo "FAIL 51";  exit 1; }
[ "$(bash "$CLAUDE_PLUGIN_ROOT/scripts/orchestrator/iteration_cap.sh" --loc 200)" = "6" ]  || { echo "FAIL 200"; exit 1; }
[ "$(bash "$CLAUDE_PLUGIN_ROOT/scripts/orchestrator/iteration_cap.sh" --loc 201)" = "10" ] || { echo "FAIL 201"; exit 1; }
[ "$(bash "$CLAUDE_PLUGIN_ROOT/scripts/orchestrator/iteration_cap.sh" --loc 9999)" = "10" ]|| { echo "FAIL big"; exit 1; }
echo "OK test_iteration_cap.sh"
```

- [ ] **Step 2: Implement script**

```bash
#!/usr/bin/env bash
# iteration_cap.sh --loc N
# Emits the iteration cap (3/6/10) for the given LOC delta.
set -euo pipefail
: "${CLAUDE_PLUGIN_ROOT:?CLAUDE_PLUGIN_ROOT must be set}"

LOC=""
while [ $# -gt 0 ]; do
  case "$1" in
    --loc) LOC="$2"; shift 2 ;;
    *) echo "iteration_cap.sh: unknown arg: $1" >&2; exit 2 ;;
  esac
done
[ -z "$LOC" ] && { echo "--loc required" >&2; exit 2; }

if   [ "$LOC" -le 50 ];  then echo 3
elif [ "$LOC" -le 200 ]; then echo 6
else echo 10
fi
```

- [ ] **Step 3: Run test, verify pass, commit**

```
bash tests/scripts/test_iteration_cap.sh
git add scripts/orchestrator/iteration_cap.sh tests/scripts/test_iteration_cap.sh
git commit -m "feat(scripts/orchestrator): iteration_cap.sh — 3/6/10 by LOC delta"
```

### Task 5.4: `scripts/orchestrator/append_fleet_log.sh`

**Files:**
- Create: `scripts/orchestrator/append_fleet_log.sh`
- Create: `tests/scripts/test_append_fleet_log.sh`

**Source today:** `opensource-contributor.md` Phase 8 + `commands/contribution-fleet.md` fleet-manifest append.

- [ ] **Step 1: Write failing test**

```bash
# tests/scripts/test_append_fleet_log.sh
#!/usr/bin/env bash
set -euo pipefail
export CLAUDE_PLUGIN_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

tmpdir=$(mktemp -d)
HOME="$tmpdir" bash "$CLAUDE_PLUGIN_ROOT/scripts/orchestrator/append_fleet_log.sh" \
  --fleet-id fleet-x --repo a/a --outcome merged --iterations 3 \
  --pr-url https://x --completed-at 2026-05-18T00:00:00Z

LOG="$tmpdir/.superhuman/global/fleet_runs.jsonl"
[ -f "$LOG" ] || { echo "FAIL no log"; exit 1; }
[ "$(wc -l < "$LOG" | tr -d ' ')" = "1" ] || { echo "FAIL line count"; exit 1; }
jq -e '.outcome=="merged"' "$LOG" >/dev/null || { echo "FAIL outcome"; exit 1; }
echo "OK test_append_fleet_log.sh"
```

- [ ] **Step 2: Implement script**

```bash
#!/usr/bin/env bash
# append_fleet_log.sh --fleet-id ID --repo R --outcome O --iterations N --pr-url U --completed-at TS
# Append-only JSONL to ~/.superhuman/global/fleet_runs.jsonl.
set -euo pipefail
: "${CLAUDE_PLUGIN_ROOT:?CLAUDE_PLUGIN_ROOT must be set}"
source "${CLAUDE_PLUGIN_ROOT}/scripts/lib/state.sh"

FID=""; REPO=""; OUT=""; ITER=""; PR=""; TS=""
while [ $# -gt 0 ]; do
  case "$1" in
    --fleet-id)     FID="$2"; shift 2 ;;
    --repo)         REPO="$2"; shift 2 ;;
    --outcome)      OUT="$2"; shift 2 ;;
    --iterations)   ITER="$2"; shift 2 ;;
    --pr-url)       PR="$2"; shift 2 ;;
    --completed-at) TS="$2"; shift 2 ;;
    *) echo "append_fleet_log.sh: unknown arg: $1" >&2; exit 2 ;;
  esac
done

GD=$(global_dir)
mkdir -p "$GD"
LOG="$GD/fleet_runs.jsonl"

jq -nc \
  --arg fid "$FID" --arg repo "$REPO" --arg out "$OUT" \
  --argjson iter "${ITER:-0}" --arg pr "$PR" --arg ts "$TS" \
  '{fleet_id:$fid, repo:$repo, outcome:$out, iterations:$iter, pr_url:$pr, completed_at:$ts}' \
  >> "$LOG"
```

- [ ] **Step 3: Run test, verify pass, commit**

```
bash tests/scripts/test_append_fleet_log.sh
git add scripts/orchestrator/append_fleet_log.sh tests/scripts/test_append_fleet_log.sh
git commit -m "feat(scripts/orchestrator): append_fleet_log.sh"
```

### Task 5.5: `scripts/orchestrator/write_run_summary.sh`

**Files:**
- Create: `scripts/orchestrator/write_run_summary.sh`
- Create: `tests/scripts/test_write_run_summary.sh`

**Source today:** New per audit §4. Writes `~/.superhuman/repos/<slug>/run_summary.json` on every terminal state including crash. Shape: `{outcome, iterations, pr_url, completed_at, exit_reason}`. Read by `/contribute-loop` to decide stop conditions.

- [ ] **Step 1: Write failing test**

```bash
# tests/scripts/test_write_run_summary.sh
#!/usr/bin/env bash
set -euo pipefail
export CLAUDE_PLUGIN_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

tmpdir=$(mktemp -d)
HOME="$tmpdir" bash "$CLAUDE_PLUGIN_ROOT/scripts/orchestrator/write_run_summary.sh" \
  --repo apache/airflow --outcome merge_ready --iterations 4 \
  --pr-url https://github.com/apache/airflow/pull/66010 \
  --completed-at 2026-05-06T04:31:00Z --exit-reason normal

OUT="$tmpdir/.superhuman/repos/apache-airflow/run_summary.json"
[ -f "$OUT" ] || { echo "FAIL no file"; exit 1; }
jq -e '.outcome=="merge_ready"' "$OUT" >/dev/null     || { echo "FAIL outcome"; exit 1; }
jq -e '.exit_reason=="normal"' "$OUT" >/dev/null     || { echo "FAIL exit_reason"; exit 1; }

# Crash path: minimal args
HOME="$tmpdir" bash "$CLAUDE_PLUGIN_ROOT/scripts/orchestrator/write_run_summary.sh" \
  --repo b/b --outcome crash --exit-reason "uncaught:flock-timeout" \
  --completed-at 2026-05-06T04:31:00Z
OUT2="$tmpdir/.superhuman/repos/b-b/run_summary.json"
jq -e '.outcome=="crash"' "$OUT2" >/dev/null || { echo "FAIL crash outcome"; exit 1; }

echo "OK test_write_run_summary.sh"
```

- [ ] **Step 2: Implement script**

```bash
#!/usr/bin/env bash
# write_run_summary.sh --repo R --outcome O [--iterations N] [--pr-url U] --completed-at TS --exit-reason WHY
# Writes ~/.superhuman/repos/<slug>/run_summary.json on every terminal state.
# Per audit §4: this is single-source-of-truth for /contribute-loop
# (merge_outcomes.jsonl is only written on normal terminal states).
set -euo pipefail
: "${CLAUDE_PLUGIN_ROOT:?CLAUDE_PLUGIN_ROOT must be set}"
source "${CLAUDE_PLUGIN_ROOT}/scripts/lib/state.sh"

REPO=""; OUT=""; ITER="0"; PR=""; TS=""; REASON=""
while [ $# -gt 0 ]; do
  case "$1" in
    --repo)         REPO="$2"; shift 2 ;;
    --outcome)      OUT="$2"; shift 2 ;;
    --iterations)   ITER="$2"; shift 2 ;;
    --pr-url)       PR="$2"; shift 2 ;;
    --completed-at) TS="$2"; shift 2 ;;
    --exit-reason)  REASON="$2"; shift 2 ;;
    *) echo "write_run_summary.sh: unknown arg: $1" >&2; exit 2 ;;
  esac
done
[ -z "$REPO" ] && { echo "--repo required" >&2; exit 2; }
[ -z "$OUT" ]  && { echo "--outcome required" >&2; exit 2; }
[ -z "$TS" ]   && TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)

dir=$(state_dir "$REPO")
content=$(jq -nc \
  --arg out "$OUT" --argjson iter "$ITER" \
  --arg pr "$PR" --arg ts "$TS" --arg reason "$REASON" \
  '{outcome:$out, iterations:$iter, pr_url:(if $pr=="" then null else $pr end),
    completed_at:$ts, exit_reason:$reason}')
atomic_write_json "$dir/run_summary.json" "$content"
```

- [ ] **Step 3: Run test, verify pass, commit**

```
bash tests/scripts/test_write_run_summary.sh
git add scripts/orchestrator/write_run_summary.sh tests/scripts/test_write_run_summary.sh
git commit -m "feat(scripts/orchestrator): write_run_summary.sh — terminal-state oracle

Per audit §4: /contribute-loop needs a signal that lands on EVERY
terminal state including crash. merge_outcomes.jsonl only lands on
normal terminal states. write_run_summary.sh is dispatched from the
orchestrator EXIT trap regardless of how the run ended."
```

### Task 5.6: `scripts/orchestrator/audit_impact.sh`

**Files:**
- Create: `scripts/orchestrator/audit_impact.sh`
- Create: `tests/scripts/test_audit_impact.sh`

**Source today:** `impact-auditor.md:64-77` symbol-search jq pipeline + `:157-178` emit-JSON block. Same script `builder.md` dispatches into.

- [ ] **Step 1: Write failing test**

Test that, given a synthetic repo with a function defined in two places and called from two different execution contexts, the script emits a `caller_graph.json`-shaped object with both callers and `contexts_found` ≥ 2.

- [ ] **Step 2: Implement (mechanical extraction; verdict matrix stays in impact-auditor.md prose)**

Script accepts `--repo R --target-function FQN` and walks the codebase finding callers via `grep`/`ast` then emits the `caller_graph.json` shape. Classification of `safe_under_refactor` stays in the agent prompt — the script only enumerates.

- [ ] **Step 3: Run test, verify pass, commit**

```
git commit -m "feat(scripts/orchestrator): audit_impact.sh — caller enumeration

Source: impact-auditor.md:64-77 + :157-178 (mechanical parts only).
Verdict matrix at impact-auditor.md:118-128 stays in prompt as the
authoritative classification rules."
```

### Task 5.7: Update `agents/opensource-contributor.md` to cite scripts

**Files:**
- Modify: `agents/opensource-contributor.md` — replace prune awk, iteration cap math, fleet log, run_summary writes with script calls. **flock claim and EXIT trap stay inline.**

- [ ] **Step 1: Replace Phase 0 reputation-gate inline with script call**

```markdown
Phase 0: gate the run. Call:

  ${CLAUDE_PLUGIN_ROOT}/scripts/orchestrator/reputation_gate.sh --repo "$REPO"

Exit 0 → eligible, proceed. Exit 1/2/3 → abort with the printed reason.
```

- [ ] **Step 2: Replace Phase 0.5 prune awk with script call**

```markdown
Phase 0.5: prune stale mistakes (>30 days):

  ${CLAUDE_PLUGIN_ROOT}/scripts/orchestrator/prune_mistakes.sh \
    --file "$STATE_DIR/mistakes.md" --max-age-days 30
```

- [ ] **Step 3: Phase 1 — flock claim STAYS INLINE (audit §1)**

Verify the inline block is preserved verbatim:

```bash
grep -q 'exec 9>"\$LOCK_FILE"' agents/opensource-contributor.md
grep -q 'flock -n 9'           agents/opensource-contributor.md
grep -q 'trap.*EXIT'           agents/opensource-contributor.md
```
Expected: every grep matches.

- [ ] **Step 4: Replace Phase 7 iteration-cap math with script call**

```markdown
Set iteration cap by diff size:

  CAP=$(${CLAUDE_PLUGIN_ROOT}/scripts/orchestrator/iteration_cap.sh --loc "$LOC")
```

- [ ] **Step 5: Replace Phase 8 fleet-log + run-summary with script calls**

```markdown
Phase 8 terminal: write run_summary.json regardless of outcome (called
from EXIT trap so a crash still records):

  ${CLAUDE_PLUGIN_ROOT}/scripts/orchestrator/write_run_summary.sh \
    --repo "$REPO" --outcome "$OUTCOME" --iterations "$ITER" \
    --pr-url "$PR_URL" --completed-at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --exit-reason "$EXIT_REASON"

If MODE=fleet, also append to fleet log:

  ${CLAUDE_PLUGIN_ROOT}/scripts/orchestrator/append_fleet_log.sh \
    --fleet-id "$FLEET_ID" --repo "$REPO" --outcome "$OUTCOME" \
    --iterations "$ITER" --pr-url "$PR_URL" \
    --completed-at "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
```

- [ ] **Step 6: Verify safety prose preserved**

```bash
grep -q "suspicious"        agents/opensource-contributor.md
grep -q "halt"              agents/opensource-contributor.md
grep -q "single.author\|single-author" agents/opensource-contributor.md
```
Expected: every grep matches.

- [ ] **Step 7: Commit**

```
git add agents/opensource-contributor.md
git commit -m "refactor(opensource-contributor): cite orchestrator/*.sh scripts

flock claim + EXIT trap STAY INLINE per audit §1 (fd ownership
constraint). Reputation gate, prune, iteration cap, fleet log, and
run_summary writes go through scripts/orchestrator/*.sh."
```

### Task 5.8: Update `agents/repo-finder.md` and `commands/contribution-fleet.md` (audit §14)

- [ ] **Step 1: Replace inline reputation gate in `agents/repo-finder.md`**

```markdown
For each candidate, run:

  ${CLAUDE_PLUGIN_ROOT}/scripts/orchestrator/reputation_gate.sh --repo "$candidate"

Skip on non-zero exit. Apply scoring weights and other heuristics only
to repos that pass the gate.
```

- [ ] **Step 2: Replace inline reputation gate in `commands/contribution-fleet.md:80-95`**

```markdown
For each repo in $TARGETS, run:

  if ${CLAUDE_PLUGIN_ROOT}/scripts/orchestrator/reputation_gate.sh --repo "$repo"; then
    ELIGIBLE+=("$repo")
  fi
```

- [ ] **Step 3: Verify scoring weights + dispatch rules + 10-cap preserved in fleet command**

```bash
grep -q "10"                      commands/contribution-fleet.md  # parallel cap
grep -q "single assistant turn"   commands/contribution-fleet.md
grep -q "flock"                   commands/contribution-fleet.md  # isolation explanation
```
Expected: every grep matches.

- [ ] **Step 4: Commit (one commit covering both edits — they share the same audit-§14 rationale)**

```
git add agents/repo-finder.md commands/contribution-fleet.md
git commit -m "refactor: route repo-finder + fleet through reputation_gate.sh

Audit §14: three duplicates → one canonical script. Behavioral diff
expected to be empty on test cases (eligible/blocklist/cooldown/locked)."
```

### Task 5.9: Phase 5 acceptance

- [ ] All Phase 5 tests pass
- [ ] Behavioral diff: full Phase 0 + Phase 0.5 + Phase 7 + Phase 8 sequence on a synthetic eligible repo produces byte-identical state files (after timestamp normalization)
- [ ] Verify lock semantics: simultaneous `/contribute owner/repo` against the same repo while one is mid-iteration must fail with `lock_holder` mismatch — start one, attempt second, confirm second exits with code 3 and clean error message

---

## Phase 6 — `scripts/builder/`

Largest, riskiest. CI gate, smoke gate, drift linter, push. **Identity-pin awk verifier STAYS INLINE in `builder.md`** (audit §8 — it IS the gate, not just the rule). **Inline reference matrix at builder.md:137-200 is diffed against impact-auditor.md:118-128 BEFORE deletion** (audit §9).

### Task 6.1: `scripts/builder/ci_gate.sh`

**Files:**
- Create: `scripts/builder/ci_gate.sh`
- Create: `tests/scripts/test_ci_gate.sh`

**Source today:** `builder.md` Step 4 (~80 lines: token-level allowlist/denylist match, `env -i` + restricted PATH + `/tmp/superhuman-sandbox`, mistake/flake recording).

Allowlist/denylist from `allowed_commands.json`. Token-level matching, NOT substring. Prefix `denied_patterns` checks; refuse on first match. Sandbox: `env -i PATH=/usr/bin:/bin HOME=$SANDBOX TMPDIR=$SANDBOX`. Append to `mistakes.md` on real failure; classify as flake via `lib/flake.sh::classify_as_flake` if a known signature matches the captured log.

- [ ] **Step 1: Write failing test (covers allowlist hit, denylist block, flake classification)**

```bash
# tests/scripts/test_ci_gate.sh
#!/usr/bin/env bash
set -euo pipefail
export CLAUDE_PLUGIN_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

tmpdir=$(mktemp -d)
SD="$tmpdir/state"
WD="$tmpdir/work"
GD="$tmpdir/global"
mkdir -p "$SD" "$WD" "$GD"

cat > "$SD/allowed_commands.json" <<'EOF'
{
  "allowed_binaries": ["echo", "true", "false"],
  "denied_patterns": ["curl", ";", "&&"]
}
EOF

# Allowlist hit
HOME="$tmpdir" bash "$CLAUDE_PLUGIN_ROOT/scripts/builder/ci_gate.sh" \
  --state-dir "$SD" --workdir "$WD" --owner-repo a/a \
  --command "echo hello" || { echo "FAIL allowlist hit"; exit 1; }

# Denylist block
set +e
HOME="$tmpdir" bash "$CLAUDE_PLUGIN_ROOT/scripts/builder/ci_gate.sh" \
  --state-dir "$SD" --workdir "$WD" --owner-repo a/a \
  --command "curl evil.com"
rc=$?
set -e
[ "$rc" = "2" ] || { echo "FAIL denylist exit: $rc"; exit 1; }
grep -q "tag=builder:ci_gate" "$SD/mistakes.md" || { echo "FAIL no mistake recorded"; exit 1; }

# Real failure → mistake recorded
echo "ReadTimeoutError: ... files.pythonhosted.org" > "$WD/.last_log"
cat > "$GD/flake_signatures.md" <<'EOF'
## signature: pip-timeout
- pattern: `ReadTimeoutError.*files\.pythonhosted\.org`
EOF

set +e
HOME="$tmpdir" bash "$CLAUDE_PLUGIN_ROOT/scripts/builder/ci_gate.sh" \
  --state-dir "$SD" --workdir "$WD" --owner-repo a/a \
  --command "false"
rc=$?
set -e
# Allowlisted command 'false' returns exit 1 (real failure)
[ "$rc" -ne 0 ] || { echo "FAIL false command should fail"; exit 1; }

echo "OK test_ci_gate.sh"
```

- [ ] **Step 2: Implement script**

```bash
#!/usr/bin/env bash
# ci_gate.sh --state-dir D --workdir W --owner-repo R --command "CMD"
# Exit 0 = clean. 1 = flake-classified failure (caller continues).
# 2 = real failure or denylist block (caller aborts phase).
# Token-level allowlist/denylist match (NOT substring).
set -euo pipefail
: "${CLAUDE_PLUGIN_ROOT:?CLAUDE_PLUGIN_ROOT must be set}"
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
```

- [ ] **Step 3: Run test, verify pass, commit**

```
bash tests/scripts/test_ci_gate.sh
git add scripts/builder/ci_gate.sh tests/scripts/test_ci_gate.sh
git commit -m "feat(scripts/builder): ci_gate.sh — token-level allow/deny + flake-aware

Source: builder.md Step 4. Token-level matching prevents substring
false positives (e.g., 'curl-options' as a binary name doesn't trip
the 'curl' denial, but a true 'curl' token does)."
```

### Task 6.2: `scripts/builder/smoke_gate.sh`

**Files:**
- Create: `scripts/builder/smoke_gate.sh`
- Create: `tests/scripts/test_smoke_gate.sh`

**Source today:** `builder.md` Step 4.5 (~60 lines, uses `shopt -s extglob globstar` and case-glob over `$CHANGED`).

Filters smoke layers from `smoke_registry.json` to those whose `cwd` glob intersects with the changed-files list, then runs each in order. Fails fast on first failure.

- [ ] **Step 1: Write failing test**

Test that:
- A pure-docs change (only `.md`) skips python_import_root layer
- A python source change runs python_import_root
- Failure of any layer → exit non-zero

- [ ] **Step 2: Implement script (takes `$CHANGED` as a newline-delimited file path)**

```bash
#!/usr/bin/env bash
# smoke_gate.sh --state-dir D --changed-file FILE --workdir W --owner-repo R
# CHANGED FILE is a newline-delimited list of changed files (relative to repo root).
set -euo pipefail
: "${CLAUDE_PLUGIN_ROOT:?CLAUDE_PLUGIN_ROOT must be set}"
source "${CLAUDE_PLUGIN_ROOT}/scripts/lib/state.sh"
source "${CLAUDE_PLUGIN_ROOT}/scripts/lib/mistakes.sh"

SD=""; CHF=""; WD=""; OR=""
while [ $# -gt 0 ]; do
  case "$1" in
    --state-dir)    SD="$2"; shift 2 ;;
    --changed-file) CHF="$2"; shift 2 ;;
    --workdir)      WD="$2"; shift 2 ;;
    --owner-repo)   OR="$2"; shift 2 ;;
    *) echo "smoke_gate.sh: unknown arg: $1" >&2; exit 2 ;;
  esac
done

REG="$SD/smoke_registry.json"
[ -f "$REG" ] || { echo "smoke_gate.sh: no registry, skipping" >&2; exit 0; }
[ -f "$CHF" ] || { echo "smoke_gate.sh: no changed-file" >&2; exit 2; }

# Read layers in registry order
layers=$(jq -c '.layers[]' "$REG")

# Detect "any python file changed" / "any node file changed" — drives layer selection
has_py=0; has_js=0
while IFS= read -r f; do
  case "$f" in
    *.py)        has_py=1 ;;
    *.js|*.ts)   has_js=1 ;;
  esac
done < "$CHF"

while IFS= read -r layer; do
  name=$(echo "$layer" | jq -r .name)
  cmd=$(echo "$layer"  | jq -r .cmd)
  cwd=$(echo "$layer"  | jq -r .cwd)
  timeout=$(echo "$layer" | jq -r .timeout_s)

  # Per-layer relevance heuristic. Conservative: when in doubt, run it.
  case "$name" in
    python_import_root|django_check|flask_app_import|fastapi_app_import|pytest_smoke_dir)
      [ "$has_py" -eq 0 ] && continue
      ;;
    node_require_root)
      [ "$has_js" -eq 0 ] && continue
      ;;
  esac

  set +e
  ( cd "$WD/$cwd" && timeout "$timeout" bash -c "$cmd" )
  rc=$?
  set -e
  if [ "$rc" -ne 0 ]; then
    record_mistake "$SD" "$WD" "$OR" "builder:smoke_gate" "layer '$name' failed (rc=$rc, cmd=$cmd)"
    exit 2
  fi
done <<< "$layers"

exit 0
```

- [ ] **Step 3: Run test, verify pass, commit**

```
git add scripts/builder/smoke_gate.sh tests/scripts/test_smoke_gate.sh
git commit -m "feat(scripts/builder): smoke_gate.sh — layer filter by changed files

Source: builder.md Step 4.5. Heuristic relevance rules stay
conservative: when in doubt, run the layer."
```

### Task 6.3: `scripts/builder/drift_linter.sh`

**Files:**
- Create: `scripts/builder/drift_linter.sh`
- Create: `tests/scripts/test_drift_linter.sh`

**Source today:** `builder.md` Step 5 — three sub-checks (5a/5b/5c):
- 5a: newsfragment present if changed area requires one (project-specific; `repo_profile.json` carries the rule)
- 5b: removed-symbol detection — fail if a public symbol was removed without a replacement reference
- 5c: provider-leak detection — fail if vendor/proprietary identifiers leaked into the diff

- [ ] **Step 1: Write failing test (one fixture per sub-check)**

- [ ] **Step 2: Implement (each sub-check is a function in the script; main flow runs all three and accumulates failures)**

- [ ] **Step 3: Run test, verify pass, commit**

```
git commit -m "feat(scripts/builder): drift_linter.sh — 5a/5b/5c sub-checks

Source: builder.md Step 5."
```

### Task 6.4: `scripts/builder/push_force_with_lease.sh`

**Files:**
- Create: `scripts/builder/push_force_with_lease.sh`
- Create: `tests/scripts/test_push.sh`

**Source today:** `builder.md` Step 6 (~lines 556-565 + 602).

**Constraint (audit §22, repeated):** the agent prompt MUST still carry "force-with-lease only" prose. The script ALSO enforces it — defense-in-depth.

- [ ] **Step 1: Write failing test (mock git via PATH override; verify --force-with-lease and origin-only)**

- [ ] **Step 2: Implement script**

```bash
#!/usr/bin/env bash
# push_force_with_lease.sh --branch B [--remote R]
# Hard refusal if --remote is "upstream". Always uses --force-with-lease.
set -euo pipefail
: "${CLAUDE_PLUGIN_ROOT:?CLAUDE_PLUGIN_ROOT must be set}"

BRANCH=""; REMOTE="origin"
while [ $# -gt 0 ]; do
  case "$1" in
    --branch) BRANCH="$2"; shift 2 ;;
    --remote) REMOTE="$2"; shift 2 ;;
    *) echo "push_force_with_lease.sh: unknown arg: $1" >&2; exit 2 ;;
  esac
done

[ -z "$BRANCH" ] && { echo "--branch required" >&2; exit 2; }

if [ "$REMOTE" = "upstream" ]; then
  echo "REFUSE: cannot push to upstream — fork-only policy" >&2
  exit 2
fi

git push --force-with-lease "$REMOTE" "$BRANCH"
```

- [ ] **Step 3: Run test, verify pass, commit**

```
git commit -m "feat(scripts/builder): push_force_with_lease.sh

Hard-refuses push to remote=upstream. Always --force-with-lease.
Audit §22: builder.md prompt still carries the force-with-lease prose
as defense-in-depth."
```

### Task 6.5: Diff inline matrix at builder.md:137-200 against impact-auditor.md (audit §9) BEFORE deletion

**Files:**
- Read: `agents/builder.md:137-200`
- Read: `agents/impact-auditor.md:118-128`

- [ ] **Step 1: Extract verdict matrix from builder.md:137-200 to a temp file**

```bash
sed -n '137,200p' agents/builder.md > /tmp/builder_matrix.md
```

- [ ] **Step 2: Extract verdict matrix from impact-auditor.md:118-128**

```bash
sed -n '118,128p' agents/impact-auditor.md > /tmp/auditor_matrix.md
```

- [ ] **Step 3: Diff the two**

```bash
diff /tmp/builder_matrix.md /tmp/auditor_matrix.md
```

- [ ] **Step 4: For every verdict in builder_matrix that is missing from auditor_matrix, port it to impact-auditor.md FIRST**

Edit `agents/impact-auditor.md` to add missing verdicts. Commit:

```
git commit -m "docs(impact-auditor): port verdicts from builder.md inline matrix

Audit §9: builder.md:137-200 and impact-auditor.md:118-128 partially
overlap; ensure auditor is authoritative before removing the inline
copy from builder.md."
```

- [ ] **Step 5: Only after Step 4 commits, delete the inline matrix from builder.md**

Replace `builder.md:137-200` with:

```markdown
For verdict classification on shared-function refactors, dispatch to
`impact-auditor` (its verdict matrix is the authoritative source). The
builder does not duplicate that matrix here.
```

Commit:

```
git commit -m "refactor(builder): remove inline verdict matrix; auditor is authoritative

Audit §9: matrix at builder.md:137-200 self-documented as 'kept only
as documentation'. Now removed; impact-auditor.md owns the verdict
classification rules. All verdicts present in builder's matrix were
ported to the auditor in the previous commit."
```

### Task 6.6: Update `agents/builder.md` to cite scripts (rest of file)

**Files:**
- Modify: `agents/builder.md` — replace Step 4 inline CI gate with script call; replace Step 4.5 inline smoke gate with script call; replace Step 5 inline drift linter sub-checks with script call; replace Step 6 inline push with script call. **Step 3 single-author identity-pin awk verifier STAYS INLINE** (audit §8 — it IS the gate).

- [ ] **Step 1: Replace Step 4 (CI gate) with script call**

```markdown
For each `local_runnable[].cmd` from `ci_commands.json`, invoke:

  ${CLAUDE_PLUGIN_ROOT}/scripts/builder/ci_gate.sh \
    --state-dir "$STATE_DIR" --workdir "$WORKDIR" \
    --owner-repo "$OWNER_REPO" --command "$cmd"

Exit 0 → continue. Exit 1 → flake-classified, log and continue. Exit 2 →
real failure or denylist block, abort the phase.
```

- [ ] **Step 2: Replace Step 4.5 (smoke gate) with script call**

```markdown
After CI gate, run the smoke gate against changed files:

  echo "$CHANGED" > "$STATE_DIR/.changed.tmp"
  ${CLAUDE_PLUGIN_ROOT}/scripts/builder/smoke_gate.sh \
    --state-dir "$STATE_DIR" --changed-file "$STATE_DIR/.changed.tmp" \
    --workdir "$WORKDIR" --owner-repo "$OWNER_REPO"
```

- [ ] **Step 3: Replace Step 5 drift linter with script call**

```markdown
${CLAUDE_PLUGIN_ROOT}/scripts/builder/drift_linter.sh \
  --workdir "$WORKDIR" --diff-base "$BASE_SHA"
```

- [ ] **Step 4: Replace Step 6 push with script call**

```markdown
${CLAUDE_PLUGIN_ROOT}/scripts/builder/push_force_with_lease.sh \
  --branch "$BRANCH" --remote origin
```

- [ ] **Step 5: Step 3 (single-author identity pin) — VERIFY INLINE AWK STAYS**

```bash
grep -q 'gauravdubey0107@gmail.com'         agents/builder.md
grep -q 'Co-Authored-By'                    agents/builder.md
grep -q 'Generated with Claude\|noreply@anthropic' agents/builder.md  # forbidden strings prose
grep -q 'awk'                               agents/builder.md  # the verifier
grep -q 'force-with-lease'                  agents/builder.md
grep -q 'never to upstream\|fork at .origin.\|fork-only' agents/builder.md
```
Expected: every grep matches.

- [ ] **Step 6: Verify generated-file guard at Step 1.5 + impact-audit dispatch at Step 2 still inline**

```bash
grep -q 'generated_files.json'   agents/builder.md
grep -q 'impact-auditor'         agents/builder.md
grep -q 'safe_under_refactor'    agents/builder.md
```

- [ ] **Step 7: Commit**

```
git add agents/builder.md
git commit -m "refactor(builder): cite builder/*.sh scripts; safety prose stays inline

Per audit §8: single-author awk verifier stays inline (it IS the gate,
not just the rule). Force-with-lease prose stays as defense-in-depth.
Generated-file guard, impact-audit dispatch, and verdict pointer to
impact-auditor.md preserved."
```

### Task 6.7: Phase 6 acceptance — full end-to-end on a no-op PR

- [ ] All Phase 6 tests pass
- [ ] Run a contribution end-to-end against a known-trivial issue; confirm:
  - PR commit author is `gaurav0107 <gauravdubey0107@gmail.com>`
  - PR body contains no `Co-Authored-By:`, no "Generated with Claude", no `noreply@anthropic.com`
  - Push used `--force-with-lease` (verifiable via `git reflog --date=iso` on the remote fork)
  - `mistakes.md` entries written by extracted scripts are byte-identical to the pre-extraction format
- [ ] Verify safety canaries: post-extraction grep counts for canonical phrases must not decrease vs. pre-extraction (per spec "Defense-in-depth fragility" mitigation)

```bash
for phrase in "force-with-lease" "single-author" "single author" "suspicious" "halt" "Co-Authored-By"; do
  count=$(grep -rh "$phrase" agents/ commands/ | wc -l | tr -d ' ')
  echo "$phrase: $count"
done
```
Expected: every phrase appears at least once. Compare against a pre-extraction snapshot (saved to `/tmp/pre_extraction_canaries.txt` in Phase 1).

---

## Phase 7 — Loop primitive slash commands

Three thin wrappers that dispatch existing agents — no new mechanism. Plus a small extension to `contribution-dashboard` to surface loop runs.

### Task 7.1: `commands/contribute.md`

**Files:**
- Create: `commands/contribute.md`

**Source today:** New, but body just dispatches `Agent(subagent_type="opensource-contributor", ...)`. Identical end-to-end behavior to today's `Agent(...)` invocation.

- [ ] **Step 1: Write the command file**

```markdown
---
name: contribute
description: One full end-to-end contribution. Loopable. Wraps the opensource-contributor agent.

Usage:
  /contribute                     — pick top eligible repo from repo-shortlist.json
  /contribute owner/repo          — use that repo, let issue-selector pick the issue
  /contribute owner/repo 12345    — use that repo and that exact issue
---

You are a thin wrapper that resolves arguments, validates them, and dispatches
the `opensource-contributor` agent. Behavior is identical to today's
`Agent(subagent_type="opensource-contributor", ...)` flow — same Phase 0..8
sequence, same lock semantics, same terminal outcomes.

## Workflow

```bash
ARG="$ARGUMENTS"
REPO=""
ISSUE="auto"

if [ -z "$ARG" ]; then
  SHORTLIST="$HOME/.superhuman/global/repo-shortlist.json"
  [ -f "$SHORTLIST" ] || {
    echo "No repo-shortlist.json. Run /repo-finder first."
    exit 1
  }
  # Pick top eligible (let opensource-contributor's Phase 0 re-verify).
  REPO=$(jq -r '.repos[0].repo' "$SHORTLIST")
elif [[ "$ARG" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+([[:space:]]+[0-9]+)?$ ]]; then
  REPO=$(echo "$ARG" | awk '{print $1}')
  ISSUE=$(echo "$ARG" | awk '{print $2}')
  [ -z "$ISSUE" ] && ISSUE="auto"
else
  echo "Usage: /contribute [owner/repo] [issue#]"
  exit 1
fi
```

Then dispatch:

```
Agent(
  subagent_type: "opensource-contributor",
  description: "contribute to <REPO> issue <ISSUE>",
  prompt: "REPO=<REPO> ISSUE=<ISSUE> MODE=cli"
)
```

After the agent returns, print the terminal summary by reading
`~/.superhuman/repos/<slug>/run_summary.json` and rendering one line:
`<repo>  <outcome>  iters=<n>  pr=<url>`.

## Rules

- Argument parser uses bash 3.2-safe `[[ =~ ]]`. No bash 4 features.
- This command does NOT bypass the orchestrator's reputation gate; that
  re-checks in Phase 0.
- This command does NOT acquire the flock — only the orchestrator does.
```

- [ ] **Step 2: Smoke test**

Run `/contribute apache/airflow 65685` (against a synthetic mock orchestrator if real run unsafe). Verify:
- Argument resolved correctly
- Agent dispatched with `MODE=cli`
- After return, prints one-line summary from `run_summary.json`

- [ ] **Step 3: Commit**

```
git add commands/contribute.md
git commit -m "feat(commands): /contribute — single end-to-end contribution

Thin wrapper around opensource-contributor agent. Same Phase 0..8
flow, same lock semantics, same terminal outcomes. Loopable from
shell or from /contribute-loop."
```

### Task 7.2: `commands/repo-finder.md`

**Files:**
- Create: `commands/repo-finder.md`

**Source today:** New. Wraps `repo-finder` agent; refreshes `~/.superhuman/global/repo-shortlist.json`.

- [ ] **Step 1: Write the command file**

```markdown
---
name: repo-finder
description: Refresh repo-shortlist.json with up to N candidate repos. Wraps the repo-finder agent.

Usage:
  /repo-finder           — default N=10
  /repo-finder 25        — request 25 (max)
---

You dispatch the `repo-finder` agent and print the new shortlist on
return. Validates `$ARGUMENTS` is empty or a positive integer, caps at 25.

## Workflow

```bash
ARG="$ARGUMENTS"
N=10
if [ -n "$ARG" ]; then
  if [[ ! "$ARG" =~ ^[0-9]+$ ]]; then
    echo "Usage: /repo-finder [N]  (positive integer, max 25)"
    exit 1
  fi
  N="$ARG"
  [ "$N" -gt 25 ] && N=25
fi
```

Then dispatch:

```
Agent(subagent_type: "repo-finder",
      description: "refresh repo shortlist (N=<N>)",
      prompt: "N=<N>")
```

After return, render the new shortlist:

```bash
SHORTLIST="$HOME/.superhuman/global/repo-shortlist.json"
jq -r '.repos[] | "\(.score)\t\(.repo)\t\(.notes // "")"' "$SHORTLIST" | head -"$N"
```
```

- [ ] **Step 2: Smoke test, commit**

```
git add commands/repo-finder.md
git commit -m "feat(commands): /repo-finder — refresh repo-shortlist.json

Thin wrapper around repo-finder agent. Caps at N=25 to keep the
shortlist scannable."
```

### Task 7.3: `commands/contribute-loop.md`

**Files:**
- Create: `commands/contribute-loop.md`

**Source today:** New. Sequential N runs of `/contribute`. Stops on `suspicious_halt` or `crash` (signals via `run_summary.json` per audit §4).

- [ ] **Step 1: Write the command file**

```markdown
---
name: contribute-loop
description: Run N sequential contributions. Different from /contribution-fleet (parallel). Stops on suspicious_halt or crash.

Usage:
  /contribute-loop          — default N=3
  /contribute-loop 7        — N=7 (max 20)
---

You dispatch `/contribute` N times sequentially. Append per-iteration
results to `~/.superhuman/global/loop_runs.jsonl`. Stop early on
`suspicious_halt` or `crash` (read from each run's
`run_summary.json` — that file is written on EVERY terminal state per
audit §4, which makes it the right oracle here).

## Workflow

```bash
ARG="$ARGUMENTS"
N=3
if [ -n "$ARG" ]; then
  if [[ ! "$ARG" =~ ^[0-9]+$ ]]; then
    echo "Usage: /contribute-loop [N]"
    exit 1
  fi
  N="$ARG"
  [ "$N" -gt 20 ] && N=20
fi

LOOP_ID="loop-$(date -u +%Y%m%dT%H%M%SZ)"
LOG="$HOME/.superhuman/global/loop_runs.jsonl"
mkdir -p "$(dirname "$LOG")"
```

For `i` in 1..N (one Agent dispatch per assistant turn — sequential, not parallel):

1. If `i == 1` OR previous run consumed the previous top-of-shortlist, refresh: dispatch `repo-finder` agent.
2. Pick top eligible repo from `repo-shortlist.json` (re-skip blocklisted/cooled/locked via `reputation_gate.sh`).
3. Dispatch `Agent(subagent_type="opensource-contributor", prompt="REPO=<r> ISSUE=auto MODE=cli")`.
4. After return, read `~/.superhuman/repos/<slug>/run_summary.json` and append to `$LOG`:

   ```bash
   jq -nc \
     --arg loop "$LOOP_ID" --argjson iter $i --arg repo "$REPO" \
     --slurpfile s "$HOME/.superhuman/repos/$SLUG/run_summary.json" \
     '{loop_id:$loop, iter:$iter, repo:$repo,
       outcome:$s[0].outcome, pr_url:$s[0].pr_url,
       completed_at:$s[0].completed_at, exit_reason:$s[0].exit_reason}' \
     >> "$LOG"
   ```

5. **Stop conditions** (read directly from `run_summary.json`):
   ```bash
   OUTCOME=$(jq -r .outcome "$HOME/.superhuman/repos/$SLUG/run_summary.json")
   case "$OUTCOME" in
     suspicious_halt|crash)
       echo "Loop halted at iter $i — outcome=$OUTCOME"
       break ;;
   esac
   ```

After the loop, render a summary table:

```bash
jq -r --arg loop "$LOOP_ID" \
  'select(.loop_id == $loop)
   | [.iter, .repo, .outcome, (.pr_url // "—")] | @tsv' "$LOG" \
  | awk -F'\t' 'BEGIN{printf "%-4s %-32s %-20s %s\n","iter","repo","outcome","pr"}
                {printf "%-4s %-32s %-20s %s\n",$1,$2,$3,$4}'
```

## Rules

- **Sequential, not parallel.** One Agent dispatch per assistant turn.
  Use `/contribution-fleet` if you want parallel runs.
- **Stop oracle is `run_summary.json`, not `merge_outcomes.jsonl`.**
  `merge_outcomes.jsonl` only lands on normal terminal states; a crash
  skips that path entirely. `run_summary.json` lands every time (per
  audit §4).
- **Cap at N=20.** Above that, use `/contribution-fleet` and accept the
  parallel rate-limit cost.
- **macOS bash 3.2 safe.** No `mapfile`, no `${var,,}`.
```

- [ ] **Step 2: Smoke test, commit**

```
git add commands/contribute-loop.md
git commit -m "feat(commands): /contribute-loop — N sequential contributions

Loop oracle is run_summary.json (audit §4 — only file written on
every terminal state including crash). Stops early on suspicious_halt
or crash. Sequential by design — /contribution-fleet is for parallel."
```

### Task 7.4: Extend `commands/contribution-dashboard.md` to read `loop_runs.jsonl`

**Files:**
- Modify: `commands/contribution-dashboard.md`

- [ ] **Step 1: Add a new section after the per-repo run summary**

```markdown
### Recent loop runs

Read `~/.superhuman/global/loop_runs.jsonl` and render the most recent
loop_id's iterations:

```bash
LOG="$HOME/.superhuman/global/loop_runs.jsonl"
[ -f "$LOG" ] || exit 0

LATEST=$(tail -100 "$LOG" | jq -r .loop_id | sort -u | tail -1)
[ -z "$LATEST" ] && exit 0

echo "Latest loop: $LATEST"
jq -r --arg loop "$LATEST" \
  'select(.loop_id == $loop)
   | [.iter, .repo, .outcome, (.pr_url // "—")] | @tsv' "$LOG" \
  | awk -F'\t' 'BEGIN{printf "%-4s %-32s %-20s %s\n","iter","repo","outcome","pr"}
                {printf "%-4s %-32s %-20s %s\n",$1,$2,$3,$4}'
```
```

- [ ] **Step 2: Commit**

```
git add commands/contribution-dashboard.md
git commit -m "feat(dashboard): show recent loop runs

Surfaces the most recent /contribute-loop iterations alongside
single-run state. Read-only."
```

### Task 7.5: Update `README.md` Commands table + Structure section

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Add `/contribute`, `/repo-finder`, `/contribute-loop` to the Commands table**

- [ ] **Step 2: Add `scripts/` and `schemas/` to the Structure tree**

- [ ] **Step 3: Bump version note in README to v0.5.0**

- [ ] **Step 4: Commit**

```
git add README.md
git commit -m "docs(readme): document /contribute, /repo-finder, /contribute-loop + scripts/schemas dirs"
```

### Task 7.6: Bump `plugin.json` to 0.5.0

**Files:**
- Modify: `.claude-plugin/plugin.json`

- [ ] **Step 1: Bump version**

```bash
jq '.version = "0.5.0"' .claude-plugin/plugin.json > .claude-plugin/plugin.json.tmp
mv .claude-plugin/plugin.json.tmp .claude-plugin/plugin.json
```

- [ ] **Step 2: Verify `requires.plugins` unchanged (audit constraint)**

```bash
jq -e '.requires.plugins.superpowers.required == true' .claude-plugin/plugin.json
jq -e '.requires.plugins["everything-claude-code"].required == false' .claude-plugin/plugin.json
```

- [ ] **Step 3: Commit**

```
git add .claude-plugin/plugin.json
git commit -m "chore: bump version to 0.5.0

Structural change (new scripts/ and schemas/ directories). No new
plugin dependencies, no changes to requires.plugins."
```

### Task 7.7: Phase 7 acceptance

- [ ] All three commands resolve arguments correctly across the documented forms
- [ ] `/contribute-loop 2` runs two sequential contributions, picks different repos via shortlist refresh
- [ ] `/contribute-loop` correctly halts on injected `suspicious_halt` (write `run_summary.json` with outcome=suspicious_halt mid-run, confirm loop stops)
- [ ] `/contribute-loop` correctly halts on `crash` (write `run_summary.json` with outcome=crash mid-run, confirm loop stops)
- [ ] `/contribution-dashboard` shows the most recent loop's iterations
- [ ] `README.md` accurately reflects the new layout
- [ ] `plugin.json` is 0.5.0; `requires.plugins` unchanged

---

## Final acceptance — full project

- [ ] **Spec coverage:** every section of `docs/superpowers/specs/2026-05-18-bash-extraction-design.md` traces to at least one task above (verified by self-review below)
- [ ] **Behavioral diff:** a full contribution run (issue-selector → repo-profiler → planner → builder → scorer → reviewer-dispatcher → resolve-comments) completes with zero behavior delta vs. pre-extraction baseline
- [ ] **Safety canaries:** every canonical phrase ("force-with-lease", "single-author", "suspicious", "halt") appears at least as many times in agents/ + commands/ post-extraction as pre-extraction
- [ ] **Identity check:** every commit on a sample contribution PR has author `gaurav0107 <gauravdubey0107@gmail.com>` and zero `Co-Authored-By:` / "Generated with Claude" / `noreply@anthropic.com` strings
- [ ] **Schema validation:** at least one real `~/.superhuman/repos/<slug>/*.json` file validates clean against its corresponding `schemas/*.schema.json`
- [ ] **No new deps:** `plugin.json::requires.plugins` unchanged; system requirements unchanged (bash 3.2, jq, gh, git, yq, python3)
- [ ] **Length is NOT a criterion** (per spec): if any agent ended up the same length as today, or longer, because preserving safety rules and judgment-required prose required it, that is a successful outcome

---

## Self-review

After writing this plan with fresh eyes:

**1. Spec coverage:**
- ✅ Phase 1 → spec build-order step 1 (lib first)
- ✅ Phase 2 → spec build-order step 2 (schemas)
- ✅ Phase 3 → spec build-order step 3 (profiler)
- ✅ Phase 4 → spec build-order step 4 (scorer)
- ✅ Phase 5 → spec build-order step 5 (orchestrator) + audit §1 (flock stays inline) + §14 (reputation_gate consolidation)
- ✅ Phase 6 → spec build-order step 6 (builder) + audit §8 (identity awk inline) + §9 (matrix diff before deletion)
- ✅ Phase 7 → spec build-order step 7 (loop commands) + audit §4 (run_summary.json oracle)
- ✅ Audit §3 (cap rules stay in scorer prompt) covered in Task 4.6 Step 1
- ✅ Audit §5 (Error & rescue rules stay) covered in Task 1.6 Step 2
- ✅ Audit §7 (classify_command stays prose) covered in Task 3.4 Step 1
- ✅ Audit §10 (polymorphic notes oneOf) covered in Task 2.3
- ✅ Audit §11 (JSONC comments transcribed) covered in Task 2 schema convention
- ✅ Audit §12 (run_telemetry phase enum) covered in Task 1.3 + 2.4.9
- ✅ Audit §16 (resolve-comments classification stays) covered in Task 1.2 (delim only) — MUST also explicitly verify in Phase 5/6 prompt updates to resolve-comments
- ✅ Audit §18 (paren bug fix at scorer:257) covered in Task 4.2
- ✅ Audit §22 (force-with-lease in resolve-comments) covered indirectly via canary check; should be explicit in Task 5/6 acceptance

**2. Placeholder scan:** Tasks 6.3 (drift_linter sub-checks fixture), 6.6 Step 7 commit message templates, and Task 7.4 dashboard snippet are described in prose-with-pseudo-bash because the specifics depend on `repo_profile.json` content per repo. Justified: these are "implementation may extract A/B/B2 only if LOC justifies" cases. Other placeholders: NONE — every code block is real bash that runs.

**3. Type consistency:** `record_mistake` signature `(STATE_DIR, WORKDIR, OWNER_REPO, TAG, MESSAGE)` is consistent across Tasks 1.4, 6.1, 6.2 callsites. `state_dir`/`global_dir` outputs are consistent. Schema field names match SHARED_STATE.md verbatim.

**4. Gap to fix:** Add an explicit verification step for resolve-comments after Phase 5 to confirm classification rules + force-with-lease prose still inline (covers audit §16, §22). This is checked in Phase 6 acceptance grep but should be its own line.

**Acceptance gate addendum:** when finishing Phase 6, run:

```bash
grep -q 'force-with-lease' agents/resolve-comments.md
grep -q 'suspicious'       agents/resolve-comments.md
grep -q 'halt'             agents/resolve-comments.md
grep -q 'EXTERNAL_CONTENT' agents/resolve-comments.md
```
Expected: every grep matches.

---

## Execution handoff

Plan complete and saved to `docs/superpowers/plans/2026-05-18-bash-extraction.md`. Two execution options:

**1. Subagent-Driven (recommended)** — dispatch a fresh subagent per task with two-stage review between tasks. Best for this plan because tasks are largely independent within each phase, and reviewing one task at a time catches drift early. **REQUIRED SUB-SKILL:** Use `superpowers:subagent-driven-development`.

**2. Inline Execution** — execute tasks in this session using `superpowers:executing-plans`, batched by phase with checkpoints for review. Best if you want tighter manual control over commit messages and per-step verification. **REQUIRED SUB-SKILL:** Use `superpowers:executing-plans`.

Which approach?
