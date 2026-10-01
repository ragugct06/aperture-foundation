#!/usr/bin/env bash
# Resolve an already-published image for a GitOps-only DEV retry.
# IMAGE_COMMIT is the original image tag; BITBUCKET_COMMIT identifies the CI fix.
# No Docker build, image pull, or ECR push is performed here.
set -euo pipefail

: "${IMAGE_COMMIT:?IMAGE_COMMIT is required}"
: "${AWS_ACCOUNT_ID:?AWS_ACCOUNT_ID is required}"
: "${AWS_REGION:?AWS_REGION is required}"
: "${ECR_REPOSITORY:?ECR_REPOSITORY is required}"
if [[ ! "${IMAGE_COMMIT}" =~ ^[0-9a-f]{40}$ ]]; then
  echo "ERROR: IMAGE_COMMIT must be the full 40-character application commit SHA."
  exit 1
fi

IMAGE_DIGEST="$(aws ecr describe-images \
  --registry-id "${AWS_ACCOUNT_ID}" \
  --repository-name "${ECR_REPOSITORY}" \
  --region "${AWS_REGION}" \
  --image-ids "imageTag=${IMAGE_COMMIT}" \
  --query 'imageDetails[0].imageDigest' --output text)"
if [[ ! "${IMAGE_DIGEST}" =~ ^sha256:[0-9a-f]{64}$ ]]; then
  echo "ERROR: ECR did not return a valid digest for ${IMAGE_COMMIT}."
  exit 1
fi

mkdir -p reports
# %q keeps the generated file safe to source even if configuration contains
# shell metacharacters. Keep the same metadata contract as publish-dev.sh.
printf 'RELEASE_TAG=%q\nSOURCE_COMMIT=%q\nIMAGE_REPOSITORY=%q\nIMAGE_DIGEST=%q\n' \
  dev "${IMAGE_COMMIT}" \
  "${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${ECR_REPOSITORY}" \
  "${IMAGE_DIGEST}" > reports/image-metadata.env
echo "Existing DEV image resolved: ${IMAGE_COMMIT}@${IMAGE_DIGEST}"
