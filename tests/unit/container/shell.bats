#!/usr/bin/env bats
# The shell integration of the image: /etc/zsh/zshrc and
# /etc/profile.d/aidc-path.sh, against a stub `mise` (no Docker).
load ../../helpers/common
load ../../helpers/stub-mise
bats_require_minimum_version 1.5.0

SHIMS=/opt/aidc/tools/mise/shims

@test "aidc-path.sh puts the mise shims on PATH once, for shells without mise activation" {
  run sh -c "PATH=/usr/bin:/bin; . '$AIDC_SOURCE_ROOT/.devcontainer/shell/aidc-path.sh'; printf '%s\n' \"\$PATH\""
  assert_success
  [ "$output" = "$SHIMS:/usr/bin:/bin" ]
  run sh -c "PATH=$SHIMS:/usr/bin; . '$AIDC_SOURCE_ROOT/.devcontainer/shell/aidc-path.sh'; printf '%s\n' \"\$PATH\""
  [ "$output" = "$SHIMS:/usr/bin" ]
}

@test "the image PATH holds the mise shims and no launcher directory" {
  local f="$AIDC_SOURCE_ROOT/.devcontainer/Dockerfile"
  grep -q -x "ENV PATH=$SHIMS:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" "$f"
  ! grep -q launchers "$f"
  ! grep -q -i launcher "$AIDC_SOURCE_ROOT/.devcontainer/shell/zshrc"
}

@test "zshrc sources a fixture oh-my-zsh and keeps aidc's history settings on top of it" {
  command -v zsh >/dev/null 2>&1 || skip "zsh is not installed"

  local fake_zsh="$BATS_TEST_TMPDIR/oh-my-zsh" home="$BATS_TEST_TMPDIR/home"
  mkdir -p "$fake_zsh" "$home"
  # Stands in for oh-my-zsh: sets its own history options, the way the real
  # oh-my-zsh does, so the test can prove aidc's zshrc overrides them.
  cat >"$fake_zsh/oh-my-zsh.sh" <<'EOF'
HISTSIZE=100
SAVEHIST=100
unsetopt SHARE_HISTORY
OMZ_SOURCED=1
EOF

  stub_mise
  export AIDC_OMZ_DIR="$fake_zsh"
  export HOME="$home"

  cat >"$BATS_TEST_TMPDIR/run.zsh" <<EOF
source "$AIDC_SOURCE_ROOT/.devcontainer/shell/zshrc"
print -r -- "OMZ_SOURCED=\$OMZ_SOURCED THEME=\$ZSH_THEME"
print -r -- "HISTSIZE=\$HISTSIZE SAVEHIST=\$SAVEHIST"
[[ -o SHARE_HISTORY ]] && print -r -- SHARE_HISTORY=on
EOF

  run --separate-stderr zsh -f "$BATS_TEST_TMPDIR/run.zsh"
  assert_success
  assert_output_contains "OMZ_SOURCED=1 THEME=robbyrussell"
  assert_output_contains "HISTSIZE=50000 SAVEHIST=50000"
  assert_output_contains "SHARE_HISTORY=on"
  [ -d "$home/.cache/oh-my-zsh" ]
}

@test "zshrc skips oh-my-zsh cleanly when \$ZSH/oh-my-zsh.sh is absent" {
  command -v zsh >/dev/null 2>&1 || skip "zsh is not installed"

  local empty="$BATS_TEST_TMPDIR/no-omz" home="$BATS_TEST_TMPDIR/home2"
  mkdir -p "$empty" "$home"

  stub_mise
  export AIDC_OMZ_DIR="$empty"
  export HOME="$home"

  cat >"$BATS_TEST_TMPDIR/run2.zsh" <<EOF
source "$AIDC_SOURCE_ROOT/.devcontainer/shell/zshrc"
print -r -- "HISTSIZE=\$HISTSIZE SAVEHIST=\$SAVEHIST"
[[ -o SHARE_HISTORY ]] && print -r -- SHARE_HISTORY=on
EOF

  run --separate-stderr zsh -f "$BATS_TEST_TMPDIR/run2.zsh"
  assert_success
  assert_output_contains "HISTSIZE=50000 SAVEHIST=50000"
  assert_output_contains "SHARE_HISTORY=on"
  [ ! -d "$home/.cache/oh-my-zsh" ]
}
