# Design — Bash extraction for prompt simplification

**Date:** 2026-05-18
**Repo:** superhuman (autonomous OSS contribution plugin for Claude Code)
**Author:** gaurav0107
**Status:** Draft, pending user review

## Goal

Shrink agent prompts so future Claude sessions load less per phase, without losing
any current behavior. The user's words: "simplify this project by still keepig
the power we have" and "without loosing anything". Lossless is the hard
constraint.

## Why this is worth doing

Prompt length today is dominated by inline bash and jq, not behavioral prose:

| Agent | Lines | Bulk |
|---|---|---|
| builder.md | 614 | ~450 lines bash (CI gate, smoke gate, drift linter, identity pin) |
| merge-probability-scorer.md | 555 | ~280 lines bash (rubric loop, historical blend, cooldown regen) |
| opensource-contributor.md | 525 | ~200 lines bash (lock, telemetry, fleet log, iteration cap) |
| repo-profiler.md | 480 | ~280 lines bash (workflow parse, smoke detect, generated-file scan) |
| SHARED_STATE.md | 523 | ~50 lines bash helpers (state_dir, atomic_write_json, require_lock) |

Every iteration loads the full agent prompt. The bash inside the prompt is
re-tokenized on every load even though it never branches on prompt context —
it runs verbatim. Moving runnable code to disk and citing it from the prompt
preserves behavior while cutting token cost.

The 614-line `agents/builder.md` even self-documents dead weight in its inline
reference matrix ("kept only as documentation"). That's a smell.

## Constraints (non-negotiable)

1. **Lossless.** No semantic edits during the move. No "while we're at it"
   refactors. A `return 1` does not become `echo "warn"`. State files must
   be byte-equivalent after timestamp normalization.
2. **Single-author commit rule stays inline in `builder.md` prompt.**
   Defense-in-depth: even if scripts misbehave, the prompt instruction
   prevents AI attribution from leaking. Hard-coded
   `gaurav0107 <gauravdubey0107@gmail.com>`. No `Co-Authored-By:`. No
   "Generated with Claude" / "🤖 Generated with [Claude Code]" /
   `noreply@anthropic.com` strings.
3. **Force-with-lease only**, never plain `--force`, never to `upstream`,
   only to fork at `origin`. This rule stays in prompt.
4. **Prompt-injection halt rule** stays in prompt (resolve-comments classifies
   `suspicious`, halts run, logs to `mistakes.md`). External content stays
   wrapped in `<<<EXTERNAL_CONTENT id=<uuid>>>>...<<<END id=<uuid>>>`.
5. **Append-only files** still append-only (`mistakes.md`,
   `reviewer_intent_notes.md`, `flake_signatures.md`, `merge_outcomes.jsonl`).
   Single-writer rules from SHARED_STATE.md ownership table preserved.
6. **No new dependencies.** Bash 3.2 (macOS default), `jq`, `gh`, `git`, `yq`,
   `python3`. Same as today.

## Premises (all hold)

- **P1: The behavioral prose is load-bearing; the bash is mechanism.**
  Agents need the *what* and *why* in the prompt; the *how* can be a script
  reference. Verified by reading each long block — none branch on prompt
  context, all run a fixed pipeline.
- **P2: `${CLAUDE_PLUGIN_ROOT}` is the right anchor.** Currently zero usages
  in repo (verified by grep). Plugin runtime injects this var, so scripts
  resolve regardless of where the user invoked Claude Code.
- **P3: Three pillars (scoring loop, repo-selection brain, safety rails) are
  load-bearing as the user said.** Simplification is *inside* pillars, not
  by removing one.

## Approaches considered

### A — Surgical extraction (Recommended) ✅

Move bash blocks meeting the threshold below from agent `.md` files into
`scripts/{lib,orchestrator,profiler,builder,scorer}/`. Move the JSON schema
section of SHARED_STATE.md into `schemas/*.json` (draft 2020-12). Leave
behavioral prose, ownership tables, run trace, and short inline snippets
in place.

**Threshold for extraction:** a bash block moves to a script if **any** of:
- It is ≥10 contiguous lines, OR
- It uses `case ... esac`, `while read`, or jq with >2 filters, OR
- It is shared by ≥2 agents (e.g., `state_dir`, `atomic_write_json`,
  `require_lock`).

