#!/usr/bin/env bats
# Docker tests for the container sudo, mise updates, downloads and project
# trust spec (docs/specs/2026-09-29-container-sudo-mise-trust-design.md):
# S1-S3 and S5-S8. Profile S is started once with both start fields off and
# reused; profile B joins it for the shared-downloads tests. bats runs a
# file's tests in source order, and later tests depend on the containers the
# earlier ones left: the tests that recreate S (S3, then S5) run last. This
# file uses its own downloads volume, so S7 starts from an empty one.
load ../helpers/integration
bats_require_minimum_version 1.5.0

setup_file() {
  aidc_it_repo "$BATS_FILE_TMPDIR"
  aidc_it_stub_bin
  aidc_it_ensure_image

  COMPOSE_TEST="$AIDC_SOURCE_ROOT/tests/fixtures/compose.test.yaml"
  COMPOSE_NONET="$AIDC_SOURCE_ROOT/tests/fixtures/compose.nonet.yaml"
  AIDC_MISE_DOWNLOADS_VOLUME="aidc-mise-downloads-$(aidc_it_run)-smt"
  PINNED_MISE="$(sed -n 's/^ARG MISE_VERSION=//p' "$AIDC_ROOT/.devcontainer/Dockerfile")"
  export COMPOSE_TEST COMPOSE_NONET AIDC_MISE_DOWNLOADS_VOLUME PINNED_MISE
  aidc_it_track_volume "$AIDC_MISE_DOWNLOADS_VOLUME"

  S="$(aidc_it_name s)"
  B="$(aidc_it_name b)"
  export S B
  aidc_it_new_profile "$S"
  aidc_it_code "$S"
  aidc_it_track_state "$S"
  aidc_it_up "$S" "$COMPOSE_TEST"
  S_STATUS="$(aidc_it_wait_init "$S")"
  export S_STATUS
}

teardown_file() {
  aidc_it_cleanup
}

mise_version_of() { # <profile>: the running mise's version number
  aidc_it_exec "$1" mise --version | awk '{ print $1 }'
}

tool_version() { # <profile> <tool key>
  aidc_it_exec "$1" mise ls --json "$2" | jq -r '.[] | select(.installed and .active) | .version'
}

@test "the first start with both start fields off succeeded" {
  [[ "$S_STATUS" == ok* ]] || {
    printf 'expected an ok init.status, got: %s\n' "$S_STATUS" >&2
    return 1
  }
}

@test "S1: vscode runs sudo without a password" {
  run aidc_it_exec "$S" sudo -n true
  assert_success
  run aidc_it_exec "$S" id -un
  assert_output_contains vscode
}

@test "S2: visudo accepts the image's sudoers configuration" {
  run aidc_it_exec "$S" sudo -n visudo -c
  assert_success
}

@test "S6: a project in the profile project space loads without a trust prompt" {
  local proj="/workspaces/$S/proj"
  mkdir -p "$AIDC_ROOT/projects/$S/proj"
  printf '[env]\nAIDC_S6 = "trusted"\n\n[tasks."aidc:status"]\nrun = "echo PROJECT-TASK"\n' \
    >"$AIDC_ROOT/projects/$S/proj/mise.toml"

  run aidc_it_exec "$S" zsh -ic "cd $proj && print -r -- \"v=\$AIDC_S6\""
  assert_success
  assert_output_contains "v=trusted"

  run docker exec --workdir "$proj" "$(aidc_it_container "$S")" env -u AIDC_S6 mise exec -- printenv AIDC_S6
  assert_success
  [ "${lines[-1]}" = trusted ]

  # The container task still ignores the trusted project's own task.
  run docker exec --workdir "$proj" "$(aidc_it_container "$S")" \
    env MISE_TASK_RUN_AUTO_INSTALL=false mise -C / run aidc:status
  assert_success
  assert_output_contains "init:"
  refute_output_contains "PROJECT-TASK"
}

