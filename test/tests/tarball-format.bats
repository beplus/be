#!/usr/bin/env bats
#
# The beplus CLI release publishes .tar.gz only, whatever the major version. be used to ask for
# .tar.xz from major 4 on, a rule inherited from Node's downloads, and would have found nothing.

load shared-functions
load '../../node_modules/bats-support/load'
load '../../node_modules/bats-assert/load'


function setup() {
  unset_n_env
  setup_tmp_prefix
  setup_tmp_mirror 4.0.0
}


function teardown() {
  rm -rf "${TMP_PREFIX_DIR}" "${TMP_MIRROR_DIR}"
}


@test "be 4.0.0 downloads the .tar.gz" {
  be 4.0.0
  output="$(beplus --version | cli_version)"
  assert_equal "${output}" "4.0.0"
}
