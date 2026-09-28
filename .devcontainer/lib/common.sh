#!/usr/bin/env bash
# Container library entry point. Sets no shell options; entry points do.

# shellcheck disable=SC2034 # used by scripts that source this file
AIDC_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

aidc::die() {
  printf 'aidc: %s\n' "$*" >&2
  exit 1
}

aidc::warn() {
  printf 'aidc: warning: %s\n' "$*" >&2
}

aidc::info() {
  printf '%s\n' "$*"
}
