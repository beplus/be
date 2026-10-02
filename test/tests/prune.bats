#!/usr/bin/env bats
#
# `be prune` removes every downloaded version except the installed one, so it has to recognise
# the installed one: activate copies <cache>/beplus/<version>/beplus to $BE_PREFIX/bin/beplus.

load shared-functions
load '../../node_modules/bats-support/load'
load '../../node_modules/bats-assert/load'


function setup() {
  unset_n_env
  setup_tmp_prefix
  # KISS and make the downloads by hand rather than do actual installs: a stub beplus that
  # prints its version banner, as 2.x does.
  local version
  for version in 2.5.0 2.6.0 2.7.0; do
    mkdir -p "${BE_PREFIX}/be/versions/beplus/${version}"
    printf '#!/bin/sh\necho "beplus CLI v%s"\n' "${version}" > "${BE_PREFIX}/be/versions/beplus/${version}/beplus"
    chmod +x "${BE_PREFIX}/be/versions/beplus/${version}/beplus"
  done
}


function teardown() {
  rm -rf "${TMP_PREFIX_DIR}"
}


@test "be prune keeps the installed version" {
  be 2.6.0

  be prune
  output="$(be ls)"
  assert_equal "${output}" "beplus/2.6.0"
  output="$(beplus --version | cli_version)"
  assert_equal "${output}" "2.6.0"
}
