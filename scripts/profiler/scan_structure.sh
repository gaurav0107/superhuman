#!/usr/bin/env bash
# scan_structure.sh --repo OWNER/REPO --worktree DIR [--head-sha SHA] [--now ISO]
# Emits repo_scan.json (structural facts) on stdout — the deterministic scan that
# grounds the lesson-distiller's dossier (producer: repo-profiler).
#
# The bash wrapper resolves repo/now/head/branch; the file-walk + JSON assembly is
# done in python3 (already a project dependency). Python is used deliberately: it has
# none of the bash-pipeline edge cases that a find/grep/jq version hit (empty-input
# grep exit codes aborting under set -e, `jq -R` dropping the first line, whole-repo
# classes yielding empty output). The python walk is robust across repo shapes —
# C-only, empty, single-symbol, vendored — always emitting a schema-valid object.
set -euo pipefail
# Not exported by the harness (template variable only), so derive it from $0.
export CLAUDE_PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}"
source "${CLAUDE_PLUGIN_ROOT}/scripts/lib/state.sh"

REPO=""; WT=""; HEAD_SHA=""; NOW=""
while [ $# -gt 0 ]; do
  case "$1" in
    --repo)     REPO="$2"; shift 2 ;;
    --worktree) WT="$2"; shift 2 ;;
    --head-sha) HEAD_SHA="$2"; shift 2 ;;
    --now)      NOW="$2"; shift 2 ;;
    *) echo "scan_structure.sh: unknown arg: $1" >&2; exit 2 ;;
  esac
done
[ -n "$REPO" ] || { echo "--repo required" >&2; exit 2; }
[ -n "$WT" ] && [ -d "$WT" ] || { echo "--worktree DIR (existing) required" >&2; exit 2; }
[ -n "$NOW" ] || NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)
[ -n "$HEAD_SHA" ] || HEAD_SHA=$(git -C "$WT" rev-parse HEAD 2>/dev/null || echo "unknown")
DEFAULT_BRANCH=$(git -C "$WT" symbolic-ref --short HEAD 2>/dev/null || echo "main")

python3 - "$REPO" "$WT" "$NOW" "$HEAD_SHA" "$DEFAULT_BRANCH" <<'PY'
import os, re, json, sys
repo, wt, now, head, branch = sys.argv[1:6]
KNOWN    = {'py','js','ts','go','rs','java','kt','cpp','cc','c','h','hpp','cs','rb','php','swift'}
SRC_EXTS = {'py','js','ts','go','rs','java','kt','cpp','cc','c','h','cs','rb','php','swift'}
SYM_EXTS = {'py','js','ts','go','rb'}
# dirs excluded from source_dirs (they are not first-party source locations)
DENY  = {'tests','test','spec','__tests__','docs','doc','node_modules','vendor','examples','.git'}
# dirs whose symbols must not enter the reuse catalog (third-party / generated / test)
NOISE = {'.git','node_modules','vendor','examples','tests','test','spec','__tests__'}
SYM_RE = re.compile(r'^(?:def |class |export default function |export function |function )([A-Za-z_][A-Za-z0-9_]*)')
langs, source_dirs, test_dirs, top_symbols = set(), set(), set(), []
for root, dirs, files in os.walk(wt):
    dirs.sort(); files.sort()                     # deterministic traversal
    rel = os.path.relpath(root, wt)
    parts = [] if rel == '.' else rel.split(os.sep)
    if '.git' in parts:                           # never descend into .git
        dirs[:] = []
        continue
    if os.path.basename(root) in ('test', 'tests', 'spec', '__tests__'):
        test_dirs.add(rel)
    for f in files:
        ext = f.rsplit('.', 1)[-1].lower() if '.' in f else ''
        if ext in KNOWN:
            langs.add(ext)
        if ext in SRC_EXTS and parts and parts[0] not in DENY:
            source_dirs.add(parts[0])
        if ext in SYM_EXTS and not (set(parts) & NOISE) and len(top_symbols) < 12:
            try:
                with open(os.path.join(root, f), encoding='utf-8', errors='ignore') as fh:
                    for line in fh:
                        m = SYM_RE.match(line)
                        if m:
                            top_symbols.append({'file': os.path.relpath(os.path.join(root, f), wt),
                                                'name': m.group(1)})
                            if len(top_symbols) >= 12:
                                break
            except Exception:
                pass
print(json.dumps({
    'repo': repo, 'generated_at': now, 'head_sha': head, 'default_branch': branch,
    'languages': sorted(langs), 'source_dirs': sorted(source_dirs), 'test_dirs': sorted(test_dirs),
    'test_name_patterns': [], 'naming': {}, 'top_symbols': top_symbols}))
PY
