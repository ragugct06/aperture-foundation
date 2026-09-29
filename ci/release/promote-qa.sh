#!/usr/bin/env bash
set -euo pipefail

SERVICE_NAME="${SERVICE_NAME:-aperture-foundation}"

: "${RELEASE_VERSION:?RELEASE_VERSION is required}"
: "${AWS_REGION:?AWS_REGION is required}"
: "${QA_AWS_ACCOUNT_ID:?QA_AWS_ACCOUNT_ID is required}"
: "${QA_ECR_REPOSITORY:?QA_ECR_REPOSITORY is required}"

SOURCE_ENV="dev"
TARGET_ENV="qa"

SOURCE_STATE_FILE="reports/source-environment.env"
RELEASE_FILE="reports/qa-release.env"
PROMOTION_FILE="reports/promoted-image.env"

echo "========================================="
echo " Foundation QA promotion"
echo "========================================="

./ci/gitops/read-environment-state.sh \
  "${SOURCE_ENV}" \
  "${SERVICE_NAME}" \
  "${SOURCE_STATE_FILE}"

./ci/release/create-next-tag.sh \
  "${SOURCE_STATE_FILE}" \
  "${RELEASE_FILE}"

./ci/ecr/promote-image.sh \
  "${SOURCE_STATE_FILE}" \
  "${RELEASE_FILE}" \
  "${QA_AWS_ACCOUNT_ID}" \
  "${QA_ECR_REPOSITORY}" \
  "${PROMOTION_FILE}"

./ci/gitops/update-environment.sh \
  "${TARGET_ENV}" \
  "${SERVICE_NAME}" \
  "${PROMOTION_FILE}"

echo "Foundation QA promotion completed successfully."
