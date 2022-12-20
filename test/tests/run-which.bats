#!/usr/bin/env bats

load shared-functions
load '../../node_modules/bats-support/load'
load '../../node_modules/bats-assert/load'

function setup_file() {
  unset_n_env
  # fixed directory so can reuse the two installs
  tmpdir="${TMPDIR:-/tmp}"
  export BE_PREFIX="${tmpdir}/be/test/run-which"
  be --download 0.22.0
  be --download latest
  # using "latest" for download tests with run and exec
}

function teardown_file() {
  rm -rf "${BE_PREFIX}"
}

@test "setupAll for run/which/exec # (2 installs)" {
  # Dummy test so setupAll displayed while running first setup
  [ -d "${BE_PREFIX}/be/versions/beplus/0.22.0" ]
}


# be which

@test "be which 0.22.0" {
  output="$(be which 0.22.0)"
  assert_equal "$output" "${BE_PREFIX}/be/versions/beplus/0.22.0/beplus"
}


@test "be which v0.22.0" {
  output="$(be which v0.22.0)"
  assert_equal "$output" "${BE_PREFIX}/be/versions/beplus/0.22.0/beplus"
}

@test "be bin v0.22.0" {
  output="$(be bin v0.22.0)"
  assert_equal "$output" "${BE_PREFIX}/be/versions/beplus/0.22.0/beplus"
}

@test "be which latest" {
  output="$(be which latest)"
  local LATEST_VERSION="$(display_remote_version latest)"
  assert_equal "$output" "${BE_PREFIX}/be/versions/beplus/${LATEST_VERSION}/beplus"
}


# be run

@test "be run 0.22.0" {
  output="$(be run 0.22.0 --version)"
  assert_equal "$output" "0.22.0"
}

@test "be run latest" {
  output="$(be run latest --version)"
  local LATEST_VERSION="$(display_remote_version latest)"
  assert_equal "$output" "${LATEST_VERSION}"
}

@test "be use 0.22.0" {
  output="$(be use 0.22.0 --version)"
  assert_equal "$output" "0.22.0"
}

@test "be as v0.22.0" {
  output="$(be as 0.22.0 --version)"
  assert_equal "$output" "0.22.0"
}

@test "be run --download latest" {
  be rm latest || true
  be run --download latest --version
  output="$(be run latest --version)"
  local LATEST_VERSION="$(display_remote_version latest)"
  assert_equal "$output" "${LATEST_VERSION}"
}


# be exec

@test "be exec v0.22.0 beplus" {
  output="$(be exec v0.22.0 beplus --version)"
  assert_equal "$output" "0.22.0"
}

@test "be exec latest" {
  output="$(be exec latest beplus --version)"
  local LATEST_VERSION="$(display_remote_version latest)"
  assert_equal "$output" "${LATEST_VERSION}"
}
