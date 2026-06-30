#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: scripts/sync.sh [sync|publish] [--yes]

  sync     Copy enabled setup files from this repo into $HOME.
  publish  Refresh this repo from enabled whitelisted files in $HOME.
  --yes    Skip the confirmation prompt.

Run scripts/setup.sh first. Sync reads the local selection file written by setup.
USAGE
}

mode=""
assume_yes=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    sync)
      if [[ -n "$mode" ]]; then
        usage
        exit 2
      fi
      mode="sync"
      ;;
    publish)
      if [[ -n "$mode" ]]; then
        usage
        exit 2
      fi
      mode="publish"
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

home_dir="${HOME:?HOME is not set}"
PATH="$home_dir/.local/bin:$home_dir/.bun/bin:$PATH"
export PATH

if [[ -z "$mode" ]]; then
  usage
  exit 2
fi

packages_for_command() {
  local command_name="$1"

  case "$(uname -s):$command_name" in
    Darwin:npx) printf '%s\n' node ;;
    Linux:npx) printf '%s\n' nodejs npm ;;
    *:*) printf '%s\n' "$command_name" ;;
  esac
}

install_packages() {
  if [[ $# -eq 0 ]]; then
    return 1
  fi

  case "$(uname -s)" in
    Darwin)
      if ! command -v brew >/dev/null 2>&1; then
        return 1
      fi
      brew install "$@"
      ;;
    Linux)
      if command -v apt-get >/dev/null 2>&1; then
        sudo apt-get update
        sudo apt-get install -y "$@"
      elif command -v dnf >/dev/null 2>&1; then
        sudo dnf install -y "$@"
      elif command -v yum >/dev/null 2>&1; then
        sudo yum install -y "$@"
      elif command -v pacman >/dev/null 2>&1; then
        sudo pacman -Sy --needed --noconfirm "$@"
      elif command -v zypper >/dev/null 2>&1; then
        sudo zypper install -y "$@"
      else
        return 1
      fi
      ;;
    *)
      return 1
      ;;
  esac
}

ensure_cmd() {
  local command_name="$1"
  shift || true
  local packages=("$@")

  if command -v "$command_name" >/dev/null 2>&1; then
    return 0
  fi

  if [[ "${#packages[@]}" -eq 0 ]]; then
    while IFS= read -r package_name; do
      packages+=("$package_name")
    done < <(packages_for_command "$command_name")
  fi

  echo "Missing required command: $command_name; attempting to install ${packages[*]}."
  install_packages "${packages[@]}" || true

  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "Missing required command after install attempt: $command_name" >&2
    exit 1
  fi
}

ensure_bunx() {
  if command -v bunx >/dev/null 2>&1; then
    return 0
  fi

  echo "Missing required command: bunx; attempting to install Bun."
  case "$(uname -s)" in
    Darwin)
      if command -v brew >/dev/null 2>&1; then
        brew install bun
      elif command -v curl >/dev/null 2>&1; then
        curl -fsSL https://bun.sh/install | bash
      fi
      ;;
    Linux)
      ensure_cmd curl
      curl -fsSL https://bun.sh/install | bash
      ;;
  esac

  PATH="$home_dir/.bun/bin:$PATH"
  export PATH
  if ! command -v bunx >/dev/null 2>&1; then
    echo "Missing required command after install attempt: bunx" >&2
    exit 1
  fi
}

require_sha1() {
  if command -v sha1sum >/dev/null 2>&1 || command -v shasum >/dev/null 2>&1; then
    return 0
  fi
  echo "Missing required command: sha1sum or shasum" >&2
  exit 1
}

lower() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]'
}

make_temp_file() {
  local tmp_base="${TMPDIR:-/tmp}"
  mktemp "$tmp_base/coding-agent-setups.XXXXXX"
}

sha1_text() {
  if command -v sha1sum >/dev/null 2>&1; then
    sha1sum | awk '{ print $1 }'
  else
    shasum -a 1 | awk '{ print $1 }'
  fi
}

ensure_cmd rsync
ensure_cmd jq
if [[ "$mode" == "publish" ]]; then
  ensure_cmd git
