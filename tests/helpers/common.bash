#!/usr/bin/env bash
# Shared Bats helpers. Tests never touch the real repository's private paths.
# Bats sets `status` and `output` in the tests that load this file.
# shellcheck disable=SC2154

AIDC_SOURCE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export AIDC_SOURCE_ROOT

# aidc_test_repo [<base-dir>]: copies the repository sources into
# <base-dir>/repo (default $BATS_TEST_TMPDIR). `setup_file` passes
# $BATS_FILE_TMPDIR, because Bats leaves BATS_TEST_TMPDIR unset there.
aidc_test_repo() {
  local repo="${1:-$BATS_TEST_TMPDIR}/repo" item
  mkdir -p "$repo"
  for item in mise.toml .devcontainer examples tasks; do
    if [ -e "$AIDC_SOURCE_ROOT/$item" ]; then
      cp -R "$AIDC_SOURCE_ROOT/$item" "$repo/$item"
    fi
  done
  export AIDC_ROOT="$repo"
  export MISE_TRUSTED_CONFIG_PATHS="$repo"
}

assert_success() {
  if [ "$status" -ne 0 ]; then
    printf 'expected success, got status %s\noutput:\n%s\n' "$status" "$output" >&2
    return 1
  fi
}

assert_failure() {
  if [ "$status" -eq 0 ]; then
    printf 'expected failure, got success\noutput:\n%s\n' "$output" >&2
    return 1
  fi
}

assert_status() {
  if [ "$status" -ne "$1" ]; then
    printf 'expected status %s, got %s\noutput:\n%s\n' "$1" "$status" "$output" >&2
    return 1
  fi
}

assert_output_contains() {
  if [[ "$output" != *"$1"* ]]; then
    printf 'expected output to contain: %s\noutput:\n%s\n' "$1" "$output" >&2
    return 1
  fi
}

refute_output_contains() {
  if [[ "$output" == *"$1"* ]]; then
    printf 'expected output not to contain: %s\noutput:\n%s\n' "$1" "$output" >&2
    return 1
  fi
}

wait_for_lock_held() {
  local file="$1"
  for _ in $(seq 1 50); do
    if ! flock -n "$file" true 2>/dev/null; then
      return 0
    fi
    sleep 0.1
  done
  printf 'lock %s was never taken\n' "$file" >&2
  return 1
}
