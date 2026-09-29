#!/usr/bin/env bash
set -euo pipefail

SERVICE_NAME="${SERVICE_NAME:-aperture-foundation}"
IMAGE_TAG="${BITBUCKET_COMMIT:-local}"
DOCKERFILE="${DOCKERFILE:-DockerFile}"

LOCAL_IMAGE="${SERVICE_NAME}:${IMAGE_TAG}"

echo "=== Building Docker runtime image ==="
echo "Image: ${LOCAL_IMAGE}"

docker build \
  --tag "${LOCAL_IMAGE}" \
  --file "${DOCKERFILE}" \
  .

export SERVICE_NAME
export IMAGE_TAG
export LOCAL_IMAGE

echo "Docker image built successfully."
