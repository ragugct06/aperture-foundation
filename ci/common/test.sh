#!/usr/bin/env bash
set -euo pipefail

TEST_PROJECT="tests/Aperture.Entitlements.Tests/Aperture.Entitlements.Tests.csproj"

echo "=== Running Foundation tests ==="

dotnet test "${TEST_PROJECT}" \
  --configuration Release \
  --no-restore

echo "Tests completed successfully."
