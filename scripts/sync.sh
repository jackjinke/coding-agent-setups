#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: scripts/sync.sh [--to-home|--from-home]

  --to-home    Copy enabled setup files from this repo into $HOME. Default.
  --from-home  Refresh this repo from enabled whitelisted files in $HOME.

Run scripts/setup.sh first. Sync reads the local selection file written by setup.
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
config_home="${XDG_CONFIG_HOME:-$home_dir/.config}"
flag_file="${CODING_AGENT_SETUPS_FLAG_FILE:-$config_home/coding-agent-setups/sync.env}"

shared_paths=(
  ".agents/.skill-lock.json"
  ".agents/skills"
)

codex_paths=(
  ".codex/AGENTS.md"
  ".codex/config.toml"
  ".codex/hooks.json"
  ".codex/rules"
  ".codex/skills/frontend-design"
)

claude_paths=(
  ".claude/CLAUDE.md"
  ".claude/config.json"
  ".claude/rules"
  ".claude/settings.json"
  ".claude/skills"
  ".claude/statusline-command.sh"
)

opencode_paths=(
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

read_flag() {
  local key="$1"
  if [[ -f "$flag_file" ]]; then
    awk -F= -v key="$key" '$1 == key { sub(/^[^=]*=/, ""); print; exit }' "$flag_file"
  fi
}

agent_enabled() {
  local key="SYNC_$1"
  local value
  value="$(read_flag "$key")"
  case "${value,,}" in
    1|true|yes|on) return 0 ;;
    *) return 1 ;;
  esac
}

require_setup_flags() {
  if [[ ! -f "$flag_file" ]]; then
    cat >&2 <<EOF
Missing setup selection file:
  $flag_file

Run scripts/setup.sh first. It installs shared files, asks which coding agents to
sync on this machine, and writes the selection file that sync uses.
EOF
    exit 1
  fi
}

copy_path() {
  local src_root="$1"
  local dst_root="$2"
  local rel="$3"
  local delete_stale="$4"
  local src="$src_root/$rel"
  local dst="$dst_root/$rel"
  local rsync_args=(-a)

  if [[ "$delete_stale" == "0" ]]; then
    rsync_args+=(--omit-dir-times)
  fi

  if [[ ! -e "$src" ]]; then
    return 0
  fi

  mkdir -p "$(dirname "$dst")"
  if [[ -d "$src" ]]; then
    mkdir -p "$dst"
    if [[ "$delete_stale" == "1" ]]; then
      rsync_args+=(--delete)
    fi
    rsync "${rsync_args[@]}" "${rsync_excludes[@]}" "$src"/ "$dst"/
  else
    rsync "${rsync_args[@]}" "${rsync_excludes[@]}" "$src" "$dst"
  fi
}

copy_group() {
  local label="$1"
  local src_root="$2"
  local dst_root="$3"
  local delete_stale="$4"
  shift 4

  echo "Syncing $label"
  for rel in "$@"; do
    copy_path "$src_root" "$dst_root" "$rel" "$delete_stale"
  done
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
  copy_group "shared files" "$home_dir" "$files_dir" 1 "${shared_paths[@]}"
  if agent_enabled CODEX; then
    copy_group "Codex" "$home_dir" "$files_dir" 1 "${codex_paths[@]}"
  fi
  if agent_enabled CLAUDE; then
    copy_group "Claude Code" "$home_dir" "$files_dir" 1 "${claude_paths[@]}"
  fi
  if agent_enabled OPENCODE; then
    copy_group "OpenCode" "$home_dir" "$files_dir" 1 "${opencode_paths[@]}"
  fi
  sanitize_opencode_config
  sanitize_codex_config
  cleanup_public_tree
  echo "Refreshed enabled repo files from $home_dir"
}

sync_to_home() {
  copy_group "shared files" "$files_dir" "$home_dir" 0 "${shared_paths[@]}"
  if agent_enabled CODEX; then
    copy_group "Codex" "$files_dir" "$home_dir" 0 "${codex_paths[@]}"
  fi
  if agent_enabled CLAUDE; then
    copy_group "Claude Code" "$files_dir" "$home_dir" 0 "${claude_paths[@]}"
  fi
  if agent_enabled OPENCODE; then
    copy_group "OpenCode" "$files_dir" "$home_dir" 0 "${opencode_paths[@]}"
  fi
  echo "Synced enabled repo files into $home_dir"
}

require_setup_flags

case "$mode" in
  from-home) sync_from_home ;;
  to-home) sync_to_home ;;
esac
