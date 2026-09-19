#!/usr/bin/env bash
set -euo pipefail

echo "=== Building Aperture Foundation ==="

dotnet build ApertureFoundation.sln \
  -c Release \
  --no-restore