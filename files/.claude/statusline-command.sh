#!/usr/bin/env bash
input=$(cat)
cwd=$(echo "$input" | jq -r '.workspace.current_dir // .cwd')

# Context window usage
ctx_used=$(echo "$input" | jq -r '.context_window.used_percentage // empty')

# Subscription rate limits
five_pct=$(echo "$input" | jq -r '.rate_limits.five_hour.used_percentage // empty')

# Build rate limit string
rate_str=""
if [ -n "$five_pct" ]; then
  rate_str="5h limit: $(printf '%.0f' "$five_pct")%"
fi

# Print directory portion (last folder name only, no full path or user@host)
printf "📂 \033[01;34m%s\033[00m" "$(basename "$cwd")"

# Print context usage if available
if [ -n "$ctx_used" ]; then
  printf "\033[00m | \033[0;33mContext: $(printf '%.0f' "$ctx_used")%%\033[00m"
fi

# Print rate limits if available
if [ -n "$rate_str" ]; then
  printf "\033[00m | \033[0;35m%s\033[00m" "$rate_str"
fi
