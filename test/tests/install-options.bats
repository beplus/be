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


@test "be --download 0.22.0" {
  be --download 0.22.0
  [ -d "${BE_PREFIX}/be/versions/beplus/0.22.0" ]
  [ ! -f "${BE_PREFIX}/bin/beplus" ]
}


@test "be --quiet 0.22.0" {
  # just checking option is allowed, not testing functionality
  be --quiet 0.22.0
  output="$(beplus --version)"
  assert_equal "${output}" "0.22.0"
}


# variations with i/install and latest/numeric
@test "version variations # (2 installs)" {
  local VERSION="0.22.0"
  local LATEST_VERSION="$(display_remote_version latest)"

  be v${VERSION}
  output="$("${BE_PREFIX}/bin/beplus" --version)"
  assert_equal "${output}" "${VERSION}"

  be "${LATEST_VERSION}"
  output="$("${BE_PREFIX}/bin/beplus" --version)"
  assert_equal "${output}" "${LATEST_VERSION}"
}
