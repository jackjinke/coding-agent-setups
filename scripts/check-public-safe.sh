#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

bad_paths=(
  "files/.codex/auth.json"
  "files/.codex/history.jsonl"
  "files/.codex/bin/litellm-token"
  "files/.agents/skills/.agents"
  "files/.agents/skills/.roo"
  "files/.claude/.credentials.json"
  "files/.claude/history.jsonl"
  "files/.claude/settings.local.json"
  "files/.config/opencode/.env"
)

failed=0
for path in "${bad_paths[@]}"; do
  if [[ -e "$path" ]]; then
    echo "Forbidden tracked path exists: $path" >&2
    failed=1
  fi
done

if find files -type f \( \
  -name '*.sqlite' -o -name '*.sqlite-shm' -o -name '*.sqlite-wal' -o \
  -name '*.db' -o -name '*.db-shm' -o -name '*.db-wal' -o \
  -name '*.pyc' \
\) | grep -q .; then
  echo "Generated database or bytecode files found under files/." >&2
  failed=1
fi

if grep -rInE \
  '(sk-[A-Za-z0-9_-]{20,}|ghp_[A-Za-z0-9_]{20,}|refresh_token|access_token|client_secret|BEGIN [A-Z ]*PRIVATE KEY)' \
  --exclude-dir=.git \
  --exclude='check-public-safe.sh' \
  . >/tmp/coding-agent-setups-secret-scan.txt; then
  echo "Secret-looking content found:" >&2
  cat /tmp/coding-agent-setups-secret-scan.txt >&2
  failed=1
fi

if [[ "$failed" -ne 0 ]]; then
  exit 1
fi

echo "Public-safe check passed."
