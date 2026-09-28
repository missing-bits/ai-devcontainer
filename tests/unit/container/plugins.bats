#!/usr/bin/env bats
# `aidc-plugins init <agent>` against a copied tree whose launchers are stub
# CLIs. The stubs serve their listings from files under $STUB_DIR, seeded
# empty or from the recorded fixtures, log every call to $STUB_DIR/calls,
# and add what a successful `add` or `install` would list, so a retry sees
# the earlier run's work. STUB_FAIL names one argument whose command fails.
load ../../helpers/common
bats_require_minimum_version 1.5.0

FIXTURES="$AIDC_SOURCE_ROOT/tests/fixtures/plugins"

setup() {
  local tree="$BATS_TEST_TMPDIR/tree"
  mkdir -p "$tree/launchers" "$BATS_TEST_TMPDIR/devcontainer" \
    "$BATS_TEST_TMPDIR/claude-state" "$BATS_TEST_TMPDIR/codex-state"
  cp -R "$AIDC_SOURCE_ROOT/.devcontainer/bin" "$AIDC_SOURCE_ROOT/.devcontainer/lib" "$tree/"
  cp "$AIDC_SOURCE_ROOT/.devcontainer/plugins.json" "$BATS_TEST_TMPDIR/devcontainer/"
  P="$tree/bin/aidc-plugins"
  export AIDC_DEVCONTAINER_DIR="$BATS_TEST_TMPDIR/devcontainer"
  export CLAUDE_CONFIG_DIR="$BATS_TEST_TMPDIR/claude-state"
  export CODEX_HOME="$BATS_TEST_TMPDIR/codex-state"
  export STUB_DIR="$BATS_TEST_TMPDIR"
  unset STUB_FAIL
  printf '[]\n' >"$STUB_DIR/claude-marketplaces.json"
  printf '[]\n' >"$STUB_DIR/claude-plugins.json"
  printf '{"marketplaces": []}\n' >"$STUB_DIR/codex-marketplaces.json"
  printf '{"installed": [], "available": []}\n' >"$STUB_DIR/codex-plugins.json"
  : >"$STUB_DIR/calls"

  cat >"$tree/launchers/claude" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'claude %s\n' "$*" >>"$STUB_DIR/calls"
m="$STUB_DIR/claude-marketplaces.json" p="$STUB_DIR/claude-plugins.json"
fail() { [ "$1" = "${STUB_FAIL-}" ] && { printf 'stub failure: %s\n' "$1" >&2; exit 1; }; return 0; }
add() { jq "$2" "$1" >"$1.new" && mv "$1.new" "$1"; }
case "$*" in
"plugin marketplace list --json") cat "$m" ;;
"plugin list --json") cat "$p" ;;
"plugin marketplace add "*" --scope user") fail "$4"; add "$m" ". + [{name: \"x\", source: \"github\", repo: \"$4\"}]" ;;
"plugin install "*" --scope user") fail "$3"; add "$p" ". + [{id: \"$3\", enabled: true}]" ;;
*) exit 2 ;;
esac
EOF
  cat >"$tree/launchers/codex" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'codex %s\n' "$*" >>"$STUB_DIR/calls"
printf 'WARNING: stub noise on stderr\n' >&2
m="$STUB_DIR/codex-marketplaces.json" p="$STUB_DIR/codex-plugins.json"
fail() { [ "$1" = "${STUB_FAIL-}" ] && { printf 'stub failure: %s\n' "$1" >&2; exit 1; }; return 0; }
add() { jq "$2" "$1" >"$1.new" && mv "$1.new" "$1"; }
case "$*" in
"plugin marketplace list --json") cat "$m" ;;
"plugin list --json") cat "$p" ;;
"plugin marketplace add "*) fail "$4"; add "$m" ".marketplaces += [{name: \"x\", marketplaceSource: {sourceType: \"git\", source: \"https://github.com/$4.git\"}}]" ;;
"plugin add "*) fail "$3"; add "$p" ".installed += [{pluginId: \"$3\", enabled: true}]" ;;
*) exit 2 ;;
esac
EOF
  chmod +x "$tree/launchers/claude" "$tree/launchers/codex"
}

state_of() {
  if [ "$1" = claude ]; then printf '%s\n' "$CLAUDE_CONFIG_DIR"; else printf '%s\n' "$CODEX_HOME"; fi
}

# changes: the calls other than listings, in order.
changes() {
  grep -v -e ' list --json$' "$STUB_DIR/calls" || true
}

assert_changes() {
  local expected
  expected="$(printf '%s\n' "$@")"
  [ "$#" -gt 0 ] || expected=""
  if [ "$(changes)" != "$expected" ]; then
    printf 'expected changes:\n%s\ngot:\n%s\n' "$expected" "$(changes)" >&2
    return 1
  fi
}

claude_all=(
  "claude plugin marketplace add anthropics/claude-plugins-official --scope user"
  "claude plugin marketplace add obra/superpowers-marketplace --scope user"
  "claude plugin marketplace add missing-bits/claude-plugins --scope user"
  "claude plugin install superpowers@claude-plugins-official --scope user"
  "claude plugin install elements-of-style@superpowers-marketplace --scope user"
  "claude plugin install working-process@missing-bits --scope user"
  "claude plugin install project-memory@missing-bits --scope user"
)
codex_all=(
  "codex plugin marketplace add anthropics/claude-plugins-official"
  "codex plugin marketplace add obra/superpowers-marketplace"
  "codex plugin add superpowers@claude-plugins-official"
  "codex plugin add elements-of-style@superpowers-marketplace"
)

