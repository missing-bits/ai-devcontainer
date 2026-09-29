#!/usr/bin/env bats
load ../../helpers/common

setup() {
  aidc_test_repo
  source "$AIDC_ROOT/tasks/host/lib/common.sh"
  source "$AIDC_ROOT/tasks/host/lib/profile_env.sh"
  source "$AIDC_ROOT/tasks/host/lib/generate.sh"
  mkdir -p "$AIDC_ROOT/profiles/demo" "$AIDC_ROOT/projects/demo" "$AIDC_ROOT/.local"
  : >"$AIDC_ROOT/profiles/demo/profile.env"
}

@test "the fragment is valid JSON named after the profile" {
  aidc::generate demo "$AIDC_ROOT/.local/demo"
  run jq -e . "$AIDC_ROOT/.local/demo/compose.yaml"
  assert_success
  [ "$(jq -r .name "$AIDC_ROOT/.local/demo/compose.yaml")" = aidc-demo ]
}

@test "the fragment sets the container hostname to the profile name" {
  aidc::generate demo "$AIDC_ROOT/.local/demo"
  local f="$AIDC_ROOT/.local/demo/compose.yaml"
  [ "$(jq -r .services.workspace.hostname "$f")" = demo ]
}

@test "build args equal the host UID and GID" {
  aidc::generate demo "$AIDC_ROOT/.local/demo"
  local f="$AIDC_ROOT/.local/demo/compose.yaml"
  [ "$(jq -r .services.workspace.build.args.USER_UID "$f")" = "$(id -u)" ]
  [ "$(jq -r .services.workspace.build.args.USER_GID "$f")" = "$(id -g)" ]
}

