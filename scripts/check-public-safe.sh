#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

make_temp_file() {
  local tmp_base="${TMPDIR:-/tmp}"
  mktemp "$tmp_base/coding-agent-setups.XXXXXX"
}

scan_output="$(make_temp_file)"
scan_raw="$(make_temp_file)"
trap 'rm -f "$scan_output" "$scan_raw"' EXIT

run_grep_scan() {
  local status=0

  grep "$@" >"$scan_raw" || status=$?
  case "$status" in
    0|1) return "$status" ;;
    *)
      echo "Secret scanner failed (grep exited $status); aborting." >&2
      exit "$status"
      ;;
  esac
}

if run_grep_scan -rIinE \
  '(sk-[A-Za-z0-9_-]{20,}|github_pat_[A-Za-z0-9_]{20,}|gh[pousr]_[A-Za-z0-9_]{20,}|BEGIN [A-Z ]*PRIVATE KEY)' \
  --exclude-dir=.git \
  --exclude='check-public-safe.sh' \
  .; then
  while IFS= read -r match; do
    printf '%s\n' "$match" >>"$scan_output"
  done <"$scan_raw"
fi

if run_grep_scan -rIinoE \
  '(refresh[_-]?token|access[_-]?token|client[_-]?secret|api[_-]?key)["'\'']?[[:space:]]*[:=][[:space:]]*["'\'']?([A-Za-z0-9._~+/=-]{20,}|process\.env\.[A-Za-z_][A-Za-z0-9_]*|\{env:[A-Za-z_][A-Za-z0-9_]*\}|\$\{[A-Za-z_][A-Za-z0-9_]*\})["'\'']?' \
  --exclude-dir=.git \
  --exclude='check-public-safe.sh' \
  .; then
  safe_env_assignment='(refresh[_-]?token|access[_-]?token|client[_-]?secret|api[_-]?key)["'\'']?[[:space:]]*[:=][[:space:]]*["'\'']?(process\.env\.OPENCODE_OMNIROUTE_API_KEY|OPENCODE_OMNIROUTE_API_KEY|\{env:OPENCODE_OMNIROUTE_API_KEY\}|\$\{OPENCODE_OMNIROUTE_API_KEY\})["'\'']?$'
  safe_opencode_env_assignment='^\./files/\.config/opencode/opencode\.jsonc:[0-9]+:(refresh[_-]?token|access[_-]?token|client[_-]?secret|api[_-]?key)["'\'']?[[:space:]]*[:=][[:space:]]*["'\'']?\{env:[A-Za-z_][A-Za-z0-9_]*\}["'\'']?$'
  shopt -s nocasematch
  while IFS= read -r match; do
    # safe_env_assignment is $-anchored and start-unanchored, so it matches the
    # trailing assignment even with grep's file:line: prefix on each -o match.
    if [[ "$match" =~ $safe_env_assignment || "$match" =~ $safe_opencode_env_assignment ]]; then
      continue
    fi
    printf '%s\n' "$match" >>"$scan_output"
  done <"$scan_raw"
  shopt -u nocasematch
fi

if [[ -s "$scan_output" ]]; then
  echo "Secret-looking content found:" >&2
  while IFS= read -r match; do
    printf '%s\n' "$match" >&2
  done <"$scan_output"
  exit 1
fi

echo "Secret check passed."
