#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
opencode_env="$HOME/.config/opencode/.env"

read_existing_env() {
  local key="$1"
  local file="$2"
  if [[ -f "$file" ]]; then
    awk -F= -v key="$key" '$1 == key { sub(/^[^=]*=/, ""); print; exit }' "$file"
  fi
}

prompt_value() {
  local key="$1"
  local prompt="$2"
  local default_value="${3:-}"
  local current
  current="$(read_existing_env "$key" "$opencode_env")"
  if [[ -n "$current" ]]; then
    default_value="$current"
  fi

  local value
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
  local key="$1"
  local prompt="$2"
  local current
  current="$(read_existing_env "$key" "$opencode_env")"

  local value
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
  tmp="$(mktemp)"
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

echo "Configuring local OpenCode environment."
base_url="$(prompt_value OPENCODE_LITELLM_BASE_URL "LiteLLM base URL" "http://localhost:4000/v1")"
api_key="$(prompt_secret OPENCODE_LITELLM_API_KEY "LiteLLM API key")"

set_env_var "$opencode_env" OPENCODE_LITELLM_BASE_URL "$base_url"
set_env_var "$opencode_env" OPENCODE_LITELLM_API_KEY "$api_key"
set_env_var "$opencode_env" OPENCODE_ENABLE_EXA "1"
set_env_var "$opencode_env" OPENCODE_EXPERIMENTAL_BACKGROUND_SUBAGENTS "1"

bash "$repo_root/scripts/sync.sh" --to-home

echo "Setup complete. OAuth files are not synced; run each agent's login flow on this machine."

