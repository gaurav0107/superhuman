# Changelog

All notable changes to **superhuman** are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/). The `version` field in `.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json`, and `.codex-plugin/plugin.json` must always match the latest released version here.

## [Unreleased]

### Fixed
- Issue triage no longer grades generic agreement such as "makes sense to me" or "good catch" as defect confirmation by itself. A standalone "False flag" maintainer comment now counts as a dismissal, including multiple spaces, tabs, or newlines between the words, while negations and questions retain their existing verdicts. Explicit reproduction and PR invitations keep their signal tiers. These are conservative lexical corrections for #33; ambiguous reply targets still require semantic review.

## [0.6.8] — 2026-08-11

## [0.6.7] — 2026-07-21

## [0.6.6] — 2026-07-19

## [0.6.5] — 2026-07-19

### Added
- **User search preferences (`/preferences`, `~/.superhuman/preferences.md`).** `/repo-finder`'s filters were constants baked into the agent prompt (`language:java`, `language:python`), and no command accepted a preference — ask for Go, get Python. They are now sourced from a file the **user** owns. `## Filters` (`languages`, `topics`, `stars`) is mechanical: parsed by `scripts/lib/preferences.sh`, compiled 1:1 into GitHub search qualifiers by `scripts/repo-finder/build_queries.sh`. `## Notes` is prose the agent applies at tie-breaks and issue selection only — never to a numeric score, and disclosed in the shortlist's `notes` field when it does. `topic[:min_stars]` gives one topic its own floor; `any` is reserved and compiles to a query with no `topic:` qualifier; `stars` is a floor and there is no ceiling (a range is a loud error, not a quiet cap). `/repo-finder` gains `--lang` / `--topic` / `--min-stars` overrides that shape one run and never persist. No preferences file means `DEFAULT_PROFILE`, byte-identical to the queries the agent carried inline, so `/contribute` on a fresh machine cannot regress. Covered by `tests/scripts/test_parse_preferences.sh` and `test_build_queries.sh` (network-free, bash 3.2-clean).

### Changed
- **Query shape follows the qualifier asymmetry.** Repeated `language:` unions; repeated `topic:` **intersects**. So languages collapse into one query and each topic gets its own — query count is `|topics|`, and adding a language costs zero queries. Emitting two `topic:` qualifiers on one line silently returns only repos tagged with *every* topic, often none, with exit 0 and no error; `build_queries.sh` refuses to emit one. Same class of silent failure: a typo'd qualifier key and a parenthesized `OR` both return `total_count: 0` with exit 0, so both are rejected at emit time rather than trusted.

### Removed
- **`repo-finder`'s Category Preference Order and its `3e` category bonus (10%).** With filtering server-side, every candidate matches the user's filters by construction, so a bonus for matching is a constant added to every row and ranks nothing. Its weight went to signals that discriminate: responsiveness 30 → **35%**, outside-contributor track 20 → **25%**.

### Fixed
- **A `preferences.md` with no `## Filters` block no longer dead-ends the scan.** A file carrying only `## Notes` (or an empty `## Filters` block) compiled to a catch-all and aborted `repo-finder` with `exit 10` and a misleading "`topics: any` with no languages" error the user never wrote — leaving `/contribute` with an empty shortlist. Such a file now means "default filters, plus advisory notes" and falls back to `DEFAULT_PROFILE`. A `## Filters` block with a real typo (`langauges: go`) still fails loudly, so the fallback never swallows a malformed filter. New `prefs_has_filters` helper in `scripts/lib/preferences.sh`; covered by `test_build_queries.sh`.
- **`/repo-finder` overrides now inherit saved axes from a non-canonical `## filters` header.** The override path (`--lang`/`--topic`/`--min-stars`) read the saved profile with an exact, case-sensitive `## Filters` matcher while `preferences.sh` accepts `## filters` and spacing variants — so `/repo-finder --topic cli` on a hand-edited lowercase-header profile silently dropped the saved `languages`/`stars` and searched with defaults. Both readers now use the same detector. Covered by the new `test_repo_finder_override_inherit.sh`.
- **The `## Filters` header is matched fully case-insensitively (`tolower`), in both readers.** Previously only `Filters`/`filters` were recognized; a `## FILTERS` block was silently ignored — and with the notes-only fallback above, that meant it emitted the default profile and dropped the user's filters with no error. `scripts/lib/preferences.sh` and the `/repo-finder` override path now normalize the header the same way.
- **An override that inherits from a malformed saved profile now fails loudly.** The override extraction greps the saved block for exact keys (`languages:`), so a mistyped `langauges: go` — which the normal path rejects with `exit 10` — was silently dropped, letting an override run proceed on a broken profile. When any axis is inherited, the saved profile is now validated with the same compiler the normal path uses (a full `--lang/--topic/--min-stars` override skips the check, since it reads nothing from the saved file).

