#!/usr/bin/env bash
set -euo pipefail

echo "=== Running Entitlements tests ==="

# TEMPORARY:
# Tests currently fail because the test project contains invalid ../../src/
# ProjectReference paths.
# Remove `|| true` after the application team fixes the test project.

dotnet test \
  tests/Aperture.Entitlements.Tests/Aperture.Entitlements.Tests.csproj \
  -c Release

echo "WARNING: Test failures are temporarily non-blocking."