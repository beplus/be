#!/usr/bin/env bats
#
# A download that fails in a way the next attempt may not, such as the 504 GitHub answers now and
# then, is tried again, up to BE_DOWNLOAD_ATTEMPTS attempts in all, the first retry waiting
# BE_DOWNLOAD_RETRY_DELAY seconds and each later one twice as long. Any other failure, such as a
# 404, is final at once. These run against flaky-mirror.js, which gives each request for a file
# the next answer <file>.plan holds before serving the file, and without waiting unless a test
# sets a delay.

load shared-functions
load '../../node_modules/bats-support/load'
load '../../node_modules/bats-assert/load'


function setup() {
  unset_n_env
  setup_tmp_prefix
  setup_flaky_mirror 2.7.0
  touch "${TMP_MIRROR_DIR}/requests.log"
  export BE_DOWNLOAD_RETRY_DELAY=0
  TARBALL="beplus-cli-v2.7.0-$(tarball_platform).tar.gz"
  TARBALL_PATH="v2.7.0/${TARBALL}"
  SUMS_PATH="v2.7.0/SHA256SUMS"
  CACHED="${BE_PREFIX}/be/versions/beplus/2.7.0"
}


function teardown() {
  stop_flaky_mirror
  rm -rf "${TMP_PREFIX_DIR}" "${TMP_MIRROR_DIR}" "${TMP_SHIM_DIR}"
}


# Synopsis: plan <path> <answer>...
# The answers the mirror gives the next requests for <path> before serving it: a status (504), a
# method and a status (HEAD 503), or drop.
function plan() {
  local path="$1"
  shift
  printf '%s\n' "$@" > "${TMP_MIRROR_DIR}/${path}.plan"
}


# Synopsis: requests <method> <path>
# The statuses the mirror answered the <method> requests for <path> with, in order.
function requests() {
  awk -v method="$1" -v path="/$2" '$1 == method && $2 == path { print $3 }' "${TMP_MIRROR_DIR}/requests.log" \
    | paste -s -d ' ' -
}


