#!/usr/bin/env bats
load ../../helpers/common

setup() {
  aidc_test_repo
  unset PROFILE WSL_DISTRO_NAME
  STUB_BIN="$BATS_TEST_TMPDIR/bin"
  mkdir -p "$STUB_BIN"
  CALLS="$BATS_TEST_TMPDIR/calls.log"
  : >"$CALLS"
  for cmd in devcontainer code; do
    cat >"$STUB_BIN/$cmd" <<STUB
#!/usr/bin/env bash
printf '%s %s\n' "$cmd" "\$*" >>"$CALLS"
exit 0
STUB
    chmod +x "$STUB_BIN/$cmd"
  done

  # docker's stub can be told, per test, to fail 'volume rm' or 'compose ...
  # down' (STUB_DOCKER_VOLUME_RM_FAIL / STUB_DOCKER_COMPOSE_DOWN_FAIL), and it
  # answers a label-filtered 'ps -aq' with one fake container ID so the
  # label-fallback pipeline in profile:remove has something to act on.
  cat >"$STUB_BIN/docker" <<'STUB'
#!/usr/bin/env bash
printf 'docker %s\n' "$*" >>"$CALLS"
case "$*" in
"volume rm "*)
  [ -z "${STUB_DOCKER_VOLUME_RM_FAIL:-}" ] || exit 1
  ;;
"compose -p "*" down")
  [ -z "${STUB_DOCKER_COMPOSE_DOWN_FAIL:-}" ] || exit 1
  ;;
"ps -aq --filter label=com.docker.compose.project="*)
  echo cid-demo
  ;;
"network rm "*)
  exit 1
  ;;
esac
exit 0
STUB
  chmod +x "$STUB_BIN/docker"

  PATH="$STUB_BIN:$PATH"
  export PATH CALLS
}

new() { run bash "$AIDC_ROOT/tasks/host/profile/new" "$@"; }
code_task() { run bash "$AIDC_ROOT/tasks/host/profile/code" "$@"; }
remove() { run bash "$AIDC_ROOT/tasks/host/profile/remove" "$@"; }

snapshot() { find "$AIDC_ROOT" | LC_ALL=C sort; }

@test "profile:new creates the profile from the example, and the project space" {
  new demo
  assert_success
  diff "$AIDC_ROOT/examples/profile/profile.env" "$AIDC_ROOT/profiles/demo/profile.env"
  [ -d "$AIDC_ROOT/projects/demo" ]
}

@test "profile:new rejects an invalid name and creates nothing" {
  before="$(snapshot)"
  new "Bad/Name"
  assert_failure
  [ "$(snapshot)" = "$before" ]
}

@test "profile:new twice refuses and keeps the first file" {
  new demo
  assert_success
  echo "custom" >"$AIDC_ROOT/profiles/demo/profile.env"
  new demo
  assert_failure
  assert_output_contains "already exists"
  [ "$(cat "$AIDC_ROOT/profiles/demo/profile.env")" = custom ]
}

@test "profile:code refuses an unknown key or an invalid state name and touches nothing" {
  new demo
  printf 'UNKNOWN=1\n' >"$AIDC_ROOT/profiles/demo/profile.env"
  before="$(snapshot)"
  code_task demo
  assert_failure
  [ "$(snapshot)" = "$before" ]
  [ ! -s "$CALLS" ]

  printf 'PROFILE_CODEX=Bad\n' >"$AIDC_ROOT/profiles/demo/profile.env"
  before="$(snapshot)"
  code_task demo
  assert_failure
  [ "$(snapshot)" = "$before" ]
  [ ! -s "$CALLS" ]
}

@test "profile:code demo creates the volumes, brings the container up, then opens VS Code" {
  new demo
  code_task demo
  assert_success
  [ "$(grep -c '^docker volume create aidc-' "$CALLS")" = 5 ]
  grep -q "^docker volume create aidc-mise-downloads\$" "$CALLS"
  grep -q "^docker volume create aidc-tools-demo\$" "$CALLS"
  grep -q "^docker volume create aidc-claude-demo\$" "$CALLS"
  grep -q "^docker volume create aidc-codex-demo\$" "$CALLS"
  grep -q "^docker volume create aidc-shell-demo\$" "$CALLS"
  grep -q "^devcontainer up --workspace-folder $AIDC_ROOT/.local/demo\$" "$CALLS"
  hex="$(printf '%s' "$AIDC_ROOT/.local/demo" | od -An -tx1 | tr -d ' \n')"
  grep -q "^code --folder-uri vscode-remote://dev-container+$hex/workspaces/demo\$" "$CALLS"
  [ "$(cat "$AIDC_ROOT/.local/active-profile")" = demo ]

  last_volume="$(grep -n '^docker volume create' "$CALLS" | tail -1 | cut -d: -f1)"
  up_line="$(grep -n '^devcontainer up' "$CALLS" | head -1 | cut -d: -f1)"
  code_line="$(grep -n '^code ' "$CALLS" | head -1 | cut -d: -f1)"
  [ "$last_volume" -lt "$up_line" ]
  [ "$up_line" -lt "$code_line" ]
}

