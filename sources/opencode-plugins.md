# OpenCode Plugin Sources

## Follow OpenCode/NPM Latest

These are declared in `opencode.jsonc` or `package.json`, or installed by their
published installer. They should not be vendored in this repo:

- `@tarquinen/opencode-dcp` through `package.json` semver; source:
  `https://github.com/Opencode-DCP/opencode-dynamic-context-pruning`
- `oh-my-opencode-slim`
- `opencode-omniroute-auth` through `package.json` semver; source:
  `https://github.com/Alph4d0g/opencode-omniroute-auth`
- `@prevalentware/opencode-goal-plugin` through `package.json` semver; source:
  `https://github.com/prevalentWare/opencode-goal-plugin`

`oh-my-opencode-slim` is installed with:

```bash
bunx oh-my-opencode-slim@latest install --no-tui --skills=yes --companion=no --background-subagents=no
```

Its bundled `worktrees` skill is kept by following the upstream installer.

Herdr's generated OpenCode plugin keeps its provenance and source identity from
the Herdr integration. `publish` snapshots the current locally installed
`~/.config/opencode/plugins/herdr-agent-state.js` into this repo, and `sync`
restores that tracked snapshot without reinstalling or updating it from the
official source. If the local file is missing, `publish` preserves the existing
tracked snapshot and prints a warning. OpenCode discovers it from the plugin
directory without a config entry.

To upgrade the tracked plugin, install the current integration locally, then
publish the resulting snapshot:

```bash
herdr integration install opencode
scripts/sync.sh publish
```

Normal `sync` restores the tracked snapshot; it does not run the Herdr
integration installer.

## Follow Upstream Git

These are local plugin paths in OpenCode config, but their source of truth is an
upstream repo. `scripts/sync.sh sync` clones or fetches the upstream latest
version and installs it locally.

- `caveman`: `https://github.com/JuliusBrussee/caveman`

Caveman is installed with its upstream OpenCode installer:

```bash
npx -y github:JuliusBrussee/caveman -- --only opencode --non-interactive --force
```

After install, `scripts/sync.sh sync` removes the Caveman `cavecrew-*`
OpenCode agents so the local agent list matches this setup.

If a patch is needed for a Git source, add it to `patches/` and reference it from
`sources/managed-sources.tsv`. Installer-managed targets are listed in
`sources/managed-skills.tsv` and `sources/managed-targets.txt`.

## Moshi Hook

Moshi hook integration is tracked by this repo for enabled agents.

- Moshi hook: https://getmoshi.app/docs/hooks

Tracked config:

- Claude Code hook commands in `files/.claude/settings.json`
- Codex hook commands in `files/.codex/hooks.json`
- OpenCode generated plugin in `files/.config/opencode/plugins/moshi-hooks.ts`

`sync` still installs Moshi when missing, pairs it when needed, and starts the
daemon. It does not rerun `moshi-hook install --target ...`; synced config is
the source of truth.

## Env Protection

Env protection is tracked by this repo as
`files/.config/opencode/plugins/env-protection.ts`. OpenCode auto-discovers local
plugins in `~/.config/opencode/plugins/`, so it does not need a `plugin` entry in
`opencode.jsonc`.
