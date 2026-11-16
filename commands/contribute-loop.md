---
name: contribute-loop
description: Run N sequential contributions. Different from /contribution-fleet (parallel). Stops early on suspicious_halt or crash. Usage — `/contribute-loop` (default N=3) or `/contribute-loop 7` (N=7, max 20).
---

You run N sequential `opensource-contributor` dispatches, refreshing the
repo shortlist between iterations as needed. You append per-iteration
results to `~/.superhuman/global/loop_runs.jsonl`. You stop early when
any iteration's terminal outcome is `suspicious_halt` or `crash` — read
from `run_summary.json` (audit §4: that file lands on EVERY terminal
state, including crashes that skip the normal `merge_outcomes.jsonl`
path, which makes it the only reliable oracle here).

`/contribution-fleet` is the parallel cousin. Use this when you want
serialised attempts (e.g. exhausting a single shortlist top-down) or
when GitHub rate limits make parallelism unsafe.

## Workflow

### Step 1: Resolve arguments

```bash
# Best-effort adoption telemetry (opt-out). Backgrounded + swallowed so it can
# never block or fail the command. See scripts/lib/usage_event.sh, TELEMETRY.md.
"${CLAUDE_PLUGIN_ROOT}/scripts/lib/usage_event.sh" --command contribute-loop >/dev/null 2>&1 & disown 2>/dev/null || true

ARG="$ARGUMENTS"
N=3
if [ -n "$ARG" ]; then
  if [[ ! "$ARG" =~ ^[0-9]+$ ]]; then
    echo "Usage: /contribute-loop [N]  (positive integer, max 20)"
    exit 1
  fi
  N="$ARG"
  [ "$N" -gt 20 ] && N=20
  [ "$N" -lt 1 ]  && N=1
fi

LOOP_ID="loop-$(date -u +%Y%m%dT%H%M%SZ)"
LOG="$HOME/.superhuman/global/loop_runs.jsonl"
mkdir -p "$(dirname "$LOG")"
echo "Loop id: $LOOP_ID  (N=$N)"
```

The cap at N=20 is the same trade-off as the fleet command's cap at 10:
above this we burn GitHub quota faster than the runs add value. Use
`/contribution-fleet` when parallelism is what you actually want.

### Step 2: Iterate (one Agent dispatch per assistant turn — sequential)

For `i` in `1..N`:

#### 2a: Refresh shortlist if needed

On the first iteration, OR when the previous iteration consumed the
top-of-shortlist, dispatch the `repo-finder` agent to refresh:

```
Agent(
  subagent_type: "repo-finder",
  description: "refresh shortlist before loop iter <i>",
  prompt: "N=10 MODE=cli"
)
```

#### 2b: Pick the next eligible repo

Apply the canonical reputation gate (`scripts/orchestrator/reputation_gate.sh`)
walking down the shortlist until one is eligible (exit 0). Repos that are
blocklisted (1), in cooldown (2), actively locked (3), or at the open-PR
cap (5) are skipped.

```bash
SHORTLIST="$HOME/.superhuman/global/repo-shortlist.json"
[ -f "$SHORTLIST" ] || { echo "no shortlist; aborting loop"; break; }

REPO=""
for r in $(jq -r '.repos[].repo' "$SHORTLIST"); do
  "${CLAUDE_PLUGIN_ROOT}/scripts/orchestrator/reputation_gate.sh" --repo "$r"
  case $? in
    0) REPO="$r"; break ;;
    *) ;;  # 1=blocklist, 2=cooldown, 3=locked, 5=open-PR cap — keep walking
  esac
done

if [ -z "$REPO" ]; then
  echo "loop iter $i: no eligible repo in shortlist; refreshing and retrying once"
  # one refresh-and-retry, then give up if still nothing
  break
fi

SLUG="${REPO/\//-}"
# A run that dies silently writes no summary; never let 2d read the last run's.
rm -f "$HOME/.superhuman/repos/$SLUG/run_summary.json"
echo "iter $i/$N → $REPO"
```

#### 2c: Dispatch one orchestrator run

```
Agent(
  subagent_type: "opensource-contributor",
  description: "loop iter <i>: contribute to <REPO>",
  prompt: |
    REPO=<REPO>
    ISSUE=auto
    MODE=cli
    LOOP_ID=<LOOP_ID>
    LOOP_ITER=<i>
)
```

#### 2d: Append the per-iteration record to `loop_runs.jsonl`

```bash
RS="$HOME/.superhuman/repos/$SLUG/run_summary.json"
if [ ! -f "$RS" ]; then
  jq -nc \
    --arg loop "$LOOP_ID" --argjson iter "$i" --arg repo "$REPO" \
    --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    '{loop_id:$loop, iter:$iter, repo:$repo,
      outcome:"no_run_summary", pr_url:null,
      completed_at:$ts, exit_reason:"missing_run_summary"}' \
    >> "$LOG"
  break  # missing run_summary is treated like a hard fault
fi

jq -nc \
  --arg loop "$LOOP_ID" --argjson iter "$i" --arg repo "$REPO" \
  --slurpfile s "$RS" \
  '{loop_id:$loop, iter:$iter, repo:$repo,
    outcome:$s[0].outcome,
    pr_url:$s[0].pr_url,
    completed_at:$s[0].completed_at,
    exit_reason:$s[0].exit_reason}' \
  >> "$LOG"
```

#### 2e: Stop conditions

```bash
OUTCOME=$(jq -r .outcome "$RS")
case "$OUTCOME" in
  suspicious_halt|crash)
    echo "Loop halted at iter $i — outcome=$OUTCOME"
    echo "  run_summary: $RS"
    break ;;
esac
```

`suspicious_halt` means a reviewer comment (or other external content)
attempted prompt injection. Continuing the loop would risk repeated
exposure with no human in the loop. `crash` means an uncaught exception
in the orchestrator chain — re-running blindly likely just re-crashes.
Both require human inspection before resuming.

### Step 3: Render the loop summary

After the loop ends (clean exit, halt, or break), render the table:

```bash
jq -r --arg loop "$LOOP_ID" \
  'select(.loop_id == $loop)
   | [.iter, .repo, .outcome, (.pr_url // "—")] | @tsv' "$LOG" \
  | awk -F'\t' 'BEGIN{printf "%-4s %-32s %-20s %s\n","iter","repo","outcome","pr"}
                {printf "%-4s %-32s %-20s %s\n",$1,$2,$3,$4}'
```

## Rules

- **Sequential, not parallel.** One `Agent` dispatch per assistant turn.
  Use `/contribution-fleet` if you want concurrent runs.
- **Stop oracle is `run_summary.json`, not `merge_outcomes.jsonl`.**
  `merge_outcomes.jsonl` is appended only on normal terminal states; a
  crash skips that path entirely. `run_summary.json` lands on every
  terminal state per audit §4. That makes it the right thing to read.
- **Cap at N=20.** Above that, parallel rate-limit cost dominates —
  `/contribution-fleet` is the right tool.
- **Reputation gate per iteration.** A repo that is eligible at iter 1
  may have been blocklisted, cooled, or locked by iter 5 (especially
  across long loops). Re-check every time.
- **Refresh shortlist as needed.** When the top candidate is taken, the
  next iteration must pull a fresh list. Otherwise we'd hammer the same
  blocklisted/cooled repo repeatedly.
- **Append-only `loop_runs.jsonl`.** Each iteration appends one JSON
  line. Never rewrite. The dashboard reads this with `tail` + `jq`.
- **macOS bash 3.2 safe.** No `mapfile`, no `${var,,}`, no associative
  arrays.
