#!/usr/bin/env bash
# Isolates mise from any environment- or profile-inherited MISE_* variables
# before the container's mise runs. Sets no shell options.

AIDC_MISE_DATA_DIR=/opt/aidc/tools/mise
AIDC_MISE_GLOBAL_CONFIG_FILE=/opt/aidc/tools/mise.toml
# Downloads go to the volume every profile shares; the rest of mise's cache
# stays in the profile's tools volume (container sudo/mise/trust spec, D5).
AIDC_MISE_DOWNLOADS_DIR=/opt/aidc/downloads
AIDC_MISE_CACHE_DIR=/opt/aidc/tools/cache

aidc::mise_isolate() {
  local var

  while IFS= read -r var; do
    [ -n "$var" ] || continue
    unset "$var"
  done < <(compgen -e MISE_ || true)

  export MISE_DATA_DIR="$AIDC_MISE_DATA_DIR"
  export MISE_GLOBAL_CONFIG_FILE="$AIDC_MISE_GLOBAL_CONFIG_FILE"
  export MISE_DOWNLOADS_DIR="$AIDC_MISE_DOWNLOADS_DIR"
  export MISE_ALWAYS_KEEP_DOWNLOAD=1
  export MISE_CACHE_DIR="$AIDC_MISE_CACHE_DIR"
  cd / || return 1
}
