#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: scripts/sync.sh [download|upload] [--yes]

  download  Copy enabled setup files from this repo into $HOME.
  upload    Refresh this repo from enabled whitelisted files in $HOME.
  --yes     Skip the confirmation prompt.

Run scripts/setup.sh first. Sync reads the local selection file written by setup.
USAGE
}

mode=""
assume_yes=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    download)
      if [[ -n "$mode" ]]; then
        usage
        exit 2
      fi
      mode="download"
      ;;
    upload)
      if [[ -n "$mode" ]]; then
        usage
        exit 2
      fi
      mode="upload"
      ;;
    -y|--yes)
      assume_yes=1
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      usage
      exit 2
      ;;
  esac
  shift
done

if [[ -z "$mode" ]]; then
  usage
  exit 2
fi

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

require_cmd rsync
require_cmd jq
require_cmd git
require_cmd patch
require_cmd sha1sum

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
files_dir="$repo_root/files"
home_dir="${HOME:?HOME is not set}"
config_home="${XDG_CONFIG_HOME:-$home_dir/.config}"
flag_file="${CODING_AGENT_SETUPS_FLAG_FILE:-$config_home/coding-agent-setups/sync.env}"
setup_dir="$config_home/coding-agent-setups"
git_cache_dir="$setup_dir/git"
managed_sources_file="$repo_root/sources/managed-sources.tsv"

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

print_enabled_groups() {
  echo "  - shared files"
  if agent_enabled CODEX; then
    echo "  - Codex"
  fi
  if agent_enabled CLAUDE; then
    echo "  - Claude Code"
  fi
  if agent_enabled OPENCODE; then
    echo "  - OpenCode"
  fi
}

confirm_sync() {
  local answer
  if [[ "$assume_yes" == "1" ]]; then
    return 0
  fi

  echo "Sync action: $mode"
  case "$mode" in
    download)
      echo "Direction: repo files -> $home_dir"
      echo "Local-only files are preserved."
      ;;
    upload)
      echo "Direction: $home_dir -> repo files"
      echo "Stale files may be deleted inside $files_dir for enabled groups."
      echo "Public-safe sanitizers run after copying."
      ;;
  esac
  echo "Enabled groups:"
  print_enabled_groups

  read -r -p "Proceed? [y/N]: " answer
  case "${answer,,}" in
    y|yes) ;;
    *)
      echo "Cancelled."
      exit 1
      ;;
  esac
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

