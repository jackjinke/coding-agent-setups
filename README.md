# Coding Agent Setups

Public-safe source files for my coding agent setup.

This repo tracks Codex, Claude Code, OpenCode, selected wrappers like `omo`,
and source manifests for upstream skills/plugins. It does not track OAuth files,
API keys, histories, caches, logs, local databases, browser profiles, or other
machine-specific runtime state. Hermes and Cursor are intentionally not synced.

## Bootstrap

Setup from anywhere:

```bash
bash -c "$(curl -fsSL https://github.com/jackjinke/coding-agent-setups/raw/main/scripts/setup.sh)"
```

Setup is interactive. It asks which agents to sync and whether to install shell
commands. Local choices are written to:

```text
~/.config/coding-agent-setups/sync.env
```

If shell commands are enabled, setup installs:

```text
coding-agent-setups
```

## Use

Sync the latest enabled setup to this machine:

```bash
coding-agent-setups sync
```

Publish this machine's enabled setup into the repo:

```bash
coding-agent-setups publish
```

Re-run setup:

```bash
coding-agent-setups setup
```

Restore from a sync backup:

```bash
coding-agent-setups restore
```

If shell commands were not enabled, use the repo-local entrypoint:

```bash
bash ~/Projects/coding-agent-setups/scripts/coding-agent-setups.sh sync
```

## Notes

- `coding-agent-setups sync` pulls the repo before running, so sync uses
  the latest scripts.
- `sync` backs up folders it may touch under
  `~/.config/coding-agent-setups/backups/` and keeps the latest three backups.
- `publish` runs the secret check, lists changed files, and can commit/push.
- API keys stay in local env files. Tracked config should reference env vars.
- Moshi hook state is local-only and is preserved across sync/publish.

Before pushing manually:

```bash
bash scripts/check-public-safe.sh
```
