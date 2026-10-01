#!/usr/bin/env bash
#
# The release rules, in one place: the pull-request check and the release workflow both run this.
#
#   scripts/release/verify-version.sh pr <base-ref> [<head-branch>]
#   scripts/release/verify-version.sh release
#
# Both modes first check that bin/be, package.json and package-lock.json carry the same version.
#
# pr       A PR into main either bumps the version or leaves bin/be alone, because whatever lands
#          on main is what scripts/install.sh installs. A bump must be newer than the base, not yet
#          tagged or on npm, and described in CHANGELOG.md. A _versions/vX.Y.Z branch must arrive
#          with exactly vX.Y.Z.
#
# release  Decides what a push to main still has to do, and writes it as key=value lines to
#          $GITHUB_OUTPUT (stdout when unset): version, tag, dist_tag, need_publish (not on npm
#          yet) and need_release (not tagged yet). Re-checks CHANGELOG.md when either is true.

set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/../.."

readonly NPM_REGISTRY="https://registry.npmjs.org"
g_errors=0

#
# error <message> — report a problem and keep checking, so one run lists all of them
#

function error() {
  if [[ "${GITHUB_ACTIONS:-}" == "true" ]]; then
    echo "::error::$*" >&2
  else
    echo "Error: $*" >&2
  fi
  g_errors=$((g_errors + 1))
}

function notice() {
  if [[ "${GITHUB_ACTIONS:-}" == "true" ]]; then
    echo "::notice::$*"
  else
    echo "$*"
  fi
}

function finish() {
  if [[ "${g_errors}" -gt 0 ]]; then
    exit 1
  fi
}

#
# json_field <file> <expression> — read a value out of a JSON file, "-" for stdin
#

function json_field() {
  node -e '
    const text = require("fs").readFileSync(process.argv[1] === "-" ? 0 : process.argv[1], "utf8");
    const json = JSON.parse(text);
    process.stdout.write(String(new Function("json", "return " + process.argv[2])(json) ?? ""));
  ' "$1" "$2"
}

#
# semver_compare <a> <b> — print -1, 0 or 1 by SemVer precedence; fails on an invalid version
#

function semver_compare() {
  # shellcheck disable=SC2016 # ${v} is a JavaScript template literal, not a shell expansion
  node -e '
    const parse = (v) => {
      const m = /^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)(?:-([0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?$/.exec(v);
      if (!m) { console.error(`Error: "${v}" is not a SemVer version.`); process.exit(2); }
      return { core: m.slice(1, 4).map(Number), pre: m[4] ? m[4].split(".") : [] };
    };
    const cmpId = (x, y) => {
      const nx = /^\d+$/.test(x), ny = /^\d+$/.test(y);
      if (nx && ny) return Math.sign(Number(x) - Number(y));
      if (nx !== ny) return nx ? -1 : 1;
      return x < y ? -1 : x > y ? 1 : 0;
    };
    const [a, b] = process.argv.slice(1).map(parse);
    let r = 0;
    for (let i = 0; i < 3 && r === 0; i++) r = Math.sign(a.core[i] - b.core[i]);
    if (r === 0 && (a.pre.length === 0) !== (b.pre.length === 0)) r = a.pre.length === 0 ? 1 : -1;
    for (let i = 0; r === 0 && i < Math.max(a.pre.length, b.pre.length); i++) {
      if (i >= a.pre.length) r = -1;
      else if (i >= b.pre.length) r = 1;
      else r = cmpId(a.pre[i], b.pre[i]);
    }
    console.log(r);
  ' "$1" "$2"
}

#
# remote_tag_commit <tag> — print the commit a tag on origin points at, nothing when there is none
#

function remote_tag_commit() {
  # An annotated tag is listed twice; its peeled "^{}" line, which sorts last, is the commit.
  git ls-remote --tags origin "refs/tags/$1" "refs/tags/$1^{}" | tail -n 1 | cut -f 1
}

#
# npm_has_version <name> <version> — whether public npm already has that version
#

function npm_has_version() {
  local status
  status="$(curl -sS -o /dev/null -w '%{http_code}' "${NPM_REGISTRY}/${1/\//%2f}/$2")"
  case "${status}" in
    200) return 0 ;;
    404) return 1 ;;
    *) echo "Error: ${NPM_REGISTRY} answered HTTP ${status} for $1@$2." >&2; exit 2 ;;
  esac
}

function check_changelog() {
  scripts/release/changelog-notes.sh "$1" > /dev/null 2>&1 \
    || error "CHANGELOG.md needs a \"## [$1] (MM/DD/YYYY)\" section describing the release (bin/bump opens it)."
}