fi
if [[ "$mode" == "sync" ]]; then
  ensure_cmd git
  ensure_cmd npx
  ensure_cmd patch
  require_sha1
  ensure_cmd tar
fi

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/scripts/local-bin.sh"
source "$repo_root/scripts/moshi-hooks.sh"

files_dir="$repo_root/files"
config_home="${XDG_CONFIG_HOME:-$home_dir/.config}"
flag_file="${CODING_AGENT_SETUPS_FLAG_FILE:-$config_home/coding-agent-setups/sync.env}"
setup_dir="$config_home/coding-agent-setups"
git_cache_dir="$setup_dir/git"
managed_sources_file="$repo_root/sources/managed-sources.tsv"
managed_skills_file="$repo_root/sources/managed-skills.tsv"
managed_targets_file="$repo_root/sources/managed-targets.txt"
retired_targets_file="$repo_root/sources/retired-targets.txt"

shared_paths=()

codex_paths=(
  ".codex/AGENTS.md"
  ".codex/config.toml"
  ".codex/hooks.json"
  ".codex/rules"
)

claude_paths=(
  ".claude/CLAUDE.md"
  ".claude/config.json"
  ".claude/rules"
  ".claude/settings.json"
  ".claude/statusline-command.sh"
)

opencode_paths=(
  ".local/bin/omo"
  ".config/opencode/AGENTS.md"
  ".config/opencode/agents"
  ".config/opencode/bun.lock"
  ".config/opencode/dcp.jsonc"
  ".config/opencode/oh-my-opencode-slim.json"
  ".config/opencode/opencode.json"
  ".config/opencode/package-lock.json"
  ".config/opencode/package.json"
  ".config/opencode/tui.json"
)

rsync_excludes=(
  "--exclude=.git/"
  "--exclude=.coding-agent-setups-backups/"
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
  "--exclude=plugins/moshi-hooks.ts"
  "--exclude=moshi-hooks.ts"
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
  case "$(lower "$value")" in
    1|true|yes|on) return 0 ;;
    *) return 1 ;;
  esac
}

shell_commands_enabled() {
  local value
  value="$(read_flag INSTALL_SHELL_COMMANDS)"
  case "$(lower "$value")" in
    0|false|no|off) return 1 ;;
    *) return 0 ;;
  esac
}

require_setup_flags() {
  if [[ ! -f "$flag_file" ]]; then
    cat >&2 <<EOF
Missing setup selection file:
  $flag_file

Run scripts/setup.sh first. It asks which coding agents to sync on this machine
and writes the selection file that sync uses.
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
    if [[ "$delete_stale" == "1" && ( -e "$dst" || -L "$dst" ) ]]; then
      rm -rf "$dst"
    fi
    return 0
  fi

  mkdir -p "$(dirname "$dst")"
  if [[ -d "$src" ]]; then
    if [[ "$delete_stale" == "1" && ( -e "$dst" || -L "$dst" ) ]]; then
      rm -rf "$dst"
    fi
    mkdir -p "$dst"
    if [[ "$delete_stale" == "1" ]]; then
      rsync_args+=(--delete)
    fi
    rsync "${rsync_args[@]}" "${rsync_excludes[@]}" "$src"/ "$dst"/
  else
    if [[ "$delete_stale" == "1" && ( -e "$dst" || -L "$dst" ) ]]; then
      rm -rf "$dst"
    fi
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
    sync)
      echo "Direction: repo files -> $home_dir"
      echo "Local-only files are preserved."
      echo "Touched folders are backed up before changes."
      ;;
    publish)
      echo "Direction: $home_dir -> repo files"
      echo "Stale files may be deleted inside $files_dir for enabled groups."
      echo "Secret check runs after copying."
      echo "Changed files are listed before the commit/push prompt."
      ;;
  esac
  echo "Enabled groups:"
  print_enabled_groups

  read -r -p "Proceed? [y/N]: " answer
  case "$(lower "$answer")" in
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
  tmp="$(make_temp_file)"
  jq '
    .provider.litellm.options.apiKey = "{env:OPENCODE_LITELLM_API_KEY}"
  ' "$path" > "$tmp"
  mv "$tmp" "$path"
  sanitize_moshi_opencode_plugins "$path"
}

