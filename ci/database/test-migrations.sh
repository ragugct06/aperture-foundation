#!/usr/bin/env bash
# Real PostgreSQL smoke test, isolated from deployment credentials/databases.
# Validates fresh install, repeat updates, rollback, and reapplication.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/runtime.sh"
REPO_ROOT="$(git rev-parse --show-toplevel)"
TEST_NAME="aperture-liquibase-${BITBUCKET_BUILD_NUMBER:-local}-$$"
cleanup() {
  docker rm -f "${TEST_NAME}" >/dev/null 2>&1 || true
  docker network rm "${TEST_NAME}" >/dev/null 2>&1 || true
}
trap cleanup EXIT

docker network create "${TEST_NAME}" >/dev/null
docker run --detach --name "${TEST_NAME}" --network "${TEST_NAME}" \
  --env POSTGRES_DB=liquibase_test --env POSTGRES_USER=migrator \
  --env POSTGRES_PASSWORD=local-test-only postgres:17.6-alpine >/dev/null
READY=false
for attempt in {1..30}; do
  if docker exec "${TEST_NAME}" pg_isready -U migrator -d liquibase_test >/dev/null 2>&1; then
    READY=true
    break
  fi
  sleep 2
done
[[ "${READY}" == true ]] || { echo "ERROR: Test PostgreSQL did not start."; exit 1; }
run_liquibase() {
  docker run --rm --network "${TEST_NAME}" \
    --volume "${REPO_ROOT}/database:/liquibase/changelog:ro" \
    --env "LIQUIBASE_COMMAND_URL=jdbc:postgresql://${TEST_NAME}:5432/liquibase_test" \
    --env LIQUIBASE_COMMAND_USERNAME=migrator --env LIQUIBASE_COMMAND_PASSWORD=local-test-only \
    "${LIQUIBASE_IMAGE}" --search-path=/liquibase/changelog \
    --changelog-file=changelog.yaml --liquibase-schema-name=public "$@"
}
run_liquibase validate
run_liquibase update
sql() { docker exec "${TEST_NAME}" psql -U migrator -d liquibase_test -At -v ON_ERROR_STOP=1 -c "$1"; }
BEFORE="$(sql 'SELECT count(*) FROM public.databasechangelog')"
run_liquibase update
[[ "$(sql 'SELECT count(*) FROM public.databasechangelog')" == "${BEFORE}" ]]
[[ "$(sql "SELECT count(*) FROM information_schema.tables WHERE table_schema='entitlement' AND table_name IN ('app_user','app_role','role_assignment','entitlement_outbox','user_credential')")" == 5 ]]
[[ "$(sql 'SELECT count(*) FROM entitlement.app_role')" -ge 4 ]]
# Roll back seeds independently and confirm unrelated roles survive.
sql "INSERT INTO entitlement.app_role (role_key, description) VALUES ('RollbackTest', 'Unrelated role')" >/dev/null
run_liquibase rollback-count --count=1
[[ "$(sql "SELECT count(*) FROM entitlement.app_role WHERE role_key IN ('Admin','ClaimsSpecialist','ProgramManager','CashPosting')")" == 0 ]]
[[ "$(sql "SELECT count(*) FROM entitlement.app_role WHERE role_key='RollbackTest'")" == 1 ]]
run_liquibase rollback-count --count=2
[[ "$(sql "SELECT count(*) FROM information_schema.tables WHERE table_schema='entitlement'")" == 0 ]]
[[ "$(sql 'SELECT count(*) FROM public.databasechangelog')" == 0 ]]
[[ "$(sql "SELECT count(*) FROM information_schema.schemata WHERE schema_name='entitlement'")" == 1 ]]
run_liquibase update
[[ "$(sql "SELECT count(*) FROM information_schema.tables WHERE table_schema='entitlement' AND table_name IN ('app_user','app_role','role_assignment','entitlement_outbox','user_credential')")" == 5 ]]
[[ "$(sql 'SELECT count(*) FROM entitlement.app_role')" == 4 ]]
[[ "$(sql 'SELECT count(*) FROM public.databasechangelog')" == "${BEFORE}" ]]
[[ "$(sql 'SELECT count(*) FROM public.databasechangeloglock WHERE locked')" == 0 ]]
echo "Liquibase PostgreSQL integration checks passed."
