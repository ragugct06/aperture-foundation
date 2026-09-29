#!/usr/bin/env bash
set -euo pipefail

echo "========================================="
echo " Running Aperture Foundation CI"
echo "========================================="

./ci/common/install-tools.sh

source ./ci/common/aws-auth.sh
source ./ci/common/setup-codeartifact.sh

./ci/common/restore.sh
./ci/common/build.sh

# TEMPORARY:
# Re-enable after the application team aligns the test project with the solution.
# ./ci/common/test.sh

./ci/common/publish.sh
./ci/common/docker-build.sh
./ci/common/image-scan.sh

echo
echo "Foundation CI completed successfully."
