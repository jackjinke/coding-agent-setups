# Coding Agent Setups

Public-safe source files for my coding agent setup.

This repo tracks generic shared setup, Codex, Claude Code, OpenCode, OMP, and
selected wrappers like `omos`, plus source manifests for upstream skills/plugins.
It does not track OAuth files, API keys, histories, caches, logs, local databases,
browser profiles, or other machine-specific runtime state. Hermes and Cursor are
intentionally not synced.

## Bootstrap

Setup from anywhere:

```bash
bash -c "$(curl -fsSL https://github.com/jackjinke/coding-agent-setups/raw/main/scripts/setup.sh)"
```

Setup is interactive. It installs the shell command and configures the local
OpenCode environment. Machine-local state is written to:

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

Choose what to sync to this machine from a checklist. The available groups are
Generic/shared, Codex, Claude Code, OpenCode, and OMP:

```bash
coding-agent-setups sync
```

Sync only checked-in config files, skipping dependency and upstream installers:

```bash
coding-agent-setups sync --config-only
```

For automation, `--yes` skips the checklist and uses the defaults saved by setup.

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
- OpenCode setup aliases `opencode` to `omos` in Bash/Zsh. With no arguments,
  `omos` starts OpenCode in Herdr on a random high port; arguments pass directly
  to the real OpenCode CLI without port or multiplexer handling.
- Sync runs `moshi-hook install --target ...` for each selected harness, then
  ensures Moshi is installed, paired, and serving.

Before pushing manually:

```bash
bash scripts/check-public-safe.sh
```
