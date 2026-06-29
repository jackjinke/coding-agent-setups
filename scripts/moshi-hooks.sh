#!/usr/bin/env bash

moshi_make_temp_file() {
  local tmp_base="${TMPDIR:-/tmp}"
  mktemp "$tmp_base/coding-agent-setups-moshi.XXXXXX"
}

moshi_platform() {
  uname -s
}

moshi_configure_path() {
  export PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:/opt/local/bin:$PATH"
}

moshi_missing() {
  ! command -v moshi-hook >/dev/null 2>&1 || ! command -v moshi >/dev/null 2>&1
}

install_moshi_hook() {
  case "$(moshi_platform)" in
    Darwin)
      if ! command -v brew >/dev/null 2>&1; then
        echo "Missing Homebrew; install Homebrew first, then rerun sync." >&2
        return 1
      fi
      echo "Installing Moshi hook with Homebrew."
      brew tap rjyo/moshi
      brew trust rjyo/moshi
      brew install moshi-hook
      ;;
    Linux)
      if ! command -v curl >/dev/null 2>&1; then
        if declare -F ensure_cmd >/dev/null 2>&1; then
          ensure_cmd curl
        else
          echo "Missing curl; install curl first, then rerun sync." >&2
          return 1
        fi
      fi
      echo "Installing Moshi hook with the official installer."
      curl -fsSL https://getmoshi.app/install.sh | sh
      ;;
    *)
      echo "Unsupported platform for automatic Moshi install: $(moshi_platform)" >&2
      return 1
      ;;
  esac
}

ensure_moshi_installed() {
  moshi_configure_path

  if moshi_missing; then
    install_moshi_hook
    moshi_configure_path
  fi

  if moshi_missing; then
    echo "Moshi install did not expose both moshi and moshi-hook on PATH." >&2
    return 1
  fi
}

moshi_is_paired() {
  local status

  status="$(moshi-hook status --json 2>/dev/null || true)"
  printf '%s' "$status" | jq -e '.paired == true' >/dev/null 2>&1
}

pair_moshi_if_needed() {
  local token="${MOSHI_PAIRING_TOKEN:-}"

  if moshi_is_paired; then
    return 0
  fi

  echo "Moshi is not paired on this machine."
  if [[ -z "$token" && -t 0 ]]; then
    read -r -s -p "Moshi pairing token: " token
    echo
  fi

  if [[ -z "$token" ]]; then
    echo "Skipping Moshi pairing; set MOSHI_PAIRING_TOKEN or rerun sync interactively." >&2
    return 1
  fi

  case "$(moshi_platform)" in
    Linux) moshi-hook pair --store file --token "$token" ;;
    *) moshi-hook pair --token "$token" ;;
  esac
}

install_moshi_agent_hooks() {
  local target

  for target in "$@"; do
    moshi-hook install --target "$target"
  done
}

write_moshi_systemd_service() {
  local service_dir="$HOME/.config/systemd/user"
  local service_file="$service_dir/moshi.service"
  local moshi_hook_path

  moshi_hook_path="$(command -v moshi-hook)"
  mkdir -p "$service_dir"
  cat > "$service_file" <<EOF
[Unit]
Description=Moshi Hook Daemon
Documentation=https://getmoshi.app/docs/hooks
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=$moshi_hook_path serve
Restart=always
RestartSec=5
Environment=XDG_RUNTIME_DIR=%t
Environment=PATH=$HOME/.local/bin:/usr/local/bin:/usr/bin:/bin

[Install]
WantedBy=default.target
EOF
}

start_moshi_background_daemon() {
  local log_dir="$HOME/.local/state/moshi"
  local moshi_hook_path

  moshi_hook_path="$(command -v moshi-hook)"
  mkdir -p "$log_dir"
  if command -v pgrep >/dev/null 2>&1 && pgrep -f "$moshi_hook_path serve" >/dev/null 2>&1; then
    return 0
  fi
  nohup "$moshi_hook_path" serve >> "$log_dir/hook.log" 2>&1 &
}

ensure_moshi_daemon_running() {
  case "$(moshi_platform)" in
    Darwin)
      if command -v brew >/dev/null 2>&1; then
        brew services start moshi-hook
      else
        start_moshi_background_daemon
      fi
      ;;
    Linux)
      if command -v systemctl >/dev/null 2>&1 && systemctl --user show-environment >/dev/null 2>&1; then
        write_moshi_systemd_service
        systemctl --user daemon-reload
        systemctl --user enable --now moshi.service
      else
        echo "systemd --user is unavailable; starting Moshi for this login session only." >&2
        start_moshi_background_daemon
      fi
      ;;
    *)
      start_moshi_background_daemon
      ;;
  esac
}

