#!/usr/bin/env bash
set -euo pipefail

echo "=== Configuring AWS OIDC authentication ==="

: "${AWS_ROLE_ARN:?AWS_ROLE_ARN is required}"
: "${AWS_REGION:?AWS_REGION is required}"
: "${BITBUCKET_STEP_OIDC_TOKEN:?BITBUCKET_STEP_OIDC_TOKEN is required}"

CREDS="$(
  aws sts assume-role-with-web-identity \
    --role-arn "${AWS_ROLE_ARN}" \
    --role-session-name "bitbucket-${BITBUCKET_BUILD_NUMBER}" \
    --web-identity-token "${BITBUCKET_STEP_OIDC_TOKEN}" \
    --duration-seconds 3600 \
    --query 'Credentials.[AccessKeyId,SecretAccessKey,SessionToken]' \
    --output text
)"

read -r AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN <<< "${CREDS}"

export AWS_ACCESS_KEY_ID
export AWS_SECRET_ACCESS_KEY
export AWS_SESSION_TOKEN
export AWS_DEFAULT_REGION="${AWS_REGION}"

echo "Verifying assumed AWS identity..."
aws sts get-caller-identity

echo "AWS OIDC authentication successful."
