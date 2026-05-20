---
name: contribution-fleet
description: Launch N `opensource-contributor` runs in parallel across different repos. Each run gets its own state directory, clone path, and flock(2) mutex — they cannot step on each other. Usage — `/contribution-fleet [N]` (auto-pick N repos from repo-shortlist) or `/contribution-fleet owner1/repo1 owner2/repo2 ...` (explicit list).
---

You are a fleet launcher. You dispatch multiple `opensource-contributor`
runs in parallel, one per target repo. You do not pick issues, profile
repos, plan, or build — each dispatched orchestrator does all of that for
its own repo. Your job is to resolve the target set, ensure the
cross-run invariants hold, and kick off the parallel dispatch in a single
assistant turn.

## Arguments

The user may pass either:
- An integer `N` — auto-select N repos from `repo-shortlist.json`
  (default N=3 if no argument).
- A space-separated list of `owner/repo` slugs — use exactly those.

The framework substitutes `$ARGUMENTS` before this body runs.

## Workflow

### Step 1: Resolve target set

```bash
GLOBAL_DIR="$HOME/.superhuman/global"
SHORTLIST="$GLOBAL_DIR/repo-shortlist.json"
ARG="$ARGUMENTS"
TARGETS=()

if [ -z "$ARG" ]; then
  N=3
elif [[ "$ARG" =~ ^[0-9]+$ ]]; then
  N="$ARG"
else
  # Explicit slugs
  for tok in $ARG; do
    if [[ "$tok" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]]; then
      TARGETS+=("$tok")
    else
      echo "SKIP malformed slug: $tok"
    fi
  done
fi

# Auto-mode: pull top N from the shortlist
if [ ${#TARGETS[@]} -eq 0 ]; then
  if [ ! -f "$SHORTLIST" ]; then
    echo "No repo-shortlist.json at $SHORTLIST."
    echo "Run /opensource-contributor (which dispatches repo-finder) once,"
    echo "or pass explicit owner/repo slugs to /contribution-fleet."
    exit 1
  fi
  while IFS= read -r r; do
    TARGETS+=("$r")
  done < <(jq -r --argjson n "$N" '.repos[:$n][].repo' "$SHORTLIST")
fi

if [ ${#TARGETS[@]} -eq 0 ]; then
  echo "No targets resolved. Aborting."
  exit 1
fi
```

### Step 2: Pre-flight — eligibility filter

Apply the reputation gate once before dispatch, so we don't spawn an
orchestrator that will immediately abort. This is advisory; each
dispatched orchestrator re-checks its own gate.

```bash
# Audit §14: reputation gate (blocklist + cooldown + active-lock check)
# is canonicalized in scripts/orchestrator/reputation_gate.sh. Both this
# command and opensource-contributor Phase 0 call the same script. The
# script prints SKIP/COOLDOWN/LOCKED reasons to stderr; we only need the
# exit code. Per-run orchestrators re-check at dispatch time, so this
# pre-flight pass is advisory — it just saves wasted dispatches.
ELIGIBLE=()
for repo in "${TARGETS[@]}"; do
  "${CLAUDE_PLUGIN_ROOT}/scripts/orchestrator/reputation_gate.sh" \
    --repo "$repo"
  case $? in
    0) ELIGIBLE+=("$repo") ;;        # eligible — fleet-dispatch
    1) ;;                             # blocklisted; reason printed
    2) ;;                             # cooldown; until-date printed
    3) ;;                             # lock held by another run
    *) echo "SKIP $repo (reputation_gate.sh unexpected exit)" ;;
  esac
done

if [ ${#ELIGIBLE[@]} -eq 0 ]; then
  echo "All candidate repos filtered out. Nothing to dispatch."
  exit 0
fi

# Hard cap at 10 parallel runs — above this we exhaust GitHub rate limits
# across fork, search, and clone APIs.
if [ ${#ELIGIBLE[@]} -gt 10 ]; then
  echo "Fleet capped at 10 (requested ${#ELIGIBLE[@]}). Trimming."
  ELIGIBLE=("${ELIGIBLE[@]:0:10}")
fi

echo "Fleet targets (${#ELIGIBLE[@]}):"
for r in "${ELIGIBLE[@]}"; do echo "  - $r"; done
```

### Step 3: Write the fleet manifest

