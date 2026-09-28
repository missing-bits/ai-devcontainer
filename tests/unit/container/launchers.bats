#!/usr/bin/env bats
# The agent CLI launchers against a copied tree whose `mise` is a stub: it
# answers `mise which <tool>` from a fixture executable that records where it
# ran and prints its arguments one per line.
load ../../helpers/common
load ../../helpers/stub-mise
bats_require_minimum_version 1.5.0

setup() {
  local tree="$BATS_TEST_TMPDIR/tree"
  mkdir -p "$tree" "$BATS_TEST_TMPDIR/bin"
  cp -R "$AIDC_SOURCE_ROOT/.devcontainer/launchers" "$AIDC_SOURCE_ROOT/.devcontainer/lib" "$tree/"
  L="$tree/launchers"

  cat >"$BATS_TEST_TMPDIR/bin/cli" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$PWD" "${STUB_PROBE-unset}" >"$STUB_DIR/ran"
printf '%s\n' "$@"
EOF
  chmod +x "$BATS_TEST_TMPDIR/bin/cli"

  stub_mise
  export STUB_MISE_BIN_claude="$BATS_TEST_TMPDIR/bin/cli"
  export STUB_MISE_BIN_codex="$BATS_TEST_TMPDIR/bin/cli"
  unset STUB_MISE_RC
}

# assert_args <arg>...: the stub executable ran and received exactly <arg>...
assert_args() {
  local expected
  expected="$(printf '%s\n' "$@")"
  assert_success
  if [ "$output" != "$expected" ]; then
    printf 'expected arguments:\n%s\ngot:\n%s\n' "$expected" "$output" >&2
    return 1
  fi
}

# codex_passes <arg>...: codex runs the stub with <arg>... unchanged.
codex_passes() {
  run --separate-stderr "$L/codex" "$@"
  assert_args "$@"
}

assert_not_run() {
  assert_status 1
  [ ! -e "$STUB_DIR/ran" ]
}

daemon_message="needs the managed app-server daemon, which aidc containers do not run"
image_message="codex: write --image=<file> once per file, so the command can be identified"
sync_invocation="MISE_TASK_RUN_AUTO_INSTALL=false mise -C / run aidc:sync"

