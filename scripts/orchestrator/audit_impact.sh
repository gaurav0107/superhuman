#!/usr/bin/env bash
# audit_impact.sh --repo OWNER/REPO --workdir DIR --target-function FQN
#                 --refactor-kind KIND [--refactor-description DESC]
#                 [--issue-number N] --out PATH
#
# Mechanical caller enumeration. Emits caller_graph.json shape with
# verdict="unknown" and safe_under_refactor=false (unclassified) — the
# impact-auditor agent classifies contexts and overrides these in Steps 2-4
# of impact-auditor.md.
#
# Source: impact-auditor.md:64-77 (grep block) + :156-177 (emit block).
# Verdict matrix at impact-auditor.md:118-128 stays in prompt as the
# authoritative classification rules.
set -euo pipefail
: "${CLAUDE_PLUGIN_ROOT:?CLAUDE_PLUGIN_ROOT must be set}"

REPO=""; WORKDIR=""; TARGET=""; KIND=""; DESC=""; OUT=""; ISSUE_NUM="0"
while [ $# -gt 0 ]; do
  case "$1" in
    --repo)                 REPO="$2";       shift 2 ;;
    --workdir)              WORKDIR="$2";    shift 2 ;;
    --target-function)      TARGET="$2";     shift 2 ;;
    --refactor-kind)        KIND="$2";       shift 2 ;;
    --refactor-description) DESC="$2";       shift 2 ;;
    --issue-number)         ISSUE_NUM="$2";  shift 2 ;;
    --out)                  OUT="$2";        shift 2 ;;
    *) echo "audit_impact.sh: unknown arg: $1" >&2; exit 2 ;;
  esac
done
[ -z "$REPO" ]    && { echo "--repo required" >&2;            exit 2; }
[ -z "$WORKDIR" ] && { echo "--workdir required" >&2;         exit 2; }
[ -z "$TARGET" ]  && { echo "--target-function required" >&2; exit 2; }
[ -z "$KIND" ]    && { echo "--refactor-kind required" >&2;   exit 2; }
[ -z "$OUT" ]     && { echo "--out required" >&2;             exit 2; }

SHORT_NAME="${TARGET##*.}"
RAW=$(mktemp)
trap 'rm -f "$RAW"' EXIT

# Mirrors impact-auditor.md:64-77 — language-agnostic grep for call sites.
# Both dotted (.calc) and bare (calc() invocations are captured.
git -C "$WORKDIR" grep -n \
  "\.${SHORT_NAME}\b\|\b${SHORT_NAME}(" \
  -- ':*.py' ':*.js' ':*.ts' ':*.tsx' ':*.go' ':*.rs' ':*.java' ':*.kt' \
  > "$RAW" 2>/dev/null || true

# Build callers JSON array from grep output.
# Each grep line is "file:line:content".
# Schema requires per-caller: location (string), caller_function, execution_context,
# safe_under_refactor (boolean), notes.
# Classification (execution_context, safe_under_refactor) is the agent's job;
# we emit safe defaults so the JSON is schema-valid.
CALLERS_JSON=$(awk -F: '
  NF >= 3 {
    file = $1
    lineno = $2
    snippet = ""
    for (i = 3; i <= NF; i++) {
      snippet = snippet (i==3 ? "" : ":") $i
    }
    gsub(/\\/, "\\\\", snippet)
    gsub(/"/, "\\\"", snippet)
    gsub(/\t/, "    ", snippet)
    sub(/^[[:space:]]+/, "", snippet)
    printf "{\"location\":\"%s:%s\",\"caller_function\":\"\",\"execution_context\":\"unknown\",\"safe_under_refactor\":false,\"notes\":\"%s\"}\n", file, lineno, snippet
  }
' "$RAW" | jq -s '.')

# Mirrors impact-auditor.md:156-177 emit shape.
# verdict="unknown" and contexts_found=[] because classification is the
# agent's job (Steps 2-4 of impact-auditor.md).
NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)
AUDIT=$(jq -n \
  --arg repo         "$REPO" \
  --argjson issue    "$ISSUE_NUM" \
  --arg target       "$TARGET" \
  --arg kind         "$KIND" \
  --arg desc         "$DESC" \
  --arg verdict      "unknown" \
  --arg ts           "$NOW" \
  --argjson callers  "$CALLERS_JSON" \
  '{repo:$repo,
    issue_number:$issue,
    generated_at:$ts,
    target_function:$target,
    refactor_kind:$kind,
    refactor_description:$desc,
    verdict:$verdict,
    callers:$callers,
    contexts_found:[],
    suggested_alternative:null}')

TMP="$OUT.tmp.$$"
mkdir -p "$(dirname "$OUT")"
printf '%s' "$AUDIT" | jq . > "$TMP" && mv "$TMP" "$OUT"
