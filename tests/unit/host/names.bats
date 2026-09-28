#!/usr/bin/env bats
load ../../helpers/common

setup() {
  aidc_test_repo
  source "$AIDC_ROOT/tasks/host/lib/names.sh"
}

@test "valid names are accepted" {
  aidc::valid_name demo
  aidc::valid_name a-1_b
}

@test "invalid and reserved names are rejected" {
  ! aidc::valid_name "Bad/Name"
  ! aidc::valid_name "-x"
  ! aidc::valid_name ""
  ! aidc::valid_name "Demo"
  ! aidc::valid_name ".."
  ! aidc::valid_name "locks"
  ! aidc::valid_name "active-profile"
}

@test "aidc::require_name exits 2 with a message on an invalid name" {
  run aidc::require_name profile "Bad/Name"
  assert_status 2
  assert_output_contains "invalid profile name"
}

@test "aidc::require_name succeeds silently on a valid name" {
  run aidc::require_name profile "demo"
  assert_success
  [ -z "$output" ]
}
