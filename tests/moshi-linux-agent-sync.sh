#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
test_dir="$(mktemp -d)"
trap 'rm -rf "$test_dir"' EXIT
mkdir -p "$test_dir/bin" "$test_dir/home/.coding-agent-setups"
log_file="$test_dir/commands.log"

for command_name in rsync git npx patch omp; do
  cat > "$test_dir/bin/$command_name" <<'EOF'
#!/usr/bin/env sh
exit 0
EOF
done

cat > "$test_dir/bin/moshi-hook" <<'EOF'
#!/usr/bin/env sh
if [ "$1" = status ]; then
  printf '{"paired":true}\n'
  exit 0
fi
printf 'moshi-hook %s\n' "$*" >> "$LOG_FILE"
EOF

cat > "$test_dir/bin/moshi" <<'EOF'
#!/usr/bin/env sh
printf 'moshi %s\n' "$*" >> "$LOG_FILE"
EOF

cat > "$test_dir/bin/jq" <<'EOF'
#!/usr/bin/env sh
exit 0
EOF

chmod +x "$test_dir/bin/"*
printf 'INSTALL_SHELL_COMMANDS=0\n' > "$test_dir/home/.coding-agent-setups/sync.env"
export LOG_FILE="$log_file"

run_sync() {
  local selection="$1"
  local option="${2:-}"

  : > "$log_file"
  printf '%s\n\n' "$selection" | script -qefc \
    "HOME='$test_dir/home' PATH='$test_dir/bin:$PATH' CODING_AGENT_SETUPS_SKIP_MANAGED_SOURCES=1 bash '$repo_root/scripts/sync.sh' sync $option" \
    /dev/null >/dev/null
}

assert_commands() {
  local expected="$1"
  local actual

  actual="$(cat "$log_file")"
  if [[ "$actual" != "$expected" ]]; then
    printf 'Unexpected commands:\n%s\n' "$actual" >&2
    exit 1
  fi
}

moshi_lifecycle_prefix="$(printf 'moshi-hook update\nmoshi service uninstall\nmoshi service install')"
moshi_lifecycle_suffix="moshi service install"

run_sync 2
assert_commands "$(printf '%s\nmoshi-hook install --target codex\n%s' "$moshi_lifecycle_prefix" "$moshi_lifecycle_suffix")"

run_sync 3
assert_commands "$(printf '%s\nmoshi-hook install --target claude\n%s' "$moshi_lifecycle_prefix" "$moshi_lifecycle_suffix")"

run_sync 4
assert_commands "$(printf '%s\nmoshi-hook install --target opencode\n%s' "$moshi_lifecycle_prefix" "$moshi_lifecycle_suffix")"

run_sync 5
assert_commands "$(printf '%s\nmoshi-hook install --target omp\n%s' "$moshi_lifecycle_prefix" "$moshi_lifecycle_suffix")"

run_sync "2 3"
assert_commands "$(printf '%s\nmoshi-hook install --target codex --target claude\n%s' "$moshi_lifecycle_prefix" "$moshi_lifecycle_suffix")"

run_sync 1
assert_commands ""

run_sync 2 --config-only
assert_commands ""
