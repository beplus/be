#!/usr/bin/env bats

load shared-functions
load '../../node_modules/bats-support/load'
load '../../node_modules/bats-assert/load'


function setup() {
  unset_n_env
  setup_tmp_prefix
}


function teardown() {
  rm -rf "${TMP_PREFIX_DIR}"
}


# Testing version permutations in lsr tests

@test "be 0.22.0" {
  be 0.22.0
  output="$(beplus --version)"
  assert_equal "${output}" "0.22.0"
}


@test "be latest" {
  be latest
  output="$(beplus --version)"
  assert_equal "${output}" "$(display_remote_version latest)"
}
