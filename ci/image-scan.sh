#!/usr/bin/env bash
set -euo pipefail

: "${LOCAL_IMAGE:?LOCAL_IMAGE is required}"

echo "=== Scanning Docker image ==="

if ! command -v trivy >/dev/null 2>&1; then
  echo "Trivy not found. Installing..."

  apt-get update
  apt-get install -y wget gnupg lsb-release

  wget -qO - https://aquasecurity.github.io/trivy-repo/deb/public.key \
    | gpg --dearmor \
    | tee /usr/share/keyrings/trivy.gpg >/dev/null

  echo "deb [signed-by=/usr/share/keyrings/trivy.gpg] https://aquasecurity.github.io/trivy-repo/deb $(lsb_release -sc) main" \
    > /etc/apt/sources.list.d/trivy.list

  apt-get update
  apt-get install -y trivy
fi

trivy image \
  --severity HIGH,CRITICAL \
  --exit-code 1 \
  "${LOCAL_IMAGE}"