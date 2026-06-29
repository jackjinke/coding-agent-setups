#!/usr/bin/env bash
set -euo pipefail

home_dir="${HOME:?HOME is not set}"
config_home="${XDG_CONFIG_HOME:-$home_dir/.config}"
repo_url="${CODING_AGENT_SETUPS_REPO_URL:-https://github.com/jackjinke/coding-agent-setups}"
repo_dir="${CODING_AGENT_SETUPS_REPO:-$home_dir/Projects/coding-agent-setups}"
run_sync=0

usage() {
  cat <<'USAGE'
Usage: scripts/setup.sh [--sync] [--repo PATH]

Runs interactive local setup. When this script is downloaded and run outside the
repo, it first clones or updates the repo, then runs the repo-local setup.

Options:
  --sync       Run sync download after setup.
  --repo PATH  Checkout path. Defaults to ~/Projects/coding-agent-setups.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --sync)
      run_sync=1
      ;;
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

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
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
  if [[ "$run_sync" == "1" ]]; then
    exec bash "$repo_dir/scripts/setup.sh" --sync
  fi
  exec bash "$repo_dir/scripts/setup.sh"
fi

setup_dir="$config_home/coding-agent-setups"
flag_file="${CODING_AGENT_SETUPS_FLAG_FILE:-$setup_dir/sync.env}"
opencode_env="$home_dir/.config/opencode/.env"

lower() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]'
}

make_temp_file() {
  local tmp_base="${TMPDIR:-/tmp}"
  mktemp "$tmp_base/coding-agent-setups.XXXXXX"
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
    echo
    value="${value:-$current}"
  else
    while [[ -z "${value:-}" ]]; do
      read -r -s -p "$prompt: " value
      echo
    done
  fi
  printf '%s' "$value"
}

set_env_var() {
  local file="$1"
  local key="$2"
  local value="$3"
  local tmp

  mkdir -p "$(dirname "$file")"
  touch "$file"
  chmod 600 "$file"
  tmp="$(make_temp_file)"
  awk -v key="$key" -v value="$value" '
    BEGIN { done = 0 }
    $0 ~ "^" key "=" {
      print key "=" value
      done = 1
      next
    }
    { print }
    END {
      if (done == 0) {
        print key "=" value
      }
    }
  ' "$file" > "$tmp"
  mv "$tmp" "$file"
  chmod 600 "$file"
}

write_flags() {
  local codex="$1"
  local claude="$2"
  local opencode="$3"
  local tmp

  mkdir -p "$setup_dir"
  tmp="$(make_temp_file)"
  cat > "$tmp" <<EOF
# Generated by coding-agent-setups/scripts/setup.sh.
# This file is machine-local and controls what scripts/sync.sh copies.
SYNC_CODEX=$codex
SYNC_CLAUDE=$claude
SYNC_OPENCODE=$opencode
EOF
  mv "$tmp" "$flag_file"
  chmod 600 "$flag_file"
}

echo "Shared agent files are installed by sync download."

sync_codex="$(prompt_yes_no "Sync Codex setup on this machine?" "$(existing_yes_no SYNC_CODEX y)")"
sync_claude="$(prompt_yes_no "Sync Claude Code setup on this machine?" "$(existing_yes_no SYNC_CLAUDE y)")"
sync_opencode="$(prompt_yes_no "Sync OpenCode setup on this machine?" "$(existing_yes_no SYNC_OPENCODE y)")"

if [[ "$sync_opencode" == "1" ]]; then
  echo "Configuring local OpenCode environment."
  base_url="$(prompt_value "$opencode_env" OPENCODE_LITELLM_BASE_URL "LiteLLM base URL" "http://localhost:4000/v1")"
  api_key="$(prompt_secret "$opencode_env" OPENCODE_LITELLM_API_KEY "LiteLLM API key")"

  set_env_var "$opencode_env" OPENCODE_LITELLM_BASE_URL "$base_url"
  set_env_var "$opencode_env" OPENCODE_LITELLM_API_KEY "$api_key"
  set_env_var "$opencode_env" OPENCODE_ENABLE_EXA "1"
  set_env_var "$opencode_env" OPENCODE_EXPERIMENTAL_BACKGROUND_SUBAGENTS "1"
fi

write_flags "$sync_codex" "$sync_claude" "$sync_opencode"
echo "Wrote sync selection to $flag_file"

echo "Setup complete."
if [[ "$run_sync" == "0" && "${CODING_AGENT_SETUPS_SUPPRESS_NEXT_STEP:-0}" != "1" ]]; then
  echo "Run this next to install dependencies and apply enabled setup files:"
  echo "  bash \"$repo_root/scripts/coding-agent-setups.sh\" sync download"
fi
echo "OAuth files are not synced; run each enabled agent's login flow on this machine."

if [[ "$run_sync" == "1" ]]; then
  bash "$repo_root/scripts/coding-agent-setups.sh" sync download --yes
fi
