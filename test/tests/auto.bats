#!/usr/bin/env bats
#
# `be auto` installs exactly the beplus CLI version a repository pins in its beplus.estate.json,
# as "cli": { "version": "x.y.z" }, so that a CLI release cannot change what a deploy runs without
# a commit in that repository. Without a pin it fails, naming the file, rather than falling back to
# the newest release. These run against a local mirror and release index where 2.12.0 is newer
# than the pinned 2.11.0.

load shared-functions
load '../../node_modules/bats-support/load'
load '../../node_modules/bats-assert/load'


function setup() {
  unset_n_env
  setup_tmp_prefix
  setup_tmp_mirror 2.11.0 2.12.0
  cat > "${TMP_MIRROR_DIR}/releases.json" <<'JSON'
[
  {"name": "v2.12.0", "tag_name": "v2.12.0", "prerelease": false, "draft": false},
  {"name": "v2.11.0", "tag_name": "v2.11.0", "prerelease": false, "draft": false}
]
JSON
  export BE_RELEASE_INDEX_URL="file://${TMP_MIRROR_DIR}/releases.json"

  PROJECT="${TMP_PREFIX_DIR}/estate"
  mkdir -p "${PROJECT}/packages/app/src"
  cd "${PROJECT}" || exit 2
}


function teardown() {
  rm -rf "${TMP_PREFIX_DIR}" "${TMP_MIRROR_DIR}" "${TMP_SHIM_DIR}"
}


# Synopsis: write_manifest <cli.version as JSON> [dir]
function write_manifest() {
  printf '{\n  "name": "estate",\n  "cli": { "version": %s }\n}\n' "$1" > "${2:-${PROJECT}}/beplus.estate.json"
}


# Synopsis: setup_shim command...
# A directory holding be, bash and the given commands, and nothing else, to run be with as its PATH.
function setup_shim() {
  TMP_SHIM_DIR="$(mktemp -d)"
  ln -s "$(command -v be)" "${TMP_SHIM_DIR}/be"
  ln -s "$(command -v bash)" "${TMP_SHIM_DIR}/bash"
  local command
  for command in "$@"; do
    ln -s "$(command -v "${command}")" "${TMP_SHIM_DIR}/${command}"
  done
}


@test "be auto installs exactly the version beplus.estate.json pins, not the newest" {
  write_manifest '"2.11.0"'
  cd "${PROJECT}/packages/app/src"
  # The index this runs against offers a newer release.
  assert_equal "$(be --latest)" "2.12.0"

  run be auto
  assert_success
  assert_output --partial "found : ${PROJECT}/beplus.estate.json"
  assert_equal "$(beplus --version | cli_version)" "2.11.0"
  assert_equal "$(be ls)" "beplus/2.11.0"
  assert_equal "$(be which auto 2> /dev/null)" "${BE_PREFIX}/be/versions/beplus/2.11.0/beplus"
  assert_equal "$(be ls-remote auto 2> /dev/null)" "2.11.0"
}


@test "the nearest beplus.estate.json decides" {
  write_manifest '"2.12.0"'
  write_manifest '"2.11.0"' "${PROJECT}/packages/app"
  cd "${PROJECT}/packages/app/src"

  assert_equal "$(be N_TEST_DISPLAY_LATEST_RESOLVED_VERSION auto 2> /dev/null)" "2.11.0"
}


@test "a pin with a leading v, or a pre-release, is still one exact version" {
  write_manifest '"v2.11.0"'
  assert_equal "$(be N_TEST_DISPLAY_LATEST_RESOLVED_VERSION auto 2> /dev/null)" "2.11.0"

  write_manifest '"2.12.0-beta.1"'
  assert_equal "$(be N_TEST_DISPLAY_LATEST_RESOLVED_VERSION auto 2> /dev/null)" "2.12.0-beta.1"
}


