#!/usr/bin/env bats
# `aidc-tools` against a copied tree whose `mise` is a stub: it logs every
# call with its working directory and MISE_* variables, answers
# `config get` and `ls --json` from variables the test sets, and fails the
# calls STUB_FAIL names.
load ../../helpers/common
bats_require_minimum_version 1.5.0

setup() {
  local tree="$BATS_TEST_TMPDIR/tree"
  mkdir -p "$tree" "$BATS_TEST_TMPDIR/bin" "$BATS_TEST_TMPDIR/tools" "$BATS_TEST_TMPDIR/devcontainer"
  cp -R "$AIDC_SOURCE_ROOT/.devcontainer/bin" "$AIDC_SOURCE_ROOT/.devcontainer/lib" "$tree/"
  T="$tree/bin/aidc-tools"

  export STUB_DIR="$BATS_TEST_TMPDIR"
  export AIDC_TOOLS_DIR="$BATS_TEST_TMPDIR/tools"
  export AIDC_DEVCONTAINER_DIR="$BATS_TEST_TMPDIR/devcontainer"
  printf '[tools]\nnew = "1"\n' >"$AIDC_DEVCONTAINER_DIR/mise.toml"

  cat >"$BATS_TEST_TMPDIR/bin/mise" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$STUB_DIR/mise-calls"
printf 'pwd=%s %s\n' "$PWD" "$(compgen -e MISE_ | sort | tr '\n' ' ')" >>"$STUB_DIR/mise-env"
while IFS= read -r pattern; do
  [ -n "$pattern" ] || continue
  [ "$*" != "$pattern" ] || exit 1
done <<<"${STUB_FAIL-}"
case "$1 ${2-}" in
"config get") printf '%s\n' "${STUB_TOOLS-}" ;;
"ls --json") printf '%s\n' "${STUB_LS_JSON:-{\}}" ;;
esac
exit 0
EOF
  for cli in claude codex; do
    printf '#!/bin/sh\nprintf x >>"$STUB_DIR/%s-called"\n' "$cli" >"$BATS_TEST_TMPDIR/bin/$cli"
  done
  printf '#!/bin/sh\nprintf "%%s\\n" "$STUB_ARCH"\n' >"$BATS_TEST_TMPDIR/bin/uname"
  chmod +x "$BATS_TEST_TMPDIR/bin/"*
  export STUB_ARCH=x86_64
  PATH="$BATS_TEST_TMPDIR/bin:$PATH"
  export PATH
  unset STUB_FAIL STUB_TOOLS STUB_LS_JSON
}

teardown() {
  if [ -n "${HOLDER-}" ]; then
    kill "$HOLDER" 2>/dev/null || true
    wait "$HOLDER" 2>/dev/null || true
  fi
}

# assert_calls <call>...: the stub mise received exactly <call>..., in order.
assert_calls() {
  local expected actual
  expected="$(printf '%s\n' "$@")"
  actual="$(cat "$STUB_DIR/mise-calls" 2>/dev/null || true)"
  if [ "$actual" != "$expected" ]; then
    printf 'expected mise calls:\n%s\ngot:\n%s\n' "$expected" "$actual" >&2
    return 1
  fi
}

old_copy() {
  printf '[tools]\nold = "1"\n' >"$AIDC_TOOLS_DIR/mise.toml"
  printf 'old lock\n' >"$AIDC_TOOLS_DIR/mise.lock"
}

@test "start copies when no copy exists, locks when no mise.lock exists, then installs locked" {
  run "$T" start
  assert_success
  cmp "$AIDC_DEVCONTAINER_DIR/mise.toml" "$AIDC_TOOLS_DIR/mise.toml"
  assert_calls "lock --global --platform linux-x64" "install --locked"
}

@test "start locks again when only the copy exists" {
  printf '[tools]\nold = "1"\n' >"$AIDC_TOOLS_DIR/mise.toml"
  run "$T" start
  assert_success
  grep -qx 'old = "1"' "$AIDC_TOOLS_DIR/mise.toml"
  assert_calls "lock --global --platform linux-x64" "install --locked"
}

@test "start with a copy and a lock only installs" {
  old_copy
  run "$T" start
  assert_success
  grep -qx 'old = "1"' "$AIDC_TOOLS_DIR/mise.toml"
  grep -qx 'old lock' "$AIDC_TOOLS_DIR/mise.lock"
  assert_calls "install --locked"
}

@test "sync copies, locks and installs" {
  old_copy
  run "$T" sync
  assert_success
  cmp "$AIDC_DEVCONTAINER_DIR/mise.toml" "$AIDC_TOOLS_DIR/mise.toml"
  assert_calls "lock --global --platform linux-x64" "install --locked"
}

@test "update runs the same then mise upgrade" {
  old_copy
  run "$T" update
  assert_success
  cmp "$AIDC_DEVCONTAINER_DIR/mise.toml" "$AIDC_TOOLS_DIR/mise.toml"
  assert_calls "lock --global --platform linux-x64" "install --locked" "upgrade"
}