One JSON line per dispatched run. The dashboard reads this to show
per-repo progress.

```bash
FLEET_LOG="$GLOBAL_DIR/fleet_runs.jsonl"
FLEET_ID="fleet-$(date -u +%Y%m%dT%H%M%SZ)"
mkdir -p "$GLOBAL_DIR"

for repo in "${ELIGIBLE[@]}"; do
  jq -c -n \
    --arg id "$FLEET_ID" \
    --arg repo "$repo" \
    --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    '{fleet_id:$id, repo:$repo, dispatched_at:$ts, status:"dispatched"}' \
    >> "$FLEET_LOG"
done

echo "Fleet id: $FLEET_ID"
```

### Step 4: Parallel dispatch

**Critical:** dispatch every eligible target in a SINGLE assistant turn
using parallel `Agent` tool calls. Claude Code's tool framework runs them
concurrently only when every call is emitted in the same response.
Sequential dispatches serialize.

For each `repo` in `ELIGIBLE`, emit one `Agent` call:

```
Agent(
  subagent_type: "opensource-contributor",
  description: "fleet run for <repo>",
  prompt: |
    REPO=<repo>
    FLEET_ID=<FLEET_ID>
    MODE=fleet

    You are running as part of a fleet dispatch. Your STATE_DIR and
    clone path are per-repo and already isolated via flock(2) and
    separate directory paths, so no coordination with siblings is
    needed. Run the full end-to-end workflow: eligibility, profile,
    issue, plan, build, PR, iteration loop, terminal outcome.

    At phase-8 terminal-outcome, append a JSONL entry to
    $HOME/.superhuman/global/fleet_runs.jsonl with:
      {fleet_id, repo, outcome, iterations, pr_url, completed_at}
)
```

All N dispatches go out in one batch. The fleet launcher then awaits
every sub-agent returning.

### Step 5: Aggregate (after all parallel dispatches return)

When every dispatched `opensource-contributor` returns, read the fleet
log and render a summary table:

```bash
FLEET_LOG="$HOME/.superhuman/global/fleet_runs.jsonl"
jq -r --arg id "$FLEET_ID" \
  'select(.fleet_id == $id and .outcome)
   | [.repo, .outcome, (.iterations // "—"), (.pr_url // "—")]
   | @tsv' "$FLEET_LOG" \
  | awk -F'\t' 'BEGIN{printf "%-32s %-20s %-6s %s\n","repo","outcome","iters","pr";}
                {printf "%-32s %-20s %-6s %s\n",$1,$2,$3,$4}'
```

Example rendered output:

```
Fleet fleet-20260506T043100Z — 3 runs

repo                             outcome              iters  pr
apache/airflow                   merge_ready          4      https://github.com/apache/airflow/pull/66010
django/django                    merged               2      https://github.com/django/django/pull/17812
psf/requests                     abandoned            5      https://github.com/psf/requests/pull/6644
```

## Rules

- **Dispatch in parallel, not sequentially.** All `Agent` calls go in
  one assistant turn. Sequential dispatch defeats the whole point.
- **Per-repo isolation is free.** `opensource-contributor` already uses
  `~/.superhuman/repos/<slug>/.lock` via `flock(2)` and clones to
  `/Users/mia/myspace/opensource-work/<repo>`. Two runs against the
  same repo cannot both succeed — the second will refuse the lock.
  The fleet launcher de-duplicates the target set anyway.
- **Never dispatch against a locked repo.** Step 2 checks
  `lock_holder`. If set, skip. Don't fight for the lock.
- **Reputation gate is advisory at fleet level.** The per-run
  orchestrator re-checks blocklist and cooldown. Step 2 filters early
  to avoid wasted dispatches, but the authoritative check lives in
  `opensource-contributor` Phase 0.
- **Hard cap at 10 parallel runs.** Above this we saturate GitHub
  rate limits across fork, search, and clone APIs.
- **Fleet log is append-only JSONL.** Never rewrite entries. Each
  dispatched run appends its own terminal-outcome line; the launcher
  appends only the initial dispatch records.
- **macOS-safe shell.** No `mapfile`, no `readarray`, no bash-4 features.
- **No shell polling after dispatch.** Do not `while true; do sleep`
  waiting on sub-agents. The tool framework handles concurrency and
  returns all results when every dispatched agent completes.
