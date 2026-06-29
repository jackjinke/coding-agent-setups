# Coding Agent Setups

Public-safe source files for my coding agent setup.

This repo tracks declarative setup only: agent instructions, prompts, selected
local plugin source, upstream source manifests, and config that refers to
environment variables. It deliberately
does not track OAuth files, API keys, histories, caches, logs, local databases,
browser profiles, or machine-specific runtime state.

## Included

- Codex: `AGENTS.md`, rules, hooks, and a sanitized config.
- Claude Code: global instructions, settings, rules, and status line.
- OpenCode: config, agents, and selected local plugin source.
- Skills installed from their upstream sources during setup/download.

Hermes and Cursor are intentionally not synced.

Skills and some OpenCode plugins are source-managed instead of vendored:

- `sources/managed-skills.tsv` lists skills and upstream installers such as
  `npx skills`, `ui-ux-pro-max-cli`, `oh-my-opencode-slim`, and Caveman.
- `sources/managed-sources.tsv` lists source trees copied from upstream Git.
- `sources/managed-targets.txt` keeps generated upstream installs out of
  `files/`.
- `sources/retired-targets.txt` removes setup entries that should no longer be
  installed.

If a local change is needed on top of upstream, store it as a patch under
`patches/` and reference it from the manifest.

## First-Time Setup

Bootstrap from anywhere:

```bash
repo="$HOME/Projects/coding-agent-setups"; mkdir -p "${repo%/*}"; if [ -d "$repo/.git" ]; then git -C "$repo" pull --ff-only; else git clone https://github.com/jackjinke/coding-agent-setups "$repo"; fi; bash "$repo/scripts/coding-agent-setups.sh" setup
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

Run setup again from an existing checkout:

```bash
bash ~/Projects/coding-agent-setups/scripts/coding-agent-setups.sh setup
```

## Sync

Apply repo files to this machine:

```bash
bash ~/Projects/coding-agent-setups/scripts/coding-agent-setups.sh sync download
```

Refresh the repo from this machine:

```bash
bash ~/Projects/coding-agent-setups/scripts/coding-agent-setups.sh sync upload
```

`sync.sh` always syncs shared files, then syncs only the agent-specific groups
enabled in `~/.config/coding-agent-setups/sync.env`. Manual sync runs ask for
confirmation before copying. Re-run `scripts/setup.sh` to change the enabled
agents for this machine.

During `download`, source-managed skills/plugins are installed from upstream,
then repo-managed config is copied into place. During `upload`, source-managed
and retired targets are removed from `files/` so the repo keeps only source
metadata and patches, not upstream copies.

During `upload`, repo-side target paths are rebuilt from the current machine
state, then the secret check runs automatically. The script lists changed files
without printing full diffs and asks whether to commit and push the prepared
snapshot.

Before every `download`, the script backs up folders it may touch. Backups are
stored inside each folder under `.coding-agent-setups-backups/`, and only the
latest three backups are kept per folder.

Restore from a download backup:

```bash
bash ~/Projects/coding-agent-setups/scripts/coding-agent-setups.sh restore
```

Restore lists the current recoverable versions, lets you choose one, then
restores every folder that has a backup for that version.

Moshi hook is managed outside this repo. If it is installed locally, `download`
preserves local hook commands whose command contains `moshi` for Claude Code and
Codex, and preserves local Moshi plugin entries for OpenCode. `upload` filters
those local Moshi entries out of repo files. The Moshi-specific capture,
restore, and filtering rules live in `scripts/moshi-hooks.sh`.

If an upstream change makes a local patch fail to apply, interactive runs ask
whether to use the upstream latest version without that patch. `--yes` only skips
the top-level sync confirmation; it does not suppress patch conflict prompts.

OpenCode plugin policy is documented in `sources/opencode-plugins.md`.

Before pushing, run:

```bash
bash scripts/check-public-safe.sh
```

## Secrets

OAuth and API credentials are intentionally local. Re-authenticate each tool on a
new machine using the tool's own login command, and keep API keys in local env
files rather than in tracked JSON/TOML config.
