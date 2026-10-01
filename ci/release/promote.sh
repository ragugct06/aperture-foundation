#!/usr/bin/env bash
# Promote an existing tagged artifact: resolve image, migrate, then update GitOps.
# Run from the application repository root. No build or tag creation occurs.
set -euo pipefail
TARGET_ENV="${1:?target environment is required}"
SERVICE_NAME="${SERVICE_NAME:-aperture-foundation}"
bash ci/release/resolve-tag.sh "${TARGET_ENV}" reports/release.env
source reports/release.env
SELECTED_RELEASE_TAG="${RELEASE_TAG}"
export IMAGE_COMMIT="${SOURCE_COMMIT}"
# A missing image must stop promotion before the database is touched.
bash ci/ecr/read-existing-image.sh
source reports/image-metadata.env
RELEASE_TAG="${SELECTED_RELEASE_TAG}"
printf 'RELEASE_TAG=%q\nSOURCE_COMMIT=%q\nIMAGE_REPOSITORY=%q\nIMAGE_DIGEST=%q\nTARGET_ENV=%q\n' \
  "${RELEASE_TAG}" "${SOURCE_COMMIT}" "${IMAGE_REPOSITORY}" "${IMAGE_DIGEST}" \
  "${TARGET_ENV}" > reports/promoted-image.env
bash ci/database/migrate.sh update "${SOURCE_COMMIT}"
bash ci/gitops/update-environment.sh "${TARGET_ENV}" "${SERVICE_NAME}" reports/promoted-image.env
echo "Promotion completed: ${RELEASE_TAG} -> ${TARGET_ENV}"
