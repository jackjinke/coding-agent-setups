#!/usr/bin/env bash

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
        install_moshi_hook_with_installer
        return
      fi
      echo "Installing Moshi hook with Homebrew."
      brew tap rjyo/moshi
      brew trust rjyo/moshi
      HOMEBREW_NO_ASK=1 brew install moshi-hook
      ;;
    Linux)
      install_moshi_hook_with_installer
      ;;
    *)
      echo "Unsupported platform for automatic Moshi install: $(moshi_platform)" >&2
      return 1
      ;;
  esac
}

install_moshi_hook_with_installer() {
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
}

update_moshi_hook() {
  case "$(moshi_platform)" in
    Darwin)
      if command -v brew >/dev/null 2>&1 && brew list --formula moshi-hook >/dev/null 2>&1; then
        echo "Updating Moshi hook with Homebrew."
        HOMEBREW_NO_ASK=1 brew update
        HOMEBREW_NO_ASK=1 brew upgrade --yes moshi-hook || true
        brew services restart moshi-hook || true
      else
        echo "Updating Moshi hook with the official installer."
        install_moshi_hook_with_installer
      fi
      ;;
    Linux)
      echo "Updating Moshi hook with the official installer."
      install_moshi_hook_with_installer
      restart_moshi_daemon_if_running
      ;;
    *)
      echo "Unsupported platform for automatic Moshi update: $(moshi_platform)" >&2
      return 1
      ;;
  esac
}

ensure_moshi_installed() {
  moshi_configure_path

  if moshi_missing; then
    install_moshi_hook
    moshi_configure_path
  else
    update_moshi_hook
    moshi_configure_path
  fi

  if moshi_missing; then
    echo "Moshi install did not expose both moshi and moshi-hook on PATH." >&2
    return 1
  fi
}

restart_moshi_daemon_if_running() {
  local moshi_hook_path

  if ! command -v moshi-hook >/dev/null 2>&1; then
    return 0
  fi

  moshi_hook_path="$(command -v moshi-hook)"
  case "$(moshi_platform)" in
    Darwin)
      if command -v brew >/dev/null 2>&1 && brew services list >/dev/null 2>&1; then
        brew services restart moshi-hook || true
      fi
      ;;
    Linux)
      if command -v systemctl >/dev/null 2>&1 && systemctl --user show-environment >/dev/null 2>&1; then
        if systemctl --user is-active --quiet moshi.service; then
          systemctl --user restart moshi.service
          return 0
        fi
      fi
      if command -v pkill >/dev/null 2>&1 && command -v pgrep >/dev/null 2>&1; then
        if pgrep -f "$moshi_hook_path serve" >/dev/null 2>&1; then
          pkill -f "$moshi_hook_path serve" || true
          start_moshi_background_daemon
        fi
      fi
      ;;
  esac
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
    ensure_moshi_daemon_running
  fi
}
