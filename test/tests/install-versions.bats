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

@test "be 2.0.0" {
  be 2.0.0
  output="$(beplus --version | cli_version)"
  assert_equal "${output}" "2.0.0"
}


@test "be latest" {
  be latest
  output="$(beplus --version | cli_version)"
  assert_equal "${output}" "$(display_remote_version latest)"
}
