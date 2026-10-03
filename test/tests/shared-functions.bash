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


# Create a local mirror laid out as the beplus CLI release publishes one, and point be at it:
# v<version>/ holds this machine's tarball, with a stub beplus that prints the version banner,
# and SHA256SUMS beside it. The mirror is a file:// URL, which be reads with curl only (wget
# fetches http, https and ftp), so without curl the test is skipped.
# Globals:
#   TMP_MIRROR_DIR
#   BE_MIRROR

function setup_tmp_mirror() {
  command -v curl > /dev/null || skip "the local mirror is a file:// URL, which needs curl"
  local version="$1"
  TMP_MIRROR_DIR="$(mktemp -d)"
  [ -d "${TMP_MIRROR_DIR}" ] || exit 2
  export TMP_MIRROR_DIR

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

  export BE_MIRROR="file://${TMP_MIRROR_DIR}"
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
