#!/usr/bin/env bash
set -euo pipefail

echo "=== Installing required CI tools ==="

MISSING_PACKAGES=()
REQUIRED_TOOLS=(curl jq git)
if [[ "${1:-build}" != "gitops" ]]; then
  REQUIRED_TOOLS+=(unzip python3)
fi
for TOOL in "${REQUIRED_TOOLS[@]}"; do
  if ! command -v "${TOOL}" >/dev/null 2>&1; then
    MISSING_PACKAGES+=("${TOOL}")
  fi
done

if (( ${#MISSING_PACKAGES[@]} > 0 )); then
  apt-get update
  apt-get install -y --no-install-recommends "${MISSING_PACKAGES[@]}"
fi

# Promotion only reads GitOps and creates a tag; it needs neither AWS nor .NET.
if [[ "${1:-build}" == "gitops" ]]; then
  exit 0
fi

if ! command -v aws >/dev/null 2>&1; then
  ARCH="$(uname -m)"

  case "${ARCH}" in
    x86_64)
      AWSCLI_ARCH="x86_64"
      ;;
    aarch64|arm64)
      AWSCLI_ARCH="aarch64"
      ;;
    *)
      echo "ERROR: Unsupported architecture: ${ARCH}"
      exit 1
      ;;
  esac

  curl -fsSL \
    "https://awscli.amazonaws.com/awscli-exe-linux-${AWSCLI_ARCH}.zip" \
    -o /tmp/awscliv2.zip

  unzip -q /tmp/awscliv2.zip -d /tmp
  /tmp/aws/install

  rm -rf /tmp/aws /tmp/awscliv2.zip
fi

echo "dotnet:"
dotnet --version

echo "aws:"
aws --version

echo "jq:"
jq --version
