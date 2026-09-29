#!/usr/bin/env bash
set -euo pipefail

SERVICE_NAME="${SERVICE_NAME:-aperture-foundation}"
IMAGE_TAG="${BITBUCKET_COMMIT:-local}"
LOCAL_IMAGE="${LOCAL_IMAGE:-${SERVICE_NAME}:${IMAGE_TAG}}"

REPORT_DIR="reports"
REPORT_FILE="${REPORT_DIR}/trivy-image-scan.json"

echo "=== Scanning Docker image ==="
echo "Image: ${LOCAL_IMAGE}"

if ! command -v trivy >/dev/null 2>&1; then
  echo "Trivy not found. Installing..."

  curl -sfL \
    https://raw.githubusercontent.com/aquasecurity/trivy/main/contrib/install.sh \
    | sh -s -- -b /usr/local/bin
fi

mkdir -p "${REPORT_DIR}"

if ! docker image inspect "${LOCAL_IMAGE}" >/dev/null 2>&1; then
  echo "ERROR: Docker image '${LOCAL_IMAGE}' is not available locally."
  exit 1
fi

trivy image \
  --scanners vuln \
  --severity HIGH,CRITICAL \
  --ignore-unfixed \
  "${LOCAL_IMAGE}"

trivy image \
  --scanners vuln \
  --severity HIGH,CRITICAL \
  --ignore-unfixed \
  --format json \
  --output "${REPORT_FILE}" \
  "${LOCAL_IMAGE}"

echo "Image scan completed successfully."
