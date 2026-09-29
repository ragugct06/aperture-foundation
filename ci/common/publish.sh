#!/usr/bin/env bash
set -euo pipefail

PROJECT="Aperture.Entitlements.Api/Aperture.Entitlements.Api.csproj"
OUTPUT_DIR="app/publish"

echo "=== Publishing Aperture Foundation ==="

rm -rf "${OUTPUT_DIR}"
mkdir -p "${OUTPUT_DIR}"

dotnet publish "${PROJECT}" \
  --configuration Release \
  --no-build \
  --no-restore \
  --output "${OUTPUT_DIR}" \
  /p:UseAppHost=false

echo "Publish completed successfully."
