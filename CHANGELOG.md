# Changelog

All notable changes to **superhuman** are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/). The `version` field in `.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json`, and `.codex-plugin/plugin.json` must always match the latest released version here.

## [0.7.1] — 2026-07-03

### Changed
- **Contributor identity is now derived from `gh`, not hard-coded.** The single-author safety rail is unchanged — every commit is still authored by exactly one identity with no co-author trailers or AI attribution — but that identity is now the `gh`-authenticated GitHub user running the plugin (`agents/builder.md` Step 3, `agents/opensource-contributor.md` Phase 0). Anyone who installs the plugin contributes under their own name instead of a hard-coded maintainer. When GitHub hides the account email, the pin falls back to the `ID+login@users.noreply.github.com` privacy address, which still attributes commits on GitHub. Both agents now guard with `gh auth status` and surface `GH_AUTH_MISSING` instead of committing as the wrong person; the post-commit author-verification compares against the derived identity.

## [0.7.0] — 2026-06-28

### Added
- **Codex runtime support.** New `.codex-plugin/plugin.json` manifest and `skills/superhuman/SKILL.md` adapter expose the full contribution workflow to Codex. Same `agents/`, `scripts/`, `schemas/` contracts; Codex executes them inline instead of via subagent dispatch.
- **Concrete `superpowers:` fallback procedures** in `skills/superhuman/SKILL.md`. Codex users without the `superpowers` plugin get a 5-section structure for `writing-plans` (Context, Touch list, Implementation steps, Verification, Risks) and a 5-step execution loop for `subagent-driven-development` (read-edit-verify-recover-commit, escalate at 3 failures).
- **Codex command-equivalent table** in README mapping every Claude Code slash command (`/contribute`, `/contribute-loop`, `/contribution-fleet`, `/contribution-dashboard`, `/repo-finder`) to a Codex prompt. Fleet is flagged unsupported since it requires parallel subagent dispatch Codex does not have.
- **Concrete Codex install instructions** — clone + symlink into `~/.codex/skills/superhuman` instead of a hand-wave to "your normal Codex plugin workflow."

### Changed
- Plugin description and keywords updated across `.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json`, and `.codex-plugin/plugin.json` to reflect dual-runtime support.

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
