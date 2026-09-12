#!/usr/bin/env bats
#
# Version resolution must not depend on the order the index happens to arrive in.
#
# The GitHub Releases API sorts by created_at, and every beplus/cli release shares one — the tags
# all point at that repo's unchanged default-branch HEAD — so the list ties and comes back in no
# particular order. `be` used to take the first match, which had `be 2` handing out a stage build
# published before the prod one. These run against a deliberately scrambled index.

load shared-functions
load '../../node_modules/bats-support/load'
load '../../node_modules/bats-assert/load'


function setup() {
  unset_n_env
  INDEX="${BATS_TEST_TMPDIR:-${BATS_TMPDIR}}/releases.json"
  cat > "${INDEX}" <<'JSON'
[
  {"name": "v2.0.0-dev.29",   "tag_name": "v2.0.0-dev.29",   "prerelease": true,  "draft": false},
  {"name": "v1.0.5",          "tag_name": "v1.0.5",          "prerelease": false, "draft": false},
  {"name": "v2.0.0",          "tag_name": "v2.0.0",          "prerelease": false, "draft": false},
  {"name": "v2.0.0-stage.30", "tag_name": "v2.0.0-stage.30", "prerelease": true,  "draft": false},
  {"name": "v2.0.0-prod.31",  "tag_name": "v2.0.0-prod.31",  "prerelease": true,  "draft": false},
  {"name": "v1.0.0-beta.2",   "tag_name": "v1.0.0-beta.2",   "prerelease": true,  "draft": false},
  {"name": "v1.0.0-beta.11",  "tag_name": "v1.0.0-beta.11",  "prerelease": true,  "draft": false}
]
JSON
  export BE_RELEASE_INDEX_URL="file://${INDEX}"
}


function teardown() {
  unset BE_RELEASE_INDEX_URL
}


@test "be ls-remote orders by SemVer precedence, not index order" {
  output="$(be ls-remote)"
  assert_equal "${output}" "2.0.0
2.0.0-stage.30
2.0.0-prod.31
2.0.0-dev.29
1.0.5
1.0.0-beta.11
1.0.0-beta.2"
}

@test "a release outranks the pre-releases it was promoted from" {
  # The reported bug: this used to resolve to whichever v2 the index listed first.
  output="$(be ls-remote 2)"
  assert_equal "$(echo "${output}" | head -n 1)" "2.0.0"
}

@test "pre-release build numbers compare numerically, not as strings" {
  output="$(be ls-remote 1.0.0)"
  assert_equal "$(echo "${output}" | head -n 1)" "1.0.0-beta.11"
}

@test "be latest picks the newest official release, not the first one listed" {
  output="$(be --latest)"
  assert_equal "${output}" "2.0.0"
}

@test "be stable picks the newest official release" {
  output="$(be --stable)"
  assert_equal "${output}" "2.0.0"
}

@test "an exact version still resolves to itself" {
  output="$(be ls-remote 2.0.0-prod.31)"
  assert_equal "${output}" "2.0.0-prod.31"
}

@test "a name that is not a version does not break resolution" {
  cat > "${INDEX}" <<'JSON'
[
  {"name": "nightly", "tag_name": "nightly", "prerelease": true,  "draft": false},
  {"name": "v2.0.0",  "tag_name": "v2.0.0",  "prerelease": false, "draft": false}
]
JSON
  output="$(be --latest)"
  assert_equal "${output}" "2.0.0"
}