@test "S6: a fresh project outside /workspaces still needs trust in the shell" {
  # `mise exec`, `mise run` and `mise install` trust their active config on
  # their own in mise's normal mode, so shell activation is where trust
  # still shows (probe 2026-09-29).
  aidc_it_exec "$S" sh -c 'mkdir -p /tmp/untrusted && printf "[env]\nAIDC_S6 = \"x\"\n" >/tmp/untrusted/mise.toml'
  run aidc_it_exec "$S" zsh -ic 'cd /tmp/untrusted && print -r -- "v=$AIDC_S6"'
  assert_success
  assert_output_contains "not trusted"
  assert_output_contains "v="
  refute_output_contains "v=x"
}

@test "S7: an archive S downloaded installs in B, with an empty tools volume, on no network" {
  local lock
  run aidc_it_exec "$S" sh -c 'ls /opt/aidc/downloads | grep -c .'
  assert_success
  [ "$output" -gt 0 ]

  aidc_it_new_profile "$B"
  aidc_it_code "$B"
  aidc_it_track_state "$B"
  lock="$BATS_FILE_TMPDIR/s-mise.lock"
  aidc_it_exec "$S" cat /opt/aidc/tools/mise.lock >"$lock"
  docker run --rm -i -v "aidc-tools-$B:/opt/aidc/tools" --entrypoint sh aidc-workspace:local \
    -c 'cat >/opt/aidc/tools/mise.lock' <"$lock"

  aidc_it_up "$B" "$COMPOSE_NONET"
  run aidc_it_wait_init "$B"
  assert_success
  # Plugin initialization needs the network; the tools step must not.
  [[ "$output" != *tools* ]] || {
    printf 'expected no tools failure offline, got: %s\n' "$output" >&2
    return 1
  }
  local tool b_ver s_ver
  for tool in 'aqua:anthropics/claude-code' 'aqua:openai/codex'; do
    b_ver="$(tool_version "$B" "$tool")"
    s_ver="$(tool_version "$S" "$tool")"
    [ -n "$b_ver" ]
    [ "$b_ver" = "$s_ver" ]
  done
}

@test "S8 probe: two containers install the same version into the shared downloads at once; a retry settles a lost race" {
  aidc_it_down "$B" "$COMPOSE_NONET"
  aidc_it_up "$B" "$COMPOSE_TEST"
  run aidc_it_wait_init "$B"
  assert_success

  # mise can race on one archive in the shared downloads: the loser fails
  # with "No such file or directory" (probe 2026-09-29, 3 of 5 runs). The
  # developer accepted report-and-retry (spec S8), so a lost race must be
  # settled by one plain retry.
  local p rc
  for p in "$S" "$B"; do
    aidc_it_exec "$p" mise install aqua:sharkdp/fd@10.2.0 >"$BATS_TEST_TMPDIR/$p.log" 2>&1 &
    printf '%s %s\n' "$p" "$!" >>"$BATS_TEST_TMPDIR/pids"
  done
  run aidc_it_exec "$S" env MISE_TASK_RUN_AUTO_INSTALL=false mise -C / run aidc:status
  assert_success
  while read -r p pid; do
    rc=0
    wait "$pid" || rc=$?
    printf '# %s: first install exit %s\n' "$p" "$rc" >&3
    if [ "$rc" -ne 0 ]; then
      grep -q 'No such file or directory' "$BATS_TEST_TMPDIR/$p.log"
      run aidc_it_exec "$p" mise install aqua:sharkdp/fd@10.2.0
      assert_success
    fi
    run aidc_it_exec "$p" mise where aqua:sharkdp/fd@10.2.0
    assert_success
  done <"$BATS_TEST_TMPDIR/pids"
}

@test "S8 probe: an install killed mid-download does not break the next one" {
  # The kill must land while mise still runs, and must leave the tool
  # uninstalled, or the probe proves nothing.
  run aidc_it_exec "$S" sh -c 'mise install aqua:cli/cli@2.63.2 >/dev/null 2>&1 & pid=$!; sleep 1; kill -9 $pid'
  assert_success
  run aidc_it_exec "$S" mise where aqua:cli/cli@2.63.2
  assert_failure
  run aidc_it_exec "$B" mise install aqua:cli/cli@2.63.2
  assert_success
  run aidc_it_exec "$B" mise where aqua:cli/cli@2.63.2
  assert_success
}