Below the threshold, snippets stay inline so the agent reading the prompt
can still see what the action looks like.

**Why this wins:** lossless by construction (cut + paste, no rewrite),
audit-friendly (each script is one file with one job), reversible
(scripts can be re-inlined if the indirection becomes annoying), and it
aligns with how plugins are meant to ship code in v0.5+ (`${CLAUDE_PLUGIN_ROOT}`
exists for exactly this).

### B — Trim only

Delete the dead inline reference matrix in `builder.md` and tighten verbose
prose. No code moves.

**Why not:** saves maybe 200 lines total. Doesn't address the bulk problem.
The bash is the bulk.

### C — Skill-ify

Convert each long bash block into a Claude Code skill (`skills/<name>/SKILL.md`
+ `bin/`).

**Why not:** skills are user-invoked or skill-tool-invoked. These blocks are
agent-internal mechanism; turning them into skills adds an indirection layer
that has no caller outside the agent. Wrong tool.

## Recommended approach: A — Surgical extraction

### Target layout

```
superhuman/
├── .claude-plugin/
│   ├── plugin.json
│   └── marketplace.json
├── agents/                       # behavioral prose only; cite scripts via ${CLAUDE_PLUGIN_ROOT}
│   ├── SHARED_STATE.md           # 523 → ~440 (helpers move out, schemas move out)
│   ├── builder.md                # 614 → ~180
│   ├── merge-probability-scorer.md  # 555 → ~180
│   ├── opensource-contributor.md # 525 → ~200
│   ├── repo-profiler.md          # 480 → ~200
│   ├── repo-finder.md            # 448 → ~250
│   ├── resolve-comments.md       # 400 → ~220
│   ├── issue-selector.md         # 244 → ~190
│   ├── impact-auditor.md         # 211 → ~170
│   ├── planner.md                # 209 → ~170
│   └── reviewer-dispatcher.md    # 203 → ~170
├── commands/
│   ├── contribution-dashboard.md
│   └── contribution-fleet.md
├── scripts/                      # NEW — runnable mechanism
│   ├── lib/
│   │   ├── state.sh              # state_dir, atomic_write_json, require_lock
│   │   ├── delim.sh              # external-content uuid wrap/unwrap
│   │   ├── telemetry.sh          # emit_telemetry, run_phase
│   │   └── flake.sh              # classify_as_flake, record_flake_hit
│   ├── orchestrator/
│   │   ├── claim_lock.sh
│   │   ├── reputation_gate.sh    # blocklist + cooldown check
│   │   ├── prune_mistakes.sh
│   │   ├── iteration_cap.sh      # adaptive 3/6/10 by LOC
│   │   └── append_fleet_log.sh
│   ├── profiler/
│   │   ├── parse_workflows.sh    # classify_command tokenizer
│   │   ├── detect_smoke.sh       # python_import_root, django_check, flask_app_import,
│   │   │                         # fastapi_app_import, pytest_smoke_dir, node_require_root
│   │   └── catalog_generated.sh
│   ├── builder/
│   │   ├── ci_gate.sh            # allowlist/denylist, sandbox, record_mistake
│   │   ├── smoke_gate.sh         # filter layers[] by changed files
│   │   ├── drift_linter.sh       # newsfragment + removed-symbol + provider-leak
│   │   ├── identity_pin.sh       # post-commit author verify
│   │   └── push_force_with_lease.sh
│   └── scorer/
│       ├── rubric.sh             # 10-dim weighted score
│       ├── historical_blend.sh   # Laplace-ish smoothing
│       ├── append_score.sh       # atomic append to scores[]
│       ├── record_outcome.sh     # JSONL append to merge_outcomes.jsonl
│       └── regen_cooldown.sh     # 180d window from merge_outcomes.jsonl
├── schemas/                      # NEW — JSON Schema draft 2020-12
│   ├── repo_profile.schema.json
│   ├── issue_candidates.schema.json
│   ├── current_contribution.schema.json
│   ├── ci_commands.schema.json
│   ├── allowed_commands.schema.json
│   ├── caller_graph.schema.json
│   ├── repo_blocklist.schema.json
│   ├── generated_files.schema.json
│   ├── repo_cooldown.schema.json
│   ├── maintainer_tone.schema.json
│   └── smoke_registry.schema.json
├── tests/scripts/                # NEW — bats or plain bash with assertions
│   ├── test_state.sh
│   ├── test_classify_command.sh
│   ├── test_iteration_cap.sh
│   └── test_regen_cooldown.sh
├── README.md
└── LICENSE
```

