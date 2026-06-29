# OpenCode Plugin Sources

## Follow OpenCode/NPM Latest

These are declared in `opencode.json` or `package.json` and should not be
vendored in this repo:

- `@tarquinen/opencode-dcp@latest`
- `opencode-see-image`
- `oh-my-opencode-slim`
- `opencode-goal-plugin` through `package.json` semver

## Follow Upstream Git

These are local plugin paths in OpenCode config, but their source of truth is an
upstream repo. `scripts/sync.sh download` clones or fetches the upstream latest
version and installs it locally.

- `opencode-pty`: `https://github.com/shekohex/opencode-pty.git`

If a patch is needed for one of these, add it to `patches/` and reference it from
`sources/managed-sources.tsv`.

## Local Plugins

These are local custom plugins or helper modules. They stay vendored under
`files/.config/opencode/plugins` until an upstream source is identified.

- `background-agents.ts`
- `caveman/`
- `kdco-primitives/`
- `moshi-hooks.ts`
- `worktree.ts`
- `worktree/`
