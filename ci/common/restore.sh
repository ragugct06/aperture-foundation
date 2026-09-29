#!/usr/bin/env bash
set -euo pipefail

SOLUTION="ApertureFoundation.sln"

echo "=== Restoring NuGet packages ==="

dotnet restore "${SOLUTION}"

echo "Restore completed successfully."
