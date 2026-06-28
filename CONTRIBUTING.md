# Contributing to superhuman

Thanks for your interest. This is a [Claude Code](https://claude.com/claude-code) plugin that runs a team of agents to make autonomous open-source contributions. Contributions of all sizes are welcome — bug fixes, new safety rails, better reviewers, docs.

## Ground rules

- **Be kind and assume good faith.** See [our Code of Conduct](#code-of-conduct).
- **Keep the safety model intact.** This plugin pushes real code to real repos. Any change that weakens a [safety rail](./SECURITY.md) (single-author rule, force-with-lease, CI allowlist, prompt-injection halt, reputation cooldown) needs an explicit rationale and will get extra scrutiny.
- **Lossless refactors.** Several past releases (e.g. v0.5.0 bash extraction) had "lose no behavior" as a hard constraint. If you're refactoring, prove the behavior is preserved with tests.

## Repo layout

```
superhuman/
├── .claude-plugin/   # plugin.json + marketplace.json manifests
├── agents/           # subagent prompts (the behavioral logic) + SHARED_STATE.md
├── commands/         # slash commands (/contribute, /repo-finder, …)
├── scripts/          # shell extracted from agent prompts, organised by agent
│   ├── lib/          # shared helpers: state.sh, mistakes.sh, flake.sh, delim.sh
│   ├── profiler/  scorer/  orchestrator/  builder/
├── schemas/          # JSON Schema (draft 2020-12) for every shared-state file
├── tests/scripts/    # bash unit tests for scripts/ (one per script/schema)
└── docs/             # design specs and plans for notable changes
```

### Where logic lives

Behavior is split deliberately:

- **Agent prompts (`agents/*.md`)** hold the reasoning, decisions, and safety prose. Things a model needs to *judge* stay here.
- **Scripts (`scripts/*.sh`)** hold the deterministic shell — JSON reads/writes, state transitions, gates. Things a computer should *execute the same way every time* live here.

When you find yourself writing more than a couple of lines of `bash`/`jq` inside an agent prompt, extract it to `scripts/` and call it from the prompt. That keeps prompts short (cheaper to load per phase) and makes the logic testable.

## Development setup

You need `gh`, `git`, `jq`, and `python3` on your `PATH` (see [README → Prerequisites](./README.md#prerequisites)). No build step — it's prompts and shell.

To work on the plugin live, install it from your local checkout:

```
/plugin marketplace add /absolute/path/to/your/superhuman/checkout
/plugin install superhuman@superhuman
/reload-plugins
```

## Tests

Every script in `scripts/` has a matching test in `tests/scripts/`. They're plain bash — no framework. Each one sets `set -euo pipefail` and exits non-zero on failure, writing only to `mktemp` dirs (never your real `~/.superhuman/`).

Run the full suite:

```bash
for t in tests/scripts/test_*.sh; do bash "$t" || echo "FAIL: $t"; done
```

Run one:

```bash
bash tests/scripts/test_state.sh
```

**A green suite is required before opening a PR.** If you add or change a script, add or update its test. If you change a shared-state file's shape, update **both** its `schemas/*.schema.json` and the `tests/scripts/test_schema_*.sh` fixture — they drift easily (the v0.5.1 `mode` telemetry field is a cautionary tale).

## Pull request checklist

- [ ] All tests pass (`for t in tests/scripts/test_*.sh; do bash "$t" || echo FAIL $t; done`).
- [ ] New/changed scripts have tests.
- [ ] Changed shared-state shapes update schema **and** test fixture together.
- [ ] No safety rail weakened without explicit justification in the PR body.
- [ ] If behavior changed meaningfully, `version` is bumped in **all three** manifests — `.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json`, and `.codex-plugin/plugin.json` (they must match — they've drifted before), and `CHANGELOG.md` has an entry.
- [ ] Notable design decisions captured under `docs/` when warranted.

## Versioning & releases

Versions follow [semver](https://semver.org/). The three manifests — `.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json`, and `.codex-plugin/plugin.json` — **must carry the same version**; a mismatch is a release bug (it happened in v0.4.1→v0.5.0). Add a dated, summarised entry to [CHANGELOG.md](./CHANGELOG.md) for every release.

## Reporting bugs & requesting features

Open a [GitHub issue](https://github.com/gaurav0107/superhuman/issues). For anything security- or safety-sensitive, follow [SECURITY.md](./SECURITY.md) instead of filing a public issue.

## Code of Conduct

Be respectful, inclusive, and constructive. Harassment, discrimination, and personal attacks are not tolerated. Maintainers may remove comments, commits, and contributions that violate this, and may block repeat offenders. Report concerns to the maintainer listed in [SECURITY.md](./SECURITY.md).

## License

By contributing, you agree that your contributions are licensed under the [MIT License](./LICENSE).
