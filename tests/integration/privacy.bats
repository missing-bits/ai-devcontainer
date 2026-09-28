#!/usr/bin/env bats
# Docker tests for AC12 (privacy). The git-ignore half of AC12 is a unit test
# (tests/unit/host/repository.bats); this file covers the parts that need
# Docker: the build context, the image and a running container's filesystem,
# a commit's identity, and the socket opt-in.
load ../helpers/integration
bats_require_minimum_version 1.5.0

GIT_AUTHOR_NAME_VALUE="AIDC Test Author"
GIT_AUTHOR_EMAIL_VALUE="author@example.invalid"
GIT_COMMITTER_NAME_VALUE="AIDC Test Committer"
GIT_COMMITTER_EMAIL_VALUE="committer@example.invalid"

setup_file() {
  aidc_it_repo "$BATS_FILE_TMPDIR"
  aidc_it_stub_bin
  aidc_it_ensure_image

  COMPOSE_TEST="$AIDC_SOURCE_ROOT/tests/fixtures/compose.test.yaml"
  export COMPOSE_TEST

  PV="$(aidc_it_name priv)"
  PVON="$(aidc_it_name priv-on)"
  export PV PVON

  aidc_it_new_profile "$PV"
  aidc_it_set_env "$PV" \
    "GIT_AUTHOR_NAME=$GIT_AUTHOR_NAME_VALUE" "GIT_AUTHOR_EMAIL=$GIT_AUTHOR_EMAIL_VALUE" \
    "GIT_COMMITTER_NAME=$GIT_COMMITTER_NAME_VALUE" "GIT_COMMITTER_EMAIL=$GIT_COMMITTER_EMAIL_VALUE"
  aidc_it_code "$PV"
  aidc_it_up "$PV" "$COMPOSE_TEST"
  aidc_it_track_profile "$PV"
  aidc_it_track_volume "aidc-claude-$PV"
  aidc_it_track_volume "aidc-codex-$PV"
  aidc_it_track_volume "aidc-shell-$PV"

  aidc_it_new_profile "$PVON"
  aidc_it_set_env "$PVON" "DOCKER_SOCKET=on"
  aidc_it_code "$PVON"
  aidc_it_up "$PVON" "$COMPOSE_TEST"
  aidc_it_track_profile "$PVON"
  aidc_it_track_volume "aidc-claude-$PVON"
  aidc_it_track_volume "aidc-codex-$PVON"
  aidc_it_track_volume "aidc-shell-$PVON"
}

teardown_file() {
  aidc_it_cleanup
}

@test "the build context holds none of the private directories" {
  run bash -c "tar -cf - -C '$AIDC_ROOT/.devcontainer' . | tar -tf -"
  assert_success
  refute_output_contains "profiles/"
  refute_output_contains "projects/"
  refute_output_contains ".local/"
}

@test "no private key file exists in the image" {
  # grep -l prints only on a match; no output and exit 1 is the passing
  # case, so "assert_failure" here means "found nothing".
  run docker run --rm --user 0 aidc-workspace:local \
    sh -c "grep -rlIE '^-----BEGIN [A-Z ]*PRIVATE KEY-----' / --exclude-dir=proc --exclude-dir=sys"
  assert_failure
  [ -z "$output" ]
}

@test "no private key file exists in a running container" {
  run docker exec -u 0 "$(aidc_it_container "$PV")" \
    grep -rlIE '^-----BEGIN [A-Z ]*PRIVATE KEY-----' / --exclude-dir=proc --exclude-dir=sys
  assert_failure
  [ -z "$output" ]
}

@test "GIT_AUTHOR_NAME and GIT_COMMITTER_EMAIL from profile.env appear in a test commit" {
  run aidc_it_exec "$PV" sh -c 'set -e; mkdir -p /tmp/gitcheck && cd /tmp/gitcheck && git init -q && git commit --allow-empty -q -m test'
  assert_success

  run aidc_it_exec "$PV" git -C /tmp/gitcheck log -1 --format=%an
  assert_success
  [ "$output" = "$GIT_AUTHOR_NAME_VALUE" ]

  run aidc_it_exec "$PV" git -C /tmp/gitcheck log -1 --format=%ce
  assert_success
  [ "$output" = "$GIT_COMMITTER_EMAIL_VALUE" ]
}

@test "the Docker socket exists only with DOCKER_SOCKET=on" {
  run aidc_it_exec "$PV" test -S /var/run/docker.sock
  assert_failure

  run aidc_it_exec "$PVON" test -S /var/run/docker.sock
  assert_success
}
