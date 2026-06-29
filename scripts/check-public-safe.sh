#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

make_temp_file() {
  local tmp_base="${TMPDIR:-/tmp}"
  mktemp "$tmp_base/coding-agent-setups.XXXXXX"
}

scan_output="$(make_temp_file)"
trap 'rm -f "$scan_output"' EXIT

if grep -rInE \
  '(sk-[A-Za-z0-9_-]{20,}|ghp_[A-Za-z0-9_]{20,}|refresh_token[[:space:]]*[:=][[:space:]]*["'\'']?[A-Za-z0-9._~+/=-]{20,}|access_token[[:space:]]*[:=][[:space:]]*["'\'']?[A-Za-z0-9._~+/=-]{20,}|client_secret[[:space:]]*[:=][[:space:]]*["'\'']?[A-Za-z0-9._~+/=-]{20,}|api[_-]?key[[:space:]]*[:=][[:space:]]*["'\'']?[A-Za-z0-9._~+/=-]{20,}|BEGIN [A-Z ]*PRIVATE KEY)' \
  --exclude-dir=.git \
  --exclude='check-public-safe.sh' \
  . >"$scan_output"; then
  echo "Secret-looking content found:" >&2
  cat "$scan_output" >&2
  exit 1
fi

echo "Secret check passed."
