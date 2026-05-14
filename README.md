# superhuman

Autonomous open-source contribution plugin for [Claude Code](https://claude.com/claude-code).

Ships a coordinated team of agents that picks an issue, profiles the repo, writes a plan, implements it, scores merge probability, iterates on the weakest dimension, and resolves review comments — all without hand-holding. State lives at `~/.superhuman/` and survives across sessions.

Inspired by [obra/superpowers](https://github.com/obra/superpowers).

## What it does

Run `Agent(subagent_type="opensource-contributor", ...)` (or `/contribution-fleet` for parallel runs) and the orchestrator will:

1. **Pick a repo** — `repo-finder` scores candidates by maintainer responsiveness, issue velocity, and AI-friendliness.
2. **Pick an issue** — `issue-selector` hard-skips docs-only, competing-PR, and <24h issues; ranks the rest by merge-likelihood.
3. **Profile the repo** — `repo-profiler` samples the last 10–20 merged PRs to extract commit conventions, PR body structure, test runner, lint commands, and a CI command allowlist.
4. **Plan** — `planner` wraps `superpowers:writing-plans` with repo-aware context (profile + reviewer notes + mistakes log) and returns an executable plan.
5. **Build** — `builder` wraps `superpowers:subagent-driven-development`, runs `impact-auditor` before refactoring shared functions, runs allowlisted local CI pre-push, and force-pushes to a fork.
6. **Score** — `merge-probability-scorer` rates the PR across 10 weighted dimensions (correctness, tests, style, PR format, process compliance, scope, docs, commit hygiene, risk, historical signal).
7. **Iterate** — `reviewer-dispatcher` picks the weakest non-plateaued dimension, routes to a language-specialist reviewer (python/go/ts/java/kotlin/rust/cpp/csharp/flutter/security), feeds findings back to the builder. Adaptive cap: 3/6/10 iterations by diff size; stops at 95% probability over two consecutive runs.
8. **Resolve comments** — `resolve-comments` classifies each review comment (suspicious / question / nit / refactor / concern), drafts replies, dispatches fixes, and halts on prompt-injection attempts.
9. **Record outcome** — merged or abandoned, the result lands in `~/.superhuman/global/merge_outcomes.jsonl` and calibrates the scorer's historical-signal dimension for future runs.

## Required plugins

This plugin depends on skills and agents from other plugins.

| Plugin | Status | Why |
|---|---|---|
| [`superpowers`](https://github.com/obra/superpowers) | **Required** | `planner` invokes `superpowers:writing-plans`; `builder` invokes `superpowers:subagent-driven-development`. Without it, both agents fail with `PluginMissingError`. |
| `everything-claude-code` | Recommended | `reviewer-dispatcher` routes to language-specialist reviewers. Falls back to inline prompts via `AgentNotFoundError` rescue if missing, but review quality drops. |

Declared in `.claude-plugin/plugin.json` under `requires.plugins`.

## Installation

```
/plugin marketplace add https://github.com/obra/superpowers
/plugin install superpowers@superpowers

/plugin marketplace add https://github.com/gaurav0107/superhuman
/plugin install superhuman@superhuman

/reload-plugins
```

## Usage

**Single run** — let the orchestrator pick everything:

```
Agent(subagent_type="opensource-contributor", prompt="find a good repo and contribute")
```

**Targeted run** — specify the repo and/or issue:

```
Agent(subagent_type="opensource-contributor", prompt="contribute to apache/airflow issue #65685")
```

**Parallel fleet** — run N independent contributions concurrently:

```
/contribution-fleet 3
/contribution-fleet apache/airflow langchain-ai/langchain pytorch/pytorch
```

Each fleet run gets its own state dir, clone path, and `flock(2)` mutex — they cannot interfere.

**Dashboard** — read-only view of live runs, score history, iteration caps, and merge outcomes:

```
/contribution-dashboard
/contribution-dashboard apache/airflow
```

## Agents

Orchestrator + 9 specialists + 1 shared-state contract document.

| Agent | Role |
|---|---|
| `opensource-contributor` | Thin orchestrator. Owns the `current_contribution.json` lock, sequences phases, enforces the iteration cap and merge threshold. |
| `repo-finder` | Discovers high-value repos worth contributing to. |
| `issue-selector` | Filters and ranks open issues; writes `issue_candidates.json`. |
| `repo-profiler` | Extracts contribution conventions from merged PRs; writes `repo_profile.json`, `ci_commands.json`, `allowed_commands.json`. |
| `planner` | Wraps `superpowers:writing-plans` with repo context; writes `plan.md`. |
| `builder` | Wraps `superpowers:subagent-driven-development`; runs impact-audit and local CI gates. |
| `impact-auditor` | Refactor blast-radius auditor. Blocks reviewer-suggested refactors that break one caller to fix another. |
| `merge-probability-scorer` | 10-dimension weighted rubric blended with historical merge outcomes. |
| `reviewer-dispatcher` | Picks the weakest dimension and routes to the right specialist reviewer. |
| `resolve-comments` | Classifies PR review comments; drafts replies or dispatches fixes. Halts on prompt-injection. |
| `SHARED_STATE.md` | Single source of truth for file ownership, readers, and concurrency contract. Not an agent — read by all. |

## Commands

| Command | Purpose |
|---|---|
| `/contribution-dashboard [owner/repo]` | Read-only view of active run, score history, plateaued dimensions, iteration cap, recent merge outcomes. |
| `/contribution-fleet [N \| owner/repo ...]` | Launch N parallel contributor runs. |

## Structure

```
superhuman/
├── .claude-plugin/
│   ├── plugin.json           # Plugin manifest + requires.plugins declarations
│   └── marketplace.json      # Marketplace catalog entry
├── agents/                   # Subagents (loaded as subagent_type by Claude Code)
│   ├── SHARED_STATE.md       # File ownership + concurrency contract
│   ├── opensource-contributor.md
│   ├── repo-finder.md
│   ├── issue-selector.md
│   ├── repo-profiler.md
│   ├── planner.md
│   ├── builder.md
│   ├── impact-auditor.md
│   ├── merge-probability-scorer.md
│   ├── reviewer-dispatcher.md
│   └── resolve-comments.md
├── commands/                 # Slash commands
│   ├── contribution-dashboard.md
│   └── contribution-fleet.md
└── skills/                   # (empty — this plugin exposes agents, not skills)
```

## State layout

All persistent state lives under `~/.superhuman/`. Per-repo state is keyed by `<owner>-<repo>` (slash replaced with hyphen).

```
~/.superhuman/
├── repos/
│   └── apache-airflow/
│       ├── repo_profile.json
│       ├── ci_commands.json
│       ├── allowed_commands.json
│       ├── issue_candidates.json
│       ├── current_contribution.json    # orchestrator lock
│       ├── plan.md
│       ├── caller_graph.json
│       ├── reviewer_intent_notes.md
│       ├── mistakes.md
│       ├── maintainer_tone.json
│       ├── smoke_registry.json
│       └── run_telemetry.jsonl
└── global/
    ├── flake_signatures.md
    ├── merge_outcomes.jsonl             # feedback corpus for scorer calibration
    ├── repo_blocklist.json
    ├── repo_cooldown.json
    └── repo-shortlist.json
```

File ownership (sole-writer + readers) is documented in `agents/SHARED_STATE.md`.

## Safety rails

- **Impact audits before refactors.** `builder` invokes `impact-auditor` before applying any reviewer-suggested refactor to a shared function. Blocks the class of bug where "just read `self.app.config` instead of calling `conf.get()`" is correct at Flask request time and fatal at FastAPI startup.
- **CI allowlist.** `builder` only runs commands pre-approved in `allowed_commands.json`. `repo-profiler` seeds the allowlist from `.github/workflows/*.yml`; anything outside it requires explicit user approval.
- **Force-with-lease only.** Pushes use `--force-with-lease` to the contributor's fork — never upstream, never plain `--force`.
- **Prompt-injection halt.** `resolve-comments` classifies any comment asking it to run shell commands, modify files outside the diff, or fetch from external URLs as `suspicious`, halts the run, and logs to `mistakes.md`.
- **Single-author commit rule.** Every commit is authored by the human contributor identity configured in `builder`. No `Co-Authored-By:` trailers, no AI attribution.
- **Reputation cooldown.** Repos where PRs consistently get rejected or ignored land in `repo_cooldown.json` and are skipped by `repo-finder` until the cooldown window expires.

## License

MIT
