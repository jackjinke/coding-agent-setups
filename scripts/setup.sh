#!/usr/bin/env bash
set -euo pipefail

home_dir="${HOME:?HOME is not set}"
config_home="${XDG_CONFIG_HOME:-$home_dir/.config}"
state_dir="${CODING_AGENT_SETUPS_HOME:-$home_dir/.coding-agent-setups}"
repo_url="${CODING_AGENT_SETUPS_REPO_URL:-https://github.com/jackjinke/coding-agent-setups}"
repo_dir="${CODING_AGENT_SETUPS_REPO:-$state_dir/source}"

usage() {
  cat <<'USAGE'
Usage: scripts/setup.sh [--repo PATH]

Runs interactive local setup. When this script is downloaded and run outside the
repo, it first clones or updates the repo, then runs the repo-local setup.

Options:
  --repo PATH  Checkout path. Defaults to ~/.coding-agent-setups/source.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo)
      if [[ $# -lt 2 ]]; then
        usage
        exit 2
      fi
      repo_dir="$2"
      shift
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

script_source="${BASH_SOURCE[0]:-}"
if [[ -n "$script_source" ]]; then
  script_dir="$(cd "$(dirname "$script_source")" && pwd)"
else
  script_dir="$(pwd)"
fi
repo_root="$(cd "$script_dir/.." && pwd)"

install_git() {
  case "$(uname -s)" in
    Darwin)
      if command -v brew >/dev/null 2>&1; then
        brew install git
      else
        echo "Missing git. Install Xcode Command Line Tools or Homebrew, then rerun setup." >&2
        return 1
      fi
      ;;
    Linux)
      if command -v apt-get >/dev/null 2>&1; then
        sudo apt-get update
        sudo apt-get install -y git
      elif command -v dnf >/dev/null 2>&1; then
        sudo dnf install -y git
      elif command -v yum >/dev/null 2>&1; then
        sudo yum install -y git
      elif command -v pacman >/dev/null 2>&1; then
        sudo pacman -Sy --needed --noconfirm git
      elif command -v zypper >/dev/null 2>&1; then
        sudo zypper install -y git
      else
        echo "Missing git and no supported package manager was found." >&2
        return 1
      fi
      ;;
    *)
      echo "Missing git. Install git, then rerun setup." >&2
      return 1
      ;;
  esac
}

ensure_git() {
  if command -v git >/dev/null 2>&1; then
    return 0
  fi

  echo "Missing git; attempting to install it."
  install_git
  if ! command -v git >/dev/null 2>&1; then
    echo "Missing git after install attempt." >&2
    exit 1
  fi
}

checkout_repo() {
  mkdir -p "$(dirname "$repo_dir")"

  if [[ -d "$repo_dir/.git" ]]; then
    git -C "$repo_dir" pull --ff-only
    return 0
  fi

  if [[ -e "$repo_dir" ]]; then
    echo "Checkout path exists but is not a git repo: $repo_dir" >&2
    exit 1
  fi

  git clone "$repo_url" "$repo_dir"
}

if [[ ! -f "$repo_root/scripts/coding-agent-setups.sh" ]]; then
  ensure_git
  checkout_repo
  exec bash "$repo_dir/scripts/setup.sh"
fi

setup_dir="$state_dir"
legacy_setup_dir="$config_home/coding-agent-setups"
flag_file="${CODING_AGENT_SETUPS_FLAG_FILE:-$setup_dir/sync.env}"
opencode_env="$home_dir/.config/opencode/.env"

source "$repo_root/scripts/local-bin.sh"

lower() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]'
}

make_temp_file() {
  local tmp_base="${TMPDIR:-/tmp}"
  mktemp "$tmp_base/coding-agent-setups.XXXXXX"
}

migrate_legacy_state() {
  local legacy_flag_file="$legacy_setup_dir/sync.env"

  if [[ "${CODING_AGENT_SETUPS_SKIP_LEGACY_MIGRATION:-0}" == "1" ]]; then
    return 0
  fi
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

read_existing_key() {
  local file="$1"
  local key="$2"
  if [[ -f "$file" ]]; then
    awk -F= -v key="$key" '$1 == key { sub(/^[^=]*=/, ""); print; exit }' "$file"
  fi
}

existing_yes_no() {
  local key="$1"
  local fallback="$2"
  local current
  current="$(read_existing_key "$flag_file" "$key")"
  case "$(lower "$current")" in
    1|true|yes|on) printf 'y' ;;
    0|false|no|off) printf 'n' ;;
    *) printf '%s' "$fallback" ;;
  esac
}

