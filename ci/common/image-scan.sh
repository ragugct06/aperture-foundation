#!/usr/bin/env bash
set -euo pipefail

SERVICE_NAME="${SERVICE_NAME:-aperture-foundation}"
IMAGE_TAG="${BITBUCKET_COMMIT:-local}"
LOCAL_IMAGE="${LOCAL_IMAGE:-${SERVICE_NAME}:${IMAGE_TAG}}"

REPORT_DIR="reports"
REPORT_FILE="${REPORT_DIR}/trivy-image-scan.json"

# Temporarily report vulnerabilities without blocking deployment. Set
# IMAGE_SCAN_EXIT_CODE=1 in CI to enforce the HIGH/CRITICAL vulnerability gate.
# Scanner execution errors still fail the step in either mode.
IMAGE_SCAN_EXIT_CODE="${IMAGE_SCAN_EXIT_CODE:-0}"
if [[ "${IMAGE_SCAN_EXIT_CODE}" != "0" && "${IMAGE_SCAN_EXIT_CODE}" != "1" ]]; then
  echo "ERROR: IMAGE_SCAN_EXIT_CODE must be 0 (report only) or 1 (block on findings)."
  exit 1
fi

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

# Scan once and write the report in both report-only and blocking modes.
# Keep comments outside the continued command below.
trivy image \
  --scanners vuln \
  --severity HIGH,CRITICAL \
  --ignore-unfixed \
  --exit-code "${IMAGE_SCAN_EXIT_CODE}" \
  --format json \
  --output "${REPORT_FILE}" \
  "${LOCAL_IMAGE}"

echo "Image scan completed successfully."
