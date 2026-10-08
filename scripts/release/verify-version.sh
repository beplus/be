#!/usr/bin/env bash
#
# The release rules, in one place: the pull-request check and the release workflow both run this.
#
#   scripts/release/verify-version.sh pr <base-ref> [<head-branch>]
#   scripts/release/verify-version.sh release <dev|stage|prod|main>
#
# Both modes first check that bin/be, package.json and package-lock.json carry the same version.
#
# pr       A PR into dev either bumps the version or leaves bin/be alone, because whatever lands
#          on dev is released, and main (fast-forwarded from dev through stage and prod) is what
#          scripts/install.sh installs. A bump must be newer than the base, not yet tagged or on
#          npm, and described in CHANGELOG.md. A _versions/vX.Y.Z branch must arrive with exactly
#          vX.Y.Z.
#
# release  Decides what a push to dev, stage, prod or main still has to do, and writes it as
#          key=value lines to $GITHUB_OUTPUT (stdout when unset): version, tag, dist_tag,
#          source_sha (the commit the version was cut from: its tag when it has one, else HEAD),
#          need_release (dev: not tagged yet), need_github_packages (dev: not in GitHub Packages
#          yet) and need_npm (main: not on public npm yet). stage, prod and main build nothing, so
#          there the version must already be tagged and in GitHub Packages: anything else is a
#          commit dev never released, and is refused. main must also be on origin/prod, so the
#          public registry only ever gets what prod already has. GitHub Packages is read with $GITHUB_PACKAGES_TOKEN. Re-checks
#          CHANGELOG.md when dev still has something to release.

set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/../.."

readonly NPM_REGISTRY="https://registry.npmjs.org"
readonly GITHUB_PACKAGES_REGISTRY="https://npm.pkg.github.com"
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

function warning() {
  if [[ "${GITHUB_ACTIONS:-}" == "true" ]]; then
    echo "::warning::$*" >&2
  else
    echo "Warning: $*" >&2
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
# registry_has_version <registry> <name> <version> [<token>] — whether a registry already has that
# version: returns 0 when it does, 1 when it does not, 2 when the registry gives no clear answer
#

function registry_has_version() {
  local registry="$1" name="$2" version="$3" token="${4:-}" packument status
  packument="$(mktemp)"
  if [[ -n "${token}" ]]; then
    status="$(curl -sS -o "${packument}" -w '%{http_code}' -H "Authorization: Bearer ${token}" "${registry}/${name/\//%2f}")"
  else
    status="$(curl -sS -o "${packument}" -w '%{http_code}' "${registry}/${name/\//%2f}")"
  fi
  case "${status}" in
    200)
      node -e '
        const packument = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
        process.exit(packument.versions && packument.versions[process.argv[2]] ? 0 : 1);
      ' "${packument}" "${version}" || { rm -f "${packument}"; return 1; } ;;
    404) rm -f "${packument}"; return 1 ;;
    *) echo "${registry} answered HTTP ${status} for ${name}." >&2; rm -f "${packument}"; return 2 ;;
  esac
  rm -f "${packument}"
}

#
# npm_has_version <name> <version> — whether public npm already has that version; stops the run
# when npm gives no clear answer
#

function npm_has_version() {
  local found=0
  registry_has_version "${NPM_REGISTRY}" "$1" "$2" || found=$?
  if [[ "${found}" -eq 2 ]]; then
    echo "Error: cannot tell whether npm has $1@$2." >&2
    exit 2
  fi
  return "${found}"
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
  local branch="${1:?usage: verify-version.sh release <dev|stage|prod|main>}"
  finish

  local need_release=false need_github_packages=false need_npm=false tag_commit source_sha
  local dist_tag=latest found=0
  tag_commit="$(remote_tag_commit "${TAG}")"
  source_sha="${tag_commit:-$(git rev-parse HEAD)}"
  [[ "${VERSION}" != *-* ]] || dist_tag=next

  if [[ -n "${GITHUB_PACKAGES_TOKEN:-}" ]]; then
    registry_has_version "${GITHUB_PACKAGES_REGISTRY}" "${NAME}" "${VERSION}" "${GITHUB_PACKAGES_TOKEN}" || found=$?
  else
    found=2
    notice "GITHUB_PACKAGES_TOKEN is not set, so GitHub Packages is not checked."
  fi

  case "${branch}" in
    dev)
      [[ -n "${tag_commit}" ]] || need_release=true
      # A registry that gives no clear answer means "try to publish"; that step reports the error.
      case "${found}" in
        0) ;;
        1) need_github_packages=true ;;
        *) need_github_packages=true
           warning "Cannot tell whether GitHub Packages has ${NAME}@${VERSION}, so publishing it is attempted." ;;
      esac
      if [[ "${need_release}" == "true" || "${need_github_packages}" == "true" ]]; then
        check_changelog "${TAG}"
      fi
      ;;
    stage | prod | main)
      [[ -n "${tag_commit}" ]] \
        || error "${TAG} is not tagged, so dev never released ${NAME}@${VERSION}. Fast-forward ${branch} to a commit dev released."
      case "${found}" in
        0) ;;
        1) error "${NAME}@${VERSION} is not in GitHub Packages, so dev never released it. Fast-forward ${branch} to a commit dev released." ;;
        *) error "Cannot tell whether GitHub Packages has ${NAME}@${VERSION}, and ${branch} promotes only what dev published there." ;;
      esac
      if [[ "${branch}" == "main" ]]; then
        if ! git merge-base --is-ancestor HEAD origin/prod 2> /dev/null; then
          error "main is ahead of prod: the public registry gets only what prod has. Fast-forward main to prod (git push origin origin/prod:main)."
        fi
        npm_has_version "${NAME}" "${VERSION}" || need_npm=true
      fi
      ;;
    *)
      error "A release runs on dev, stage, prod or main, not on ${branch}."
      ;;
  esac
  finish

  case "${branch}" in
    dev)
      if [[ "${need_release}" == "true" || "${need_github_packages}" == "true" ]]; then
        notice "Releasing ${NAME}@${VERSION} on dev from ${source_sha} (tag and GitHub pre-release: ${need_release}, GitHub Packages: ${need_github_packages}; dev's CodeArtifact when it lacks it)."
      else
        notice "${NAME}@${VERSION} is tagged ${TAG} and in GitHub Packages; dev's CodeArtifact gets it if it lacks it."
      fi ;;
    main)
      if [[ "${need_npm}" == "true" ]]; then
        notice "Publishing ${NAME}@${VERSION} (${TAG}) to the public npm registry."
      else
        notice "Nothing to publish: ${NAME}@${VERSION} is already on the public npm registry."
      fi ;;
    *)
      notice "Promoting ${NAME}@${VERSION} (${TAG}) to ${branch}'s CodeArtifact$([[ "${branch}" == "prod" ]] && echo ", and making its GitHub Release a full release")." ;;
  esac

  {
    echo "version=${VERSION}"
    echo "tag=${TAG}"
    echo "dist_tag=${dist_tag}"
    echo "source_sha=${source_sha}"
    echo "need_release=${need_release}"
    echo "need_github_packages=${need_github_packages}"
    echo "need_npm=${need_npm}"
  } >> "${GITHUB_OUTPUT:-/dev/stdout}"
}

case "${1:-}" in
  pr) shift; verify_pr "$@" ;;
  release) shift; verify_release "$@" ;;
  *) echo "usage: verify-version.sh pr <base-ref> [<head-branch>] | release <dev|stage|prod|main>" >&2; exit 2 ;;
esac
