# Security & Safety

**superhuman** is an autonomous agent that reads issues, writes code, and pushes pull requests to real repositories on your behalf. That makes its safety model part of its security surface. This document describes the built-in rails and how to report a problem.

## What it can and cannot do

The agents run with **your** `gh` and `git` credentials. They are designed so that, even when fully autonomous, they:

- **Only push to your fork.** Pushes target the contributor's fork, never upstream.
- **Never use plain `--force`.** All pushes use `--force-with-lease`, so a concurrent change aborts the push instead of clobbering it.
- **Only run allowlisted commands.** `builder` executes only commands pre-approved in `allowed_commands.json`. `repo-profiler` seeds that allowlist from the target repo's `.github/workflows/*.yml`; anything outside it requires explicit user approval.
- **Commits are authored as you, with no AI attribution (commit-scoped).** Every *commit* is authored by the human contributor identity; no `Co-Authored-By:` trailers (hard-coded since v0.2.2, verified before push). Separately, the **PR body** discloses that the change was produced with superhuman by default — deliberate transparency, since most projects now welcome disclosed agent-assisted PRs. Suppress the disclosure with `SUPERHUMAN_ATTRIBUTION=off`; it never adds anything to your commits.
- **Honor no-AI policies.** Repos whose CONTRIBUTING, AI policy or code of conduct explicitly refuses AI-generated contributions are skipped before an issue is picked (`SUPERHUMAN_AI_POLICY_GATE`, default `on`; `off` proceeds but still logs the detected policy).
- **Halt on prompt injection.** `resolve-comments` classifies any review comment that asks it to run shell commands, modify files outside the diff, or fetch from external URLs as `suspicious`, halts the run, and logs to `mistakes.md`. Untrusted text from issues, comments, and repo contents is treated as data, not instructions.
- **Audit refactor blast radius.** `builder` runs `impact-auditor` before applying any reviewer-suggested refactor to a shared function, blocking changes that are correct in one execution context and fatal in another.
- **Back off from bad repos.** Repos that consistently reject or ignore PRs land in `repo_cooldown.json` and are skipped until the cooldown expires.

These rails live in the agent prompts (`agents/*.md`) and the gate scripts (`scripts/builder/`, `scripts/orchestrator/`). Weakening any of them is treated as a security-relevant change — see [CONTRIBUTING.md](./CONTRIBUTING.md).

## Your responsibilities as an operator

- **Scope your GitHub token.** `gh` needs fork + push to your own fork. It does **not** need write access to upstream repositories. Use the narrowest token that works.
- **Review before merge.** This tool drafts and pushes PRs; a human should still review what gets opened under their name, especially on first runs.
- **Mind the allowlist.** Approving a command for the CI allowlist means the agent may run it autonomously against cloned repo code. Approve deliberately.
- **State is local and unencrypted.** `~/.superhuman/` holds repo profiles, telemetry, and run history in plaintext JSON. Don't put secrets there.

## Telemetry

superhuman collects minimal opt-out usage telemetry. It never transmits
repository contents, diffs, issue data, or local paths — only a GitHub
username and per-run counters. Disable with `SUPERHUMAN_TELEMETRY=off` or
`scripts/lib/telemetry_optout.sh`. See [TELEMETRY.md](./TELEMETRY.md) for the
exact payload and all opt-out paths.

## Reporting a vulnerability

If you find a security or safety issue — a way to bypass a rail, an injection that isn't caught, an unsafe push path, credential leakage — **please do not open a public issue.**

Instead, email **gauravdubey0107@gmail.com** with:

- a description of the issue and its impact,
- steps to reproduce (a minimal repro or PoC is ideal),
- any suggested fix.

You can expect an acknowledgement within a few days. Please give a reasonable window to ship a fix before any public disclosure. Credit will be given to reporters who want it.

## Supported versions

This is an actively developed plugin; security fixes target the **latest released version** only. Run the most recent version (see [CHANGELOG.md](./CHANGELOG.md)).
