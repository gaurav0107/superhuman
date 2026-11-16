#!/usr/bin/env bash
# catalog_generated.sh REPO_DIR
# Emits {repo, generated_at, entries:[{path, marker, regenerate_cmd}]} on stdout.
# Cap: 500 entries. Beyond that, log a warning to stderr and truncate.
set -euo pipefail
# Not exported by the harness (template variable only), so derive it from $0.
export CLAUDE_PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(CDPATH= cd "$(dirname "$0")/../.." && pwd)}"

REPO_DIR="${1:?repo dir required}"
[ -d "$REPO_DIR" ] || { echo "catalog_generated.sh: not a dir" >&2; exit 2; }
cd "$REPO_DIR"

MARKERS=(
  "AUTO-GENERATED"
  "DO NOT EDIT"
  "@generated"
  "openapi-generator"
  "protoc"
  "prisma generate"
  "swagger-codegen"
)

pattern=""
for m in "${MARKERS[@]}"; do
  if [ -z "$pattern" ]; then pattern="$m"; else pattern="$pattern|$m"; fi
done

entries='[]'
count=0
CAP=500

while IFS= read -r f; do
  [ "$count" -ge "$CAP" ] && { echo "catalog_generated.sh: cap $CAP reached, truncating" >&2; break; }
  marker=$(head -5 "$f" 2>/dev/null | grep -Eo "$pattern" | head -1 || true)
  [ -z "$marker" ] && continue
  rel=$(echo "$f" | sed 's|^\./||')
  entries=$(echo "$entries" | jq \
    --arg p "$rel" --arg m "$marker" \
    '. + [{path:$p, marker:$m, regenerate_cmd:null}]')
  count=$((count + 1))
done < <(find . -type f \( -name '*.py' -o -name '*.yaml' -o -name '*.yml' \
                          -o -name '*.json' -o -name '*.go' -o -name '*.ts' \
                          -o -name '*.js' -o -name '*.rs' \) 2>/dev/null)

repo_slug=$(basename "$(pwd)")
ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
jq -n --arg r "$repo_slug" --arg ts "$ts" --argjson e "$entries" \
  '{repo:$r, generated_at:$ts, entries:$e}'
