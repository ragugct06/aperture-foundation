#!/usr/bin/env bash
set -euo pipefail

DEPLOY_ENV="${1:?deployment environment is required}"
SERVICE_NAME="${2:?service name is required}"
METADATA_FILE="${3:?metadata file is required}"

: "${GITOPS_ACCESS_TOKEN:?GITOPS_ACCESS_TOKEN is required}"

GITOPS_APPROVER_TOKEN="${GITOPS_APPROVER_TOKEN:-${GITOPS_ACCESS_TOKEN}}"

if [[ ! -f "${METADATA_FILE}" ]]; then
  echo "ERROR: Metadata file not found: ${METADATA_FILE}"
  exit 1
fi

source "${METADATA_FILE}"

: "${RELEASE_TAG:?RELEASE_TAG is required}"
: "${SOURCE_COMMIT:?SOURCE_COMMIT is required}"
: "${IMAGE_REPOSITORY:?IMAGE_REPOSITORY is required}"
: "${IMAGE_DIGEST:?IMAGE_DIGEST is required}"

GITOPS_WORKSPACE="anovorx"
GITOPS_REPO="aperture-gitops"
GITOPS_BASE_BRANCH="main"

VALUES_FILE="environments/${DEPLOY_ENV}/${SERVICE_NAME}/values.yaml"
SHORT_COMMIT="${SOURCE_COMMIT:0:12}"

if [[ "${DEPLOY_ENV}" == "dev" ]]; then
  DEPLOY_BRANCH="deploy/${DEPLOY_ENV}/${SERVICE_NAME}/${SHORT_COMMIT}"
else
  DEPLOY_BRANCH="deploy/${DEPLOY_ENV}/${SERVICE_NAME}/${RELEASE_TAG}"
fi

WORK_DIR="$(mktemp -d)"

cleanup() {
  rm -rf "${WORK_DIR}"
}

trap cleanup EXIT

echo "========================================="
echo " Preparing GitOps deployment"
echo "========================================="
echo "Service:     ${SERVICE_NAME}"
echo "Environment: ${DEPLOY_ENV}"
echo "Release:     ${RELEASE_TAG}"
echo "Commit:      ${SOURCE_COMMIT}"
echo "Digest:      ${IMAGE_DIGEST}"

git clone \
  --quiet \
  --branch "${GITOPS_BASE_BRANCH}" \
  "https://x-token-auth:${GITOPS_ACCESS_TOKEN}@bitbucket.org/${GITOPS_WORKSPACE}/${GITOPS_REPO}.git" \
  "${WORK_DIR}/${GITOPS_REPO}"

cd "${WORK_DIR}/${GITOPS_REPO}"

if [[ ! -f "${VALUES_FILE}" ]]; then
  echo "ERROR: GitOps values file not found: ${VALUES_FILE}"
  exit 1
fi

git config user.name "Aperture CI"
git config user.email "aperture-ci@users.noreply.bitbucket.org"

git checkout -B "${DEPLOY_BRANCH}" "origin/${GITOPS_BASE_BRANCH}"

if ! command -v yq >/dev/null 2>&1; then
  YQ_VERSION="v4.47.2"

  curl -fsSL \
    "https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/yq_linux_amd64" \
    -o /usr/local/bin/yq

  chmod +x /usr/local/bin/yq
fi

export RELEASE_TAG SOURCE_COMMIT IMAGE_REPOSITORY IMAGE_DIGEST

yq -i '
  .release.version = strenv(RELEASE_TAG) |
  .release.commit = strenv(SOURCE_COMMIT) |
  .image.repository = strenv(IMAGE_REPOSITORY) |
  .image.tag = "" |
  .image.digest = strenv(IMAGE_DIGEST)
' "${VALUES_FILE}"

if git diff --quiet -- "${VALUES_FILE}"; then
  echo "GitOps already references this release."
  exit 0
fi

git add "${VALUES_FILE}"

git commit \
  -m "deploy(${SERVICE_NAME}): ${DEPLOY_ENV} ${RELEASE_TAG} [skip ci]"

git push --force-with-lease origin "${DEPLOY_BRANCH}"

PR_TITLE="deploy(${SERVICE_NAME}): ${DEPLOY_ENV} ${RELEASE_TAG}"

PR_PAYLOAD="$(
  cat <<JSON
{
  "title": "${PR_TITLE}",
  "source": {
    "branch": {
      "name": "${DEPLOY_BRANCH}"
    }
  },
  "destination": {
    "branch": {
      "name": "${GITOPS_BASE_BRANCH}"
    }
  },
  "close_source_branch": true
}
JSON
)"

PR_RESPONSE="/tmp/gitops-pr-response.json"

HTTP_CODE="$(
  curl \
    --silent \
    --show-error \
    --output "${PR_RESPONSE}" \
    --write-out "%{http_code}" \
    --request POST \
    --header "Authorization: Bearer ${GITOPS_ACCESS_TOKEN}" \
    --header "Content-Type: application/json" \
    --data "${PR_PAYLOAD}" \
    "https://api.bitbucket.org/2.0/repositories/${GITOPS_WORKSPACE}/${GITOPS_REPO}/pullrequests"
)"

if [[ "${HTTP_CODE}" != "201" ]]; then
  echo "ERROR: Failed to create GitOps PR."
  cat "${PR_RESPONSE}"
  exit 1
fi

PR_ID="$(jq -r '.id' "${PR_RESPONSE}")"

if [[ -z "${PR_ID}" || "${PR_ID}" == "null" ]]; then
  echo "ERROR: Unable to determine GitOps PR ID."
  exit 1
fi

echo "Created GitOps PR: ${PR_ID}"

APPROVE_CODE="$(
  curl \
    --silent \
    --show-error \
    --output /tmp/gitops-pr-approve-response.json \
    --write-out "%{http_code}" \
    --request PUT \
    --header "Authorization: Bearer ${GITOPS_APPROVER_TOKEN}" \
    "https://api.bitbucket.org/2.0/repositories/${GITOPS_WORKSPACE}/${GITOPS_REPO}/pullrequests/${PR_ID}/approve"
)"

if [[ "${APPROVE_CODE}" != "200" ]]; then
  echo "ERROR: Failed to approve GitOps PR."
  cat /tmp/gitops-pr-approve-response.json
  exit 1
fi

echo "GitOps PR approved."

MERGE_CODE="$(
  curl \
    --silent \
    --show-error \
    --output /tmp/gitops-pr-merge-response.json \
    --write-out "%{http_code}" \
    --request POST \
    --header "Authorization: Bearer ${GITOPS_APPROVER_TOKEN}" \
    --header "Content-Type: application/json" \
    --data '{"close_source_branch": true}' \
    "https://api.bitbucket.org/2.0/repositories/${GITOPS_WORKSPACE}/${GITOPS_REPO}/pullrequests/${PR_ID}/merge"
)"

if [[ "${MERGE_CODE}" != "200" ]]; then
  echo "ERROR: Failed to merge GitOps PR."
  cat /tmp/gitops-pr-merge-response.json
  exit 1
fi

echo "GitOps PR approved and merged successfully."
