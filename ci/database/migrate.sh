#!/usr/bin/env bash
# Usage: bash ci/database/migrate.sh validate|update-sql|update <full Git commit>
# Always deploy changelogs from the selected release, not the CI fix's checkout.
# Required deployment variables: DB_SECRET_ID and AWS_REGION.
# Fetch connection details from AWS Secrets Manager at runtime. Never print them.
# Database/history tables live in an existing database; this does not create
# databases or login roles and never automatically adopts an existing schema.
set -euo pipefail
set +x

ACTION="${1:?Liquibase action required}"
REVISION="${2:?full migration commit required}"
case "${ACTION}" in
  validate|update-sql|update) ;;
  *) echo "ERROR: Allowed actions: validate, update-sql, update."; exit 1 ;;
esac
[[ "${REVISION}" =~ ^[0-9a-f]{40}$ ]] || { echo "ERROR: Migration commit must be a full SHA."; exit 1; }
: "${DB_SECRET_ID:?Set the deployment database secret name or ARN}"
: "${AWS_REGION:?Set the AWS region containing the database secret}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/runtime.sh"
REPO_ROOT="$(git rev-parse --show-toplevel)"
cd "${REPO_ROOT}"
if ! git cat-file -e "${REVISION}^{commit}" 2>/dev/null; then
  git fetch --no-tags origin "${REVISION}"
fi
# Fail closed for older images without changelogs. Never fall back to latest main.
if ! git cat-file -e "${REVISION}:database/changelog.yaml" 2>/dev/null; then
  echo "ERROR: Release ${REVISION} has no Liquibase changelog. Use a release containing database/."
  exit 1
fi

# Bitbucket's Docker service permits bind mounts under the checkout directory.
WORK_DIR="$(mktemp -d "${REPO_ROOT}/.liquibase-work.XXXXXX")"
trap 'rm -rf "${WORK_DIR}"' EXIT
chmod 755 "${WORK_DIR}"
git archive "${REVISION}" database | tar -x -C "${WORK_DIR}"
chmod -R a+rX "${WORK_DIR}/database"
source "${SCRIPT_DIR}/load-db-secret.sh"
export LIQUIBASE_COMMAND_URL LIQUIBASE_COMMAND_USERNAME LIQUIBASE_COMMAND_PASSWORD

echo "Liquibase ${ACTION}: migration commit ${REVISION}"
run_liquibase() {
  docker run --rm \
    --volume "${WORK_DIR}/database:/liquibase/changelog:ro" \
    --env LIQUIBASE_COMMAND_URL --env LIQUIBASE_COMMAND_USERNAME --env LIQUIBASE_COMMAND_PASSWORD \
    "${LIQUIBASE_IMAGE}" --search-path=/liquibase/changelog \
    --changelog-file=changelog.yaml --liquibase-schema-name=public "$1"
}
# Validate syntax/checksums before any update. An error stops GitOps deployment.
run_liquibase validate
if [[ "${ACTION}" != "validate" ]]; then
  run_liquibase "${ACTION}"
fi
