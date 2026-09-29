#!/usr/bin/env bash
set -euo pipefail

STATE_FILE="${1:?source environment state file is required}"
RELEASE_FILE="${2:?release metadata file is required}"
TARGET_ACCOUNT_ID="${3:?target AWS account ID is required}"
TARGET_REPOSITORY="${4:?target ECR repository is required}"
OUTPUT_FILE="${5:?output metadata file is required}"

: "${AWS_REGION:?AWS_REGION is required}"

if [[ ! -f "${STATE_FILE}" ]]; then
  echo "ERROR: Source state file not found: ${STATE_FILE}"
  exit 1
fi

if [[ ! -f "${RELEASE_FILE}" ]]; then
  echo "ERROR: Release metadata file not found: ${RELEASE_FILE}"
  exit 1
fi

source "${STATE_FILE}"
source "${RELEASE_FILE}"

: "${SOURCE_IMAGE_REPOSITORY:?SOURCE_IMAGE_REPOSITORY is required}"
: "${SOURCE_IMAGE_DIGEST:?SOURCE_IMAGE_DIGEST is required}"
: "${SOURCE_COMMIT:?SOURCE_COMMIT is required}"
: "${RELEASE_TAG:?RELEASE_TAG is required}"

TARGET_REGISTRY="${TARGET_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
TARGET_REPOSITORY_URI="${TARGET_REGISTRY}/${TARGET_REPOSITORY}"

SOURCE_REGISTRY="${SOURCE_IMAGE_REPOSITORY%%/*}"
SOURCE_IMAGE="${SOURCE_IMAGE_REPOSITORY}@${SOURCE_IMAGE_DIGEST}"

TARGET_TAG="${SOURCE_COMMIT}"
TARGET_IMAGE="${TARGET_REPOSITORY_URI}:${TARGET_TAG}"

echo "========================================="
echo " Promoting immutable image"
echo "========================================="
echo "Release: ${RELEASE_TAG}"
echo "Commit:  ${SOURCE_COMMIT}"
echo "Digest:  ${SOURCE_IMAGE_DIGEST}"

aws ecr get-login-password \
  --region "${AWS_REGION}" \
  | docker login \
      --username AWS \
      --password-stdin "${SOURCE_REGISTRY}"

docker pull "${SOURCE_IMAGE}"

aws ecr get-login-password \
  --region "${AWS_REGION}" \
  | docker login \
      --username AWS \
      --password-stdin "${TARGET_REGISTRY}"

set +e

EXISTING_DIGEST="$(
  aws ecr describe-images \
    --repository-name "${TARGET_REPOSITORY}" \
    --region "${AWS_REGION}" \
    --image-ids imageTag="${TARGET_TAG}" \
    --query 'imageDetails[0].imageDigest' \
    --output text \
    2>/tmp/ecr-promote-error
)"

DESCRIBE_EXIT_CODE=$?

set -e

if [[ ${DESCRIBE_EXIT_CODE} -ne 0 ]]; then
  if grep -q "ImageNotFoundException" /tmp/ecr-promote-error; then
    EXISTING_DIGEST=""
  else
    echo "ERROR: Failed to query target ECR."
    cat /tmp/ecr-promote-error
    exit 1
  fi
fi

if [[ -z "${EXISTING_DIGEST}" || "${EXISTING_DIGEST}" == "None" ]]; then
  docker tag \
    "${SOURCE_IMAGE}" \
    "${TARGET_IMAGE}"

  docker push "${TARGET_IMAGE}"
else
  echo "Target image already exists."
fi

IMAGE_DIGEST="$(
  aws ecr describe-images \
    --repository-name "${TARGET_REPOSITORY}" \
    --region "${AWS_REGION}" \
    --image-ids imageTag="${TARGET_TAG}" \
    --query 'imageDetails[0].imageDigest' \
    --output text
)"

mkdir -p "$(dirname "${OUTPUT_FILE}")"

cat > "${OUTPUT_FILE}" <<METADATA
RELEASE_TAG=${RELEASE_TAG}
SOURCE_COMMIT=${SOURCE_COMMIT}
IMAGE_REPOSITORY=${TARGET_REPOSITORY_URI}
IMAGE_DIGEST=${IMAGE_DIGEST}
METADATA

echo "Image promotion completed successfully."
