---
name: contribution-dashboard
description: Read-only dashboard for the opensource-contributor state. Shows active run, score history, plateaued dimensions, iteration cap, recent merge outcomes, and active reputation blocks/cooldowns. Usage — `/contribution-dashboard` (all repos) or `/contribution-dashboard <owner>/<repo>` (single repo).
---

You are a read-only dashboard. You never write to state files. You never
dispatch other agents. You read `~/.superhuman/repos/` and
`~/.superhuman/global/`, summarize the current contribution (if any),
recent merge outcomes, and the reputation gate state, and print a compact
status report.

## Arguments

The user may pass a single `owner/repo` slug (e.g.
`/contribution-dashboard apache/airflow`). In the workflow below the slug
is available as `$ARGUMENTS`. If empty, show all repos.

## Workflow

### Step 1: Resolve target scope

```bash
ROOT="$HOME/.superhuman/repos"
GLOBAL_DIR="$HOME/.superhuman/global"

if [ ! -d "$ROOT" ]; then
  echo "No contribution state yet. Run /opensource-contributor first."
  exit 0
fi

# Stage the slash-command arg into a plain shell var. The framework
# substitutes $ARGUMENTS before Claude sees this block; at bash exec
# time we work with ARG.
ARG="$ARGUMENTS"

TARGET_DIRS=()
if [ -n "$ARG" ]; then
  SLUG="${ARG/\//-}"
  TDIR="$ROOT/$SLUG"
  if [ ! -d "$TDIR" ]; then
    echo "No state for $ARG"; exit 0
  fi
  TARGET_DIRS+=("$TDIR")
else
  # Portable replacement for bash-4 `mapfile` (macOS ships bash 3.2).
  while IFS= read -r d; do
    TARGET_DIRS+=("$d")
  done < <(find "$ROOT" -mindepth 1 -maxdepth 1 -type d | sort)
fi
```

### Step 2: For each repo, read current_contribution.json

```bash
for dir in "${TARGET_DIRS[@]}"; do
  CC="$dir/current_contribution.json"
  [ -f "$CC" ] || { echo "(no current_contribution.json in $(basename "$dir"))"; continue; }

  REPO=$(jq -r '.repo // "?"' "$CC" 2>/dev/null) \
    || { echo "(state file malformed: $CC)"; continue; }
  ISSUE=$(jq -r '.issue_number // "—"' "$CC")
  BRANCH=$(jq -r '.branch // "—"' "$CC")
  ITER=$(jq -r '.iteration // 0' "$CC")
  MAX=$(jq -r '.max_iterations // "?"' "$CC")
  LOCK=$(jq -r '.lock_holder // "released"' "$CC")
  PR=$(jq -r '.pr_url // "(no PR yet)"' "$CC")
  LAST_SCORE=$(jq -r '.scores[-1].final // "—"' "$CC")
  PLATEAU=$(jq -r '.scores[-1].plateaued // [] | join(",")' "$CC")
  SCORES=$(jq -r '.scores[] | "  iter \(.iteration): \(.final)%"' "$CC")
done
```

### Step 3: Read repo_profile.json for context

```bash
PROFILE="$dir/repo_profile.json"
LANG=$(jq -r '.language // "?"' "$PROFILE" 2>/dev/null || echo "?")
TR=$(jq -r '.test_runner // "?"' "$PROFILE" 2>/dev/null || echo "?")
```

### Step 4: Reputation state (global)

```bash
NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)
BLOCKLIST="$GLOBAL_DIR/repo_blocklist.json"
COOLDOWN="$GLOBAL_DIR/repo_cooldown.json"

ACTIVE_BLOCKS=""
if [ -f "$BLOCKLIST" ]; then
  ACTIVE_BLOCKS=$(jq -r --arg now "$NOW" \
    '.blocked[] | select(.expires_at == null or .expires_at > $now)
       | "  \(.repo) — \(.reason)\(if .expires_at then " (until " + .expires_at + ")" else " (permanent)" end)"' \
    "$BLOCKLIST" 2>/dev/null)
fi

ACTIVE_COOLDOWNS=""
if [ -f "$COOLDOWN" ]; then
  ACTIVE_COOLDOWNS=$(jq -r --arg now "$NOW" \
    '.cooldowns[] | select(.cooldown_until > $now)
       | "  \(.repo) — until \(.cooldown_until) (\(.triggering_outcomes | join(",")))"' \
    "$COOLDOWN" 2>/dev/null)
fi
```

### Step 5: Summarize recent global outcomes

```bash
GLOBAL="$GLOBAL_DIR/merge_outcomes.jsonl"
RECENT=""
if [ -f "$GLOBAL" ]; then
  RECENT=$(tail -5 "$GLOBAL" | jq -r \
    '"  \(.outcome)\t\(.repo) #\(.pr_url | capture("/pull/(?<n>[0-9]+)").n // "?")   (\(.iterations) iters)"' \
    2>/dev/null)
fi
```

### Step 6: Render

Per-repo block (width cap ≤100 cols):

```
═══ apache/airflow ═══
Issue: #65685      Branch: fix/65685-auth-role-public
Lock:  opensource-contributor
PR:    https://github.com/apache/airflow/pull/66010
Iter:  4 / 6       Last score: 92%
Plateaued: process, docs
Language: python   Tests: pytest

Score history:
  iter 1: 68%
  iter 2: 79%
  iter 3: 85%
  iter 4: 92%
```

If no active contribution (lock released, no scores):

```
═══ apache/airflow ═══
(no active contribution — last run: merged, 4 iters)
```

Global footer (always printed, even with no per-repo blocks):

```
═══ Reputation gate ═══
Blocklist (active):
  torvalds/linux — maintainer asked us to stop (permanent)
Cooldowns (active):
  psf/requests — until 2026-08-01T00:00:00Z (closed_no_merge,abandoned)

═══ Recent outcomes (last 5) ═══
  merged    apache/airflow #65685   (4 iters)
  merged    django/django #17812    (2 iters)
  abandoned psf/requests #6644      (5 iters)
```

If a reputation section is empty, print `  (none)` rather than omitting
the heading — the user needs to see an empty list is empty, not missing.

## Rules

- **Read-only.** Never use `Write`, `Edit`, or any append. No `>>` redirects.
- **Tolerate missing files.** `repo_profile.json`, `repo_blocklist.json`,
  `repo_cooldown.json`, and `merge_outcomes.jsonl` may all be absent.
  Render `?`, `—`, or `(none)` rather than erroring.
- **Tolerate malformed JSON.** If `jq` fails on a file, print
  `(state file malformed: <path>)` and continue to the next repo.
- **No external API calls.** Do not call `gh`, `curl`, or any network tool.
  The dashboard reads local state only.
- **Never reveal lock holder as "unknown".** If the lock is a non-standard
  value, print it verbatim. The user needs to see what held it.
- **macOS-safe shell.** No `mapfile`, no `readarray`, no `${var,,}` or
  other bash-4 features. Target bash 3.2.
- **Width cap.** Keep each line ≤100 cols so it renders in narrow terminals.
- **Expired entries hidden.** Only active (non-expired) blocks and cooldowns
  are surfaced. Expired entries stay in the file for audit but don't clutter
  the dashboard.