## [0.6.4] — 2026-07-13

## [0.6.3] — 2026-07-12

### Added
- **Automated patch releases on merge (`.github/workflows/release.yml`).** Every push to `main` now cuts a release: an ordinary merge auto-bumps the patch version across all three manifests, promotes the `## [Unreleased]` CHANGELOG section into a dated section, commits the bump back to `main`, then tags and publishes the GitHub Release. A merge that already carries a new version (a manual minor/major bump) is released as-is instead of being patched past. The version-writing + CHANGELOG promotion is extracted to `scripts/release/prepare_release.sh` (covered by `tests/scripts/test_prepare_release.sh`), with strict `^X.Y.Z$` validation so a malformed manifest version can't reach the workflow. Replaces `release-tag.yml`, which only tagged manual bumps.
- **Merge gating on `main`.** Branch protection now requires the `suite` CI checks to pass and all review conversations (CodeRabbit) to be resolved before a PR can merge — a failing check or an unresolved review comment blocks the merge. The release bot pushes its bump commit with a `RELEASE_TOKEN` admin PAT to get past protection (`enforce_admins=false`); see CONTRIBUTING → Versioning & releases.
- **One-command installer (`install.sh`).** Installs superhuman **and its dependent plugins** — `superpowers` (required) and `everything-claude-code` / ECC (recommended) — in a single command via the Claude Code CLI (`claude plugin marketplace add` / `plugin install`). Idempotent and re-runnable; checks prerequisites (`git`/`gh`/`jq`/`python3` + `gh auth`), and falls back to printing the manual slash-commands when the `claude` CLI isn't on `PATH`. Flags: `--skip-ecc`, `--codex` (clone + symlink the Codex skill), `--dry-run`. Usage: `curl -fsSL https://raw.githubusercontent.com/gaurav0107/superhuman/main/install.sh | bash`. Covered by `tests/scripts/test_install.sh`; README **Installation** section leads with it.

### Fixed
- **Installer used the wrong marketplace/plugin IDs**, so both dependency installs failed (`Plugin "superpowers" not found in marketplace "superpowers"`, and likewise for ECC). The marketplace name comes from each repo's `marketplace.json`, not the repo slug. Corrected to the verified IDs: `superpowers@superpowers-marketplace` (via `obra/superpowers-marketplace`) and `ecc@ecc` (via `affaan-m/everything-claude-code`). Added a bare-plugin-name retry so a future marketplace rename self-heals instead of hard-failing. README manual commands updated to match.

## [0.6.2] — 2026-07-06

### Added
- **Usage & lifecycle telemetry.** Two new opt-out PostHog events extend adoption measurement beyond terminal contribution outcomes, governed by the same single opt-out gate (`SUPERHUMAN_TELEMETRY=off` / `telemetry.json` / `print`):
  - **`superhuman_used`** — emitted (backgrounded, non-blocking) on every command invocation, carrying `command` and `version`. All five commands (`contribute`, `contribute-loop`, `contribution-dashboard`, `contribution-fleet`, `repo-finder`) are instrumented.
  - **`superhuman_lifecycle`** — emitted once after install or a version change (`kind` = `install`|`update`, plus `version`, `prev_version`), inferred from a cached `~/.superhuman/global/last_version.json` since Claude Code plugins have no native installer hook.
  - **`scripts/lib/telemetry_common.sh`** — shared, sourced opt-out/identity/version/send helpers; `usage_ping.sh` refactored to source it (behavior parity), new `usage_event.sh` emits the two events.
- Payload remains minimal (`distinct_id` = GitHub username only); `TELEMETRY.md` documents all three events.

### Fixed
- `usage_event.sh` no longer writes the lifecycle cache in `SUPERHUMAN_TELEMETRY=print` (dry-run) mode, so previewing telemetry no longer consumes the one-shot install/update signal.

## [0.6.1] — 2026-07-06

### Fixed
- **PR-body attribution is now rogue-proof — the canonical footer is the single source of truth.** `scripts/orchestrator/pr_body_with_attribution.sh` now *scrubs* any model-authored attribution line from the PR body before appending the deterministic `🤖 Opened with [Superhuman](…)` footer (or, with `SUPERHUMAN_ATTRIBUTION=off`, emitting the scrubbed body with no footer). This prevents a model-improvised, unlinked, fine-print disclosure line (or double attribution) from replacing the canonical linked footer. Scrubbing is scoped to the **footer zone** (after the last `---`, else the trailing paragraph, else the final line) and gated on a structural signal, so legitimate mid-body prose is never touched. The same pass also strips Claude/AI attribution (`🤖 Generated with…`, `Co-authored-by:`, `noreply@anthropic.com`) from the PR body, closing a gap where those were guarded only in commit messages. `agents/planner.md` gains a matching defense-in-depth rule: never author attribution in the PR body — the harness owns the canonical footer.

