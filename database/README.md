# Database migrations

Liquibase owns schema changes; EF Core continues to provide application data access.
The DEV and QA databases are empty/new, so the initial changesets create the schema
normally. Do not run `changelog-sync`, EF database updates, or the legacy schema/seed
scripts alongside this changelog. Historical EF migrations remain for reference.

## One-time environment setup

1. Provision the PostgreSQL database and a dedicated migration login in each
   environment. Database creation and login passwords are operational setup, not
   migrations. The migration login must own the objects it creates and have
   `CONNECT` and `CREATE` on the database, plus `USAGE, CREATE` on `public` for
   Liquibase's history tables. Use the same owner for subsequent migrations;
   granting table privileges alone does not grant permission to alter tables.
2. Configure these Bitbucket **deployment variables separately for DEV, QA (QE), UAT, and PROD**:

   | Variable | Example / purpose |
   | --- | --- |
   | `DB_SECRET_ID` | AWS Secrets Manager secret name or ARN for this environment |
   | `AWS_REGION` | Region containing the secret |
   | `AWS_ROLE_ARN` | Role assumed through Bitbucket OIDC |
   | `DB_SSLMODE` | Optional PostgreSQL TLS mode; defaults to `require` |

   Store the connection values in a JSON `SecretString` with keys `host`, `database`,
   `username`, and `password`, plus optional `port` (defaults to 5432). The username
   must be the dedicated migration login from step 1. For different JSON key names,
   configure `DB_SECRET_HOST_KEY`, `DB_SECRET_DATABASE_KEY`,
   `DB_SECRET_USERNAME_KEY`, `DB_SECRET_PASSWORD_KEY`, and/or `DB_SECRET_PORT_KEY`.
   Values are top-level keys; no database connection values belong in the changelog.

   The runner fetches the current secret during every invocation, constructs the
   PostgreSQL JDBC URL, and passes credentials to Liquibase through environment
   variables. It does not write the secret to disk or print it. Any previously set
   `LIQUIBASE_COMMAND_*` connection variables are replaced with the fetched values.
   Failed retrieval or invalid fields stop the migration before Liquibase runs.

   Grant the OIDC role `secretsmanager:GetSecretValue` on the environment's secret
   and `kms:Decrypt` on its key if using a customer-managed KMS key. The runner
   needs network access to AWS Secrets Manager, and its Docker containers need
   access to PostgreSQL. Configure TLS for your database; `verify-full` also needs
   the appropriate CA trust configured in the Liquibase container.
3. Commit this integration, then run `migrate-dev-db` from that commit. For QE,
   create a beta tag on the tested main commit and run `migrate-qe-db` with
   that `RELEASE_TAG`. Use RC and final tags for UAT and production. An application
   delivery from a commit containing this integration can also perform the initial update.
4. Grant the application's separate runtime login access to the new schema and
   tables before starting the application. For example, as the migration owner,
   replacing `aperture_runtime` with the provisioned runtime role:

   ```sql
   GRANT USAGE ON SCHEMA entitlement TO aperture_runtime;
   GRANT SELECT, INSERT, UPDATE ON ALL TABLES IN SCHEMA entitlement TO aperture_runtime;
   ALTER DEFAULT PRIVILEGES IN SCHEMA entitlement
       GRANT SELECT, INSERT, UPDATE ON TABLES TO aperture_runtime;
   ```

   Run default-privilege configuration as the role that will create future tables.
   The runtime login should not own schema objects or use migration credentials.
   `scripts/002_database_roles.sql` is a provisioning reference; it does not create
   login credentials or substitute for object ownership.

The baseline creates five tables in `entitlement`: `app_user`, `app_role`,
`role_assignment`, `entitlement_outbox`, and `user_credential`. It seeds Admin,
ClaimsSpecialist, ProgramManager, and CashPosting roles, without creating users or
passwords. Liquibase tracks applied changes in `public.databasechangelog` and
serializes updates with `public.databasechangeloglock`. Existing application tables
cause initial creation to fail instead of being silently adopted.

## Delivery flow

- Normal DEV delivery publishes/resolves the image, applies the changelog from
  `BITBUCKET_COMMIT`, then updates GitOps. Failure prevents the GitOps update.
- Existing-image DEV delivery applies the changelog from `IMAGE_COMMIT`.
- QE, UAT, and production promotions resolve `RELEASE_TAG` to a commit on main,
  verify its existing image, apply its changelog, then update GitOps with that
  image digest. QE uses beta tags, UAT uses RC tags, and production uses final
  tags. QE maps to the existing `QA` deployment and `qa` GitOps directory.
