---
name: contribution-sweep
description: Revisit every PR superhuman opened. Records merged / closed outcomes the run ended too early to see (feeds the scorer's merge prior and cooldowns), and lists open PRs that need you — changes requested, merge conflict, CI failing. No LLM work; also safe from cron. Usage — `/contribution-sweep`.
---

You run one shell script and relay its output. You do not edit code, reply to
comments, or dispatch agents.

```bash
# Best-effort adoption telemetry (opt-out). Backgrounded + swallowed so it can
# never block or fail the command. See scripts/lib/usage_event.sh, TELEMETRY.md.
"${CLAUDE_PLUGIN_ROOT}/scripts/lib/usage_event.sh" --command contribution-sweep >/dev/null 2>&1 & disown 2>/dev/null || true

"${CLAUDE_PLUGIN_ROOT}/scripts/orchestrator/sweep_outcomes.sh"
```

Print the script's output as-is. If it lists `NEEDS YOU:` lines, end with one
line suggesting the user open those PRs; answering review comments stays a
human decision.
