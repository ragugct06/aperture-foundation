#!/usr/bin/env bash
# Sourced by the deployment and integration-test scripts. Liquibase 4.33 ships
# the PostgreSQL JDBC driver; moving to 5.x requires packaging that driver too.
LIQUIBASE_IMAGE="liquibase/liquibase:4.33.0"