@test "S3: vscode updates mise without sudo, and a recreated container returns to the pinned version" {
  [ "$(mise_version_of "$S")" = "$PINNED_MISE" ]
  # The target must differ from the pin, or the update proves no change.
  [ "$PINNED_MISE" != 2026.9.16 ]
  run aidc_it_exec "$S" mise self-update -y --no-plugins 2026.9.16
  assert_success
  [ "$(mise_version_of "$S")" = 2026.9.16 ]

  aidc_it_down "$S" "$COMPOSE_TEST"
  aidc_it_up "$S" "$COMPOSE_TEST"
  run aidc_it_wait_init "$S"
  assert_success
  [ "$(mise_version_of "$S")" = "$PINNED_MISE" ]
}

@test "S5: online, both start fields update mise and upgrade the tools" {
  aidc_it_set_env "$S" START_UPDATE_MISE=on START_UPGRADE_TOOLS=on
  aidc_it_code "$S"
  aidc_it_down "$S" "$COMPOSE_TEST"
  aidc_it_up "$S" "$COMPOSE_TEST"
  run aidc_it_wait_init "$S"
  assert_success
  [[ "$output" == ok* ]] || {
    printf 'expected an ok init.status, got: %s\n' "$output" >&2
    return 1
  }
  [ "$(mise_version_of "$S")" != "$PINNED_MISE" ]
  run aidc_it_exec "$S" grep -c offline /opt/aidc/tools/init.log
  [ "$output" = 0 ]
  run aidc_it_exec "$S" grep -qx 'aidc: tools step: update' /opt/aidc/tools/init.log
  assert_success
}

@test "S5: offline, both start fields skip their updates without a failure" {
  aidc_it_down "$S" "$COMPOSE_TEST"
  aidc_it_up "$S" "$COMPOSE_NONET"
  run aidc_it_wait_init "$S"
  assert_success
  [[ "$output" == ok* ]] || {
    printf 'expected an ok init.status offline, got: %s\n' "$output" >&2
    return 1
  }
  [ "$(mise_version_of "$S")" = "$PINNED_MISE" ]
  run aidc_it_exec "$S" cat /opt/aidc/tools/init.log
  assert_output_contains "offline: skipping the mise self-update"
  assert_output_contains "offline: skipping the tools upgrade"
}

@test "S5: offline, a tool the old lock does not cover fails the tools step and the copy stays" {
  sed -i '/^\[tools\]$/a "aqua:BurntSushi/xsv" = "0.13.0"' "$AIDC_ROOT/.devcontainer/mise.toml"
  aidc_it_down "$S" "$COMPOSE_NONET"
  aidc_it_up "$S" "$COMPOSE_NONET"
  run aidc_it_wait_init "$S"
  assert_success
  [[ "$output" == failed*tools* ]] || {
    printf 'expected failed: tools, got: %s\n' "$output" >&2
    return 1
  }
  run aidc_it_exec "$S" grep -c 'BurntSushi/xsv' /opt/aidc/tools/mise.toml
  assert_success
  sed -i '/BurntSushi\/xsv/d' "$AIDC_ROOT/.devcontainer/mise.toml"
}

@test "S5: offline, a tools volume with no mise.lock fails the tools step and the copy stays" {
  aidc_it_exec "$S" rm -f /opt/aidc/tools/mise.lock
  aidc_it_down "$S" "$COMPOSE_NONET"
  aidc_it_up "$S" "$COMPOSE_NONET"
  run aidc_it_wait_init "$S"
  assert_success
  [[ "$output" == failed*tools* ]] || {
    printf 'expected failed: tools, got: %s\n' "$output" >&2
    return 1
  }
  run aidc_it_exec "$S" test -f /opt/aidc/tools/mise.toml
  assert_success
  run aidc_it_exec "$S" test -e /opt/aidc/tools/mise.lock
  assert_failure
  run aidc_it_exec "$S" grep -q 'no mise.lock' /opt/aidc/tools/init.log
  assert_success
}
