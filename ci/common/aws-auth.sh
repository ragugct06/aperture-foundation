#!/usr/bin/env bash
set -euo pipefail

echo "=== Configuring AWS OIDC authentication ==="

: "${AWS_REGION:?AWS_REGION is required}"
: "${AWS_ROLE_ARN:?AWS_ROLE_ARN is required}"
: "${BITBUCKET_STEP_OIDC_TOKEN:?BITBUCKET_STEP_OIDC_TOKEN is required}"

export AWS_DEFAULT_REGION="${AWS_REGION}"

AWS_WEB_IDENTITY_TOKEN_FILE="${BITBUCKET_CLONE_DIR}/web-identity-token"

printf '%s' "${BITBUCKET_STEP_OIDC_TOKEN}" \
  > "${AWS_WEB_IDENTITY_TOKEN_FILE}"

export AWS_WEB_IDENTITY_TOKEN_FILE

echo "Verifying AWS identity..."
aws sts get-caller-identity

echo "AWS authentication successful."
