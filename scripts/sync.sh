#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: scripts/sync.sh [--to-home|--from-home]

  --to-home    Copy tracked setup files from this repo into $HOME. Default.
  --from-home  Refresh this repo from the whitelisted files in $HOME.
USAGE
}

mode="to-home"
if [[ $# -gt 1 ]]; then
  usage
  exit 2
fi

if [[ $# -eq 1 ]]; then
  case "$1" in
    --to-home) mode="to-home" ;;
    --from-home) mode="from-home" ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      usage
      exit 2
      ;;
  esac
fi

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

require_cmd rsync
require_cmd jq

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
files_dir="$repo_root/files"
home_dir="${HOME:?HOME is not set}"

paths=(
  ".agents/.skill-lock.json"
  ".agents/skills"
  ".codex/AGENTS.md"
  ".codex/config.toml"
  ".codex/hooks.json"
  ".codex/rules"
  ".codex/skills/frontend-design"
  ".claude/CLAUDE.md"
  ".claude/config.json"
  ".claude/rules"
  ".claude/settings.json"
  ".claude/skills"
  ".claude/statusline-command.sh"
  ".config/opencode/AGENTS.md"
  ".config/opencode/agents"
  ".config/opencode/bun.lock"
  ".config/opencode/commands"
  ".config/opencode/dcp.jsonc"
  ".config/opencode/oh-my-opencode-slim.json"
  ".config/opencode/opencode.json"
  ".config/opencode/package-lock.json"
  ".config/opencode/package.json"
  ".config/opencode/plugins/background-agents.ts"
  ".config/opencode/plugins/caveman"
  ".config/opencode/plugins/kdco-primitives"
  ".config/opencode/plugins/moshi-hooks.ts"
  ".config/opencode/plugins/opencode-pty"
  ".config/opencode/plugins/worktree"
  ".config/opencode/plugins/worktree.ts"
  ".config/opencode/skills"
  ".config/opencode/tui.json"
)

rsync_excludes=(
  "--exclude=.git/"
  "--exclude=.agents/"
  "--exclude=.roo/"
  "--exclude=.venv/"
  "--exclude=venv/"
  "--exclude=node_modules/"
  "--exclude=__pycache__/"
  "--exclude=*.pyc"
  "--exclude=.env"
  "--exclude=.env.*"
  "--exclude=auth.json"
  "--exclude=.credentials.json"
  "--exclude=history.jsonl"
  "--exclude=sessions/"
  "--exclude=projects/"
  "--exclude=cache/"
  "--exclude=logs/"
  "--exclude=telemetry/"
  "--exclude=file-history/"
  "--exclude=.ocx/"
  "--exclude=.caveman-active"
  "--exclude=*.sqlite"
  "--exclude=*.sqlite-*"
  "--exclude=*.db"
  "--exclude=*.db-*"
  "--exclude=*.bak.*"
  "--exclude=*.lock"
)

copy_path() {
  local src_root="$1"
  local dst_root="$2"
  local rel="$3"
  local src="$src_root/$rel"
  local dst="$dst_root/$rel"

  if [[ ! -e "$src" ]]; then
    return 0
  fi

  mkdir -p "$(dirname "$dst")"
  if [[ -d "$src" ]]; then
    mkdir -p "$dst"
    rsync -a --delete "${rsync_excludes[@]}" "$src"/ "$dst"/
  else
    rsync -a "${rsync_excludes[@]}" "$src" "$dst"
  fi
}

sanitize_opencode_config() {
  local path="$files_dir/.config/opencode/opencode.json"
  local tmp
  if [[ ! -f "$path" ]]; then
    return 0
  fi
  tmp="$(mktemp)"
  jq '.provider.litellm.options.apiKey = "{env:OPENCODE_LITELLM_API_KEY}"' "$path" > "$tmp"
  mv "$tmp" "$path"
}

sanitize_codex_config() {
  local path="$files_dir/.codex/config.toml"
  local tmp
  if [[ ! -f "$path" ]]; then
    return 0
  fi
  tmp="$(mktemp)"
  awk '
    /^\[projects\./ { skip = 1; next }
    /^\[hooks\.state/ { skip = 1; next }
    /^\[/ { skip = 0 }
    skip == 0 { print }
  ' "$path" > "$tmp"
  mv "$tmp" "$path"
}

cleanup_public_tree() {
  if [[ ! -d "$files_dir" ]]; then
    return 0
  fi
  while IFS= read -r link_path; do
    rm "$link_path"
  done < <(find "$files_dir" \( -xtype l -o -type l -lname '/*' \) -print)
}

sync_from_home() {
  mkdir -p "$files_dir"
  for rel in "${paths[@]}"; do
    copy_path "$home_dir" "$files_dir" "$rel"
  done
  sanitize_opencode_config
  sanitize_codex_config
  cleanup_public_tree
  echo "Refreshed repo files from $home_dir"
}

sync_to_home() {
  for rel in "${paths[@]}"; do
    copy_path "$files_dir" "$home_dir" "$rel"
  done
  echo "Synced repo files into $home_dir"
}

case "$mode" in
  from-home) sync_from_home ;;
  to-home) sync_to_home ;;
esac