@test "start copy copies, then installs locked when mise.lock exists, and never locks" {
  old_copy
  run "$T" start copy
  assert_success
  cmp "$AIDC_DEVCONTAINER_DIR/mise.toml" "$AIDC_TOOLS_DIR/mise.toml"
  grep -qx 'old lock' "$AIDC_TOOLS_DIR/mise.lock"
  assert_calls "install --locked"
}

@test "start copy keeps the copy and fails when the old lock does not cover it" {
  old_copy
  export STUB_FAIL="install --locked"
  run "$T" start copy
  assert_status 1
  cmp "$AIDC_DEVCONTAINER_DIR/mise.toml" "$AIDC_TOOLS_DIR/mise.toml"
  assert_calls "install --locked" "config get --file $AIDC_TOOLS_DIR/mise.toml tools" "ls --json"
}

@test "start copy without mise.lock runs plain mise install, never locks, and fails" {
  run "$T" start copy
  assert_status 1
  cmp "$AIDC_DEVCONTAINER_DIR/mise.toml" "$AIDC_TOOLS_DIR/mise.toml"
  assert_output_contains "no mise.lock"
  assert_calls "install" "config get --file $AIDC_TOOLS_DIR/mise.toml tools" "ls --json"
}

@test "start copy takes the tools lock" {
  old_copy
  flock "$AIDC_TOOLS_DIR/.lock" sleep 30 &
  HOLDER=$!
  wait_for_lock_held "$AIDC_TOOLS_DIR/.lock"
  run timeout 1 "$T" start copy
  assert_status 124
  [ ! -e "$STUB_DIR/mise-calls" ]
}

@test "self-update updates the mise binary only, without the tools lock" {
  flock "$AIDC_TOOLS_DIR/.lock" sleep 30 &
  HOLDER=$!
  wait_for_lock_held "$AIDC_TOOLS_DIR/.lock"
  run timeout 5 "$T" self-update
  assert_success
  assert_calls "self-update -y --no-plugins"
}

@test "a failing self-update exits non-zero" {
  export STUB_FAIL="self-update -y --no-plugins"
  run "$T" self-update
  assert_failure
  assert_output_contains "aidc-tools self-update failed"
}

@test "the copy is readable by everyone" {
  run "$T" sync
  assert_success
  [ "$(stat -c %a "$AIDC_TOOLS_DIR/mise.toml")" = 644 ]
}

@test "an interrupted copy leaves the old file" {
  old_copy
  printf '#!/bin/sh\nexit 1\n' >"$BATS_TEST_TMPDIR/bin/mv"
  chmod +x "$BATS_TEST_TMPDIR/bin/mv"
  run "$T" sync
  assert_failure
  grep -qx 'old = "1"' "$AIDC_TOOLS_DIR/mise.toml"
  [ "$(find "$AIDC_TOOLS_DIR" -mindepth 1 -not -name .lock -printf '%f\n' | sort | tr '\n' ' ')" = "mise.lock mise.toml " ]
  assert_calls
}

@test "a failing install exits non-zero and names the failed tools" {
  old_copy
  export STUB_FAIL="install --locked"
  export STUB_TOOLS='"aqua:good/tool" = "1"
"aqua:bad/tool" = "latest"'
  export STUB_LS_JSON='{"aqua:good/tool":[{"version":"1.2.3","installed":true,"active":true}],
"aqua:bad/tool":[{"version":"9.9.9","installed":false,"active":true}]}'
  run "$T" sync
  assert_status 1
  assert_output_contains "not installed: aqua:bad/tool"
  refute_output_contains "aqua:good/tool"
  # One install request covers every declared tool.
  [ "$(grep -c '^install' "$STUB_DIR/mise-calls")" -eq 1 ]
}

@test "a failing mise lock --global falls back to plain mise install" {
  old_copy
  export STUB_FAIL="lock --global --platform linux-x64"
  run "$T" sync
  assert_status 1
  assert_output_contains "mise lock --global failed"
  assert_calls "lock --global --platform linux-x64" "install" "config get --file $AIDC_TOOLS_DIR/mise.toml tools" "ls --json"
}

@test "the lock covers the container platform only" {
  local arch expected
  for arch in x86_64:linux-x64 amd64:linux-x64 aarch64:linux-arm64 arm64:linux-arm64; do
    rm -f "$STUB_DIR/mise-calls"
    STUB_ARCH="${arch%%:*}" run "$T" sync
    assert_success
    expected="${arch#*:}"
    assert_calls "lock --global --platform $expected" "install --locked"
  done
}

@test "an unknown architecture skips the lock and falls back to plain mise install" {
  STUB_ARCH=sparc64 run "$T" sync
  assert_status 1
  assert_output_contains "unknown architecture sparc64"
  assert_calls "install" "config get --file $AIDC_TOOLS_DIR/mise.toml tools" "ls --json"
}

