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


@test "be ls # just plain beplus" {
  # KISS and just make folders rather than do actual installs
  mkdir -p "${BE_PREFIX}/be/versions/beplus/0.17.0"
  mkdir -p "${BE_PREFIX}/be/versions/beplus/0.22.0"

  output="$(be ls)"
  assert_equal "${output}" "beplus/0.17.0
beplus/0.22.0"
}
