#!/usr/bin/env bats
# Docker tests for the policy keys (TD §3.7): the sandbox defaults hold, and
# the agent CLIs' updates and Codex's managed daemon follow each CLI's own
# defaults. One profile, started once and reused.
load ../helpers/integration
bats_require_minimum_version 1.5.0

setup_file() {
  aidc_it_repo "$BATS_FILE_TMPDIR"
  aidc_it_stub_bin
  aidc_it_ensure_image

  COMPOSE_TEST="$AIDC_SOURCE_ROOT/tests/fixtures/compose.test.yaml"
  export COMPOSE_TEST

  P="$(aidc_it_name policy)"
  export P
  aidc_it_new_profile "$P"
  aidc_it_code "$P"
  aidc_it_up "$P" "$COMPOSE_TEST"
  aidc_it_track_state "$P"

  status="$(aidc_it_wait_init "$P")"
  [[ "$status" == ok* ]] || {
    printf 'expected an ok init.status, got: %s\n' "$status" >&2
    return 1
  }
}

teardown_file() {
  aidc_it_cleanup
}

@test "claude update defers to mise, not to a policy" {
  # Installed through mise, Claude Code refuses to update itself (probe
  # 2026-09-29); no managed setting blocks it any more.
  run aidc_it_exec "$P" claude update
  assert_output_contains "managed by a package manager"
  refute_output_contains "disabled by your administrator"
}

@test "Codex starts its managed daemon" {
  run aidc_it_exec "$P" codex app-server daemon start
  assert_success
  run aidc_it_exec "$P" codex app-server daemon version
  assert_success
  assert_output_contains '"status":"running"'
  run aidc_it_exec "$P" test -d /home/vscode/.codex/packages/app-server-daemon
  assert_success
  run aidc_it_exec "$P" codex app-server daemon stop
  assert_success
}

@test "Codex reports danger-full-access and on-request as effective" {
  # codex doctor's overall exit status reflects unrelated environment checks
  # (no login in this state profile), so only the sandbox line is asserted;
  # danger-full-access is reported as "unrestricted fs" (P6.3 probe wording).
  run aidc_it_exec "$P" codex doctor
  assert_output_contains "unrestricted fs + enabled network"
  assert_output_contains "approval OnRequest"
}
