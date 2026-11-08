#!/usr/bin/env bash


# unset the be environment variables so tests running from known state.
# Globals:
#   lots

function unset_n_env(){
  unset BE_PREFIX
  unset BE_CACHE_PREFIX
  unset BE_MIRROR
  unset BE_DOWNLOAD_MIRROR
  unset BE_MAX_REMOTE_MATCHES
  unset BE_RELEASE_INDEX_URL
  unset BE_DOWNLOAD_ATTEMPTS
  unset BE_DOWNLOAD_RETRY_DELAY
  unset HTTP_USER
  unset HTTP_PASSWORD
  unset GREP_OPTIONS
}


# Create temporary dir and configure be to use it.
# Globals:
#   TMP_PREFIX_DIR
#   BE_PREFIX
#   PATH

function setup_tmp_prefix() {
  TMP_PREFIX_DIR="$(mktemp -d)"
  [ -d "${TMP_PREFIX_DIR}" ] || exit 2
  # return a safer variable to `rm -rf` later than BE_PREFIX
  export TMP_PREFIX_DIR

  export BE_PREFIX="${TMP_PREFIX_DIR}"
  export PATH="${BE_PREFIX}/bin:${PATH}"
}


# Create a local mirror laid out as the beplus CLI release publishes one: for each <version>
# given, v<version>/ holds this machine's tarball, with a stub beplus that prints the version
# banner, and SHA256SUMS beside it.
# Usage: make_tmp_mirror version...
# Globals:
#   TMP_MIRROR_DIR

function make_tmp_mirror() {
  TMP_MIRROR_DIR="$(mktemp -d)"
  [ -d "${TMP_MIRROR_DIR}" ] || exit 2
  export TMP_MIRROR_DIR

  local version
  for version in "$@"; do
    local release="${TMP_MIRROR_DIR}/v${version}"
    local tarball="beplus-cli-v${version}-$(tarball_platform).tar.gz"
    mkdir -p "${release}" "${TMP_MIRROR_DIR}/stub"
    printf '#!/bin/sh\necho "beplus CLI v%s"\n' "${version}" > "${TMP_MIRROR_DIR}/stub/beplus"
    chmod +x "${TMP_MIRROR_DIR}/stub/beplus"
    tar -czf "${release}/${tarball}" -C "${TMP_MIRROR_DIR}/stub" beplus
    if command -v sha256sum &> /dev/null; then
      (cd "${release}" && sha256sum "${tarball}" > SHA256SUMS)
    else
      (cd "${release}" && shasum -a 256 "${tarball}" > SHA256SUMS)
    fi
  done
}


# make_tmp_mirror, with be pointed at it as a file:// URL. be reads that with curl only (wget
# fetches http, https and ftp), so without curl the test is skipped.
# Usage: setup_tmp_mirror version...
# Globals:
#   TMP_MIRROR_DIR
#   BE_MIRROR

function setup_tmp_mirror() {
  command -v curl > /dev/null || skip "the local mirror is a file:// URL, which needs curl"
  make_tmp_mirror "$@"
  export BE_MIRROR="file://${TMP_MIRROR_DIR}"
}


# make_tmp_mirror, served on 127.0.0.1 by flaky-mirror.js and with be pointed at it: a request for
# a file whose <file>.plan lists answers gets those first, one per request, such as a 504 (see
# flaky-mirror.js). Each request is logged to ${TMP_MIRROR_DIR}/requests.log. Needs node. Stop it
# with stop_flaky_mirror.
# Usage: setup_flaky_mirror version...
# Globals:
#   TMP_MIRROR_DIR
#   FLAKY_MIRROR_PID
#   BE_MIRROR

function setup_flaky_mirror() {
  command -v node > /dev/null || skip "the flaky mirror runs on node"
  make_tmp_mirror "$@"
  local port_file="${TMP_MIRROR_DIR}/port"
  # With fd 3 open, bats would wait for the server to exit.
  node "${BATS_TEST_DIRNAME}/flaky-mirror.js" "${TMP_MIRROR_DIR}" "${port_file}" > /dev/null 2>&1 3>&- &
  FLAKY_MIRROR_PID=$!
  local waited=0
  while [[ ! -s "${port_file}" ]]; do
    if (( waited++ >= 100 )); then
      stop_flaky_mirror
      echo "flaky-mirror.js did not start within 10 seconds" >&2
      return 1
    fi
    sleep 0.1
  done
  export BE_MIRROR="http://127.0.0.1:$(cat "${port_file}")"
  # Not through a proxy that may be set for the tests.
  export no_proxy="127.0.0.1${no_proxy:+,${no_proxy}}"
  export NO_PROXY="127.0.0.1${NO_PROXY:+,${NO_PROXY}}"
}


