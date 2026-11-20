#!/usr/bin/env bash
# tests/scripts/test_pr_body_with_attribution.sh
set -euo pipefail
export CLAUDE_PLUGIN_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SCRIPT="$CLAUDE_PLUGIN_ROOT/scripts/orchestrator/pr_body_with_attribution.sh"

fail() { echo "FAIL: $1"; exit 1; }
marker_count() { printf '%s' "$1" | grep -cF 'Opened with [superhuman]'; }

BASE='## Summary
Fixes the thing.'

# 1. Default (unset): footer appended, base body preserved, repo url present, one marker.
unset SUPERHUMAN_ATTRIBUTION 2>/dev/null || true
OUT="$(printf '%s' "$BASE" | bash "$SCRIPT")"
printf '%s' "$OUT" | grep -qF 'Fixes the thing.'                || fail "default: base body lost"
printf '%s' "$OUT" | grep -qF 'github.com/gaurav0107/superhuman' || fail "default: repo url missing"
[ "$(marker_count "$OUT")" = "1" ]                              || fail "default: marker count != 1"
# Brand is lowercase "superhuman" (not the Superhuman email app); footer is exactly one line.
[ "$(printf '%s' "$OUT" | tail -n 1)" = '🤖 Opened with [superhuman](https://github.com/gaurav0107/superhuman), the open-source Claude Code plugin.' ] \
                                                                || fail "default: footer wording changed"

# 2a. Disable + clean body: returned byte-for-byte.
for v in off OFF false 0 no; do
  OUT="$(printf '%s' "$BASE" | SUPERHUMAN_ATTRIBUTION="$v" bash "$SCRIPT")"
  [ "$OUT" = "$BASE" ] || fail "disable '$v': clean body not returned verbatim"
done

# 2b. Disable + rogue attribution: rogue line scrubbed, no footer, base kept.
ROGUE="$BASE

<sub>Prepared with assistance from the Superhuman open-source contribution plugin.</sub>"
OUT="$(printf '%s' "$ROGUE" | SUPERHUMAN_ATTRIBUTION=off bash "$SCRIPT")"
printf '%s' "$OUT" | grep -qiF 'Prepared with assistance' && fail "disable: rogue line not scrubbed"
printf '%s' "$OUT" | grep -qiF 'superhuman'                && fail "disable: superhuman mention remains"
printf '%s' "$OUT" | grep -qF  'Fixes the thing.'          || fail "disable: base body lost"

# 3. Idempotency: re-running a footered body yields the same output, one marker.
WITH_FOOTER="$(printf '%s' "$BASE" | bash "$SCRIPT")"
AGAIN="$(printf '%s' "$WITH_FOOTER" | bash "$SCRIPT")"
[ "$AGAIN" = "$WITH_FOOTER" ]           || fail "idempotency: output changed on second pass"
[ "$(marker_count "$AGAIN")" = "1" ]    || fail "idempotency: marker count != 1"

# 4. Rogue <sub> line, attribution ON: stripped, replaced by exactly one canonical footer.
OUT="$(printf '%s' "$ROGUE" | bash "$SCRIPT")"
printf '%s' "$OUT" | grep -qiF 'Prepared with assistance' && fail "on: rogue line not scrubbed"
printf '%s' "$OUT" | grep -qF 'Fixes the thing.'          || fail "on: base body lost"
[ "$(marker_count "$OUT")" = "1" ]                        || fail "on: marker count != 1"

# 5. Model wrote its own (non-canonical) Superhuman line: no double attribution.
MODEL_FOOTER="$BASE