ensure_moshi_for_targets() {
  if [[ $# -eq 0 ]]; then
    return 0
  fi

  ensure_moshi_installed
  if pair_moshi_if_needed; then
    install_moshi_agent_hooks "$@"
    ensure_moshi_daemon_running
  fi
}

sanitize_moshi_opencode_plugins() {
  local config="$1"
  local tmp

  if [[ ! -f "$config" ]]; then
    return 0
  fi

  tmp="$(moshi_make_temp_file)"
  jq '
    def is_moshi_plugin: tostring | ascii_downcase | contains("moshi");
    .plugin |= (
      if type == "array" then
        map(select(is_moshi_plugin | not))
      else
        .
      end
    )
  ' "$config" > "$tmp"
  mv "$tmp" "$config"
}

capture_moshi_opencode_plugins() {
  local config="$1"
  local output="$2"

  if [[ ! -f "$config" ]]; then
    printf '[]\n' > "$output"
    return 0
  fi

  if ! jq '[.plugin[]? | select(tostring | ascii_downcase | contains("moshi"))]' "$config" > "$output"; then
    printf '[]\n' > "$output"
  fi
}

restore_moshi_opencode_plugins() {
  local config="$1"
  local saved_plugins="$2"
  local tmp

  if [[ ! -f "$config" || ! -f "$saved_plugins" ]]; then
    return 0
  fi

  tmp="$(moshi_make_temp_file)"
  jq --slurpfile moshi "$saved_plugins" '
    def is_moshi_plugin: tostring | ascii_downcase | contains("moshi");
    .plugin = (
      (
        if (.plugin | type) == "array" then
          .plugin
        else
          []
        end
        | map(select(is_moshi_plugin | not))
      )
      + ($moshi[0] // [])
    )
  ' "$config" > "$tmp"
  mv "$tmp" "$config"
}

sanitize_moshi_command_hooks() {
  local config="$1"
  local tmp

  if [[ ! -f "$config" ]]; then
    return 0
  fi

  tmp="$(moshi_make_temp_file)"
  jq '
    def is_moshi_command: ((.command? // "") | tostring | ascii_downcase | contains("moshi"));
    def strip_moshi_hook_groups:
      with_entries(
        .value |= (
          if type == "array" then
            map(
              if type == "object" and ((.hooks? | type) == "array") then
                .hooks |= map(select(is_moshi_command | not))
              else
                .
              end
              | select(((.hooks? | type) != "array") or ((.hooks | length) > 0))
            )
          else
            .
          end
        )
      )
      | with_entries(select(((.value | type) != "array") or ((.value | length) > 0)));

    if ((.hooks? | type) == "object") then
      .hooks |= strip_moshi_hook_groups
      | if ((.hooks | length) == 0) then del(.hooks) else . end
    else
      .
    end
  ' "$config" > "$tmp"
  mv "$tmp" "$config"
}

capture_moshi_command_hooks() {
  local config="$1"
  local output="$2"

  if [[ ! -f "$config" ]]; then
    printf '{}\n' > "$output"
    return 0
  fi

  if ! jq '
    def is_moshi_command: ((.command? // "") | tostring | ascii_downcase | contains("moshi"));
    (.hooks // {})
    | if type == "object" then
        with_entries(
          .value |= (
            if type == "array" then
              map(
                select(type == "object" and ((.hooks? | type) == "array"))
                | .hooks |= map(select(is_moshi_command))
                | select((.hooks | length) > 0)
              )
            else
              []
            end
          )
        )
        | with_entries(select((.value | length) > 0))
      else
        {}
      end
  ' "$config" > "$output"; then
    printf '{}\n' > "$output"
  fi
}

restore_moshi_command_hooks() {
  local config="$1"
  local saved_hooks="$2"
  local tmp

  if [[ ! -f "$saved_hooks" ]]; then
    return 0
  fi
  if [[ ! -f "$config" ]] && ! jq -e 'type == "object" and length > 0' "$saved_hooks" >/dev/null; then
    return 0
  fi

  mkdir -p "$(dirname "$config")"
  tmp="$(moshi_make_temp_file)"
  if [[ -f "$config" ]]; then
    jq --slurpfile moshi "$saved_hooks" '
      def is_moshi_command: ((.command? // "") | tostring | ascii_downcase | contains("moshi"));
      def strip_moshi_hook_groups:
        with_entries(
          .value |= (
            if type == "array" then
              map(
                if type == "object" and ((.hooks? | type) == "array") then
                  .hooks |= map(select(is_moshi_command | not))
                else
                  .
                end
                | select(((.hooks? | type) != "array") or ((.hooks | length) > 0))
              )
            else
              .
            end
          )
        )
        | with_entries(select(((.value | type) != "array") or ((.value | length) > 0)));
      def strip_moshi:
        if ((.hooks? | type) == "object") then
          .hooks |= strip_moshi_hook_groups
          | if ((.hooks | length) == 0) then del(.hooks) else . end
        else
          .
        end;
      def merge_moshi($saved):
        .hooks = (
          (.hooks // {})
          | reduce (($saved // {}) | keys_unsorted[]) as $key (.;
              .[$key] = ((.[$key] // []) + ($saved[$key] // []))
            )
        )
        | if ((.hooks | length) == 0) then del(.hooks) else . end;

      strip_moshi | merge_moshi($moshi[0] // {})
    ' "$config" > "$tmp"
  else
    printf '{}\n' | jq --slurpfile moshi "$saved_hooks" '
      def merge_moshi($saved):
        .hooks = (
          {}
          | reduce (($saved // {}) | keys_unsorted[]) as $key (.;
              .[$key] = ($saved[$key] // [])
            )
        )
        | if ((.hooks | length) == 0) then del(.hooks) else . end;

      merge_moshi($moshi[0] // {})
    ' > "$tmp"
  fi
  mv "$tmp" "$config"
}