# Synopsis: setup_path_without_curl
# A directory linking every command on PATH but curl, to run be with as its PATH, so that it
# downloads with wget.
function setup_path_without_curl() {
  command -v wget > /dev/null || skip "needs wget"
  TMP_SHIM_DIR="$(mktemp -d)"
  local dirs
  local dir
  IFS=':' read -ra dirs <<< "${PATH}"
  for dir in "${dirs[@]}"; do
    # ln links no name twice, so the command first on PATH wins, as in a lookup.
    if [[ -d "${dir}" ]]; then
      ln -s "${dir}"/* "${TMP_SHIM_DIR}/" 2> /dev/null || true
    fi
  done
  rm -f "${TMP_SHIM_DIR}/curl"
}


@test "a tarball download answered with a 504 is tried again, and installed" {
  plan "${TARBALL_PATH}" "GET 504" "GET 504"

  run be 2.7.0
  assert_success
  assert_output --partial "retrying : ${BE_MIRROR}/${TARBALL_PATH} answered HTTP 504; attempt 2 of 5 in 0 seconds"
  assert_output --partial "retrying : ${BE_MIRROR}/${TARBALL_PATH} answered HTTP 504; attempt 3 of 5 in 0 seconds"
  assert_equal "$(requests GET "${TARBALL_PATH}")" "504 504 200"
  assert_equal "$(beplus --version | cli_version)" "2.7.0"
  [ ! -e "${CACHED}/${TARBALL}" ]
}


@test "the preflight, SHA256SUMS and the tarball are each tried again" {
  plan "${TARBALL_PATH}" "HEAD 503" "GET 500"
  plan "${SUMS_PATH}" 502 429 408

  run be 2.7.0
  assert_success
  assert_equal "$(requests HEAD "${TARBALL_PATH}")" "503 200"
  assert_equal "$(requests GET "${SUMS_PATH}")" "502 429 408 200"
  assert_equal "$(requests GET "${TARBALL_PATH}")" "500 200"
  assert_equal "$(beplus --version | cli_version)" "2.7.0"
}


@test "a dropped connection is tried again" {
  plan "${TARBALL_PATH}" "GET drop"

  run be 2.7.0
  assert_success
  assert_output --regexp "retrying : ${BE_MIRROR}/${TARBALL_PATH} failed \((curl exit 52|wget exit 4)\); attempt 2 of 5"
  assert_equal "$(requests GET "${TARBALL_PATH}")" "drop 200"
  assert_equal "$(beplus --version | cli_version)" "2.7.0"
}


@test "a 404 is not tried again" {
  rm "${TMP_MIRROR_DIR}/${SUMS_PATH}"

  run be 2.7.0
  assert_failure
  assert_output --partial "failed to download SHA256SUMS for 2.7.0 (${BE_MIRROR}/${SUMS_PATH})"
  refute_output --partial "retrying"
  assert_equal "$(requests GET "${SUMS_PATH}")" "404"
}


@test "a version the mirror lacks fails its preflight at once" {
  run be 2.8.0
  assert_failure
  assert_output --partial "download preflight failed for '2.8.0'"
  refute_output --partial "retrying"
  assert_equal "$(requests HEAD "v2.8.0/beplus-cli-v2.8.0-$(tarball_platform).tar.gz")" "404"
}


@test "be gives up after BE_DOWNLOAD_ATTEMPTS attempts" {
  export BE_DOWNLOAD_ATTEMPTS=3
  plan "${SUMS_PATH}" 504 504 504 504

  run be 2.7.0
  assert_failure
  assert_output --partial "gave up : ${BE_MIRROR}/${SUMS_PATH} answered HTTP 504 on attempt 3 of 3"
  assert_output --partial "failed to download SHA256SUMS for 2.7.0"
  assert_equal "$(requests GET "${SUMS_PATH}")" "504 504 504"
  [ ! -e "${BE_PREFIX}/bin/beplus" ]
}


@test "a tarball download that fails for good leaves no part of it behind, and a later install works" {
  export BE_DOWNLOAD_ATTEMPTS=2
  plan "${TARBALL_PATH}" "GET drop" "GET 504"

  run be 2.7.0
  assert_failure
  assert_output --partial "failed to download archive for 2.7.0"
  [ ! -e "${CACHED}/${TARBALL}" ]
  [ ! -e "${BE_PREFIX}/bin/beplus" ]

  run be 2.7.0
  assert_success
  assert_equal "$(beplus --version | cli_version)" "2.7.0"
}


@test "BE_DOWNLOAD_ATTEMPTS=1 makes one attempt" {
  export BE_DOWNLOAD_ATTEMPTS=1
  plan "${SUMS_PATH}" 504

  run be 2.7.0
  assert_failure
  refute_output --partial "retrying"
  refute_output --partial "gave up"
  assert_equal "$(requests GET "${SUMS_PATH}")" "504"
}


@test "the wait doubles from BE_DOWNLOAD_RETRY_DELAY" {
  export BE_DOWNLOAD_RETRY_DELAY=1
  plan "${SUMS_PATH}" 504 504

  run be 2.7.0
  assert_success
  assert_line --regexp "attempt 2 of 5 in 1 second$"
  assert_line --regexp "attempt 3 of 5 in 2 seconds$"
}


@test "retries are shown with --quiet too" {
  plan "${SUMS_PATH}" 503

  run be --quiet 2.7.0
  assert_success
  assert_output --partial "retrying : ${BE_MIRROR}/${SUMS_PATH} answered HTTP 503"
}


@test "the release index is tried again, and be --latest outputs only the version" {
  echo '[{"name": "v2.7.0", "tag_name": "v2.7.0", "prerelease": false, "draft": false}]' > "${TMP_MIRROR_DIR}/releases.json"
  plan releases.json 503 drop
  export BE_RELEASE_INDEX_URL="${BE_MIRROR}/releases.json"

  assert_equal "$(be --latest 2> "${TMP_PREFIX_DIR}/stderr")" "2.7.0"
  run cat "${TMP_PREFIX_DIR}/stderr"
  assert_output --partial "retrying : ${BE_MIRROR}/releases.json answered HTTP 503; attempt 2 of 5"
  assert_output --partial "retrying : ${BE_MIRROR}/releases.json failed ("
  assert_equal "$(requests GET releases.json)" "503 drop 200"
}


@test "with wget, a 503, a 504 and a dropped connection are tried again, and a 404 is not" {
  setup_path_without_curl
  plan "${TARBALL_PATH}" "HEAD 503" "GET 504"
  plan "${SUMS_PATH}" drop

  run env PATH="${TMP_SHIM_DIR}" be 2.7.0
  assert_success
  assert_output --partial "retrying : ${BE_MIRROR}/${TARBALL_PATH} answered HTTP 503; attempt 2 of 5"
  assert_output --partial "retrying : ${BE_MIRROR}/${TARBALL_PATH} answered HTTP 504; attempt 2 of 5"
  assert_output --partial "retrying : ${BE_MIRROR}/${SUMS_PATH} failed (wget exit 4); attempt 2 of 5"
  # One request each: wget does not retry them itself as well.
  assert_equal "$(requests HEAD "${TARBALL_PATH}")" "503 200"
  assert_equal "$(requests GET "${SUMS_PATH}")" "drop 200"
  assert_equal "$(requests GET "${TARBALL_PATH}")" "504 200"
  assert_equal "$(beplus --version | cli_version)" "2.7.0"

  run env PATH="${TMP_SHIM_DIR}" be 2.8.0
  assert_failure
  refute_output --partial "retrying"
  assert_equal "$(requests HEAD "v2.8.0/beplus-cli-v2.8.0-$(tarball_platform).tar.gz")" "404"
}


@test "a BE_DOWNLOAD_ATTEMPTS or BE_DOWNLOAD_RETRY_DELAY that is not a whole number is refused" {
  run env BE_DOWNLOAD_ATTEMPTS=0 be 2.7.0
  assert_failure
  assert_output --partial "BE_DOWNLOAD_ATTEMPTS is '0', not a whole number of 1 or more"

  run env BE_DOWNLOAD_RETRY_DELAY=08 be 2.7.0
  assert_failure
  assert_output --partial "BE_DOWNLOAD_RETRY_DELAY is '08', not a whole number of seconds"

  assert_equal "$(cat "${TMP_MIRROR_DIR}/requests.log")" ""
}
