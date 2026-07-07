#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
omo_script="$repo_root/files/.local/bin/omo"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

fail() {
  printf 'not ok - %s\n' "$1" >&2
  exit 1
}

assert_log_contains() {
  local pattern="$1"
  local log_file="$2"

  if ! grep -Fq -- "$pattern" "$log_file"; then
    printf 'tmux log:\n' >&2
    sed 's/^/  /' "$log_file" >&2 || true
    fail "expected tmux log to contain: $pattern"
  fi
}

assert_log_empty() {
  local log_file="$1"

  if [[ -s "$log_file" ]]; then
    printf 'unexpected log contents:\n' >&2
    sed 's/^/  /' "$log_file" >&2
    fail "expected log to be empty"
  fi
}

mkdir -p "$tmp_dir/bin" "$tmp_dir/parent/child"

cat > "$tmp_dir/bin/tmux" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

printf '%s\n' "tmux $*" >> "${FAKE_TMUX_LOG:?}"

case "${1:-}" in
  has-session)
    shift
    target=""
    while (($#)); do
      case "$1" in
        -t)
          target="$2"
          shift 2
          ;;
        *)
          shift
          ;;
      esac
    done

    session_name="${target#=}"
    for existing_session in ${FAKE_TMUX_EXISTING_SESSIONS:-}; do
      if [[ "$existing_session" == "$session_name" ]]; then
        exit 0
      fi
    done
    printf 'can'\''t find session: %s\n' "$session_name" >&2
    exit 1
    ;;
  display-message)
    shift
    target=""
    format=""
    while (($#)); do
      case "$1" in
        -p)
          shift
          ;;
        -t)
          target="$2"
          shift 2
          ;;
        *)
          format="$1"
          shift
          ;;
      esac
    done

    if [[ "$format" == '#S' ]]; then
      printf '%s\n' "${FAKE_TMUX_CURRENT_SESSION:-}"
      exit 0
    fi

    session_name="${target#=}"
    for existing_session in ${FAKE_TMUX_EXISTING_SESSIONS:-}; do
      if [[ "$existing_session" == "$session_name" ]]; then
        printf '@%s\n' "$session_name"
        exit 0
      fi
    done
    exit 1
    ;;
  new-session)
    session_name="session"
    print_id=0
    while (($#)); do
      case "$1" in
        -s)
          session_name="$2"
          shift 2
          ;;
        -P)
          print_id=1
          shift
          ;;
        *)
          shift
          ;;
      esac
    done
    if [[ "$print_id" == "1" ]]; then
      printf '@%s\n' "$session_name"
    fi
    ;;
  new-window)
    print_id=0
    while (($#)); do
      case "$1" in
        -P)
          print_id=1
          shift
          ;;
        *)
          shift
          ;;
      esac
    done
    if [[ "$print_id" == "1" ]]; then
      printf '%%1\n'
    fi
    ;;
  attach-session|select-window|switch-client)
    ;;
  *)
    printf 'unexpected tmux command: %s\n' "$1" >&2
    exit 64
    ;;
esac
EOF
chmod 755 "$tmp_dir/bin/tmux"

cat > "$tmp_dir/bin/opencode" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "opencode $*" >> "${FAKE_OPENCODE_LOG:?}"
EOF
chmod 755 "$tmp_dir/bin/opencode"

tmux_log="$tmp_dir/tmux.log"
opencode_log="$tmp_dir/opencode.log"
: > "$tmux_log"
: > "$opencode_log"

(
  cd "$tmp_dir/parent/child"
  PATH="$tmp_dir/bin:$PATH" \
    TMUX=/tmp/fake-tmux-client \
    FAKE_TMUX_CURRENT_SESSION=parent \
    FAKE_TMUX_EXISTING_SESSIONS= \
    FAKE_TMUX_LOG="$tmux_log" \
    FAKE_OPENCODE_LOG="$opencode_log" \
    bash "$omo_script" status
)

if [[ -s "$opencode_log" ]]; then
  printf 'opencode log:\n' >&2
  sed 's/^/  /' "$opencode_log" >&2
  fail "omo ran opencode in the current tmux pane instead of creating a child session"
fi

assert_log_contains "has-session -t =child-1" "$tmux_log"
assert_log_contains "new-session" "$tmux_log"
assert_log_contains "-s child-1" "$tmux_log"
assert_log_contains "-n child-1" "$tmux_log"
assert_log_contains "switch-client" "$tmux_log"

: > "$tmux_log"
: > "$opencode_log"

(
  cd "$tmp_dir/parent/child"
  PATH="$tmp_dir/bin:$PATH" \
    TMUX=/tmp/fake-tmux-client \
    FAKE_TMUX_CURRENT_SESSION=parent \
    FAKE_TMUX_EXISTING_SESSIONS=child-1 \
    FAKE_TMUX_LOG="$tmux_log" \
    FAKE_OPENCODE_LOG="$opencode_log" \
    bash "$omo_script" status
)

if [[ -s "$opencode_log" ]]; then
  printf 'opencode log:\n' >&2
  sed 's/^/  /' "$opencode_log" >&2
  fail "omo ran opencode in the current tmux pane instead of creating the next child session"
fi

assert_log_contains "has-session -t =child-1" "$tmux_log"
assert_log_contains "has-session -t =child-2" "$tmux_log"
assert_log_contains "new-session" "$tmux_log"
assert_log_contains "-s child-2" "$tmux_log"
assert_log_contains "-n child-2" "$tmux_log"
assert_log_contains "switch-client" "$tmux_log"

: > "$tmux_log"
: > "$opencode_log"

(
  cd "$tmp_dir/parent/child"
  PATH="$tmp_dir/bin:$PATH" \
    TMUX=/tmp/fake-tmux-client \
    OMO_TMUX_MANAGED=1 \
    FAKE_TMUX_CURRENT_SESSION=child-1 \
    FAKE_TMUX_EXISTING_SESSIONS=child-1 \
    FAKE_TMUX_LOG="$tmux_log" \
    FAKE_OPENCODE_LOG="$opencode_log" \
    bash "$omo_script" status
)

assert_log_empty "$tmux_log"
assert_log_contains "opencode --port" "$opencode_log"

printf 'ok - omo creates numbered tmux sessions by current directory name\n'
