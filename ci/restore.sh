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

echo "=== Restoring NuGet packages ==="

dotnet restore ApertureFoundation.sln