#!/usr/bin/env bash
# The naming rule for environment, agent state, and shell history profiles
# (TD SS3.1). Sourced by host tasks. Sets no shell options.

aidc::valid_name() {
  local name="${1-}"
  [[ "$name" =~ ^[a-z0-9][a-z0-9_-]*$ ]] || return 1
  case "$name" in
  locks | active-profile) return 1 ;;
  esac
}

aidc::require_name() {
  local kind="$1" name="${2-}"
  if ! aidc::valid_name "$name"; then
    printf "aidc: invalid %s name '%s': use lowercase letters, digits, '-' and '_', starting with a letter or digit, and not 'locks' or 'active-profile'\n" \
      "$kind" "$name" >&2
    exit 2
  fi
}
