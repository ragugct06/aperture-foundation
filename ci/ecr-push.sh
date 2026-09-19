#!/usr/bin/env bash
set -euo pipefail

: "${AWS_REGION:?AWS_REGION is required}"
: "${AWS_ACCOUNT_ID:?AWS_ACCOUNT_ID is required}"
: "${ECR_REPOSITORY:?ECR_REPOSITORY is required}"
: "${IMAGE_TAG:?IMAGE_TAG is required}"
: "${LOCAL_IMAGE:?LOCAL_IMAGE is required}"

ECR_REGISTRY="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
REMOTE_IMAGE="${ECR_REGISTRY}/${ECR_REPOSITORY}:${IMAGE_TAG}"

echo "=== Logging in to ECR ==="

aws ecr get-login-password --region "${AWS_REGION}" \
  | docker login \
      --username AWS \
      --password-stdin "${ECR_REGISTRY}"

echo "=== Tagging image ==="

docker tag \
  "${LOCAL_IMAGE}" \
  "${REMOTE_IMAGE}"

echo "=== Pushing image ==="

docker push "${REMOTE_IMAGE}"

echo "Published image:"
echo "${REMOTE_IMAGE}"