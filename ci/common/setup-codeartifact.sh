#!/usr/bin/env bash
set -euo pipefail

echo "=== Configuring AWS CodeArtifact ==="

: "${AWS_REGION:?AWS_REGION is required}"
: "${CODEARTIFACT_DOMAIN:?CODEARTIFACT_DOMAIN is required}"
: "${CODEARTIFACT_DOMAIN_OWNER:?CODEARTIFACT_DOMAIN_OWNER is required}"
: "${CODEARTIFACT_REPOSITORY:?CODEARTIFACT_REPOSITORY is required}"

CODEARTIFACT_TOKEN="$(
  aws codeartifact get-authorization-token \
    --domain "${CODEARTIFACT_DOMAIN}" \
    --domain-owner "${CODEARTIFACT_DOMAIN_OWNER}" \
    --region "${AWS_REGION}" \
    --query authorizationToken \
    --output text
)"

export CODEARTIFACT_TOKEN

CODEARTIFACT_REPOSITORY_URL="$(
  aws codeartifact get-repository-endpoint \
    --domain "${CODEARTIFACT_DOMAIN}" \
    --domain-owner "${CODEARTIFACT_DOMAIN_OWNER}" \
    --repository "${CODEARTIFACT_REPOSITORY}" \
    --format nuget \
    --region "${AWS_REGION}" \
    --query repositoryEndpoint \
    --output text
)"

CODEARTIFACT_REPOSITORY_URL="${CODEARTIFACT_REPOSITORY_URL%/}/v3/index.json"

if dotnet nuget list source \
  --configfile nuget.config \
  | grep -q "aperture-codeartifact"; then

  dotnet nuget update source aperture-codeartifact \
    --source "${CODEARTIFACT_REPOSITORY_URL}" \
    --username aws \
    --password "${CODEARTIFACT_TOKEN}" \
    --store-password-in-clear-text \
    --configfile nuget.config
else
  dotnet nuget add source "${CODEARTIFACT_REPOSITORY_URL}" \
    --name aperture-codeartifact \
    --username aws \
    --password "${CODEARTIFACT_TOKEN}" \
    --store-password-in-clear-text \
    --configfile nuget.config
fi

dotnet nuget disable source local-sdk \
  --configfile nuget.config \
  2>/dev/null || true

dotnet nuget enable source aperture-codeartifact \
  --configfile nuget.config

echo "CodeArtifact configured successfully."