@test "update still upgrades after a failing install and exits non-zero" {
  old_copy
  export STUB_FAIL="install --locked"
  run "$T" update
  assert_status 1
  assert_calls "lock --global --platform linux-x64" "install --locked" "upgrade" "config get --file $AIDC_TOOLS_DIR/mise.toml tools" "ls --json"
}

@test "every mise call runs from / with only the five fixed MISE_* variables" {
  export MISE_FOO=bar MISE_TASK_RUN_AUTO_INSTALL=false MISE_TRUSTED_CONFIG_PATHS=/workspaces
  mkdir -p "$BATS_TEST_TMPDIR/work"
  cd "$BATS_TEST_TMPDIR/work"
  old_copy
  for task in start sync update status self-update "start copy"; do
    # shellcheck disable=SC2086 # "start copy" is two arguments
    run "$T" $task
    assert_success
  done
  [ "$(wc -l <"$STUB_DIR/mise-env")" -ge 7 ]
  if grep -vx 'pwd=/ MISE_ALWAYS_KEEP_DOWNLOAD MISE_CACHE_DIR MISE_DATA_DIR MISE_DOWNLOADS_DIR MISE_GLOBAL_CONFIG_FILE ' "$STUB_DIR/mise-env"; then
    return 1
  fi
}

@test "the tools lock is taken" {
  old_copy
  flock "$AIDC_TOOLS_DIR/.lock" sleep 30 &
  HOLDER=$!
  wait_for_lock_held "$AIDC_TOOLS_DIR/.lock"
  run timeout 1 "$T" sync
  assert_status 124
  [ ! -e "$STUB_DIR/mise-calls" ]
}

@test "status reads files only" {
  old_copy
  printf 'failed 2026-09-28T10:00:00Z: tools\n' >"$AIDC_TOOLS_DIR/init.status"
  seq 1 40 | sed 's/^/log line /' >"$AIDC_TOOLS_DIR/init.log"
  export CLAUDE_CONFIG_DIR="$BATS_TEST_TMPDIR/claude" CODEX_HOME="$BATS_TEST_TMPDIR/codex"
  mkdir -p "$CLAUDE_CONFIG_DIR/.aidc" "$CODEX_HOME"
  touch "$CLAUDE_CONFIG_DIR/.aidc/plugins-initialized"
  export STUB_TOOLS='"aqua:anthropics/claude-code" = "latest"
jq = "1.8.1"

["aqua:jdx/usage"]
version = "6"'
  export STUB_LS_JSON='{"jq":[{"version":"1.8.1","installed":true,"active":true}],
"aqua:jdx/usage":[{"version":"6.11.1","installed":true,"active":true}]}'
  # A held tools lock does not block the status report.
  flock "$AIDC_TOOLS_DIR/.lock" sleep 30 &
  HOLDER=$!
  wait_for_lock_held "$AIDC_TOOLS_DIR/.lock"

  run timeout 5 "$T" status
  assert_success
  assert_output_contains "failed 2026-09-28T10:00:00Z: tools"
  assert_output_contains "log line 40"
  refute_output_contains "log line 20
"
  assert_output_contains "aqua:anthropics/claude-code missing"
  assert_output_contains "jq 1.8.1"
  assert_output_contains "aqua:jdx/usage 6.11.1"
  refute_output_contains "version"
  assert_output_contains "claude: initialized"
  assert_output_contains "codex: not initialized"
  [ ! -e "$STUB_DIR/claude-called" ]
  [ ! -e "$STUB_DIR/codex-called" ]
  assert_calls "config get --file $AIDC_TOOLS_DIR/mise.toml tools" "ls --json"
}

@test "status without a copy, a log or a marker still reports" {
  export CLAUDE_CONFIG_DIR="$BATS_TEST_TMPDIR/claude" CODEX_HOME="$BATS_TEST_TMPDIR/codex"
  run "$T" status
  assert_success
  assert_output_contains "no init.status"
  assert_output_contains "no tools config copy"
  assert_output_contains "claude: not initialized"
  assert_calls
}

@test "an unknown task exits non-zero" {
  run "$T" bogus
  assert_failure
  assert_output_contains "usage: aidc-tools start [copy]|sync|update|status|self-update"
}

@test "only start takes the copy argument" {
  run "$T" sync copy
  assert_failure
  assert_output_contains "usage:"
  run "$T" start-copy
  assert_failure
  assert_output_contains "usage:"
}

@test "the container tasks call aidc-tools by absolute path" {
  local file="$AIDC_SOURCE_ROOT/.devcontainer/mise.toml" task
  for task in sync update status; do
    grep -qx "\[tasks.\"aidc:$task\"\]" "$file"
    grep -qx "run = \"/usr/local/lib/aidc/bin/aidc-tools $task\"" "$file"
  done
  grep -qx '"aqua:anthropics/claude-code" = "latest"' "$file"
  grep -qx '"aqua:openai/codex" = "latest"' "$file"
}
