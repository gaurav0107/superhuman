---
name: contribute
description: One full end-to-end contribution. Loopable. Wraps the opensource-contributor agent. Usage — `/contribute` (auto-pick top eligible repo from repo-shortlist.json), `/contribute owner/repo` (let issue-selector pick the issue), or `/contribute owner/repo 12345` (use that exact issue).
---

You are a thin wrapper around the `opensource-contributor` agent. You
resolve `$ARGUMENTS`, validate it, dispatch the orchestrator, and print a
one-line summary on return. Behavior is identical to today's
`Agent(subagent_type="opensource-contributor", ...)` invocation — same
Phase 0..8 sequence, same lock semantics, same terminal outcomes. The
orchestrator does the real work; this command exists so the run is
loopable from the shell or from `/contribute-loop`.

## Workflow

### Step 1: Resolve arguments

```bash
ARG="$ARGUMENTS"
REPO=""
ISSUE="auto"

if [ -z "$ARG" ]; then
  SHORTLIST="$HOME/.superhuman/global/repo-shortlist.json"
  if [ ! -f "$SHORTLIST" ]; then
    echo "No repo-shortlist.json at $SHORTLIST."
    echo "Run /repo-finder first to seed it, or pass owner/repo explicitly."
    exit 1
  fi
  # Pick top of shortlist; opensource-contributor's Phase 0 reputation
  # gate re-verifies eligibility (blocklist + cooldown + active lock).
  REPO=$(jq -r '.repos[0].repo' "$SHORTLIST")
  if [ -z "$REPO" ] || [ "$REPO" = "null" ]; then
    echo "repo-shortlist.json has no candidates. Run /repo-finder."
    exit 1
  fi
elif [[ "$ARG" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+([[:space:]]+[0-9]+)?$ ]]; then
  REPO=$(echo "$ARG" | awk '{print $1}')
  MAYBE_ISSUE=$(echo "$ARG" | awk '{print $2}')
  [ -n "$MAYBE_ISSUE" ] && ISSUE="$MAYBE_ISSUE"
else
  echo "Usage: /contribute [owner/repo] [issue#]"
  echo "  /contribute                     — pick top eligible repo"
  echo "  /contribute owner/repo          — pick issue automatically"
  echo "  /contribute owner/repo 12345    — use that exact issue"
  exit 1
fi

SLUG="${REPO/\//-}"
```

### Step 2: Dispatch the orchestrator

```
Agent(
  subagent_type: "opensource-contributor",
  description: "contribute to <REPO> issue <ISSUE>",
  prompt: |
    REPO=<REPO>
    ISSUE=<ISSUE>
    MODE=cli

    Run the full Phase 0..8 sequence: reputation gate, fork+clone,
    profile, issue-selection (skip if ISSUE != "auto"), plan, build,
    open PR, iteration loop, terminal outcome. Honor the
    current_contribution.json lock semantics. On terminal state, write
    run_summary.json (audit §4: this lands on EVERY terminal state
    including crash so the wrapper can read it back).
)
```

### Step 3: Render the one-line summary

After the orchestrator returns, read `run_summary.json` and print one
line. The file lands on every terminal state (audit §4), so this is the
authoritative oracle for what just happened — the orchestrator's own
output may be truncated or, on crash, missing.

```bash
RS="$HOME/.superhuman/repos/$SLUG/run_summary.json"
if [ ! -f "$RS" ]; then
  echo "$REPO  no_run_summary  iters=?  pr=—"
  exit 1
fi

OUTCOME=$(jq -r '.outcome // "unknown"'      "$RS")
ITERS=$(  jq -r '.iterations // 0'           "$RS")
PR=$(     jq -r '.pr_url // "—"'             "$RS")
printf '%s  %s  iters=%s  pr=%s\n' "$REPO" "$OUTCOME" "$ITERS" "$PR"
```

## Rules

- **Argument parser uses bash 3.2-safe `[[ =~ ]]`.** No bash 4 features
  like `${var,,}` or `mapfile`.
- **This command does NOT bypass the orchestrator's reputation gate.**
  Phase 0 of `opensource-contributor` re-checks blocklist, cooldown, and
  active-lock. Skipping that here would let a single `/contribute
  banned/repo` invocation burn goodwill we cannot replace.
- **This command does NOT acquire the flock.** Only the orchestrator
  claims `~/.superhuman/repos/<slug>/.lock`. Wrapping the lock here
  would break two-process coordination (the orchestrator's `trap` would
  release a fd this command never opened).
- **Read `run_summary.json`, not stdout.** The orchestrator's output is
  human-readable; `run_summary.json` is structured and lands even on
  crash. The summary line above pulls outcome/iterations/PR from JSON.
- **Loopable.** This command is a building block for `/contribute-loop`
  (sequential N runs) and `/contribution-fleet` (parallel N runs).
  Neither dispatches `/contribute` directly — they dispatch the same
  agent — but the contract (one orchestrator run per invocation, summary
  via `run_summary.json`) is identical.
