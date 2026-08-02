#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

docker run --rm \
  -v "$repo_root:/repo:ro" \
  bash:3.2 \
  sh -c '
    mkdir -p /tmp/bin /tmp/home/.coding-agent-setups
    printf "#!/bin/sh\nexit 0\n" > /tmp/bin/rsync
    chmod +x /tmp/bin/rsync
    printf "INSTALL_SHELL_COMMANDS=0\n" > /tmp/home/.coding-agent-setups/sync.env
    HOME=/tmp/home PATH=/tmp/bin:$PATH bash /repo/scripts/sync.sh sync --yes --config-only
  '
