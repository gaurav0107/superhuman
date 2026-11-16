#!/usr/bin/env bash
# prune_mistakes.sh --file PATH --max-age-days N [--now ISO_TS]
# Removes entries (## H2 blocks) older than N days from a mistakes.md.
# Atomic: writes to temp + rename. Append-only contract preserved
# (no other writer touches the file during this).
#
# Implementation note: The plan called for awk with match($0,/re/,array)
# which is a gawk extension unavailable on macOS BSD awk.  Replaced with
# an equivalent python3 block-parser that is fully portable.
set -euo pipefail
# Not exported by the harness (template variable only), so derive it from $0.
export CLAUDE_PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}"

FILE=""; MAX=""; NOW=""
while [ $# -gt 0 ]; do
  case "$1" in
    --file)         FILE="$2"; shift 2 ;;
    --max-age-days) MAX="$2";  shift 2 ;;
    --now)          NOW="$2";  shift 2 ;;
    *) echo "prune_mistakes.sh: unknown arg: $1" >&2; exit 2 ;;
  esac
done
[ -z "$FILE" ] && { echo "--file required" >&2; exit 2; }
[ -z "$MAX" ]  && { echo "--max-age-days required" >&2; exit 2; }
[ -z "$NOW" ]  && NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)
[ -f "$FILE" ] || exit 0

tmp="${FILE}.tmp.$$"

python3 - "$FILE" "$MAX" "$NOW" > "$tmp" <<'PYEOF'
import sys, re, datetime

filepath, max_days_str, now_str = sys.argv[1], sys.argv[2], sys.argv[3]
max_days = int(max_days_str)

now_dt = datetime.datetime.fromisoformat(now_str.replace("Z", "+00:00"))
cutoff_ts = now_dt.timestamp() - max_days * 86400

h2_re = re.compile(r'^## ([0-9T:Z\-]+) ')

blocks = []
current_lines = []
current_keep = True

with open(filepath, "r") as f:
    for line in f:
        m = h2_re.match(line)
        if m:
            if current_lines:
                blocks.append((current_keep, current_lines))
            current_lines = [line]
            ts_str = m.group(1)
            try:
                entry_dt = datetime.datetime.fromisoformat(ts_str.replace("Z", "+00:00"))
                current_keep = entry_dt.timestamp() >= cutoff_ts
            except ValueError:
                current_keep = True
        else:
            current_lines.append(line)

if current_lines:
    blocks.append((current_keep, current_lines))

for keep, lines in blocks:
    if keep:
        sys.stdout.writelines(lines)
PYEOF

mv "$tmp" "$FILE"
