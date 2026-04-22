# superhuman

Personal skills and agents library for Claude Code.

Structured as a Claude Code plugin, inspired by [obra/superpowers](https://github.com/obra/superpowers).

## Structure

```
superhuman/
├── .claude-plugin/
│   └── plugin.json
├── agents/          # Subagents invokable via the Agent tool
└── skills/          # Skills invokable via the Skill tool
```

## Agents

- **opensource-contributor** — End-to-end open source contribution workflow.
- **merge-probability-scorer** — Scores likelihood that a PR/patch will be merged.
- **repo-finder** — Finds repositories matching given criteria.

## Skills

None yet. Add `.md` files under `skills/<skill-name>/SKILL.md` as you build them.

## Installation

In Claude Code:

```
/plugin marketplace add https://github.com/gaurav0107/superhuman
/plugin install superhuman@superhuman
/reload-plugins
```

> This repo is private — `gh auth` or a GitHub token with repo read access is required on the machine that installs it.

## License

MIT
