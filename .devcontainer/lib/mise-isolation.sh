#!/usr/bin/env bash
# Isolates mise from any environment- or profile-inherited MISE_* variables
# before the container's mise runs. Sets no shell options.

AIDC_MISE_DATA_DIR=/opt/aidc/tools/mise
AIDC_MISE_GLOBAL_CONFIG_FILE=/opt/aidc/tools/mise.toml

aidc::mise_isolate() {
  local var

  while IFS= read -r var; do
    [ -n "$var" ] || continue
    unset "$var"
  done < <(compgen -e MISE_ || true)

  export MISE_DATA_DIR="$AIDC_MISE_DATA_DIR"
  export MISE_GLOBAL_CONFIG_FILE="$AIDC_MISE_GLOBAL_CONFIG_FILE"
  cd / || return 1
}