#
# Versions must agree everywhere they are written down
#

NAME="$(json_field package.json 'json.name')"
VERSION="$(json_field package.json 'json.version')"
TAG="v${VERSION}"
readonly NAME VERSION TAG

semver_compare "${VERSION}" "${VERSION}" > /dev/null || exit 1

be_version="$(sed -n 's/^VERSION="\(.*\)"$/\1/p' bin/be)"
[[ "${be_version}" == "${TAG}" ]] \
  || error "bin/be says VERSION=\"${be_version}\" but package.json says ${VERSION}. Run bin/bump ${VERSION}."

lock_version="$(json_field package-lock.json 'json.version')"
lock_root_version="$(json_field package-lock.json 'json.packages[""].version')"
[[ "${lock_version}" == "${VERSION}" && "${lock_root_version}" == "${VERSION}" ]] \
  || error "package-lock.json says ${lock_version}/${lock_root_version} but package.json says ${VERSION}. Run bin/bump ${VERSION}."

function verify_pr() {
  local base_ref="${1:?usage: verify-version.sh pr <base-ref> [<head-branch>]}"
  local head_branch="${2:-${HEAD_BRANCH:-$(git branch --show-current)}}"
  local base_version
  base_version="$(git show "${base_ref}:package.json" | json_field - 'json.version')"

  if [[ "${head_branch}" =~ ^_versions/v(.+)$ && "${BASH_REMATCH[1]}" != "${VERSION}" ]]; then
    error "Branch ${head_branch} must cut v${BASH_REMATCH[1]}, but the version is ${VERSION}. Run bin/bump ${BASH_REMATCH[1]}."
  fi

  if [[ "${VERSION}" == "${base_version}" ]]; then
    if ! git diff --quiet "${base_ref}...HEAD" -- bin/be; then
      error "bin/be changed but the version is still ${VERSION}. Run bin/bump patch|minor|major and describe the release in CHANGELOG.md."
    fi
    finish
    notice "No version bump: merging this PR releases nothing."
    return
  fi

  if [[ "$(semver_compare "${VERSION}" "${base_version}")" != "1" ]]; then
    error "The version must move forward: ${VERSION} is not newer than ${base_version} on ${base_ref}."
  fi
  if [[ -n "$(remote_tag_commit "${TAG}")" ]]; then
    error "Tag ${TAG} already exists. Bump to a version that has not been released."
  fi
  if npm_has_version "${NAME}" "${VERSION}"; then
    error "${NAME}@${VERSION} is already on npm. Bump to a version that has not been released."
  fi
  check_changelog "${TAG}"
  finish
  notice "Merging this PR releases ${NAME}@${VERSION} (${base_version} → ${VERSION})."
}

function verify_release() {
  finish

  local need_publish=false need_release=false tag_commit dist_tag=latest
  npm_has_version "${NAME}" "${VERSION}" || need_publish=true
  tag_commit="$(remote_tag_commit "${TAG}")"
  [[ -n "${tag_commit}" ]] || need_release=true
  [[ "${VERSION}" != *-* ]] || dist_tag=next

  # Publishing must not put a commit's code under a tag that names a different commit.
  if [[ "${need_publish}" == "true" && -n "${tag_commit}" && "${tag_commit}" != "$(git rev-parse HEAD)" ]]; then
    error "${NAME}@${VERSION} is not on npm, but tag ${TAG} points at ${tag_commit}, not HEAD. Publish from that commit or bump the version."
  fi
  if [[ "${need_publish}" == "true" || "${need_release}" == "true" ]]; then
    check_changelog "${TAG}"
  fi
  finish

  if [[ "${need_publish}" == "true" || "${need_release}" == "true" ]]; then
    notice "Releasing ${NAME}@${VERSION} (publish to npm: ${need_publish}, tag and GitHub Release: ${need_release})."
  else
    notice "Nothing to release: ${NAME}@${VERSION} is already on npm and tagged ${TAG}."
  fi

  {
    echo "version=${VERSION}"
    echo "tag=${TAG}"
    echo "dist_tag=${dist_tag}"
    echo "need_publish=${need_publish}"
    echo "need_release=${need_release}"
  } >> "${GITHUB_OUTPUT:-/dev/stdout}"
}

case "${1:-}" in
  pr) shift; verify_pr "$@" ;;
  release) verify_release ;;
  *) echo "usage: verify-version.sh pr <base-ref> [<head-branch>] | release" >&2; exit 2 ;;
esac
