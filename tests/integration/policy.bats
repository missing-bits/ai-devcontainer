#!/usr/bin/env bats
# Docker tests for AC6 (TD §3.7 policy keys). One profile, started once and
# reused; bats runs a file's tests in source order and later tests build on
# state the earlier ones leave (a user override file, a completed exec run).
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
  aidc_it_track_profile "$P"
  aidc_it_track_volume "aidc-claude-$P"
  aidc_it_track_volume "aidc-codex-$P"
  aidc_it_track_volume "aidc-shell-$P"

  status="$(aidc_it_wait_init "$P")"
  [[ "$status" == ok* ]] || {
    printf 'expected an ok init.status, got: %s\n' "$status" >&2
    return 1
  }
}

teardown_file() {
  aidc_it_cleanup
}

@test "claude update refuses" {
  # Verified 2026-09-28: claude update exits 0 and reports the managed
  # refusal message rather than performing the update.
  run aidc_it_exec "$P" claude update
  assert_success
  assert_output_contains "Updates are disabled by your administrator"
}

@test "a user settings.json setting DISABLE_UPDATES=0 does not re-enable Claude's update" {
  aidc_it_exec "$P" sh -c 'echo "{\"env\":{\"DISABLE_UPDATES\":\"0\"}}" > /home/dev/.claude/settings.json'
  run aidc_it_exec "$P" claude update
  assert_success
  assert_output_contains "Updates are disabled by your administrator"
}

@test "a user config.toml cannot re-enable the Codex update check" {
  aidc_it_exec "$P" sh -c 'printf "check_for_update_on_startup = true\n" > /home/dev/.codex/config.toml'
  # codex doctor's own exit status reflects unrelated environment checks
  # (e.g. no login in this state profile), not this override, so only the
  # startup warning line is asserted.
  run aidc_it_exec "$P" codex doctor
  assert_output_contains "Configured value for \`check_for_update_on_startup\` is overridden by the required value false from /etc/codex/requirements.toml."
}

@test "after codex runs, no app-server daemon process exists and CODEX_HOME/packages is absent" {
  aidc_it_exec "$P" sh -c 'codex exec --skip-git-repo-check "hi" </dev/null >/tmp/codex-exec.log 2>&1' || true
  run aidc_it_exec "$P" pgrep -f app-server
  assert_failure
  run aidc_it_exec "$P" test -d /home/dev/.codex/packages
  assert_failure
}

@test "Codex reports danger-full-access and on-request as effective" {
  # codex doctor's overall exit status reflects unrelated environment checks
  # (no login in this state profile), so only the sandbox line is asserted;
  # danger-full-access is reported as "unrestricted fs" (P6.3 probe wording).
  run aidc_it_exec "$P" codex doctor
  assert_output_contains "unrestricted fs + enabled network"
  assert_output_contains "approval OnRequest"
}
