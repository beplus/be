#!/usr/bin/env bash
#
# check-environment.sh <dev|stage|prod> — the release job's GitHub environment names the account
# and the CodeArtifact environment it publishes to, and both must be set: `beplus aws codeartifact
# auth` silently falls back to "dev" without an environment, which would publish a prod promotion
# into dev.

set -euo pipefail

readonly expected="${1:?usage: check-environment.sh <dev|stage|prod>}"
errors=0

if [[ -z "${BE_ENVIRONMENT:-}" ]]; then
  echo "::error::BE_ENVIRONMENT is empty - set it to ${expected} on the '${expected}' GitHub environment."
  errors=1
elif [[ "${BE_ENVIRONMENT}" != "${expected}" ]]; then
  echo "::error::BE_ENVIRONMENT is '${BE_ENVIRONMENT}' on the '${expected}' GitHub environment; it must be ${expected}."
  errors=1
fi
if [[ ! "${BE_AWS_ACCOUNT_ID:-}" =~ ^[0-9]{12}$ ]]; then
  echo "::error::BE_AWS_ACCOUNT_ID must be the 12-digit account of ${expected}'s CodeArtifact, set on the '${expected}' GitHub environment."
  errors=1
fi
exit "${errors}"
