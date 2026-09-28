#!/usr/bin/env bats
# Docker tests for AC3, AC4, AC5 and the TD §5 cross-container flock. Most
# tests share one profile (C), started once and reused, because each of
# these scenarios only needs the tools already installed or a small,
# host-side edit of the read-only-mounted .devcontainer/mise.toml; bats runs
# a file's tests in source order, and later tests here depend on the
# container the earlier ones already brought up. The recreate-offline test
# runs last because it recreates C's container. The flock test is
# self-contained and does not depend on C.
load ../helpers/integration
bats_require_minimum_version 1.5.0

setup_file() {
  aidc_it_repo "$BATS_FILE_TMPDIR"
  aidc_it_stub_bin
  aidc_it_ensure_image

  COMPOSE_TEST="$AIDC_SOURCE_ROOT/tests/fixtures/compose.test.yaml"
  COMPOSE_NONET="$AIDC_SOURCE_ROOT/tests/fixtures/compose.nonet.yaml"
  export COMPOSE_TEST COMPOSE_NONET

  C="$(aidc_it_name c)"
  export C
  aidc_it_new_profile "$C"
  aidc_it_code "$C"
  aidc_it_up "$C" "$COMPOSE_TEST"
  aidc_it_track_state "$C"

  C_STATUS="$(aidc_it_wait_init "$C")"
  export C_STATUS
}

teardown_file() {
  aidc_it_cleanup
}

# mise_version <tool key>: the version `mise ls --json` reports installed
# and active for <tool key>, from inside C. `mise ls --json <tool>` (one
# tool named explicitly) returns a flat array, unlike the full listing's
# object-of-arrays shape (verified against the pinned mise on the host).
mise_version() {
  aidc_it_exec "$C" mise ls --json "$1" | jq -r '.[] | select(.installed and .active) | .version'
}

@test "the first start installed the container tools" {
  [[ "$C_STATUS" == ok* ]] || {
    printf 'expected an ok init.status, got: %s\n' "$C_STATUS" >&2
    return 1
  }
}

@test "claude --version and codex --version report the tools volume's CLIs, also from inside a project declaring other versions" {
  local claude_ver codex_ver
  claude_ver="$(mise_version 'aqua:anthropics/claude-code')"
  codex_ver="$(mise_version 'aqua:openai/codex')"
  [ -n "$claude_ver" ]
  [ -n "$codex_ver" ]

  run aidc_it_exec "$C" claude --version
  assert_success
  assert_output_contains "$claude_ver"
  run aidc_it_exec "$C" codex --version
  assert_success
  assert_output_contains "$codex_ver"

  mkdir -p "$AIDC_ROOT/projects/$C/proj"
  printf '[tools]\n"aqua:anthropics/claude-code" = "2.0.0"\n"aqua:openai/codex" = "0.100.0"\n' \
    >"$AIDC_ROOT/projects/$C/proj/mise.toml"

  run docker exec --workdir "/workspaces/$C/proj" "$(aidc_it_container "$C")" claude --version
  assert_success
  assert_output_contains "$claude_ver"
  run docker exec --workdir "/workspaces/$C/proj" "$(aidc_it_container "$C")" codex --version
  assert_success
  assert_output_contains "$codex_ver"
}

@test "aidc:sync installs a tool added to .devcontainer/mise.toml" {
  # Inserted right after [tools], not appended: the file ends inside the
  # last [tasks."..."] table, and appending there would corrupt it.
  sed -i '/^\[tools\]$/a "aqua:sharkdp/fd" = "10"' "$AIDC_ROOT/.devcontainer/mise.toml"

  run docker exec "$(aidc_it_container "$C")" env MISE_TASK_RUN_AUTO_INSTALL=false mise -C / run aidc:sync
  assert_success

  run mise_version 'aqua:sharkdp/fd'
  assert_success
  [ -n "$output" ]
}

@test "aidc:update moves a tool locked to an older version to a newer allowed one" {
  local before after
  # Repin fd to an old exact version and install it, so the update has a
  # real move to make.
  sed -i 's#"aqua:sharkdp/fd" = "10"#"aqua:sharkdp/fd" = "8.7.1"#' "$AIDC_ROOT/.devcontainer/mise.toml"
  run docker exec "$(aidc_it_container "$C")" env MISE_TASK_RUN_AUTO_INSTALL=false mise -C / run aidc:sync
  assert_success
  before="$(mise_version 'aqua:sharkdp/fd')"
  [ "$before" = 8.7.1 ]

  sed -i 's#"aqua:sharkdp/fd" = "8.7.1"#"aqua:sharkdp/fd" = "10"#' "$AIDC_ROOT/.devcontainer/mise.toml"
  run docker exec "$(aidc_it_container "$C")" env MISE_TASK_RUN_AUTO_INSTALL=false mise -C / run aidc:update
  assert_success
  after="$(mise_version 'aqua:sharkdp/fd')"
  [ -n "$after" ]
  [ "$after" != "$before" ]
}

