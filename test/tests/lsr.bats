#!/usr/bin/env bats

load shared-functions
load '../../node_modules/bats-support/load'
load '../../node_modules/bats-assert/load'


function setup() {
  unset_n_env
}


# labels

@test "be lsr stable" {
  output="$(be lsr stable)"
  assert_equal "${output}" "$(display_remote_version stable)"
}

@test "be ls-remote latest" {
  output="$(be ls-remote latest)"
  assert_equal "${output}" "$(display_remote_version latest)"
}

@test "be list-remote current" {
  output="$(be list-remote current)"
  assert_equal "${output}" "$(display_remote_version latest)"
}
