#!/usr/bin/env bash
# Isolates mise from any environment- or profile-inherited MISE_* variables
# before the container's mise runs. Sets no shell options.

AIDC_MISE_DATA_DIR=/opt/aidc/tools/mise
AIDC_MISE_GLOBAL_CONFIG_FILE=/opt/aidc/tools/mise.toml

# The documented `aidc:sync` invocation (TD §2, §3.6): the neutral directory
# is chosen before any configuration loads, and disabling auto-install keeps
# it from bypassing the tools lock. A single constant, used by both
# launchers, so a later change (e.g. after Task 4's probes) is one line.
# shellcheck disable=SC2034 # used by scripts that source this file
AIDC_SYNC_INVOCATION="MISE_TASK_RUN_AUTO_INSTALL=false mise -C / run aidc:sync"

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
