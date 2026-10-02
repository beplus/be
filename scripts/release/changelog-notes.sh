#!/usr/bin/env bash
#
# Print the body of one version's section of CHANGELOG.md — the GitHub Release notes.
#
#   scripts/release/changelog-notes.sh v0.8.0
#
# The section runs from its "## [vX.Y.Z]" heading to the next "## [" heading. Fails when the
# section is missing or has no text.

set -euo pipefail

readonly TAG="${1:?usage: changelog-notes.sh vX.Y.Z}"
readonly CHANGELOG="${CHANGELOG:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/CHANGELOG.md}"

# Leading and trailing blank lines are dropped; blank lines inside the section are kept.
notes="$(awk -v heading="## [${TAG}]" '
  index($0, heading) == 1 { found = 1; next }
  found && /^## \[/ { exit }
  found && /[^[:space:]]/ {
    for (i = 0; i < blanks; i++) print ""
    blanks = 0
    started = 1
    print
    next
  }
  found && started { blanks++ }
' "${CHANGELOG}")"

if [[ -z "${notes}" ]]; then
  echo "Error: CHANGELOG.md has no notes under \"## [${TAG}]\"." >&2
  exit 1
fi

printf '%s\n' "${notes}"
