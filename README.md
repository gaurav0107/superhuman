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

Install as a Claude Code plugin pointing at this repo.

## License

MIT
