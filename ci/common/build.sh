#!/usr/bin/env bash
set -euo pipefail

SOLUTION="ApertureFoundation.sln"

echo "=== Building Aperture Foundation ==="

dotnet build "${SOLUTION}" \
  --configuration Release \
  --no-restore

echo "Build completed successfully."
