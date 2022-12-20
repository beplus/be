#!/usr/bin/env bats

load shared-functions
load '../../node_modules/bats-support/load'
load '../../node_modules/bats-assert/load'


function setup() {
  unset_n_env
}


@test "install: contents" {
  readonly TARGET_VERSION="0.22.0"
  setup_tmp_prefix

  [ ! -d "${BE_PREFIX}/be/versions" ]

  be ${TARGET_VERSION}

  # Cached version
  [ -d "${BE_PREFIX}/be/versions/beplus/${TARGET_VERSION}" ]
  # beplus
  [ -f "${BE_PREFIX}/bin/beplus" ]

  output="$(beplus --version)"
  assert_equal "${output}" "${TARGET_VERSION}"

  rm -rf "${TMP_PREFIX_DIR}"
}


@test "install: cache prefix" {
  readonly BE_CACHE_PREFIX="$(mktemp -d)"
  readonly TARGET_VERSION="0.22.0"
  setup_tmp_prefix
  export BE_CACHE_PREFIX

  [ ! -d "${BE_CACHE_PREFIX}/be/versions/beplus/${TARGET_VERSION}" ]
  [ ! -d "${BE_PREFIX}/be/versions/beplus/${TARGET_VERSION}" ]

  be ${TARGET_VERSION}

  # Cached version
  [ -d "${BE_CACHE_PREFIX}/be/versions/beplus/${TARGET_VERSION}" ]
  [ ! -d "${BE_PREFIX}/be/versions/beplus/${TARGET_VERSION}" ]

  rm -rf "${TMP_PREFIX_DIR}" "${BE_CACHE_PREFIX}"
}