- Database-only changes skip application builds. `migrate-dev-db` uses its pipeline
  commit and runs disposable PostgreSQL validation first. `migrate-qe-db`,
  `migrate-uat-db`, and `migrate-prod-db` use the selected release tag and run
  Liquibase validation/update against the configured target database. They do not
  require an image or update GitOps.
  Independently delivered database changes need their own promotion through all
  environments. Test their SQL against disposable PostgreSQL before tagging.
- Use immutable tags and promote the same tested commit from beta to RC to final.
  Release metadata in `reports/` records the tag, resolved commit, and target;
  application promotion also records the image repository and digest.

The runner extracts committed `database/` files using `git archive`. Uncommitted
edits and newer checkout files never enter release migrations. An older image
commit without `database/changelog.yaml` is rejected; build a new release that
contains the integration rather than substituting an unrelated changelog.

Migrations run while the previous application is still serving traffic. Use
backward-compatible additions and staged removals. Database updates and GitOps
merges are separate operations: if GitOps fails after a migration, fix the issue
and retry. Liquibase skips already applied changesets. Redeploying an older image
does not undo newer database changes. Automatic rollback is not configured;
review and deliver a corrective changeset for recovery.

The initial changesets include explicit Liquibase rollback statements for manual
recovery. Seed rollback deletes only the four seeded role keys and fails if role
assignments still reference them. Table rollback drops tables in dependency order,
including their data, indexes, and constraints. It preserves the `entitlement`
schema because it may have existed before the baseline.

`changelog.yaml` defines changesets and references plain SQL files in `changes/`
and `rollback/`. Both directions use `splitStatements: false`, allowing PostgreSQL
`DO $$ BEGIN ... END; $$;` and function bodies with internal semicolons. Liquibase
manages the transaction; do not add transaction-level `BEGIN` or `COMMIT` statements.

## Local commands and tests

Docker must be installed and running. The runtime image is pinned in
`ci/database/runtime.sh` to Liquibase 4.33.0, which includes the PostgreSQL JDBC
driver. Upgrading to Liquibase 5 requires explicit driver packaging; review the
[official Docker repository](https://github.com/liquibase/docker) before upgrading.

Run an isolated fresh install and repeat update against disposable PostgreSQL 17:

```sh
bash ci/database/test-migrations.sh
bash ci/common/validate-scripts.sh
```

The integration test uses working-tree changelogs and disposable credentials,
checks all five tables, role seeds, history stability, rollback and reapplication,
and lock release, then
removes its container and network. Relevant PR/main changes and the manual
migration/full-build pipelines run it in CI. It does not contact DEV or QA.

For an intentional operation against a configured database, authenticate your AWS
CLI (for example with your organization's SSO profile), export `DB_SECRET_ID` and
`AWS_REGION`, and install AWS CLI, `jq`, and Docker. Then run:

```sh
bash ci/database/migrate.sh validate "$(git rev-parse HEAD)"
bash ci/database/migrate.sh update-sql "$(git rev-parse HEAD)"
# Applies changes to the configured database:
bash ci/database/migrate.sh update "$(git rev-parse HEAD)"
```

`validate` checks changelog structure/checksums, not PostgreSQL execution. Review
`update-sql` output before an operational update; generated SQL can contain data
from changesets. The disposable PostgreSQL test exercises SQL execution.

## Adding a migration

1. Add a numbered file, for example `changes/004-add-user-column.sql`:

   ```sql
   ALTER TABLE entitlement.app_user ADD COLUMN display_name varchar(200);
   ```
2. Add its rollback file, `rollback/004-add-user-column.sql`:

   ```sql
   ALTER TABLE entitlement.app_user DROP COLUMN display_name;
   ```

   Append a `changeSet` to `database/changelog.yaml`, following the existing entries:

   ```yaml
   - changeSet:
       id: 004-add-user-column
       author: aperture
       logicalFilePath: changes/004-add-user-column.sql
       dbms: postgresql
       changes:
         - sqlFile:
             path: changes/004-add-user-column.sql
             relativeToChangelogFile: true
             splitStatements: false
       rollback:
         - sqlFile:
             path: rollback/004-add-user-column.sql
             relativeToChangelogFile: true
             splitStatements: false
   ```

   Keep existing order, changeset identities, and file paths stable. SQL files are
   plain SQL; define rollback references in YAML, not `--rollback` comments.
3. Never edit an executed changeset or clear checksums to hide an edit. Add a new
   changeset. Avoid psql directives, explicit transaction wrappers, and unreviewed
   destructive SQL.
4. Run both test commands above and review compatibility with the application.
   Commit the changelog before using the release-pinned migration runner.
