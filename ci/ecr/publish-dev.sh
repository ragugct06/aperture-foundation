#!/usr/bin/env bash
set -euo pipefail

SERVICE_NAME="${SERVICE_NAME:-aperture-foundation}"

: "${AWS_ACCOUNT_ID:?AWS_ACCOUNT_ID is required}"
: "${AWS_REGION:?AWS_REGION is required}"
: "${ECR_REPOSITORY:?ECR_REPOSITORY is required}"
: "${BITBUCKET_COMMIT:?BITBUCKET_COMMIT is required}"

IMAGE_TAG="${BITBUCKET_COMMIT}"

ECR_REGISTRY="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
ECR_REPOSITORY_URI="${ECR_REGISTRY}/${ECR_REPOSITORY}"

LOCAL_IMAGE="${SERVICE_NAME}:${IMAGE_TAG}"
REMOTE_IMAGE="${ECR_REPOSITORY_URI}:${IMAGE_TAG}"

METADATA_DIR="reports"
METADATA_FILE="${METADATA_DIR}/image-metadata.env"

mkdir -p "${METADATA_DIR}"

echo "========================================="
echo " Publishing immutable DEV image"
echo "========================================="
echo "Service: ${SERVICE_NAME}"
echo "Commit:  ${BITBUCKET_COMMIT}"

aws ecr get-login-password \
  --region "${AWS_REGION}" \
  | docker login \
      --username AWS \
      --password-stdin "${ECR_REGISTRY}"

set +e

EXISTING_DIGEST="$(
  aws ecr describe-images \
    --registry-id "${AWS_ACCOUNT_ID}" \
    --repository-name "${ECR_REPOSITORY}" \
    --region "${AWS_REGION}" \
    --image-ids imageTag="${IMAGE_TAG}" \
    --query 'imageDetails[0].imageDigest' \
    --output text \
    2>/tmp/ecr-describe-error
)"

DESCRIBE_EXIT_CODE=$?

set -e

if [[ ${DESCRIBE_EXIT_CODE} -ne 0 ]]; then
  if grep -q "ImageNotFoundException" /tmp/ecr-describe-error; then
    EXISTING_DIGEST=""
  else
    echo "ERROR: Failed to query ECR."
    cat /tmp/ecr-describe-error
    exit 1
  fi
fi

if [[ -z "${EXISTING_DIGEST}" || "${EXISTING_DIGEST}" == "None" ]]; then
  echo "Publishing new immutable image..."

  docker tag \
    "${LOCAL_IMAGE}" \
    "${REMOTE_IMAGE}"

  docker push "${REMOTE_IMAGE}"
else
  echo "Image already exists."
  echo "Immutable tag will not be overwritten."
fi

IMAGE_DIGEST="$(
  aws ecr describe-images \
    --registry-id "${AWS_ACCOUNT_ID}" \
    --repository-name "${ECR_REPOSITORY}" \
    --region "${AWS_REGION}" \
    --image-ids imageTag="${IMAGE_TAG}" \
    --query 'imageDetails[0].imageDigest' \
    --output text
)"

if [[ -z "${IMAGE_DIGEST}" || "${IMAGE_DIGEST}" == "None" ]]; then
  echo "ERROR: Unable to resolve image digest."
  exit 1
fi

cat > "${METADATA_FILE}" <<METADATA
RELEASE_TAG=dev
SOURCE_COMMIT=${BITBUCKET_COMMIT}
IMAGE_REPOSITORY=${ECR_REPOSITORY_URI}
IMAGE_DIGEST=${IMAGE_DIGEST}
METADATA

echo
echo "DEV image published successfully."
echo "Repository: ${ECR_REPOSITORY_URI}"
echo "Commit: ${BITBUCKET_COMMIT}"
echo "Digest: ${IMAGE_DIGEST}"