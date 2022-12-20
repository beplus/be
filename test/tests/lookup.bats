#!/usr/bin/env bats

load shared-functions
load '../../node_modules/bats-support/load'
load '../../node_modules/bats-assert/load'


function setup() {
  unset_n_env
}


@test "be --stable" {
  output="$(be --stable)"
  local expected_version
  expected_version="$(display_remote_version stable)"
  expected_version="${expected_version#v}"
  assert_equal "${output}" "${expected_version}"
}


@test "be --latest" {
  output="$(be --latest)"
  local expected_version
  expected_version="$(display_remote_version latest)"
  expected_version="${expected_version#v}"
  assert_equal "${output}" "${expected_version}"
}
