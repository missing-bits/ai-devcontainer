#!/usr/bin/env bats
# `aidc-entrypoint` against a copied tree whose `aidc-tools` and
# `aidc-plugins` are stubs; the launchers' resolution is the stub `mise`'s
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
exit "${STUB_TOOLS_RC:-0}"
EOF
  cat >"$tree/bin/aidc-plugins" <<'EOF'
#!/usr/bin/env bash
printf 'plugins %s\n' "$*" >>"$STUB_DIR/steps"
[ "$2" != "${STUB_PLUGINS_FAIL-}" ]
EOF
  chmod +x "$tree/bin/aidc-tools" "$tree/bin/aidc-plugins"

  stub_mise
  export STUB_MISE_BIN_claude=/opt/claude STUB_MISE_BIN_codex=/opt/codex
  unset STUB_TOOLS_RC STUB_PLUGINS_FAIL
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

@test "entrypoint skips plugin init for an agent whose launcher does not resolve" {
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
