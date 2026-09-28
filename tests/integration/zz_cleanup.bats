#!/usr/bin/env bats
# Runs last in a full integration run (`bats --recursive` sorts full paths,
# so it follows every other tests/integration/*.bats). Every resource this
# suite creates is tracked and removed by the file or test that created it
# (tests/helpers/integration.bash aidc_it_cleanup); this is a safety net that
# only lists and asserts, never deletes by pattern. The workspace image is
# outside cleanup and is not touched here. Parallel runs (`bats --jobs`) are
# unsupported: they would make this check meaningless.
load ../helpers/integration
bats_require_minimum_version 1.5.0

@test "no container or volume of this run is left behind" {
  run aidc_it_run
  assert_success
  local id="$output"

  run docker ps -aq --filter "name=-${id}-"
  assert_success
  [ -z "$output" ]

  run docker volume ls -q --filter "name=-${id}-"
  assert_success
  [ -z "$output" ]
}