## [0.6.0] — 2026-07-05

> First tagged release since `v0.5.1`. The interim `0.7.0` / `0.7.1` / `0.8.0` version bumps were manifest-only and never tagged, so their changes are consolidated into this release.

### Added
- **Learning substrate — the system now learns from reviewer feedback instead of repeating it.** A durable, typed knowledge base that outlives a single run and generalizes across repos, closing a Birth → Retrieve → Prevent → Enforce → Curate loop so the same review comments stop recurring across merged PRs.
  - **`lesson-distiller` agent** (producer/curator; sole owner of the knowledge base). *Seed mode* authors a short repo architecture **dossier** grounded in a deterministic structural scan, and emits deterministic scan **rule cards**. *Curate mode* mines a run's classified reviewer comments and merge outcome into typed rule cards, then runs graduated cross-repo promotion, age-based decay, contradiction-demotion, demoted→active re-confirmation, and maintainer-reraise regression logging.
  - **Rule cards** (`schemas/rule_card.schema.json`) — typed, provenance-tracked convention records. Deterministic cards reference one of a fixed check registry (`file_present`, `file_in_dir`, `commit_matches`, `identifier_case`); semantic cards carry prose the scorer's LLM pass judges. A card is DATA — no executable field — and a mined `check.id` outside the registry is force-converted to semantic.
  - **PREVENT** — `planner` and `builder` retrieve the dossier + matching cards (`select_lessons.sh`) and inject them as MUST-follow conventions (planner's Compliance checklist; builder's subagent-driven-development constraints).
  - **ENFORCE** — `merge-probability-scorer` runs `check_lessons.sh` on the diff; an unfixed ENFORCED violation caps the merge score at 75% (blocks merge-ready ≥80%) and lists the rule under Blocking Issues. Shipped violations are logged to a cross-repo regression corpus at terminal only.
  - **Graduated cross-repo promotion** — a repo-scoped rule recurring across ≥2 distinct repos becomes a `global-candidate`; ≥3 graduates it to enforced `global` scope.
  - **Scripts** (all unit-tested, bash-3.2-safe): `scripts/lessons/{select_lessons,check_lessons,merge_cards,promote_lessons,decay_lessons,record_regression,set_lesson_status}.sh`; `scripts/profiler/{scan_structure,write_repo_scan,dossier_fresh}.sh`; `scripts/lib/lesson_checks.sh` (fixed check registry + canonical dedupe key).
  - **Observability** — `/contribution-dashboard` gains a Learning panel: per-repo rule-card counts (total / active / enforced / by kind, plus demoted) and dossier freshness, and a global section with promoted cards (candidate vs. enforced) and the regression alarm log.
- **New shared-state files** (registered in `agents/SHARED_STATE.md`): `repo_scan.json` (owner repo-profiler); `dossier.md`, `dossier_meta.json`, `lessons.jsonl`, `lessons_global.jsonl`, `lesson_regressions.jsonl` (owner lesson-distiller); `classified_comments.json` (owner resolve-comments — the distiller handoff). Each with a draft 2020-12 schema where applicable.
- **PR-origin disclosure.** `scripts/orchestrator/pr_body_with_attribution.sh` assembles the PR body and appends a Superhuman origin-disclosure footer, honoring `SUPERHUMAN_ATTRIBUTION`. Unit-tested by `tests/scripts/test_pr_body_with_attribution.sh`; `agents/opensource-contributor.md` Phase 6 pipes the plan-derived body through it before `gh pr create`.
- **Codex runtime support.** `.codex-plugin/plugin.json` manifest and `skills/superhuman/SKILL.md` adapter expose the full contribution workflow to Codex, executing the same `agents/`, `scripts/`, `schemas/` contracts inline instead of via subagent dispatch. Includes concrete `superpowers:` fallback procedures, a Codex command-equivalent table in the README, and clone + symlink install instructions.

