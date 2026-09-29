#!/usr/bin/env bats
# The policy files and the shared Compose file hold exactly the keys of TD
# SS3.7 and the fixed values of TD SS2 (no Docker).
load ../../helpers/common
bats_require_minimum_version 1.5.0

setup() {
  D="$AIDC_SOURCE_ROOT/.devcontainer"
}

# toml_keys <file>: the non-comment, non-blank lines of <file>, sorted.
toml_keys() {
  grep -v -E '^[[:space:]]*(#|$)' "$1" | sort
}

@test "Claude managed settings hold exactly the two env keys" {
  run jq -c -S . "$D/policy/claude-managed-settings.json"
  assert_success
  [ "$output" = '{"env":{"CLAUDE_CODE_PLUGIN_PREFER_HTTPS":"1","DISABLE_UPDATES":"1"}}' ]
}

@test "Codex requirements disable the update check and store credentials in a file" {
  run toml_keys "$D/policy/codex-requirements.toml"
  assert_success
  [ "$output" = "$(printf '%s\n' 'check_for_update_on_startup = false' 'cli_auth_credentials_store = "file"')" ]
  refute_output_contains allowed_sandbox_modes
}

@test "Codex system config sets the sandbox and approval defaults" {
  run toml_keys "$D/policy/codex-config.toml"
  assert_success
  [ "$output" = "$(printf '%s\n' 'approval_policy = "on-request"' 'sandbox_mode = "danger-full-access"')" ]
}

@test "the shared Compose file fixes image, init, user, updates off and the read-only bind" {
  local f="$D/compose.yaml"
  grep -q -x '    image: aidc-workspace:local' "$f"
  grep -q -x '    init: true' "$f"
  grep -q -x '    user: vscode' "$f"
  grep -q -x '      DISABLE_UPDATES: "1"' "$f"
  grep -q -x '      - .:/opt/aidc/devcontainer:ro' "$f"
}

@test "the shared Compose file sets the tool and state environment of TD SS3.2" {
  local f="$D/compose.yaml"
  grep -q -x '      MISE_DATA_DIR: /opt/aidc/tools/mise' "$f"
  grep -q -x '      MISE_GLOBAL_CONFIG_FILE: /opt/aidc/tools/mise.toml' "$f"
  grep -q -x '      CLAUDE_CONFIG_DIR: /home/vscode/.claude' "$f"
  grep -q -x '      CODEX_HOME: /home/vscode/.codex' "$f"
  grep -q -x '      HISTFILE: /home/vscode/.local/state/shell/zsh_history' "$f"
}

@test "the shared Compose file trusts the project space and shares mise downloads" {
  local f="$D/compose.yaml"
  grep -q -x '      MISE_TRUSTED_CONFIG_PATHS: /workspaces' "$f"
  grep -q -x '      MISE_DOWNLOADS_DIR: /opt/aidc/downloads' "$f"
  grep -q -x '      MISE_ALWAYS_KEEP_DOWNLOAD: "1"' "$f"
  grep -q -x '      MISE_CACHE_DIR: /opt/aidc/tools/cache' "$f"
}

@test "the Compose file and the mise isolation set the same mise directories" {
  local var value
  for var in MISE_DATA_DIR MISE_GLOBAL_CONFIG_FILE MISE_DOWNLOADS_DIR MISE_CACHE_DIR; do
    value="$(sed -n "s/^AIDC_$var=//p" "$D/lib/mise-isolation.sh")"
    [ -n "$value" ]
    grep -q -x "      $var: $value" "$D/compose.yaml"
  done
}
