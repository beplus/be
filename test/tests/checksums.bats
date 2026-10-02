#!/usr/bin/env bats
#
# be extracts a download only when it matches its line in the SHA256SUMS the beplus CLI release
# publishes beside its tarballs. These install from a local mirror laid out like the release.

load shared-functions
load '../../node_modules/bats-support/load'
load '../../node_modules/bats-assert/load'


function setup() {
  unset_n_env
  setup_tmp_prefix
  setup_tmp_mirror 2.7.0
  RELEASE="${TMP_MIRROR_DIR}/v2.7.0"
  TARBALL="beplus-cli-v2.7.0-$(tarball_platform).tar.gz"
  CACHED="${BE_PREFIX}/be/versions/beplus/2.7.0"
}


function teardown() {
  rm -rf "${TMP_PREFIX_DIR}" "${TMP_MIRROR_DIR}"
}


@test "a download that matches SHA256SUMS is installed, and its tarball removed" {
  be 2.7.0
  output="$(beplus --version | cli_version)"
  assert_equal "${output}" "2.7.0"
  [ ! -e "${CACHED}/${TARBALL}" ]
  [ ! -e "${CACHED}/be.lock" ]
}


@test "a download that matches a v1-style SHA256SUMS line is installed" {
  # v1.0.5 published `<name>: <hash>` lines, without a trailing newline.
  printf '%s: %s' "${TARBALL}" "$(cut -d ' ' -f 1 "${RELEASE}/SHA256SUMS")" > "${RELEASE}/SHA256SUMS"

  be 2.7.0
  output="$(beplus --version | cli_version)"
  assert_equal "${output}" "2.7.0"
}


@test "a download that does not match SHA256SUMS is not extracted" {
  echo "0000000000000000000000000000000000000000000000000000000000000000  ${TARBALL}" > "${RELEASE}/SHA256SUMS"

  run be 2.7.0
  assert_failure
  assert_output --partial "checksum mismatch for ${BE_MIRROR}/v2.7.0/${TARBALL}"
  [ ! -e "${CACHED}/beplus" ]
  [ ! -e "${CACHED}/${TARBALL}" ]
  # Like a half-finished download, so the next install downloads it again.
  [ -e "${CACHED}/be.lock" ]
  [ ! -e "${BE_PREFIX}/bin/beplus" ]
}


@test "a download SHA256SUMS has no line for is not extracted" {
  # The right checksum, but listed under another platform's tarball only.
  echo "$(cut -d ' ' -f 1 "${RELEASE}/SHA256SUMS")  beplus-cli-v2.7.0-aix-ppc64.tar.gz" > "${RELEASE}/SHA256SUMS"

  run be 2.7.0
  assert_failure
  assert_output --partial "no checksum for ${TARBALL} in ${BE_MIRROR}/v2.7.0/SHA256SUMS"
  [ ! -e "${CACHED}/beplus" ]
  [ ! -e "${BE_PREFIX}/bin/beplus" ]
}


@test "a release without SHA256SUMS is not extracted" {
  rm "${RELEASE}/SHA256SUMS"

  run be 2.7.0
  assert_failure
  assert_output --partial "failed to download SHA256SUMS for 2.7.0 (${BE_MIRROR}/v2.7.0/SHA256SUMS)"
  [ ! -e "${CACHED}/beplus" ]
  [ ! -e "${BE_PREFIX}/bin/beplus" ]
}