sanitize_codex_config() {
  local path="$files_dir/.codex/config.toml"
  local tmp
  if [[ ! -f "$path" ]]; then
    return 0
  fi
  tmp="$(make_temp_file)"
  awk '
    /^\[projects\./ { skip = 1; next }
    /^\[hooks\.state/ { skip = 1; next }
    /^\[/ { skip = 0 }
    skip == 0 { print }
  ' "$path" > "$tmp"
  mv "$tmp" "$path"
}

cleanup_public_tree() {
  local link_path link_target

  if [[ ! -d "$files_dir" ]]; then
    return 0
  fi
  while IFS= read -r link_path; do
    link_target="$(readlink "$link_path" 2>/dev/null || true)"
    if [[ ! -e "$link_path" || "$link_target" == /* ]]; then
      rm "$link_path"
    fi
  done < <(find "$files_dir" -type l -print)
}

backup_keep_count=3
backup_dir="$setup_dir/backups"

sync_backup_roots() {
  if shell_commands_enabled || agent_enabled OPENCODE; then
    printf '%s\n' "$home_dir/.local/bin"
  fi
  if agent_enabled CODEX || agent_enabled OPENCODE; then
    printf '%s\n' "$home_dir/.agents"
  fi
  if agent_enabled CODEX; then
    printf '%s\n' "$home_dir/.codex"
  fi
  if agent_enabled CLAUDE; then
    printf '%s\n' "$home_dir/.claude"
  fi
  if agent_enabled OPENCODE; then
    printf '%s\n' "$config_home/opencode" "$home_dir/.opencode"
  fi
}

prune_folder_backups() {
  local count=0
  local backup_path

  if [[ ! -d "$backup_dir" ]]; then
    return 0
  fi

  while IFS= read -r backup_path; do
    count=$((count + 1))
    if (( count > backup_keep_count )); then
      rm -rf "$backup_path"
    fi
  done < <(
    for backup_path in "$backup_dir"/*; do
      [[ -d "$backup_path" ]] || continue
      printf '%s\n' "$backup_path"
    done | sort -r
  )
}

backup_name_for_root() {
  local root="$1"
  printf '%s' "$root" | sed 's#^/##; s#[^A-Za-z0-9._-]#_#g'
}

create_folder_backup() {
  local root="$1"
  local backup_id="$2"
  local backup_set_dir="$backup_dir/$backup_id"
  local archive="$backup_set_dir/$(backup_name_for_root "$root").tar.gz"

  mkdir -p "$root"
  mkdir -p "$backup_set_dir"
  tar -czf "$archive" --exclude="./.coding-agent-setups-backups" -C "$root" .
  echo "Backed up $root -> $archive"
}

create_sync_backups() {
  local root
  local backup_id
  local has_roots=0

  backup_id="${CODING_AGENT_SETUPS_BACKUP_ID:-$(date -u +%Y%m%dT%H%M%SZ)}"
  while IFS= read -r root; do
    if [[ "$has_roots" == "0" ]]; then
      echo "Creating sync backups: $backup_id"
      has_roots=1
    fi
    create_folder_backup "$root" "$backup_id"
  done < <(sync_backup_roots)
  if [[ "$has_roots" == "1" ]]; then
    prune_folder_backups
  fi
}

source_target_enabled() {
  local target="$1"
  case "$target" in
    .agents/*) return 0 ;;
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
    .opencode/*)
      agent_enabled OPENCODE
      return
      ;;
    .local/bin/omo)
      agent_enabled OPENCODE
      return
      ;;
    *) return 1 ;;
  esac
}

csv_contains() {
  local csv="$1"
  local value="$2"
  case ",$csv," in
    *",$value,"*) return 0 ;;
    *) return 1 ;;
  esac
}

cache_dir_for_repo() {
  local repo="$1"
  local key
  key="$(printf '%s' "$repo" | sha1_text)"
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
  case "$(lower "$answer")" in
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

remove_caveman_opencode_agents() {
  if ! agent_enabled OPENCODE; then
    return 0
  fi
  rm -f \
    "$config_home/opencode/agents/cavecrew-builder.md" \
    "$config_home/opencode/agents/cavecrew-investigator.md" \
    "$config_home/opencode/agents/cavecrew-reviewer.md"
}

install_npx_skill() {
  local source="$1"
  local skill="$2"
  local allowed_agents="$3"
  local agent_args=()

  if agent_enabled CODEX && csv_contains "$allowed_agents" codex; then
    agent_args+=(-a codex)
  fi
  if agent_enabled CLAUDE && csv_contains "$allowed_agents" claude-code; then
    agent_args+=(-a claude-code)
  fi
  if agent_enabled OPENCODE && csv_contains "$allowed_agents" opencode; then
    agent_args+=(-a opencode)
  fi
  if [[ "${#agent_args[@]}" -eq 0 ]]; then
    return 0
  fi

  echo "Installing skill via npx skills: $source@$skill"
  npx skills@latest add "$source" -g --copy -y "${agent_args[@]}" -s "$skill"
}

install_uipro() {
  local allowed_agents="$1"

  if agent_enabled CODEX && csv_contains "$allowed_agents" codex; then
    echo "Installing UI UX Pro Max for Codex"
    npx ui-ux-pro-max-cli@latest init --ai codex --global --force
  fi
  if agent_enabled CLAUDE && csv_contains "$allowed_agents" claude-code; then
    echo "Installing UI UX Pro Max for Claude Code"
    npx ui-ux-pro-max-cli@latest init --ai claude --global --force
  fi
  if agent_enabled OPENCODE && csv_contains "$allowed_agents" opencode; then
    echo "Installing UI UX Pro Max for OpenCode"
    npx ui-ux-pro-max-cli@latest init --ai opencode --global --force
  fi
}

install_opencode_ohmy() {
  if ! agent_enabled OPENCODE; then
    return 0
  fi
  ensure_bunx
  echo "Installing oh-my-opencode-slim"
  bunx oh-my-opencode-slim@latest install \
    --no-tui \
    --skills=yes \
    --companion=no
}

install_opencode_caveman() {
  if ! agent_enabled OPENCODE; then
    return 0
  fi
  echo "Installing Caveman for OpenCode"
  if ! npx -y github:JuliusBrussee/caveman -- --only opencode --non-interactive --force; then
    echo "Caveman installer failed." >&2
    return 1
  fi
  remove_caveman_opencode_agents
}

resolve_opencode_plugin_ref() {
  local ref="$1"

  case "$ref" in
    /*) printf '%s' "$ref" ;;
    ./*) printf '%s/%s' "$config_home/opencode" "${ref#./}" ;;
    ../*) printf '%s/%s' "$config_home/opencode" "$ref" ;;
    *) return 1 ;;
  esac
}

remove_opencode_plugin_ref() {
  local config="$1"
  local ref="$2"
  local tmp

  tmp="$(make_temp_file)"
  jq --arg ref "$ref" '
    if (.plugin? | type) == "array" then
      .plugin |= map(select(. != $ref))
    else
      .
    end
  ' "$config" > "$tmp"
  mv "$tmp" "$config"
}

repair_missing_opencode_file_plugins() {
  local config="$config_home/opencode/opencode.json"
  local refs_file ref plugin_path

  if ! agent_enabled OPENCODE || [[ ! -f "$config" ]]; then
    return 0
  fi

  refs_file="$(make_temp_file)"
  jq -r '
    .plugin[]?
    | select(type == "string")
    | select(startswith("./") or startswith("../") or startswith("/"))
  ' "$config" > "$refs_file"

  while IFS= read -r ref; do
    plugin_path="$(resolve_opencode_plugin_ref "$ref" || true)"
    [[ -n "$plugin_path" ]] || continue

    if [[ "$ref" == "./plugins/caveman/plugin.js" && ! -e "$plugin_path" && "${CODING_AGENT_SETUPS_SKIP_MANAGED_SOURCES:-0}" != "1" ]]; then
      echo "Caveman plugin file is missing; reinstalling Caveman for OpenCode."
      if install_opencode_caveman && [[ -e "$plugin_path" ]]; then
        continue
      fi
    fi

    if [[ ! -e "$plugin_path" ]]; then
      echo "Removing missing OpenCode plugin reference: $ref" >&2
      remove_opencode_plugin_ref "$config" "$ref"
    fi
  done < "$refs_file"

  rm -f "$refs_file"
}

install_managed_skills() {
  local installer source skill allowed_agents notes

  if [[ ! -f "$managed_skills_file" ]]; then
    return 0
  fi
  if [[ "${CODING_AGENT_SETUPS_SKIP_MANAGED_SOURCES:-0}" == "1" ]]; then
    echo "Skipping managed upstream skills."
    return 0
  fi

  while IFS=$'\t' read -r installer source skill allowed_agents notes <&3; do
    [[ -z "${installer:-}" || "$installer" == \#* ]] && continue
    case "$installer" in
      npx-skills)
        if ! install_npx_skill "$source" "$skill" "$allowed_agents"; then
          echo "Managed skill install failed; continuing: $source@$skill" >&2
        fi
        ;;
      uipro)
        install_uipro "$allowed_agents"
        ;;
      opencode-ohmy)
        install_opencode_ohmy
        ;;
      opencode-caveman)
        install_opencode_caveman
        ;;
      *)
        echo "Unknown managed skill installer: $installer" >&2
        exit 1
        ;;
    esac
  done 3< "$managed_skills_file"
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

prune_target_file_from_repo() {
  local target_file="$1"
  local target_rel target

  if [[ ! -f "$target_file" ]]; then
    return 0
  fi

  while IFS= read -r target_rel; do
    [[ -z "${target_rel:-}" || "$target_rel" == \#* ]] && continue
    target="$files_dir/$target_rel"
    if [[ -e "$target" || -L "$target" ]]; then
      rm -rf "$target"
    fi
  done < "$target_file"
}

remove_target_file_from_home() {
  local target_file="$1"
  local target_rel target

  if [[ ! -f "$target_file" ]]; then
    return 0
  fi

  while IFS= read -r target_rel; do
    [[ -z "${target_rel:-}" || "$target_rel" == \#* ]] && continue
    if ! source_target_enabled "$target_rel"; then
      continue
    fi
    target="$home_dir/$target_rel"
    if [[ -e "$target" || -L "$target" ]]; then
      rm -rf "$target"
    fi
  done < "$target_file"
}

prune_non_vendored_targets_from_repo() {
  local target_rel repo ref source_path patch_rel build_cmd
  local target

  prune_target_file_from_repo "$managed_targets_file"
  prune_target_file_from_repo "$retired_targets_file"

  if [[ ! -f "$managed_sources_file" ]]; then
    return 0
  fi

  while IFS=$'\t' read -r target_rel repo ref source_path patch_rel build_cmd; do
    [[ -z "${target_rel:-}" || "$target_rel" == \#* ]] && continue
    target="$files_dir/$target_rel"
    if [[ -e "$target" || -L "$target" ]]; then
      rm -rf "$target"
    fi
  done < "$managed_sources_file"
}

remove_retired_targets_from_home() {
  remove_target_file_from_home "$retired_targets_file"
}

show_changed_files() {
  local changes

  changes="$(git -C "$repo_root" status --short)"
  if [[ -z "$changes" ]]; then
    echo "No changed files."
    return 1
  fi

  echo "Changed files:"
  printf '%s\n' "$changes"
}

prompt_commit_and_push() {
  local answer
  local message="${CODING_AGENT_SETUPS_COMMIT_MESSAGE:-Refresh coding agent setup}"

  if [[ ! -t 0 ]]; then
    echo "Skipping commit/push prompt because stdin is not interactive."
    return 0
  fi

  read -r -p "Commit and push these changes? [y/N]: " answer
  case "$(lower "$answer")" in
    y|yes) ;;
    *)
      echo "Leaving changes uncommitted."
      return 0
      ;;
  esac

  git -C "$repo_root" add -A
  if git -C "$repo_root" diff --cached --quiet; then
    echo "No staged changes to commit."
    return 0
  fi

  git -C "$repo_root" commit -m "$message"
  git -C "$repo_root" push
}

finish_publish_review() {
  echo "Running secret check."
  "$repo_root/scripts/check-public-safe.sh"
  if show_changed_files; then
    prompt_commit_and_push
  fi
}

publish_from_home() {
  mkdir -p "$files_dir"
  if [[ "${#shared_paths[@]}" -gt 0 ]]; then
    copy_group "shared files" "$home_dir" "$files_dir" 1 "${shared_paths[@]}"
  fi
  if agent_enabled CODEX; then
    if [[ "${#codex_paths[@]}" -gt 0 ]]; then
      copy_group "Codex" "$home_dir" "$files_dir" 1 "${codex_paths[@]}"
    fi
  fi
  if agent_enabled CLAUDE; then
    if [[ "${#claude_paths[@]}" -gt 0 ]]; then
      copy_group "Claude Code" "$home_dir" "$files_dir" 1 "${claude_paths[@]}"
    fi
  fi
  if agent_enabled OPENCODE; then
    if [[ "${#opencode_paths[@]}" -gt 0 ]]; then
      copy_group "OpenCode" "$home_dir" "$files_dir" 1 "${opencode_paths[@]}"
    fi
  fi
  sanitize_moshi_command_hooks "$files_dir/.claude/settings.json"
  sanitize_moshi_command_hooks "$files_dir/.codex/hooks.json"
  sanitize_opencode_config
  sanitize_codex_config
  prune_non_vendored_targets_from_repo
  cleanup_public_tree
  echo "Refreshed enabled repo files from $home_dir"
  finish_publish_review
}

sync_to_home() {
  local moshi_plugins_file=""
  local claude_moshi_hooks_file=""
  local codex_moshi_hooks_file=""
  local moshi_targets=()

  create_sync_backups
  if shell_commands_enabled; then
    install_coding_agent_shell_commands "$repo_root"
  fi

  if agent_enabled CODEX; then
    codex_moshi_hooks_file="$(make_temp_file)"
    capture_moshi_command_hooks "$home_dir/.codex/hooks.json" "$codex_moshi_hooks_file"
    moshi_targets+=(codex)
  fi
  if agent_enabled CLAUDE; then
    claude_moshi_hooks_file="$(make_temp_file)"
    capture_moshi_command_hooks "$home_dir/.claude/settings.json" "$claude_moshi_hooks_file"
    moshi_targets+=(claude)
  fi
  if agent_enabled OPENCODE; then
    moshi_plugins_file="$(make_temp_file)"
    capture_moshi_opencode_plugins "$config_home/opencode/opencode.json" "$moshi_plugins_file"
    moshi_targets+=(opencode)
  fi

  install_managed_skills
  install_managed_sources
  if [[ "${#shared_paths[@]}" -gt 0 ]]; then
    copy_group "shared files" "$files_dir" "$home_dir" 0 "${shared_paths[@]}"
  fi
  if agent_enabled CODEX; then
    if [[ "${#codex_paths[@]}" -gt 0 ]]; then
      copy_group "Codex" "$files_dir" "$home_dir" 0 "${codex_paths[@]}"
    fi
    restore_moshi_command_hooks "$home_dir/.codex/hooks.json" "$codex_moshi_hooks_file"
    rm -f "$codex_moshi_hooks_file"
  fi
  if agent_enabled CLAUDE; then
    if [[ "${#claude_paths[@]}" -gt 0 ]]; then
      copy_group "Claude Code" "$files_dir" "$home_dir" 0 "${claude_paths[@]}"
    fi
    restore_moshi_command_hooks "$home_dir/.claude/settings.json" "$claude_moshi_hooks_file"
    rm -f "$claude_moshi_hooks_file"
  fi
  if agent_enabled OPENCODE; then
    if [[ "${#opencode_paths[@]}" -gt 0 ]]; then
      copy_group "OpenCode" "$files_dir" "$home_dir" 0 "${opencode_paths[@]}"
    fi
    restore_moshi_opencode_plugins "$config_home/opencode/opencode.json" "$moshi_plugins_file"
    rm -f "$moshi_plugins_file"
    repair_missing_opencode_file_plugins
  fi
  if [[ "${#moshi_targets[@]}" -gt 0 ]]; then
    ensure_moshi_for_targets "${moshi_targets[@]}"
  fi
  remove_caveman_opencode_agents
  remove_retired_targets_from_home
  echo "Synced enabled repo files into $home_dir"
}

require_setup_flags
confirm_sync

case "$mode" in
  publish) publish_from_home ;;
  sync) sync_to_home ;;
esac
