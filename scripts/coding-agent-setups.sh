#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
home_dir="${HOME:?HOME is not set}"
config_home="${XDG_CONFIG_HOME:-$home_dir/.config}"
setup_dir="$config_home/coding-agent-setups"
backup_dir="$setup_dir/backups"

usage() {
  cat <<'USAGE'
Usage: scripts/coding-agent-setups.sh <command> [args]

Commands:
  setup             Run interactive first-time setup.
  sync <args>       Run sync. Example: sync download, sync upload.
  restore           Restore a previous download backup.

Existing scripts/setup.sh and scripts/sync.sh remain available, but this is the
preferred entry point.
USAGE
}

lower() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]'
}

make_temp_file() {
  local tmp_base="${TMPDIR:-/tmp}"
  mktemp "$tmp_base/coding-agent-setups.XXXXXX"
}

backup_roots() {
  printf '%s\n' \
    "$home_dir/.agents" \
    "$home_dir/.codex" \
    "$home_dir/.claude" \
    "$home_dir/.opencode" \
    "$home_dir/.local/bin" \
    "$config_home/opencode"
}

display_path() {
  local path="$1"
  case "$path" in
    "$home_dir") printf '~' ;;
    "$home_dir"/*) printf '~/%s' "${path#"$home_dir"/}" ;;
    *) printf '%s' "$path" ;;
  esac
}

archive_for() {
  local root="$1"
  local version="$2"
  printf '%s/%s/%s.tar.gz' "$backup_dir" "$version" "$(backup_name_for_root "$root")"
}

backup_name_for_root() {
  local root="$1"
  printf '%s' "$root" | sed 's#^/##; s#[^A-Za-z0-9._-]#_#g'
}

list_restore_versions() {
  local version_dir

  if [[ ! -d "$backup_dir" ]]; then
    return 0
  fi

  for version_dir in "$backup_dir"/*; do
    [[ -d "$version_dir" ]] || continue
    basename "$version_dir"
  done | sort -r | head -n 3
}

folders_for_version() {
  local version="$1"
  local root archive
  local folders=()
  local i

  while IFS= read -r root; do
    archive="$(archive_for "$root" "$version")"
    if [[ -f "$archive" ]]; then
      folders+=("$(display_path "$root")")
    fi
  done < <(backup_roots)

  printf '%s' "${folders[0]:-}"
  for ((i = 1; i < ${#folders[@]}; i++)); do
    printf ', %s' "${folders[$i]}"
  done
}

format_backup_version_time() {
  local version="$1"
  local year month day hour minute second

  case "$version" in
    [0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]T[0-9][0-9][0-9][0-9][0-9][0-9]*)
      year="${version:0:4}"
      month="${version:4:2}"
      day="${version:6:2}"
      hour="${version:9:2}"
      minute="${version:11:2}"
      second="${version:13:2}"
      printf '%s-%s-%s %s:%s:%s UTC' "$year" "$month" "$day" "$hour" "$minute" "$second"
      ;;
    *)
      printf 'unknown time'
      ;;
  esac
}

choose_restore_version() {
  local versions_file="$1"
  local version_count="$2"
  local answer
  local index

  while true; do
    read -r -p "Restore which version? [1-$version_count]: " answer
    case "$answer" in
      ''|*[!0-9]*)
        echo "Please enter a number." >&2
        ;;
      *)
        index=$((10#$answer - 1))
        if (( index >= 0 && index < version_count )); then
          sed -n "$((index + 1))p" "$versions_file"
          return 0
        fi
        echo "Please choose a number from 1 to $version_count." >&2
        ;;
    esac
  done
}

restore_folder() {
  local root="$1"
  local version="$2"
  local archive
  local entry

  archive="$(archive_for "$root" "$version")"
  [[ -f "$archive" ]] || return 0

  if [[ -e "$root" && ! -d "$root" ]]; then
    echo "Cannot restore over non-directory: $root" >&2
    return 1
  fi

  mkdir -p "$root"
  for entry in "$root"/.[!.]* "$root"/..?* "$root"/*; do
    [[ -e "$entry" || -L "$entry" ]] || continue
    rm -rf "$entry"
  done
  tar -xzf "$archive" -C "$root"
  echo "Restored $(display_path "$root")"
}

restore_backups() {
  local versions_file version_count
  local i version selected answer root

  versions_file="$(make_temp_file)"
  list_restore_versions > "$versions_file"
  version_count="$(wc -l < "$versions_file" | tr -d '[:space:]')"
  if [[ "$version_count" == "0" ]]; then
    echo "No backups found."
    rm -f "$versions_file"
    return 1
  fi

  echo "Available restore versions:"
  i=1
  while IFS= read -r version; do
    printf '  %d. %s [%s] (%s)\n' \
      "$i" \
      "$(format_backup_version_time "$version")" \
      "$version" \
      "$(folders_for_version "$version")"
    i=$((i + 1))
  done < "$versions_file"

  selected="$(choose_restore_version "$versions_file" "$version_count")"
  echo "Selected: $selected"
  echo "Folders: $(folders_for_version "$selected")"
  read -r -p "Restore this version? Current files in those folders will be replaced. [y/N]: " answer
  case "$(lower "$answer")" in
    y|yes) ;;
    *)
      echo "Cancelled."
      rm -f "$versions_file"
      return 1
      ;;
  esac
  rm -f "$versions_file"

  while IFS= read -r root; do
    restore_folder "$root" "$selected"
  done < <(backup_roots)

  echo "Restore complete."
}

if [[ $# -lt 1 ]]; then
  usage
  exit 2
fi

command="$1"
shift

case "$command" in
  setup)
    exec "$script_dir/setup.sh" "$@"
    ;;
  sync)
    exec "$script_dir/sync.sh" "$@"
    ;;
  restore)
    if [[ $# -gt 0 ]]; then
      usage
      exit 2
    fi
    restore_backups
    ;;
  -h|--help|help)
    usage
    ;;
  *)
    usage
    exit 2
    ;;
esac
