# Coding Agent Setups

Public-safe source files for my coding agent setup.

This repo tracks Codex, Claude Code, OpenCode, selected wrappers like `omo`,
and source manifests for upstream skills/plugins. It does not track OAuth files,
API keys, histories, caches, logs, local databases, browser profiles, or other
machine-specific runtime state. Hermes and Cursor are intentionally not synced.

## Bootstrap

Setup from anywhere:

```bash
tmp="$(mktemp "${TMPDIR:-/tmp}/coding-agent-setups.XXXXXX")" && curl -fsSL https://github.com/jackjinke/coding-agent-setups/raw/main/scripts/setup.sh -o "$tmp" && bash "$tmp"
```

Setup and immediately download the enabled config:

```bash
tmp="$(mktemp "${TMPDIR:-/tmp}/coding-agent-setups.XXXXXX")" && curl -fsSL https://github.com/jackjinke/coding-agent-setups/raw/main/scripts/setup.sh -o "$tmp" && bash "$tmp" --sync
```

Setup is interactive. It asks which agents to sync and whether to install shell
commands. Local choices are written to:

```text
~/.config/coding-agent-setups/sync.env
```

If shell commands are enabled, setup installs:

```text
coding-agent-setups
coding-agent-sync
```

## Use

Download the latest enabled setup to this machine:

```bash
coding-agent-sync
```

Upload this machine's enabled setup into the repo:

```bash
coding-agent-setups sync upload
```

Re-run setup:

```bash
coding-agent-setups setup
```

Restore from a download backup:

```bash
coding-agent-setups restore
```

If shell commands were not enabled, use the repo-local entrypoint:

```bash
bash ~/Projects/coding-agent-setups/scripts/coding-agent-setups.sh sync download
```

## Notes

- `coding-agent-setups` pulls the repo before running, so later sync runs use
  the latest scripts.
- `download` backs up folders it may touch under
  `~/.config/coding-agent-setups/backups/` and keeps the latest three backups.
- `upload` runs the secret check, lists changed files, and can commit/push.
- API keys stay in local env files. Tracked config should reference env vars.
- Moshi hook state is local-only and is preserved across download/upload.

Before pushing manually:

```bash
bash scripts/check-public-safe.sh
```
