#!/usr/bin/env bash
set -euo pipefail

SERVICE_NAME="${SERVICE_NAME:-aperture-foundation}"

: "${RELEASE_VERSION:?RELEASE_VERSION is required}"

SOURCE_ENV="dev"
TARGET_ENV="qa"

SOURCE_STATE_FILE="reports/source-environment.env"
RELEASE_FILE="reports/qa-release.env"
PROMOTION_FILE="reports/promoted-image.env"

echo "========================================="
echo " Foundation QA promotion"
echo "========================================="
echo "Service:         ${SERVICE_NAME}"
echo "Release version: ${RELEASE_VERSION}"

echo
echo "========================================="
echo " Reading current DEV deployment"
echo "========================================="

./ci/gitops/read-environment-state.sh \
  "${SOURCE_ENV}" \
  "${SERVICE_NAME}" \
  "${SOURCE_STATE_FILE}"

echo
echo "========================================="
echo " Creating QA release tag"
echo "========================================="

./ci/release/create-next-tag.sh \
  "${SOURCE_STATE_FILE}" \
  "${RELEASE_FILE}"

source "${SOURCE_STATE_FILE}"
source "${RELEASE_FILE}"

: "${SOURCE_COMMIT:?SOURCE_COMMIT is required}"
: "${SOURCE_IMAGE_REPOSITORY:?SOURCE_IMAGE_REPOSITORY is required}"
: "${SOURCE_IMAGE_DIGEST:?SOURCE_IMAGE_DIGEST is required}"
: "${RELEASE_TAG:?RELEASE_TAG is required}"

echo
echo "========================================="
echo " Reusing immutable Shared ECR image"
echo "========================================="
echo "Repository: ${SOURCE_IMAGE_REPOSITORY}"
echo "Digest:     ${SOURCE_IMAGE_DIGEST}"
echo "Commit:     ${SOURCE_COMMIT}"

mkdir -p reports

cat > "${PROMOTION_FILE}" <<METADATA
RELEASE_TAG=${RELEASE_TAG}
SOURCE_COMMIT=${SOURCE_COMMIT}
IMAGE_REPOSITORY=${SOURCE_IMAGE_REPOSITORY}
IMAGE_DIGEST=${SOURCE_IMAGE_DIGEST}
METADATA

echo
echo "========================================="
echo " Updating QA GitOps"
echo "========================================="

./ci/gitops/update-environment.sh \
  "${TARGET_ENV}" \
  "${SERVICE_NAME}" \
  "${PROMOTION_FILE}"

echo
echo "Foundation QA promotion completed successfully."