---
Opened with Superhuman (https://github.com/gaurav0107/superhuman)."
OUT="$(printf '%s' "$MODEL_FOOTER" | bash "$SCRIPT")"
[ "$(marker_count "$OUT")" = "1" ]                                       || fail "double-attr: marker count != 1"
[ "$(printf '%s' "$OUT" | grep -cF 'github.com/gaurav0107/superhuman')" = "1" ] || fail "double-attr: url appears more than once"

# 6. Claude/AI attribution in body: stripped; only the canonical footer remains.
AI="$BASE

🤖 Generated with Claude Code
Co-authored-by: Claude <noreply@anthropic.com>"
OUT="$(printf '%s' "$AI" | bash "$SCRIPT")"
printf '%s' "$OUT" | grep -qiF 'Generated with Claude' && fail "ai: claude line not scrubbed"
printf '%s' "$OUT" | grep -qiF 'Co-authored-by'        && fail "ai: co-author trailer not scrubbed"
printf '%s' "$OUT" | grep -qiF 'noreply@anthropic.com' && fail "ai: anthropic email not scrubbed"
[ "$(marker_count "$OUT")" = "1" ]                     || fail "ai: marker count != 1"

# 7. False-positive guard: legitimate prose mentioning tools/verbs is preserved.
LEGIT='## Summary
This fixes the Claude SDK timeout.
We generated the config with make.'
OUT="$(printf '%s' "$LEGIT" | bash "$SCRIPT")"
printf '%s' "$OUT" | grep -qF 'This fixes the Claude SDK timeout.' || fail "fp: claude-sdk sentence stripped"
printf '%s' "$OUT" | grep -qF 'We generated the config with make.' || fail "fp: generated-with-make sentence stripped"
[ "$(marker_count "$OUT")" = "1" ]                                 || fail "fp: marker count != 1"

# 8. Mid-body '---' separator preserved (only trailing attribution is touched).
SECT='## Part 1
alpha

---

## Part 2
beta'
OUT="$(printf '%s' "$SECT" | bash "$SCRIPT")"
printf '%s' "$OUT" | grep -qF '## Part 1' || fail "sect: part 1 lost"
printf '%s' "$OUT" | grep -qF '## Part 2' || fail "sect: part 2 lost"
printf '%s' "$OUT" | grep -qF 'beta'      || fail "sect: content after --- lost"
# mid-body '---' plus the footer separator == 2 horizontal rules.
[ "$(printf '%s' "$OUT" | grep -cE '^-{3,}$')" = "2" ] || fail "sect: mid-body '---' not preserved"

# 9. Footer-zone guard: mid-body prose co-mentioning a verb + tool name is preserved.
FP='## Summary
We opened a ticket about the Claude rate limit issue.
We built a new AI agent framework for customer support.

## Fix
Adjusted retry backoff.'
OUT="$(printf '%s' "$FP" | bash "$SCRIPT")"
printf '%s' "$OUT" | grep -qF 'opened a ticket about the Claude' || fail "fz: mid-body Claude line stripped"
printf '%s' "$OUT" | grep -qF 'built a new AI agent framework'   || fail "fz: mid-body AI-agent line stripped"
[ "$(marker_count "$OUT")" = "1" ]                               || fail "fz: marker count != 1"

# 10. Mid-body anthropic email in prose is preserved (only the footer zone is scrubbed).
FP3='## Summary
Contact the previous author at noreply@anthropic.com for context.

## Fix
done.'
OUT="$(printf '%s' "$FP3" | bash "$SCRIPT")"
printf '%s' "$OUT" | grep -qF 'noreply@anthropic.com' || fail "fz: mid-body anthropic email stripped"

# 11. Degenerate body (no '---', no blank line): legit prose on the final line is
#     preserved — the fuzzy verb+name rule is disabled without a structural signal.
DEG='## Summary
Fixes the bug.
We built a new AI agent framework for customer support.'
OUT="$(printf '%s' "$DEG" | bash "$SCRIPT")"
printf '%s' "$OUT" | grep -qF 'built a new AI agent framework' || fail "degenerate: final-line prose stripped"
[ "$(marker_count "$OUT")" = "1" ]                             || fail "degenerate: marker count != 1"

# 12. Degenerate body: an explicit attribution artifact on the final line IS still
#     stripped (explicit catches fire even without a structural signal).
DEGA='## Summary
Fixes the bug.
Generated by Superhuman: https://github.com/gaurav0107/superhuman'
OUT="$(printf '%s' "$DEGA" | bash "$SCRIPT")"
[ "$(printf '%s' "$OUT" | grep -cF 'github.com/gaurav0107/superhuman')" = "1" ] || fail "degenerate: explicit url attribution not scrubbed"
[ "$(marker_count "$OUT")" = "1" ]                                             || fail "degenerate: marker count != 1"

# 13. Empty body: scrubs to empty, footer appended cleanly, exactly one marker.
OUT="$(printf '%s' '' | bash "$SCRIPT")"
[ "$(marker_count "$OUT")" = "1" ] || fail "empty: marker count != 1"

# 14. Attribution-only body: the lone attribution line is scrubbed (explicit catch
#     fires even in the no-structure fallback); result carries just the footer.
OUT="$(printf '%s' '🤖 Opened with [Superhuman](https://github.com/gaurav0107/superhuman), an open-source contribution agent.' | bash "$SCRIPT")"
[ "$(marker_count "$OUT")" = "1" ] || fail "attribution-only: marker count != 1"
# 14b. A pre-rebrand footer ("[Superhuman] … contribution agent") is scrubbed, not kept beside the new one.
printf '%s' "$OUT" | grep -qF 'open-source contribution agent' && fail "legacy footer not scrubbed"

# 15. Documented residual (pins the structural-signal-gate cost): a rogue line with
#     NO preceding blank/'---' is NOT scrubbed by the fuzzy rule. If this ever
#     changes, revisit the gate deliberately.
STRLESS='## Summary
<sub>Prepared with assistance from the Superhuman plugin.</sub>'
OUT="$(printf '%s' "$STRLESS" | SUPERHUMAN_ATTRIBUTION=off bash "$SCRIPT")"
printf '%s' "$OUT" | grep -qiF 'prepared with assistance' || fail "residual: structureless rogue unexpectedly changed"

echo "OK test_pr_body_with_attribution.sh"