prompt_yes_no() {
  local prompt="$1"
  local default_value="$2"
  local suffix answer

  case "$default_value" in
    y) suffix="Y/n" ;;
    n) suffix="y/N" ;;
    *) suffix="y/n" ;;
  esac

  while true; do
    read -r -p "$prompt [$suffix]: " answer
    answer="${answer:-$default_value}"
    case "$(lower "$answer")" in
      y|yes) printf '1'; return 0 ;;
      n|no) printf '0'; return 0 ;;
      *) echo "Please answer yes or no." >&2 ;;
    esac
  done
}

prompt_value() {
  local file="$1"
  local key="$2"
  local prompt="$3"
  local default_value="${4:-}"
  local current value

  current="$(read_existing_key "$file" "$key")"
  if [[ -n "$current" ]]; then
    default_value="$current"
  fi

  if [[ -n "$default_value" ]]; then
    read -r -p "$prompt [$default_value]: " value
    value="${value:-$default_value}"
  else
    while [[ -z "${value:-}" ]]; do
      read -r -p "$prompt: " value
    done
  fi
  printf '%s' "$value"
}

prompt_secret() {
  local file="$1"
  local key="$2"
  local prompt="$3"
  local current value

  current="$(read_existing_key "$file" "$key")"
  if [[ -n "$current" ]]; then
    read -r -s -p "$prompt [keep existing]: " value
    echo >&2
    value="${value:-$current}"
  else
    while [[ -z "${value:-}" ]]; do
      read -r -s -p "$prompt: " value
      echo >&2
    done
  fi
  printf '%s' "$value"
}

set_env_var() {
  local file="$1"
  local key="$2"
  local value="$3"
  local tmp line wrote

  mkdir -p "$(dirname "$file")"
  touch "$file"
  chmod 600 "$file"

  case "$value" in
    *$'\n'*|*$'\r'*)
      echo "Refusing to write multiline value for $key." >&2
      return 1
      ;;
  esac

  tmp="$(make_temp_file)"
  wrote=0
  while IFS= read -r line || [[ -n "$line" ]]; do
    case "$line" in
      "$key="*)
        if [[ "$wrote" == "0" ]]; then
          printf '%s=%s\n' "$key" "$value"
          wrote=1
        fi
        ;;
      *)
        printf '%s\n' "$line"
        ;;
    esac
  done < "$file" > "$tmp"
  if [[ "$wrote" == "0" ]]; then
    printf '%s=%s\n' "$key" "$value" >> "$tmp"
  fi
  mv "$tmp" "$file"
  chmod 600 "$file"
}

write_flags() {
  local shell_commands="$1"
  local tmp

  mkdir -p "$setup_dir"
  tmp="$(make_temp_file)"
  cat > "$tmp" <<EOF
# Generated by coding-agent-setups/scripts/setup.sh.
INSTALL_SHELL_COMMANDS=$shell_commands
EOF
  mv "$tmp" "$flag_file"
  chmod 600 "$flag_file"
}

migrate_legacy_state

detected_shell="$(detect_active_shell)"
install_shell_commands="$(prompt_yes_no "Make coding-agent-setups available in your ${detected_shell:-current} shell?" "$(existing_yes_no INSTALL_SHELL_COMMANDS y)")"
if [[ "$install_shell_commands" == "1" ]]; then
  install_coding_agent_shell_commands "$repo_root"
fi

echo "Configuring local OpenCode environment."
base_url="$(prompt_value "$opencode_env" OPENCODE_OMNIROUTE_BASE_URL "OmniRoute base URL" "http://localhost:20128/v1")"
set_env_var "$opencode_env" OPENCODE_OMNIROUTE_BASE_URL "$base_url"
set_env_var "$opencode_env" OPENCODE_EXPERIMENTAL_BACKGROUND_SUBAGENTS "1"
set_env_var "$opencode_env" OPENCODE_EXPERIMENTAL_CODE_MODE "true"
ensure_opencode_env_wrapper
echo "Run /connect omniroute in OpenCode to store the OmniRoute API key."

write_flags "$install_shell_commands"
echo "Wrote setup state to $flag_file"

echo "Setup complete."
if [[ "${CODING_AGENT_SETUPS_SUPPRESS_NEXT_STEP:-0}" != "1" ]]; then
  echo "Run this next to choose and apply setup files:"
  if [[ "$install_shell_commands" == "1" ]]; then
    echo "  coding-agent-setups sync"
  else
    echo "  bash \"$repo_root/scripts/coding-agent-setups.sh\" sync"
  fi
fi
echo "OAuth files are not synced; run each agent's login flow as needed."
