#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
test_dir="$(mktemp -d)"
trap 'rm -rf "$test_dir"' EXIT
mkdir -p "$test_dir/bin"
log_file="$test_dir/commands.log"

cat > "$test_dir/bin/uname" <<'EOF'
#!/usr/bin/env sh
printf 'Linux\n'
EOF

cat > "$test_dir/bin/moshi-hook" <<'EOF'
#!/usr/bin/env sh
printf 'moshi-hook %s\n' "$*" >> "$LOG_FILE"
EOF

cat > "$test_dir/bin/moshi" <<'EOF'
#!/usr/bin/env sh
printf 'moshi %s\n' "$*" >> "$LOG_FILE"
EOF

cat > "$test_dir/bin/curl" <<'EOF'
#!/usr/bin/env sh
printf 'curl %s\n' "$*" >> "$LOG_FILE"
exit 1
EOF

chmod +x "$test_dir/bin/uname" "$test_dir/bin/moshi-hook" "$test_dir/bin/moshi" "$test_dir/bin/curl"
export LOG_FILE="$log_file"
PATH="$test_dir/bin:$PATH"
export PATH

source "$repo_root/scripts/moshi-hooks.sh"
update_moshi_hook

expected="$(printf 'moshi-hook update\nmoshi service install')"
actual="$(cat "$log_file")"
if [[ "$actual" != "$expected" ]]; then
  printf 'Unexpected commands:\n%s\n' "$actual" >&2
  exit 1
fi
