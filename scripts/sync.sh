#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: scripts/sync.sh [sync|publish] [--yes] [-c|--config-only]

  sync               Copy setup files and install skills from this repo into $HOME.
  publish            Refresh repo files from $HOME.
  --yes              Skip confirmation prompts.
  -c, --config-only  Sync checked-in config files only; skip installers/dependencies.

Run scripts/setup.sh first.
USAGE
}

mode=""
assume_yes=0
config_only=0
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
    -c|--config-only)
      config_only=1
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
if [[ "$config_only" == "1" && "$mode" != "sync" ]]; then
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

  if [[ "${config_only:-0}" == "1" ]]; then
    echo "Missing required command: $command_name" >&2
    exit 1
  fi

  echo "Missing required command: $command_name; attempting to install ${packages[*]}."
  install_packages "${packages[@]}" || true

  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "Missing required command after install attempt: $command_name" >&2
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
if [[ "$mode" == "publish" ]]; then
  ensure_cmd git
fi
if [[ "$mode" == "sync" ]]; then
  ensure_cmd tar
fi

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/scripts/local-bin.sh"

files_dir="$repo_root/files"
config_home="${XDG_CONFIG_HOME:-$home_dir/.config}"
setup_dir="${CODING_AGENT_SETUPS_HOME:-$home_dir/.coding-agent-setups}"
legacy_setup_dir="$config_home/coding-agent-setups"
flag_file="${CODING_AGENT_SETUPS_FLAG_FILE:-$setup_dir/sync.env}"
git_cache_dir="$setup_dir/git"
managed_sources_file="$repo_root/sources/managed-sources.tsv"
managed_skills_file="$repo_root/sources/managed-skills.tsv"
managed_targets_file="$repo_root/sources/managed-targets.txt"
retired_targets_file="$repo_root/sources/retired-targets.txt"

migrate_legacy_state() {
  local legacy_flag_file="$legacy_setup_dir/sync.env"

  if [[ -n "${CODING_AGENT_SETUPS_FLAG_FILE:-}" ]]; then
    return 0
  fi
  if [[ "$setup_dir" == "$legacy_setup_dir" ]]; then
    return 0
  fi
  if [[ -f "$flag_file" || ! -f "$legacy_flag_file" ]]; then
    return 0
  fi

  mkdir -p "$setup_dir"
  cp "$legacy_flag_file" "$flag_file"
  chmod 600 "$flag_file"
  echo "Migrated sync selection to $flag_file"
}

generic_paths=()
omp_paths=()

append_omp_path() {
  local candidate="$1"
  local existing

  if [[ "${#omp_paths[@]}" -gt 0 ]]; then
    for existing in "${omp_paths[@]}"; do
      if [[ "$existing" == "$candidate" ]]; then
        return 0
      fi
    done
  fi
  omp_paths+=("$candidate")
}

discover_omp_config_paths() {
  local root="$1"
  local config_dir="$root/.omp/agent"
  local path

  if [[ ! -d "$config_dir" ]]; then
    return 0
  fi
  while IFS= read -r -d '' path; do
    append_omp_path "${path#"$root/"}"
  done < <(
    find "$config_dir" \
      \( -type d \( -name sessions -o -name terminal-sessions -o -name cache -o -path "$config_dir/predict" \) -prune \) -o \
      \( -type f \( -name '*.md' -o -name '*.json' -o -name '*.jsonl' -o -name '*.yaml' -o -name '*.yml' \) \
        ! -name auth.json ! -name .credentials.json ! -name history.jsonl -print0 \)
  )
}

refresh_omp_paths() {
  local src_root="$1"
  local dst_root="$2"

  omp_paths=()
  discover_omp_config_paths "$src_root"
  discover_omp_config_paths "$dst_root"
  # Discovery skips code; repo-owned extensions are listed explicitly.
  append_omp_path ".omp/agent/extensions/impeccable.ts"
}

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
  "--exclude=.caveman-active"
  "--exclude=*.sqlite"
  "--exclude=*.sqlite-*"
  "--exclude=*.db"
  "--exclude=*.db-*"
  "--exclude=*.bak.*"
  "--exclude=*.lock"
)