@test "an existing marker stops before any CLI call" {
  for agent in claude codex; do
    mkdir -p "$(state_of "$agent")/.aidc"
    touch "$(state_of "$agent")/.aidc/plugins-initialized"
    run "$P" init "$agent"
    assert_success
  done
  [ ! -s "$STUB_DIR/calls" ]
}

@test "the marker is rechecked after the lock" {
  local aidc="$CLAUDE_CONFIG_DIR/.aidc" pid _
  mkdir -p "$aidc"
  flock "$aidc/lock" bash -c "while [ ! -e '$STUB_DIR/release' ]; do sleep 0.05; done" 3>&- &
  wait_for_lock_held "$aidc/lock"
  "$P" init claude 3>&- &
  pid=$!
  for _ in $(seq 1 100); do
    [ "$(readlink "/proc/$pid/fd/9" 2>/dev/null)" = "$aidc/lock" ] && break
    sleep 0.05
  done
  [ "$(readlink "/proc/$pid/fd/9")" = "$aidc/lock" ]
  touch "$aidc/plugins-initialized"
  touch "$STUB_DIR/release"
  wait "$pid"
  [ ! -s "$STUB_DIR/calls" ]
}

@test "a new state profile gets every catalog marketplace and default, then the marker" {
  run "$P" init claude
  assert_success
  run "$P" init codex
  assert_success
  assert_changes "${claude_all[@]}" "${codex_all[@]}"
  [ -e "$CLAUDE_CONFIG_DIR/.aidc/plugins-initialized" ]
  [ -e "$CODEX_HOME/.aidc/plugins-initialized" ]
}

@test "a listed marketplace is not added again" {
  cp "$FIXTURES/claude-marketplaces.json" "$STUB_DIR/claude-marketplaces.json"
  cp "$FIXTURES/codex-marketplaces.json" "$STUB_DIR/codex-marketplaces.json"
  run "$P" init claude
  assert_success
  run "$P" init codex
  assert_success
  assert_changes "${claude_all[@]:3}" "${codex_all[@]:2}"
}

@test "a listed plugin, disabled included, is not installed again" {
  local agent
  for agent in claude codex; do
    cp "$FIXTURES/$agent-marketplaces.json" "$STUB_DIR/$agent-marketplaces.json"
    cp "$FIXTURES/$agent-plugins.json" "$STUB_DIR/$agent-plugins.json"
  done
  # The fixtures record elements-of-style disabled in both CLIs.
  jq -e '.[] | select(.id == "elements-of-style@superpowers-marketplace") | .enabled == false' \
    "$STUB_DIR/claude-plugins.json"
  jq -e '.installed[] | select(.pluginId == "elements-of-style@superpowers-marketplace") | .enabled == false' \
    "$STUB_DIR/codex-plugins.json"
  run "$P" init claude
  assert_success
  run "$P" init codex
  assert_success
  assert_changes
  [ -e "$CLAUDE_CONFIG_DIR/.aidc/plugins-initialized" ]
  [ -e "$CODEX_HOME/.aidc/plugins-initialized" ]
}

@test "one failing install leaves the marker absent and logs the failure" {
  export STUB_FAIL=working-process@missing-bits
  run "$P" init claude
  assert_failure
  assert_output_contains "claude plugin install working-process@missing-bits --scope user"
  assert_changes "${claude_all[@]}"
  [ ! -e "$CLAUDE_CONFIG_DIR/.aidc/plugins-initialized" ]
}

@test "the retry installs only the missing defaults, then writes the marker" {
  export STUB_FAIL=working-process@missing-bits
  run "$P" init claude
  assert_failure
  unset STUB_FAIL
  : >"$STUB_DIR/calls"
  run "$P" init claude
  assert_success
  assert_changes "claude plugin install working-process@missing-bits --scope user"
  [ -e "$CLAUDE_CONFIG_DIR/.aidc/plugins-initialized" ]
}

@test "a default removed after the marker exists is not reinstalled" {
  run "$P" init codex
  assert_success
  jq '.installed |= map(select(.pluginId != "superpowers@claude-plugins-official"))' \
    "$STUB_DIR/codex-plugins.json" >"$STUB_DIR/removed.json"
  mv "$STUB_DIR/removed.json" "$STUB_DIR/codex-plugins.json"
  : >"$STUB_DIR/calls"
  run "$P" init codex
  assert_success
  [ ! -s "$STUB_DIR/calls" ]
}

@test "a marketplace add failure is reported and the run exits non-zero" {
  export STUB_FAIL=obra/superpowers-marketplace
  run "$P" init codex
  assert_failure
  assert_output_contains "codex plugin marketplace add obra/superpowers-marketplace"
  [ ! -e "$CODEX_HOME/.aidc/plugins-initialized" ]
}

@test "an unknown agent is rejected" {
  run "$P" init other
  assert_failure
  [ ! -s "$STUB_DIR/calls" ]
}
