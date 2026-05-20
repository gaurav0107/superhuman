---
name: repo-finder
description: Refresh repo-shortlist.json with up to N candidate repos. Wraps the repo-finder agent. Usage — `/repo-finder` (default N=10) or `/repo-finder 25` (request 25, capped at 25).
---

You are a thin wrapper around the `repo-finder` agent. You validate
`$ARGUMENTS`, dispatch the agent, then render the refreshed shortlist on
return. The agent does the discovery — searches GitHub, scores repos
against the rubric, applies the reputation gate, writes
`~/.superhuman/global/repo-shortlist.json`. This command exists so the
shortlist refresh is invokable directly from the REPL without remembering
the agent name.

## Workflow

### Step 1: Resolve arguments

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
  [ "$N" -lt 1 ]  && N=1
fi
```

The cap of 25 is deliberate: the shortlist is meant to be human-scannable
in the dashboard. Beyond 25 the per-repo scoring cost outpaces the value.

### Step 2: Dispatch the agent

```
Agent(
  subagent_type: "repo-finder",
  description: "refresh repo shortlist (N=<N>)",
  prompt: |
    N=<N>
    MODE=cli
)
```

### Step 3: Render the new shortlist

```bash
SHORTLIST="$HOME/.superhuman/global/repo-shortlist.json"
if [ ! -f "$SHORTLIST" ]; then
  echo "repo-finder agent did not write $SHORTLIST. Check its output."
  exit 1
fi

echo "Top $N candidates:"
jq -r '.repos[] | "\(.score)\t\(.repo)\t\(.notes // "")"' "$SHORTLIST" \
  | head -"$N" \
  | awk -F'\t' 'BEGIN{printf "%-6s %-32s %s\n","score","repo","notes"}
                {printf "%-6s %-32s %s\n",$1,$2,$3}'
```

## Rules

- **Cap at N=25.** Higher values waste GitHub search quota and produce a
  list humans cannot scan. The agent itself enforces this internally; the
  cap here is defense in depth.
- **Reputation gate is the agent's job.** Both the agent (during
  candidate scoring) and `opensource-contributor` Phase 0 (at dispatch
  time) re-check blocklist + cooldown + active-lock. This wrapper does
  not gate.
- **`$ARGUMENTS` is optional.** Empty defaults to N=10. Anything other
  than a positive integer is rejected with a usage line.
- **macOS bash 3.2 safe.** No bash 4 features.
