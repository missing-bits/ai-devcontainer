#!/usr/bin/env bash
# Codex CLI launcher support. Sets no shell options.
# shellcheck disable=SC2034

# Every table below matches Codex 0.158.0's `--help` output (`codex --help`,
# `codex resume --help`, `codex fork --help`, `codex app-server --help`).
# Re-verify them when `.devcontainer/mise.toml` moves `aqua:openai/codex` to
# a materially newer minor version; there is no runtime version guard, so a
# mismatch is an accepted risk rather than a refusal.

# Every command and alias `codex --help` lists.
AIDC_CODEX_COMMANDS=(
  agents exec e review login logout mcp plugin app-server remote-control
  completion update doctor sandbox debug apply a resume queue archive delete
  migrate-rollouts unarchive fork cloud exec-server features help
)

# Root options that take exactly one value.
AIDC_CODEX_VALUE_OPTIONS=(
  -c --config --enable --disable --remote --remote-auth-token-env
  -m --model --local-provider -p --profile -s --sandbox -C --cd --add-dir
  -a --ask-for-approval
)

# Options marked `<...>...`, which take one or more values and so swallow
# the words that follow them (root, `resume`, and `fork` alike).
AIDC_CODEX_MULTI_VALUE_OPTIONS=(-i --image)

# Options of `resume` and of `fork` that take exactly one value; the two
# commands differ only in `resume --include-non-interactive`, which takes none.
AIDC_CODEX_RESUME_VALUE_OPTIONS=(
  -c --config --enable --disable --remote --remote-auth-token-env
  -m --model --local-provider -p --profile -s --sandbox -C --cd --add-dir
  -a --ask-for-approval
)

# Options of `app-server` that take exactly one value.
AIDC_CODEX_APP_SERVER_VALUE_OPTIONS=(
  -c --config --enable --disable --code-mode-host --listen --ws-auth
  --ws-token-file --ws-token-sha256 --ws-shared-secret-file --ws-issuer
  --ws-audience --ws-max-clock-skew-seconds
)
