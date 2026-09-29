#!/usr/bin/env bats
load ../../helpers/common

setup() {
  aidc_test_repo
  source "$AIDC_ROOT/tasks/host/lib/common.sh"
  source "$AIDC_ROOT/tasks/host/lib/profile_env.sh"
  mkdir -p "$AIDC_ROOT/profiles/dev"
}

write_env() { printf '%s\n' "$@" >"$AIDC_ROOT/profiles/dev/profile.env"; }

@test "comments and blank lines are ignored" {
  write_env "# a comment" "" "PROFILE_CLAUDE=" "   " "# another"
  aidc::load_profile_env dev
  [ "$AIDC_STATE_CLAUDE" = dev ]
}

@test "an unknown key is rejected with its line number" {
  write_env "PROFILE_CLAUDE=dev" "UNKNOWN=1"
  run aidc::load_profile_env dev
  assert_failure
  assert_output_contains "line 2"
  assert_output_contains "unknown key 'UNKNOWN'"
}

@test "a duplicate key is rejected" {
  write_env "DOCKER_SOCKET=on" "DOCKER_SOCKET=off"
  run aidc::load_profile_env dev
  assert_failure
  assert_output_contains "line 2"
  assert_output_contains "duplicate key"
}

@test "an empty value counts as unset" {
  write_env "PROFILE_CLAUDE=" "PROFILE_CODEX=" "PROFILE_SHELL=" "DOCKER_SOCKET=" "GIT_AUTHOR_NAME="
  aidc::load_profile_env dev
  [ "$AIDC_STATE_CLAUDE" = dev ]
  [ "$AIDC_STATE_CODEX" = dev ]
  [ "$AIDC_STATE_SHELL" = dev ]
  [ "$AIDC_DOCKER_SOCKET" = off ]
  [ -z "$AIDC_GIT_AUTHOR_NAME" ]
}

@test "PROFILE_CLAUDE=Bad is rejected" {
  write_env "PROFILE_CLAUDE=Bad"
  run aidc::load_profile_env dev
  assert_status 2
}

@test "DOCKER_SOCKET=yes is rejected" {
  write_env "DOCKER_SOCKET=yes"
  run aidc::load_profile_env dev
  assert_failure
}

@test "the start fields default to on and accept off" {
  write_env ""
  aidc::load_profile_env dev
  [ "$AIDC_START_UPDATE_MISE" = on ]
  [ "$AIDC_START_UPGRADE_TOOLS" = on ]
  write_env "START_UPDATE_MISE=off" "START_UPGRADE_TOOLS=off"
  aidc::load_profile_env dev
  [ "$AIDC_START_UPDATE_MISE" = off ]
  [ "$AIDC_START_UPGRADE_TOOLS" = off ]
}

@test "a start field other than on or off is rejected" {
  local field
  for field in START_UPDATE_MISE START_UPGRADE_TOOLS; do
    write_env "$field=yes"
    run aidc::load_profile_env dev
    assert_failure
    assert_output_contains "$field must be 'on' or 'off'"
  done
}

@test "KEEP_RUNNING defaults to on, accepts off, and rejects anything else" {
  write_env ""
  aidc::load_profile_env dev
  [ "$AIDC_KEEP_RUNNING" = on ]
  write_env "KEEP_RUNNING=off"
  aidc::load_profile_env dev
  [ "$AIDC_KEEP_RUNNING" = off ]
  write_env "KEEP_RUNNING=yes"
  run aidc::load_profile_env dev
  assert_failure
  assert_output_contains "KEEP_RUNNING must be 'on' or 'off'"
}

@test "quotes in a value are kept literally" {
  write_env 'GIT_AUTHOR_NAME="Example Developer"'
  aidc::load_profile_env dev
  [ "$AIDC_GIT_AUTHOR_NAME" = '"Example Developer"' ]
}

@test "a dollar sign in a value survives, unexpanded" {
  write_env 'GIT_SSH_COMMAND=ssh -i $HOME/.ssh/id_ed25519'
  aidc::load_profile_env dev
  [ "$AIDC_GIT_SSH_COMMAND" = 'ssh -i $HOME/.ssh/id_ed25519' ]
}

@test "a trailing '# x' after a value is part of the value" {
  write_env 'GIT_AUTHOR_NAME=Example Developer # x'
  aidc::load_profile_env dev
  [ "$AIDC_GIT_AUTHOR_NAME" = 'Example Developer # x' ]
}

@test "every GIT_* field is available and unset by default" {
  write_env ""
  aidc::load_profile_env dev
  [ -z "$AIDC_GIT_AUTHOR_NAME" ]
  [ -z "$AIDC_GIT_AUTHOR_EMAIL" ]
  [ -z "$AIDC_GIT_COMMITTER_NAME" ]
  [ -z "$AIDC_GIT_COMMITTER_EMAIL" ]
  [ -z "$AIDC_GIT_SSH_COMMAND" ]
}

@test "a missing profile points to profile:new" {
  run aidc::load_profile_env nope
  assert_failure
  assert_output_contains "mise run profile:new nope"
}

@test "an explicit state key selects a shared name" {
  write_env "PROFILE_CLAUDE=team"
  aidc::load_profile_env dev
  [ "$AIDC_STATE_CLAUDE" = team ]
  [ "$AIDC_STATE_CODEX" = dev ]
}