@test "be auto without a beplus.estate.json fails and installs nothing" {
  run be auto
  assert_failure
  assert_output --partial "auto found no beplus.estate.json in ${PROJECT} or above it"
  [ ! -e "${BE_PREFIX}/bin/beplus" ]
  [ ! -e "${BE_PREFIX}/be/versions" ]
}


@test "be auto fails, naming the file, when beplus.estate.json pins no version" {
  local manifest
  for manifest in '{ "name": "estate" }' '{ "cli": {} }' '{ "cli": { "version": null } }'; do
    echo "${manifest}" > "${PROJECT}/beplus.estate.json"
    run be auto
    assert_failure
    assert_output --partial "${PROJECT}/beplus.estate.json pins no beplus CLI version"
  done
  [ ! -e "${BE_PREFIX}/bin/beplus" ]
}


@test "a nearer beplus.estate.json without a pin does not fall back to one further up" {
  write_manifest '"2.11.0"'
  echo '{ "name": "app" }' > "${PROJECT}/packages/app/beplus.estate.json"
  cd "${PROJECT}/packages/app"

  run be auto
  assert_failure
  assert_output --partial "${PROJECT}/packages/app/beplus.estate.json pins no beplus CLI version"
  [ ! -e "${BE_PREFIX}/bin/beplus" ]
}


@test "be auto refuses a pin that is not one exact version" {
  local version
  for version in '"2"' '"2.11"' '"latest"' '"^2.11.0"' '"~2.11.0"' '">=2.11.0"' '"2.11.x"' '""'; do
    write_manifest "${version}"
    run be auto
    assert_failure
    assert_output --partial "in ${PROJECT}/beplus.estate.json is ${version}, not one exact version"
  done
  [ ! -e "${BE_PREFIX}/bin/beplus" ]
}


@test "be auto refuses a pin that is not a string" {
  local version
  for version in '2.11' 'true' '{"major":2}'; do
    write_manifest "${version}"
    run be auto
    assert_failure
    assert_output --partial "in ${PROJECT}/beplus.estate.json is ${version}, not a version string"
  done
  [ ! -e "${BE_PREFIX}/bin/beplus" ]
}


@test "be auto fails, naming the file, when beplus.estate.json is not valid JSON" {
  local manifest
  for manifest in '{ "cli": { "version": "2.11.0" }' '' '{} {}'; do
    printf '%s' "${manifest}" > "${PROJECT}/beplus.estate.json"
    run be auto
    assert_failure
    assert_output --partial "${PROJECT}/beplus.estate.json could not be read as JSON by "
  done
  [ ! -e "${BE_PREFIX}/bin/beplus" ]
}


@test "jq reads the pin where there is no node" {
  command -v jq > /dev/null || skip "jq is not installed"
  setup_shim jq

  write_manifest '"2.11.0"'
  run env PATH="${TMP_SHIM_DIR}" "${TMP_SHIM_DIR}/be" N_TEST_DISPLAY_LATEST_RESOLVED_VERSION auto
  assert_success
  assert_line "2.11.0"

  echo '{ "name": "estate" }' > "${PROJECT}/beplus.estate.json"
  run env PATH="${TMP_SHIM_DIR}" "${TMP_SHIM_DIR}/be" auto
  assert_failure
  assert_output --partial "${PROJECT}/beplus.estate.json pins no beplus CLI version"

  local manifest
  for manifest in '{ "cli": { "version": "2.11.0" }' '' '{} {}'; do
    printf '%s' "${manifest}" > "${PROJECT}/beplus.estate.json"
    run env PATH="${TMP_SHIM_DIR}" "${TMP_SHIM_DIR}/be" auto
    assert_failure
    assert_output --partial "${PROJECT}/beplus.estate.json could not be read as JSON by jq: "
  done
}


@test "be auto without node or jq says it needs one of them" {
  setup_shim

  write_manifest '"2.11.0"'
  run env PATH="${TMP_SHIM_DIR}" "${TMP_SHIM_DIR}/be" auto
  assert_failure
  assert_output --partial "reading the beplus CLI pin from ${PROJECT}/beplus.estate.json needs node or jq"
}
