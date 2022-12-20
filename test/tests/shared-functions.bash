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

  if [[ -z "${version}" ]]; then
    match='.'
  elif [[ "${version}" = "stable" ]]; then
    match_count=1
    match='.'
  elif [[ "${version}" = "latest" || "${version}" = "current" ]]; then
    match_count=1
    match='.'
  elif is_numeric_version "${version}"; then
    version="v${version#v}"
    # Avoid restriction message if exact version
    is_exact_numeric_version "${version}" && match_count=1
    # Quote any dots in version so they are literal for expression
    match="${version//\./\.}"
    # Avoid 1.2 matching 1.23
    match="^${match}[^0-9]"
  else
    abort "invalid version '$1'"
  fi

  local index_url="https://api.github.com/repos/beplus/cli/releases"

  for row in $(do_get_index "${index_url}" | jq -r '.[] | @base64'); do
    _jq() {
     echo ${row} | base64 --decode | jq -r ${1}
    }
   echo $(_jq '.name')
  done | awk "NR<=${match_count}" \
    | cut -f 1 \
    | grep -E -o '[^v].*'

  return "${PIPESTATUS[0]}"
}
