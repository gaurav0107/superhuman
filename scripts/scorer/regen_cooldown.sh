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
  def to_epoch(t): t | sub("Z$"; "") | strptime("%Y-%m-%dT%H:%M:%S") | mktime;
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
        | (map(select((.outcome | IN("closed_no_merge","abandoned","suspicious_halt"))
                      and (to_epoch(.closed_at)) >= ($now_e - 180*86400))))
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
