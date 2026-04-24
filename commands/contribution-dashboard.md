---
name: contribution-dashboard
description: Read-only dashboard for the opensource-contributor state. Shows active run, score history, plateaued dimensions, iteration cap, and recent merge outcomes. Usage — `/contribution-dashboard` (all repos) or `/contribution-dashboard <owner>/<repo>` (single repo).
---

You are a read-only dashboard. You never write to state files. You never
dispatch other agents. You read `~/.gstack/projects/superhuman/state/`,
summarize the current contribution (if any) and recent merge outcomes, and
print a compact status report.

## Arguments

- `$1` (optional) — an `owner/repo` slug. If omitted, show all repos with
  state directories.

## Workflow

### Step 1: Resolve target scope

```bash
ROOT="$HOME/.gstack/projects/superhuman/state"
if [ ! -d "$ROOT" ]; then
  echo "No contribution state yet. Run /opensource-contributor first."
  exit 0
fi

if [ -n "$1" ]; then
  SLUG="${1/\//-}"
  TARGET_DIRS=("$ROOT/$SLUG")
  [ ! -d "${TARGET_DIRS[0]}" ] && { echo "No state for $1"; exit 0; }
else
  # All non-global repo state dirs
  mapfile -t TARGET_DIRS < <(find "$ROOT" -mindepth 1 -maxdepth 1 -type d ! -name _global)
fi
```

### Step 2: For each repo, read current_contribution.json

```bash
for dir in "${TARGET_DIRS[@]}"; do
  REPO=$(jq -r .repo "$dir/current_contribution.json" 2>/dev/null) || continue
  ISSUE=$(jq -r '.issue_number // "—"' "$dir/current_contribution.json")
  BRANCH=$(jq -r '.branch // "—"' "$dir/current_contribution.json")
  ITER=$(jq -r '.iteration' "$dir/current_contribution.json")
  MAX=$(jq -r '.max_iterations // "?"' "$dir/current_contribution.json")
  LOCK=$(jq -r '.lock_holder // "released"' "$dir/current_contribution.json")
  PR=$(jq -r '.pr_url // "(no PR yet)"' "$dir/current_contribution.json")
  LAST_SCORE=$(jq -r '.scores[-1].final // "—"' "$dir/current_contribution.json")
  PLATEAU=$(jq -r '.scores[-1].plateaued // [] | join(",")' "$dir/current_contribution.json")
done
```

### Step 3: Read repo_profile.json for context

```bash
LANG=$(jq -r '.language // "?"' "$dir/repo_profile.json" 2>/dev/null)
TR=$(jq -r '.test_runner // "?"' "$dir/repo_profile.json" 2>/dev/null)
```

### Step 4: Summarize recent global outcomes

```bash
GLOBAL="$ROOT/_global/merge_outcomes.jsonl"
if [ -f "$GLOBAL" ]; then
  RECENT=$(tail -5 "$GLOBAL" | jq -c '{pr:.pr_url, outcome:.outcome, iters:.iterations}')
fi
```

### Step 5: Render

Per-repo block:

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

Global footer:

```
═══ Recent outcomes (last 5) ═══
  merged    apache/airflow #65685   (4 iters)
  merged    django/django #17812    (2 iters)
  abandoned psf/requests #6644      (5 iters)
```

If no active contribution (lock released, no scores):

```
═══ apache/airflow ═══
(no active contribution — last run: merged, 4 iters)
```

## Rules

- **Read-only.** Never use `Write`, `Edit`, or any append. No `>>` redirects.
  If you need to run `jq`, use `jq -r '...' file` without modifying anything.
- **Tolerate missing files.** `repo_profile.json` may be absent early in a
  run. Render `?` or `—` rather than erroring.
- **Tolerate malformed JSON.** If `jq` fails, print `(state file malformed)`
  and continue to the next repo.
- **No external API calls.** Do not call `gh`, `curl`, or any network tool.
  The dashboard reads local state only.
- **Never reveal lock holder as "unknown".** If the lock is a non-standard
  value, print it verbatim. The user needs to see what held it.
- **Width cap.** Keep each line ≤100 cols so it renders in narrow terminals.
