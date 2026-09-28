#!/usr/bin/env bats
load ../../helpers/common

setup() {
  aidc_test_repo
  unset PROFILE
  STUB_BIN="$BATS_TEST_TMPDIR/bin"
  mkdir -p "$STUB_BIN"
  CALLS="$BATS_TEST_TMPDIR/calls.log"
  : >"$CALLS"
  for cmd in docker devcontainer code; do
    cat >"$STUB_BIN/$cmd" <<STUB
#!/usr/bin/env bash
printf '%s %s\n' "$cmd" "\$*" >>"$CALLS"
exit 0
STUB
    chmod +x "$STUB_BIN/$cmd"
  done
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
  [ "$(grep -c '^docker volume create aidc-' "$CALLS")" = 4 ]
  grep -q "^docker volume create aidc-tools-demo\$" "$CALLS"
  grep -q "^docker volume create aidc-claude-demo\$" "$CALLS"
  grep -q "^docker volume create aidc-codex-demo\$" "$CALLS"
  grep -q "^docker volume create aidc-shell-demo\$" "$CALLS"
  grep -q "^devcontainer up --workspace-folder $AIDC_ROOT/.local/demo\$" "$CALLS"
  grep -q "^code " "$CALLS"
  [ "$(cat "$AIDC_ROOT/.local/active-profile")" = demo ]

  last_volume="$(grep -n '^docker volume create' "$CALLS" | tail -1 | cut -d: -f1)"
  up_line="$(grep -n '^devcontainer up' "$CALLS" | head -1 | cut -d: -f1)"
  code_line="$(grep -n '^code ' "$CALLS" | head -1 | cut -d: -f1)"
  [ "$last_volume" -lt "$up_line" ]
  [ "$up_line" -lt "$code_line" ]
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

@test "profile:remove tears down a profile, keeps state, and is idempotent" {
  new demo
  code_task demo
  assert_success
  : >"$CALLS"

  remove demo
  assert_success
  grep -q "^docker compose -p aidc-demo down\$" "$CALLS"
  grep -q "^docker volume rm aidc-tools-demo\$" "$CALLS"
  ! grep -q "volume rm aidc-claude" "$CALLS"
  ! grep -q "volume rm aidc-codex" "$CALLS"
  ! grep -q "volume rm aidc-shell" "$CALLS"
  [ ! -d "$AIDC_ROOT/.local/demo" ]
  [ ! -f "$AIDC_ROOT/.local/active-profile" ]
  [ -d "$AIDC_ROOT/profiles/demo" ]
  [ -d "$AIDC_ROOT/projects/demo" ]

  : >"$CALLS"
  remove demo
  assert_success
  grep -q "^docker compose -p aidc-demo down\$" "$CALLS"
}

@test "mise registers the three profile tasks" {
  run mise --cd "$AIDC_ROOT" tasks ls
  assert_success
  assert_output_contains "profile:new"
  assert_output_contains "profile:code"
  assert_output_contains "profile:remove"
}
