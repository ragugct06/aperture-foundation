#!/usr/bin/env bash
set -euo pipefail

: "${IMAGE_TAG:?IMAGE_TAG is required}"
: "${GITOPS_TOKEN:?GITOPS_TOKEN is required}"

GITOPS_REPO="bitbucket.org/anovorx/aperture-gitops.git"
GITOPS_BRANCH="feature/ci-pipline"
VALUES_FILE="environments/dev/aperture-foundation/values.yaml"

WORK_DIR="$(mktemp -d)"

cleanup() {
  rm -rf "${WORK_DIR}"
}
trap cleanup EXIT

echo "=== Updating Foundation DEV GitOps image ==="
echo "Image tag: ${IMAGE_TAG}"

git clone \
  --branch "${GITOPS_BRANCH}" \
  --single-branch \
  "https://x-token-auth:${GITOPS_TOKEN}@${GITOPS_REPO}" \
  "${WORK_DIR}/aperture-gitops"

cd "${WORK_DIR}/aperture-gitops"

if [ ! -f "${VALUES_FILE}" ]; then
  echo "ERROR: ${VALUES_FILE} not found."
  exit 1
fi

sed -i \
  "s|^[[:space:]]*tag:.*|  tag: ${IMAGE_TAG}|" \
  "${VALUES_FILE}"

if git diff --quiet; then
  echo "GitOps already references ${IMAGE_TAG}."
  exit 0
fi

git config user.name "bitbucket-pipelines"
git config user.email "commits-noreply@bitbucket.org"

git add "${VALUES_FILE}"
git commit -m "deploy(aperture-foundation): DEV ${IMAGE_TAG} [skip ci]"
git push origin "${GITOPS_BRANCH}"

echo "GitOps update pushed successfully."