@test "the four state volumes are external and named after the profile" {
  aidc::generate demo "$AIDC_ROOT/.local/demo"
  local f="$AIDC_ROOT/.local/demo/compose.yaml"
  for v in aidc-tools-demo aidc-claude-demo aidc-codex-demo aidc-shell-demo; do
    [ "$(jq -r ".volumes[\"$v\"].external" "$f")" = true ]
  done
}

@test "PROFILE_CLAUDE selects the Claude volume's name" {
  printf 'PROFILE_CLAUDE=team\n' >"$AIDC_ROOT/profiles/demo/profile.env"
  aidc::generate demo "$AIDC_ROOT/.local/demo"
  local f="$AIDC_ROOT/.local/demo/compose.yaml"
  [ "$(jq -r '.volumes | has("aidc-claude-team")' "$f")" = true ]
  [ "$(jq -r '[.services.workspace.volumes[] | select(.target == "/home/vscode/.claude")][0].source' "$f")" = aidc-claude-team ]
}

@test "bind sources are absolute" {
  aidc::generate demo "$AIDC_ROOT/.local/demo"
  local f="$AIDC_ROOT/.local/demo/compose.yaml" src
  src="$(jq -r '.services.workspace.volumes[] | select(.target == "/workspaces/demo") | .source' "$f")"
  [[ "$src" = /* ]]
  [ "$src" = "$AIDC_ROOT/projects/demo" ]
}

@test "a dollar sign in a GIT_* value is written doubled" {
  printf 'GIT_AUTHOR_NAME=a$HOME\n' >"$AIDC_ROOT/profiles/demo/profile.env"
  aidc::generate demo "$AIDC_ROOT/.local/demo"
  [ "$(jq -r .services.workspace.environment.GIT_AUTHOR_NAME "$AIDC_ROOT/.local/demo/compose.yaml")" = 'a$$HOME' ]
}

@test "set GIT_* fields appear as environment, unset ones are absent" {
  printf 'GIT_AUTHOR_NAME=Example Developer\n' >"$AIDC_ROOT/profiles/demo/profile.env"
  aidc::generate demo "$AIDC_ROOT/.local/demo"
  local f="$AIDC_ROOT/.local/demo/compose.yaml"
  [ "$(jq -r '.services.workspace.environment.GIT_AUTHOR_NAME' "$f")" = "Example Developer" ]
  [ "$(jq -r '.services.workspace.environment | has("GIT_AUTHOR_EMAIL")' "$f")" = false ]
}

@test "only the start fields are in the environment when every GIT_* field is unset" {
  aidc::generate demo "$AIDC_ROOT/.local/demo"
  [ "$(jq -c '.services.workspace.environment' "$AIDC_ROOT/.local/demo/compose.yaml")" = '{"AIDC_START_UPDATE_MISE":"off","AIDC_START_UPGRADE_TOOLS":"off"}' ]
}

@test "the start fields reach the container as AIDC_START_*" {
  printf 'START_UPDATE_MISE=on\nSTART_UPGRADE_TOOLS=on\n' >"$AIDC_ROOT/profiles/demo/profile.env"
  aidc::generate demo "$AIDC_ROOT/.local/demo"
  local f="$AIDC_ROOT/.local/demo/compose.yaml"
  [ "$(jq -r .services.workspace.environment.AIDC_START_UPDATE_MISE "$f")" = on ]
  [ "$(jq -r .services.workspace.environment.AIDC_START_UPGRADE_TOOLS "$f")" = on ]
}

@test "the shared mise downloads volume is external and mounted at /opt/aidc/downloads" {
  aidc::generate demo "$AIDC_ROOT/.local/demo"
  local f="$AIDC_ROOT/.local/demo/compose.yaml"
  [ "$(jq -r '.volumes["aidc-mise-downloads"].external' "$f")" = true ]
  [ "$(jq -r '[.services.workspace.volumes[] | select(.target == "/opt/aidc/downloads")][0] | "\(.type) \(.source)"' "$f")" = "volume aidc-mise-downloads" ]
}

@test "AIDC_MISE_DOWNLOADS_VOLUME names the downloads volume" {
  AIDC_MISE_DOWNLOADS_VOLUME=aidc-mise-downloads-it1-x aidc::generate demo "$AIDC_ROOT/.local/demo"
  local f="$AIDC_ROOT/.local/demo/compose.yaml"
  [ "$(jq -r '.volumes | has("aidc-mise-downloads-it1-x")' "$f")" = true ]
  [ "$(jq -r '.volumes | has("aidc-mise-downloads")' "$f")" = false ]
  [ "$(jq -r '[.services.workspace.volumes[] | select(.target == "/opt/aidc/downloads")][0].source' "$f")" = aidc-mise-downloads-it1-x ]
}

@test "the socket bind and group_add appear only with DOCKER_SOCKET=on" {
  aidc::generate demo "$AIDC_ROOT/.local/demo"
  run grep -c docker.sock "$AIDC_ROOT/.local/demo/compose.yaml"
  [ "$output" = 0 ]
  [ "$(jq -r '.services.workspace | has("group_add")' "$AIDC_ROOT/.local/demo/compose.yaml")" = false ]

  printf 'DOCKER_SOCKET=on\n' >"$AIDC_ROOT/profiles/demo/profile.env"
  run aidc::generate demo "$AIDC_ROOT/.local/demo2"
  assert_failure

  aidc::generate demo "$AIDC_ROOT/.local/demo3" 998
  local f="$AIDC_ROOT/.local/demo3/compose.yaml"
  [ "$(jq -r '[.services.workspace.volumes[] | select(.target == "/var/run/docker.sock")] | length' "$f")" = 1 ]
  [ "$(jq -r '.services.workspace.group_add[0]' "$f")" = 998 ]
}

@test "a Docker group ID is refused unless the socket is on" {
  run aidc::generate demo "$AIDC_ROOT/.local/demo" 998
  assert_failure
}

@test "devcontainer.json carries the TD fields with the absolute shared compose path first" {
  aidc::generate demo "$AIDC_ROOT/.local/demo"
  local f="$AIDC_ROOT/.local/demo/.devcontainer/devcontainer.json"
  [ "$(jq -r .name "$f")" = aidc-demo ]
  [ "$(jq -r .service "$f")" = workspace ]
  [ "$(jq -r .workspaceFolder "$f")" = /workspaces/demo ]
  [ "$(jq -r .remoteUser "$f")" = vscode ]
  [ "$(jq -r .overrideCommand "$f")" = false ]
  [ "$(jq -r .updateRemoteUserUID "$f")" = false ]
  [ "$(jq -r '.dockerComposeFile[0]' "$f")" = "$AIDC_ROOT/.devcontainer/compose.yaml" ]
  [ "$(jq -r '.dockerComposeFile[1]' "$f")" = "../compose.yaml" ]
}

@test "an existing out-dir is refused and nothing is deleted" {
  mkdir -p "$AIDC_ROOT/.local/demo/keepme"
  touch "$AIDC_ROOT/.local/demo/keepme/file"
  run aidc::generate demo "$AIDC_ROOT/.local/demo"
  assert_failure
  [ -f "$AIDC_ROOT/.local/demo/keepme/file" ]
}

@test "an invalid profile name is refused" {
  run aidc::generate "Bad/Name" "$AIDC_ROOT/.local/bad"
  assert_failure
  [ ! -e "$AIDC_ROOT/.local/bad" ]
}
