#!/usr/bin/env bash
#
# catch-up-codeartifact.sh <version> — publish to this environment's CodeArtifact ($BE_ENVIRONMENT's)
# every version of @beplus/be before <version> that dev released and the CodeArtifact lacks.
#
# A fast-forward promotes every commit up to the one it lands on, and dev may have released several
# versions since the last promotion: stage and prod get each of them, not only the newest, so an
# estate that pinned one on dev installs it there too. "Released" is in GitHub Packages, and each is
# the tarball dev published there, byte for byte. "Before" is SemVer: dev releases one version at a
# time, so a lower version came from a commit before this one; dev's newer versions wait for their
# own promotion.
#
# Oldest first, under a `catch-up` dist-tag that is removed afterwards, so `latest` stays where
# publish-codeartifact.sh puts it; so is one an earlier run left behind. Removing a dist-tag needs
# codeartifact:PutPackageMetadata on the environment's npm-publishing role. A version the registry
# refuses (one archived there on purpose) is a warning, and the next promotion tries it again.
#
# Writes caught_up (the versions published now) and earlier (every version before <version> the
# CodeArtifact has now), space-separated, as key=value lines to $GITHUB_OUTPUT (stdout when unset).
# Runs after the job assumed the environment's npm-publishing role and installed the beplus CLI;
# GitHub Packages is read with $NODE_AUTH_TOKEN.

set -euo pipefail

readonly version="${1:?usage: catch-up-codeartifact.sh <version>}"
readonly name="@beplus/be"
readonly github="https://npm.pkg.github.com/"

auth="$(beplus aws codeartifact auth --env "${BE_ENVIRONMENT:?BE_ENVIRONMENT is not set}" --json)"
registry="https://$(jq -r '.data.registry // empty' <<< "${auth}")"
if [[ "${registry}" == "https://" ]]; then
  echo "::error::beplus aws codeartifact auth --env ${BE_ENVIRONMENT} named no registry: ${auth}"
  exit 1
fi

# The token stays in the environment: npm expands ${NODE_AUTH_TOKEN} itself.
temp="${RUNNER_TEMP:-$(mktemp -d)}"
npmrc="${temp}/.npmrc-github"
# shellcheck disable=SC2016 # npm expands it, not the shell
echo '//npm.pkg.github.com/:_authToken=${NODE_AUTH_TOKEN}' > "${npmrc}"

#
# versions <where> <npm args...> — every version of @beplus/be a registry has, one a line; nothing
# when it has none. Any other answer stops the run.
#

function versions() {
  local where="$1" out err
  shift
  err="$(mktemp)"
  if out="$(npm view "${name}" versions --json "$@" 2> "${err}")"; then
    rm -f "${err}"
    node -e 'console.log([].concat(JSON.parse(process.argv[1] || "[]")).join("\n"))' "${out}"
  elif grep -q E404 <<< "${out}$(cat "${err}")"; then
    rm -f "${err}"
  else
    echo "::error::Cannot list the versions of ${name} in ${where}: ${out}$(cat "${err}")" >&2
    rm -f "${err}"
    return 1
  fi
}

released="$(versions "GitHub Packages" --userconfig "${npmrc}" --@beplus:registry="${github}")"
here="$(versions "${BE_ENVIRONMENT}'s CodeArtifact" --registry="${registry}" --@beplus:registry="${registry}")"
# A catch-up tag an earlier run could not remove (no PutPackageMetadata, or cancelled), if any.
stale="$(npm view "${name}" dist-tags.catch-up --registry="${registry}" --@beplus:registry="${registry}" 2> /dev/null || true)"

# npm's own copy of semver, which every npm carries: nothing is installed for this.
# shellcheck disable=SC2016 # ${…} is a JavaScript template literal, not a shell expansion
earlier="$(node -e '
  const semver = require(`${process.argv[1]}/npm/node_modules/semver`);
  const released = require("fs").readFileSync(0, "utf8").split("\n").filter(Boolean);
  console.log(semver.sort(released.filter((v) => semver.lt(v, process.argv[2]))).join("\n"));
' "$(npm root -g)" "${version}" <<< "${released}")"

dir="$(mktemp -d)"
caught_up=()
landed=()
refused=()
while read -r v; do
  [[ -n "${v}" ]] || continue
  if grep -qxF "${v}" <<< "${here}"; then
    landed+=("${v}")
    continue
  fi
  echo "Publishing ${name}@${v} to ${BE_ENVIRONMENT}'s CodeArtifact (dist-tag catch-up)"
  if file="$(npm pack "${name}@${v}" --pack-destination "${dir}" --userconfig "${npmrc}" --@beplus:registry="${github}" | tail -n 1)" \
    && npm publish "${dir}/${file}" --tag catch-up --registry="${registry}" --@beplus:registry="${registry}"; then
    caught_up+=("${v}")
    landed+=("${v}")
  else
    refused+=("${v}")
    echo "::warning::Could not publish ${name}@${v} to ${BE_ENVIRONMENT}'s CodeArtifact. The next promotion tries again."
  fi
done <<< "${earlier}"

if [[ "${#caught_up[@]}" -gt 0 ]]; then
  echo "Caught up on ${caught_up[*]}."
elif [[ "${#refused[@]}" -eq 0 ]]; then
  echo "${BE_ENVIRONMENT}'s CodeArtifact already has every version dev released before ${version}."
fi

if [[ "${#caught_up[@]}" -gt 0 || -n "${stale}" ]]; then
  [[ -z "${stale}" ]] || echo "Removing the catch-up dist-tag an earlier run left on ${stale}."
  npm dist-tag rm "${name}" catch-up --registry="${registry}" --@beplus:registry="${registry}" > /dev/null \
    || echo "::warning::Could not remove the catch-up dist-tag from ${name} in ${BE_ENVIRONMENT}'s CodeArtifact: the role needs codeartifact:PutPackageMetadata. The next promotion tries again."
fi

{
  echo "caught_up=${caught_up[*]}"
  echo "earlier=${landed[*]}"
} >> "${GITHUB_OUTPUT:-/dev/stdout}"