backup_excludes=(
  "--exclude=.coding-agent-setups-backups"
  "--exclude=.coding-agent-setups-backups/*"
  "--exclude=.git"
  "--exclude=.git/*"
  "--exclude=.bun"
  "--exclude=.bun/*"
  "--exclude=*/.bun"
  "--exclude=*/.bun/*"
  "--exclude=.npm"
  "--exclude=.npm/*"
  "--exclude=*/.npm"
  "--exclude=*/.npm/*"
  "--exclude=.pnpm-store"
  "--exclude=.pnpm-store/*"
  "--exclude=*/.pnpm-store"
  "--exclude=*/.pnpm-store/*"
  "--exclude=.yarn/cache"
  "--exclude=.yarn/cache/*"
  "--exclude=*/.yarn/cache"
  "--exclude=*/.yarn/cache/*"
  "--exclude=node_modules"
  "--exclude=node_modules/*"
  "--exclude=*/node_modules"
  "--exclude=*/node_modules/*"
  "--exclude=.venv"
  "--exclude=.venv/*"
  "--exclude=*/.venv"
  "--exclude=*/.venv/*"
  "--exclude=venv"
  "--exclude=venv/*"
  "--exclude=*/venv"
  "--exclude=*/venv/*"
  "--exclude=__pycache__"
  "--exclude=__pycache__/*"
  "--exclude=*/__pycache__"
  "--exclude=*/__pycache__/*"
  "--exclude=*.pyc"
  "--exclude=.cache"
  "--exclude=.cache/*"
  "--exclude=*/.cache"
  "--exclude=*/.cache/*"
  "--exclude=.tmp"
  "--exclude=.tmp/*"
  "--exclude=*/.tmp"
  "--exclude=*/.tmp/*"
  "--exclude=tmp"
  "--exclude=tmp/*"
  "--exclude=*/tmp"
  "--exclude=*/tmp/*"
  "--exclude=cache"
  "--exclude=cache/*"
  "--exclude=*/cache"
  "--exclude=*/cache/*"
  "--exclude=logs"
  "--exclude=logs/*"
  "--exclude=*/logs"
  "--exclude=*/logs/*"
  "--exclude=packages"
  "--exclude=packages/*"
  "--exclude=*/packages"
  "--exclude=*/packages/*"
  "--exclude=shell_snapshots"
  "--exclude=shell_snapshots/*"
  "--exclude=*/shell_snapshots"
  "--exclude=*/shell_snapshots/*"
  "--exclude=history.jsonl"
  "--exclude=*/history.jsonl"
  "--exclude=sessions"
  "--exclude=sessions/*"
  "--exclude=*/sessions"
  "--exclude=*/sessions/*"
  "--exclude=projects"
  "--exclude=projects/*"
  "--exclude=*/projects"
  "--exclude=*/projects/*"
  "--exclude=telemetry"
  "--exclude=telemetry/*"
  "--exclude=*/telemetry"
  "--exclude=*/telemetry/*"
  "--exclude=file-history"
  "--exclude=file-history/*"
  "--exclude=*/file-history"
  "--exclude=*/file-history/*"
  "--exclude=goals"
  "--exclude=goals/*"
  "--exclude=*/goals"
  "--exclude=*/goals/*"
  "--exclude=*.sqlite"
  "--exclude=*.sqlite-*"
  "--exclude=*.db"
  "--exclude=*.db-*"
)

read_flag() {
  local key="$1"
  if [[ -f "$flag_file" ]]; then
    awk -F= -v key="$key" '$1 == key { sub(/^[^=]*=/, ""); print; exit }' "$flag_file"
  fi
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
Setup has not been completed:
  $flag_file

Run scripts/setup.sh first to configure this machine.
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

confirm_publish() {
  local answer
  if [[ "$assume_yes" == "1" ]]; then
    return 0
  fi
  echo "Publish action"
  echo "Direction: $home_dir -> repo files"
  echo "Stale files may be deleted inside $files_dir."
  echo "Secret check runs after copying."
  echo "Changed files are listed before the commit/push prompt."
  read -r -p "Proceed? [y/N]: " answer
  case "$(lower "$answer")" in
    y|yes) ;;
    *)
      echo "Cancelled."
      exit 1
      ;;
  esac
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
  if shell_commands_enabled; then
    printf '%s\n' "$home_dir/.local/bin"
  fi
  printf '%s\n' \
    "$home_dir/.agents" \
    "$home_dir/.pi/agent" \
    "$home_dir/.omp/agent"
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
  tar -czf "$archive" "${backup_excludes[@]}" -C "$root" .
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