@test "under WSL, profile:code passes the Windows form of the host path in the URI" {
  new demo
  cat >"$STUB_BIN/wslpath" <<'STUB'
#!/usr/bin/env bash
[ "$1" = -w ] && printf '\\\\wsl.localhost\\Distro%s\n' "$(printf '%s' "$2" | tr / '\\')"
STUB
  chmod +x "$STUB_BIN/wslpath"
  WSL_DISTRO_NAME=Distro code_task demo
  assert_success
  win="$(PATH="$STUB_BIN:$PATH" wslpath -w "$AIDC_ROOT/.local/demo")"
  case "$win" in '\\wsl.localhost\Distro\'*) ;; *) false ;; esac
  hex="$(printf '%s' "$win" | od -An -tx1 | tr -d ' \n')"
  grep -q "^code --folder-uri vscode-remote://dev-container+$hex/workspaces/demo\$" "$CALLS"
}

@test "profile:code alone uses the active profile; with none, it lists profiles/" {
  new demo
  code_task demo
  assert_success
  : >"$CALLS"
  code_task
  assert_success
  grep -q "^devcontainer up --workspace-folder $AIDC_ROOT/.local/demo\$" "$CALLS"

  rm -f "$AIDC_ROOT/.local/active-profile"
  code_task
  assert_failure
  assert_output_contains "profiles/"
  assert_output_contains "demo"
}

@test "profile:remove rejects invalid names and touches nothing" {
  new demo
  for bad in '../x' 'Bad/Name' ''; do
    before="$(snapshot)"
    : >"$CALLS"
    remove "$bad"
    assert_failure
    [ "$(snapshot)" = "$before" ]
    [ ! -s "$CALLS" ]
  done
}

@test "profile:remove tears down a profile via compose, keeps state, and is idempotent via the label" {
  new demo
  code_task demo
  assert_success
  : >"$CALLS"

  # First run: .local/demo still exists, so the compose-down branch runs.
  remove demo
  assert_success
  grep -q "^docker compose -p aidc-demo down\$" "$CALLS"
  ! grep -q "^docker ps -aq" "$CALLS"
  grep -q "^docker volume inspect aidc-tools-demo\$" "$CALLS"
  grep -q "^docker volume rm aidc-tools-demo\$" "$CALLS"
  ! grep -q "volume rm aidc-claude" "$CALLS"
  ! grep -q "volume rm aidc-codex" "$CALLS"
  ! grep -q "volume rm aidc-shell" "$CALLS"
  [ ! -d "$AIDC_ROOT/.local/demo" ]
  [ ! -f "$AIDC_ROOT/.local/active-profile" ]
  [ -d "$AIDC_ROOT/profiles/demo" ]
  [ -d "$AIDC_ROOT/projects/demo" ]

  # Second run: .local/demo is gone, so removal is by label, never a bare
  # 'compose down' that could pick up a stray file or exported COMPOSE_FILE.
  : >"$CALLS"
  remove demo
  assert_success
  ! grep -q "^docker compose" "$CALLS"
  grep -q "^docker ps -aq --filter label=com.docker.compose.project=aidc-demo\$" "$CALLS"
  grep -q "^docker rm -f cid-demo\$" "$CALLS"
  # The stub fails 'network rm' (simulating an already-removed network);
  # the task tolerates it and still exits 0.
  grep -q "^docker network rm aidc-demo_default\$" "$CALLS"
}

@test "a failing docker volume rm makes profile:remove exit non-zero and keep the generated files" {
  new demo
  code_task demo
  assert_success
  : >"$CALLS"

  export STUB_DOCKER_VOLUME_RM_FAIL=1
  remove demo
  unset STUB_DOCKER_VOLUME_RM_FAIL
  assert_failure
  grep -q "^docker volume rm aidc-tools-demo\$" "$CALLS"
  [ -d "$AIDC_ROOT/.local/demo" ]
  [ "$(cat "$AIDC_ROOT/.local/active-profile")" = demo ]
}

@test "a failing docker compose down aborts before .local/<p> is removed" {
  new demo
  code_task demo
  assert_success
  : >"$CALLS"

  export STUB_DOCKER_COMPOSE_DOWN_FAIL=1
  remove demo
  unset STUB_DOCKER_COMPOSE_DOWN_FAIL
  assert_failure
  ! grep -q "^docker volume rm" "$CALLS"
  [ -d "$AIDC_ROOT/.local/demo" ]
  [ "$(cat "$AIDC_ROOT/.local/active-profile")" = demo ]
}

@test "mise registers the three profile tasks" {
  run mise --cd "$AIDC_ROOT" tasks ls
  assert_success
  assert_output_contains "profile:new"
  assert_output_contains "profile:code"
  assert_output_contains "profile:remove"
}
