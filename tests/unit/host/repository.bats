#!/usr/bin/env bats
load ../../helpers/common

@test "git check-ignore covers profiles, projects and .local" {
  for path in profiles/x/profile.env projects/x/a .local/x/compose.yaml; do
    run git -C "$AIDC_SOURCE_ROOT" check-ignore -q "$path"
    assert_success
  done
}

@test "the image context holds none of the private directories" {
  local compose="$AIDC_SOURCE_ROOT/.devcontainer/compose.yaml"
  if [ -f "$compose" ]; then
    # Isolate the `workspace` service's own block (from its key to the next
    # sibling key at the same indentation) so the context check cannot match
    # a different service's `build:`.
    run awk '
      /^[[:space:]]*workspace:[[:space:]]*$/ {
        match($0, /^[[:space:]]*/); indent = RLENGTH; found = 1; print; next
      }
      found {
        match($0, /^[[:space:]]*/); cur = RLENGTH
        if ($0 ~ /^[[:space:]]*$/) { print; next }
        if (cur <= indent) { exit }
        print
      }
    ' "$compose"
    assert_success
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
  # The agent CLIs follow latest by developer decision (TD §3.9).
  versions="$(grep -vE '^"aqua:(anthropics/claude-code|openai/codex)"' <<<"$output" |
    grep -oE '"[^"]*"$' | tr -d '"')"
  [ -n "$versions" ]
  run grep -vE '^[0-9]+\.[0-9]+\.[0-9]+$' <<<"$versions"
  assert_failure
}