install_npx_skills() {
  local source="$1"
  local allowed_agents="$2"
  shift 2
  local skills=("$@")
  local agent_args=()
  local skill_args=()
  local skill

  if [[ "${#skills[@]}" -eq 0 ]]; then
    return 0
  fi

  if csv_contains "$allowed_agents" codex; then
    agent_args+=(-a codex)
  fi
  if csv_contains "$allowed_agents" opencode; then
    agent_args+=(-a opencode)
  fi
  if [[ "${#agent_args[@]}" -eq 0 ]]; then
    return 0
  fi

  for skill in "${skills[@]}"; do
    skill_args+=(-s "$skill")
  done

  echo "Installing skills via npx skills: $source@${skills[*]}"
  npm_config_yes=true npx --yes --package=skills@latest -- skills add "$source" -g --copy -y "${agent_args[@]}" "${skill_args[@]}"
}

install_impeccable() {

  echo "Installing Impeccable into shared agent skills"
  npx -y impeccable@latest install \
    --providers=codex \
    --scope=global \
    --no-hooks \
    --force \
    --yes
}

install_managed_skills() {
  local installer source skill allowed_agents notes
  local npx_source=""
  local npx_allowed_agents=""
  local npx_skills=()

  if [[ ! -f "$managed_skills_file" ]]; then
    return 0
  fi
  if [[ "${CODING_AGENT_SETUPS_SKIP_MANAGED_SOURCES:-0}" == "1" ]]; then
    echo "Skipping managed upstream skills."
    return 0
  fi

  flush_npx_skills() {
    if [[ "${#npx_skills[@]}" -eq 0 ]]; then
      return 0
    fi

    if ! install_npx_skills "$npx_source" "$npx_allowed_agents" "${npx_skills[@]}"; then
      echo "Managed skill install failed; continuing: $npx_source@${npx_skills[*]}" >&2
    fi

    npx_source=""
    npx_allowed_agents=""
    npx_skills=()
  }

  while IFS=$'\t' read -r installer source skill allowed_agents notes <&3; do
    [[ -z "${installer:-}" || "$installer" == \#* ]] && continue
    case "$installer" in
      npx-skills)
        if [[ "${#npx_skills[@]}" -eq 0 ]]; then
          npx_source="$source"
          npx_allowed_agents="$allowed_agents"
        elif [[ "$source" != "$npx_source" || "$allowed_agents" != "$npx_allowed_agents" ]]; then
          flush_npx_skills
          npx_source="$source"
          npx_allowed_agents="$allowed_agents"
        fi
        npx_skills+=("$skill")
        ;;
      impeccable)
        flush_npx_skills
        if ! install_impeccable; then
          echo "Impeccable install failed; skipping and keeping any existing install." >&2
        fi
        ;;
      *)
        flush_npx_skills
        echo "Unknown managed skill installer: $installer" >&2
        exit 1
        ;;
    esac
  done 3< "$managed_skills_file"

  flush_npx_skills
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
  refresh_omp_paths "$home_dir" "$files_dir"
  mkdir -p "$files_dir"
  if [[ "${#generic_paths[@]}" -gt 0 ]]; then
    copy_group "Generic / shared" "$home_dir" "$files_dir" 1 "${generic_paths[@]}"
  fi
  if [[ "${#omp_paths[@]}" -gt 0 ]]; then
    copy_group "OMP" "$home_dir" "$files_dir" 1 "${omp_paths[@]}"
  fi
  prune_non_vendored_targets_from_repo
  cleanup_public_tree
  echo "Refreshed repo files from $home_dir"
  finish_publish_review
}

sync_to_home() {
  if [[ "$config_only" != "1" ]]; then
    ensure_cmd git
    ensure_cmd npx
    ensure_cmd patch
    require_sha1
  fi

  create_sync_backups
  if [[ "$config_only" != "1" ]]; then
    if shell_commands_enabled; then
      install_coding_agent_shell_commands "$repo_root"
    fi
    install_managed_skills
    install_managed_sources
  fi
  refresh_omp_paths "$files_dir" "$home_dir"
  if [[ "${#generic_paths[@]}" -gt 0 ]]; then
    copy_group "Generic / shared" "$files_dir" "$home_dir" 0 "${generic_paths[@]}"
  fi
  if [[ "${#omp_paths[@]}" -gt 0 ]]; then
    copy_group "OMP" "$files_dir" "$home_dir" 0 "${omp_paths[@]}"
  fi
  remove_retired_targets_from_home
  echo "Synced repo files into $home_dir"
}

migrate_legacy_state
require_setup_flags
if [[ "$mode" == "publish" ]]; then
  confirm_publish
fi
case "$mode" in
  publish) publish_from_home ;;
  sync) sync_to_home ;;
esac
