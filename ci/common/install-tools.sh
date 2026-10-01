#!/usr/bin/env bash
set -euo pipefail

echo "=== Installing required CI tools ==="

MISSING_PACKAGES=()
REQUIRED_TOOLS=(curl jq git)
MODE="${1:-build}"
case "${MODE}" in
  build|aws) REQUIRED_TOOLS+=(unzip) ;;
  scripts) REQUIRED_TOOLS+=(python3) ;;
  gitops) ;;
  *) echo "ERROR: Unknown tool mode: ${MODE}"; exit 1 ;;
esac
for TOOL in "${REQUIRED_TOOLS[@]}"; do
  if ! command -v "${TOOL}" >/dev/null 2>&1; then
    MISSING_PACKAGES+=("${TOOL}")
  fi
done

if (( ${#MISSING_PACKAGES[@]} > 0 )); then
  apt-get update
  apt-get install -y --no-install-recommends "${MISSING_PACKAGES[@]}"
fi

# GitOps-only operations and offline script checks need neither AWS CLI nor .NET.
if [[ "${MODE}" == "gitops" || "${MODE}" == "scripts" ]]; then
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

if [[ "${MODE}" == "build" ]]; then
  echo "dotnet:"
  dotnet --version
fi

echo "aws:"
aws --version

echo "jq:"
jq --version