### Changed
- `repo-profiler` now publishes `repo_scan.json` (deterministic structural scan of the worktree) to ground the dossier.
- `resolve-comments` persists classified, non-suspicious comments to `classified_comments.json` for the distiller.
- `opensource-contributor` sequences the distiller: `MODE=seed` after profiling (Phase 2.5) and `MODE=curate` post-terminal (Phase 8.5) — both non-fatal.
- `skills/superhuman/SKILL.md` gained the learning-substrate safety rail for the Codex runtime.
- **PRs now disclose their Superhuman origin by default** — a one-line footer on the **PR body** (`🤖 Opened with [Superhuman](https://github.com/gaurav0107/superhuman), an open-source contribution agent.`). Set `SUPERHUMAN_ATTRIBUTION=off` (also `false`/`0`/`no`) to suppress it.
- **Contributor identity is derived from `gh`, not hard-coded** (`agents/builder.md` Step 3, `agents/opensource-contributor.md` Phase 0). Whoever installs the plugin contributes under their own name; falls back to the `ID+login@users.noreply.github.com` privacy address when GitHub hides the email. Both agents guard with `gh auth status` and surface `GH_AUTH_MISSING`.
- **The single-author commit rule is unchanged and now explicitly commit-scoped.** Commits carry no `Co-Authored-By:` trailers and no AI attribution (pre-push verifier enforces it); the disclosure lives only in the PR body.
- Plugin description and keywords updated across the three manifests to reflect dual-runtime (Claude Code + Codex) support.

### Security
- Reviewer comments feeding the distiller are treated as EXTERNAL_CONTENT; the distiller extracts ONLY into the constrained rule-card schema. A comment attempting a command, URL, or out-of-repo write is classified `suspicious`, logged to `mistakes.md`, and never minted into a card. Enforced rules feed the scorer's judgment only — they can never expand `allowed_commands.json` or drive builder shell. The active↔demoted transition routes exclusively through `set_lesson_status.sh`; `merge_cards.sh` refuses status-flips-via-merge, so a crafted comment cannot flip an enforced rule by re-merging it.

## [0.5.1] — 2026-06-08

### Fixed
- **Orchestrator could not dispatch.** The Claude Code harness does not grant the `Agent` tool to spawned subagents, so `opensource-contributor` running as a subagent could never fan out to specialists. The orchestrator now executes each specialist contract **inline** — it reads the specialist `.md` and follows it itself — and records `mode: "inline"` in run telemetry. `dispatched` mode is reserved for a future top-level slash-command orchestrator.
- **Manifest drift.** `marketplace.json` had been left at `0.4.1` since v0.5.0 shipped; it is now re-synced with `plugin.json`.

## [0.5.0] — 2026-05-18

### Changed
- **Bash extracted from agent prompts into versioned `scripts/`.** Inline `bash`/`jq` was the bulk of every prompt; moving it out shrinks per-phase load and makes the logic unit-testable. Safety prose (single-author rule, force-with-lease, suspicious-halt) intentionally stays inline in the prompts. Hard constraint for this release: lose no behavior.
- **JSON Schemas formalised under `schemas/`.** Every shared-state file now has a draft 2020-12 schema, validated at write time.

### Added
- Loop primitive commands: `/contribute`, `/repo-finder`, `/contribute-loop`.
- Bash unit-test suite under `tests/scripts/` covering `scripts/` and every schema.

## [0.4.1] — 2026

### Changed
- Declared plugin dependencies (`superpowers` required, `everything-claude-code` recommended) in `plugin.json` under `requires.plugins`.
- Dropped hard-coded `gstack` paths.
- Rewrote the README for public consumption.

## [0.4.0] — 2026

### Added
- `merge-probability-scorer` historical-signal predictor (blends a 10-dimension rubric with past merge outcomes).
- `impact-auditor` agent — refactor blast-radius auditor that blocks reviewer-suggested refactors which break one caller to fix another.
- `/contribution-fleet` parallel run launcher with per-run state isolation and a `flock(2)` mutex.
- Smoke gate in `builder`.

## [0.3.0] — 2026

### Changed
- Hardened the contributor agent — tightened phase sequencing, iteration caps, and merge-threshold handling.

## [0.2.4] — 2026

### Fixed
- Dashboard now runs on macOS's default bash 3.2.

### Added
- Reputation state surfaced in `/contribution-dashboard`.

## [0.2.3] — 2026

### Added
- Reputation gate: repos that consistently reject or ignore PRs land in a cooldown and are skipped by `repo-finder`.

### Changed
- Migrated all persistent state to `~/.superhuman/`.

## [0.2.2] — 2026

### Changed
- Hard-coded the single-author commit rule; forbids `Co-Authored-By:` / AI-attribution trailers. Every commit is authored by the human contributor identity.

## [0.2.0] — 2026

### Changed
- Version bump to trigger plugin cache refresh.

## [0.0.1-beta] — 2026

### Added
- Initial release: orchestrator plus specialist agents for autonomous open-source contribution.

[0.5.1]: https://github.com/gaurav0107/superhuman/releases/tag/v0.5.1
[0.5.0]: https://github.com/gaurav0107/superhuman/releases/tag/v0.5.0
[0.3.0]: https://github.com/gaurav0107/superhuman/releases/tag/v0.3.0
[0.0.1-beta]: https://github.com/gaurav0107/superhuman/releases/tag/v0.0.1-beta
