#!/usr/bin/env bash
# DEV application delivery using the pinned shared tools, without migrations.
set -euo pipefail
cd "${BITBUCKET_CLONE_DIR:-$(git rev-parse --show-toplevel)}"
export PIPELINE_ROOT="${PWD}/.pipeline-tools"
CI_DIR="${PIPELINE_ROOT}/ci"
set -a
source ci/service.env
set +a

case "${1:-build}" in
  build)
    source "${CI_DIR}/common/ci.sh"
    bash "${CI_DIR}/ecr/publish-dev.sh"
    ;;
  existing)
    bash "${CI_DIR}/common/install-tools.sh" aws
    source "${CI_DIR}/common/aws-auth.sh"
    bash "${CI_DIR}/ecr/read-existing-image.sh"
    ;;
  *) echo "ERROR: Expected build or existing." >&2; exit 1 ;;
esac

echo "DEV database migrations are manual; run migrate-dev-db separately."
bash "${CI_DIR}/gitops/update-environment.sh" dev "${SERVICE_NAME}" reports/image-metadata.env