source_target_enabled() {
  local target="$1"
  case "$target" in
    .agents/skills/*) return 0 ;;
    .codex/*)
      agent_enabled CODEX
      return
      ;;
    .claude/*)
      agent_enabled CLAUDE
      return
      ;;
    .config/opencode/*)
      agent_enabled OPENCODE
      return
      ;;
    *) return 1 ;;
  esac
}

cache_dir_for_repo() {
  local repo="$1"
  local key
  key="$(printf '%s' "$repo" | sha1sum | awk '{ print $1 }')"
  printf '%s/%s' "$git_cache_dir" "$key"
}

checkout_managed_repo() {
  local repo="$1"
  local ref="$2"
  local cache_dir="$3"
  local default_branch

  mkdir -p "$git_cache_dir"
  if [[ -d "$cache_dir/.git" ]]; then
    git -C "$cache_dir" fetch --prune --tags origin
  else
    git clone "$repo" "$cache_dir"
  fi

  if [[ "$ref" == "latest" ]]; then
    git -C "$cache_dir" remote set-head origin -a >/dev/null 2>&1 || true
    default_branch="$(git -C "$cache_dir" symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null | sed 's#^origin/##')"
    if [[ -z "$default_branch" ]]; then
      default_branch="main"
    fi
    git -C "$cache_dir" checkout --quiet --detach "origin/$default_branch"
  elif git -C "$cache_dir" rev-parse --verify --quiet "origin/$ref" >/dev/null; then
    git -C "$cache_dir" checkout --quiet --detach "origin/$ref"
  else
    git -C "$cache_dir" checkout --quiet --detach "$ref"
  fi
}

apply_managed_patch() {
  local target="$1"
  local patch_rel="$2"
  local patch_file="$repo_root/$patch_rel"
  local answer

  if [[ "$patch_rel" == "-" ]]; then
    return 0
  fi
  if [[ ! -f "$patch_file" ]]; then
    echo "Missing patch file: $patch_file" >&2
    exit 1
  fi

  if patch --dry-run -p1 -d "$target" < "$patch_file" >/dev/null; then
    patch -p1 -d "$target" < "$patch_file" >/dev/null
    return 0
  fi

  echo "Patch no longer applies cleanly: $patch_rel" >&2
  echo "Target: $target" >&2
  if [[ ! -t 0 ]]; then
    echo "Using upstream version without this patch." >&2
    return 0
  fi

  read -r -p "Use upstream latest without applying this patch? [y/N]: " answer
  case "${answer,,}" in
    y|yes) return 0 ;;
    *) echo "Cancelled."; exit 1 ;;
  esac
}

run_managed_build() {
  local target="$1"
  local build_cmd="$2"
  if [[ "$build_cmd" == "-" ]]; then
    return 0
  fi
  (cd "$target" && bash -lc "$build_cmd")
}

install_managed_sources() {
  local target_rel repo ref source_path patch_rel build_cmd
  local cache_dir source_dir target

  if [[ ! -f "$managed_sources_file" ]]; then
    return 0
  fi
  if [[ "${CODING_AGENT_SETUPS_SKIP_MANAGED_SOURCES:-0}" == "1" ]]; then
    echo "Skipping managed upstream sources."
    return 0
  fi

  while IFS=$'\t' read -r target_rel repo ref source_path patch_rel build_cmd; do
    [[ -z "${target_rel:-}" || "$target_rel" == \#* ]] && continue
    if ! source_target_enabled "$target_rel"; then
      continue
    fi

    echo "Installing upstream source: $target_rel"
    cache_dir="$(cache_dir_for_repo "$repo")"
    checkout_managed_repo "$repo" "$ref" "$cache_dir"
    source_dir="$cache_dir/$source_path"
    target="$home_dir/$target_rel"
    if [[ ! -d "$source_dir" ]]; then
      echo "Managed source path not found: $source_dir" >&2
      exit 1
    fi
    mkdir -p "$target"
    rsync -a --delete "${rsync_excludes[@]}" "$source_dir"/ "$target"/
    apply_managed_patch "$target" "$patch_rel"
    run_managed_build "$target" "$build_cmd"
  done < "$managed_sources_file"
}

claude_shared_skill_link_excluded() {
  case "$1" in
    xiaohongshu-cli) return 0 ;;
    *) return 1 ;;
  esac
}

ensure_claude_shared_skill_links() {
  local skill_dir="$home_dir/.agents/skills"
  local claude_skill_dir="$home_dir/.claude/skills"
  local source_path name link_path excluded_link

  if ! agent_enabled CLAUDE; then
    return 0
  fi
  if [[ ! -d "$skill_dir" ]]; then
    return 0
  fi

  mkdir -p "$claude_skill_dir"
  excluded_link="$claude_skill_dir/xiaohongshu-cli"
  if [[ -L "$excluded_link" ]]; then
    rm "$excluded_link"
  fi

  while IFS= read -r source_path; do
    name="$(basename "$source_path")"
    if claude_shared_skill_link_excluded "$name"; then
      continue
    fi
    link_path="$claude_skill_dir/$name"
    if [[ -e "$link_path" || -L "$link_path" ]]; then
      continue
    fi
    ln -s "../../.agents/skills/$name" "$link_path"
  done < <(find "$skill_dir" -maxdepth 1 -mindepth 1 -type d -print)
}

prune_managed_sources_from_repo() {
  local target_rel repo ref source_path patch_rel build_cmd
  local target

  if [[ ! -f "$managed_sources_file" ]]; then
    return 0
  fi

  while IFS=$'\t' read -r target_rel repo ref source_path patch_rel build_cmd; do
    [[ -z "${target_rel:-}" || "$target_rel" == \#* ]] && continue
    if ! source_target_enabled "$target_rel"; then
      continue
    fi
    target="$files_dir/$target_rel"
    if [[ -e "$target" || -L "$target" ]]; then
      rm -rf "$target"
    fi
  done < "$managed_sources_file"
}

upload_from_home() {
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
  prune_managed_sources_from_repo
  cleanup_public_tree
  echo "Refreshed enabled repo files from $home_dir"
}

download_to_home() {
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
  install_managed_sources
  ensure_claude_shared_skill_links
  echo "Synced enabled repo files into $home_dir"
}

require_setup_flags
confirm_sync

case "$mode" in
  upload) upload_from_home ;;
  download) download_to_home ;;
esac
