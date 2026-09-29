#!/usr/bin/env bash
set -euo pipefail

DEPLOY_ENV="${1:?deployment environment is required}"
SERVICE_NAME="${2:?service name is required}"
OUTPUT_FILE="${3:?output file is required}"

: "${GITOPS_ACCESS_TOKEN:?GITOPS_ACCESS_TOKEN is required}"

CALLER_DIR="$(pwd)"

if [[ "${OUTPUT_FILE}" != /* ]]; then
  OUTPUT_FILE="${CALLER_DIR}/${OUTPUT_FILE}"
fi

GITOPS_WORKSPACE="anovorx"
GITOPS_REPO="aperture-gitops"
GITOPS_BRANCH="main"

VALUES_FILE="environments/${DEPLOY_ENV}/${SERVICE_NAME}/values.yaml"

WORK_DIR="$(mktemp -d)"

cleanup() {
  rm -rf "${WORK_DIR}"
}

trap cleanup EXIT

git clone \
  --quiet \
  --depth 1 \
  --branch "${GITOPS_BRANCH}" \
  "https://x-token-auth:${GITOPS_ACCESS_TOKEN}@bitbucket.org/${GITOPS_WORKSPACE}/${GITOPS_REPO}.git" \
  "${WORK_DIR}/${GITOPS_REPO}"

cd "${WORK_DIR}/${GITOPS_REPO}"

if [[ ! -f "${VALUES_FILE}" ]]; then
  echo "ERROR: GitOps values file not found: ${VALUES_FILE}"
  exit 1
fi

if ! command -v yq >/dev/null 2>&1; then
  YQ_VERSION="v4.47.2"

  curl -fsSL \
    "https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/yq_linux_amd64" \
    -o /usr/local/bin/yq

  chmod +x /usr/local/bin/yq
fi

SOURCE_COMMIT="$(yq -r '.release.commit // ""' "${VALUES_FILE}")"
SOURCE_IMAGE_REPOSITORY="$(yq -r '.image.repository // ""' "${VALUES_FILE}")"
SOURCE_IMAGE_DIGEST="$(yq -r '.image.digest // ""' "${VALUES_FILE}")"

if [[ -z "${SOURCE_COMMIT}" ]]; then
  echo "ERROR: release.commit is empty."
  exit 1
fi

if [[ -z "${SOURCE_IMAGE_REPOSITORY}" ]]; then
  echo "ERROR: image.repository is empty."
  exit 1
fi

if [[ -z "${SOURCE_IMAGE_DIGEST}" ]]; then
  echo "ERROR: image.digest is empty."
  exit 1
fi

mkdir -p "$(dirname "${OUTPUT_FILE}")"

cat > "${OUTPUT_FILE}" <<STATE
SOURCE_COMMIT=${SOURCE_COMMIT}
SOURCE_IMAGE_REPOSITORY=${SOURCE_IMAGE_REPOSITORY}
SOURCE_IMAGE_DIGEST=${SOURCE_IMAGE_DIGEST}
STATE

echo "Environment state captured successfully."
