#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
home_dir="${HOME:?HOME is not set}"
config_home="${XDG_CONFIG_HOME:-$home_dir/.config}"
backup_dir_name=".coding-agent-setups-backups"

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

backup_roots() {
  printf '%s\n' \
    "$home_dir/.agents" \
    "$home_dir/.codex" \
    "$home_dir/.claude" \
    "$home_dir/.opencode" \
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
  printf '%s/%s/%s.tar.gz' "$root" "$backup_dir_name" "$version"
}

list_restore_versions() {
  local root backup_dir archive version
  declare -A seen=()

  while IFS= read -r root; do
    backup_dir="$root/$backup_dir_name"
    [[ -d "$backup_dir" ]] || continue
    while IFS= read -r archive; do
      version="$(basename "$archive" .tar.gz)"
      seen["$version"]=1
    done < <(find "$backup_dir" -maxdepth 1 -type f -name '*.tar.gz' -print)
  done < <(backup_roots)

  if [[ "${#seen[@]}" -eq 0 ]]; then
    return 0
  fi

  printf '%s\n' "${!seen[@]}" | sort -r | head -n 3
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
  local readable

  if [[ "$version" =~ ^([0-9]{4})([0-9]{2})([0-9]{2})T([0-9]{2})([0-9]{2})([0-9]{2}) ]]; then
    readable="${BASH_REMATCH[1]}-${BASH_REMATCH[2]}-${BASH_REMATCH[3]} ${BASH_REMATCH[4]}:${BASH_REMATCH[5]}:${BASH_REMATCH[6]} UTC"
    if date -d "$readable" '+%Y-%m-%d %H:%M:%S %Z' >/dev/null 2>&1; then
      date -d "$readable" '+%Y-%m-%d %H:%M:%S %Z'
    else
      printf '%s' "$readable"
    fi
  else
    printf 'unknown time'
  fi
}

choose_restore_version() {
  local -n versions_ref="$1"
  local answer
  local index

  while true; do
    read -r -p "Restore which version? [1-${#versions_ref[@]}]: " answer
    case "$answer" in
      ''|*[!0-9]*)
        echo "Please enter a number."
        ;;
      *)
        index=$((answer - 1))
        if (( index >= 0 && index < ${#versions_ref[@]} )); then
          printf '%s' "${versions_ref[$index]}"
          return 0
        fi
        echo "Please choose a number from 1 to ${#versions_ref[@]}."
        ;;
    esac
  done
}

restore_folder() {
  local root="$1"
  local version="$2"
  local archive backup_dir

  archive="$(archive_for "$root" "$version")"
  [[ -f "$archive" ]] || return 0

  if [[ -e "$root" && ! -d "$root" ]]; then
    echo "Cannot restore over non-directory: $root" >&2
    return 1
  fi

  backup_dir="$root/$backup_dir_name"
  mkdir -p "$backup_dir"
  find "$root" -mindepth 1 -maxdepth 1 ! -name "$backup_dir_name" -exec rm -rf {} +
  tar -xzf "$archive" -C "$root"
  echo "Restored $(display_path "$root")"
}

restore_backups() {
  local versions=()
  local i selected answer root

  mapfile -t versions < <(list_restore_versions)
  if [[ "${#versions[@]}" -eq 0 ]]; then
    echo "No backups found."
    return 1
  fi

  echo "Available restore versions:"
  for i in "${!versions[@]}"; do
    printf '  %d. %s [%s] (%s)\n' \
      "$((i + 1))" \
      "$(format_backup_version_time "${versions[$i]}")" \
      "${versions[$i]}" \
      "$(folders_for_version "${versions[$i]}")"
  done

  selected="$(choose_restore_version versions)"
  echo "Selected: $selected"
  echo "Folders: $(folders_for_version "$selected")"
  read -r -p "Restore this version? Current files in those folders will be replaced. [y/N]: " answer
  case "${answer,,}" in
    y|yes) ;;
    *)
      echo "Cancelled."
      return 1
      ;;
  esac

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
