#!/usr/bin/env bats
# Docker tests for AC2, AC7 and AC11: two independent profiles, the shared
# vs. per-profile state volumes, and profile:remove. devcontainer and code
# are stubbed throughout, so profile:code only validates, generates
# .local/<p>/ and creates volumes; every real container start goes through
# `docker compose ... up -d` with tests/fixtures/compose.test.yaml, per the
# brief.
load ../helpers/integration
bats_require_minimum_version 1.5.0

setup_file() {
  aidc_it_repo "$BATS_FILE_TMPDIR"
  aidc_it_stub_bin
  aidc_it_ensure_image

  COMPOSE_TEST="$AIDC_SOURCE_ROOT/tests/fixtures/compose.test.yaml"
  export COMPOSE_TEST

  A="$(aidc_it_name a)"
  B="$(aidc_it_name b)"
  export A B

  aidc_it_new_profile "$A"
  aidc_it_new_profile "$B"
  echo "marker-a" >"$AIDC_ROOT/projects/$A/marker-a"
  echo "marker-b" >"$AIDC_ROOT/projects/$B/marker-b"
  aidc_it_code "$A"
  aidc_it_code "$B"
  aidc_it_up "$A" "$COMPOSE_TEST"
  aidc_it_up "$B" "$COMPOSE_TEST"
  # State volumes are named after the profile itself (unset PROFILE_* fields,
  # AC7); profile:remove never touches them, so aidc_it_track_state tracks
  # the profile and its three state volumes together.
  aidc_it_track_state "$A"
  aidc_it_track_state "$B"
}

teardown_file() {
  aidc_it_cleanup
}

@test "two profiles run at once with their own tools volume and checkouts; id -u/id -g match the host" {
  run docker inspect --format '{{.State.Running}}' "$(aidc_it_container "$A")"
  assert_success
  [ "$output" = true ]
  run docker inspect --format '{{.State.Running}}' "$(aidc_it_container "$B")"
  assert_success
  [ "$output" = true ]

  run docker inspect --format '{{ range .Mounts }}{{ if eq .Destination "/opt/aidc/tools" }}{{ .Name }}{{ end }}{{ end }}' "$(aidc_it_container "$A")"
  assert_success
  [ "$output" = "aidc-tools-$A" ]
  run docker inspect --format '{{ range .Mounts }}{{ if eq .Destination "/opt/aidc/tools" }}{{ .Name }}{{ end }}{{ end }}' "$(aidc_it_container "$B")"
  assert_success
  [ "$output" = "aidc-tools-$B" ]

  run aidc_it_exec "$A" cat "/workspaces/$A/marker-a"
  assert_success
  [ "$output" = marker-a ]
  run aidc_it_exec "$A" test -e "/workspaces/$B"
  assert_failure
  run aidc_it_exec "$B" cat "/workspaces/$B/marker-b"
  assert_success
  [ "$output" = marker-b ]

  run aidc_it_exec "$A" id -u
  assert_success
  [ "$output" = "$(id -u)" ]
  run aidc_it_exec "$A" id -g
  assert_success
  [ "$output" = "$(id -g)" ]
  run aidc_it_exec "$B" id -u
  assert_success
  [ "$output" = "$(id -u)" ]
}

@test "a profile with unset state fields mounts volumes named after itself" {
  run jq -r '.volumes | keys[]' "$AIDC_ROOT/.local/$A/compose.yaml"
  assert_success
  assert_output_contains "aidc-tools-$A"
  assert_output_contains "aidc-claude-$A"
  assert_output_contains "aidc-codex-$A"
  assert_output_contains "aidc-shell-$A"
}

@test "two profiles naming the same state profile share one Claude and one Codex volume, and a settings file written in one is read in the other" {
  local shared s1 s2
  shared="$(aidc_it_name shared)"
  s1="$(aidc_it_name shared-x)"
  s2="$(aidc_it_name shared-y)"
  aidc_it_new_profile "$s1"
  aidc_it_new_profile "$s2"
  aidc_it_set_env "$s1" "PROFILE_CLAUDE=$shared" "PROFILE_CODEX=$shared"
  aidc_it_set_env "$s2" "PROFILE_CLAUDE=$shared" "PROFILE_CODEX=$shared"
  aidc_it_code "$s1"
  aidc_it_code "$s2"
  aidc_it_up "$s1" "$COMPOSE_TEST"
  aidc_it_up "$s2" "$COMPOSE_TEST"
  aidc_it_track_profile "$s1"
  aidc_it_track_profile "$s2"
  aidc_it_track_volume "aidc-claude-$shared"
  aidc_it_track_volume "aidc-codex-$shared"
  aidc_it_track_volume "aidc-shell-$s1"
  aidc_it_track_volume "aidc-shell-$s2"

  run docker inspect --format '{{ range .Mounts }}{{ if eq .Destination "/home/vscode/.claude" }}{{ .Name }}{{ end }}{{ end }}' "$(aidc_it_container "$s1")"
  assert_success
  [ "$output" = "aidc-claude-$shared" ]
  run docker inspect --format '{{ range .Mounts }}{{ if eq .Destination "/home/vscode/.claude" }}{{ .Name }}{{ end }}{{ end }}' "$(aidc_it_container "$s2")"
  assert_success
  [ "$output" = "aidc-claude-$shared" ]

  aidc_it_exec "$s1" sh -c 'echo written-in-s1 > /home/vscode/.claude/shared-settings'
  run aidc_it_exec "$s2" cat /home/vscode/.claude/shared-settings
  assert_success
  [ "$output" = written-in-s1 ]

  aidc_it_exec "$s2" sh -c 'echo written-in-s2 > /home/vscode/.codex/shared-settings'
  run aidc_it_exec "$s1" cat /home/vscode/.codex/shared-settings
  assert_success
  [ "$output" = written-in-s2 ]
}

@test "profile:remove removes the container, .local/<p> and the tools volume, keeps projects, profiles and state volumes, and succeeds again" {
  aidc_it_exec "$A" sh -c 'echo survives >/home/vscode/.claude/pre-remove-marker'

  run bash "$AIDC_ROOT/tasks/host/profile/remove" "$A"
  assert_success
  run docker ps -aq --filter "name=$(aidc_it_container "$A")"
  assert_success
  [ -z "$output" ]
  [ ! -d "$AIDC_ROOT/.local/$A" ]
  run docker volume inspect "aidc-tools-$A"
  assert_failure
  [ -d "$AIDC_ROOT/projects/$A" ]
  [ -d "$AIDC_ROOT/profiles/$A" ]
  run docker volume inspect "aidc-claude-$A" "aidc-codex-$A" "aidc-shell-$A"
  assert_success

  run bash "$AIDC_ROOT/tasks/host/profile/remove" "$A"
  assert_success
}

@test "a state volume survives profile:remove and a later profile:code" {
  aidc_it_code "$A"
  aidc_it_up "$A" "$COMPOSE_TEST"

  run aidc_it_exec "$A" cat /home/vscode/.claude/pre-remove-marker
  assert_success
  [ "$output" = survives ]
}
