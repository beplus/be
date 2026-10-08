#!/usr/bin/env bash
#
# publish-codeartifact.sh <tarball> — publish the tarball to this environment's CodeArtifact
# ($BE_ENVIRONMENT's; dev's is npm.beplus.cloud) under $DIST_TAG, unless it already has that version.
# Runs after the job assumed the environment's npm-publishing role and installed the beplus CLI.
#
# publishConfig pins the @beplus scope to npmjs, and only command-line flags outrank it, so the
# registry `beplus aws codeartifact auth` writes into ~/.npmrc (with its token) is also named on
# every npm command line here.

set -euo pipefail

readonly tarball="${1:?usage: publish-codeartifact.sh <tarball>}"
readonly dist_tag="${DIST_TAG:?DIST_TAG is not set}"

auth="$(beplus aws codeartifact auth --env "${BE_ENVIRONMENT:?BE_ENVIRONMENT is not set}" --json)"
registry="https://$(jq -r '.data.registry // empty' <<< "${auth}")"
if [[ "${registry}" == "https://" ]]; then
  echo "::error::beplus aws codeartifact auth --env ${BE_ENVIRONMENT} named no registry: ${auth}"
  exit 1
fi

spec="$(tar -xOzf "${tarball}" package/package.json | jq -r '"\(.name)@\(.version)"')"
if out="$(npm view "${spec}" version --registry="${registry}" --@beplus:registry="${registry}" 2>&1)" && [[ -n "${out}" ]]; then
  echo "Skipping ${spec}: already in ${BE_ENVIRONMENT}'s CodeArtifact"
  exit 0
elif ! grep -q E404 <<< "${out}"; then
  echo "::error::Cannot tell whether ${BE_ENVIRONMENT}'s CodeArtifact has ${spec}: ${out}"
  exit 1
fi

echo "Publishing ${spec} to ${BE_ENVIRONMENT}'s CodeArtifact (dist-tag ${dist_tag})"
npm publish "${tarball}" --tag "${dist_tag}" --registry="${registry}" --@beplus:registry="${registry}"
