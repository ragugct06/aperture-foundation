#!/usr/bin/env bash
set -euo pipefail

: "${ECR_REPOSITORY:?ECR_REPOSITORY is required}"

IMAGE_TAG="${BITBUCKET_COMMIT}"
LOCAL_IMAGE="${ECR_REPOSITORY}:${IMAGE_TAG}"

echo "=== Building Docker image ==="
echo "Image tag: ${IMAGE_TAG}"

docker build \
  --secret id=codeartifact_token,env=CODEARTIFACT_TOKEN \
  -t "${LOCAL_IMAGE}" \
  -f DockerFile \
  .

export IMAGE_TAG
export LOCAL_IMAGE