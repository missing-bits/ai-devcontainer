#!/usr/bin/env bash
# Stub `mise` shared by the container unit tests. It never touches the real
# mise; it answers `which` and `activate zsh` from environment variables the
# test sets, and records what it was called with under $STUB_DIR.

# stub_mise_bin_dir: creates the directory holding the stub `mise`
# executable (once per test) and prints its path.
stub_mise_bin_dir() {
  local dir="$BATS_TEST_TMPDIR/stub-mise-bin"
  if [ ! -x "$dir/mise" ]; then
    mkdir -p "$dir"
    cat >"$dir/mise" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
: "${STUB_DIR:?STUB_DIR must be set}"
case "${1-}" in
which)
  tool="$2"
  {
    printf 'pwd=%s\n' "$PWD"
    compgen -e MISE_ | sort
  } >"$STUB_DIR/mise-which-$tool-env"
  printf 'x\n' >>"$STUB_DIR/mise-which-$tool-calls"
  var="STUB_MISE_BIN_$tool"
  if [ -n "${!var-}" ]; then
    printf '%s\n' "${!var}"
    exit 0
  fi
  exit "${STUB_MISE_RC:-1}"
  ;;
activate)
  # $2 names the shell (zsh); this stub only ever backs the zsh hook-order
  # test, so the shell name itself is not inspected.
  printf '%s\n' "${STUB_MISE_ACTIVATE_SCRIPT-}"
  ;;
*)
  exit 1
  ;;
esac
STUB
    chmod +x "$dir/mise"
  fi
  printf '%s\n' "$dir"
}

# stub_mise: prepends the stub `mise` to PATH and exports STUB_DIR, so a
# launcher under test records its resolution calls into $BATS_TEST_TMPDIR.
stub_mise() {
  local dir
  dir="$(stub_mise_bin_dir)"
  export STUB_DIR="$BATS_TEST_TMPDIR"
  PATH="$dir:$PATH"
  export PATH
}
