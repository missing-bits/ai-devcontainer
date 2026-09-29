#!/usr/bin/env bats
# `aidc-entrypoint` against a copied tree whose `aidc-tools` and
# `aidc-plugins` are stubs; the CLIs' resolution is the stub `mise`'s
# `which`, answered from STUB_MISE_BIN_<agent>.
load ../../helpers/common
load ../../helpers/stub-mise
bats_require_minimum_version 1.5.0

setup() {
  local tree="$BATS_TEST_TMPDIR/tree"
  mkdir -p "$tree" "$BATS_TEST_TMPDIR/tools"
  cp -R "$AIDC_SOURCE_ROOT/.devcontainer/bin" "$AIDC_SOURCE_ROOT/.devcontainer/lib" "$tree/"
  E="$tree/bin/aidc-entrypoint"
  export AIDC_TOOLS_DIR="$BATS_TEST_TMPDIR/tools"

  cat >"$tree/bin/aidc-tools" <<'EOF'
#!/usr/bin/env bash
printf 'tools %s\n' "$*" >>"$STUB_DIR/steps"
cat "$AIDC_TOOLS_DIR/init.status" >"$STUB_DIR/status-during-tools"
printf 'tools step output\n'
[ "$*" != "${STUB_TOOLS_FAIL-}" ] || exit 1
exit "${STUB_TOOLS_RC:-0}"
EOF
  cat >"$tree/bin/aidc-plugins" <<'EOF'
#!/usr/bin/env bash
printf 'plugins %s\n' "$*" >>"$STUB_DIR/steps"
[ "$2" != "${STUB_PLUGINS_FAIL-}" ]
EOF
  chmod +x "$tree/bin/aidc-tools" "$tree/bin/aidc-plugins"

  # The network check's curl: logs its arguments; STUB_CURL_RC 0 means a
  # response came back (online), anything else none (offline).
  mkdir -p "$BATS_TEST_TMPDIR/curl-bin"
  cat >"$BATS_TEST_TMPDIR/curl-bin/curl" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$STUB_DIR/curl-calls"
exit "${STUB_CURL_RC:-0}"
EOF
  chmod +x "$BATS_TEST_TMPDIR/curl-bin/curl"
  PATH="$BATS_TEST_TMPDIR/curl-bin:$PATH"

  stub_mise
  export STUB_MISE_BIN_claude=/opt/claude STUB_MISE_BIN_codex=/opt/codex
  unset STUB_TOOLS_RC STUB_TOOLS_FAIL STUB_PLUGINS_FAIL STUB_CURL_RC
  unset AIDC_START_UPDATE_MISE AIDC_START_UPGRADE_TOOLS
}

# assert_marker <state> [<steps>]: init.status holds `<state> <UTC time>`,
# followed by `: <steps>` when <steps> is given.
assert_marker() {
  local expected="^$1 [0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z${2:+: $2}\$"
  if ! grep -qE "$expected" "$AIDC_TOOLS_DIR/init.status"; then
    printf 'expected init.status to match %s, got:\n%s\n' "$expected" "$(cat "$AIDC_TOOLS_DIR/init.status")" >&2
    return 1
  fi
}

assert_steps() {
  local expected
  expected="$(printf '%s\n' "$@")"
  if [ "$(cat "$STUB_DIR/steps")" != "$expected" ]; then
    printf 'expected steps:\n%s\ngot:\n%s\n' "$expected" "$(cat "$STUB_DIR/steps")" >&2
    return 1
  fi
}

run_entrypoint() {
  run --separate-stderr "$E" bash -c 'printf "keep-alive %s\n" "$*"' _ a "b c"
  assert_success
  [ "$output" = "keep-alive a b c" ]
}

@test "entrypoint writes running, then ok, and execs its arguments" {
  run_entrypoint
  grep -qE '^running [0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:]{8}Z$' "$STUB_DIR/status-during-tools"
  assert_marker ok
  assert_steps "tools start" "plugins init claude" "plugins init codex"
  grep -qx 'tools step output' "$AIDC_TOOLS_DIR/init.log"
}

@test "with both start fields off, entrypoint makes no network check and updates nothing" {
  export AIDC_START_UPDATE_MISE=off AIDC_START_UPGRADE_TOOLS=off
  run_entrypoint
  assert_marker ok
  assert_steps "tools start" "plugins init claude" "plugins init codex"
  [ ! -e "$STUB_DIR/curl-calls" ]
}

