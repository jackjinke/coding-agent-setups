# Coding Agent Setups

Public-safe source files for my coding agent setup.

This repo tracks declarative setup only: agent instructions, skills, prompts,
plugin source, and config that refers to environment variables. It deliberately
does not track OAuth files, API keys, histories, caches, logs, local databases,
browser profiles, or machine-specific runtime state.

## Included

- Codex: `AGENTS.md`, rules, hooks, selected local skills, and a sanitized config.
- Claude Code: global instructions, settings, rules, status line, and skills.
- OpenCode: config, agents, commands, skills, and plugin source.
- Shared agent skills under `.agents/skills`.

Hermes and Cursor are intentionally not synced.

## First-Time Setup

From a cloned repo:

```bash
bash scripts/setup.sh
```

The setup script is interactive. It always installs shared agent files, then asks
which coding agent setups to sync on this machine:

- Codex
- Claude Code
- OpenCode

If an enabled agent needs local inputs, setup prompts for them. OpenCode currently
prompts for the LiteLLM base URL and API key, writes them to
`~/.config/opencode/.env` with restrictive permissions, and keeps the tracked
`opencode.json` pointed at `{env:OPENCODE_LITELLM_API_KEY}`.

Setup writes the machine-local sync selection to:

```text
~/.config/coding-agent-setups/sync.env
```

That file is not tracked. Later sync runs read it and do not prompt.

For a private GitHub repo, a typical bootstrap is:

```bash
gh repo clone OWNER/coding-agent-setups ~/Projects/coding-agent-setups
bash ~/Projects/coding-agent-setups/scripts/setup.sh
```

For a public repo, replace the `gh repo clone` command with a normal HTTPS clone.

## Sync

Apply repo files to this machine:

```bash
bash scripts/sync.sh --to-home
```

Refresh the repo from this machine:

```bash
bash scripts/sync.sh --from-home
```

`sync.sh` always syncs shared files, then syncs only the agent-specific groups
enabled in `~/.config/coding-agent-setups/sync.env`. Re-run `scripts/setup.sh` to
change the enabled agents for this machine.

Before pushing, run:

```bash
bash scripts/check-public-safe.sh
```

## Secrets

OAuth and API credentials are intentionally local. Re-authenticate each tool on a
new machine using the tool's own login command, and keep API keys in local env
files rather than in tracked JSON/TOML config.
