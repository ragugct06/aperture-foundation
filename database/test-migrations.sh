#!/usr/bin/env bash
# Sourced by the shared PostgreSQL test runner; sql and run_liquibase are provided.
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
