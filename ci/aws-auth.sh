#!/usr/bin/env bash
set -euo pipefail

echo "=== AWS authentication setup ==="

: "${AWS_REGION:?AWS_REGION is required}"
: "${AWS_ROLE_ARN:?AWS_ROLE_ARN is required}"
: "${BITBUCKET_STEP_OIDC_TOKEN:?BITBUCKET_STEP_OIDC_TOKEN is required}"

if ! command -v aws >/dev/null 2>&1; then
  echo "AWS CLI not found. Installing AWS CLI v2..."

  apt-get update
  apt-get install -y curl unzip

  ARCH="$(uname -m)"

  case "${ARCH}" in
    x86_64)
      AWSCLI_ARCH="x86_64"
      ;;
    aarch64|arm64)
      AWSCLI_ARCH="aarch64"
      ;;
    *)
      echo "Unsupported architecture: ${ARCH}"
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

echo "AWS CLI version:"
aws --version

export AWS_DEFAULT_REGION="${AWS_REGION}"

export AWS_WEB_IDENTITY_TOKEN_FILE="${BITBUCKET_CLONE_DIR}/web-identity-token"

printf '%s' "${BITBUCKET_STEP_OIDC_TOKEN}" \
  > "${AWS_WEB_IDENTITY_TOKEN_FILE}"

echo "Verifying AWS identity..."
aws sts get-caller-identity

echo "AWS OIDC authentication successful."