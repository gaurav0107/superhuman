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