@test "the network check is one request to api.github.com with a five-second timeout" {
  export AIDC_START_UPDATE_MISE=on AIDC_START_UPGRADE_TOOLS=on
  run_entrypoint
  [ "$(cat "$STUB_DIR/curl-calls")" = "-sS -o /dev/null --max-time 5 https://api.github.com" ]
}

@test "START_UPDATE_MISE online updates mise before the tools step" {
  export AIDC_START_UPDATE_MISE=on
  run_entrypoint
  assert_marker ok
  assert_steps "tools self-update" "tools start" "plugins init claude" "plugins init codex"
}

@test "START_UPGRADE_TOOLS online runs the update path as the tools step" {
  export AIDC_START_UPGRADE_TOOLS=on
  run_entrypoint
  assert_marker ok
  assert_steps "tools update" "plugins init claude" "plugins init codex"
  grep -qx 'aidc: tools step: update' "$AIDC_TOOLS_DIR/init.log"
}

@test "both start fields online: self-update, then the update path" {
  export AIDC_START_UPDATE_MISE=on AIDC_START_UPGRADE_TOOLS=on
  run_entrypoint
  assert_marker ok
  assert_steps "tools self-update" "tools update" "plugins init claude" "plugins init codex"
}

@test "offline, the start fields skip their updates, log it, and add no failure" {
  export AIDC_START_UPDATE_MISE=on AIDC_START_UPGRADE_TOOLS=on STUB_CURL_RC=6
  run_entrypoint
  assert_marker ok
  assert_steps "tools start copy" "plugins init claude" "plugins init codex"
  grep -q 'offline: skipping the mise self-update' "$AIDC_TOOLS_DIR/init.log"
  grep -q 'offline: skipping the tools upgrade' "$AIDC_TOOLS_DIR/init.log"
  grep -qx 'aidc: tools step: start copy' "$AIDC_TOOLS_DIR/init.log"
}

@test "a failed self-update is named mise and the start goes on" {
  export AIDC_START_UPDATE_MISE=on STUB_TOOLS_FAIL=self-update
  run_entrypoint
  assert_marker failed mise
  assert_steps "tools self-update" "tools start" "plugins init claude" "plugins init codex"
}

@test "a failed update path is named tools and the start goes on" {
  export AIDC_START_UPGRADE_TOOLS=on STUB_TOOLS_FAIL=update
  run_entrypoint
  assert_marker failed tools
  assert_steps "tools update" "plugins init claude" "plugins init codex"
}

@test "a failed offline start copy is named tools" {
  export AIDC_START_UPGRADE_TOOLS=on STUB_CURL_RC=28 STUB_TOOLS_FAIL="start copy"
  run_entrypoint
  assert_marker failed tools
}

@test "entrypoint overwrites the init log at every start" {
  printf 'previous start\n' >"$AIDC_TOOLS_DIR/init.log"
  run_entrypoint
  ! grep -q 'previous start' "$AIDC_TOOLS_DIR/init.log"
}

@test "entrypoint writes failed: tools when the tools step fails" {
  export STUB_TOOLS_RC=1
  run_entrypoint
  assert_marker failed tools
  assert_steps "tools start" "plugins init claude" "plugins init codex"
}

@test "entrypoint writes failed: plugins-claude when plugin init fails" {
  export STUB_PLUGINS_FAIL=claude
  run_entrypoint
  assert_marker failed plugins-claude
  assert_steps "tools start" "plugins init claude" "plugins init codex"
}

@test "entrypoint names every failed step" {
  export STUB_TOOLS_RC=1 STUB_PLUGINS_FAIL=codex
  run_entrypoint
  assert_marker failed "tools plugins-codex"
}

@test "entrypoint skips plugin init for an agent whose CLI does not resolve" {
  unset STUB_MISE_BIN_codex
  run_entrypoint
  assert_marker failed plugins-codex
  assert_steps "tools start" "plugins init claude"
  grep -q 'codex is not installed' "$AIDC_TOOLS_DIR/init.log"
}

@test "entrypoint execs its arguments when the tools volume is not writable" {
  export AIDC_TOOLS_DIR="$BATS_TEST_TMPDIR/missing/tools"
  run --separate-stderr "$E" bash -c 'printf "keep-alive\n"'
  assert_success
  # Without a log, the steps' output stays on the container's own streams.
  [ "${lines[-1]}" = "keep-alive" ]
}
