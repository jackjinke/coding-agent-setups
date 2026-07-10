#!/usr/bin/env bash

coding_agent_bin_dir() {
  printf '%s' "${CODING_AGENT_SETUPS_BIN_DIR:-$HOME/.local/bin}"
}

detect_active_shell() {
  local shell_path shell_name

  if [[ -n "${CODING_AGENT_SETUPS_SHELL:-}" ]]; then
    shell_path="$CODING_AGENT_SETUPS_SHELL"
  elif command -v ps >/dev/null 2>&1 && [[ -n "${PPID:-}" ]]; then
    shell_path="$(ps -p "$PPID" -o comm= 2>/dev/null | awk 'NR == 1 { print $1 }')"
  else
    shell_path=""
  fi

  shell_name="${shell_path##*/}"
  shell_name="${shell_name#-}"
  case "$shell_name" in
    bash|zsh|fish)
      printf '%s' "$shell_name"
      return 0
      ;;
  esac

  shell_path="${SHELL:-}"
  shell_name="${shell_path##*/}"
  shell_name="${shell_name#-}"
  printf '%s' "$shell_name"
}

single_quote() {
  printf "'"
  printf '%s' "$1" | sed "s/'/'\\\\''/g"
  printf "'"
}

shell_startup_file() {
  local shell_name="$1"

  case "$shell_name" in
    zsh)
      printf '%s' "$HOME/.zshrc"
      ;;
    bash)
      case "$(uname -s)" in
        Darwin) printf '%s' "$HOME/.bash_profile" ;;
        *) printf '%s' "$HOME/.bashrc" ;;
      esac
      ;;
    fish)
      printf '%s' "$HOME/.config/fish/conf.d/coding-agent-setups.fish"
      ;;
    *)
      return 1
      ;;
  esac
}

ensure_shell_path_for_local_bins() {
  local bin_dir="$1"
  local shell_name
  local startup_file marker quoted_bin_dir

  shell_name="$(detect_active_shell)"
  echo "Detected shell: ${shell_name:-unknown}"
  startup_file="$(shell_startup_file "$shell_name" 2>/dev/null || true)"
  if [[ -z "$startup_file" ]]; then
    echo "Unsupported shell for automatic PATH setup: ${shell_name:-unknown}" >&2
    echo "Add $bin_dir to PATH to run coding-agent-setups directly." >&2
    return 0
  fi

  mkdir -p "$(dirname "$startup_file")"
  touch "$startup_file"
  marker="# coding-agent-setups PATH"
  if grep -Fq "$marker" "$startup_file"; then
    return 0
  fi

  quoted_bin_dir="$(single_quote "$bin_dir")"
  case "$shell_name" in
    fish)
      cat >> "$startup_file" <<EOF

$marker
set -l coding_agent_setups_bin_dir $quoted_bin_dir
if not contains -- \$coding_agent_setups_bin_dir \$PATH
    set -gx PATH \$coding_agent_setups_bin_dir \$PATH
end
EOF
      ;;
    *)
      cat >> "$startup_file" <<EOF

$marker
coding_agent_setups_bin_dir=$quoted_bin_dir
case ":\$PATH:" in
  *":\$coding_agent_setups_bin_dir:"*) ;;
  *) export PATH="\$coding_agent_setups_bin_dir:\$PATH" ;;
esac
EOF
      ;;
  esac
  echo "Updated $startup_file so $bin_dir is on PATH for new shells."
}

ensure_opencode_env_wrapper() {
  local shell_name startup_file alias_line

  shell_name="$(detect_active_shell)"
  case "$shell_name" in
    bash|zsh) ;;
    *)
      echo "Unsupported shell for automatic OpenCode alias: ${shell_name:-unknown}" >&2
      return 0
      ;;
  esac

  startup_file="$(shell_startup_file "$shell_name")"
  mkdir -p "$(dirname "$startup_file")"
  touch "$startup_file"
  alias_line="alias opencode='\$HOME/.local/bin/omos'"

  if grep -Fxq "$alias_line" "$startup_file"; then
    return 0
  fi

  printf '\n%s\n' "$alias_line" >> "$startup_file"
  echo "Updated $startup_file so opencode launches omos for new shells."
}

install_coding_agent_local_bins() {
  local repo_root="$1"
  local bin_dir
  local repo_root_quoted

  bin_dir="$(coding_agent_bin_dir)"
  repo_root_quoted="$(printf '%q' "$repo_root")"
  mkdir -p "$bin_dir"

  cat > "$bin_dir/coding-agent-setups" <<EOF
#!/usr/bin/env bash
set -euo pipefail

default_repo_dir=$repo_root_quoted
repo_dir="\${CODING_AGENT_SETUPS_REPO:-\$default_repo_dir}"

if [[ ! -d "\$repo_dir/.git" ]]; then
  echo "Missing coding-agent-setups checkout: \$repo_dir" >&2
  echo "Run setup again from the README bootstrap command." >&2
  exit 1
fi

exec bash "\$repo_dir/scripts/coding-agent-setups.sh" "\$@"
EOF
  chmod 755 "$bin_dir/coding-agent-setups"
  rm -f "$bin_dir/coding-agent-sync"

  echo "Installed host commands:"
  echo "  $bin_dir/coding-agent-setups"
}

install_coding_agent_shell_commands() {
  local repo_root="$1"
  local bin_dir

  bin_dir="$(coding_agent_bin_dir)"
  install_coding_agent_local_bins "$repo_root"
  ensure_shell_path_for_local_bins "$bin_dir"
}
