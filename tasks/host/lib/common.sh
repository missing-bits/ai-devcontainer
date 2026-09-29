#!/usr/bin/env bash
# Host library entry point. Sets no shell options; entry points do.

AIDC_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
export AIDC_ROOT

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

# Prints the name of the mise downloads volume every profile shares.
# AIDC_MISE_DOWNLOADS_VOLUME is a test seam: production sets none.
aidc::downloads_volume() {
  printf '%s\n' "${AIDC_MISE_DOWNLOADS_VOLUME:-aidc-mise-downloads}"
}

# Prints the environment profiles under profiles/, one per line; nothing when
# profiles/ is absent or empty.
aidc::list_profiles() {
  local d="$AIDC_ROOT/profiles" entry
  [ -d "$d" ] || return 0
  for entry in "$d"/*/; do
    [ -d "$entry" ] || continue
    basename "$entry"
  done
}

# shellcheck source=names.sh
source "$AIDC_ROOT/tasks/host/lib/names.sh"
