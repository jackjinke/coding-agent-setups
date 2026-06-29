# OpenCode Plugin Sources

## Follow OpenCode/NPM Latest

These are declared in `opencode.json` or `package.json`, or installed by their
published installer. They should not be vendored in this repo:

- `@tarquinen/opencode-dcp@latest`
- `opencode-see-image`
- `oh-my-opencode-slim`
- `opencode-goal-plugin` through `package.json` semver

`oh-my-opencode-slim` is installed with:

```bash
bunx oh-my-opencode-slim@latest install --no-tui --skills=yes --companion=no --background-subagents=no
```

Its bundled `worktrees` skill is kept by following the upstream installer.

## Follow Upstream Git

These are local plugin paths in OpenCode config, but their source of truth is an
upstream repo. `scripts/sync.sh download` clones or fetches the upstream latest
version and installs it locally.

- `opencode-pty`: `https://github.com/shekohex/opencode-pty.git`
- `caveman`: `https://github.com/JuliusBrussee/caveman`

Caveman is installed with its upstream OpenCode installer:

```bash
npx -y github:JuliusBrussee/caveman -- --only opencode --non-interactive --force
```

After install, `scripts/sync.sh download` removes the Caveman `cavecrew-*`
OpenCode agents so the local agent list matches this setup.

If a patch is needed for a Git source, add it to `patches/` and reference it from
`sources/managed-sources.tsv`. Installer-managed targets are listed in
`sources/managed-skills.tsv` and `sources/managed-targets.txt`.

## External Local Plugins

These are installed and maintained outside this repo. They should not be
vendored, uploaded, or installed by `scripts/sync.sh`.

- Moshi hook: https://getmoshi.app/docs/install

If Moshi hook is installed on a machine, `download` preserves it and `upload`
ignores it.

The same rule applies across agents. `scripts/moshi-hooks.sh` treats hook
commands whose command contains `moshi` as local-only state for Claude Code and
Codex, and treats Moshi plugin entries in `opencode.json` as local-only state
for OpenCode.

There are currently no vendored local OpenCode plugins in this repo.
