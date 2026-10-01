#!/usr/bin/env bash
set -euo pipefail

RELEASE_TAG="${1:?release tag is required}"
DEPLOY_ENV="${2:?deployment environment is required}"

NUMBER='(0|[1-9][0-9]*)'
BETA_PATTERN="^v?${NUMBER}\.${NUMBER}\.${NUMBER}-beta\.${NUMBER}$"
RC_PATTERN="^v?${NUMBER}\.${NUMBER}\.${NUMBER}-rc\.${NUMBER}$"
PROD_PATTERN="^v?${NUMBER}\.${NUMBER}\.${NUMBER}$"

case "${DEPLOY_ENV}" in
  qa|qe)
    EXPECTED_PATTERN="${BETA_PATTERN}"
    EXPECTED_FORMAT="1.2.3-beta.1"
    ;;
  uat)
    EXPECTED_PATTERN="${RC_PATTERN}"
    EXPECTED_FORMAT="1.2.3-rc.1"
    ;;
  prod)
    EXPECTED_PATTERN="${PROD_PATTERN}"
    EXPECTED_FORMAT="1.2.3"
    ;;
  *)
    echo "ERROR: Unsupported environment: ${DEPLOY_ENV}"
    exit 1
    ;;
esac

if [[ ! "${RELEASE_TAG}" =~ ${EXPECTED_PATTERN} ]]; then
  echo "ERROR: Invalid ${DEPLOY_ENV} release tag."
  echo "Expected format: ${EXPECTED_FORMAT}"
  exit 1
fi

echo "Release tag is valid: ${RELEASE_TAG}"
