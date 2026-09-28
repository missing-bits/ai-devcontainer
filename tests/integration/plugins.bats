#!/usr/bin/env bats
# Docker tests for AC8, AC9 and AC10 (TD §3.3, §3.5, §6). Each scenario needs
# its own fresh profile, since AC9 and AC10 depend on catching or forcing a
# particular first-start outcome.
load ../helpers/integration
bats_require_minimum_version 1.5.0

setup_file() {
  aidc_it_repo "$BATS_FILE_TMPDIR"
  aidc_it_stub_bin
  aidc_it_ensure_image

  COMPOSE_TEST="$AIDC_SOURCE_ROOT/tests/fixtures/compose.test.yaml"
  COMPOSE_NONET="$AIDC_SOURCE_ROOT/tests/fixtures/compose.nonet.yaml"
  export COMPOSE_TEST COMPOSE_NONET
}

teardown_file() {
  aidc_it_cleanup
}

claude_plugin_count() {
  docker exec "$(aidc_it_container "$1")" claude plugin list --json 2>/dev/null | jq 'length' 2>/dev/null || printf 0
}

@test "a new state profile gets every default plugin and the marker" {
  local p1
  p1="$(aidc_it_name p1)"
  aidc_it_new_profile "$p1"
  aidc_it_code "$p1"
  aidc_it_up "$p1" "$COMPOSE_TEST"
  aidc_it_track_state "$p1"

  local status
  status="$(aidc_it_wait_init "$p1")"
  [[ "$status" == ok* ]] || {
    printf 'expected an ok init.status, got: %s\n' "$status" >&2
    return 1
  }

  run aidc_it_exec "$p1" test -e /home/vscode/.claude/.aidc/plugins-initialized
  assert_success
  run aidc_it_exec "$p1" test -e /home/vscode/.codex/.aidc/plugins-initialized
  assert_success

  run aidc_it_exec "$p1" claude plugin list --json
  assert_success
  run jq -r '.[].id' <<<"$output"
  assert_success
  assert_output_contains "superpowers@claude-plugins-official"
  assert_output_contains "elements-of-style@superpowers-marketplace"
  assert_output_contains "working-process@missing-bits"
  assert_output_contains "project-memory@missing-bits"

  run aidc_it_exec "$p1" codex plugin list --json
  assert_success
  run jq -r '.installed[].pluginId' <<<"$output"
  assert_success
  assert_output_contains "superpowers@claude-plugins-official"
  assert_output_contains "elements-of-style@superpowers-marketplace"
}

@test "an interrupted first plugin install completes at the next start, with the marker" {
  local p2 container count i
  p2="$(aidc_it_name p2)"
  aidc_it_new_profile "$p2"
  aidc_it_code "$p2"
  aidc_it_up "$p2" "$COMPOSE_TEST"
  aidc_it_track_state "$p2"
  container="$(aidc_it_container "$p2")"

  # Poll for the first (but not every) default plugin, then kill the
  # container immediately, so the marker cannot yet exist (TD §3.5 writes it
  # only after every install succeeds). Plugin initialization only starts
  # once the tools step finishes, so the window covers a full tool install
  # (up to 300s) plus room to catch the first plugin before the rest land.
  count=0
  for i in $(seq 1 1500); do
    count="$(claude_plugin_count "$p2")"
    if [ "${count:-0}" -ge 1 ] 2>/dev/null; then
      break
    fi
    sleep 0.2
  done
  [ "${count:-0}" -ge 1 ] || {
    printf 'never observed a first installed plugin within the timeout\n' >&2
    return 1
  }
  docker kill "$container" >/dev/null

  aidc_it_up "$p2" "$COMPOSE_TEST"
  local status
  status="$(aidc_it_wait_init "$p2")"
  [[ "$status" == ok* ]] || {
    printf 'expected an ok init.status after the retry, got: %s\n' "$status" >&2
    return 1
  }

  run aidc_it_exec "$p2" test -e /home/vscode/.claude/.aidc/plugins-initialized
  assert_success
  run aidc_it_exec "$p2" claude plugin list --json
  assert_success
  run jq 'length' <<<"$output"
  assert_success
  [ "$output" -eq 4 ]
}

@test "first start with no network runs, and aidc:status from an untrusted project shows the tools, plugins and failed initialization; a later start with the network installs and reports ok" {
  local p3 container status
  p3="$(aidc_it_name p3)"
  aidc_it_new_profile "$p3"
  aidc_it_code "$p3"
  aidc_it_up "$p3" "$COMPOSE_NONET"
  aidc_it_track_state "$p3"
  container="$(aidc_it_container "$p3")"

  status="$(aidc_it_wait_init "$p3")"
  [[ "$status" == failed* ]] || {
    printf 'expected a failed init.status with no network, got: %s\n' "$status" >&2
    return 1
  }

  mkdir -p "$AIDC_ROOT/projects/$p3/untrusted-proj"
  printf '[tools]\nnode = "24"\n' >"$AIDC_ROOT/projects/$p3/untrusted-proj/mise.toml"

  run docker exec --workdir "/workspaces/$p3/untrusted-proj" "$container" \
    env MISE_TASK_RUN_AUTO_INSTALL=false mise -C / run aidc:status
  assert_success
  assert_output_contains "failed"
  assert_output_contains "aqua:anthropics/claude-code missing"
  assert_output_contains "aqua:openai/codex missing"
  assert_output_contains "claude: not initialized"
  assert_output_contains "codex: not initialized"

  aidc_it_down "$p3" "$COMPOSE_NONET"
  aidc_it_up "$p3" "$COMPOSE_TEST"
  status="$(aidc_it_wait_init "$p3")"
  [[ "$status" == ok* ]] || {
    printf 'expected an ok init.status after the network recreate, got: %s\n' "$status" >&2
    return 1
  }
}
