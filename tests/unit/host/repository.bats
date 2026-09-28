#!/usr/bin/env bats
load ../../helpers/common

@test "git check-ignore covers profiles, projects and .local" {
  for path in profiles/x/profile.env projects/x/a .local/x/compose.yaml; do
    run git -C "$AIDC_SOURCE_ROOT" check-ignore -q "$path"
    assert_success
  done
}

@test "the image context holds none of the private directories" {
  local compose="$AIDC_SOURCE_ROOT/.devcontainer/docker-compose.yaml"
  if [ -f "$compose" ]; then
    run grep -A2 '^ *build:' "$compose"
    assert_output_contains "context: ."
  fi
  for path in profiles projects .local; do
    [ ! -e "$AIDC_SOURCE_ROOT/.devcontainer/$path" ]
  done
}

@test "host tools are pinned" {
  run mise config get --file "$AIDC_SOURCE_ROOT/mise.toml" tools
  assert_success
  local versions
  versions="$(grep -oE '"[^"]*"$' <<<"$output" | tr -d '"')"
  [ -n "$versions" ]
  run grep -vE '^[0-9]+\.[0-9]+\.[0-9]+$' <<<"$versions"
  assert_failure
}
