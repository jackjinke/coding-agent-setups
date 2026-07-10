# Coding Agent Setups

Public-safe source files for my coding agent setup.

This repo tracks Codex, Claude Code, OpenCode, selected wrappers like `omos`,
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
~/.coding-agent-setups/sync.env
```

The repo checkout lives under:

```text
~/.coding-agent-setups/source
```

Backups and managed upstream checkouts also stay under `~/.coding-agent-setups/`.

If shell commands are enabled, setup installs:

```text
coding-agent-setups
```

## Use

Sync the latest enabled setup to this machine:

```bash
coding-agent-setups sync
```

Sync only checked-in config files, skipping dependency and upstream installers:

```bash
coding-agent-setups sync --config-only
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
bash ~/.coding-agent-setups/source/scripts/coding-agent-setups.sh sync
```

## Notes

- `coding-agent-setups sync` and `coding-agent-setups publish` fetch
  `origin/main` and hard-reset the source checkout before running, so commands
  use the latest tracked scripts.
- `sync` backs up folders it may touch under
  `~/.coding-agent-setups/backups/` and keeps the latest three backups.
- `publish` runs the secret check, lists changed files, and can commit/push.
- API keys stay in local env files. Tracked config should reference env vars.
- OpenCode setup installs an `opencode` shell wrapper that launches `omos`,
  which loads `~/.config/opencode/.env`, starts tmux, and chooses a random high port.
- Moshi hook config is tracked for enabled agents; sync only ensures Moshi is
  installed, paired, and serving.

Before pushing manually:

```bash
bash scripts/check-public-safe.sh
```
