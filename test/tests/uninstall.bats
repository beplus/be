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


@test "be uninstall (of 0.22.0)" {
  be 0.22.0
  [ -f "${BE_PREFIX}/bin/beplus" ]

  # Check we get all the files if we uninstall and rm cache.
  echo y | be uninstall
  be rm 0.22.0
  output="$(find "${BE_PREFIX}" -not -type d)"
  assert_equal "$output" ""
}


@test "be uninstall (of latest)" {
  be latest
  [ -f "${BE_PREFIX}/bin/beplus" ]

  # Check we get all the files if we uninstall and rm cache.
  echo y | be uninstall
  be rm latest
  output="$(find "${BE_PREFIX}" -not -type d)"
  assert_equal "$output" ""
}