function stop_flaky_mirror() {
  if [[ -n "${FLAKY_MIRROR_PID}" ]]; then
    kill "${FLAKY_MIRROR_PID}" 2> /dev/null || true
  fi
  FLAKY_MIRROR_PID=
}

#
# @todo Duplicate
# Synopsis: tarball_platform
# The platform in a release tarball's name, as be picks it for this machine.
#

function tarball_platform() {
  local os arch
  case "$(uname -s)" in
    Linux) os="linux" ;;
    Darwin) os="macos" ;;
  esac
  case "$(uname -m)" in
    x86_64) arch="x64" ;;
    aarch64 | armv8l) arch="arm64" ;;
    *) arch="$(uname -m)" ;;
  esac
  echo "${os}-${arch}"
}

#
# Synopsis: beplus --version | cli_version
# The version a beplus binary reports, without the leading v. 2.x prints a banner whose first
# line is "beplus CLI vX.Y.Z", where older builds printed just the version.
#

function cli_version() {
  sed -n -E 's/^[[:space:]]*(beplus CLI )?v?([0-9]+\.[0-9]+\.[0-9]+[^[:space:]]*)[[:space:]]*$/\2/p' | head -n 1
}

#
# @todo Duplicate
# Synopsis: is_numeric_version version
#

function is_numeric_version() {
  # e.g. 6, v7.1, 8.11.3
  [[ "$1" =~ ^[v]{0,1}[0-9]+(\.[0-9]+){0,2}$ ]]
}

#
# @todo Duplicate
# Synopsis: is_exact_numeric_version version
#

function is_exact_numeric_version() {
  # e.g. 6, v7.1, 8.11.3
  [[ "$1" =~ ^[v]{0,1}[0-9]+\.[0-9]+\.[0-9]+$ ]]
}

#
# @todo Duplicate
# Synopsis: do_get_index [option...] url
# Call curl or wget with combination of global and passed options,
# with options tweaked to be more suitable for getting index.
#

function do_get_index() {
  if command -v curl &> /dev/null; then
    # --silent to suppress progress et al
    curl --silent --compressed "${CURL_OPTIONS[@]}" "$@"
  elif command -v wget &> /dev/null; then
    wget "${WGET_OPTIONS[@]}" "$@"
  else
    abort "curl or wget command required"
  fi
}

# display_remote_version <version>
# Return version number, without leading v.
#
# @todo Simplified "duplicate"
# This simper (and independent) code here can cause transient false positive failures.

function display_remote_version() {
  local version="$1"
  local match='.'
  local match_count="${BE_MAX_REMOTE_MATCHES}"
  local official_only=

  if [[ -z "${version}" ]]; then
    match='.'
  elif [[ "${version}" = "stable" ]]; then
    match_count=1
    match='.'
    official_only=1
  elif [[ "${version}" = "latest" || "${version}" = "current" ]]; then
    match_count=1
    match='.'
    official_only=1
  elif is_numeric_version "${version}"; then
    version="v${version#v}"
    # Avoid restriction message if exact version
    is_exact_numeric_version "${version}" && match_count=1
    # Quote any dots in version so they are literal for expression
    match="${version//\./\.}"
    # Anchor the end so '1' matches v1.x but not v10.x, while an exact
    # 'v1.2.3' still matches its bare name (which has no trailing separator).
    match="^${match}([^0-9]|$)"
  else
    abort "invalid version '$1'"
  fi

  # The same index be reads: the GitHub Releases API lists builds the mirror does not host, and
  # rate-limits unauthenticated callers such as CI runners.
  local index_url="${BE_RELEASE_INDEX_URL:-https://beplus.s3.amazonaws.com/cli/releases.json}"

  local jq_release_filter='.[]'
  if [[ -n "${official_only}" ]]; then
    jq_release_filter='.[] | select(.prerelease != true and .draft != true)'
  fi

  do_get_index "${index_url}" \
    | jq -r "${jq_release_filter} | .name" \
    | grep -E "${match}" \
    | awk "NR<=${match_count}" \
    | cut -f 1 \
    | grep -E -o '[^v].*'

  return "${PIPESTATUS[0]}"
}