@test "claude passes its arguments, working directory, and environment unchanged and resolves once" {
  mkdir -p "$BATS_TEST_TMPDIR/work"
  cd "$BATS_TEST_TMPDIR/work"
  STUB_PROBE=kept run --separate-stderr "$L/claude" a "b c"
  assert_args a "b c"
  [ "$(cat "$STUB_DIR/ran")" = "$BATS_TEST_TMPDIR/work
kept" ]
  [ "$(wc -l <"$STUB_DIR/mise-which-claude-calls")" -eq 1 ]
}

@test "each launcher resolves from / with only the two fixed MISE_* variables, whatever the caller's directory" {
  export MISE_FOO=bar
  for launcher in claude codex; do
    mkdir -p "$BATS_TEST_TMPDIR/work"
    cd "$BATS_TEST_TMPDIR/work"
    run --separate-stderr "$L/$launcher"
    assert_success
    local env_file="$STUB_DIR/mise-which-$launcher-env"
    [ -f "$env_file" ]
    grep -qx 'pwd=/' "$env_file"
    [ "$(grep -c '^MISE_' "$env_file")" -eq 2 ]
    grep -qx 'MISE_DATA_DIR' "$env_file"
    grep -qx 'MISE_GLOBAL_CONFIG_FILE' "$env_file"
  done
  unset MISE_FOO
}

@test "no resolved CLI exits non-zero and names the documented aidc:sync invocation" {
  for launcher in claude codex; do
    unset "STUB_MISE_BIN_$launcher"
    run "$L/$launcher"
    assert_not_run
    assert_output_contains "$sync_invocation"
  done
}

@test "codex refuses a multi-value option written as separate words before a positional" {
  run "$L/codex" -i a.png exec hi
  assert_not_run
  assert_output_contains "$image_message"
  run "$L/codex" -i a.png resume
  assert_not_run
  assert_output_contains "$image_message"
}

@test "codex accepts --image=<file> and leaves a command's own options alone" {
  codex_passes --image=a.png exec hi
  codex_passes -ia.png exec hi
  codex_passes exec -i a.png hi
}

@test "codex starts the interactive CLI with --no-daemon" {
  mkdir -p "$BATS_TEST_TMPDIR/work"
  cd "$BATS_TEST_TMPDIR/work"
  STUB_PROBE=kept run --separate-stderr "$L/codex"
  assert_args --no-daemon
  [ "$(cat "$STUB_DIR/ran")" = "$BATS_TEST_TMPDIR/work
kept" ]
  [ "$(wc -l <"$STUB_DIR/mise-which-codex-calls")" -eq 1 ]

  run --separate-stderr "$L/codex" "fix the bug"
  assert_args --no-daemon "fix the bug"
  run --separate-stderr "$L/codex" resume --last
  assert_args resume --no-daemon --last
  run --separate-stderr "$L/codex" -m o3 fork
  assert_args -m o3 fork --no-daemon
  run --separate-stderr "$L/codex" -mo3 fork
  assert_args -mo3 fork --no-daemon
  run --separate-stderr "$L/codex" -- resume
  assert_args --no-daemon -- resume
  run --separate-stderr "$L/codex" -i a.png
  assert_args --no-daemon -i a.png
}

@test "codex passes non-interactive commands through unchanged" {
  codex_passes -c model=x exec hi
  codex_passes --add-dir /x exec hi
  codex_passes e hi
  codex_passes login status
}

@test "codex adds no --no-daemon when --no-daemon or --remote is an option token" {
  codex_passes --no-daemon
  codex_passes --remote ws://x resume
  codex_passes --remote=ws://x
  codex_passes "fix the bug" --remote ws://x
  codex_passes resume --remote ws://x
  codex_passes fork --remote=ws://x
  codex_passes resume --no-daemon
}

@test "codex never reads an option's value or a word after -- as a flag" {
  run --separate-stderr "$L/codex" -c --remote
  assert_args --no-daemon -c --remote
  run --separate-stderr "$L/codex" -- --remote
  assert_args --no-daemon -- --remote
  run --separate-stderr "$L/codex" -c --no-daemon
  assert_args --no-daemon -c --no-daemon
  run --separate-stderr "$L/codex" resume -c --remote
  assert_args resume --no-daemon -c --remote
  run --separate-stderr "$L/codex" resume -- --remote
  assert_args resume --no-daemon -- --remote
}

@test "codex refuses the subcommands that need the managed daemon" {
  local args
  for args in agents remote-control "app-server daemon start" "app-server --listen stdio:// daemon start" \
    "app-server proxy" "-c x=1 app-server -c y=2 proxy --sock /s"; do
    # shellcheck disable=SC2086
    run "$L/codex" $args
    assert_not_run
    assert_output_contains "$daemon_message"
  done
}

@test "codex passes app-server through when daemon is not its subcommand" {
  codex_passes app-server --listen stdio://
  codex_passes app-server --listen daemon
  codex_passes app-server generate-ts --out /x
}

@test "zshrc registers the launcher hook after mise's" {
  command -v zsh >/dev/null 2>&1 || skip "zsh is not installed"

  local launchers="$BATS_TEST_TMPDIR/launchers" project_bin="$BATS_TEST_TMPDIR/project-bin" \
    work="$BATS_TEST_TMPDIR/work"
  mkdir -p "$launchers" "$project_bin" "$work"
  printf '#!/bin/sh\nprintf launcher\\n\n' >"$launchers/claude"
  chmod +x "$launchers/claude"
  printf '#!/bin/sh\nprintf project\\n\n' >"$project_bin/claude"
  chmod +x "$project_bin/claude"

  cat >"$BATS_TEST_TMPDIR/activate.zsh" <<'EOF'
autoload -Uz add-zsh-hook
_stub_mise_hook() { path=("__PROJECT_BIN__" "${(@)path:#__PROJECT_BIN__}") }
add-zsh-hook precmd _stub_mise_hook
add-zsh-hook chpwd _stub_mise_hook
EOF
  sed -i "s#__PROJECT_BIN__#$project_bin#g" "$BATS_TEST_TMPDIR/activate.zsh"

  stub_mise
  export STUB_MISE_ACTIVATE_SCRIPT
  STUB_MISE_ACTIVATE_SCRIPT="$(cat "$BATS_TEST_TMPDIR/activate.zsh")"
  export AIDC_LAUNCHER_DIR="$launchers"

  cat >"$BATS_TEST_TMPDIR/run.zsh" <<EOF
source "$AIDC_SOURCE_ROOT/.devcontainer/shell/zshrc"
cd "$work" || exit 1
print -r -- "CHPWD=\$(command -v claude)"
for f in "\${precmd_functions[@]}"; do "\$f"; done
print -r -- "HISTSIZE=\$HISTSIZE SAVEHIST=\$SAVEHIST"
[[ -o SHARE_HISTORY ]] && print -r -- SHARE_HISTORY=on
command -v claude
EOF

  run --separate-stderr zsh -f "$BATS_TEST_TMPDIR/run.zsh"
  assert_success
  # The chpwd hook alone, fired by the cd above before any precmd ever runs,
  # already resolves to the launcher: dropping its registration in zshrc
  # would leave only the stub's own chpwd hook and fail this line.
  assert_output_contains "CHPWD=$launchers/claude"
  assert_output_contains "HISTSIZE=50000 SAVEHIST=50000"
  assert_output_contains "SHARE_HISTORY=on"
  [ "${lines[-1]}" = "$launchers/claude" ]
}
