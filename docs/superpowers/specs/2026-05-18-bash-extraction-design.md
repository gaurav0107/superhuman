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

> **Completeness first. Line counts are not a target.**
>
> An independent audit pass against the agent prompts found 8 places
> where naive extraction would change behavior. They are addressed in
> **"Audit corrections"** below.
>
> The user's rule: *"making them short is less important than the
> completeness"* AND *"don't be so aggressive in lines reduction, you
> can still choose to have more lines."*
>
> Read this as: the line counts in the layout block are **rough estimates,
> not goals.** If preserving a behavior, a corner-case warning, or a
> defensive comment means an agent file ends up the same length as today
> — or longer — that's a successful outcome. The point of extraction is
> to **isolate runnable mechanism from prose** so each can be reviewed
> on its own terms. Token reduction is a side effect, not the prize.
>
> Concretely: a "successful" trim could leave any given agent at 100%
> of its current size if the safety rules, judgment-required prose, and
> defensive comments genuinely require it. The spec MUST NOT push
> against an agent staying long when length is the right call.

### Target layout

```
superhuman/
├── .claude-plugin/
│   ├── plugin.json
│   └── marketplace.json
├── agents/                       # behavioral prose + safety rules + judgment-required logic; mechanical bash cited via ${CLAUDE_PLUGIN_ROOT}
│   ├── SHARED_STATE.md           # today: 523. Sheds: helper bash, JSONC schema bodies. Keeps: layout, ownership, contract, run trace, error & rescue rules. Final length lands wherever it lands.
│   ├── builder.md                # today: 614. Sheds: CI gate body, smoke gate body, drift linter body. Keeps: single-author rule + post-commit awk verifier (it IS the gate), force-with-lease rule, generated-file guard, impact-audit dispatch tree, push policy. Long is fine — safety prose is dense.
│   ├── merge-probability-scorer.md  # today: 555. Sheds: arithmetic, jq pipelines, JSONL appends. Keeps: 10-dim definitions, weights, cap rules + cap TRIGGERS, threshold, plateau rule, blend formula prose.
│   ├── opensource-contributor.md # today: 525. Sheds: prune awk, iteration cap math, fleet log, run summary. Keeps: phase ordering, flock claim + EXIT trap (must stay — fd ownership), suspicious-halt rule, terminal states.
│   ├── repo-profiler.md          # today: 480. Sheds: workflow YAML extraction, smoke layer detector code, generated-file scan code. Keeps: classify_command rules (prose), denylist-first rule, never-overwrite rule, rationale per smoke layer.
│   ├── repo-finder.md            # today: 448. Sheds: reputation_gate (now shared script), cooldown read. Keeps: scoring weights, blocklist precedence, discovery heuristics. Mostly stays inline.
│   ├── resolve-comments.md       # today: 400. Sheds: delim helpers. Keeps: classification rules (judgment-required), suspicious-halt action, EXTERNAL_CONTENT wrapping, force-with-lease restatement.
│   ├── issue-selector.md         # today: 244. Sheds: nothing required; small filters can stay inline. Implementation may extract A/B/B2/F/G filter pipelines if it improves clarity, but not pressured.
│   ├── impact-auditor.md         # today: 211. Sheds: symbol-search jq + emit-JSON block. Keeps: verdict matrix (authoritative), classification logic.
│   ├── planner.md                # today: 209. Minimal extraction (state.sh sourcing only). May stay at ~209 if extraction adds no clarity.
│   └── reviewer-dispatcher.md    # today: 203. Minimal extraction. Pointer to SHARED_STATE.md error rules stays.
├── commands/
│   ├── contribution-dashboard.md
│   └── contribution-fleet.md
├── scripts/                      # NEW — runnable mechanism
│   ├── lib/
│   │   ├── state.sh              # state_dir, global_dir, atomic_write_json, require_lock, validate_json
│   │   ├── delim.sh              # external-content uuid wrap/unwrap
│   │   ├── telemetry.sh          # emit_telemetry, run_phase (phase enum lives here too)
│   │   ├── mistakes.sh           # record_mistake (sourced by builder scripts; takes STATE_DIR/WORKDIR/OWNER_REPO as args)
│   │   └── flake.sh              # classify_as_flake, record_flake_hit
│   ├── orchestrator/
│   │   ├── reputation_gate.sh    # blocklist + cooldown check (used by orchestrator, repo-finder, fleet)
│   │   ├── prune_mistakes.sh
│   │   ├── iteration_cap.sh      # adaptive 3/6/10 by LOC
│   │   ├── append_fleet_log.sh
│   │   └── write_run_summary.sh  # writes ~/.superhuman/repos/<slug>/run_summary.json on every terminal state (incl. crash)
│   #  NOTE: claim_lock is intentionally NOT a script — flock fd must be held by orchestrator's own shell.
│   #  See "Audit corrections" §1.
│   ├── profiler/
│   │   ├── parse_workflows.sh    # extracts run: blocks ONLY; classification stays in agent prompt (see Audit §7)
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
│       ├── compute_score.sh      # arithmetic only (10 dims × weights, plateau detect, raw→final). Cap TRIGGERS stay in prompt.
│       ├── historical_blend.sh   # Laplace-ish smoothing (jq -s preserved)
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

### Audit corrections (completeness over brevity)

These are the eight critical findings from the independent audit, with
the resolution adopted in this spec. Read this section before the
per-agent table — it constrains how the table is interpreted.

**§1. flock fd cannot move to a script.**
Today `opensource-contributor.md:198-216` does `exec 9>"$LOCK_FILE";
flock -n 9` and holds fd 9 for the entire run; a trap on EXIT releases.
If `claim_lock.sh` is a separate process, fd 9 closes when the script
returns, releasing the lock immediately. **Resolution:** the flock
preamble **stays inline in `opensource-contributor.md`**. Only the
*release-and-archive* logic on terminal state moves to a script. The
SHARED_STATE.md run trace already says "trap releases flock fd" — that
remains accurate.

**§2. `record_mistake`, `classify_as_flake`, `record_flake_hit` are
shared bash functions, not scripts.**
Today builder.md:336-403 defines these as inline functions called from
multiple steps. Sub-scripts with `set -euo pipefail` cannot share a
function table. **Resolution:** promote them to `scripts/lib/mistakes.sh`
and `scripts/lib/flake.sh`. Each builder sub-script sources both libs.
Functions take `STATE_DIR`, `WORKDIR`, `OWNER_REPO` as **explicit args**,
not closed-over env (extraction-safe).

**§3. CI-health cap detection logic stays inline in scorer prompt.**
Today the cap-trigger rule (compare `/tmp/<name>.log` timestamps against
`mistakes.md`; SKIPPED only when no log exists at all for any
`local_runnable` command) is prompt-time decision logic — Claude reads
the rule and judges per case. **Resolution:** cap *triggers and rules*
stay in `merge-probability-scorer.md` prompt. Only the *score arithmetic*
(weighted sum, plateau detection, raw→final transform) moves to
`scripts/scorer/compute_score.sh`. Renaming `rubric.sh` → `compute_score.sh`
to make this scope explicit.

**§4. Terminal-state signal for `/contribute-loop`.**
`/contribute-loop` claims to "stop on `suspicious_halt` or `crash`" but
those outcomes only land in `merge_outcomes.jsonl` when the orchestrator
explicitly dispatches `MODE=record_outcome` — a crash skips that path.
**Resolution:** add `scripts/orchestrator/write_run_summary.sh`. The
orchestrator writes `~/.superhuman/repos/<slug>/run_summary.json` on
EVERY terminal state including crash (via the EXIT trap), with shape
`{outcome, iterations, pr_url, completed_at, exit_reason}`. The slash
command reads this file. Normal terminal states ALSO write
`merge_outcomes.jsonl`, but `run_summary.json` is the
single-source-of-truth for the loop runner.

**§5. `Error & rescue rules` section in SHARED_STATE.md must stay.**
Audit caught an enumeration omission. `reviewer-dispatcher.md:157`
points to this section for `AgentNotFoundError` / `ContractViolationError`
fallbacks. **Resolution:** explicit addition to the "stays" list for
`SHARED_STATE.md`. Lines 505-523 of today's SHARED_STATE.md remain
verbatim.

**§6. Six agents had line-count targets but no extraction map.**
**Resolution:** the per-agent table below now lists what moves for
all 11 agents, and the targets are revised to match what's actually
achievable while preserving safety rules inline. `repo-finder.md`,
`resolve-comments.md`, `issue-selector.md`, `impact-auditor.md`,
`planner.md`, `reviewer-dispatcher.md` get only modest cuts (mostly
state-helper sourcing); their bash is small or context-dependent.

**§7. `classify_command` is prose, not bash today.**
This is the single highest extraction risk in the spec. `repo-profiler.md:130-165`
describes classification rules ("denylist first at the token level, not
substring; strip quoted string literals; binary-name denials must match
a whole token; ...") that Claude reads and applies with judgment.
Translating prose to bash is a behavior change, not a move. **Resolution:**
`scripts/profiler/parse_workflows.sh` does **only** the mechanical part
— extracting `run:` blocks from YAML and emitting them on stdout. The
**classification rules stay in the prompt**, and Claude does the
classification (calling small helpers from `scripts/lib/state.sh` for
the file write). Builder uses `allowed_commands.json` to enforce at
execution time, which is a separate code path that already exists.
Net effect: the riskiest "extraction" is downgraded to "extract the
boring half, leave the judgmental half alone."

**§8. Builder safety rules need to stay inline. No line target.**
Single-author defense-in-depth lives across builder.md:209-272 + 609-614:
git config pin, invocation constraints text, post-commit verification
awk block, and Rules-section restatement. Force-with-lease lives at
:556-565 + :602. All of these stay inline per the defense-in-depth
principle. The 30-line awk extractor for `VIOLATIONS` stays inline
(it's the actual gate, not just the rule). **Resolution:** no line
target. Builder lands at whatever length lets the safety prose breathe.

### Other audit findings carried into the implementation

- **§9 (Concerning):** the inline reference matrix at `builder.md:137-200`
  partially overlaps with `impact-auditor.md:118-128` but is not
  byte-identical. Implementation must **diff the two before deletion**;
  any verdicts present in builder's matrix and absent from auditor's
  matrix get added to the auditor before the inline copy is removed.
- **§10 (Concerning):** scorer `notes` field is polymorphic (sometimes
  string, sometimes nested object). Schema for `current_contribution.json`
  must declare `additionalProperties: true` on the scores[].notes leaf
  AND list the known shapes in a `oneOf`. No data shape narrowing.
- **§11 (Concerning):** JSONC comments carry load-bearing prose
  (`repo_blocklist.json` precedence; `repo_cooldown.json` 90/180-day
  rule; `generated_files.json` regenerate_cmd=null contract; etc.).
  Implementation must transcribe these into the schema's
  top-level `description` and per-property `description` fields, not
  drop them.
- **§12:** `run_telemetry.jsonl` allowed-phase enum (SHARED_STATE.md:371-373)
  becomes a JSON Schema `enum` constraint and `lib/telemetry.sh::run_phase`
  validates against it before append. Audit all `run_phase "<label>"`
  call sites during the orchestrator move.
- **§14:** `reputation_gate` is duplicated across `opensource-contributor.md`,
  `repo-finder.md`, and `commands/contribution-fleet.md`. All three
  routes through `scripts/orchestrator/reputation_gate.sh` after the
  move. Spec table updated below.
- **§16:** `resolve-comments.md` classification regex/rules stay in the
  prompt (judgment-required). Only the EXTERNAL_CONTENT delim helpers
  move to `lib/delim.sh`.
- **§18 (Nit, but fix-during-move):** `merge-probability-scorer.md:257`
  has an unbalanced paren in the python3 inline. **Fix in place during
  extraction**, with the fix called out in the commit message.
- **§22:** verify resolve-comments.md after trim still contains
  "force-with-lease only" (Step 4, Rules section). It must.

### What moves vs. what stays per agent

| Agent | Stays in prompt | Moves to script |
|---|---|---|
| `builder.md` | Single-author rule (config pin + invocation constraints + post-commit awk verifier — all inline; the awk IS the gate), force-with-lease rule, generated-file guard rule, impact-audit dispatch decision tree, push policy, smoke-gate intent, classification of CI failures (real vs. flake) | `scripts/builder/ci_gate.sh` (sandbox + allowlist enforce), `scripts/builder/smoke_gate.sh` (takes `$CHANGED` file list as arg), `scripts/builder/drift_linter.sh` (5a/5b/5c sub-checks), `scripts/builder/push_force_with_lease.sh`. **Inline reference matrix at lines 137-200**: implementation must diff against `impact-auditor.md` matrix; any verdict only-in-builder gets ported to the auditor before inline deletion. |
| `merge-probability-scorer.md` | 10-dim rubric definitions, weights, cap rules and **cap triggers** (Process cap, CI-health cap with flake exemption), threshold, plateau rule, historical-signal blend formula | `scripts/scorer/compute_score.sh` (arithmetic only — weighted sum, plateau detection, raw→final), `scripts/scorer/historical_blend.sh` (jq -s preserved), `scripts/scorer/append_score.sh`, `scripts/scorer/record_outcome.sh`, `scripts/scorer/regen_cooldown.sh`. Fix unbalanced paren at `:257` during move. |
| `opensource-contributor.md` | Phase ordering, **flock + lock_holder claim** (must stay inline — fd ownership), suspicious-halt rule, terminal states, EXIT trap that releases lock and writes `run_summary.json` | `scripts/orchestrator/reputation_gate.sh`, `scripts/orchestrator/prune_mistakes.sh`, `scripts/orchestrator/iteration_cap.sh` (3/6/10 by LOC), `scripts/orchestrator/append_fleet_log.sh`, `scripts/orchestrator/write_run_summary.sh`, `scripts/lib/telemetry.sh` (run_phase + enum validation) |
| `repo-profiler.md` | **classify_command rules** (prose; Claude judges), denylist-first rule, never-overwrite `allowed_commands.json`, smoke-layer detection intent and per-layer rationale | `scripts/profiler/parse_workflows.sh` (extract `run:` blocks only — no classification), `scripts/profiler/detect_smoke.sh` (six layer detectors), `scripts/profiler/catalog_generated.sh` (generator-marker scan with 500-entry cap) |
| `repo-finder.md` | Scoring weights, blocklist precedence rule | `scripts/orchestrator/reputation_gate.sh` (shared with orchestrator + fleet), `scripts/lib/state.sh` for cooldown read. Scoring stays inline. |
| `resolve-comments.md` | **Classification rules** (suspicious/question/nit/refactor/concern), suspicious-halt action, EXTERNAL_CONTENT wrapping rule, force-with-lease restatement | `scripts/lib/delim.sh` for delim wrap/unwrap helpers only. The classification regex/rules stay in prompt. |
| `issue-selector.md` | Skip-rules (docs-only, competing PR, <24h), ranking weights | filter pipelines A/B/B2/F/G can move to `scripts/profiler/issue_filters.sh` only if their LOC justifies it; otherwise stay inline. **Decision deferred to implementation**, default = stay inline (small enough). |
| `impact-auditor.md` | Verdict matrix (authoritative), classification logic | symbol-search jq pipeline (`:64-77`) and emit-JSON block (`:157-178`) move to `scripts/orchestrator/audit_impact.sh` — same script `builder.md` dispatches into. Verdict matrix prose stays. |
| `planner.md` | Plan template, what each section means | minimal extraction (state.sh sourcing only) |
| `reviewer-dispatcher.md` | Dispatch decision (weakest non-plateaued dim), specialist mapping table, FINDINGS_JSON contract | minimal extraction; pointer to SHARED_STATE.md "Error & rescue rules" stays in prompt |
| `commands/contribution-fleet.md` (existing) | Fleet semantics, parallel-dispatch rule, hard cap | `scripts/orchestrator/reputation_gate.sh` replaces inline duplicate (lines 80-95 today) |
| All agents that touch state | — | `scripts/lib/state.sh` (`state_dir`, `global_dir`, `atomic_write_json`, `require_lock`, `validate_json`) |
| `SHARED_STATE.md` | Directory layout, ownership table, concurrency contract, prompt-injection wrapping rule, end-to-end run trace, **Error & rescue rules section** (lines 505-523 verbatim) | JSON schema bodies → `schemas/*.schema.json`. Helper shell functions → `scripts/lib/state.sh`. Document keeps one-line pointers (e.g., "schema: `schemas/repo_profile.schema.json`"). Comments in JSONC schemas → schema `description` fields, not dropped. |

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

1. **Lib first** (`scripts/lib/`). Move `state_dir`, `global_dir`,
   `atomic_write_json`, `require_lock`, `validate_json`, telemetry
   (with phase enum validation), delim, **mistakes**, **flake** helpers.
   Hand-test each. Tests in `tests/scripts/test_state.sh`,
   `test_mistakes.sh`, `test_telemetry_phase_enum.sh`.
2. **Schemas** (`schemas/*.schema.json`). Convert from JSONC in
   SHARED_STATE.md, validate against existing real state files in
   `~/.superhuman/repos/`.
3. **Profiler** (`scripts/profiler/`). Smallest surface, easiest to verify
   (run on one cached repo, diff output JSON against pre-extraction baseline).
4. **Scorer** (`scripts/scorer/`). Rubric + historical blend + cooldown regen.
   Verify on a known PR with frozen scores in `merge_outcomes.jsonl`.
5. **Orchestrator** (`scripts/orchestrator/`). Last-but-one because it
   sequences the others — extracting before downstream is moved would force
   double rewrites. **flock claim STAYS inline in the agent prompt**;
   only `reputation_gate.sh`, `prune_mistakes.sh`, `iteration_cap.sh`,
   `append_fleet_log.sh`, `write_run_summary.sh`, `audit_impact.sh` move.
   Update `repo-finder.md` and `commands/contribution-fleet.md` to call
   `reputation_gate.sh` (eliminates 3-place duplication, audit §14).
6. **Builder** (`scripts/builder/`). Largest, riskiest. CI gate, smoke gate,
   drift linter, push. **Identity pin awk verifier stays inline** (it IS
   the gate, not just the rule). **Inline reference matrix at builder.md:137-200
   is diffed against impact-auditor.md verdict matrix BEFORE deletion**;
   any verdict only-in-builder is ported to the auditor first. Run
   end-to-end against a no-op PR before declaring done. Verify
   `mistakes.md` format byte-identical to pre-extraction.
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
- `/contribute-loop` correctly stops on `suspicious_halt` and on `crash`
  by reading `run_summary.json` (verified by injecting both terminal
  states in a test run).
- The flock mutex still holds across the entire run — verified by
  attempting a second `/contribute owner/repo` against the same repo
  while the first is mid-iteration; the second must abort with
  `lock_holder` mismatch (NOT silently proceed).
- `record_mistake` calls from extracted builder scripts produce
  `mistakes.md` entries byte-identical to the pre-extraction format.
- `classify_command` rules in repo-profiler agent prompt produce the
  same allowlist/denylist split as today on at least one real workflow
  YAML (`apache/airflow/.github/workflows/ci.yml` or equivalent).
- **Length is not a success criterion.** An agent that ends up the same
  length as today, or longer, because preserving safety rules and
  judgment-required prose required it, is a successful outcome. The
  success criterion is: mechanical bash that no longer needs to live in
  the prompt has moved to scripts; everything else stays exactly where
  reviewers can find it.
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
  required fields only. JSONC comments transcribed into top-level
  `description` and per-property `description` fields, not dropped.
  `notes` field on scores[] declared `oneOf` over known shapes
  (string OR object) since it is currently polymorphic. Tighten in a
  follow-up if desired.

- **Prompt-time decision logic accidentally hard-coded.** The biggest
  risk in extraction is moving prose-as-judgment to bash-as-rule
  (audit §3, §7). Mitigation: any block where the agent is "applying
  judgment per case" stays in prompt. Mechanical pipelines (regex
  extraction, JSON shaping, file writes) move. **Rule of thumb:** if
  the bash today contains comments like "first match wins" or "use
  judgment for edge cases," it doesn't move.

- **Defense-in-depth fragility.** Single-author rule, force-with-lease
  rule, prompt-injection halt rule live in BOTH prompt AND scripts after
  extraction. Mitigation: implementation must verify every agent prompt
  still carries the rule text after the trim. Acceptance check: grep
  the post-extraction agent files for the canonical phrases
  ("force-with-lease", "single-author", "suspicious", "halt") — counts
  must not decrease vs. pre-extraction except where an agent's role
  legitimately doesn't need a given rule (verified case-by-case).

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
