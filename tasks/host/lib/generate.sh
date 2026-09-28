#!/usr/bin/env bash
# Generator for .local/<p>/: the Compose fragment and devcontainer.json
# (TD SS3.2, SS3.8). Never calls Docker. Sets no shell options. Both files
# are written with jq; JSON is valid YAML, so compose.yaml is written as
# JSON too.

# aidc::_gen_escape <value>: doubles '$' so Compose's own interpolation of
# the fragment reproduces the literal value (TD SS3.1).
aidc::_gen_escape() {
  printf '%s' "${1//\$/\$\$}"
}

aidc::_gen_fail() { # <staging dir> <message>
  [ -z "$1" ] || rm -rf -- "$1"
  aidc::die "$2"
}

# aidc::generate <profile> <out-dir> [<docker-gid>]
# Creates <out-dir>, which must not exist while its parent must, and writes
# <out-dir>/compose.yaml and <out-dir>/.devcontainer/devcontainer.json.
# <docker-gid> is required exactly when the profile's DOCKER_SOCKET is 'on'.
aidc::generate() {
  local profile="${1-}" out="${2-}" gid="${3-}"
  aidc::require_name profile "$profile"
  [ -n "$out" ] || aidc::die "generate: an output directory is required"
  if [ -e "$out" ] || [ -L "$out" ]; then
    aidc::die "generate: $out already exists"
  fi
  [ -d "$(dirname -- "$out")" ] || aidc::die "generate: the parent of $out does not exist"
  aidc::load_profile_env "$profile"
  if [ "$AIDC_DOCKER_SOCKET" = on ]; then
    [[ "$gid" =~ ^[0-9]+$ ]] || aidc::die "generate: profile '$profile' enables the Docker socket: a numeric Docker group ID is required"
  elif [ -n "$gid" ]; then
    aidc::die "generate: profile '$profile' does not enable the Docker socket: no Docker group ID is accepted"
  fi

  local stage vol_tools vol_claude vol_codex vol_shell project workspace uid gidnum
  stage="$(mktemp -d)" || aidc::die "generate: cannot create a staging directory"
  mkdir -- "$stage/.devcontainer" || aidc::_gen_fail "$stage" "generate: cannot create the staging .devcontainer directory"

  vol_tools="aidc-tools-$profile"
  vol_claude="aidc-claude-$AIDC_STATE_CLAUDE"
  vol_codex="aidc-codex-$AIDC_STATE_CODEX"
  vol_shell="aidc-shell-$AIDC_STATE_SHELL"
  project="$AIDC_ROOT/projects/$profile"
  workspace="/workspaces/$profile"
  uid="$(id -u)" || aidc::_gen_fail "$stage" "generate: cannot read the host UID"
  gidnum="$(id -g)" || aidc::_gen_fail "$stage" "generate: cannot read the host GID"

  local socket_flag=false
  [ "$AIDC_DOCKER_SOCKET" = on ] && socket_flag=true

  if ! jq -n \
    --arg name "aidc-$profile" \
    --arg uid "$uid" \
    --arg gid "$gidnum" \
    --arg tools "$vol_tools" \
    --arg claude "$vol_claude" \
    --arg codex "$vol_codex" \
    --arg shell "$vol_shell" \
    --arg project "$project" \
    --arg workspace "$workspace" \
    --argjson sockon "$socket_flag" \
    --arg dgid "$gid" \
    --arg an "$(aidc::_gen_escape "$AIDC_GIT_AUTHOR_NAME")" \
    --arg ae "$(aidc::_gen_escape "$AIDC_GIT_AUTHOR_EMAIL")" \
    --arg cn "$(aidc::_gen_escape "$AIDC_GIT_COMMITTER_NAME")" \
    --arg ce "$(aidc::_gen_escape "$AIDC_GIT_COMMITTER_EMAIL")" \
    --arg sc "$(aidc::_gen_escape "$AIDC_GIT_SSH_COMMAND")" \
    '
    ({GIT_AUTHOR_NAME: $an, GIT_AUTHOR_EMAIL: $ae, GIT_COMMITTER_NAME: $cn,
      GIT_COMMITTER_EMAIL: $ce, GIT_SSH_COMMAND: $sc}
      | with_entries(select(.value != ""))) as $env
    | ([
        {type: "volume", source: $tools, target: "/opt/aidc/tools"},
        {type: "volume", source: $claude, target: "/home/dev/.claude"},
        {type: "volume", source: $codex, target: "/home/dev/.codex"},
        {type: "volume", source: $shell, target: "/home/dev/.local/state/shell"},
        {type: "bind", source: $project, target: $workspace}
      ] + (if $sockon then
            [{type: "bind", source: "/var/run/docker.sock", target: "/var/run/docker.sock"}]
          else [] end)) as $volumes
    | ({build: {args: {USER_UID: $uid, USER_GID: $gid}}, volumes: $volumes}
        + (if ($env | length) > 0 then {environment: $env} else {} end)
        + (if $sockon then {group_add: [$dgid]} else {} end)) as $workspace_svc
    | {
        name: $name,
        services: {workspace: $workspace_svc},
        volumes: {
          ($tools): {external: true},
          ($claude): {external: true},
          ($codex): {external: true},
          ($shell): {external: true}
        }
      }
    ' >"$stage/compose.yaml"; then
    aidc::_gen_fail "$stage" "generate: cannot write compose.yaml"
  fi

  if ! jq -n \
    --arg name "aidc-$profile" \
    --arg shared "$AIDC_ROOT/.devcontainer/compose.yaml" \
    --arg workspace "$workspace" \
    '{
      name: $name,
      dockerComposeFile: [$shared, "../compose.yaml"],
      service: "workspace",
      workspaceFolder: $workspace,
      remoteUser: "dev",
      overrideCommand: false,
      updateRemoteUserUID: false
    }' >"$stage/.devcontainer/devcontainer.json"; then
    aidc::_gen_fail "$stage" "generate: cannot write devcontainer.json"
  fi

  mv -T -- "$stage" "$out" || aidc::_gen_fail "$stage" "generate: cannot write $out"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  set -euo pipefail
  # shellcheck source=common.sh
  source "$(dirname "$0")/common.sh"
  # shellcheck source=profile_env.sh
  source "$AIDC_ROOT/tasks/host/lib/profile_env.sh"
  aidc::generate "$@"
fi
