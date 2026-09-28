#!/usr/bin/env bats
# Runs first in a full integration run (`bats --recursive` sorts full paths,
# so this file precedes every other tests/integration/*.bats and
# zz_cleanup.bats follows them all). Computes this run's id, refuses to start
# on a collision with an existing Docker resource, and builds
# aidc-workspace:local once for the whole run, so every later file's first
# start already has the image and no test rebuilds it. The image is outside
# cleanup: zz_cleanup.bats does not remove it. Parallel runs (`bats --jobs`)
# are unsupported: they break this order.
load ../helpers/integration
bats_require_minimum_version 1.5.0

@test "compute the run id and build the workspace image once" {
  run aidc_it_run
  assert_success
  [[ "$output" =~ ^it[a-z0-9]+$ ]]

  run aidc_it_ensure_image
  assert_success
  run docker image inspect aidc-workspace:local
  assert_success
}
