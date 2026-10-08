#!/usr/bin/env bash
#
# fetch-github-packages.sh <version> <dir> — download @beplus/be@<version> from GitHub Packages, the
# tarball dev published, into <dir>. stage and prod promote exactly those bytes; a version GitHub
# Packages does not have is one dev never released, and is refused. Needs $NODE_AUTH_TOKEN.

set -euo pipefail

readonly version="${1:?usage: fetch-github-packages.sh <version> <dir>}"
readonly dir="${2:?usage: fetch-github-packages.sh <version> <dir>}"
readonly spec="@beplus/be@${version}"
readonly registry="https://npm.pkg.github.com/"

# The token stays in the environment: npm expands ${NODE_AUTH_TOKEN} itself.
npmrc="${RUNNER_TEMP:-$(mktemp -d)}/.npmrc-github"
# shellcheck disable=SC2016 # npm expands it, not the shell
echo '//npm.pkg.github.com/:_authToken=${NODE_AUTH_TOKEN}' > "${npmrc}"

if ! out="$(npm view "${spec}" version --userconfig "${npmrc}" --@beplus:registry="${registry}" 2>&1)"; then
  if grep -q E404 <<< "${out}"; then
    echo "::error::${spec} is not in GitHub Packages, so dev never released it. Promote a commit dev released."
  else
    echo "::error::Cannot tell whether GitHub Packages has ${spec}: ${out}"
  fi
  exit 1
fi

mkdir -p "${dir}"
npm pack "${spec}" --pack-destination "${dir}" --userconfig "${npmrc}" --@beplus:registry="${registry}" > /dev/null
ls -l "${dir}"