### What moves vs. what stays per agent

| Agent | Stays in prompt | Moves to script |
|---|---|---|
| `builder.md` | Single-author rule, force-with-lease rule, generated-file guard intent, impact-audit dispatch decision tree, push policy | `scripts/builder/ci_gate.sh`, `scripts/builder/smoke_gate.sh`, `scripts/builder/drift_linter.sh`, `scripts/builder/identity_pin.sh`, `scripts/builder/push_force_with_lease.sh`. Inline reference matrix marked "kept as documentation" — **deleted** (was dead weight per file's own admission). |
| `merge-probability-scorer.md` | 10-dim rubric definitions, weights, cap rules, threshold, plateau rule | `scripts/scorer/rubric.sh`, `scripts/scorer/historical_blend.sh`, `scripts/scorer/append_score.sh`, `scripts/scorer/record_outcome.sh`, `scripts/scorer/regen_cooldown.sh` |
| `opensource-contributor.md` | Phase ordering, lock semantics, suspicious-halt rule, terminal states | `scripts/orchestrator/claim_lock.sh`, `scripts/orchestrator/reputation_gate.sh`, `scripts/orchestrator/prune_mistakes.sh`, `scripts/orchestrator/iteration_cap.sh`, `scripts/orchestrator/append_fleet_log.sh`, `scripts/lib/telemetry.sh` |
| `repo-profiler.md` | What gets profiled and why, denylist-first rule, never overwrite `allowed_commands.json` | `scripts/profiler/parse_workflows.sh`, `scripts/profiler/detect_smoke.sh`, `scripts/profiler/catalog_generated.sh` |
| `repo-finder.md` | Scoring weights, blocklist precedence | (small bash, mostly stays inline; only the cooldown read moves to `scripts/lib/state.sh`) |
| `resolve-comments.md` | Classification rules, suspicious-halt action, EXTERNAL_CONTENT wrapping | `scripts/lib/delim.sh` for delimiter helpers |
| `repo-profiler.md`, `builder.md`, `scorer.md`, `orchestrator.md` (shared) | — | `scripts/lib/state.sh` (`state_dir`, `atomic_write_json`, `require_lock`) |
| `SHARED_STATE.md` | Directory layout, ownership table, concurrency contract, prompt-injection wrapping rule, end-to-end run trace | JSON schema bodies → `schemas/*.schema.json`. Helper shell functions section → `scripts/lib/state.sh`. Document keeps a one-line pointer for each (e.g., "schema: see `schemas/repo_profile.schema.json`"). |

### Script-call convention

Every script:

```bash
#!/usr/bin/env bash
set -euo pipefail

# Required: ${CLAUDE_PLUGIN_ROOT} must be set by the plugin runtime.
: "${CLAUDE_PLUGIN_ROOT:?CLAUDE_PLUGIN_ROOT must be set}"

source "${CLAUDE_PLUGIN_ROOT}/scripts/lib/state.sh"
# ...other lib deps...

# Args documented in header comment.
# Exit codes:
#   0 — success
#   1 — recoverable failure (caller decides what to do)
#   2 — unrecoverable (caller should abort phase)
```

Agent prompts cite scripts like:

> Run the CI gate. The exact command pipeline lives at
> `${CLAUDE_PLUGIN_ROOT}/scripts/builder/ci_gate.sh`. It returns
> exit 0 on green, 1 on flake-classified failure (continue), 2 on real
> failure (append `mistakes.md` tag=`builder:ci_gate` and abort).

### Schema validation

`SHARED_STATE.md` already says "Schema validation on read. Every reader
validates against the minimal schema below." Today the schemas are JSONC
comments. Move them to `schemas/*.schema.json` (draft 2020-12, JSON, no
comments) and have `scripts/lib/state.sh` expose:

```bash
validate_json schemas/<name>.schema.json /path/to/file.json
```

Failures still trigger "regenerate via the owner agent" per existing rule.
No behavior change — schemas just live where they can be programmatically
checked.

### Distribution plan

- Bump `.claude-plugin/plugin.json` → `0.5.0` (this is a structural change;
  consumers see new `scripts/` and `schemas/` directories).
- Update `README.md` "Structure" section to show new layout.
- Add `scripts/README.md` explaining the call convention and exit codes.
- No change to `requires.plugins` (still `superpowers` required,
  `everything-claude-code` recommended).

## New slash commands (loop primitives)

The current command set (`/contribution-dashboard`, `/contribution-fleet`)
forces every full run to go through `Agent(subagent_type="opensource-contributor", ...)`,
which is awkward to script and impossible to put in a shell loop. Add
three loop primitives so the user can drive runs from a slash command
or a wrapping shell loop.

### `/contribute [owner/repo] [issue#]`

One full end-to-end contribution. Loopable. Wraps the `opensource-contributor`
agent.

- **No args** → pick top eligible repo from `~/.superhuman/global/repo-shortlist.json`
  (skip blocklisted, skip in-cooldown, skip locked), then run.
- **`owner/repo`** → use that repo, let `issue-selector` pick the issue.
- **`owner/repo issue#`** → use that repo and that exact issue.

Behavior is identical to today's `Agent(subagent_type="opensource-contributor", ...)`
flow — same Phase-0..Phase-8 sequence, same lock semantics, same
terminal outcomes recorded to `merge_outcomes.jsonl`. The slash command
is a thin wrapper that resolves args, calls the orchestrator, and prints
the terminal summary. No new behavior; just a new entry point.

File: `commands/contribute.md`. Body resolves `$ARGUMENTS`, validates
slug shape, optionally validates issue number, then dispatches:

```
Agent(subagent_type: "opensource-contributor",
      prompt: "REPO=<repo> ISSUE=<n|auto> MODE=cli")
```

### `/repo-finder [N]`

Refresh `~/.superhuman/global/repo-shortlist.json` with up to N candidates
(default 10, max 25). Wraps the `repo-finder` agent.

- Reads `repo_blocklist.json` and `repo_cooldown.json` to filter.
- Writes `repo-shortlist.json` atomically (temp + rename).
- Prints the new shortlist.

File: `commands/repo-finder.md`. Body validates `$ARGUMENTS` (must be a
positive integer or empty), then dispatches:

```
Agent(subagent_type: "repo-finder", prompt: "N=<n>")
```

### `/contribute-loop [N]`

Run `/contribute` **sequentially** N times (default N=3, max N=20).
Different from `/contribution-fleet`, which dispatches in parallel.
Sequential matters when the user wants to:

- Stay under GitHub rate limits on a single account.
- Watch one run finish before deciding the next target.
- Avoid the 10-parallel cap of fleet mode.

Loop semantics:

1. For i in 1..N:
   1. Refresh shortlist if i==1 OR if the last run consumed the previous
      top-of-shortlist (so we don't pick the same repo we just contributed
      to and now hold a cooldown on).
   2. Pick top eligible repo from shortlist.
   3. Dispatch `opensource-contributor` (same as `/contribute` no-arg).
   4. On terminal outcome `merged | merge_ready | rejected | abandoned |
      stale`, append a row to `~/.superhuman/global/loop_runs.jsonl` with
      `{loop_id, iter, repo, outcome, pr_url, completed_at}`.
   5. On terminal outcome `suspicious_halt` or `crash`, **stop the loop**
      and surface. Don't keep burning runs into a broken state.
2. Render summary table (`repo | outcome | iters | pr`) for the loop.

File: `commands/contribute-loop.md`. Body validates `$ARGUMENTS`, then
loops over single dispatches. Sequential dispatch is naturally handled
by issuing one `Agent` call per iteration in successive turns (the
fleet trick of "single turn = parallel" is not used here — that's the
whole point).

### Why these three (and not more)

The user wants a loop. These three are the minimum surface that enables
a loop:

- `/repo-finder` populates the candidate set.
- `/contribute` consumes one candidate.
- `/contribute-loop` does that N times sequentially.

Phase-level entry points (`/repo-profiler`, `/issue-selector`, `/score-pr`,
`/resolve-comments`) and maintenance valves (`/blocklist`, `/contribution-cancel`)
are intentionally **deferred** to keep the v0.5.0 surface small. Add
them later if real workflows need them.

### Updates to existing commands

- `/contribution-dashboard` — extended to read `loop_runs.jsonl` and show
  the most recent loop's progress alongside individual runs.
- `/contribution-fleet` — unchanged.

## Build order

1. **Lib first** (`scripts/lib/`). Move `state_dir`, `atomic_write_json`,
   `require_lock`, telemetry, delim helpers. Hand-test each.
2. **Schemas** (`schemas/*.schema.json`). Convert from JSONC in
   SHARED_STATE.md, validate against existing real state files in
   `~/.superhuman/repos/`.
3. **Profiler** (`scripts/profiler/`). Smallest surface, easiest to verify
   (run on one cached repo, diff output JSON against pre-extraction baseline).
4. **Scorer** (`scripts/scorer/`). Rubric + historical blend + cooldown regen.
   Verify on a known PR with frozen scores in `merge_outcomes.jsonl`.
5. **Orchestrator** (`scripts/orchestrator/`). Last-but-one because it
   sequences the others — extracting before downstream is moved would force
   double rewrites.
6. **Builder** (`scripts/builder/`). Largest, riskiest. CI gate, smoke gate,
   drift linter. Run end-to-end against a no-op PR before declaring done.
7. **Loop primitive commands.** Add `commands/contribute.md`,
   `commands/repo-finder.md`, `commands/contribute-loop.md`. These are
   thin wrappers that dispatch existing agents — no new mechanism. Update
   `commands/contribution-dashboard.md` to read `loop_runs.jsonl`. Update
   `README.md` Commands table.

After each step:
- Update the corresponding agent `.md` to cite the new script.
- Run a behavioral diff: trigger the same phase before and after, capture
  state-file outputs, normalize timestamps, byte-compare.

## Success criteria

- `/contribute`, `/repo-finder`, `/contribute-loop` work end-to-end.
  `/contribute-loop 2` completes two sequential runs, with the second
  picking a different repo than the first (cooldown / shortlist refresh
  logic verified).
- Every agent `.md` is **≥30% shorter** in line count.
- `builder.md` and `merge-probability-scorer.md` are **≥50% shorter**.
- State files written by post-extraction code are **byte-identical** to
  pre-extraction code after timestamp normalization (`generated_at`,
  `started_at`, etc.).
- `~/.superhuman/repos/<slug>/*.json` schemas validate clean against
  `schemas/*.schema.json` for at least one real repo.
- A full contribution run (issue-selector → repo-profiler → planner →
  builder → scorer → reviewer-dispatcher → resolve-comments) completes
  with zero behavior delta.
- Single-author commits still single-author. Force-with-lease still in use.
- No new dependencies in `plugin.json` or system requirements.

## Risks

- **`${CLAUDE_PLUGIN_ROOT}` not set** during local script tests outside the
  plugin runtime. Mitigation: scripts assert the var with `:?`; `tests/scripts/`
  exports it manually.
- **Bash 3.2 portability** (macOS default). Already using bash-3.2-safe
  patterns in current code (no `mapfile`, no `${var,,}`, no `[[ =~ ]]` PCRE).
  Linter: `shellcheck --shell=bash` on every new script with the existing
  patterns.
- **Lossy edit during move.** Mitigation: every PR ships diff-of-outputs
  evidence (a known input → captured output before, captured output after,
  empty diff after timestamp normalization).
- **Schema strictness change.** Today JSONC comments document fields
  loosely; JSON Schema draft 2020-12 is stricter. Mitigation: schemas
  start with `additionalProperties: true` and required-list = current
  required fields only. Tighten in a follow-up if desired.

## Open questions

- **Q1.** Should `scripts/lib/state.sh` use `flock` from util-linux on Linux
  and a `mkdir`-based fallback on macOS, or assume both have `flock(2)`
  via a small C shim? **Default:** keep current approach (whatever
  `opensource-contributor.md` does today is unchanged — code moves verbatim).
- **Q2.** Should we ship a `bun test` runner for `tests/scripts/` or stick
  with plain bash + `assert` helpers? **Default:** plain bash; no new
  dep.
- **Q3.** Do we keep the dead inline reference matrix in `builder.md`
  during the move (for review traceability) and delete it in a follow-up
  commit, or delete in the same change? **Default:** delete same-change;
  the file itself says it's documentation-only and the deletion is
  trivially reviewable.

## Next steps

1. User reviews this spec.
2. On approval, invoke `superpowers:writing-plans` to produce the
   implementation plan from this design.
3. Plan should sequence the build-order list above, one PR per step,
   each with output-diff evidence.