@test "with one uninstallable tool declared, sync installs the others, names it, and exits non-zero" {
  sed -i '/^\[tools\]$/a "aqua:aidc-test-org-does-not-exist/aidc-test-tool-does-not-exist" = "latest"' \
    "$AIDC_ROOT/.devcontainer/mise.toml"

  run docker exec "$(aidc_it_container "$C")" env MISE_TASK_RUN_AUTO_INSTALL=false mise -C / run aidc:sync
  assert_failure
  assert_output_contains "aidc-test-org-does-not-exist/aidc-test-tool-does-not-exist"

  run mise_version 'aqua:sharkdp/fd'
  assert_success
  [ -n "$output" ]
  run mise_version 'aqua:anthropics/claude-code'
  assert_success
  [ -n "$output" ]

  # aidc:update against the same uninstallable-tool state: names the failure,
  # exits non-zero, and the other tools stay installed too.
  run docker exec "$(aidc_it_container "$C")" env MISE_TASK_RUN_AUTO_INSTALL=false mise -C / run aidc:update
  assert_failure
  assert_output_contains "aidc-test-org-does-not-exist/aidc-test-tool-does-not-exist"

  run mise_version 'aqua:sharkdp/fd'
  assert_success
  [ -n "$output" ]
  run mise_version 'aqua:anthropics/claude-code'
  assert_success
  [ -n "$output" ]
  run mise_version 'aqua:openai/codex'
  assert_success
  [ -n "$output" ]

  # Leave the copy installable again for the recreate test below: editing
  # the host source is not enough, since a plain restart only re-copies
  # .devcontainer/mise.toml into the tools volume when no copy exists yet
  # (TD §3.3 "start"); aidc:sync always re-copies it.
  sed -i '/aidc-test-tool-does-not-exist/d' "$AIDC_ROOT/.devcontainer/mise.toml"
  run docker exec "$(aidc_it_container "$C")" env MISE_TASK_RUN_AUTO_INSTALL=false mise -C / run aidc:sync
  assert_success
}

@test "after recreation from the cached image with --network none, tool versions are unchanged" {
  local claude_before codex_before fd_before claude_after codex_after fd_after status
  claude_before="$(mise_version 'aqua:anthropics/claude-code')"
  codex_before="$(mise_version 'aqua:openai/codex')"
  fd_before="$(mise_version 'aqua:sharkdp/fd')"

  aidc_it_down "$C" "$COMPOSE_TEST"
  aidc_it_up "$C" "$COMPOSE_NONET"
  status="$(aidc_it_wait_init "$C")"
  [[ "$status" == ok* ]] || {
    printf 'expected an ok init.status after the offline recreate, got: %s\n' "$status" >&2
    return 1
  }

  claude_after="$(mise_version 'aqua:anthropics/claude-code')"
  codex_after="$(mise_version 'aqua:openai/codex')"
  fd_after="$(mise_version 'aqua:sharkdp/fd')"
  [ "$claude_after" = "$claude_before" ]
  [ "$codex_after" = "$codex_before" ]
  [ "$fd_after" = "$fd_before" ]
}

@test "a second container waits for a flock held by the first on a shared volume and gets it once the holder stops" {
  local vol holder waiter
  vol="$(aidc_it_name flock-vol)"
  holder="$(aidc_it_name flock-holder)"
  waiter="$(aidc_it_name flock-waiter)"

  docker volume create "$vol" >/dev/null
  aidc_it_track_volume "$vol"

  # --user 0: /v is a fresh volume with no pre-existing mount point in the
  # image, so Docker creates it owned by root; the non-root default user
  # could not otherwise write the lock file. Ownership is irrelevant to what
  # this test exercises (the flock itself).
  docker run -d --name "$holder" --user 0 -v "$vol:/v" --entrypoint sh aidc-workspace:local \
    -c 'flock /v/.lock sh -c "touch /v/held; sleep 20"' >/dev/null
  aidc_it_track_container "$holder"

  local i
  for i in $(seq 1 50); do
    docker exec "$holder" test -e /v/held 2>/dev/null && break
    sleep 0.1
  done
  run docker exec "$holder" test -e /v/held
  assert_success

  docker run -d --name "$waiter" --user 0 -v "$vol:/v" --entrypoint sh aidc-workspace:local \
    -c 'flock /v/.lock sh -c "touch /v/acquired"' >/dev/null
  aidc_it_track_container "$waiter"

  sleep 2
  run docker exec "$holder" test -e /v/acquired
  assert_failure

  docker stop "$holder" >/dev/null

  local acquired=1
  for i in $(seq 1 50); do
    if docker run --rm --user 0 -v "$vol:/v" --entrypoint sh aidc-workspace:local -c 'test -e /v/acquired'; then
      acquired=0
      break
    fi
    sleep 0.2
  done
  [ "$acquired" -eq 0 ]
}
