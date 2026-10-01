#!/usr/bin/env bash
# Update one environment's image reference in the GitOps repository.
#
# Usage (run from the application repository root):
#   bash ci/gitops/update-environment.sh dev aperture-foundation reports/image-metadata.env
#   bash ci/gitops/update-environment.sh qa aperture-foundation reports/promoted-image.env
#
# Called by: the DEV pipeline or ci/release/promote-qa.sh.
# Input: a trusted, generated shell file containing RELEASE_TAG, SOURCE_COMMIT,
#        IMAGE_REPOSITORY, and IMAGE_DIGEST; GitOps credentials come from CI.
# Flow: load metadata -> clone GitOps -> edit values -> push/reuse branch -> PR.
# Success: GitOps already has the requested values, or the deployment PR merged.
# This script does not build/pull an image or wait for the cluster to deploy it.
#
# SOURCE_COMMIT identifies application code. DEPLOY_COMMIT identifies the GitOps
# configuration change. They belong to different repositories.

# Stop on failed commands, unset variables, and failures within shell pipelines.
set -euo pipefail

# Keep the helper's absolute path because we later cd into the GitOps clone.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 1. Validate inputs and load the image metadata.
# ${name:?message} stops immediately when an argument/variable is missing or empty.
DEPLOY_ENV="${1:?deployment environment is required}"
SERVICE_NAME="${2:?service name is required}"
METADATA_FILE="${3:?metadata file is required}"

: "${GITOPS_ACCESS_TOKEN:?GITOPS_ACCESS_TOKEN is required}"
: "${GITOPS_APPROVER_EMAIL:?GITOPS_APPROVER_EMAIL is required}"
: "${GITOPS_APPROVER_TOKEN:?GITOPS_APPROVER_TOKEN is required}"

if [[ ! -f "${METADATA_FILE}" ]]; then
  echo "ERROR: Metadata file not found: ${METADATA_FILE}"
  exit 1
fi

# source loads shell assignments into this process; use only CI-generated files.
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

# Stable branch names let a retry find the same deployment branch and open PR.
# DEV uses a commit ID because every DEV build shares the release label "dev".
# QA uses the versioned release tag, for example v1.2.0-beta.3.
if [[ "${DEPLOY_ENV}" == "dev" ]]; then
  DEPLOY_BRANCH="deploy/${DEPLOY_ENV}/${SERVICE_NAME}/${SHORT_COMMIT}"
else
  DEPLOY_BRANCH="deploy/${DEPLOY_ENV}/${SERVICE_NAME}/${RELEASE_TAG}"
fi

# 2. Work in a disposable GitOps clone, leaving the application checkout intact.
WORK_DIR="$(mktemp -d)"

cleanup() {
  rm -rf "${WORK_DIR}"
}

# Remove the clone on both success and failure (including its authenticated URL).
trap cleanup EXIT

echo "========================================="
echo " Preparing GitOps deployment"
echo "========================================="
echo "Service:     ${SERVICE_NAME}"
echo "Environment: ${DEPLOY_ENV}"
echo "Release:     ${RELEASE_TAG}"
echo "Commit:      ${SOURCE_COMMIT}"
echo "Digest:      ${IMAGE_DIGEST}"
echo "Branch:      ${DEPLOY_BRANCH}"

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

# Build the desired change from current GitOps main, not an older retry branch.
# -B creates/resets only the local branch in this disposable clone.
git checkout -B \
  "${DEPLOY_BRANCH}" \
  "origin/${GITOPS_BASE_BRANCH}"

# The YAML editor below uses Mike Farah's yq v4 syntax (Linux amd64 runner).
if ! command -v yq >/dev/null 2>&1; then
  echo "Installing yq..."

  YQ_VERSION="v4.47.2"

  curl -fsSL \
    "https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/yq_linux_amd64" \
    -o /usr/local/bin/yq

  chmod +x /usr/local/bin/yq
fi

# 3. Update release metadata and pin the image by digest.
# yq's strenv() reads exported variables as strings, avoiding YAML type inference.
export RELEASE_TAG
export SOURCE_COMMIT
export IMAGE_REPOSITORY
export IMAGE_DIGEST

echo
echo "========================================="
echo " Updating GitOps values"
echo "========================================="

# Clear the image tag so the requested digest is the image selection in values.
yq -i '
  .release.version = strenv(RELEASE_TAG) |
  .release.commit = strenv(SOURCE_COMMIT) |
  .image.repository = strenv(IMAGE_REPOSITORY) |
  .image.tag = "" |
  .image.digest = strenv(IMAGE_DIGEST)
' "${VALUES_FILE}"

# A retry after a successful merge needs no new commit, push, or PR.
if git diff --quiet -- "${VALUES_FILE}"; then
  echo "GitOps already references this release."
  exit 0
fi

echo
echo "========================================="
echo " GitOps change"
echo "========================================="

git diff -- "${VALUES_FILE}"

git add "${VALUES_FILE}"

# 4. Reuse an identical remote branch, or push the newly prepared change.
# write-tree identifies the complete staged file tree; COMMIT^{tree} identifies
# the remote commit's tree. Equal trees mean no content changed, even if a new
# commit would have a different timestamp. Reuse preserves approvals/builds.
# A missing remote branch is expected on the first run, hence "|| true".
REMOTE_COMMIT="$(git rev-parse --verify "refs/remotes/origin/${DEPLOY_BRANCH}" 2>/dev/null || true)"
if [[ -n "${REMOTE_COMMIT}" && "$(git write-tree)" == "$(git rev-parse "${REMOTE_COMMIT}^{tree}")" ]]; then
  echo "Reusing unchanged deployment branch."
  DEPLOY_COMMIT="${REMOTE_COMMIT}"
else
  git commit -m "deploy(${SERVICE_NAME}): ${DEPLOY_ENV} ${RELEASE_TAG}"
  DEPLOY_COMMIT="$(git rev-parse HEAD)"
  # Replace the remote branch only if it still points to the commit we observed.
  # An empty REMOTE_COMMIT means the branch must still be absent. A concurrent
  # update fails the push instead of being overwritten. Do not use plain --force.
  git push --force-with-lease="refs/heads/${DEPLOY_BRANCH}:${REMOTE_COMMIT}" \
    origin "HEAD:refs/heads/${DEPLOY_BRANCH}"
fi

# 5. Delegate PR lookup/creation, approval, checks, and merge verification.
# Pass the GitOps commit so the helper can detect an unexpected PR source change.
bash "${SCRIPT_DIR}/complete-pull-request.sh" \
  "${GITOPS_WORKSPACE}" "${GITOPS_REPO}" "${DEPLOY_BRANCH}" \
  "${GITOPS_BASE_BRANCH}" "${DEPLOY_COMMIT}" \
  "deploy(${SERVICE_NAME}): ${DEPLOY_ENV} ${RELEASE_TAG}"

echo "GitOps updated: ${DEPLOY_ENV}/${SERVICE_NAME} ${RELEASE_TAG} (${IMAGE_DIGEST})"
