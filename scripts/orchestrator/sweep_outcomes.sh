#!/usr/bin/env bash
# sweep_outcomes.sh
# Revisits every PR recorded in merge_outcomes.jsonl that has no final outcome yet, records
# merged / closed_no_merge for the ones GitHub has concluded, regenerates
# cooldowns, and lists open PRs that need a human. No LLM; safe to run from cron.
#
# A run ends minutes after opening its PR (merge_ready, plateau, ...), long
# before a maintainer decides, so without this sweep merges were never recorded:
# historical_blend saw ~0% merge rate and a merge could never clear a cooldown.
#
# PRs come from merge_outcomes.jsonl itself — only ones superhuman opened, never
# the user's other PRs. Exit 0 always unless misconfigured (10); per-PR gh
# failures are warned and retried next sweep.
set -euo pipefail
# Not exported by the harness (template variable only), so derive it from $0.
export CLAUDE_PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(CDPATH= cd "$(dirname "$0")/../.." && pwd)}"
source "${CLAUDE_PLUGIN_ROOT}/scripts/lib/state.sh"

[ $# -eq 0 ] || { echo "sweep_outcomes.sh: takes no arguments" >&2; exit 10; }
command -v gh >/dev/null || { echo "sweep_outcomes.sh: gh not on PATH" >&2; exit 10; }

LOG="$(global_dir)/merge_outcomes.jsonl"
[ -f "$LOG" ] || { echo "sweep: no merge_outcomes.jsonl yet; nothing to do"; exit 0; }

# url \t repo \t iterations, for PRs whose latest row is not a final outcome.
pending=$(jq -rs "$OUTCOMES_JQ"'
  map(select((.pr_url // "") | startswith("https://github.com/")))
  | latest_per_pr
  | map(select(.outcome | IN("merged","closed_no_merge") | not))
  | .[] | [.pr_url, .repo, ((.iterations // .iteration_count // 0) | tostring)] | @tsv' "$LOG")

tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT
recorded=0 open=0 failed=0
while IFS=$'\t' read -r url repo iters; do
  [ -n "$url" ] || continue
  if ! gh pr view "$url" --json state,mergedAt,closedAt,reviewDecision,mergeStateStatus,statusCheckRollup > "$tmp" 2>/dev/null; then
    echo "WARN: could not read $url; will retry next sweep" >&2
    failed=$((failed + 1)); continue
  fi
  case "$(jq -r .state "$tmp")" in
    MERGED) out=merged;          at=$(jq -r .mergedAt "$tmp") ;;
    CLOSED) out=closed_no_merge; at=$(jq -r .closedAt "$tmp") ;;
    *)
      open=$((open + 1))
      why=$(jq -r '[
          (select(.reviewDecision == "CHANGES_REQUESTED") | "changes requested"),
          (select(.mergeStateStatus == "DIRTY") | "merge conflict"),
          (select([.statusCheckRollup[]? | (.conclusion // .state)] | any(IN("FAILURE","ERROR","TIMED_OUT","STARTUP_FAILURE","ACTION_REQUIRED"))) | "CI failing")
        ] | join(", ")' "$tmp")
      [ -z "$why" ] || echo "NEEDS YOU: $url — $why"
      continue ;;
  esac
  bash "${CLAUDE_PLUGIN_ROOT}/scripts/scorer/record_outcome.sh" \
    --repo "$repo" --pr-url "$url" --outcome "$out" \
    --iterations "${iters:-0}" --closed-at "$at"
  echo "RECORDED: $url — $out"
  recorded=$((recorded + 1))
done <<< "$pending"

# Always: a sweep that died after recording must not leave cooldowns stale.
bash "${CLAUDE_PLUGIN_ROOT}/scripts/scorer/regen_cooldown.sh"
echo "sweep: recorded=$recorded open=$open unreadable=$failed"
