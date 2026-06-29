#!/usr/bin/env bash

moshi_make_temp_file() {
  local tmp_base="${TMPDIR:-/tmp}"
  mktemp "$tmp_base/coding-agent-setups-moshi.XXXXXX"
}

sanitize_moshi_opencode_plugins() {
  local config="$1"
  local tmp

  if [[ ! -f "$config" ]]; then
    return 0
  fi

  tmp="$(moshi_make_temp_file)"
  jq '
    def is_moshi_plugin: tostring | ascii_downcase | contains("moshi");
    .plugin |= (
      if type == "array" then
        map(select(is_moshi_plugin | not))
      else
        .
      end
    )
  ' "$config" > "$tmp"
  mv "$tmp" "$config"
}

capture_moshi_opencode_plugins() {
  local config="$1"
  local output="$2"

  if [[ ! -f "$config" ]]; then
    printf '[]\n' > "$output"
    return 0
  fi

  if ! jq '[.plugin[]? | select(tostring | ascii_downcase | contains("moshi"))]' "$config" > "$output"; then
    printf '[]\n' > "$output"
  fi
}

restore_moshi_opencode_plugins() {
  local config="$1"
  local saved_plugins="$2"
  local tmp

  if [[ ! -f "$config" || ! -f "$saved_plugins" ]]; then
    return 0
  fi

  tmp="$(moshi_make_temp_file)"
  jq --slurpfile moshi "$saved_plugins" '
    def is_moshi_plugin: tostring | ascii_downcase | contains("moshi");
    .plugin = (
      (
        if (.plugin | type) == "array" then
          .plugin
        else
          []
        end
        | map(select(is_moshi_plugin | not))
      )
      + ($moshi[0] // [])
    )
  ' "$config" > "$tmp"
  mv "$tmp" "$config"
}

sanitize_moshi_command_hooks() {
  local config="$1"
  local tmp

  if [[ ! -f "$config" ]]; then
    return 0
  fi

  tmp="$(moshi_make_temp_file)"
  jq '
    def is_moshi_command: ((.command? // "") | tostring | ascii_downcase | contains("moshi"));
    def strip_moshi_hook_groups:
      with_entries(
        .value |= (
          if type == "array" then
            map(
              if type == "object" and ((.hooks? | type) == "array") then
                .hooks |= map(select(is_moshi_command | not))
              else
                .
              end
              | select(((.hooks? | type) != "array") or ((.hooks | length) > 0))
            )
          else
            .
          end
        )
      )
      | with_entries(select(((.value | type) != "array") or ((.value | length) > 0)));

    if ((.hooks? | type) == "object") then
      .hooks |= strip_moshi_hook_groups
      | if ((.hooks | length) == 0) then del(.hooks) else . end
    else
      .
    end
  ' "$config" > "$tmp"
  mv "$tmp" "$config"
}

capture_moshi_command_hooks() {
  local config="$1"
  local output="$2"

  if [[ ! -f "$config" ]]; then
    printf '{}\n' > "$output"
    return 0
  fi

  if ! jq '
    def is_moshi_command: ((.command? // "") | tostring | ascii_downcase | contains("moshi"));
    (.hooks // {})
    | if type == "object" then
        with_entries(
          .value |= (
            if type == "array" then
              map(
                select(type == "object" and ((.hooks? | type) == "array"))
                | .hooks |= map(select(is_moshi_command))
                | select((.hooks | length) > 0)
              )
            else
              []
            end
          )
        )
        | with_entries(select((.value | length) > 0))
      else
        {}
      end
  ' "$config" > "$output"; then
    printf '{}\n' > "$output"
  fi
}

restore_moshi_command_hooks() {
  local config="$1"
  local saved_hooks="$2"
  local tmp

  if [[ ! -f "$saved_hooks" ]]; then
    return 0
  fi
  if [[ ! -f "$config" ]] && ! jq -e 'type == "object" and length > 0' "$saved_hooks" >/dev/null; then
    return 0
  fi

  mkdir -p "$(dirname "$config")"
  tmp="$(moshi_make_temp_file)"
  if [[ -f "$config" ]]; then
    jq --slurpfile moshi "$saved_hooks" '
      def is_moshi_command: ((.command? // "") | tostring | ascii_downcase | contains("moshi"));
      def strip_moshi_hook_groups:
        with_entries(
          .value |= (
            if type == "array" then
              map(
                if type == "object" and ((.hooks? | type) == "array") then
                  .hooks |= map(select(is_moshi_command | not))
                else
                  .
                end
                | select(((.hooks? | type) != "array") or ((.hooks | length) > 0))
              )
            else
              .
            end
          )
        )
        | with_entries(select(((.value | type) != "array") or ((.value | length) > 0)));
      def strip_moshi:
        if ((.hooks? | type) == "object") then
          .hooks |= strip_moshi_hook_groups
          | if ((.hooks | length) == 0) then del(.hooks) else . end
        else
          .
        end;
      def merge_moshi($saved):
        .hooks = (
          (.hooks // {})
          | reduce (($saved // {}) | keys_unsorted[]) as $key (.;
              .[$key] = ((.[$key] // []) + ($saved[$key] // []))
            )
        )
        | if ((.hooks | length) == 0) then del(.hooks) else . end;

      strip_moshi | merge_moshi($moshi[0] // {})
    ' "$config" > "$tmp"
  else
    printf '{}\n' | jq --slurpfile moshi "$saved_hooks" '
      def merge_moshi($saved):
        .hooks = (
          {}
          | reduce (($saved // {}) | keys_unsorted[]) as $key (.;
              .[$key] = ($saved[$key] // [])
            )
        )
        | if ((.hooks | length) == 0) then del(.hooks) else . end;

      merge_moshi($moshi[0] // {})
    ' > "$tmp"
  fi
  mv "$tmp" "$config"
}
